#!/usr/bin/env python3
# streams.py: split the game's sources into their emissions (docs/memory-map.md,
# "The sources and their emissions"). Run by the Makefile from the repository's
# root.
#
# Disc Elite is two programs, each with its own source in the original's
# order: the flight code (elite-source-flight.asm) and the docked code
# (elite-source-docked.asm). The port puts each program in two sideways RAM
# banks, its home bank (paged whenever the program's code runs) and its cold
# bank (paged only for far calls), and each routine or table sits once, at
# its original place in its source, with the area it lives in as a field of
# its header:
#
#   \       Name: TT219
#   ...
#   \       Area: cold
#
# No Area field: the home bank, from S% at &8000 in the source's order.
# "Area: cold": the cold bank, from &8000 in the source's order.
# "Area: blueprints": the home bank's blueprint slot (the docked program's
# own ship blueprints, which the flight program loads from a D.MOx file
# instead), assembled at BPSLOT%. A block runs from its header to the next
# header (or to a separator line of stars, which starts an untagged block:
# the original's PRINT and SAVE sections).
#
# BeebAsm assembles a file once and has one location counter, and the two
# banks share the addresses &8000-&BFFF, so each area's blocks are assembled
# from a copy of the source of their own: 3-assembled-output/elite-<program>-
# <area>.asm is the program's source with every line outside that area's
# blocks blanked (so that line numbers stay the source's).
# elite-layout-<program>.asm INCLUDEs the copies one after the other, each at
# its own address, so every label is defined exactly once and every block is
# assembled once.
#
# Each emission is the original in its order, with a stub wherever a routine
# lives on the other side. The hot side is the home bank (with its blueprint
# slot); the cold side the cold bank. In a hot copy, the line that defines a
# cold label X that the hot side refers to holds X's stub, under X's own name:
#
#   .TT22 JSR farC : EQUW TT22_C        (TT22_C: the body, in the cold copy)
#
# and in the cold copy, the line that defines a hot label H that cold code
# calls or jumps to holds H's stub, under the name the cold copy's calls are
# renamed to:
#
#   .xh_TT26 JSR farH : EQUW TT26
#
# (farCj and jh_ / farHj for the targets that never return, NORETURN below).
# A cold block's stubs go in the copy of the hot area of the nearest block
# before it that is not cold, so the stubs sit where the routine was carved
# out of that emission, and a block that falls through into a routine of the
# other side falls into its stub: the stub calls the body and returns to the
# falling routine's caller with the caller's bank back, which is what the
# fall-through did in the original (a jump stub, for a target that never
# returns, just jumps).
#
# The text tokens (elite-text-tokens.asm, the original's WORDS file at &0400)
# are split the same way: its blocks tagged "Area: cold" (the recursive token
# table QQ18 and the macros that build it) are assembled into each program's
# cold bank (3-assembled-output/elite-tokens-cold.asm), and those tagged
# "Area: resident" (the sine and arctan tables SNE and ACT, which stay at
# &07C0) into the loader's resident block (elite-tokens-resident.asm). Its
# untagged blocks (the original file's configuration and SAVE) are not part
# of the port's build.
#
# Checks (exit status 1 on failure):
#   * every block's IF ... ENDIF nesting is balanced (a blanked block must not
#     take half of a conditional with it);
#   * a block whose code can fall through its end is followed, in the source,
#     by a block of the same area (each area is assembled in the source's
#     order, so a block falls into the next block of its own area), or by a
#     block of the other side whose first statement is its entry label, so
#     that the falling block falls into that label's stub; any other
#     fall-through across areas (into or out of the blueprint slot) is an
#     error;
#   * a block that ends with the original's skip trick (EQUB &2C or &24, which
#     makes the next instruction the operand of a BIT) is followed by a block
#     of its own area;
#   * every stub's line is blank in its copy, and every target is defined in
#     the program's source (a stub has a place only there).
import os, re, sys

