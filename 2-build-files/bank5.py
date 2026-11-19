#!/usr/bin/env python3
"""bank5.py: build bank 5, the filled renderer's rasteriser (docs/renderer.md).

    python3 2-build-files/bank5.py [BEEBASM]

Assembles 1-source-files/main-sources/gfx-bank5.asm (the BBC Master port's
rasteriser in NMOS 6502 code, gfx-raster*.asm, laid out for the Model B's
bank 5) and writes 3-assembled-output/BANK5.bin (from R_IMG%, the bank's
start, to &C000: the row runs and all), bank5-symbols.txt, and
bank5-entry.asm (the address of its jump table, RJT, for the glue's
trampolines: gfx-glue.asm, and R_IMG%, for the loader), appending the
assembly's report to compile.txt. The Makefile runs it twice: before the
flight code (whose layout needs RJT), and after it, when the flight code's
layout has made its cold 5 pass's tails (3-assembled-output/C5_r.bin, which
the bank's assembly takes in: bank5-c5.asm's C5BIN says whether they are
there yet).
"""
import glob, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BEEBASM = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('BEEBASM', 'beebasm')
SRC = '1-source-files/main-sources/gfx-bank5.asm'

subprocess.run([sys.executable, '2-build-files/streams.py', 'passes'], check=True)   # (the renderer's
                                   # pass copies, which the bank's assembly INCLUDEs)
c5 = glob.glob('3-assembled-output/C5_*.bin')   # (the flight code's cold 5 pass, in the
open('3-assembled-output/bank5-c5.asm', 'w').write(   # run pages' tails: once its layout
    '\\ bank5-c5.asm -- written by 2-build-files/bank5.py; do not edit.\n\n'   # has made them,
    'C5BIN = %s\n' % ('TRUE' if c5 else 'FALSE'))                       # gfx-bank5.asm)
r = subprocess.run([BEEBASM, '-i', SRC, '-v'], capture_output=True, text=True)
out = r.stdout + r.stderr
if r.returncode or 'error' in out.lower():
    print('\n'.join(l for l in out.splitlines() if 'error' in l.lower() or 'assert' in l.lower())[-3000:])
    sys.exit('bank5: assembly failed')
open('3-assembled-output/compile.txt', 'a').write(out)
print('\n'.join(l for l in out.splitlines() if l.startswith('Bank 5')))
d = subprocess.run([BEEBASM, '-i', SRC, '-d'], capture_output=True, text=True, check=True)
open('3-assembled-output/bank5-symbols.txt', 'w').write(
    '\n'.join(l for l in d.stdout.splitlines() if l.startswith('[{')) + '\n')
rjt = re.search(r"'RJT':(\d+)", d.stdout)   # bank 5's jump table, for the glue's
img = re.search(r"'R_IMAGE':(\d+)", d.stdout)   # trampolines (gfx-glue.asm), and
open('3-assembled-output/bank5-entry.asm', 'w').write(   # where its image goes (the loader)
    '\\ bank5-entry.asm -- written by 2-build-files/bank5.py; do not edit.\n\n'
    'RJT = &%04X             \\ bank 5\'s jump table (gfx-bank5.asm)\n'
    'R_IMG%% = &%04X          \\ bank 5\'s image, BANK5.bin, from there to &C000\n' % (int(rjt.group(1)), int(img.group(1))))
