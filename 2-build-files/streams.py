#!/usr/bin/env python3
# streams.py: emit each program's source in three passes, low, hot and cold,
# and flow the hot pass through its containers (docs/memory-map.md, "The
# sources and their passes"). Run by the Makefile from the repository's root,
# twice:
#
#   python3 2-build-files/streams.py measure    the copies for elite-measure-<program>.asm
#   python3 2-build-files/streams.py place      the copies for elite-layout-<program>.asm,
#                                              placed by the sizes the measure gave
#
# Disc Elite is two programs, each with its own source in the original's
# order: the flight code (elite-source-flight.asm) and the docked code
# (elite-source-docked.asm). Each of their routines and tables sits once, at
# its original place, and the pass it is emitted in is a field of its header:
#
#   \       Name: TT219
#   ...
#   \       Area: cold
#
#   * no Area field (or "Area: hot"): the hot pass, the game code that runs
#     with the program's home bank, bank 4, paged. It flows through its
#     containers in order: main RAM (HOTM%, elite-map.asm), then bank 4 from
#     S% at &8000 (HOME%) to the room that the layout keeps at the bank's end
#     (the quarter squares and the blueprint slot, and in the flight code the
#     renderer's routines that run in game context).
#   * "Area: low": the low pass, code that must be in main RAM, where it is
#     seen whatever bank is paged (LOW%, elite-map.asm). The disc version's
#     own code of that kind (the interrupt handler, the break handler, the
#     last saved commander) is in the loader, and the port keeps it in its
#     resident block (elite-resident.asm), so a program's low pass holds only
#     what both sides call and that needs nothing of either: the cold pass
#     calls it directly, with no stub (direct_calls).
#   * "Area: cold": the cold pass, sideways RAM bank 7 from &8000, below the
#     renderer's window at the bank's top.
#   * "Area: blueprints": the docked code's own ship blueprints, in bank 4's
#     blueprint slot at BPSLOT% (the flight code loads its set from a D.MOx
#     file there instead).
#   * "Area: none": code the port no longer runs (the renderer does its work):
#     its text stays, but its copy has only its labels and one RTS, at its
#     place, so a reference to it still assembles, and returns at once.
#   * ", again" after any of these: the block is also emitted a second time,
#     into 3-assembled-output/elite-<program>-again.asm (every other line blank, so
#     line numbers stay), with no stubs, and with its own labels and the
#     targets of its JSRs and JMPs named A_<name>, for the renderer to run the
#     original's code with stand-ins of its own for some calls.
#   * ", runs on" after any of these: a table that code reads past its end
#     into the next block, which must therefore follow it, in the same pass
#     and unit, as if it fell through.
#
# A block runs from its header to the next header (or to a separator line of
# stars, which starts an untagged block: the original's PRINT and SAVE
# sections). The blocks before the one that defines S% (the configuration and
# the workspaces) are the configuration, assembled first.
#
# BeebAsm assembles a file once and has one location counter, and banks 4 and
# 7 share the addresses &8000-&BFFF, so each container's blocks are assembled
# from a copy of the source of their own: 3-assembled-output/elite-<program>-<copy>.asm
# is the program's source with every line outside that copy's blocks blanked
# (so that line numbers stay the source's): config, low, hotm (main RAM),
# hot (bank 4), blueprints and cold; and for the measure, measure (the whole
# hot pass in one, with a label FLOW_<n> at the start of each block).
# elite-layout-<program>.asm INCLUDEs the copies each at its own address, so
# every label is defined exactly once and every block is assembled once.
#
# The flow. The hot pass is cut into units: blocks that must stay together,
# because one falls through into the next (its last statement can continue,
# or is a BIT skip, EQUB &2C or &24), runs on into it, or branches into
# another (the blocks from the one to the other, as a branch's reach is
# short). In the source's order, each unit goes into the container the flow
# has reached if it fits there, and the flow moves on to the next container
# when it does not (so each container holds its units in the source's order,
# and the containers follow each other in it). The sizes are measured, not
# estimated: the measure copies are assembled once (elite-measure-<program>.asm,
# whose symbols give each FLOW_<n>), and a block's size does not depend on
# where it goes (a stub at its place is the same size in every container).
# 3-assembled-output/flow-<program>.txt lists the containers and their units.
#
# The stubs. The low and hot passes are one side, the hot side (main RAM and
# bank 4, paged whenever the program's code runs), and the cold pass the
# other; each side calls and reads itself directly. A call across goes
# through a 5-byte stub, at the place of the routine it reaches, in the
# caller's side's copy. In a hot copy, the line that defines a cold label X
# that the hot side refers to holds X's stub, under X's own name:
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
# The far calls (elite-far.asm) are in the resident block in main RAM. A cold
# block's stubs go in the copy of the nearest block before it that is not
# cold, so a block that falls through into a routine of the other side falls
# into its stub: the stub calls the body and returns to the falling routine's
# caller with the caller's bank back, which is what the fall-through did in
# the original (a jump stub, for a target that never returns, just jumps).
# The cold pass calls the low pass's routines that need nothing of the hot
# side directly, with no stub (3-assembled-output/direct-<program>.txt).
#
# The text tokens (elite-text-tokens.asm, the original's WORDS file at &0400)
# are split by area too: its blocks tagged "Area: cold" (the recursive token
# table QQ18 and the macros that build it) are assembled into each program's
# cold pass (3-assembled-output/elite-tokens-cold.asm), and those tagged
# "Area: resident" (the sine and arctan tables SNE and ACT, which stay at
# &07C0) into the loader's resident block (elite-tokens-resident.asm). Its
# untagged blocks (the original file's configuration and SAVE) are not part
# of the port's build.
#
# Checks (exit status 1 on failure):
#   * every block's IF ... ENDIF nesting is balanced (a blanked block must not
#     take half of a conditional with it);
#   * a block whose code can fall through its end is followed, in the source,
#     by a block of its own pass (in the hot pass, the same unit), or by a
#     block of the other side whose first statement is its entry label, so
#     that the falling block falls into that label's stub; any other
#     fall-through across passes is an error;
#   * a block that ends with the original's skip trick (EQUB &2C or &24) is
#     followed by a block of its own pass (a stub cannot be skipped into);
#   * no block branches into another pass of its side (a branch to the
#     other side reaches the target's stub, at its place in its own copy);
#   * every stub's line is blank in its copy, and every target is defined in
#     the program's source (a stub has a place only there);
#   * every unit fits a container, and the flow fits.
import os, re, sys