SRCDIR = "1-source-files/main-sources/"
OUTDIR = "3-assembled-output/"
PROGS = ("flight", "docked")
AREAS = ("home", "blueprints", "cold")
HOT = ("home", "blueprints")
TAGS = {"cold": "cold", "blueprints": "blueprints"}
TOKENS = SRCDIR + "elite-text-tokens.asm"
TOKAREAS = ("cold", "resident")
TOKTAGS = {"cold": "cold", "resident": "resident"}
STAR = re.compile(r"^\\ \*{70,}\s*$")
AREA = re.compile(r"^\\       Area: (.*)$")
NOFALL = set("RTS RTI JMP BRK".split())

# NORETURN: the targets that never return to their caller, so that their
# stubs jump (farCj, farHj) and leave no far-call frame on the stack: the
# routines that reset the stack (TT170, BR1, DEATH2, BEGIN ...) or loop
# for ever
NORETURN = {
    "flight": {"DEATH2", "DEATH", "RSHIPS", "INBAY", "DOENTRY", "FRCE", "TT100", "MLOOP", "GOIN"},
    "docked": {"DEATH2", "TT170", "BR1", "BAY", "BEGIN", "SCRAM", "DOENTRY", "DOBEGIN", "FRCE", "TT100", "MLOOP",
               "TT110", "MEBRK", "BRBR"},
}


def code_part(line):
    out, q = "", False
    for ch in line:
        if ch == '"':
            q = not q
        if ch == "\\" and not q:
            break
        out += ch
    return out.strip()


def blocks(lines, tags, path, default="home"):
    """[(start, end, name, area)]: a block starts at a header (a line of
    stars followed by a lone backslash) or at a separator line of stars"""
    out = [[0, None, None, default]]
    inh = False
    for i, l in enumerate(lines):
        if STAR.match(l):
            if inh:
                inh = False
                if (i + 2 < len(lines) and lines[i + 1].rstrip() == "\\"
                        and lines[i + 2].startswith("\\       Name:")):
                    out.append([i, None, None, default])     # (a banner's closing line
                    inh = True                               # opens the next header)
            elif i + 1 < len(lines) and lines[i + 1].rstrip() == "\\":
                out.append([i, None, None, default])
                inh = True
            else:
                out.append([i, None, None, default])
        elif inh:
            if not l.startswith("\\"):
                sys.exit("%s:%d: a header that is not closed" % (path, i + 1))
            m = re.match(r"^\\       Name: (.*)$", l)
            if m:
                out[-1][2] = m.group(1).strip()
            m = AREA.match(l)
            if m:
                t = m.group(1).strip()
                if t not in tags:
                    sys.exit("%s:%d: unknown area %r" % (path, i + 1, t))
                out[-1][3] = tags[t]
    for k, b in enumerate(out):
        b[1] = out[k + 1][0] if k + 1 < len(out) else len(lines)
    return [tuple(b) for b in out]


# the build options' flags (elite-build-options.asm, as the Makefile writes
# them for the port), for the checks' view of conditional assembly
FLAGS = {"_STH_DISC": True, "_IB_DISC": False, "_SRAM_DISC": False, "_MATCH_ORIGINAL_BINARIES": True,
         "_REMOVE_CHECKSUMS": True, "_MAX_COMMANDER": False, "_INTERLACE_FIX": False,
         "_STH_DISC OR _IB_DISC": True, "_REMOVE_CHECKSUMS OR _INTERLACE_FIX": True}


def active_lines(lines):
    """for each line, False if it is in a branch of IF ... ENDIF that the
    flags rule out (a condition on anything else counts as either way)"""
    out, stack = [], []          # stack: [this branch on, a branch taken, known]
    for l in lines:
        c = code_part(l)
        m = re.match(r"^(IF|ELIF|ELSE|ENDIF)\b\s*(.*)$", c, re.I)
        on = all(st[0] for st in stack)
        if not m:
            out.append(on)
            continue
        kw, cond = m.group(1).upper(), m.group(2).strip()
        v = FLAGS.get(cond.replace("NOT(", "").rstrip(")")) if cond else None
        if v is not None and cond.startswith("NOT("):
            v = not v
        if kw == "IF":
            stack.append([True if v is None else v, bool(v), v is not None])
        elif kw in ("ELIF", "ELSE") and stack:
            st = stack[-1]
            if not st[2]:
                st[0] = True
            elif kw == "ELSE":
                st[0] = not st[1]
            else:
                st[0] = (not st[1]) and (True if v is None else v)
                st[1] = st[1] or st[0]
                st[2] = st[2] and v is not None
        elif kw == "ENDIF" and stack:
            stack.pop()
        out.append(False)
    return out


