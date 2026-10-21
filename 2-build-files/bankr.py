#!/usr/bin/env python3
"""bankr.py: build bank R, the filled renderer's rasteriser (docs/renderer.md).

    python3 2-build-files/bankr.py [BEEBASM]

Port (Model B), after the Tube branch's tube/build.sh (its Model B host's
bank P): the rasteriser's sources (1-source-files/main-sources/gfx-raster*.asm,
65C02, the BBC Master port's) are made NMOS by 2-build-files/nmos.py into
3-assembled-output/nmos/, with the hand fixes it asks for (the same as the
Tube's); then gfx-bankr.asm is assembled, and each branch that the longer
NMOS code puts out of range is made long (2-build-files/longbr.py, in the
converted copy) until it assembles. Writes 3-assembled-output/R.bin (16K, at
&8000) and bankr-symbols.txt, and appends the assembly's report to
compile.txt.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BEEBASM = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('BEEBASM', 'beebasm')
MS = '1-source-files/main-sources'
OUT = '3-assembled-output/nmos'
os.makedirs(OUT, exist_ok=True)

# (file, --sub fixes): as tube/build.sh converts them
FILES = [
    ('gfx-raster.asm', []),
    ('gfx-raster_arith.asm', []),
    ('gfx-raster_pset.asm', []),
    ('gfx-raster_poly.asm', []),
    ('gfx-raster_polyb.asm', []),
    ('gfx-raster_line.asm', []),
    ('gfx-raster_lineb.asm', []),
    ('gfx-raster_rep.asm', []),
    ('gfx-raster_lcold.asm', [
        "  PHX\n  LDX l_x0=  STX R_NTMPX               \\ (NMOS: PHX, A live)\n  LDX l_x0",
        "  PLX\n  DEC l_n=  LDX R_NTMPX\n  DEC l_n"]),
]
# (the converted code's temporaries are in bank R, gfx-rws.asm's R_NTMP and
# R_NTMPY, not in zero page as the Tube's at &E5-&E7)
for f, subs in FILES:
    cmd = [sys.executable, '2-build-files/nmos.py', os.path.join(MS, f), os.path.join(OUT, f),
           '--report', os.path.join(OUT, f.replace('.asm', '.txt')), '--tmp', 'R_NTMP', '--tmpy', 'R_NTMPY']
    for s in subs:
        cmd += ['--sub', s]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit('bankr: %s%s' % (r.stdout, r.stderr))

for k in range(200):
    r = subprocess.run([BEEBASM, '-i', os.path.join(MS, 'gfx-bankr.asm'), '-v'], capture_output=True, text=True)
    out = r.stdout + r.stderr
    if r.returncode == 0 and 'error' not in out.lower():
        break
    m = re.search(r'^(\S+):(\d+): error: Branch out of range', out, re.M)
    if not m or not m.group(1).startswith(OUT):
        print('\n'.join(l for l in out.splitlines() if 'error' in l.lower() or 'assert' in l.lower())[-3000:])
        sys.exit('bankr: assembly failed')
    subprocess.run([sys.executable, '2-build-files/longbr.py', m.group(1), m.group(2)], check=True)
else:
    sys.exit('bankr: too many long branches')
open('3-assembled-output/compile.txt', 'a').write(out)
print('\n'.join(l for l in out.splitlines() if l.startswith('Bank R')))
d = subprocess.run([BEEBASM, '-i', os.path.join(MS, 'gfx-bankr.asm'), '-d'],
                   capture_output=True, text=True, check=True)  # (the labels, as the Makefile's
open('3-assembled-output/bankr-symbols.txt', 'w').write(    # beebasm -d for the programs)
    '\n'.join(l for l in d.stdout.splitlines() if l.startswith('[{')) + '\n')
