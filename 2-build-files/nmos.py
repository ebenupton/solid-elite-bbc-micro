#!/usr/bin/env python3
"""nmos.py: convert the Master port's 65C02 (65SC12) host code to NMOS 6502
for the Model B host (docs/TUBE-PLAN.md: one NMOS host binary).

    python3 tube/tools/nmos.py SRC OUT [--report FILE] [--tmp ZP] [--sub FROM=TO ...]

Each 65C02-only instruction is rewritten with NMOS instructions that leave
every register and flag the following code reads as the original did. Which
registers and flags are dead after an instruction is found by a forward scan
of the source (fall-through, branches and JMPs to labels in the same file),
conservatively: at an RTS, RTI, JMP elsewhere, a macro or a directive,
everything is live; at a JSR the callee is assumed to read A, X, Y, C and V
(not N and Z).

  BRA l          JMP l
  STZ m          LDr #0 : STr m with a dead register r and N, Z dead (a run of
                 STZs shares one LDr), else PHP ... PLP around it, else PHA ...
  INC A, DEC A   CLC : ADC #1 / SEC : SBC #1 (C and V dead), else TAX : INX : TXA
                 (X dead), TAY ... (Y dead), else STA tmp : INC tmp : LDA tmp
  LDA (zp) ...   LDY #0 : LDA (zp),Y (Y dead; for a store N and Z dead too)
  PHX / PLX      TXA : PHA (A, N, Z dead) / PLA : TAX (A dead); PHY, PLY alike

Anything else (TSB, TRB, BIT #, JMP (a,X), an indirect with Y live, PHX with A
live, a BRA to P%+n) stops the conversion with the line, to be handled in the
source (--sub replaces text on the way in). The output is assembled with
CPU 0, so BeebAsm rejects anything left over. The report lists every site.
"""
import re, sys

ARGS = sys.argv[1:]
SRC, OUT = ARGS[0], ARGS[1]
REPORT = None
TMP = "&E5"
TMPY = "&E6"
SUBS = []
i = 2
while i < len(ARGS):
    if ARGS[i] == "--report": REPORT = ARGS[i + 1]; i += 2
    elif ARGS[i] == "--tmp": TMP = ARGS[i + 1]; i += 2
    elif ARGS[i] == "--tmpy": TMPY = ARGS[i + 1]; i += 2
    elif ARGS[i] == "--sub":
        a, b = ARGS[i + 1].split("=", 1); SUBS.append((a.replace("\\n", "\n"), b.replace("\\n", "\n"))); i += 2
    else: sys.exit("unknown option " + ARGS[i])

text = open(SRC, encoding="latin-1").read()
for a, b in SUBS:
    if a not in text: sys.exit("--sub: %r not found in %s" % (a, SRC))
    text = text.replace(a, b)
lines = text.split("\n")

A, X, Y, N, Z, C, V = 1, 2, 4, 8, 16, 32, 64
ALL = 127
# mnemonic -> (reads, writes) (addressing adds X or Y reads)
RW = {
 "LDA": (0, A|N|Z), "LDX": (0, X|N|Z), "LDY": (0, Y|N|Z), "STA": (A, 0), "STX": (X, 0), "STY": (Y, 0), "STZ": (0, 0),
 "ADC": (A|C, A|N|Z|C|V), "SBC": (A|C, A|N|Z|C|V), "AND": (A, A|N|Z), "ORA": (A, A|N|Z), "EOR": (A, A|N|Z),
 "CMP": (A, N|Z|C), "CPX": (X, N|Z|C), "CPY": (Y, N|Z|C), "BIT": (A, N|Z|V),
 "ASL": (0, N|Z|C), "LSR": (0, N|Z|C), "ROL": (C, N|Z|C), "ROR": (C, N|Z|C), "INC": (0, N|Z), "DEC": (0, N|Z),
 "INX": (X, X|N|Z), "DEX": (X, X|N|Z), "INY": (Y, Y|N|Z), "DEY": (Y, Y|N|Z),
 "TAX": (A, X|N|Z), "TAY": (A, Y|N|Z), "TXA": (X, A|N|Z), "TYA": (Y, A|N|Z), "TSX": (0, X|N|Z), "TXS": (X, 0),
 "PHA": (A, 0), "PHX": (X, 0), "PHY": (Y, 0), "PHP": (N|Z|C|V, 0), "PLA": (0, A|N|Z), "PLX": (0, X|N|Z), "PLY": (0, Y|N|Z), "PLP": (0, N|Z|C|V),
 "BCC": (C, 0), "BCS": (C, 0), "BEQ": (Z, 0), "BNE": (Z, 0), "BMI": (N, 0), "BPL": (N, 0), "BVC": (V, 0), "BVS": (V, 0), "BRA": (0, 0),
 "CLC": (0, C), "SEC": (0, C), "CLV": (0, V), "CLI": (0, 0), "SEI": (0, 0), "CLD": (0, 0), "SED": (0, 0), "NOP": (0, 0),
 "TSB": (A, Z), "TRB": (A, Z), "JMP": (0, 0), "JSR": (0, 0), "RTS": (0, 0), "RTI": (0, 0), "BRK": (0, 0),
}
BRANCH = {"BCC", "BCS", "BEQ", "BNE", "BMI", "BPL", "BVC", "BVS", "BRA"}