SRCDIR = "1-source-files/main-sources/"
OUTDIR = "3-assembled-output/"
PROGS = ("flight", "docked")
TAGS = {"hot": "hot", "low": "low", "cold": "cold", "blueprints": "blueprints", "none": "none"}
TOKENS = SRCDIR + "elite-text-tokens.asm"
TOKTAGS = {"cold": "cold", "resident": "resident"}
STAR = re.compile(r"^\\ \*{70,}\s*$")
AREA = re.compile(r"^\\       Area: (.*)$")
NOFALL = set("RTS RTI JMP BRK".split())
BRANCH = set("BCC BCS BEQ BMI BNE BPL BVC BVS".split())
HOTSIDE = ("low", "hot", "blueprints")

# the hot pass's containers, in the flow's order, by the names the layout
# files give their bounds (elite-map.asm and elite-layout-<program>.asm, as
# the measure assembles them): (copy, start, end)
CONTAINERS = (("hot", "M_HOT", "M_HOT_END"), ("hotm", "M_HOTM", "M_HOTM_END"))

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


class Block:
    def __init__(self, start, default):
        self.s, self.e, self.name, self.area = start, None, None, default
        self.again = self.runson = False


def blocks(lines, tags, path, default):
    """[Block]: a block starts at a header (a line of stars followed by a lone
    backslash) or at a separator line of stars"""
    out = [Block(0, default)]
    inh = False
    for i, l in enumerate(lines):
        if STAR.match(l):
            if inh:
                inh = False
                if (i + 2 < len(lines) and lines[i + 1].rstrip() == "\\"
                        and lines[i + 2].startswith("\\       Name:")):
                    out.append(Block(i, default))          # (a banner's closing line
                    inh = True                             # opens the next header)
            elif i + 1 < len(lines) and lines[i + 1].rstrip() == "\\":
                out.append(Block(i, default))
                inh = True
            else:
                out.append(Block(i, default))
        elif inh:
            if not l.startswith("\\"):
                sys.exit("%s:%d: a header that is not closed" % (path, i + 1))
            m = re.match(r"^\\       Name: (.*)$", l)
            if m:
                out[-1].name = m.group(1).strip()
            m = AREA.match(l)
            if m:
                t = m.group(1).strip()
                while True:
                    if t.endswith(", again"):
                        t = t[:-len(", again")]
                        out[-1].again = True
                    elif t.endswith(", runs on"):
                        t = t[:-len(", runs on")]
                        out[-1].runson = True
                    else:
                        break
                if t not in tags:
                    sys.exit("%s:%d: unknown area %r" % (path, i + 1, t))
                out[-1].area = tags[t]
    for k, b in enumerate(out):
        b.e = out[k + 1].s if k + 1 < len(out) else len(lines)
    return out


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


