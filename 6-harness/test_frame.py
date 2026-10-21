#!/usr/bin/env python3
"""Smoke test for bank F, the filled renderer's frame layer (docs/renderer.md).

    python3 6-harness/test_frame.py [--png DIR] [--nobuild]

Port (Model B): builds banks R and F (2-build-files/bankr.py and bankf.py;
the game must have been built, for the symbols they read) and runs them on
py65's NMOS 6502 (the Model B's) with:

  * main RAM: the glue (GLUE.bin at GLUE%: the trampolines and GCALL), the
    loader's bank numbers (BANKR, BANKF) and the game's variables that the
    records read (at the flight program's addresses);
  * &8000-&BFFF paged by writes to ROMSEL (&FE30): the game's home bank
    (empty), bank R or bank F; the MOS ROM (its font) at &C000;
  * every entry called as the game will call it, LDX #n : JSR GCALL from main
    RAM with the home bank paged.

It records synthetic frames (ships with their real faces, projected here
from the blueprints that faces.py reads; the sun and the planet as discs,
a planet curve, lines, dots, a distant ship, stars, text, the sights and
our laser beams) and checks that:

  * every call writes nothing but the renderer's zero page (&06-&27, the
    frame layer's &D2-&E1), the stack page, the screen buffers, the mailbox
    and the shared variables (&7E00-&7EFF), the glue's own two bytes, &F4,
    ROMSEL and banks R and F; that the zero page is as it was after every
    call; and that the caller's bank is paged back;
  * the first frame blanks both buffers' windows, keeps buffer 1's border and
    copies it to buffer 0, draws into buffer 0 (buffer 1 on show) and queues
    the flip (GFLIP, GPEND); the next draws into buffer 1;
  * the frame drew what was recorded: the sun's and the planet's colours at
    their centres, every ship's centre filled, the text's glyphs, the sights,
    nothing outside the window;
  * a buffer's next frame repairs it exactly: buffer 0 after scene A then
    scene C is byte for byte buffer 0 after scene C alone (on a fresh
    machine).

Writes frame PNGs (4x, CMYK) to --png DIR (default 3-assembled-output) to be
looked at. Exit status 0 only if every check passes.
"""
import math, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, '3-assembled-output')
BEEBASM = os.environ.get('BEEBASM', 'beebasm')
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(REPO, '2-build-files'))

HOME = 6                                         # the banks (the loader finds
RBANK, FBANK = 4, 5                              # them; any distinct numbers)
STUB = 0x7FC0                                    # where the test's caller runs
FG = ['F_INIT', 'F_DIRECT', 'F_FRAME', 'F_SHIP', 'F_LINE', 'F_DOT', 'F_PLANET', 'F_SHPPT',
      'F_PCURVE', 'F_PPOINT', 'F_CHAR', 'F_DELCHAR', 'F_CLRTEXT', 'F_BOMB']
FAILS = []


def check(cond, what):
    print(('  ok   ' if cond else '  FAIL ') + what)
    if not cond:
        FAILS.append(what)


