#!/usr/bin/env python3
"""panel.py: the dashboard's image for the port's four-colour screen.

    python3 2-build-files/panel.py [outdir]     (default 3-assembled-output)

Port (docs/renderer.md): the original's dashboard (1-source-files/images/
P.DIALS.bin, seven mode 5 character rows of 256 bytes: 128 pixels of four
colours across) becomes P.PANEL.bin, seven rows of MODE 1's 512 bytes (256
pixels across), loaded to PANEL% (&7000): each mode 5 pixel becomes two
MODE 1 pixels, so the dashboard keeps its shape, and its colours become the
screen's: the original's red (1) magenta, yellow (2) yellow and its third
colour (3) cyan. The dashboard's routines draw at the same doubled scale
(MODE 5 byte b becomes MODE 1 bytes EXPL(b) and EXPR(b), which this also
writes, as elite-panel-tables.asm, for them).
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "3-assembled-output")
MAP = [0, 2, 3, 1]                     # original logical colour -> CMYK logical colour

def pix5(b, p):
    """mode 5 (and MODE 1) pixel p (0 = left) of byte b: bits 7-p and 3-p"""
    return ((b >> (7 - p)) & 1) << 1 | ((b >> (3 - p)) & 1)

def byte1(ps):
    """the MODE 1 byte of four pixel colours"""
    v = 0
    for p, c in enumerate(ps):
        v |= ((c >> 1) & 1) << (7 - p) | (c & 1) << (3 - p)
    return v

def expand(b):
    ps = [MAP[pix5(b, p)] for p in range(4)]
    return byte1([ps[0], ps[0], ps[1], ps[1]]), byte1([ps[2], ps[2], ps[3], ps[3]])

src = open(os.path.join(ROOT, "1-source-files/images/P.DIALS.bin"), "rb").read()
img = bytearray(7 * 512)
for row in range(7):
    for col in range(32):
        for line in range(8):
            b = src[row * 256 + col * 8 + line]
            l, r = expand(b)
            img[row * 512 + col * 16 + line] = l
            img[row * 512 + col * 16 + 8 + line] = r
open(os.path.join(out, "P.PANEL.bin"), "wb").write(img)
with open(os.path.join(out, "elite-panel-tables.asm"), "w") as f:
    f.write("\\ elite-panel-tables.asm, written by 2-build-files/panel.py: the dashboard's\n"
            "\\ mode 5 bytes as pairs of MODE 1 bytes (left and right), in CMYK colours\n\n")
    for name, k in (("EXPL", 0), ("EXPR", 1)):
        f.write(".%s\n\n" % name)
        for i in range(0, 256, 8):
            f.write(" EQUB " + ", ".join("&%02X" % expand(b)[k] for b in range(i, i + 8)) + "\n")
        f.write("\n")
print("panel.py: P.PANEL.bin (%d bytes), elite-panel-tables.asm" % len(img))
