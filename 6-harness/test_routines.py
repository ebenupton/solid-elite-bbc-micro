#!/usr/bin/env python3
"""Exhaustive checks of the speed-ups' routines against the original's, on py65.

    python3 6-harness/test_routines.py [--quick] [NAME ...]

Each test calls one routine of the flight code with given inputs, in the
original (4-reference-binaries/sth: D.CODE.unprot.bin at &11E3, with its
symbols) and in the port (3-assembled-output: the flight code's home image
D.CODEH.bin at &8000, with its symbols, and the quarter-square tables that
the loader builds in main RAM), and compares everything the test names as
an output: the registers, the flags and the variables. The game's gate
(verify.sh) compares the game state at every main-loop iteration; this
compares one routine's results for every input, or for a large random
sample, so a speed-up's exactness is shown before the gate runs.

Exit status 0 only if every test passes. --quick samples fewer inputs.
"""
import os, random, re, sys
from py65.devices.mpu6502 import MPU

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def syms(path):
    out = {}
    for m in re.finditer(r"'([^']+)':(\d+)", open(path).read()):
        out.setdefault(m.group(1), int(m.group(2)))
    return out


def map_constants():
    """the port's memory map constants (elite-map.asm)"""
    out = {}
    for l in open(os.path.join(REPO, "1-source-files/main-sources/elite-map.asm")):
        m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*&([0-9A-Fa-f]+)", l)
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


def flight_constants(path):
    """the flight source's constants that are needed here (by value)"""
    out = {}
    for l in open(path, encoding="latin-1"):
        m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*(\d+)\s", l)
        if m:
            out.setdefault(m.group(1), int(m.group(2)))
    return out


class PagedMemory:
    """the port's memory as the CPU sees it: main RAM, with one of the
    sideways RAM banks at &8000-&BFFF, paged by a write to ROMSEL (&FE30), as
    the far calls do"""

    def __init__(self, main, banks, cur):
        self.main, self.banks, self.cur = main, banks, cur

    def __getitem__(self, a):
        if isinstance(a, slice):
            return self.main[a]
        if 0x8000 <= a < 0xC000:
            return self.banks[self.cur][a - 0x8000]
        return self.main[a]

    def __setitem__(self, a, v):
        if 0x8000 <= a < 0xC000:
            self.banks[self.cur][a - 0x8000] = v
        else:
            if a == 0xFE30:
                self.cur = v & 15
            self.main[a] = v

    def __len__(self):
        return 65536


class Machine:
    """a 64K py65 machine with one build of the flight code loaded"""

    def __init__(self, name, sy, images, extra=()):
        self.name, self.sy = name, sy
        self.base = [0] * 65536
        for addr, data in images:
            self.base[addr:addr + len(data)] = list(data)
        for addr, data in extra:
            self.base[addr:addr + len(data)] = list(data)
        self.mpu = MPU()

    def call(self, routine, a=0, x=0, y=0, c=0, mem=None, limit=200000):
        mpu = self.mpu
        if getattr(self, "banks", None):          # (the port: main RAM and its banks)
            bank = self.cold_bank if routine in self.cold_labels else self.home_bank
            mpu.memory = PagedMemory(list(self.base), {k: list(v) for k, v in self.banks.items()}, bank)
            mpu.memory.main[0xF4] = bank
        else:
            mpu.memory = list(self.base)
        for k, v in (mem or {}).items():
            mpu.memory[self.addr(k)] = v & 255
        mpu.a, mpu.x, mpu.y = a & 255, x & 255, y & 255
        mpu.p = 0x20 | (1 if c else 0)
        mpu.sp = 0xFF
        ret = 0xFFF0                              # (an RTS from the routine lands here)
        mpu.memory[0x1FF] = (ret - 1) >> 8
        mpu.memory[0x1FE] = (ret - 1) & 255
        mpu.sp = 0xFD
        mpu.pc = self.sy[routine]
        n = 0
        while mpu.pc != ret:
            mpu.step()
            n += 1
            if n > limit:
                raise RuntimeError("%s %s: no return" % (self.name, routine))
        return n

    def addr(self, k):
        if isinstance(k, int):
            return k
        if k.startswith("&"):
            return int(k[1:], 16)
        base, _, off = k.partition("+")
        return self.sy[base] + (int(off) if off else 0)

    def out(self, names):
        mpu = self.mpu
        r = {"A": mpu.a, "X": mpu.x, "Y": mpu.y,
             "N": mpu.p >> 7 & 1, "V": mpu.p >> 6 & 1, "Z": mpu.p >> 1 & 1, "C": mpu.p & 1}
        out = {}
        for n in names:
            if n in r:
                out[n] = r[n]
            elif n == "SCREENPIX":                # (the space view's lit pixels, whatever the format)
                out[n] = self.lit()
            elif "*" in n:                        # (NAME*N: N bytes from NAME, as one output)
                k, _, c = n.partition("*")
                a = self.addr(k)
                out[n] = tuple(mpu.memory[a:a + int(c)])
            else:
                out[n] = mpu.memory[self.addr(n)]
        return out


