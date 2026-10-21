#!/usr/bin/env python3
# hotset.py: which blocks of the flight program run in flight, and how often,
# from a profile (6-harness/bprofile.mjs over the gate's run).
#
#   python3 6-harness/hotset.py PROFILE              (a profile of the original)
#   python3 6-harness/hotset.py PROFILE --port [--bank N]
#                                                    (a profile of the port: its
#                                                    home bank, ROMSEL N, 7 by
#                                                    default in jsbeeb)
#
# A block is a routine or table of the source, from its header to the next
# (as 2-build-files/streams.py splits the source). For each block of the
# flight program in main RAM (the original) or in the home bank (the port):
# its address and size, the cycles it took per flight iteration, the share
# of flight iterations in which any of its code ran ("touched"), and the
# number of times its first instruction ran per flight iteration ("calls":
# what a far call to it would cost, at about 110 cycles each). Prints the
# blocks in the source's order.
import json, re, sys

args = sys.argv[1:]
prof = json.load(open(args[0]))
port = "--port" in args
bank = 7
for i, a in enumerate(args):
    if a == "--bank":
        bank = int(args[i + 1])
src = "1-source-files/main-sources/elite-source-flight.asm"
syms = "3-assembled-output/flight-symbols.txt" if port else "4-reference-binaries/sth/flight-symbols.txt"
sy = {}
for m in re.finditer(r"'([^']+)':(\d+)L?", open(syms).read()):
    sy.setdefault(m.group(1), int(m.group(2)))
home = None
if port:
    home = set()
    for l in open("3-assembled-output/flight-banks.txt"):
        n, r = l.split()
        if r == "H":
            home.add(n)

blocks, cur = [], None
for l in open(src, encoding="latin-1"):
    m = re.match(r"^\\       Name: (.*)$", l)
    if m:
        cur = [m.group(1).strip(), "", [], ""]
        blocks.append(cur)
        continue
    m = re.match(r"^\\   Category: (.*)$", l)
    if m and cur:
        cur[1] = m.group(1).strip()
        continue
    m = re.match(r"^\\       Area: (.*)$", l)
    if m and cur:
        cur[3] = m.group(1).strip()
        continue
    m = re.match(r"^\.([A-Za-z_][\w%]*)", l)
    if m and cur:
        cur[2].append(m.group(1))
LO, HI, KEY = (0x8000, 0xB600, "b%d:" % bank) if port else (0x11E3, 0x5600, "m:")
rows = []
for name, cat, labs, area in blocks:
    if port and area:
        continue
    ads = [sy[x] for x in labs if x in sy and LO <= sy[x] < HI and (home is None or x in home)]
    if ads:
        rows.append([min(ads), name, cat])
rows.sort()
fl = prof["scenarios"]["flight"]
N = fl["iterations"]
pc = {}
for k, v in fl["pcs"].items():
    if k.startswith(KEY):
        a = int(k[len(KEY):], 16)
        pc[a] = (v, fl["iters"][k], fl.get("execs", {}).get(k, 0))
out = []
for i, (a, name, cat) in enumerate(rows):
    e = rows[i + 1][0] if i + 1 < len(rows) else HI
    cyc = sum(pc[x][0] for x in range(a, e) if x in pc)
    touched = max([pc[x][1] for x in range(a, e) if x in pc] or [0])
    calls = pc[a][2] if a in pc else 0
    out.append((a, e - a, name, cat, cyc / N, touched / N, calls / N))
print("%d flight iterations; %d bytes in all" % (N, sum(r[1] for r in out)))
print(" addr  size   cyc/it  touched  calls/it  block (category)")
for r in out:
    print("%5X %5d %8.1f %7.1f%% %8.2f  %s (%s)" % (r[0], r[1], r[4], 100 * r[5], r[6], r[2], r[3]))
