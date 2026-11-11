#!/usr/bin/env python3
"""bank6.py: build bank 6, the filled renderer's frame layer (docs/renderer.md).

    python3 2-build-files/bank6.py [BEEBASM]

Port (Model B): run after the flight program is assembled. The frame layer
reads the game's variables where the flight program has them (its zero page
and main RAM workspace, the same in the docked program, which this checks)
and calls bank 5 through the trampolines in main RAM, which page the bank
whose number the loader keeps in BANK5 (likewise GCALL and BANK6), and the
game's code through the far calls (farC for the disc layer in bank 7, farH
for the entries at S% + 16 and S% + 19 in bank 4): so this writes those
addresses, and the game's constants it uses, into
3-assembled-output/bank6-game.asm, from flight-symbols.txt,
docked-symbols.txt, loader-symbols.txt and elite-source-flight.asm, then
assembles gfx-bank6.asm. Writes 3-assembled-output/BANK6.bin (16K, at &8000),
GLUE.bin (the main RAM glue, at GLUE%) and bank6-symbols.txt, prints bank
6's usage and appends the assembly's report to compile.txt.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BEEBASM = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('BEEBASM', 'beebasm')
MS = '1-source-files/main-sources'
OUT = '3-assembled-output'

# the game's variables the frame layer reads (all in main RAM)
VARS = ['INWK', 'XX2', 'XX3', 'XX4', 'XX16', 'XX0', 'XX19', 'XX20', 'INF', 'XSAV', 'RAND', 'Q', 'U',
        'TGT', 'CNT', 'V', 'K', 'K3', 'K4', 'K5', 'K6', 'TYPE', 'X1', 'Y1', 'X2', 'Y2', 'ZZ', 'QQ11',
        'FRIN', 'K%', 'LASX', 'LASY', 'XC', 'YC', 'VIEW', 'QQ12']
# what only the flight code's frame reaches: the sun near the planet (S_SUN,
# gfx-ssun.asm, run only when the flight code's hframe calls F_FRAME) and the
# disc layer's painter in its bank 7 (gfx-raster_disc.asm)
FLIGHT = ['MJ', 'MCNT', 'ALPHA', 'BETA', 'DELTA', 'P', 'R', 'S', 'T', 'K2', 'FIST', 'QQ15',
          'MV40', 'ZINF', 'DP_BEGIN', 'DP_ROWS', 'DP_DISC2']
# and its constants
CONSTS = ['NOST', 'NOSH', 'NI%', 'SST', 'PLT', 'X', 'Y']


def symbols(name):
    t = open(os.path.join(OUT, name + '-symbols.txt')).read()
    return {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", t)}


flight, docked, loader = symbols('flight'), symbols('docked'), symbols('loader')
L = ['\\ bank6-game.asm -- written by 2-build-files/bank6.py; do not edit.', '']
for v in VARS:
    a = flight[v]
    assert docked.get(v) == a, '%s is at &%04X in the flight program, %r in the docked' % (v, a, docked.get(v))
    assert a < 0x1000 or 0x7F00 <= a < 0x8000, '%s (&%04X) is not in main RAM below the screen buffers' % (v, a)
    L.append('%-8s = &%04X' % (v, a))
for c in FLIGHT:   # S_SUN's (flight code only) and the disc layer's painter, in the
    a = flight[c]  # flight code's cold bank
    L.append('%-8s = &%04X' % (c, a))
for b in ('BANK5', 'BANK6', 'farC', 'farH'):
    L.append('%-8s = &%04X' % (b, loader[b]))
src = open(os.path.join(MS, 'elite-source-flight.asm'), encoding='latin-1').read()
for c in CONSTS:
    m = re.search(r'^\s*%s\s*=\s*(\d+)\s' % re.escape(c), src, re.M)
    assert m, c
    L.append('%-8s = %s' % (c, m.group(1)))
open(os.path.join(OUT, 'bank6-game.asm'), 'w').write('\n'.join(L) + '\n')

subprocess.run([sys.executable, '2-build-files/streams.py', 'passes'], check=True)   # (the renderer's
                                   # pass copies, which the bank's assembly INCLUDEs)
r = subprocess.run([BEEBASM, '-i', os.path.join(MS, 'gfx-bank6.asm'), '-v'], capture_output=True, text=True)
out = r.stdout + r.stderr
if r.returncode or re.search(r'error|assert', out, re.I):
    print('\n'.join(l for l in out.splitlines() if l.startswith('Bank 6') or re.search(r'error|assert', l, re.I))[-3000:])
    sys.exit('bank6: assembly failed')
open(os.path.join(OUT, 'compile.txt'), 'a').write(out)
print('\n'.join(l for l in out.splitlines() if l.startswith('Bank 6') or l.startswith('Glue')))
d = subprocess.run([BEEBASM, '-i', os.path.join(MS, 'gfx-bank6.asm'), '-d'],
                   capture_output=True, text=True, check=True)
open(os.path.join(OUT, 'bank6-symbols.txt'), 'w').write(
    '\n'.join(l for l in d.stdout.splitlines() if l.startswith('[{')) + '\n')
