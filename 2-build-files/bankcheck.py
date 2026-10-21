#!/usr/bin/env python3
# bankcheck.py: check the banking rules of the port (docs/memory-map.md).
# Run by the Makefile from the repository's root, after the programs are
# assembled.
#
# For each program (flight, docked), the areas are: "home" (the program's
# home bank: 3-assembled-output/elite-<program>-home.asm and its blueprint
# slot, elite-<program>-blueprints.asm, with the layout file's own lines),
# "cold" (its cold bank: elite-<program>-cold.asm, and the text tokens'
# elite-tokens-cold.asm) and "main" (main RAM: every label whose address is
# below &8000, whichever copy defines it: the workspaces, and the loader's
# resident blocks, 3-assembled-output/resident.asm). Each side's far-call
# stubs are in its own copy, at their targets' places (2-build-files/streams.py).
# The home bank is paged whenever the program's code runs; the cold bank only
# during far calls; main RAM is always there.
#
# Rules, for every reference from code or data in one area to a label in
# another:
#  * branches never cross areas;
#  * cold code reaches home code only through stubs (xh_name, jh_name: JSR
#    farH / farHj : EQUW name), and never reads home data (it may take an
#    address: #LO/#HI);
#  * home code reaches cold code only through stubs (JSR farC / farCj :
#    EQUW name_C), and never reads cold data;
#  * a stub is only called, jumped or branched to, or its address taken (a
#    jump table): code that reads or writes a stub's label is reading the
#    stub, not the data of the routine or table that lives on the other
#    side (a variable that both sides use must be on the side that reads it,
#    with its users), and no reference is an offset from a stub's label (the
#    stub's neighbours are not the routine's);
#  * cold code never reads through XX0, which always points at a blueprint in
#    the home bank (the one pointer into a bank that the game keeps in zero
#    page: the others point into main RAM, or, like V for the token printers,
#    into the bank of the code that uses them);
#  * main RAM is visible to every area (and the constants that are addresses
#    in the home bank, XX21 and E% in the flight code, are home data);
#  * a line with the comment "bankcheck: ok" is exempt (reviewed by hand).
# Exit status 1 if any rule is broken.
import re, sys

OUT = "3-assembled-output/"
SRC = "1-source-files/main-sources/"
PROGS = ("flight", "docked")
FAR = ("farH", "farHj", "farC", "farCj")
MNEM = set(("ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS CLC CLD CLI CLV CMP CPX CPY "
            "DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP "
            "ROL ROR RTI RTS SBC SEC SED SEI STA STX STY TAX TAY TSX TXA TXS TYA").split())
BRANCH = set("BCC BCS BEQ BMI BNE BPL BVC BVS".split())
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_%]*")


def code_part(line):
    out, q = "", False
    for ch in line:
        if ch == '"':
            q = not q
        if ch == "\\" and not q:
            break
        out += ch
    return out


def statements(path):
    try:
        lines = open(path, encoding="latin-1").read().split("\n")
    except FileNotFoundError:
        return
    for n, line in enumerate(lines, 1):
        c = code_part(line)
        ok = "bankcheck: ok" in line
        for st in re.split(r"\s:\s", c):
            t = st.strip()
            labels = []
            while True:
                m = re.match(r"^\.([A-Za-z_][\w%]*)\s*(.*)$", t)
                if not m:
                    break
                labels.append(m.group(1))
                t = m.group(2).strip()
            mn, op = None, ""
            m = re.match(r"^([A-Za-z]{3})\b\s*(.*)$", t)
            if m and m.group(1).upper() in MNEM:
                mn, op = m.group(1).upper(), m.group(2)
            else:
                op = t
            yield n, line, labels, mn, op, ok


def idents(op):
    s = re.sub(r"'.'", "", re.sub(r'"[^"]*"', "", op))   # (strings and character literals)
    s = re.sub(r"&[0-9A-Fa-f]+", "", s)
    return IDENT.findall(s)