def code_of(l):
    q = False
    for k, ch in enumerate(l):
        if ch == '"': q = not q
        if ch == "\\" and not q: return l[:k]
    return l

def split(l):
    """(label, mnemonic, operand, comment) of a line ('' where absent); a line
    that is not a single plain instruction has mnemonic None"""
    code, com = l, ""
    q = False
    for k, ch in enumerate(l):
        if ch == '"': q = not q
        if ch == "\\" and not q: code, com = l[:k], l[k:]; break
    m = re.match(r"^(\s*)(\.\^?[A-Za-z_][\w%]*)?\s*(.*?)\s*$", code)
    lab, rest = m.group(2) or "", m.group(3)
    if not rest: return lab, "", "", com
    if ":" in rest: return lab, None, rest, com
    m2 = re.match(r"^([A-Za-z]{3})(\s+(.*))?$", rest)
    if not m2 or m2.group(1).upper() not in RW: return lab, None, rest, com
    return lab, m2.group(1).upper(), (m2.group(3) or "").strip(), com

P = [split(l) for l in lines]
labels = {}
for k, (lab, mn, op, com) in enumerate(P):
    if lab: labels[lab.lstrip(".^")] = k

def regs_of(mn, op):
    r, w = RW[mn]
    o = op.upper().replace(" ", "")
    if mn in ("ASL", "LSR", "ROL", "ROR", "INC", "DEC") and o in ("A", ""): r |= A; w |= A
    if o.endswith(",X") or o.endswith(",X)"): r |= X
    if o.endswith(",Y"): r |= Y
    if mn == "BIT" and op.startswith("#"): w = Z
    return r, w

RTSNZ = [False]           # (PLX/PLY's case: N, Z at an RTS count as dead)
def dead(k, want, depth=0, seen=None):
    """the subset of want (bits) that no path from line k on reads before
    writing it (conservative: unknown control flow counts as a read)"""
    if seen is None: seen = set()
    pend, live, j = want, 0, k
    while pend:
        if j >= len(P): live |= pend; break
        if (j, pend) in seen: break                # (a loop that reads none of them)
        seen.add((j, pend))
        lab, mn, op, com = P[j]
        if mn is None: live |= pend; break
        if mn == "": j += 1; continue
        r, w = regs_of(mn, op)
        if mn == "JSR": r = A | X | Y | C | V
        live |= r & pend
        pend &= ~r & ~w
        if not pend: break
        if mn in ("RTS", "RTI", "BRK"): live |= pend & ~((N | Z) if RTSNZ[0] and mn == "RTS" else 0); break
        if mn == "JMP" or mn in BRANCH:
            t = op.strip()
            if t not in labels or depth >= 40 or "(" in t: live |= pend; break
            d = dead(labels[t], pend, depth + 1, seen)
            live |= pend & ~d
            pend &= d
            if mn in ("JMP", "BRA"): break
        j += 1
    return want & ~live

