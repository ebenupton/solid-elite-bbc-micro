#!/usr/bin/env python3
# hotset.py: which blocks of the flight program run in flight, and how often,
# from a profile of the original (6-harness/bprofile.mjs over the gate's run).
#
#   python3 6-harness/hotset.py PROFILE [--src elite-source-flight.asm]
#                                       [--syms flight-symbols.txt] [--all]
#
# A block is a routine or table of the source, from its header to the next
# (as 2-build-files/streams.py splits the source). For each block of the
# flight program: its address and size in the original, the cycles it took
# per flight iteration, and the share of flight iterations in which any of
# its code ran ("touched"). The hot blocks (touched in at least 1% of flight
# iterations, or taking at least 20 cycles per iteration) are the ones the
# home bank holds; the rest are cold. Prints the blocks in the source's
# order, with totals.
import json, re, sys

args = sys.argv[1:]
prof = json.load(open(args[0]))
src = "1-source-files/main-sources/elite-source-flight.asm"
syms = "4-reference-binaries/sth/flight-symbols.txt"
show_all = "--all" in args
for i, a in enumerate(args):
    if a == "--src": src = args[i + 1]
    if a == "--syms": syms = args[i + 1]
sy = {}
for m in re.finditer(r"'([^']+)':(\d+)L?", open(syms).read()):
    sy.setdefault(m.group(1), int(m.group(2)))

# blocks: (name, category, [labels])
blocks = []
cur = None
for l in open(src, encoding="latin-1"):
    m = re.match(r"^\\       Name: (.*)$", l)
    if m:
        cur = [m.group(1).strip(), "", []]
        blocks.append(cur)
        continue
    m = re.match(r"^\\   Category: (.*)$", l)
    if m and cur:
        cur[1] = m.group(1).strip()
        continue
    m = re.match(r"^\.([A-Za-z_][\w%]*)", l)
    if m and cur:
        cur[2].append(m.group(1))
CODE_LO, CODE_HI = 0x11E3, 0x5600
rows = []
for name, cat, labs in blocks:
    ads = [sy[x] for x in labs if x in sy and CODE_LO <= sy[x] < CODE_HI]
    if ads:
        rows.append([min(ads), name, cat])
rows.sort()
fl = prof["scenarios"]["flight"]
N = fl["iterations"]
pc = {}
for k, v in fl["pcs"].items():
    if k.startswith("m:"):
        pc[int(k[2:], 16)] = (v, fl["iters"][k])
out = []
for i, (a, name, cat) in enumerate(rows):
    e = rows[i + 1][0] if i + 1 < len(rows) else CODE_HI
    cyc = sum(pc[x][0] for x in range(a, e) if x in pc)
    touched = max([pc[x][1] for x in range(a, e) if x in pc] or [0])
    out.append((a, e - a, name, cat, cyc / N, touched / N))
hot = lambda r: r[5] >= 0.01 or r[4] >= 20
th = sum(r[1] for r in out if hot(r))
tc = sum(r[1] for r in out if not hot(r))
print("%d flight iterations; %d bytes hot, %d bytes cold, %d in all" % (N, th, tc, th + tc))
print(" addr  size   cyc/it  touched  hot  block (category)")
for r in out:
    if show_all or True:
        print("%5X %5d %8.1f %7.1f%%  %s  %s (%s)" % (r[0], r[1], r[4], 100 * r[5], "H" if hot(r) else ".", r[2], r[3]))