def syms_of(name):
    t = open(os.path.join(OUT, name + '-symbols.txt')).read()
    return {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", t)}


def consts():
    """elite-map.asm's constants, bankf-game.asm's (the game's) and
    gfx-faces.asm's (BeebAsm's symbol dump has labels only)"""
    out = {}
    ms = os.path.join(REPO, '1-source-files', 'main-sources')
    for f in (os.path.join(ms, 'elite-map.asm'), os.path.join(OUT, 'bankf-game.asm'),
              os.path.join(ms, 'gfx-faces.asm')):
        for l in open(f, encoding='latin-1'):
            for st in l.split('\\')[0].split(':'):
                m = re.match(r'^\s*([A-Za-z_][\w%]*)\s*=\s*(.+)$', st)
                if m:
                    e = re.sub(r'&([0-9A-Fa-f]+)', r'0x\1', m.group(2)).strip()
                    try:
                        out[m.group(1)] = eval(e, {}, dict(out))
                    except Exception:
                        pass
    return out


def build():
    for tool in ('bankr.py', 'bankf.py'):
        r = subprocess.run([sys.executable, os.path.join(REPO, '2-build-files', tool), BEEBASM],
                           capture_output=True, text=True)
        if r.returncode:
            print(r.stdout, r.stderr)
            raise SystemExit('%s failed' % tool)
        print(r.stdout.strip())


class Mem:
    """64K with &8000-&BFFF paged by ROMSEL, and a write guard"""

    def __init__(self, S):
        self.main = bytearray(0x10000)
        self.banks = {HOME: bytearray(0x4000),
                      RBANK: bytearray(open(os.path.join(OUT, 'R.bin'), 'rb').read()),
                      FBANK: bytearray(open(os.path.join(OUT, 'F.bin'), 'rb').read())}
        os_rom = os.path.join(HERE, 'node_modules', 'jsbeeb', 'public', 'roms', 'os.rom')
        self.main[0xC000:0x10000] = open(os_rom, 'rb').read()[:0x4000]
        self.sel = HOME
        g = open(os.path.join(OUT, 'GLUE.bin'), 'rb').read()
        self.main[S['GLUE%']:S['GLUE%'] + len(g)] = g
        ok = bytearray(0x10000)                  # the write guard's allowed bytes
        for lo, hi in ((0x06, 0x28), (0xD2, 0xE2), (0xF4, 0xF5), (0x100, 0x200), (0x1000, 0x7000),
                       (0x7E00, 0x7F00), (S['rtA'], S['rtA'] + 3), (S['rtl'] + 1, S['rtl'] + 3), (S['rtj'] + 1, S['rtj'] + 2)):
            ok[lo:hi] = b'\1' * (hi - lo)
        self.ok = ok
        self.bad = []

    def __getitem__(self, a):
        if 0x8000 <= a < 0xC000:
            return self.banks[self.sel][a - 0x8000]
        return self.main[a]

    def __setitem__(self, a, v):
        if 0x8000 <= a < 0xC000:
            if self.sel == HOME:
                self.bad.append(a)
            self.banks[self.sel][a - 0x8000] = v
            return
        if a == 0xFE30:
            self.sel = v & 15
            return
        if not self.ok[a]:
            self.bad.append(a)
        if a < 0xC000:
            self.main[a] = v


class Machine:
    def __init__(self):
        from py65.devices.mpu6502 import MPU
        self.S = dict(consts())
        self.S.update(syms_of('bankf'))
        self.mem = Mem(self.S)
        S, m = self.S, self.mem.main
        m[S['BANKR']], m[S['BANKF']] = RBANK, FBANK
        m[0xF4] = HOME
        self.mpu = MPU(memory=self.mem)
        self.cycles = {}

    def __getitem__(self, name):
        return self.mem.main[self.S[name]]

    def __setitem__(self, name, v):
        self.mem.main[self.S[name]] = v & 255

    def poke(self, a, v):
        self.mem.main[a] = v & 255

    def put16(self, name, v, off=0):
        a = self.S[name] + off
        self.mem.main[a], self.mem.main[a + 1] = v & 255, (v >> 8) & 255

    def call(self, entry, a=0, y=0, maxcyc=40_000_000):
        """LDX #n : JSR GCALL : (stop) from main RAM, the home bank paged"""
        n = FG.index(entry)
        mpu, mem = self.mpu, self.mem
        g = self.S['GCALL']
        code = [0xA2, n, 0x20, g & 255, g >> 8]
        mem.main[STUB:STUB + 5] = bytes(code)
        zp = bytes(mem.main[0:0x100])
        mem.bad = []
        mpu.a, mpu.x, mpu.y, mpu.p, mpu.sp = a & 255, 0x55, y & 255, 0x24, 0xFF
        mpu.pc = STUB
        c0 = mpu.processorCycles
        step = mpu.step
        end = STUB + 5
        while mpu.pc != end:
            step()
            if mpu.processorCycles - c0 > maxcyc:
                raise RuntimeError('runaway in %s at &%04X' % (entry, mpu.pc))
        cyc = mpu.processorCycles - c0
        self.cycles.setdefault(entry, []).append(cyc)
        if mem.bad:
            FAILS.append('%s wrote outside its areas: %s' % (entry, ' '.join('&%04X' % b for b in sorted(set(mem.bad))[:12])))
            print('  FAIL', FAILS[-1])
        zd = [i for i in range(256) if mem.main[i] != zp[i] and i not in (0xF4,)]
        if zd:
            FAILS.append('%s left zero page changed: %s' % (entry, ' '.join('&%02X' % i for i in zd[:12])))
            print('  FAIL', FAILS[-1])
        if mem.sel != HOME or mem.main[0xF4] != HOME:
            FAILS.append('%s did not page the home bank back' % entry)
            print('  FAIL', FAILS[-1])
        if mpu.y != y & 255:
            FAILS.append('%s did not keep Y' % entry)
            print('  FAIL', FAILS[-1])
        return cyc

    def vsync(self):
        """the vertical sync interrupt's part: show the pending buffer"""
        if self['GFLIP']:
            self['GFRONT'] = self['GPEND']
            self['GFLIP'] = 0

    def buffer(self, b):
        base = self.S['BUF0'] if b == 0 else self.S['SCREEN%']
        return bytes(self.mem.main[base:base + 0x3000])


# ---------------------------------------------------------------------------
# Screens

def addr(x, y):
    return (y >> 3) * 0x200 + (y & 7) + (x >> 2) * 8


def pixel(buf, x, y):
    b = buf[addr(x, y)]
    p = x & 3
    return ((b >> (7 - p)) & 1) << 1 | ((b >> (3 - p)) & 1)


PAL = [(0, 0, 0), (0, 255, 255), (255, 0, 255), (255, 255, 0)]   # black, cyan, magenta, yellow


def png(buf, path, scale=4):
    from PIL import Image
    im = Image.new('RGB', (256, 192))
    px = im.load()
    for y in range(192):
        for x in range(256):
            px[x, y] = PAL[pixel(buf, x, y)]
    im.resize((256 * scale, 192 * scale), Image.NEAREST).save(path)


def border(m):
    """what TT66 leaves on buffer 1: the border (line 0, pixels 0-1 and 254-255
    of every line) and some text in the window; buffer 0 holds garbage"""
    import random
    rnd = random.Random(7)
    base0, base1 = m.S['BUF0'], m.S['SCREEN%']
    for a in range(0x3000):
        m.mem.main[base0 + a] = rnd.randrange(256)
        m.mem.main[base1 + a] = rnd.randrange(256) if (a // 8) % 7 == 3 else 0
    for x in range(64):
        m.mem.main[base1 + addr(4 * x, 0)] = 0xFF
    for y in range(192):
        m.mem.main[base1 + addr(0, y)] |= 0xCC
        m.mem.main[base1 + addr(252, y)] |= 0x33


# ---------------------------------------------------------------------------
# Scenes

def rot(ax, ay, az):
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    mul = lambda a, b: [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(rz, mul(ry, rx))


def col(r, j):
    return [r[0][j], r[1][j], r[2][j]]


SHIPS = None


def ships():
    global SHIPS
    if SHIPS is None:
        import faces
        SHIPS = dict(faces.load_ships())
    return SHIPS


def record_ship(m, gtype, pos, angles, winding=False, xx4=0):
    """F_SHIP for blueprint gtype at view position pos, orientation from
    angles (sidev, roofv, nosev = R x, R y, -R z: det -1, as ZINF's), XX2 as
    LL9 sets it (31 if the normal faces us, else 0), or 255 for every face
    (winding: a far ship, culled by its winding)"""
    s = ships()[gtype]
    r = rot(*angles)
    side, roof, nose = col(r, 0), col(r, 1), [-c for c in col(r, 2)]
    S = m.S
    for k, v in enumerate((nose, roof, side)):      # INWK+9.. nosev, roofv, sidev
        for i in range(3):
            q = int(round(v[i] * 0x6000))
            mag = min(abs(q), 0x7FFF)
            a = S['INWK'] + 9 + 6 * k + 2 * i
            m.poke(a, mag & 255)
            m.poke(a + 1, (mag >> 8) | (0x80 if q < 0 else 0))
    z = int(pos[2])
    m.poke(S['INWK'] + 6, z & 255)
    m.poke(S['INWK'] + 7, z >> 8)
    view = lambda b: [pos[i] + b[0] * side[i] + b[1] * roof[i] + b[2] * nose[i] for i in range(3)]
    for vi, v in enumerate(s['verts']):
        p = view((v['x'], v['y'], v['z']))
        sx = int(round(128 + 256 * p[0] / p[2]))
        sy = int(round(96 - 256 * p[1] / p[2]))
        a = S['XX3'] + 4 * vi
        for k, w in enumerate((sx & 255, (sx >> 8) & 255, sy & 255, (sy >> 8) & 255)):
            m.poke(a + k, w)
    for fi, f in enumerate(s['faces']):
        n = f['n']
        nv = [n[0] * side[i] + n[1] * roof[i] + n[2] * nose[i] for i in range(3)]
        on = [v for v in s['verts'] if fi in v['faces']]     # a vertex on the face
        v = on[0] if on else {'x': 0, 'y': 0, 'z': 0}
        p = view((v['x'], v['y'], v['z']))
        vis = sum(nv[i] * p[i] for i in range(3)) < 0
        m.poke(S['XX2'] + fi, 255 if winding else (31 if vis else 0))
    m['GNF'], m['GNV'], m['GTYPE'] = len(s['faces']), len(s['verts']), gtype
    m['XX4'] = xx4
    m.call('F_SHIP', y=0x77)
    return [(sx_sy(m, vi)) for vi in range(len(s['verts']))]


def sx_sy(m, vi):
    a = m.S['XX3'] + 4 * vi
    g = m.mem.main
    x = g[a] | g[a + 1] << 8
    y = g[a + 2] | g[a + 3] << 8
    return (x - 65536 if x >= 32768 else x, y - 65536 if y >= 32768 else y)


def text(m, s, x, y):
    for i, c in enumerate(s):
        m['XC'], m['YC'] = x + i + 1, y
        m.call('F_CHAR', a=ord(c), y=0x33)


def scene(m, k):
    """record scene k (0: A, 1: B, 2: C); returns what to look for"""
    S = m.S
    look = {}
    m['QQ11'] = 0
    if k == 0:                                   # the sun, top right
        m['TYPE'] = 129
        m.put16('K3', 210)
        m.put16('K4', 40)
        m['K'] = 30
        m.call('F_PLANET')
        look['sun'] = (210, 40)
    m['TYPE'] = 128                              # the planet
    px, py, pr = (60, 140, 50) if k != 1 else (70, 130, 46)
    m.put16('K3', px)
    m.put16('K4', py)
    m['K'] = pr
    m.poke(S['INWK'] + 6, 0)
    m.poke(S['INWK'] + 7, 0x40)
    m.call('F_PLANET')
    look['planet'] = (px - pr // 2, py + pr // 3)
    m.call('F_PCURVE')                           # a meridian: a half ellipse
    for i in range(17):
        t = math.pi * (i / 16.0 - 0.5)
        m.put16('K6', int(round(px + pr * 0.4 * math.cos(t))))
        m.put16('K5', int(round(py + pr * math.sin(t))), 2)
        m.call('F_PPOINT')
    look['ships'] = []
    if k == 0:
        ships_rec = [(11, (-40, 10, 700), (0.4, 0.7, 0.2), False),     # Cobra Mk III
                     (2, (200, -40, 1400), (0.3, 0.5, 0.1), False),    # Coriolis station
                     (29, (90, 60, 900), (1.2, 0.3, 0.4), True)]       # Thargoid, far
    else:
        ships_rec = [(32, (-60, 30, 1500), (0.5, 0.2, 0.3), False),    # Dodecahedron station
                     (20, (60, -20, 500), (0.2, 2.6, 0.5), False),     # Adder
                     (4, (0, 50, 400), (0.7, 0.2, 0.1), False)]        # Alloy plate
    for t, pos, ang, w in ships_rec:
        record_ship(m, t, pos, ang, winding=w)
        look['ships'].append((int(128 + 256 * pos[0] / pos[2]), int(96 - 256 * pos[1] / pos[2]), t))
    m['GLCOL'] = 2                               # an enemy laser
    m['X1'], m['Y1'], m['X2'], m['Y2'] = 20, 20, 120, 90
    m.call('F_LINE')
    m['GDCOL'] = 4                               # particles
    for i in range(8):
        m['ZZ'] = 60 + 10 * i
        m.call('F_DOT', a=150 + 3 * i, y=30 + 7 * i)
    m['TYPE'] = 11                               # a distant ship
    m.put16('K3', 240)
    m.put16('K4', 170)
    m.call('F_SHPPT')
    for i in range(1, S['NOST'] + 1):            # the stardust (the hooks' job)
        m.poke(S['MBOX'] + 0x50 + i, (37 * i + 11 * k) % 250 + 3)
        m.poke(S['MBOX'] + 0x68 + i, (53 * i + 5 * k) % 186 + 3)
        m.poke(S['MBOX'] + 0x80 + i, 1 + i % 3)
    m.poke(S['MBOX'] + 0x50, 0)
    m.poke(S['MBOX'] + 0x80, 0)
    m.call('F_CLRTEXT', a=0, y=23)
    if k == 1:
        text(m, 'LEFT VIEW', 11, 0)
        text(m, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345', 0, 22)
    else:
        text(m, 'FRONT VIEW', 11, 1)
        text(m, 'Hello, Model B', 9, 20)
        text(m, 'x', 31, 12)
        text(m, 'x', 0, 12)
        text(m, 'Q', 5, 5)
        text(m, 'Q', 5, 5)                       # (EOR: printed twice is gone)
        m.call('F_DELCHAR', a=10, y=20)          # the 'e' of Hello
    look['text'] = k
    m['GSIGHT'] = 1
    m['GLASV'] = 1 if k == 0 else 0
    m['LASX'], m['LASY'] = 128, 96
    return look


def frame(m, png_dir=None, name=None):
    m.vsync()
    back = m['GFRONT'] ^ 1 if m['GMODE'] & 0x80 else 0
    cyc = m.call('F_FRAME', y=0x99)
    check(m['GFLIP'] == 0xFF and m['GPEND'] == back, 'the frame queued the flip to buffer %d' % back)
    if png_dir:
        png(m.buffer(back), os.path.join(png_dir, name))
    return back, cyc


def main():
    args = sys.argv[1:]
    png_dir = OUT
    if '--png' in args:
        png_dir = args[args.index('--png') + 1]
    if '--nobuild' not in args:
        build()
    m = Machine()
    S = m.S
    print('F_INIT, F_DIRECT')
    m.call('F_INIT')
    border(m)
    b1_before = m.buffer(1)
    m.call('F_DIRECT')
    check(m['GMODE'] == 0 and m['GFRONT'] == 1, 'F_DIRECT: direct mode, buffer 1 on show')
    m.mem.main[S['FRIN'] + 1] = 129              # the sun in slot 1, up and to the right
    for i, v in enumerate((0, 0x40, 0, 0, 0x30, 0, 0, 0x60, 0)):
        m.poke(S['K%'] + S['NI%'] + i, v)

    print('frame 1: scene A on buffer 0')
    look = scene(m, 0)
    b, cyc1 = frame(m, png_dir, 'frame-1.png')
    buf0, buf1 = m.buffer(0), m.buffer(1)
    check(b == 0 and m['GMODE'] & 0x80, 'the first frame entered space mode and drew buffer 0')
    border_ok = all(buf0[addr(4 * x, 0)] == b1_before[addr(4 * x, 0)] for x in range(64)) and \
        all(buf0[addr(0, y)] & 0xCC == b1_before[addr(0, y)] & 0xCC and
            buf0[addr(252, y)] & 0x33 == b1_before[addr(252, y)] & 0x33 for y in range(192))
    check(border_ok, "buffer 1's border copied to buffer 0")
    check(all(buf1[addr(x, y)] == (b1_before[addr(x, y)] & (0xCC if x < 4 else 0x33 if x >= 252 else 0))
              for y in range(1, 192) for x in range(0, 256, 4)), "buffer 1's window blanked, its border kept")
    check(all(pixel(buf0, x, y) == 0 for y in range(1, 192) for x in (0, 1, 254, 255)
              if pixel(b1_before, x, y) == 0), 'nothing drawn on the border')
    sx, sy = look['sun']
    check(buf0[addr(sx, sy)] == S['FC_SUNE'] if (sy & 1) == 0 else buf0[addr(sx, sy)] == S['FC_SUNO'],
          "the sun's colour at its centre")
    lit = lambda x, y: any(pixel(buf0, x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
    for x, y, t in look['ships']:
        check(lit(x, y), 'ship type %d drawn at (%d, %d)' % (t, x, y))
    check(any(pixel(buf0, x, y) == 3 for x in range(88, 128) for y in range(8, 16)), "the title's glyphs drawn")
    check(all(pixel(buf0, x, y) == 0 for x in range(40, 48) for y in range(40, 48)), "the 'Q' printed twice is gone")
    check(pixel(buf0, 128 - 15, 96) != 0 and pixel(buf0, 128, 96 + 15) != 0, 'the sights drawn')
    ref_text = buf0

    print('frame 2: scene B on buffer 1 (the light from the sun)')
    m.mem.main[S['FRIN'] + 1] = 0                # (the fixed light from here on)
    scene(m, 1)
    b, cyc2 = frame(m, png_dir, 'frame-2.png')
    check(b == 1, 'the second frame drew buffer 1')
    check(m.buffer(0) == buf0, 'buffer 0 untouched by it')

    print('frame 3: scene C on buffer 0, over scene A')
    scene(m, 2)
    b, cyc3 = frame(m, png_dir, 'frame-3.png')
    got = m.buffer(0)

    print('a fresh machine: scene C alone on buffer 0')
    m2 = Machine()
    m2.call('F_INIT')
    border(m2)
    m2.call('F_DIRECT')
    m2.mem.main[S['FRIN'] + 1] = 0
    scene(m2, 2)
    frame(m2)
    want = m2.buffer(0)
    diff = [a for a in range(0x3000) if got[a] != want[a]]
    check(not diff, 'the repair: buffer 0 after scene A then C is buffer 0 after C alone%s' % (
        '' if not diff else ' (%d bytes differ, first at offset &%04X)' % (len(diff), diff[0])))
    if diff:
        bad = bytearray(want)
        for a in diff:
            bad[a] = 0xF0
        png(bytes(bad), os.path.join(png_dir, 'frame-3-diff.png'))

    print('cycles: F_FRAME %s (frame 1 includes blanking both buffers); F_SHIP %s; F_CHAR %d' % (
        ', '.join(str(c) for c in (cyc1, cyc2, cyc3)),
        '..'.join(str(f(m.cycles['F_SHIP'])) for f in (min, max)), max(m.cycles['F_CHAR'])))
    print('PNGs in %s: frame-1.png, frame-2.png, frame-3.png' % png_dir)
    if FAILS:
        print('%d check(s) failed' % len(FAILS))
        sys.exit(1)
    print('all checks passed')


if __name__ == '__main__':
    main()