def check(prog, errors):
    files = {OUT + "elite-%s-home.asm" % prog: "home", OUT + "elite-%s-blueprints.asm" % prog: "home",
             OUT + "elite-%s-cold.asm" % prog: "cold", OUT + "elite-tokens-cold.asm": "cold",
             SRC + "elite-layout-%s.asm" % prog: "home", OUT + "resident.asm": "main"}
    show = {OUT + "elite-%s-%s.asm" % (prog, a): "elite-source-%s.asm" % prog for a in ("home", "blueprints", "cold")}
    show[OUT + "elite-tokens-cold.asm"] = "elite-text-tokens.asm"
    addr = {}
    try:
        for m in re.finditer(r"'([^']+)':(\d+)", open(OUT + "%s-symbols.txt" % prog).read()):
            addr.setdefault(m.group(1), int(m.group(2)))
    except FileNotFoundError:
        errors.append("%s: no symbols (%s-symbols.txt)" % (prog, prog))
        return 0
    area, own, stubs = {}, {}, set()
    for f, a in files.items():
        own[f] = set()
        for n, line, labels, mn, op, ok in statements(f):
            if mn == "JSR" and op.strip() in FAR:
                stubs.update(labels)
            for l in labels:
                area.setdefault(l, a)
                own[f].add(l)
            m = re.match(r"^([A-Za-z_]\w*)\s*=", op.strip())
            if m and mn is None:               # (constants and macro locals the file assigns)
                own[f].add(m.group(1))
            m = re.match(r"^(MACRO\s+\w+|FOR)\s+(.*)$", op.strip(), re.I)
            if m:                              # (macro parameters and loop variables)
                own[f].update(IDENT.findall(m.group(2).split(",")[0] if m.group(1).upper() == "FOR" else m.group(2)))
    for l in list(area):                       # (main RAM: whatever copy defines it)
        if addr.get(l, 0x8000) < 0x8000:
            area[l] = "main"
    # constants that are addresses in the home bank (the blueprint slot and
    # the missile's blueprint: XX21 and E% in the flight code), which are not
    # labels, so their area comes from their definitions
    for n, line, labels, mn, op, ok in statements(SRC + "elite-source-%s.asm" % prog):
        m = re.match(r"^([A-Za-z_][\w%]*)\s*=\s*(.*)$", op.strip())
        if m and mn is None and re.search(r"\b(BPSLOT%|MISSILE%|HOME%)", m.group(2)) and m.group(1) not in ("CODE%", "LOAD%"):
            area[m.group(1)] = "home"
    for f, a in files.items():
        prev, prevop = None, None
        for n, line, labels, mn, op, ok in statements(f):
            if ok:
                prev, prevop = mn, op.strip()
                continue
            if mn is None and re.match(r"^[A-Za-z_][\w%]*\s*=", op.strip()):
                continue                       # (an assignment defines a constant)
            if mn is None and re.match(r"^(PRINT|SAVE|ASSERT|IF|ELIF|SKIP|ORG|CLEAR|ALIGN|GUARD|INCLUDE|INCBIN)\b", op.strip(), re.I):
                continue                       # (assembler directives)
            if mn is None and re.match(r"^EQUW\b", op.strip(), re.I) and prev == "JSR" and prevop in FAR:
                prev, prevop = None, None
                continue                       # the EQUW of a far-call stub
            if a == "cold" and re.search(r"\(\s*XX0\s*\)", op):
                errors.append("%s: %s:%d: cold code reads a blueprint through XX0 (%s %s)"
                              % (prog, show.get(f, f), n, mn, op.strip()))
            for x in idents(op):
                if x in stubs and re.search(r"(?<![\w%])" + re.escape(x) + r"\s*[-+]", op):
                    errors.append("%s: %s:%d: %s %s uses an offset from the stub %s (its neighbours are not the routine's)"
                                  % (prog, show.get(f, f), n, mn or "", op.strip(), x))
                    continue
                if x in stubs and mn not in ("JSR", "JMP") and mn not in BRANCH and not op.strip().startswith("#") and mn is not None:
                    errors.append("%s: %s:%d: %s %s reads or writes the stub %s (it lives on the other side)"
                                  % (prog, show.get(f, f), n, mn, op.strip(), x))
                    continue
                b = "self" if x in own[f] else area.get(x)
                if b is None or b == a or b == "self" or b == "main" or a == "main" or x in FAR:
                    continue
                where = "%s:%d" % (show.get(f, f), n)
                if mn in BRANCH:
                    errors.append("%s: %s: branch from %s to %s %s" % (prog, where, a, b, x))
                elif op.strip().startswith("#"):
                    continue                   # (an address, not a read)
                elif a == "cold":
                    if mn in ("JSR", "JMP"):
                        errors.append("%s: %s: cold code calls %s in %s directly (use a stub)" % (prog, where, x, b))
                    else:
                        errors.append("%s: %s: cold code refers to %s label %s" % (prog, where, b, x))
                else:
                    errors.append("%s: %s: %s refers to cold label %s (use a stub)" % (prog, where, a, x))
            prev = mn
            prevop = op.strip()
    return len(area)


errors = []
n = sum(check(p, errors) for p in PROGS)
for e in errors:
    print("bankcheck:", e)
print("bankcheck: %d labels, %s" % (n, "%d rule(s) broken" % len(errors) if errors else "all rules hold"))
sys.exit(1 if errors else 0)
