#!/usr/bin/env python3
"""bankf.py: build bank F, the filled renderer's frame layer (docs/renderer.md).

    python3 2-build-files/bankf.py [BEEBASM]

Port (Model B): run after the flight program is assembled. The frame layer
reads the game's variables where the flight program has them (its zero page
and main RAM workspace, the same in the docked program, which this checks)
and calls bank R through the trampolines in main RAM, which page the bank
whose number the loader keeps in BANKR (likewise GCALL and BANKF): so this
writes those addresses, and the game's constants it uses, into
3-assembled-output/bankf-game.asm, from flight-symbols.txt,
docked-symbols.txt, loader-symbols.txt and elite-source-flight.asm, then
assembles gfx-bankf.asm. Writes 3-assembled-output/F.bin (16K, at &8000),
GLUE.bin (the main RAM glue, at GLUE%) and bankf-symbols.txt, prints bank
F's usage and appends the assembly's report to compile.txt.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BEEBASM = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('BEEBASM', 'beebasm')
MS = '1-source-files/main-sources'
OUT = '3-assembled-output'

# the game's variables the frame layer reads (all in main RAM)
VARS = ['INWK', 'XX2', 'XX3', 'XX4', 'K', 'K3', 'K4', 'K5', 'K6', 'TYPE', 'X1', 'Y1', 'X2', 'Y2',
        'ZZ', 'QQ11', 'FRIN', 'K%', 'ALPHA', 'BETA', 'LASX', 'LASY', 'XC', 'YC', 'VIEW']
# and its constants
CONSTS = ['NOST', 'NI%', 'SST', 'PLT']


def symbols(name):
    t = open(os.path.join(OUT, name + '-symbols.txt')).read()
    return {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", t)}


flight, docked, loader = symbols('flight'), symbols('docked'), symbols('loader')
L = ['\\ bankf-game.asm -- written by 2-build-files/bankf.py; do not edit.', '']
for v in VARS:
    a = flight[v]
    assert docked.get(v) == a, '%s is at &%04X in the flight program, %r in the docked' % (v, a, docked.get(v))
    assert a < 0x1000 or 0x7F00 <= a < 0x8000, '%s (&%04X) is not in main RAM below the screen buffers' % (v, a)
    L.append('%-8s = &%04X' % (v, a))
for c in ('DL_FRAME',):   # the disc layer, in the flight code's cold bank
    L.append('%-8s = &%04X' % (c, flight[c]))
for b in ('BANKR', 'BANKF', 'farC'):
    L.append('%-8s = &%04X' % (b, loader[b]))
src = open(os.path.join(MS, 'elite-source-flight.asm'), encoding='latin-1').read()
for c in CONSTS:
    m = re.search(r'^\s*%s\s*=\s*(\d+)\s' % re.escape(c), src, re.M)
    assert m, c
    L.append('%-8s = %s' % (c, m.group(1)))
open(os.path.join(OUT, 'bankf-game.asm'), 'w').write('\n'.join(L) + '\n')

r = subprocess.run([BEEBASM, '-i', os.path.join(MS, 'gfx-bankf.asm'), '-v'], capture_output=True, text=True)
out = r.stdout + r.stderr
if r.returncode or re.search(r'error|assert', out, re.I):
    print('\n'.join(l for l in out.splitlines() if re.search(r'error|assert', l, re.I))[-3000:])
    sys.exit('bankf: assembly failed')
open(os.path.join(OUT, 'compile.txt'), 'a').write(out)
print('\n'.join(l for l in out.splitlines() if l.startswith('Bank F') or l.startswith('Glue')))
d = subprocess.run([BEEBASM, '-i', os.path.join(MS, 'gfx-bankf.asm'), '-d'],
                   capture_output=True, text=True, check=True)
open(os.path.join(OUT, 'bankf-symbols.txt'), 'w').write(
    '\n'.join(l for l in d.stdout.splitlines() if l.startswith('[{')) + '\n')
