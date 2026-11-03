#!/usr/bin/env python3
"""bank5.py: build bank 5, the filled renderer's rasteriser (docs/renderer.md).

    python3 2-build-files/bank5.py [BEEBASM]

Assembles 1-source-files/main-sources/gfx-bank5.asm (the BBC Master port's
rasteriser in NMOS 6502 code, gfx-raster*.asm, laid out for the Model B's
bank 5) and writes 3-assembled-output/BANK5.bin (16K, at &8000) and
bank5-symbols.txt, appending the assembly's report to compile.txt.
"""
import os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BEEBASM = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('BEEBASM', 'beebasm')
SRC = '1-source-files/main-sources/gfx-bank5.asm'

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