def is_dead(k, bits): return dead(k + 1, bits) == bits

out, report, errors = [], [], []
zero_reg = None             # a register known to hold 0 (a run of converted STZs)
consumed = set()            # lines already emitted inside a (zp) block
IZP = re.compile(r"^\(\s*([^,)]+)\s*\)$")
# conditional blocks that the Model B host never assembles (IF ... _HOSTB = 0,
# and the ELSE of IF _HOSTB): left as they are, without complaint
INACT = set()
stack = []
for k, l in enumerate(lines):
    t = l.split("\\")[0].strip()
    if re.match(r"^IF\b", t):
        cond = t[2:].strip()
        off = (bool(re.search(r"_HOSTB\s*=\s*0\b", cond)) and "OR" not in cond) or \
              bool(re.match(r"^_TPART\s*(<>\s*2|=\s*[01])\s*$", cond))   # (the host's _TPART is 2)
        on = cond == "_HOSTB"
        stack.append([off, on])
    elif re.match(r"^ELSE\b", t) and stack:
        off, on = stack[-1]; stack[-1] = [on, off]
    elif re.match(r"^ENDIF\b", t) and stack:
        stack.pop()
    elif any(st[0] for st in stack):
        INACT.add(k)
for k, l in enumerate(lines):
    if k in consumed: continue
    if k in INACT: out.append(l); continue
    lab, mn, op, com = P[k]
    ind = re.match(r"^(\s*)", l).group(1) or " "
    prefix = (lab + " ") if lab else ""
    def emit(instrs, note):
        first = True
        for ins in instrs:
            out.append((prefix if first else "") + " " + ins + ((" " + com) if first and com else ""))
            first = False
        report.append("%d: %s %s -> %s" % (k + 1, mn, op, " : ".join(instrs)) + (" (%s)" % note if note else ""))
    if mn is None or mn == "":
        out.append(l); zero_reg = None if (mn is None or lab) else zero_reg; continue
    if mn not in ("BRA", "STZ", "PHX", "PHY", "PLX", "PLY", "TSB", "TRB") and not (mn in ("INC", "DEC") and op.upper() == "A") \
            and not re.match(r"^\(\s*[^,)]+\s*\)$", op) and not (mn == "BIT" and op.startswith("#")) and not (mn == "JMP" and ",X)" in op.replace(" ", "").upper()):
        out.append(l)
        r, w = regs_of(mn, op)
        if zero_reg and (w & zero_reg or lab): zero_reg = None
        continue
    if mn == "BRA":
        if "P%" in op: errors.append("%d: BRA %s" % (k + 1, op)); out.append(l); continue
        emit(["JMP " + op], ""); zero_reg = None; continue
    if mn == "STZ":
        o = op.upper().replace(" ", "")
        idxx = o.endswith(",X")
        absx = idxx and not re.match(r"^(&[0-9A-F]{1,2}|\d{1,3}),X$", o)
        if zero_reg and not lab:
            r = zero_reg
            if r == A or (r == Y and not absx) or (r == X and not idxx):
                emit(["ST%s %s" % ("A" if r == A else "X" if r == X else "Y", op)], "zero reused"); continue
        cands = [(A, "A")] + ([] if idxx else [(X, "X")]) + ([] if absx else [(Y, "Y")])
        done = False
        for bit, nm in cands:
            if is_dead(k, bit | N | Z):
                emit(["LD%s #0" % nm, "ST%s %s" % (nm, op)], ""); zero_reg = bit; done = True; break
        if done: continue
        for bit, nm in cands:
            if is_dead(k, bit):
                emit(["PHP", "LD%s #0" % nm, "ST%s %s" % (nm, op), "PLP"], "flags kept"); zero_reg = None; done = True; break
        if done: continue
        emit(["PHP", "PHA", "LDA #0", "STA " + op, "PLA", "PLP"], "all kept"); zero_reg = None; continue
    zero_reg = None
    if mn in ("INC", "DEC"):
        if is_dead(k, C | V):
            emit(["CLC", "ADC #1"] if mn == "INC" else ["SEC", "SBC #1"], ""); continue
        for bit, nm in ((X, "X"), (Y, "Y")):
            if is_dead(k, bit):
                emit(["TA" + nm, ("IN" if mn == "INC" else "DE") + nm, "T%sA" % nm], ""); break
        else:
            emit(["STA " + TMP, mn + " " + TMP, "LDA " + TMP], "via " + TMP)
        continue
    m = re.match(r"^\(\s*([^,)]+)\s*\)$", op)
    if m and mn not in ("JMP",):
        store = mn == "STA"
        need = Y | (N | Z if store else 0)
        if is_dead(k, need):
            emit(["LDY #0", "%s (%s),Y" % (mn, m.group(1))], ""); continue
        # Y live: a block of (zp) accesses and instructions that leave Y alone
        # (no labels, no control flow) shares one save of Y in TMPY
        blk, j = [k], k + 1
        while j < len(P):
            lb2, mn2, op2, _ = P[j]
            if mn2 is None or lb2: break
            if mn2 == "": j += 1; continue
            if mn2 in BRANCH or mn2 in ("JMP", "JSR", "RTS", "RTI", "BRK", "BRA", "PHX", "PHY", "PLX", "PLY", "STZ", "TSB", "TRB"): break
            if mn2 in ("INC", "DEC") and op2.upper() == "A": break
            if IZP.match(op2 or "") and mn2 != "JMP": blk.append(j); j += 1; continue
            r2, w2 = regs_of(mn2, op2)
            if (r2 | w2) & Y: break
            blk.append(j); j += 1
        while blk and not IZP.match(P[blk[-1]][2] or ""): blk.pop()
        if len(blk) > 1:
            last = blk[-1]
            lastmn = P[last][1]
            body = []
            for b in blk:
                lb, mb, ob, cb = P[b]
                mm = IZP.match(ob or "")
                body.append("%s (%s),Y" % (mb, mm.group(1)) if mm and mb != "JMP" else ("%s %s" % (mb, ob)).strip())
            live = not is_dead(last, N | Z)
            own = any(regs_of(P[b][1], "")[1] & (N | Z) for b in blk)   # does the block set N, Z?
            if live and own:      # the block's own flags, as it left them
                instrs = ["STY " + TMPY, "LDY #0"] + body + ["PHP", "LDY " + TMPY, "PLP"]
            elif live:            # those from before it
                instrs = ["PHP", "STY " + TMPY, "LDY #0"] + body + ["LDY " + TMPY, "PLP"]
            else:
                instrs = ["STY " + TMPY, "LDY #0"] + body + ["LDY " + TMPY]
            emit(instrs, "Y kept, %d accesses" % len(blk))
            for b in blk[1:]: consumed.add(b)
            continue
        # Y live: keep it in TMPY round the indexed access, and the flags as
        # the original leaves them (a store: as before it; a load: its own)
        if is_dead(k, N | Z):
            emit(["STY " + TMPY, "LDY #0", "%s (%s),Y" % (mn, m.group(1)), "LDY " + TMPY], "Y kept")
        elif store:
            emit(["PHP", "STY " + TMPY, "LDY #0", "%s (%s),Y" % (mn, m.group(1)), "LDY " + TMPY, "PLP"], "Y and flags kept")
        else:
            emit(["STY " + TMPY, "LDY #0", "%s (%s),Y" % (mn, m.group(1)), "PHP", "LDY " + TMPY, "PLP"], "Y and flags kept")
        continue
    if mn in ("PHX", "PHY"):
        r = "X" if mn == "PHX" else "Y"
        if is_dead(k, A | N | Z): emit(["T%sA" % r, "PHA"], ""); continue
        if is_dead(k, N | Z): emit(["STA " + TMP, "T%sA" % r, "PHA", "LDA " + TMP], "A kept in " + TMP); continue
        errors.append("%d: %s (A and flags live)" % (k + 1, mn)); out.append(l); continue
    if mn in ("PLX", "PLY"):
        r = "X" if mn == "PLX" else "Y"
        if is_dead(k, A): emit(["PLA", "TA" + r], ""); continue
        if is_dead(k, N | Z): emit(["STA " + TMP, "PLA", "TA" + r, "LDA " + TMP], "A kept in " + TMP); continue
        RTSNZ[0] = True; ok = is_dead(k, N | Z); RTSNZ[0] = False
        if ok: emit(["STA " + TMP, "PLA", "TA" + r, "LDA " + TMP], "A kept in " + TMP + "; N, Z not returned"); continue
        if is_dead(k, C): emit(["STA " + TMP, "PLA", "TA" + r, "LDA " + TMP, "CP%s #0" % r], "A kept in " + TMP + ", flags from " + r); continue
        errors.append("%d: %s (A and all flags live)" % (k + 1, mn)); out.append(l); continue
    errors.append("%d: %s %s" % (k + 1, mn, op)); out.append(l)