def bit_skip(stmt):
    return bool(stmt and re.match(r"^EQUB\s+&(2C|24)\b", stmt.strip(), re.I))


def falls_through(stmt, macros):
    if stmt is None:
        return False
    w = stmt.split()
    if not w:
        return False
    op = w[0].upper()
    if w[0] in macros:
        return False                   # (a macro: the original's data macros)
    if bit_skip(stmt):
        return True                    # (a BIT skip: the next instruction's
                                       # bytes are its operand, so it runs on)
    if op in NOFALL:
        return False
    if re.match(r"^(EQU[BWDS]|SKIP|INCBIN|FOR|NEXT|PRINT|SAVE|ASSERT|ORG|CLEAR|GUARD|MACRO|ENDMACRO|INCLUDE|CPU|COPYBLOCK|ALIGN)\b", op):
        return False                   # (data and directives: nothing to fall from)
    if re.match(r"^[A-Za-z_][\w%]*\s*=", stmt) or stmt.startswith("."):
        return False                   # (a constant, or a label alone)
    return True


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


def includes(lines):
    """the files that lines INCLUDE (from 1-source-files/main-sources/), with
    theirs"""
    out = []
    for l in lines:
        m = re.match(r'^\s*INCLUDE\s+"(1-source-files/main-sources/[^"]+)"', split_code(l)[0])
        if m:
            out += read_file(m.group(1))
    return out


# ---------------------------------------------------------------- the stubs
#
# The sources use the original's names throughout. A program's cold copy is
# assembled with each cold label X renamed X_C (its definition and every
# reference in the cold copy), and with each JSR or JMP from cold code to a
# label of the hot side H going through a stub, xh_H (JSR farH: call H with
# the home bank paged in, then page the cold bank back) or, for the targets in
# NORETURN, jh_H (JSR farHj: jump to H), but for the low routines it calls
# directly. Every other file keeps the names as they are, so a reference
# from outside the cold pass to a cold label X reaches its stub, .X (JSR
# farC : EQUW X_C, or farCj for the targets in NORETURN). There is one stub
# for each cold label that a file outside the cold pass refers to, for each
# hot label that cold code calls or jumps to, and for each routine that a
# block of the other side falls into. Labels that are one place (defined one
# after another, with nothing assembled between them) share a stub: the
# earlier ones are bare labels at their lines. Labels ending in % keep their
# names. Cold code that needs a stub's address (a jump table) names the stub
# itself, xh_H.