ACTIVE = []


def last_statement(lines, s, e):
    """the last statement of lines[s:e] that is assembled (None if none),
    passing over the lines of conditional assembly (IF, ELIF, ELSE, ENDIF)
    and the branches the build's flags rule out"""
    for i in range(e - 1, s - 1, -1):
        if ACTIVE and not ACTIVE[i]:
            continue
        c = code_part(lines[i])
        if c and not re.match(r"^(IF|ELIF|ELSE|ENDIF)\b", c, re.I):
            return c if c.upper().startswith("EQU") else c.split(" : ")[-1].strip()
    return None


def entry_label(lines, s, e, macros):
    """the label at the start of lines[s:e] (its first statement that is
    assembled), or None if the block starts with anything else"""
    for i in range(s, e):
        if ACTIVE and not ACTIVE[i]:
            continue
        c = code_part(lines[i])
        if not c or re.match(r"^(IF|ELIF|ELSE|ENDIF)\b", c, re.I) or not assembles(c, macros):
            continue
        m = re.match(r"^\.([A-Za-z_][A-Za-z0-9_]*)", c)
        return m.group(1) if m else None
    return None


def assembles(c, macros):
    """whether the statement c assembles bytes or moves the address (an
    instruction, data, a label, ORG ...), not just comments, PRINTs, SAVEs,
    ASSERTs or constants"""
    if not c or re.match(r"^(PRINT|SAVE|ASSERT|IF|ELIF|ELSE|ENDIF|MACRO|ENDMACRO|GUARD|CPU)\b", c, re.I):
        return False
    return not re.match(r"^[A-Za-z_][\w%]*\s*=", c)


def falls_through(stmt, macros):
    if stmt is None:
        return False
    w = stmt.split()
    if not w:
        return False
    op = w[0].upper()
    if w[0] in macros:
        return False                   # (a macro: the original's data macros)
    if op in NOFALL:
        return False
    if re.match(r"^(EQU[BWDS]|SKIP|INCBIN|FOR|NEXT|PRINT|SAVE|ASSERT|ORG|CLEAR|GUARD|MACRO|ENDMACRO|INCLUDE|CPU|COPYBLOCK|ALIGN)\b", op):
        return False                   # (data and directives: nothing to fall from)
    if re.match(r"^[A-Za-z_][\w%]*\s*=", stmt) or stmt.startswith("."):
        return False                   # (a constant, or a label alone)
    return True


# ---------------------------------------------------------------- the glue
#
# The sources use the original's names throughout. A program's cold copy is
# assembled with each cold label X renamed X_C (its definition and every
# reference in the cold copy), and with each JSR or JMP from cold code to a
# hot label H going through a stub, xh_H (JSR farH: call H with the home bank
# paged in, then page the cold bank back) or, for the targets in NORETURN,
# jh_H (JSR farHj: jump to H). Every other file keeps the names as they are,
# so a reference from outside the cold bank to a cold label X reaches its
# stub, .X (JSR farC : EQUW X_C, or farCj for the targets in NORETURN). Each
# stub is at its target's place in the other side's copy (above); there is
# one for each cold label that a file outside the cold bank refers to and for
# each hot label that cold code calls or jumps to, and one for each routine
# that a block of the other side falls into. Labels that are one place
# (defined one after another, with nothing assembled between them) share a
# stub: the earlier ones are bare labels at their lines. Labels ending in %
# keep their names. Cold code that needs a stub's address (a jump table)
# names the stub itself, xh_H.

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*%?")


def split_code(line):
    """(code, comment): the line up to its comment, and the comment"""
    q = False
    for k, ch in enumerate(line):
        if ch == '"':
            q = not q
        elif ch == "\\" and not q:
            return line[:k], line[k:]
    return line, ""