# a converted line whose label is referenced at an offset (a patched operand,
# label+2) would now point into another instruction: those are for --sub
for r in report:
    n = int(r.split(":")[0])
    lab = P[n - 1][0].lstrip(".^")
    if lab and re.search(r"\b%s\s*[+-]\s*\d" % re.escape(lab), text):
        errors.append("%d: %s is referenced at an offset (a patched operand)" % (n, lab))
# a P%+n (or label+n) operand whose span crosses a converted instruction now
# lands elsewhere: also for --sub
conv = set(int(r.split(":")[0]) - 1 for r in report)
ZPC = {}
for l in lines:
    m = re.match(r"^\s*([A-Za-z_]\w*)\s*=\s*&([0-9A-Fa-f]+)\s*($|\\)", l)
    if m and int(m.group(2), 16) < 256: ZPC[m.group(1)] = 1
def length(mn, op):
    o = (op or "").strip()
    if o in ("", "A"): return 1
    if o.startswith("#") or mn in BRANCH: return 2
    if o.startswith("("): return 3 if mn == "JMP" else 2
    base = re.split(r"[,+\-]", o)[0].strip()
    if re.match(r"^&[0-9A-Fa-f]{1,2}$", base) or base in ZPC: return 2
    return 3
def span_lines(k, n, fwd):
    """the lines of the n bytes after (or before) line k's instruction"""
    out, j, b = [], k, 0
    while b < n:
        j = j + 1 if fwd else j - 1
        if j < 0 or j >= len(P): break
        lab, mn, op, com = P[j]
        if mn is None: return None
        if mn == "": continue
        out.append(j); b += length(mn, op)
    return out
