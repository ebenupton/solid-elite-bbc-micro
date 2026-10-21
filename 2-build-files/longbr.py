#!/usr/bin/env python3
"""longbr.py: make out-of-range branches long, for the Model B host's NMOS
copies of the Master port's sources (NMOS code is longer, so some branches
no longer reach).

    python3 tube/tools/longbr.py FILE LINE [LINE ...]

Rewrites each given line's branch  Bxx target  as  B(not xx) P%+5 : JMP target
(the line's label, if any, stays on the first instruction). Refuses a line
that a P%+n or P%-n branch nearby may span (the caller fixes that by hand).
"""
import re, sys
INV = {"BEQ": "BNE", "BNE": "BEQ", "BCC": "BCS", "BCS": "BCC", "BMI": "BPL", "BPL": "BMI", "BVC": "BVS", "BVS": "BVC"}
f = sys.argv[1]
lines = open(f, encoding="latin-1").read().split("\n")
for ln in sorted(set(int(x) for x in sys.argv[2:]), reverse=True):
    i = ln - 1
    l = lines[i]
    m = re.match(r"^(\s*(?:\.\^?[A-Za-z_]\w*\s+)?)(B(?:EQ|NE|CC|CS|MI|PL|VC|VS))\s+([^\s\\]+)(.*)$", l)
    if not m:
        if re.match(r"^\s*BRA\b", l): sys.exit("longbr.py: %s:%d: BRA (nmos.py makes those JMP)" % (f, ln))
        sys.exit("longbr.py: %s:%d: no branch: %r" % (f, ln, l))
    pre, op, tgt, rest = m.groups()
    if "P%" in tgt: sys.exit("longbr.py: %s:%d: a P%% branch: by hand" % (f, ln))
    for j in range(max(0, i - 12), i):
        if re.search(r"\bB\w\w\s+P%\s*\+\s*\d+", lines[j]): sys.exit("longbr.py: %s:%d: a P%%+n branch at line %d may span it: by hand" % (f, ln, j + 1))
    lines[i] = "%s%s P%%+5%s\n JMP %s" % (pre, INV[op], rest, tgt)
open(f, "w", encoding="latin-1").write("\n".join(lines))