def direct_calls(lines, bl, eff, cold, hot):
    """the low pass's labels that the cold pass may call or jump to directly,
    with no stub: those of the low blocks that, with every low block they
    call, jump or branch to or fall into, refer to nothing of the hot or cold
    pass, so that they run the same with the cold pass paged in"""
    lab = {}
    for k, b in enumerate(bl):
        for n, i in defined(lines[b.s:b.e]):
            if ACTIVE[b.s + i]:
                lab.setdefault(n, k)
    low = [k for k in range(len(bl)) if eff[k] == "low" and ASM[k]]
    bad, edges = set(), {k: set() for k in low}
    for k in low:
        b = bl[k]
        own = {n for n, i in defined(lines[b.s:b.e])}
        for i in range(b.s, b.e):
            if not ACTIVE[i]:
                continue
            for off, st in statements(split_code(lines[i])[0]):
                st = re.sub(r"^\s*(\.[A-Za-z_]\w*\s*)+", "", st)
                m = re.match(r"^([A-Za-z]{3})\b", st.strip())
                op = m.group(1).upper() if m else ""
                for a, c, t in tokens(st):
                    if t in own or (m and t.upper() == op):
                        continue
                    k2 = lab.get(t)
                    if k2 is not None and eff[k2] == "low":
                        if op in ("JSR", "JMP") or op in BRANCH:
                            edges[k].add(k2)
                    elif k2 is not None and eff[k2] in ("hot", "cold", "blueprints"):
                        bad.add(k)
                    elif t in cold:
                        bad.add(k)
        if falls_through(last_statement(lines, b.s, b.e), set()):
            nxt = [k2 for k2 in range(k + 1, len(bl)) if ASM[k2]]
            if nxt and eff[nxt[0]] == "low":
                edges[k].add(nxt[0])
    changed = True
    while changed:
        changed = False
        for k in low:
            if k not in bad and edges[k] & bad:
                bad.add(k)
                changed = True
    out = set()
    for k in low:
        if k not in bad:
            b = bl[k]
            out.update(n for n, i in defined(lines[b.s:b.e]) if ACTIVE[b.s + i])
    return out