for k, (lab, mn, op, com) in enumerate(P):
    m = re.search(r"P%\s*([+-])\s*(\d+)", op or "") if mn else None
    if not m: continue
    n = int(m.group(2)) - (length(mn, op) if m.group(1) == "+" else 0)
    rng = span_lines(k, n, m.group(1) == "+")
    hit = [j for j in (rng if rng is not None else range(k + 1, k + 6)) if j in conv]
    if hit: errors.append("%d: %s %s spans converted line(s) %s" % (k + 1, mn, op, [j + 1 for j in hit]))
for m in re.finditer(r"\b([A-Za-z_]\w*)\s*\+\s*(\d+)", "\n".join(code_of(l) for l in lines)):
    lab, n = m.group(1), int(m.group(2))
    if lab in labels and n > 2 and P[labels[lab]][1]:
        k0 = labels[lab]
        rng = span_lines(k0 - 1, n, True)
        hit = [j for j in (rng if rng is not None else range(k0, k0 + n)) if j in conv]
        if hit: errors.append("%s+%d: the offset spans converted line(s) %s" % (lab, n, [j + 1 for j in hit]))
res = "\n".join(out)
res = re.sub(r"^(\s*)CPU 1\b", r"\1CPU 0", res, flags=re.M)
open(OUT, "w", encoding="latin-1").write(res)
if REPORT: open(REPORT, "w").write("\n".join(report) + "\n")
if errors:
    print("nmos.py: %s: %d site(s) to handle by hand:" % (SRC, len(errors)))
    for e in errors: print("  " + e)
    sys.exit(1)
print("nmos.py: %s: %d site(s) converted" % (SRC, len(report)))