def tokens(code):
    """(start, end, name) of the identifiers in code, outside strings and
    character literals, and not hex (&), binary (%) or decimal digits"""
    out, k, n = [], 0, len(code)
    while k < n:
        ch = code[k]
        if ch == '"':
            k = code.find('"', k + 1)
            k = n if k < 0 else k + 1
        elif ch == "'" and k + 2 < n and code[k + 2] == "'":
            k += 3
        elif ch in "&%" or ch.isdigit():
            k += 1
            while k < n and (code[k].isalnum() or code[k] == "_"):
                k += 1
        else:
            m = IDENT.match(code, k)
            if m:
                out.append((m.start(), m.end(), m.group(0)))
                k = m.end()
            else:
                k += 1
    return out


def mnemonic(st, a):
    """whether the identifier at st[a:] is the statement's instruction or
    directive (its first word, after any label definitions), not an operand:
    a label may share its name with a mnemonic (SCAN's .RTS)"""
    m = re.match(r"^(\s*\.[A-Za-z_][A-Za-z0-9_]*%?)*\s*", st)
    return a == m.end() and not st[:a].rstrip().endswith(".")


def defined(lines):
    """[(name, line)] of the labels the lines define (.name)"""
    out = []
    for i, l in enumerate(lines):
        code = split_code(l)[0]
        for st in code.split(":"):
            m = re.match(r"^\s*\.([A-Za-z_][A-Za-z0-9_]*%?)", st)
            if m:
                out.append((m.group(1), i))
    return out


def aliases(lines, macros):
    """{label: first label of its place}: labels defined one after another
    with nothing assembled between them are one place"""
    out, cur = {}, None
    for i, l in enumerate(lines):
        code = split_code(l)[0].strip()
        if not code:
            continue
        m = re.match(r"^\.([A-Za-z_][A-Za-z0-9_]*%?)\s*(.*)$", code)
        if m:
            cur = cur or m.group(1)
            out[m.group(1)] = cur
            if m.group(2).strip():
                cur = None
        elif assembles(code, macros):
            cur = None
    return out


def statements(code):
    """the statements of a line's code (split at colons outside strings)"""
    out, q, last = [], False, 0
    for k, ch in enumerate(code):
        if ch == '"':
            q = not q
        elif ch == ":" and not q:
            out.append((last, code[last:k]))
            last = k + 1
    out.append((last, code[last:]))
    return out


def read_file(path, seen=None):
    """a source file's lines, with the files it INCLUDEs from 1-source-files/main-sources/"""
    seen = seen if seen is not None else set()
    if path in seen or not os.path.exists(path):
        return []
    seen.add(path)
    lines = open(path, encoding="latin-1").read().split("\n")
    out = [(path, lines)]
    for l in lines:
        m = re.match(r'^\s*INCLUDE\s+"(1-source-files/main-sources/[^"]+)"', split_code(l)[0])
        if m:
            out += read_file(m.group(1), seen)
    return out


