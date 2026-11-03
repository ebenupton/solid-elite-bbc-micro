#!/usr/bin/env python3
# ovlcheck.py: check that no overlay can be replaced while its code is running
#
# The flight code's overlays ("Area: overlay N", streams.py) share bank 7's
# overlay region, and a call into overlay N loads N over whatever overlay is
# there (ovf1 in the flight source). So no code reachable from overlay N's
# routines (through calls, jumps, branches and falls into the next routine,
# in any pass) may call into another overlay: it would return into code that
# is no longer there. Routines that never return (NORETURN: the main loop's
# restarts) end a path. Exits 1 with the paths that break this.

import collections, re, sys

SRC = "1-source-files/main-sources/elite-source-flight.asm"
NORETURN = {"DEATH2", "DEATH", "RSHIPS", "INBAY", "DOENTRY", "FRCE", "TT100", "MLOOP",
            "GOIN", "BEGIN", "TT170"}
NOTCODE = re.compile(r"(\.|SKIP|EQU|ORG|ASSERT|PRINT|IF|ELSE|ENDIF|INCLUDE|SAVE|CLEAR|GUARD)|\S+\s*=")

src = open(SRC, encoding="latin-1").read().split("\n")
blocks, owner, cur = [], {}, None
for line in src:
    m = re.match(r"\\\s+Name: (.*)", line)
    if m:
        cur = {"name": m.group(1).strip(), "ovl": None, "calls": set(), "last": ""}
        blocks.append(cur)
        continue
    if cur is None:
        continue
    m = re.match(r"\\\s+Area: .*\boverlay (\d)", line)
    if m:
        cur["ovl"] = m.group(1)
    code = line.split("\\")[0].strip()
    for m in re.finditer(r"(?:^|:)\s*\.([A-Za-z_][A-Za-z0-9_%]*)", code):
        owner[m.group(1)] = cur["name"]
    for m in re.finditer(r"\b(?:JSR|JMP|B[A-Z]{2})\s+([A-Za-z_][A-Za-z0-9_%]*)", code):
        if m.group(1) not in NORETURN:
            cur["calls"].add(m.group(1))
    if code and not NOTCODE.match(code):
        cur["last"] = code.split(":")[-1].strip()

ovl = {b["name"]: b["ovl"] for b in blocks}
calls = collections.defaultdict(set)
for a, b in zip(blocks, blocks[1:]):
    for c in a["calls"]:
        if owner.get(c, a["name"]) != a["name"]:
            calls[a["name"]].add(owner[c])
    if a["last"] and not re.match(r"(JMP|RTS|RTI|BRK)\b", a["last"]):
        calls[a["name"]].add(b["name"])         # (falls into the next routine)

bad = 0
for n in sorted({o for o in ovl.values() if o}):
    seen = {b for b, o in ovl.items() if o == n}
    stack, via = list(seen), {b: b for b in seen}
    while stack:
        x = stack.pop()
        for y in calls[x]:
            if ovl[y] not in (None, n):
                print("ovlcheck: %s (reached from overlay %s's %s) calls %s in overlay %s"
                      % (x, n, via[x], y, ovl[y]))
                bad += 1
            elif y not in seen:
                seen.add(y)
                via[y] = via[x]
                stack.append(y)
print("ovlcheck: %s" % ("%d overlay conflicts" % bad if bad else "no overlay calls another"))
sys.exit(1 if bad else 0)