def glue(prog, src, copies, errors, lines, bl, eff, copy_of, falls, hotcopies):
    """the stubs between the sides, written into the copies at their places;
    returns (stubs into the cold pass, stubs out of it, the direct calls)"""
    noreturn = NORETURN[prog]
    macros = set()
    for l in lines:
        m = re.match(r"^\s*MACRO\s+(\w+)", l)
        if m:
            macros.add(m.group(1))
    cold = {n for n, i in defined(copies["cold"]) if not n.endswith("%")}
    # the hot side's labels, with the files the hot blocks INCLUDE
    hotfiles = [(c, copies[c]) for c in hotcopies]
    for c in hotcopies:
        hotfiles += includes(copies[c])
    hot = {}
    for f, ls in hotfiles:
        for n, i in defined(ls):
            hot.setdefault(n, f)
    for n in cold & set(hot):
        errors.append("%s: %s is defined in the cold pass and outside it" % (src, n))
    alias = {}
    for f, ls in hotfiles + [("cold", copies["cold"])]:
        alias.update(aliases(ls, macros))
    direct = direct_calls(lines, bl, eff, cold, hot)
    # the cold copy: X -> X_C, JSR/JMP H -> xh_H / jh_H
    outh = []                               # (stub name, target, place, kind) in order
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
            if m and m.group(2) in hot and m.group(2) not in cold and m.group(2) not in direct:
                code = m.group(1) + ("jh_" if m.group(2) in noreturn else "xh_") + m.group(2) + m.group(3)
            cc[i] = code + comment
            continue
        new = ""
        pos = 0
        for off, st in statements(code):
            m = re.match(r"^(\s*)(JSR|JMP)(\s+)([A-Za-z_][A-Za-z0-9_]*%?)(.*)$", st, re.I)
            if m and m.group(4) in hot and m.group(4) not in cold and m.group(4) not in direct:
                h = m.group(4)
                if m.group(5).strip():
                    errors.append("%s:%d: %s %s%s from the cold pass: a stub can only call a label"
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
    # references to cold labels from outside the cold pass
    others = read_file(SRCDIR + "elite-layout-%s.asm" % prog)
    outc, seenc = [], set()
    elsewhere = {n for f, ls in others for n, i in defined(ls)}
    for f, ls in [(c, copies[c]) for c in hotcopies + ["config"]] + others:
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
                    if f in hotcopies:
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
        elif entry not in direct:          # (cold code falls into a hot routine)
            place = alias.get(entry, entry)
            kind = "jh_" if place in noreturn or entry in noreturn else "xh_"
            if kind + entry not in seenh:
                seenh[kind + entry] = place
                outh.append((kind + entry, entry, place, kind))
    # where each label is defined in the source (its first line that the
    # build's flags assemble), and its block
    barea = [None] * len(lines)
    for k, b in enumerate(bl):
        for i in range(b.s, b.e):
            barea[i] = k
    where = {}
    for n, i in defined(lines):
        if ACTIVE[i]:
            where.setdefault(n, i)

    def host(i):
        """the hot copy that holds the stubs at line i of a cold block: that
        of the nearest block before it, in the source, that is not cold and
        holds code, so that a block that falls through into the cold block
        falls into its stubs"""
        for k in range(barea[i] - 1, -1, -1):
            if eff[k] == "cold" or not ASM[k] or copy_of[k] not in hotcopies:
                continue
            return copy_of[k]
        return hotcopies[-1]

    def place_stubs(groups, ok_area, side):
        """groups: [(far helper, [(stub label, target label)])], each group one
        place; each stub goes at the line of its target's definition, in the
        copy that hosts it, and the labels of a place share the stub at the
        last of them"""
        n = 0
        for far, members in groups:
            at = []
            for stub, target in members:
                i = where.get(target)
                if i is None or eff[barea[i]] not in ok_area:
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
    # the stubs into the cold pass, in the hot copies at the cold labels' places
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
    # the stubs out of the cold pass, in the cold copy at the hot labels' places
    groups, done = [], {}
    for stub, h, place, kind in outh:
        key = (kind, place)
        if key not in done:
            done[key] = len(groups)
            groups.append(("farHj" if kind == "jh_" else "farH", []))
        groups[done[key]][1].append((stub, h))
    nh = place_stubs(groups, ("hot", "low", "blueprints"), "hot")
    # a cold block that falls into a low routine the cold pass calls directly
    # falls into a jump to it, at that routine's place in the cold copy
    for side, entry in falls:
        if side == "cold" and entry in direct:
            i = where[entry]
            if code_part(cc[i]):
                errors.append("%s:%d: the seam into %s: its line is not blank in the cold copy" % (src, i + 1, entry))
            else:
                cc[i] = " JMP %s                \\ (the fall-through into %s, in the low pass)" % (entry, entry)
    return nc, nh, direct


ASM = []


def again_copy(lines, bl):
    """the ", again" blocks, every other line blank: each label a block
    defines, and each JSR or JMP target outside the block, renamed A_<name>
    (in the code, not the comments), so that the copy's labels are its own
    and the file that INCLUDEs it decides where each call goes (the original
    routine, A_X = X, or a stand-in .A_X)"""
    out = [""] * len(lines)
    for b in bl:
        if not b.again:
            continue
        own = set()
        for i in range(b.s, b.e):
            m = re.match(r"^\.([A-Za-z_]\w*)", code_part(lines[i]))
            if m:
                own.add(m.group(1))
        for i in range(b.s, b.e):
            c = code_part(lines[i])
            if not c:
                out[i] = lines[i]
                continue
            n = len(lines[i]) - len(lines[i].lstrip())
            code = re.sub(r"\b(JSR|JMP)\s+([A-Za-z_]\w*)", lambda m: "%s A_%s" % (m.group(1), m.group(2)), c)
            code = re.sub(r"(?<![\w%])([A-Za-z_]\w*)\b",
                          lambda m: "A_" + m.group(1) if m.group(1) in own else m.group(1), code)
            out[i] = " " * n + code + lines[i][lines[i].index(c) + len(c):]
    return out


def stub_none(lines, bl, src):
    """each "Area: none" block's code: only its labels, then an RTS on its
    last code line (the lines between blanked, so line numbers stay)"""
    for b in bl:
        if b.area != "none":
            continue
        last = None
        for i in range(b.s, b.e):
            if code_part(lines[i]).strip():
                m = re.match(r"^(\.[A-Za-z_]\w*)", lines[i])
                lines[i] = m.group(1) if m else ""
                last = i
        if last is None:
            sys.exit("%s:%d: %s: Area: none, and no code" % (src, b.s + 1, b.name))
        lines[last] = (lines[last] + " : RTS") if lines[last] else " RTS"
        b.area = "hot"
        b.none = True


def measured(prog):
    """the measure's symbols (3-assembled-output/measure-<program>-symbols.txt, beebasm
    -d of elite-measure-<program>.asm)"""
    sy = {}
    for m in re.finditer(r"'([^']+)':(\d+)", open(OUTDIR + "measure-%s-symbols.txt" % prog).read()):
        sy.setdefault(m.group(1), int(m.group(2)))
    return sy


def program(prog, phase, errors):
    src = SRCDIR + "elite-source-%s.asm" % prog
    lines = open(src, encoding="latin-1").read().split("\n")
    bl = blocks(lines, TAGS, src, "hot")
    for b in bl:
        b.none = False
    with open(OUTDIR + "elite-%s-again.asm" % prog, "w", encoding="latin-1") as f:
        f.write("\n".join(again_copy(lines, bl)))
    stub_none(lines, bl, src)
    ACTIVE[:] = active_lines(lines)
    macros = set(m.group(1) for m in (re.match(r"^\s*MACRO\s+(\w+)", l) for l in lines) if m)
    for b in bl:
        depth = 0
        for i in range(b.s, b.e):
            c = code_part(lines[i]).upper()
            depth += bool(re.match(r"^IF\b", c)) - bool(re.match(r"^ENDIF\b", c))
        if depth:
            errors.append("%s:%d: %s: IF ... ENDIF not balanced in a block" % (src, b.s + 1, b.name))
    ASM[:] = [any(ACTIVE[i] and assembles(code_part(lines[i]), macros) for i in range(b.s, b.e)) for b in bl]
    # each block's pass: the configuration before S%'s block, then its tag
    first = min(k for k, b in enumerate(bl) if any(re.match(r"^\.S%", code_part(lines[i]))
                                                   for i in range(b.s, b.e)))
    eff = ["config" if k < first else b.area for k, b in enumerate(bl)]
    if any(eff[k] != "hot" for k in range(first, first + 1)):
        errors.append("%s: S%%'s block must be in the hot pass" % src)
    side = lambda p: "cold" if p == "cold" else "hot"
    # the hot pass's blocks that assemble, in the source's order, and its units
    hot = [k for k in range(len(bl)) if eff[k] == "hot" and ASM[k]]
    pos = {k: n for n, k in enumerate(hot)}
    parent = list(range(len(hot)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def join(a, b):
        for x in range(min(a, b), max(a, b)):      # (a unit is a run of blocks)
            ra, rb = find(x), find(x + 1)
            if ra != rb:
                parent[max(ra, rb)] = min(ra, rb)
    # fall-through: each block that can fall through its end must be followed,
    # in the source, by a block of its own pass that holds code (in the hot
    # pass, the same unit), or by a block of the other side whose first
    # statement is its entry label, as that label's stub is then the next
    # thing in the falling block's pass
    falls = []
    for k, b in enumerate(bl):
        if eff[k] == "config" or not ASM[k]:
            continue
        st = last_statement(lines, b.s, b.e)
        if not falls_through(st, macros) and not b.runson:
            continue
        for k2 in range(k + 1, len(bl)):
            b2 = bl[k2]
            if not ASM[k2]:
                continue               # (comments, PRINTs and constants only)
            if any(re.match(r"^(ORG|CLEAR|SKIPTO)\b", code_part(lines[i]), re.I) for i in range(b2.s, b2.e)):
                errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s, which moves the address"
                              % (src, b.e, b.name, eff[k], st, b2.name))
            elif eff[k2] == eff[k]:
                if eff[k] == "hot":
                    join(pos[k], pos[k2])
            elif bit_skip(st) or b.runson:
                errors.append("%s:%d: %s (%s) %s %s (%s): they must be in one pass"
                              % (src, b.e, b.name, eff[k], "runs on into" if b.runson else "skips into",
                                 b2.name, eff[k2]))
            elif side(eff[k2]) != side(eff[k]):
                entry = entry_label(lines, b2.s, b2.e, macros)
                if entry:
                    falls.append((side(eff[k]), entry))
                else:
                    errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s (%s), whose "
                                  "first statement is not its entry label" % (src, b.e, b.name, eff[k], st, b2.name,
                                                                              eff[k2]))
            else:
                errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s (%s), another pass"
                              % (src, b.e, b.name, eff[k], st, b2.name, eff[k2]))
            break
    # branches: a hot block that branches into another keeps the blocks from
    # the one to the other in one unit (a branch reaches only 128 bytes); no
    # branch crosses passes
    blockof = {}
    for k, b in enumerate(bl):
        for n, i in defined(lines[b.s:b.e]):
            if ACTIVE[b.s + i]:
                blockof.setdefault(n, k)
    for k, b in enumerate(bl):
        if eff[k] == "config" or not ASM[k]:
            continue
        for i in range(b.s, b.e):
            if not ACTIVE[i]:
                continue
            for off, st in statements(split_code(lines[i])[0]):
                m = re.match(r"^\s*(?:\.[A-Za-z_]\w*\s+)*([A-Za-z]{3})\s+([A-Za-z_]\w*)(?![\w%])", st)
                if not m or m.group(1).upper() not in BRANCH:
                    continue
                k3 = blockof.get(m.group(2))
                if k3 is None or k3 == k:
                    continue
                if eff[k3] == eff[k]:
                    if k in pos:
                        join(pos[k], pos[k3])
                elif side(eff[k3]) != side(eff[k]):
                    # (a branch to a routine of the other side reaches its
                    # stub, at its place in this side's copy: in the hot
                    # pass, that is the copy of the nearest hot block before
                    # it, which must then be in the branch's unit)
                    if k in pos:
                        hk = next((j for j in range(k3 - 1, -1, -1) if eff[j] == "hot" and ASM[j]), None)
                        if hk is None:
                            errors.append("%s:%d: %s branches to %s (%s), whose stub has no place"
                                          % (src, i + 1, b.name, m.group(2), eff[k3]))
                        else:
                            join(pos[k], pos[hk])
                else:
                    errors.append("%s:%d: %s branches to %s in another pass (%s)"
                                  % (src, i + 1, b.name, m.group(2), eff[k3]))
    units = []                             # [first, last] positions in hot
    for n in range(len(hot)):
        if n and find(n) == find(n - 1):
            units[-1][1] = n
        else:
            units.append([n, n])
    # each block's copy
    copy_of = {}
    report = []
    hotcopies = ["low"] + (["measure"] if phase == "measure" else [c[0] for c in CONTAINERS]) + ["blueprints"]
    if phase == "measure":
        for k in range(len(bl)):
            copy_of[k] = "measure" if eff[k] == "hot" else eff[k]
    else:
        sy = measured(prog)
        addr = [sy["FLOW_%d" % k] for k in hot] + [sy["FLOW_END"]]
        bsize = [addr[n + 1] - addr[n] for n in range(len(hot))]
        conts = []
        for c, a, z in CONTAINERS:
            if a not in sy or z not in sy:
                errors.append("%s: the measure does not give the container %s's bounds (%s, %s)" % (prog, c, a, z))
                return ""
            conts.append([c, sy[a], sy[z], []])
        used = {c[0]: 0 for c in conts}
        cur = 0
        for u0, u1 in units:
            names = "%s..%s" % (bl[hot[u0]].name, bl[hot[u1]].name) if u1 > u0 else bl[hot[u0]].name
            size = sum(bsize[n] for n in range(u0, u1 + 1))
            if any(re.match(r"^\.S%", code_part(lines[i])) for n in (u0,) for i in range(bl[hot[n]].s, bl[hot[n]].e)):
                cur = [c[0] for c in conts].index("hot")       # (S% starts bank 4: the
            while cur < len(conts) and conts[cur][1] + used[conts[cur][0]] + size > conts[cur][2]:
                cur += 1                                      # entry table at &8000)
            if cur == len(conts):
                errors.append("%s: the hot pass does not fit: %s (%d bytes) has no room" % (prog, names, size))
                break
            c = conts[cur]
            c[3].append((used[c[0]], size, names))
            used[c[0]] += size
            for n in range(u0, u1 + 1):
                copy_of[hot[n]] = c[0]
        for k in range(len(bl)):
            if k not in copy_of:
                if eff[k] == "hot":        # (a block that assembles nothing: the
                    copy_of[k] = copy_of.get(k - 1, "hot")   # one before it's)
                else:
                    copy_of[k] = eff[k]
        for name, a, z, us in conts:
            report.append("%s &%04X-&%04X: %d units, %d bytes, %d free" % (name, a, z - 1, len(us), used[name],
                                                                          z - a - used[name]))
            for off, size, names in us:
                report.append("  &%04X %5d %s" % (a + off, size, names))
    copies = {}
    allc = ["config", "low", "cold", "blueprints"] + (["measure"] if phase == "measure" else [c[0] for c in CONTAINERS])
    for a in allc:
        copies[a] = []
        for k, b in enumerate(bl):
            copies[a] += [lines[i] if copy_of[k] == a else "" for i in range(b.s, b.e)]
    if phase == "measure":
        for k in hot:
            copies["measure"][bl[k].s] = ".FLOW_%d" % k
    nstubs = glue(prog, src, copies, errors, lines, bl, eff, copy_of, falls, hotcopies)
    with open(OUTDIR + "direct-%s.txt" % prog, "w") as f:   # (for bankcheck.py)
        f.write("".join("%s\n" % n for n in sorted(nstubs[2])))
    for a in allc:
        with open(OUTDIR + "elite-%s-%s.asm" % (prog, a), "w", encoding="latin-1") as f:
            f.write("\n".join(copies[a]))
    if phase == "place":
        with open(OUTDIR + "flow-%s.txt" % prog, "w") as f:
            f.write("\n".join(report) + "\n")
    n = {p: sum(1 for k in range(len(bl)) if eff[k] == p and ASM[k]) for p in ("low", "hot", "cold", "blueprints")}
    nn = sum(1 for b in bl if b.none)
    out = "%s: %d blocks (low %d, hot %d, cold %d, blueprints %d, none %d), %d hot units, stubs %d into the cold " \
          "pass, %d out of it, %d direct" % (prog, len(bl), n["low"], n["hot"], n["cold"], n["blueprints"], nn,
                                             len(units), nstubs[0], nstubs[1], len(nstubs[2]))
    if phase == "place":
        out += "; " + "; ".join(l for l in report if not l.startswith("  &"))
    return out