def glue(prog, src, copies, errors, lines, bl, falls):
    noreturn = NORETURN[prog]
    macros = set()
    for l in copies["home"]:
        m = re.match(r"^\s*MACRO\s+(\w+)", l)
        if m:
            macros.add(m.group(1))
    cold = {n for n, i in defined(copies["cold"]) if not n.endswith("%")}
    # the hot side's labels, with the files the hot blocks INCLUDE
    hotfiles = [(a, copies[a]) for a in HOT]
    for a in HOT:
        for l in copies[a]:
            m = re.match(r'^\s*INCLUDE\s+"(1-source-files/main-sources/[^"]+)"', split_code(l)[0])
            if m:
                hotfiles += read_file(m.group(1))
    hot = {}
    for f, ls in hotfiles:
        for n, i in defined(ls):
            hot.setdefault(n, f)
    for n in cold & set(hot):
        errors.append("%s: %s is defined in the cold bank and outside it" % (src, n))
    alias = {}
    for f, ls in hotfiles + [("cold", copies["cold"])]:
        alias.update(aliases(ls, macros))
    # the cold copy: X -> X_C, JSR/JMP H -> xh_H / jh_H
    outh = []                               # (stub name, target) in order
    seenh = {}
    cc = copies["cold"]
    act = active_lines(cc)
    for i, l in enumerate(cc):
        code, comment = split_code(l)
        if not code.strip():
            continue
        if not act[i]:                     # (a branch the build leaves out: the
            for a, b, name in reversed(tokens(code)):   # names, but no stubs)
                if name in cold and not mnemonic(code, a):
                    code = code[:a] + name + "_C" + code[b:]
            m = re.match(r"^(\s*(?:JSR|JMP)\s+)([A-Za-z_]\w*)(.*)$", code, re.I)
            if m and m.group(2) in hot and m.group(2) not in cold:
                code = m.group(1) + ("jh_" if m.group(2) in noreturn else "xh_") + m.group(2) + m.group(3)
            cc[i] = code + comment
            continue
        new = ""
        pos = 0
        for off, st in statements(code):
            m = re.match(r"^(\s*)(JSR|JMP)(\s+)([A-Za-z_][A-Za-z0-9_]*%?)(.*)$", st, re.I)
            if m and m.group(4) in hot and m.group(4) not in cold:
                h = m.group(4)
                if m.group(5).strip():
                    errors.append("%s:%d: %s %s%s from the cold bank: a stub can only call a label"
                                  % (src, i + 1, m.group(2), h, m.group(5)))
                place = alias.get(h, h)
                kind = "jh_" if place in noreturn or h in noreturn else "xh_"
                stub = kind + h
                if stub not in seenh:
                    seenh[stub] = place
                    outh.append((stub, h, place, kind))
                new += code[pos:off] + m.group(1) + m.group(2) + m.group(3) + stub + m.group(5)
                pos = off + len(st)
                continue
            for a, b, name in tokens(st):
                if name in cold and not mnemonic(st, a):
                    new += code[pos:off + a] + name + "_C"
                    pos = off + b
                m2 = re.match(r"^(xh_|jh_)(.+)$", name)
                if m2 and m2.group(2) in hot and name not in seenh:
                    seenh[name] = alias.get(m2.group(2), m2.group(2))   # (a stub named in the
                    outh.append((name, m2.group(2), seenh[name], m2.group(1)))   # source: its address)
            new += code[pos:off + len(st)]
            pos = off + len(st)
        cc[i] = new + code[pos:] + comment
    # references to cold labels from outside the cold bank
    others = []
    for f in (SRCDIR + "elite-layout-%s.asm" % prog,):
        others += read_file(f)
    outc, seenc = [], set()
    elsewhere = {n for f, ls in others for n, i in defined(ls)}
    for f, ls in [(a, copies[a]) for a in HOT] + others:
        own = {n for n, i in defined(ls)}
        for l in ls:                       # (loop variables and macro parameters)
            m = re.match(r"^\s*(FOR|MACRO)\s+(.*)$", split_code(l)[0], re.I)
            if m:
                own.update(IDENT.findall(m.group(2).split(",")[0] if m.group(1).upper() == "FOR"
                                         else m.group(2)))
        for i, l in enumerate(ls):
            for a, b, name in tokens(split_code(l)[0]):
                if name not in cold or name in own:
                    continue
                if name in elsewhere:      # (another file's label of the same name)
                    if f in HOT:
                        errors.append("%s:%d: %s is a cold label and a label of another file"
                                      % (src, i + 1, name))
                    continue
                if name not in seenc:
                    seenc.add(name)
                    outc.append(name)
    # the stubs that the fall-through seams land on: a block that falls
    # through its end into a block of the other side falls into the stub at
    # that block's entry label
    for side, entry in falls:
        if side == "hot":                  # (hot code falls into a cold routine)
            if entry not in seenc:
                seenc.add(entry)
                outc.append(entry)
        else:                              # (cold code falls into a hot routine)
            place = alias.get(entry, entry)
            kind = "jh_" if place in noreturn or entry in noreturn else "xh_"
            if kind + entry not in seenh:
                seenh[kind + entry] = place
                outh.append((kind + entry, entry, place, kind))
    # where each label is defined in the source (its first line that the
    # build's flags assemble), and the area of that line's block
    barea = [None] * len(lines)
    for k, (s0, e0, name, area) in enumerate(bl):
        for i in range(s0, e0):
            barea[i] = k
    where = {}
    for n, i in defined(lines):
        if ACTIVE[i]:
            where.setdefault(n, i)

    def host(i):
        """the hot area whose emission holds the stubs at line i of a cold
        block: that of the nearest block before it, in the source, that is
        not cold and holds code, so that a block that falls through into the
        cold block falls into its stubs"""
        for k in range(barea[i] - 1, -1, -1):
            s0, e0, name, area = bl[k]
            if area == "cold":
                continue
            if any(ACTIVE[j] and assembles(code_part(lines[j]), macros) for j in range(s0, e0)):
                return area
        return "home"

    def place_stubs(groups, ok_area, side):
        """groups: [(far helper, [(stub label, target label)])], each group one
        place; each stub goes at the line of its target's definition, in the
        copy of the area that hosts it, and the labels of a place share the
        stub at the last of them"""
        n = 0
        for far, members in groups:
            at = []
            for stub, target in members:
                i = where.get(target)
                if i is None or bl[barea[i]][3] not in ok_area:
                    errors.append("%s: no place in the source for the stub %s (%s is not defined "
                                  "in the source's %s blocks)" % (src, stub, target, side))
                    continue
                at.append((i, stub, target))
            at.sort()
            for k, (i, stub, target) in enumerate(at):
                a = host(i) if side == "cold" else "cold"
                text = ".%s" % stub
                # (a label shares the next one's stub only if nothing is
                # assembled between them in this copy)
                if k == len(at) - 1 or any(assembles(code_part(copies[a][j]), macros)
                                           for j in range(i + 1, at[k + 1][0])):
                    text += " JSR %s : EQUW %s" % (far, target + "_C" if side == "cold" else target)
                    n += 1
                cur = copies[a][i]
                if (a, i) in placed:
                    copies[a][i] = cur + " : " + text      # (two stubs at one line)
                elif code_part(cur):
                    errors.append("%s:%d: the stub %s's line is not blank in the %s copy"
                                  % (src, i + 1, stub, a))
                else:
                    copies[a][i] = text
                    placed.add((a, i))
        return n

    placed = set()

    # the stubs into the cold bank, in the hot copies at the cold labels' places
    groups, done = [], {}
    for name in outc:
        place = alias.get(name, name)
        far = "farCj" if place in noreturn or name in noreturn else "farC"
        if place not in done:
            done[place] = len(groups)
            groups.append((far, []))
        elif groups[done[place]][0] != far:
            errors.append("%s: %s and %s are one place but not both NORETURN" % (src, name, place))
        groups[done[place]][1].append((name, name))
    nc = place_stubs(groups, ("cold",), "cold")
    # the stubs out of the cold bank, in the cold copy at the hot labels' places
    groups, done = [], {}
    for stub, h, place, kind in outh:
        key = (kind, place)
        if key not in done:
            done[key] = len(groups)
            groups.append(("farHj" if kind == "jh_" else "farH", []))
        groups[done[key]][1].append((stub, h))
    nh = place_stubs(groups, HOT, "hot")
    return nc, nh


