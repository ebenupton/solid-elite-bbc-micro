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
        base, _, off = k.partition("+")
        return self.sy[base] + (int(off) if off else 0)

    def out(self, names):
        mpu = self.mpu
        r = {"A": mpu.a, "X": mpu.x, "Y": mpu.y,
             "N": mpu.p >> 7 & 1, "V": mpu.p >> 6 & 1, "Z": mpu.p >> 1 & 1, "C": mpu.p & 1}
        return {n: (r[n] if n in r else mpu.memory[self.addr(n)]) for n in names}


def load():
    ref_sy = syms(os.path.join(REPO, "4-reference-binaries/sth/flight-symbols.txt"))
    ref = Machine("original", ref_sy, [(0x11E3, open(os.path.join(REPO, "4-reference-binaries/sth/D.CODE.unprot.bin"), "rb").read())])
    cand_sy = syms(os.path.join(REPO, "3-assembled-output/flight-symbols.txt"))
    mc = map_constants()
    extra = []
    if "QSL" in mc:                               # (the quarter squares, as the loader installs them)
        lo = [(n * n // 4) & 255 for n in range(512)]
        hi = [(n * n // 4) >> 8 for n in range(512)]
        extra = [(mc["QSL"], lo), (mc["QSH"], hi)]
        cand_sy.setdefault("QSL", mc["QSL"])
        cand_sy.setdefault("QSH", mc["QSH"])
    cand = Machine("port", cand_sy, [(0x8000, open(os.path.join(REPO, "3-assembled-output/D.CODEH.bin"), "rb").read())], extra)
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
    ("SQUA", "SQUA", lambda: ((a, 0, y, c, {"T": 0x77}) for a, y, c in EVERY(B, [0x5A], [0, 1])),
     MUL),
]


def main():
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    ref, cand = load()
    bad = 0
    for name, routine, inputs, outs in TESTS:
        if names and name not in names:
            continue
        if routine not in cand.sy:
            print("%-10s skipped (not in the port's symbols)" % name)
            continue
        n = fails = cyc_r = cyc_c = 0
        first = None
        for a, x, y, c, mem in inputs():
            ref.call(routine, a, x, y, c, mem)
            cyc_r += ref.mpu.processorCycles if hasattr(ref.mpu, "processorCycles") else 0
            r = ref.out(outs)
            cand.call(routine, a, x, y, c, mem)
            k = cand.out(outs)
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
