#!/usr/bin/env python3
# setcheck.py: check each blueprint set's renderer data, as built, against the
# tables of all types
#
# Each blueprint set carries the renderer's data for its own ships
# (elite-shipset.asm, gfx-setnorm.asm, gfx-settab.asm, gfx-setfaces.asm from
# faces.py): their unit normals with FC_NORMTAB in bank 4's slot, and their
# face and detail lists with FC_FACETAB and FC_DETTAB for bank 6's FCSLOT.
# For each of the sixteen D.MOx files and the docked code's set (in T.CODEH
# and T.CODEC), this reads which types the set has from its own XX21 (type 2
# with 24 vertices is the dodecahedron station, 32), follows the tables as
# the lighting and the frame layer do, and checks that every type's normals,
# face list and detail list are byte for byte the ones faces.py makes for
# that type (2-build-files/faces-master.json), and that every type the set
# does not have has none (0 in FC_NORMTAB), but the Cobra Mk III (11) in a
# set with only the pirate's (24), which has the pirate's (the escape pod's
# launch, ESCAPE, draws the pirate's with TYPE 11 in such a set). Exits 1 on
# any difference.

import json, os, re, sys

OUT = "3-assembled-output/"
master = {int(k): v for k, v in json.load(open("2-build-files/faces-master.json")).items()}
sy = {}
for m in re.finditer(r"'([^']+)':(\d+)", open(OUT + "docked-symbols.txt").read()):
    sy.setdefault(m.group(1), int(m.group(2)))
BPSLOT, NORMTAB, FCSLOT = sy["XX21"], sy["FC_NORMTAB_S"], sy["FC_FACETAB_S"]
DETTAB = FCSLOT + 2 * 33

bad = 0


def check(name, b4, b6):
    """b4(addr) reads bank 4 (the slot), b6(addr) the face lists' slot"""
    global bad
    w4 = lambda a: b4(a) | b4(a + 1) << 8
    w6 = lambda a: b6(a) | b6(a + 1) << 8
    types = []
    for t in range(1, 32):
        a = w4(BPSLOT + 2 * (t - 1))
        if a:
            types.append(32 if t == 2 and b4(a + 8) // 6 == 24 else t)
    def fail(msg):
        global bad
        print("setcheck: %s: %s" % (name, msg))
        bad += 1
    for t in range(1, 33):
        n = w4(NORMTAB + 2 * t)
        mt = t
        if t == 11 and t not in types and 24 in types:
            mt = 24                         # (ESCAPE: the pirate's)
        elif t not in types:
            if n:
                fail("type %d is not in the set but has normals" % t)
            continue
        m = master[mt]
        got = [b4(n + i) for i in range(len(m["normals"]))]
        if got != m["normals"]:
            fail("type %d's normals differ" % t)
        f, d = w6(FCSLOT + 2 * t), w6(DETTAB + 2 * t)
        if [b6(f + i) for i in range(len(m["faces"]))] != m["faces"]:
            fail("type %d's face list differs" % t)
        if [b6(d + i) for i in range(len(m["details"]))] != m["details"]:
            fail("type %d's detail list differs" % t)
    return types


for c in "ABCDEFGHIJKLMNOP":
    data = open(OUT + "D.MO%s.bin" % c, "rb").read()
    setf = 0xC000 - BPSLOT                   # (part 3: after the slot's pages)
    check("D.MO" + c, lambda a: data[a - BPSLOT], lambda a: data[setf + a - FCSLOT])
h = open(OUT + "T.CODEH.bin", "rb").read()
cimg = open(OUT + "T.CODEC.bin", "rb").read()
check("the docked code", lambda a: h[a - 0x8000], lambda a: cimg[a - FCSLOT])
print("setcheck: %s" % ("%d differences" % bad if bad else
      "every set's normals and face lists are the all-types tables'"))
sys.exit(1 if bad else 0)