def program(prog, errors):
    src = SRCDIR + "elite-source-%s.asm" % prog
    lines = open(src, encoding="latin-1").read().split("\n")
    bl = blocks(lines, TAGS, src)
    ACTIVE[:] = active_lines(lines)
    macros = set(m.group(1) for m in (re.match(r"^\s*MACRO\s+(\w+)", l) for l in lines) if m)
    for s, e, name, area in bl:
        depth = 0
        for i in range(s, e):
            c = code_part(lines[i]).upper()
            if re.match(r"^IF\b", c):
                depth += 1
            elif re.match(r"^ENDIF\b", c):
                depth -= 1
        if depth and area != "home":
            errors.append("%s:%d: %s: IF ... ENDIF not balanced in an area's block" % (src, s + 1, name))
    # fall-through: each block that can fall through its end must be followed,
    # in the source, by a block of its own area that holds code, or by a block
    # of the other side (hot: the home bank; cold) whose first statement is
    # its entry label, as that label's stub is then the next thing in the
    # falling block's emission
    falls = []
    for k, (s, e, name, area) in enumerate(bl):
        st = last_statement(lines, s, e)
        if st and re.match(r"^EQUB\s+&(2C|24)\b", st, re.I):
            # (the original's skip trick: an EQUB &2C or &24 makes the next
            # instruction the operand of a BIT, so the block falls into the
            # instruction after it, which must be the next block's, in the
            # same area: a stub cannot be skipped into)
            for s2, e2, name2, area2 in bl[k + 1:]:
                if any(ACTIVE[i] and assembles(code_part(lines[i]), macros) for i in range(s2, e2)):
                    if area2 != area:
                        errors.append("%s:%d: %s (%s) skips into %s (%s) with %s: they must be in one area"
                                      % (src, e, name, area, name2, area2, st))
                    break
            continue
        if not falls_through(st, macros):
            continue
        for s2, e2, name2, area2 in bl[k + 1:]:
            if not any(ACTIVE[i] and assembles(code_part(lines[i]), macros) for i in range(s2, e2)):
                continue               # (comments, PRINTs and constants only)
            if any(re.match(r"^(ORG|CLEAR|SKIPTO)\b", code_part(lines[i]), re.I) for i in range(s2, e2)):
                errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s, which moves the address"
                              % (src, e, name, area, st, name2))
            elif area2 != area:
                entry = entry_label(lines, s2, e2, macros)
                side = "hot" if area == "home" and area2 == "cold" else \
                       "cold" if area == "cold" and area2 == "home" else None
                if side and entry:
                    falls.append((side, entry))
                else:
                    errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s (%s)%s"
                                  % (src, e, name, area, st, name2, area2,
                                     "" if side else ", and no stub of %s is in %s's emission" % (name2, area)))
            break
    copies = {}
    for a in AREAS:
        copies[a] = []
        for s, e, name, area in bl:
            copies[a] += [lines[i] if area == a else "" for i in range(s, e)]
    nstubs = glue(prog, src, copies, errors, lines, bl, falls)
    for a in AREAS:
        with open(OUTDIR + "elite-%s-%s.asm" % (prog, a), "w", encoding="latin-1") as f:
            f.write("\n".join(copies[a]))
    n = {a: sum(1 for b in bl if b[3] == a and b[2]) for a in AREAS}
    return "%s: %d blocks (%s), stubs %d into the cold bank, %d out of it" % (
        prog, len(bl), ", ".join("%s %d" % (a, n[a]) for a in AREAS), nstubs[0], nstubs[1])