def text_tokens(errors):
    """the text tokens' copies, one per area (TOKTAGS); untagged blocks go
    in neither"""
    lines = open(TOKENS, encoding="latin-1").read().split("\n")
    bl = blocks(lines, TOKTAGS, TOKENS, "none")
    for b in bl:
        depth = 0
        for i in range(b.s, b.e):
            c = code_part(lines[i]).upper()
            depth += bool(re.match(r"^IF\b", c)) - bool(re.match(r"^ENDIF\b", c))
        if depth and b.area != "none":
            errors.append("%s:%d: %s: IF ... ENDIF not balanced in an area's block" % (TOKENS, b.s + 1, b.name))
    for a in TOKTAGS.values():
        out = []
        for b in bl:
            out += [lines[i] if b.area == a else "" for i in range(b.s, b.e)]
        with open(OUTDIR + "elite-tokens-%s.asm" % a, "w", encoding="latin-1") as f:
            f.write("\n".join(out))
    return "tokens: %s" % ", ".join("%s %d" % (a, sum(1 for b in bl if b.area == a)) for a in TOKTAGS.values())


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else "place"
    if phase not in ("measure", "place"):
        sys.exit("usage: streams.py measure|place")
    errors = []
    report = [program(p, phase, errors) for p in PROGS] + [text_tokens(errors)]
    for e in errors:
        print("streams:", e)
    print("streams (%s): %s%s" % (phase, "; ".join(report), ", %d error(s)" % len(errors) if errors else ""))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
