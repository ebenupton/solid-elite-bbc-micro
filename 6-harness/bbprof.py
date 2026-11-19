#!/usr/bin/env python3
# bbprof.py: a bbench.mjs --prof file summed by label, per scene.
#
#   python3 6-harness/bbprof.py PROF.json [--scene s,t] [--top 40]
#                                         [--label L1,L2 ...] [--stubs 1]
#
# Each PC is given to the nearest label at or below it in what was mapped
# there: main RAM (the flight program's, the loader's and the glue's
# labels), bank 4 or 7 (the flight program's labels of that role,
# flight-banks.txt), bank 5 (bank5-symbols.txt) or bank 6
# (bank6-symbols.txt and the flight code's cold 6 pass). For each label: the
# cycles per iteration run from it to the next label, and its entries (the
# times its own first instruction ran) per iteration. --label prints only
# those labels, in every scene (a label shares its line with the others at
# its address: L matches any of them). --stubs 1 prints instead each far-call
# stub's calls per iteration (a label whose code is a JSR to farC, farC6 or
# farH, in the flight program's images and bank 6's), by scene.
import json, os, re, sys

args = sys.argv[1:]
prof = json.load(open(args[0]))
opt = {}
for i, a in enumerate(args):
    if a.startswith('--') and i + 1 < len(args):
        opt[a[2:]] = args[i + 1]
OUT = os.path.dirname(prof['build'])

def syms(name):
    p = os.path.join(OUT, name + '-symbols.txt')
    d = {}
    for m in re.finditer(r"'([^']+)':(\d+)L?", open(p).read()):
        d.setdefault(m.group(1), int(m.group(2)))
    return d

roles = {}
for l in open(os.path.join(OUT, 'flight-banks.txt')):
    f = l.split()
    if len(f) == 2:
        roles[f[0]] = f[1]
bk = prof['banks']
rolebank = {'H': bk.get('BANK4'), 'C': bk.get('BANK7'), '6': bk.get('BANK6'), '5': bk.get('BANK5')}
maps = {}          # map key -> sorted [(addr, label)]
def add(m, a, n):
    maps.setdefault(m, []).append((a, n))
skip = re.compile(r'^(CODE|LOAD)')
for n, a in syms('flight').items():
    if skip.match(n):
        continue
    if a < 0x8000:
        add('m', a, n)
    elif a < 0xC000:
        r = roles.get(n, 'H')
        if rolebank.get(r) is not None:
            add('b%d' % rolebank[r], a, n)
for n, a in syms('loader').items():
    if a < 0x8000 and not skip.match(n):
        add('m', a, n)
for n, a in syms('bank5').items():
    if 0x8000 <= a < 0xC000:
        add('b%d' % bk['BANK5'], a, n)
for n, a in syms('bank6').items():
    if 0x8000 <= a < 0xC000:
        add('b%d' % bk['BANK6'], a, n)
for m in maps:
    d = {}
    for a, n in maps[m]:
        if n not in d.get(a, '').split('/'):
            d[a] = d[a] + '/' + n if a in d else n
    maps[m] = sorted(d.items())

import bisect
keys = {m: [a for a, _ in v] for m, v in maps.items()}
def label(k):
    m, a = k.split(':')
    a = int(a, 16)
    if m not in maps:
        return k
    i = bisect.bisect_right(keys[m], a) - 1
    if i < 0:
        return k
    return maps[m][i][1]

want = opt.get('label', '').split(',') if 'label' in opt else None
img = {}           # map key -> (base, bytes)
bj = json.load(open(prof['build']))
for f, role, base in bj['flight']['images']:
    m = 'm' if role == 'm' else 'b%d' % rolebank[role]
    img.setdefault(m, []).append((int(base, 16), open(os.path.join(OUT, f), 'rb').read()))
img.setdefault('b%d' % bk['BANK6'], []).append((0x8000, open(os.path.join(OUT, 'BANK6.bin'), 'rb').read()))
ld = syms('loader')
far = {ld[n]: n for n in ('farC', 'farC6', 'farC5', 'farH', 'farCj', 'farHj') if n in ld}
def stubof(m, a):
    for base, data in img.get(m, []):
        o = a - base
        if 0 <= o and o + 3 <= len(data) and data[o] == 0x20:
            t = data[o + 1] | data[o + 2] << 8
            if t in far:
                return far[t]
    return None
scenes = opt['scene'].split(',') if 'scene' in opt else list(prof['scenes'])
top = int(opt.get('top', 40))
for s in scenes:
    sc = prof['scenes'][s]
    cyc, ent = {}, {}
    for k, c in sc['cycles'].items():
        n = label(k)
        cyc[n] = cyc.get(n, 0) + c
        m, a = k.split(':')
        ad = int(a, 16)
        lm = maps.get(m)
        if lm:
            i = bisect.bisect_right(keys[m], ad) - 1
            if i >= 0 and lm[i][0] == ad:
                ent[n] = ent.get(n, 0) + sc['execs'][k]
    print('%s: %d cycles/iteration' % (s, sc['cyclesPerIteration']))
    if 'stubs' in opt:
        rows = []
        for k, e in sc['execs'].items():
            m, a = k.split(':')
            st = stubof(m, int(a, 16))
            if st:
                rows.append((e, label(k), st, k))
        for e, n, st, k in sorted(rows, reverse=True)[:top]:
            print('  %-24s %-6s %-10s %6.1f calls' % (n, st, k, e))
        continue
    rows = sorted(cyc.items(), key=lambda x: -x[1])
    if want is not None:
        rows = [(n, c) for n, c in cyc.items() if set(n.split('/')) & set(want)]
    else:
        rows = rows[:top]
    for n, c in rows:
        print('  %-14s %9.0f cycles %8.1f entries' % (n, c, ent.get(n, 0)))