def _lit(self):
    """the set of (x, y) pixels of the space view (256 x 192) that are lit: in
    the original's mono screen at &6000 (32 bytes a line, 256 a character
    row), or the port's four-colour screen at SCREEN% (four pixels a byte,
    512 bytes a character row), where a pixel is lit if either bit plane is
    set; so a routine that draws in one colour with EOR leaves the same set"""
    m = self.mpu.memory
    out = set()
    if self.name == "original":
        for y in range(192):
            base = 0x6000 + (y // 8) * 256 + y % 8
            for c in range(32):
                b = m[base + c * 8]
                if b:
                    for p in range(8):
                        if b >> (7 - p) & 1:
                            out.add((c * 8 + p, y))
    else:
        scr = map_constants()["SCREEN%"]
        for y in range(192):
            base = scr + (y // 8) * 512 + y % 8
            for c in range(64):
                b = m[base + c * 8]
                if b:
                    for p in range(4):
                        if (b >> (7 - p) | b >> (3 - p)) & 1:
                            out.add((c * 4 + p, y))
    return frozenset(out)


Machine.lit = _lit


def load():
    ref_sy = syms(os.path.join(REPO, "4-reference-binaries/sth/flight-symbols.txt"))
    ref = Machine("original", ref_sy, [(0x11E3, open(os.path.join(REPO, "4-reference-binaries/sth/D.CODE.unprot.bin"), "rb").read())])
    cand_sy = syms(os.path.join(REPO, "3-assembled-output/flight-symbols.txt"))
    mc = map_constants()
    extra = []
    if "QSL" in mc:                               # (the quarter squares, as the flight code's home image has them)
        lo = [(n * n // 4) & 255 for n in range(512)]
        hi = [(n * n // 4) >> 8 for n in range(512)]
        extra = [(mc["QSL"], lo), (mc["QSH"], hi)]
        cand_sy.setdefault("QSL", mc["QSL"])
        cand_sy.setdefault("QSH", mc["QSH"])
    if "LCOL" in mc:                              # (the drawing routines' colour: yellow, both bit planes)
        extra = extra + [(mc["LCOL"], [0xFF])]
    # (the port: main RAM with the loader's resident block A, which holds the
    # far calls, and the flight code's home and cold images in two banks,
    # numbered as jsbeeb's PROBE finds them, 7 and 6)
    ld = syms(os.path.join(REPO, "3-assembled-output/loader-symbols.txt"))
    loader = open(os.path.join(REPO, "3-assembled-output/ELITE4.bin"), "rb").read()
    resa = loader[ld["RESAcode"] - 0x1900:ld["RESAcode"] - 0x1900 + 0x400]
    cand = Machine("port", cand_sy, [(0x0400, resa)], extra)
    cand.home_bank, cand.cold_bank = 7, 6
    ref.base[0x07C0:0x0800] = list(resa[0x3C0:0x400])   # (SNE and ACT, as the original's loader puts them)
    for k, v in (("BANKH", 7), ("BANKC", 6), ("BANKR", 5), ("BANKF", 4)):
        cand.base[ld[k]] = v
    def bank(path):
        d = list(open(os.path.join(REPO, path), "rb").read())
        return d + [0] * (16384 - len(d))
    cand.banks = {7: bank("3-assembled-output/D.CODEH.bin"), 6: bank("3-assembled-output/D.CODEC.bin")}
    for (a, data) in extra:                       # (the quarter squares, in the home bank)
        if 0x8000 <= a < 0xC000:
            cand.banks[7][a - 0x8000:a - 0x8000 + len(data)] = list(data)
    cand.cold_labels = set()
    for l in open(os.path.join(REPO, "3-assembled-output/flight-banks.txt")):
        f = l.split()
        if len(f) == 2 and f[1] == "C":
            cand.cold_labels.add(f[0])
    cand.cold = cand
    return ref, cand


# ---------------------------------------------------------------- the tests
#
# Each test is (name, routine, inputs, outputs): inputs is a function that
# yields (A, X, Y, C, {variable: value}) tuples; outputs names the registers,
# flags and variables to compare after the call.

def grid(*ranges):
    """every combination of the given value lists"""
    if not ranges:
        yield ()
        return
    for v in ranges[0]:
        for rest in grid(*ranges[1:]):
            yield (v,) + rest


def sample(n, *ranges):
    rnd = random.Random(1)
    for _ in range(n):
        yield tuple(rnd.choice(r) for r in ranges)


def stars_mem(i):
    """a random pass of the front view's stardust (STARS1): 18 particles,
    a speed, roll and pitch, and seeds, as the game has them"""
    rnd = random.Random(i)
    m = {"NOSTM": 18}
    for k in range(1, 19):
        sx = rnd.choice([rnd.randrange(256), rnd.randrange(120), rnd.randrange(8)])
        sy = rnd.choice([rnd.randrange(256), rnd.randrange(120), rnd.randrange(8)])
        m["SX+%d" % k] = sx | rnd.choice([0, 0x80])
        m["SY+%d" % k] = sy | rnd.choice([0, 0x80])
        m["SZ+%d" % k] = rnd.choice([rnd.randrange(16, 256), rnd.randrange(1, 256), rnd.randrange(16, 41)])
        m["SXL+%d" % k] = rnd.randrange(256)
        m["SYL+%d" % k] = rnd.randrange(256)
        m["SZL+%d" % k] = rnd.randrange(256)
    d = rnd.randrange(1, 41)
    m["DELTA"] = d
    m["DELT4"] = (d * 64) & 255
    m["DELT4+1"] = (d * 64) >> 8
    a = rnd.choice([0, rnd.randrange(32), rnd.randrange(8)])
    sa = rnd.choice([0, 0x80])
    m["ALP1"], m["ALP2"], m["ALP2+1"], m["ALPHA"] = a, sa, sa ^ 0x80, a | sa
    b = rnd.choice([0, rnd.randrange(9), rnd.randrange(32)])
    sb = rnd.choice([0, 0x80])
    m["BET1"], m["BET2"], m["BET2+1"], m["BETA"] = b, sb, sb ^ 0x80, b | sb
    for k in range(4):
        m["RAND+%d" % k] = rnd.randrange(256)
    return m


def bline_mem(i):
    """a random call of BLINE: a planet's centre and a new point near the
    screen, the previous point, a part-filled line heap and FLAG"""
    rnd = random.Random(i)
    m = {}
    def w(name, v):
        m[name] = v & 255
        m[name + "+1"] = (v >> 8) & 255
    w("K4", rnd.randrange(-100, 300) & 0xFFFF)           # (centre y)
    w("K5", rnd.choice([rnd.randrange(256), rnd.randrange(-200, 500) & 0xFFFF]))
    m["K5+2"] = rnd.randrange(256)
    m["K5+3"] = rnd.choice([0, 0, 1, 0xFF])
    w("K6", rnd.choice([rnd.randrange(256), rnd.randrange(-200, 500) & 0xFFFF]))
    m["T"] = rnd.choice([0, 0, 0xFF, 1])
    m["FLAG"] = rnd.choice([0, 0, 0, 0xFF])
    lsp = rnd.randrange(1, 60)
    m["LSP"] = lsp
    for k in range(lsp):
        m["LSY2+%d" % k] = rnd.choice([rnd.randrange(192), 0xFF])
        m["LSX2+%d" % k] = rnd.randrange(256)
    m["CNT"] = rnd.randrange(64)
    m["STP"] = rnd.choice([1, 2, 4, 8, 16])
    return rnd.randrange(256), m


B = range(256)
B1 = range(1, 256)
QUICK = "--quick" in sys.argv
EVERY = (lambda *r: sample(4000, *r)) if QUICK else grid

# The flags compared are N, Z and C: the game reads V only straight after a
# BIT or a call of DORND, never after the routines tested here.
MUL = ["A", "X", "Y", "N", "Z", "C", "P", "T"]

TESTS = [
    # (MU11 is never entered with X = 0: MULTU and SQUA2 return 0 for that)
    ("MU11", "MU11", lambda: ((0, x, y, c, {"P": p}) for p, x, y, c in EVERY(B, B1, [0x5A], [0, 1])), MUL),
    ("MULTU", "MULTU", lambda: ((0, 0, y, c, {"P": p, "Q": q}) for p, q, y, c in EVERY(B, B, [0x5A], [0, 1])),
     MUL),
    ("MLU2", "MLU2", lambda: ((a, 0, y, c, {"Q": q}) for a, q, y, c in EVERY(B, B, [0x5A], [0, 1])),
     MUL),
    ("SQUA2", "SQUA2", lambda: ((a, 0, y, c, {"T": 0x77}) for a, y, c in EVERY(B, [0x5A], [0, 1])),
     MUL),
    ("FMLTU", "FMLTU", lambda: ((a, x, 0x5A, c, {"Q": q, "P": 0x33}) for a, q, x, c in EVERY(B, B, [0, 0x81], [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q"]),
    ("FMLTU2", "FMLTU2", lambda: ((a, 0x81, 0x5A, c, {"K": k, "Q": 0x11}) for a, k, c in EVERY(B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q"]),
    ("MULT1", "MULT1", lambda: ((a, 0x81, 0x5A, c, {"Q": q, "T1": 0x33}) for a, q, c in EVERY(B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "T", "T1"]),
    ("MULT12", "MULT12", lambda: ((a, 0x81, 0x5A, c, {"Q": q, "T1": 0x33}) for a, q, c in EVERY(B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "R", "S", "T", "T1"]),
    # (P < 32: MLS1 and MLS2 set it to ALP1, and the callers of MULTS-2 to
    # |alpha| or |beta|)
    ("MLS1", "MLS1", lambda: ((a, 0x81, 0x5A, c, {"ALP1": p, "T1": 0x33}) for a, p, c in EVERY(B, range(32), [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "T", "T1"]),
    ("MLS2", "MLS2", lambda: ((a, 0x81, 0x5A, c, {"ALP1": p, "XX": 0x12, "XX+1": 0x34}) for a, p, c in EVERY(B, range(32), [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "R", "S", "T", "T1"]),
    ("MULTS", "MULTS", lambda: ((a, 0x81, 0x5A, c, {"P": p, "T1": 0x33}) for a, p, c in EVERY(B, range(32), [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "T", "T1"]),
    ("MLTU2", "MLTU2", lambda: ((a, 0x81, 0x5A, c, {"P": p, "Q": q, "P+1": 0x33}) for a, p, q, c in sample(4000 if QUICK else 200000, B, B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "P+1", "Q"]),
    ("MULT3", "MULT3", lambda: ((a, 0x81, 0x5A, c, {"P": p, "P+1": p1, "Q": q, "T": 0x44}) for a, p, p1, q, c in sample(200000 if not QUICK else 4000, B, B, B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "K", "K+1", "K+2", "K+3", "P", "P+1", "Q", "R", "T"]),
    ("LL28", "LL28", lambda: ((a, 0x81, 0x5A, c, {"Q": q, "R": 0x33}) for a, q, c in EVERY(B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "Q", "R"]),
    ("LL31", "LL31", lambda: ((a, 0x81, 0x5A, c, {"Q": q, "R": 254}) for a, q, c in EVERY(B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "Q", "R"]),
    ("DVID4", "DVID4", lambda: ((a, 0x81, 0x5A, c, {"Q": q, "P": 0x33, "R": 0x44}) for a, q, c in EVERY(B, B1, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "R"]),
    ("DV42", "DV42", lambda: ((0, 0x81, y, c, {"SZ": q, "SZ+1": q, "DELTA": d}) for d, q, y, c in grid(range(1, 41), range(16, 256), [0, 1], [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "R"]),
    # (DVID3B2: z is never 0, as the original would loop for ever)
    ("DVID3B2", "DVID3B2", lambda: ((a, 0x81, 0x5A, c, {"P": p, "P+1": p1, "INWK+6": zl, "INWK+7": zh, "INWK+8": zs}) for a, p, p1, zl, zh, zs, c in
        ((a, p, p1, zl, zh, zs, c) for a, p, p1, zl, zh, zs, c in sample(4000 if QUICK else 300000, B, B, B, B, B, list(range(4)) + [0x80, 0x81, 0x7F, 0xFF], [0, 1]) if zl | zh | (zs & 0x7F))),
     ["A", "X", "Y", "N", "Z", "C", "K", "K+1", "K+2", "K+3", "P", "P+1", "P+2", "Q", "R", "S", "T"]),
    ("ADD", "ADD", lambda: ((a, 0x81, 0x5A, c, {"P": pp, "R": r, "S": ss, "T": 0x33, "T1": 0x44}) for a, pp, r, ss, c in
        sample(20000 if QUICK else 400000, B, B, B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "R", "S", "T", "T1"]),
    ("ADD", "ADD", lambda: ((a, 0x81, 0x5A, c, {"P": pp, "R": pp ^ d, "S": a ^ 0x80 ^ e, "T": 0x33, "T1": 0x44}) for a, pp, d, e, c in
        grid(B, [0, 1, 2, 0x7F, 0x80, 0xFE, 0xFF], [0, 1, 2, 0x80], [0, 1, 0x80, 0x81], [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "R", "S", "T", "T1"]),
    ("MAD", "MAD", lambda: ((a, 0x81, 0x5A, c, {"Q": q, "P": 0x55, "R": r, "S": ss, "T": 0x33, "T1": 0x44}) for a, q, r, ss, c in
        sample(20000 if QUICK else 400000, B, [0, 0x80, 1, 0x81] + list(B), B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "R", "S", "T", "T1"]),
    ("TAS3", "TAS3", lambda: ((0, 0x81, y, c, {"XX15": x0, "XX15+1": x1, "XX15+2": x2, "INWK+%d" % y: v0, "INWK+%d" % (y + 2): v1, "INWK+%d" % (y + 4): v2}) for y, x0, x1, x2, v0, v1, v2, c in
        sample(5000 if QUICK else 300000, [10, 12, 14, 16, 18, 20], B, B, B, [0, 0x80] + list(B), [0, 0x80] + list(B), [0, 0x80] + list(B), [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "R", "S", "T", "T1"]),
    ("MVS4", "MVS4", lambda: ((0, 0x81, y, c, {"ALPHA": al, "BETA": be, **{"INWK+%d" % (y + k): v[k] for k in range(6)}}) for y, al, be, c, v in
        ((y, al, be, c, v) for y, al, be, c, v in sample(4000 if QUICK else 200000, [9, 15, 21], [0, 0x80, 1, 0x81, 2, 0x7F, 0xFF], [0, 0x80, 1, 0x81, 3, 0x7F, 0xFE], [0, 1],
            [tuple(x) for x in sample(500, B, [0, 0x80, 0x60, 0xE0] + list(B), B, [0x80, 0, 0x60, 0xE0] + list(B), B, [0, 0x80] + list(B))]))),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "R", "S", "T", "T1", "INWK+9", "INWK+10", "INWK+11", "INWK+12", "INWK+13", "INWK+14", "INWK+15", "INWK+16", "INWK+17", "INWK+18", "INWK+19", "INWK+20", "INWK+21", "INWK+22", "INWK+23", "INWK+24", "INWK+25", "INWK+26"]),
    ("LL5", "LL5", lambda: ((0x11, 0x81, 0x5A, c, {"R": r, "Q": q, "S": 0x22, "T": 0x33}) for r, q, c in EVERY(B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "V", "Q", "R", "S", "T"]),
    ("LL38", "LL38", lambda: ((a, 0x81, 0x5A, c, {"R": r, "Q": q, "S": ss}) for a, r, q, ss, c in grid([0, 0x80, 0x33, 0xB3], B, B, [0, 0x80], [0, 1]) if not QUICK or (r ^ q) & 7 == 0),
     ["A", "X", "Y", "N", "Z", "C", "V", "Q", "R", "S"]),
    ("TIS2", "TIS2", lambda: ((a, 0x81, 0x5A, c, {"Q": q, "T": 0x33}) for a, q, c in EVERY(B, B1, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "Q", "T"]),
    ("TIS1", "TIS1", lambda: ((a, x, 0x5A, c, {"R": r, "S": ss}) for a, x, r, ss, c in sample(5000 if QUICK else 300000, B, B, B, B, [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "Q", "R", "S", "T", "T1"]),
    # (STARS1 for whole passes over the stardust, with random particles and
    # flight: the particles, the seeds and the screen are compared)
    ("STARS1", "STARS1", lambda: ((0, 0, 0, c, stars_mem(i)) for i, c in zip(range(150 if QUICK else 2000), [0, 1] * 2000)),
     ["Y", "SX*19", "SXL*19", "SY*19", "SYL*19", "SZ*19", "SZL*19", "RAND*4", "SCREENPIX"]),
    # (BLINE: the line ends in XX15 are not compared, as on the first call the
    # port has already copied the points into them; they are temporaries,
    # and the heap holds the ends of every line drawn)
    ("BLINE", "BLINE", lambda: ((0, x, 0x5A, c, m) for (x, m), c in ((bline_mem(i), i & 1) for i in range(3000 if QUICK else 100000))),
     ["CNT", "LSP", "FLAG", "K5", "K5+1", "K5+2", "K5+3", "XX13", "LSX2*80", "LSY2*80", "SCREENPIX"]),
    # (PIX1: P = 0, as all its callers set it; Y indexes the particle; A, X,
    # N and Z are PIXEL's, which differ on the four-colour screen and which
    # its callers do not read; C they do, as DORND's input)
    ("PIX1", "PIX1", lambda: ((a, 0x81, y, c, {"P": 0, "R": r, "S": ss, "X1": x1, "Y1": y1, "ZZ": zz}) for a, r, ss, x1, y1, zz, y, c in
        sample(20000 if QUICK else 300000, B, B, B, B, B, [16, 40, 90, 144, 255], [1, 5, 18], [0, 1])),
     ["Y", "C", "YY+1", "SYL*19", "T", "T1", "SCREENPIX"]),
    # (DADD: ADD's work for the dashboard's pitch and roll, against ADD)
    ("DADD", "ADD/DADD", lambda: ((a | sg, 0x81, 0x5A, c, {"P": 0, "R": 0, "S": 8, "T": 0x33, "T1": 0x44}) for a, sg, c in grid(range(8), [0, 0x80], [0, 1])),
     ["A", "X", "Y", "N", "Z", "C", "P", "R", "S", "T", "T1"]),
    ("SQUA", "SQUA", lambda: ((a, 0, y, c, {"T": 0x77}) for a, y, c in EVERY(B, [0x5A], [0, 1])),
     MUL),
]


def main():
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    ref, cand = load()
    bad = 0
    for name, routine, inputs, outs in TESTS:
        routine, _, port_routine = routine.partition("/")   # ("ORIG/PORT": the port's version has its own name)
        port_routine = port_routine or routine
        if port_routine not in cand.sy and port_routine + "_C" in cand.sy:
            port_routine += "_C"                         # (a cold-bank body, as streams.py names it)
        if names and name not in names:
            continue
        if port_routine not in cand.sy:
            print("%-10s skipped (not in the port's symbols)" % name)
            continue
        n = fails = cyc_r = cyc_c = 0
        first = None
        for a, x, y, c, mem in inputs():
            ref.call(routine, a, x, y, c, mem)
            cyc_r += ref.mpu.processorCycles if hasattr(ref.mpu, "processorCycles") else 0
            r = ref.out(outs)
            m = cand.cold if port_routine in cand.cold_labels else cand
            m.call(port_routine, a, x, y, c, mem)
            k = m.out(outs)
            n += 1
            if r != k:
                fails += 1
                if first is None:
                    first = (a, x, y, c, mem, r, k)
        if fails:
            bad += 1
            a, x, y, c, mem, r, k = first
            diff = {o: (r[o], k[o]) for o in outs if r[o] != k[o]}
            print("%-10s FAIL %d of %d; first: A=%d X=%d Y=%d C=%d %s: (original, port) %s" % (name, fails, n, a, x, y, c, mem, diff))
        else:
            print("%-10s pass (%d inputs)" % (name, n))
    print("TEST_ROUTINES %s" % ("FAIL" if bad else "PASS"))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