def text_tokens(errors):
    """the text tokens' copies, one per area (TOKAREAS); untagged blocks go
    in neither"""
    lines = open(TOKENS, encoding="latin-1").read().split("\n")
    bl = blocks(lines, TOKTAGS, TOKENS, default="none")
    for s, e, name, area in bl:
        depth = 0
        for i in range(s, e):
            c = code_part(lines[i]).upper()
            depth += bool(re.match(r"^IF\b", c)) - bool(re.match(r"^ENDIF\b", c))
        if depth and area != "none":
            errors.append("%s:%d: %s: IF ... ENDIF not balanced in an area's block" % (TOKENS, s + 1, name))
    for a in TOKAREAS:
        out = []
        for s, e, name, area in bl:
            out += [lines[i] if area == a else "" for i in range(s, e)]
        with open(OUTDIR + "elite-tokens-%s.asm" % a, "w", encoding="latin-1") as f:
            f.write("\n".join(out))
    return "tokens: %s" % ", ".join("%s %d" % (a, sum(1 for b in bl if b[3] == a)) for a in TOKAREAS)


def main():
    errors = []
    report = [program(p, errors) for p in PROGS] + [text_tokens(errors)]
    for e in errors:
        print("streams:", e)
    print("streams: %s%s" % ("; ".join(report), ", %d error(s)" % len(errors) if errors else ""))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
