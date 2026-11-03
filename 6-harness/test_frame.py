#!/usr/bin/env python3
"""The test of bank 6, the filled renderer's frame layer (docs/renderer.md).

    python3 6-harness/test_frame.py [--png DIR] [--nobuild]

Port (Model B): builds banks 5 and 6 (2-build-files/bank5.py and bank6.py;
the game must have been built, for the symbols they read and the flight
code's images) and runs them on py65's NMOS 6502 (the Model B's) with:

  * main RAM: the resident block A (the far calls, from the loader's
    image), the glue (GLUE.bin at GLUE%: the trampolines and GCALL), the
    loader's bank numbers and the game's variables;
  * &8000-&BFFF paged by writes to ROMSEL (&FE30): the flight code's home
    bank (D.CODEH, with a blueprint set, D.MOx, in its slot), bank 5,
    bank 6, or the flight code's cold bank (D.CODEC, with the disc layer's
    painter in its window);
    the MOS ROM (its font) at &C000;
  * the ships recorded by the game's own LL9 (H_LL42, S_SHIP, L_REC:
    F_SHIP), and every other entry called as the game calls it, LDX #n :
    JSR GCALL from main RAM with the home bank paged; the frame runs LL9's
    part 6 on (LL42F) and PTCLS (PTCLR) in the home bank through farH.

It records synthetic frames (ships placed and turned, one firing at us and
one exploding; the sun and the planet as discs, a distant ship,
stars, text, the sights and our laser beams) and checks that:

  * every bank 6 entry writes nothing but the renderer's zero page (&06-&27,
    the frame layer's &D2-&E1), the stack page, the screen buffers, the
    mailbox and the shared variables (&7E00-&7EFF), the glue's and the far
    calls' own bytes, &F4, ROMSEL and banks 5 and 6 (and F_FRAME, which runs
    game code, also the game's zero page and page 1, XX3); that the zero
    page is as it was after every call, but for the drawing's temporaries
    after F_FRAME (the frame keeps the rest: f_zsv, f_gkeep); that Y is kept
    and the caller's bank paged back;
  * the first frame enters space mode, copies buffer 1's border to buffer 0
    and draws buffer 0 (buffer 1 on show), and queues the flip; the next
    draws buffer 1;
  * the frame drew what was recorded: the sun's colour at its centre, every
    ship's centre filled, the last ship's vertices projected where they
    should be, the text's glyphs, the sights, the explosion's particles;
  * a buffer's next frame repairs it exactly: buffer 0 after scene A, then
    scene C is byte for byte buffer 0 after scene C alone (on a fresh
    machine), the text included (the text map, incremental per buffer);
  * the disc layer (gfx-frame.asm's f_ddraw, with its painter in the flight
    code's bank 7, gfx-raster_disc.asm and gfx-raster_disc2.asm) against a
    model of it: the bigger disc in front, the smaller behind it, the planet's
    surface (circle records as gfx-merid.asm's pc_circ makes them, from
    6-harness/planet_caps.py) as PC_ROWS has its rows (that model's rows,
    pixel for pixel); and over sequences of frames, each buffer's frame byte
    for byte the same as the scene drawn on a fresh machine.

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

HOME = 4                                         # the banks (the loader finds
RBANK, FBANK, COLD = 5, 6, 7                     # them; any distinct numbers)
BPSLOT = 0xB700                                  # (elite-map.asm)
STUB = 0x7FC0                                    # where the test's caller runs
FG = ['F_INIT', 'F_DIRECT', 'F_FRAME', 'F_SHIP', 'F_LINE', 'F_PDOT', 'F_PLANET', 'F_SHPPT',
      'F_CHAR', 'F_DELCHAR', 'F_CLRTEXT', 'F_GUN', 'F_HANG0', 'F_HANGAR', 'F_CLOUD', 'F_SETLD']
# the drawing's temporaries, which game code the frame runs may leave changed
# (blib.mjs's DRAW_EXCLUDE): name, length
DRAWTMP = [('SC', 2), ('T1', 1), ('P', 3), ('Q', 1), ('R', 1), ('S', 1), ('T', 1), ('U', 1), ('XX15', 6),
           ('XX12', 6), ('K', 4), ('K2', 4), ('K3', 14), ('K4', 2), ('K5', 4), ('K6', 5), ('XX16', 18),
           ('XX0', 2), ('XX', 2), ('YY', 2), ('XSAV', 1), ('YSAV', 1), ('XX17', 1), ('XX13', 1), ('CNT', 1),
           ('CNT2', 1), ('STP', 1), ('XX4', 1), ('XX20', 1), ('ZZ', 1), ('V', 2), ('XX14', 1), ('SWAP', 1),
           ('XX18', 4), ('XX19', 2)]
FAILS = []


def check(cond, what):
    print(('  ok   ' if cond else '  FAIL ') + what)
    if not cond:
        FAILS.append(what)


def syms_of(name):
    t = open(os.path.join(OUT, name + '-symbols.txt')).read()
    return {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", t)}


def consts():
    """elite-map.asm's constants, bank6-game.asm's (the game's),
    gfx-faces.asm's and gfx-rws.asm's (BeebAsm's symbol dump has labels only)"""
    out = {}
    ms = os.path.join(REPO, '1-source-files', 'main-sources')
    for f in (os.path.join(ms, 'elite-map.asm'), os.path.join(OUT, 'bank6-game.asm'),
              os.path.join(ms, 'gfx-faces.asm'), os.path.join(ms, 'gfx-rws.asm')):
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
    for tool in ('bank5.py', 'bank6.py'):
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
        self.fcsize = S['FCSLOT_SIZE']
        cold = open(os.path.join(OUT, 'D.CODEC.bin'), 'rb').read()
        self.banks = {HOME: bytearray(open(os.path.join(OUT, 'D.CODEH.bin'), 'rb').read()),
                      RBANK: bytearray(open(os.path.join(OUT, 'BANK5.bin'), 'rb').read()),
                      FBANK: bytearray(open(os.path.join(OUT, 'BANK6.bin'), 'rb').read()),
                      COLD: bytearray(cold + bytes(0x4000 - len(cold)))}
        os_rom = os.path.join(HERE, 'node_modules', 'jsbeeb', 'public', 'roms', 'os.rom')
        self.main[0xC000:0x10000] = open(os_rom, 'rb').read()[:0x4000]
        miss = open(os.path.join(OUT, 'MISSILE.bin'), 'rb').read()
        self.main[0x7F00:0x7F00 + len(miss)] = miss
        from test_routines import map_constants, main_part
        for a, d in main_part(self.banks[HOME], map_constants()):   # (the main RAM
            self.main[a:a + len(d)] = d                             # part, as PCLI)
        self.sel = HOME
        ld = S['loader']                         # the resident block A (the far
        lb = open(os.path.join(OUT, 'ELITE4.bin'), 'rb').read()   # calls), as the loader
        self.main[0x400:0x800] = lb[ld['RESAcode'] - 0x1900:ld['RESAcode'] - 0x1900 + 0x400]   # puts it
        g = open(os.path.join(OUT, 'GLUE.bin'), 'rb').read()
        self.main[S['GLUE%']:S['GLUE%'] + len(g)] = g
        ok = bytearray(0x10000)                  # the write guard's allowed bytes
        for lo, hi in ((0x06, 0x28), (0xD2, 0xE2), (0xF4, 0xF5), (0x100, 0x200), (0x1000, 0x7000),
                       (0x7E00, 0x7F00), (S['rtA'], S['rtA'] + 3), (S['rtl'] + 1, S['rtl'] + 3), (S['rtj'] + 1, S['rtj'] + 2),
                       (ld['fA'], ld['fA'] + 5), (ld['fpc'] + 1, ld['fpc'] + 3), (ld['fpj'] + 1, ld['fpj'] + 3)):
            ok[lo:hi] = b'\1' * (hi - lo)
        self.ok = ok
        game = bytearray(ok)                     # game code (LL9, and what the
        mc = map_constants()                     # frame runs) also writes the
        for lo, hi in ((0, 0x100), (0x300, 0x400), (0x900, 0xD00),   # game's zero
                       (mc['PROGM%'], mc['PROGM_END%']), (mc['PROGX%'], mc['PROGX_END%'])):
            game[lo:hi] = b'\1' * (hi - lo)     # page, UP, K% and the main RAM part
        self.okgame = game
        self.guard = ok
        self.bad = []

    def blueprints(self, name):
        """the blueprint set D.MOx into the home bank's slot, and its face
        lists, after the slot's pages, into bank 6's (as PCLI, then LOMOD's
        F_SETLD, do; elite-shipset.asm)"""
        d = open(os.path.join(OUT, 'D.MO%s.bin' % name), 'rb').read()
        n = 0xC000 - BPSLOT
        self.banks[HOME][BPSLOT - 0x8000:0x4000] = d[:n]
        fcslot = 0xBFC0 - self.fcsize
        self.banks[FBANK][fcslot - 0x8000:fcslot - 0x8000 + self.fcsize] = d[n:n + self.fcsize].ljust(self.fcsize, b'\0')

    def __getitem__(self, a):
        if 0x8000 <= a < 0xC000:
            return self.banks[self.sel][a - 0x8000]
        return self.main[a]

    def __setitem__(self, a, v):
        if 0x8000 <= a < 0xC000:
            self.banks[self.sel][a - 0x8000] = v
            return
        if a == 0xFE30:
            self.sel = v & 15
            return
        if not self.guard[a]:
            self.bad.append(a)
        if a < 0xC000:
            self.main[a] = v


class Machine:
    def __init__(self):
        from py65.devices.mpu6502 import MPU
        self.S = dict(consts())
        self.S.update(syms_of('bank6'))
        self.S['loader'] = syms_of('loader')
        self.F = syms_of('flight')
        self.mem = Mem(self.S)
        S, m = self.S, self.mem.main
        m[S['BANK5']], m[S['BANK6']] = RBANK, FBANK
        m[S['loader']['BANK7']] = COLD
        m[S['loader']['BANK4']] = HOME
        self.tmp = set()                         # the drawing's temporaries
        for n, k in DRAWTMP:
            self.tmp.update(range(self.F[n], self.F[n] + k))
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
        mem.guard = mem.okgame if entry == 'F_FRAME' else mem.ok
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
        zd = [i for i in range(256) if mem.main[i] != zp[i] and i not in (0xF4,) and
              not (entry == 'F_FRAME' and i in self.tmp)]
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

    def gcall(self, addr, maxcyc=2_000_000):
        """JSR addr (game code in the home bank) from main RAM, the home bank
        paged, with the game's write guard; returns the cycles"""
        mpu, mem = self.mpu, self.mem
        mem.main[STUB:STUB + 3] = bytes([0x20, addr & 255, addr >> 8])
        mem.bad = []
        mem.guard = mem.okgame
        mpu.p, mpu.sp = 0x24, 0xFF
        mpu.pc = STUB
        c0 = mpu.processorCycles
        while mpu.pc != STUB + 3:
            mpu.step()
            if mpu.processorCycles - c0 > maxcyc:
                raise RuntimeError('runaway in &%04X at &%04X' % (addr, mpu.pc))
        if mem.bad:
            FAILS.append('game code &%04X wrote outside its areas: %s' % (addr, ' '.join('&%04X' % b for b in sorted(set(mem.bad))[:12])))
            print('  FAIL', FAILS[-1])
        if mem.sel != HOME or mem.main[0xF4] != HOME:
            FAILS.append('game code &%04X did not page the home bank back' % addr)
            print('  FAIL', FAILS[-1])
        return mpu.processorCycles - c0

    def planet(self):
        """the hooks' record of the sun or the planet (CIRCLE's H_CIRC, SUN)"""
        self.call('F_PLANET')

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
    """what TTX66 leaves on buffer 1: its window black, its border (line 0,
    pixels 0-1 and 254-255 of every line); buffer 0 holds garbage (a disc
    command has used it: F_INIT marks it so)"""
    import random
    rnd = random.Random(7)
    base0, base1 = m.S['BUF0'], m.S['SCREEN%']
    for a in range(0x3000):
        m.mem.main[base0 + a] = rnd.randrange(256)
        m.mem.main[base1 + a] = 0
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


HEAP = 0x0A00                                    # the slots' ship line heaps (K%)


def record_ship(m, gtype, pos, angles, slot, fire=False, explode=False):
    """LL9 for blueprint gtype (32: the dodecahedron station, type 2) in slot
    slot, at view position pos, orientation from angles (sidev, roofv, nosev
    = R x, R y, -R z: det -1, as ZINF's); firing at us (fire) or just killed
    (explode: LL9 starts its explosion cloud); the ship's data copied back to
    its slot afterwards, as the main loop does"""
    r = rot(*angles)
    side, roof, nose = col(r, 0), col(r, 1), [-c for c in col(r, 2)]
    S, F = m.S, m.F
    inwk = bytearray(37)
    for i, v in enumerate(pos):                  # x, y, z: sign-magnitude, 24-bit
        q = int(v)
        inwk[3 * i], inwk[3 * i + 1], inwk[3 * i + 2] = abs(q) & 255, (abs(q) >> 8) & 255, 0x80 if q < 0 else 0
    for k, v in enumerate((nose, roof, side)):      # INWK+9.. nosev, roofv, sidev
        for i in range(3):
            q = int(round(v[i] * 0x6000))
            mag = min(abs(q), 0x7FFF)
            inwk[9 + 6 * k + 2 * i] = mag & 255
            inwk[10 + 6 * k + 2 * i] = (mag >> 8) | (0x80 if q < 0 else 0)
    inwk[31] = 0x40 if fire else 0x80 if explode else 0
    heap = HEAP + 0x40 * slot
    inwk[33], inwk[34] = heap & 255, heap >> 8
    inwk[35] = 0x80
    for i in range(37):
        m.poke(F['INWK'] + i, inwk[i])
    t = 2 if gtype == 32 else gtype
    bp = m.mem.banks[HOME][BPSLOT - 0x8000 + 2 * (t - 1):][:2]
    m.poke(F['XX0'], bp[0])
    m.poke(F['XX0'] + 1, bp[1])
    m.poke(F['TYPE'], t)
    inf = F['K%'] + slot * S['NI%']
    m.poke(F['INF'], inf & 255)
    m.poke(F['INF'] + 1, inf >> 8)
    m.poke(F['XSAV'], slot)
    m.poke(F['FRIN'] + slot, t)
    m['QQ11'] = 0
    m.gcall(F['LL9'])
    for i in range(37):                          # (MA15's copy back to the slot)
        m.poke(inf + i, m.mem.main[F['INWK'] + i])


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
    """record scene k (0: A, 1: B, 2: C, 3: D, 4: E: the planet alone moving, for
    the incremental disc); returns what to look for"""
    S = m.S
    look = {}
    m['QQ11'] = 0
    if k == 0:                                   # the sun, top right
        m['TYPE'] = 129
        m.put16('K3', 210)
        m.put16('K4', 40)
        m['K'] = 30
        m.planet()
        look['sun'] = (210, 40)
    m['TYPE'] = 128                              # the planet
    px, py, pr = {1: (70, 130, 46), 3: (64, 136, 54), 4: (74, 126, 47)}.get(k, (60, 140, 50))
    m.put16('K3', px)
    m.put16('K4', py)
    m['K'] = pr
    m.poke(S['INWK'] + 6, 0)
    m.poke(S['INWK'] + 7, 0x40)
    m.planet()
    look['planet'] = (px - pr // 2, py + pr // 3)
    look['ships'] = []
    if k == 0:
        m.mem.blueprints('C')
        ships_rec = [(11, (-40, 10, 700), (0.4, 0.7, 0.2), dict(fire=True)),    # Cobra Mk III, firing
                     (2, (200, -40, 1400), (0.3, 0.5, 0.1), {}),               # Coriolis station
                     (13, (90, 60, 2600), (1.2, 0.3, 0.4), {}),                # Boa, far (winding)
                     (16, (-120, -60, 1000), (0.2, 0.9, 0.6), dict(explode=True))]   # Viper, exploding
    else:
        m.mem.blueprints('B')
        ships_rec = [(32, (-60, 30, 1500), (0.5, 0.2, 0.3), {}),    # Dodecahedron station
                     (20, (60, -20, 500), (0.2, 2.6, 0.5), {}),     # Adder
                     (4, (0, 50, 400), (0.7, 0.2, 0.1), {})]        # Alloy plate
    for slot, (ty, pos, ang, kw) in enumerate(ships_rec):
        record_ship(m, ty, pos, ang, slot + 2, **kw)
        if not kw.get('explode'):
            look['ships'].append((int(128 + 256 * pos[0] / pos[2]), int(96 - 256 * pos[1] / pos[2]), ty))
        else:
            look['cloud'] = (int(128 + 256 * pos[0] / pos[2]), int(96 - 256 * pos[1] / pos[2]))
    look['last'] = min(ships_rec, key=lambda s: s[1][2])[:3]
    m['X1'], m['Y1'], m['X2'], m['Y2'] = 20, 20, 120, 90     # an enemy laser
    m.call('F_LINE')
    m['TYPE'] = 11                               # a distant ship
    m.put16('K3', 240)
    m.put16('K4', 170)
    m.call('F_SHPPT')
    for i in range(1, S['NOST'] + 1):            # the stardust (the hooks' job)
        m.poke(S['MB_SX'] + i, (37 * i + 11 * k) % 250 + 3)
        m.poke(S['MB_SY'] + i, (53 * i + 5 * k) % 186 + 3)
        m.poke(S['MB_SS'] + i, 1 + i % 3)
    m.poke(S['MB_SX'], 0)
    m.poke(S['MB_SS'], 0)
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



# ---------------------------------------------------------------------------
# The disc layer (gfx-frame.asm's f_dprep, f_ddraw and f_disc2, the painter in
# the flight code's bank 7): a model of what it draws, and scenes

sys.path.insert(0, HERE)
import planet_caps as PCM                        # (the circle engine's model)


def fc_planet():
    """gfx-frame.asm's colour B of the planet's surface (FC_PLLE, FC_PLLO)"""
    t = open(os.path.join(REPO, '1-source-files', 'main-sources', 'gfx-frame.asm'), encoding='latin-1').read()
    m = re.search(r'FC_PLLE\s*=\s*&([0-9A-Fa-f]+)\s*:\s*FC_PLLO\s*=\s*&([0-9A-Fa-f]+)', t)
    return int(m.group(1), 16), int(m.group(2), 16)


def isqrt_hw(r):
    """the half-width table: floor(sqrt(r * r - d * d)) for d = 0 to r"""
    return [math.isqrt(r * r - d * d) for d in range(r + 1)]


def disc_spans(cx, cy, r):
    """{row: (left, right)} of a disc as f_discspans clips it (rows 1 to 191,
    columns 2 to 253; a row with nothing left of it is not there)"""
    hw, out = isqrt_hw(r), {}
    for y in range(max(cy - r, 1), min(cy + r, 191) + 1):
        n = hw[abs(y - cy)]
        xl, xr = max(cx - n, 2), min(cx + n, 253)
        if xr >= 2 and xl <= 253 and xl <= xr:
            out[y] = (xl, xr)
    return out


def le(v, n):
    return [(v >> (8 * i)) & 255 for i in range(n)]


def surface(cx, cy, r, vecs, typ, qq2):
    """the planet's circles as PF_HOOK makes them (planet_caps.py's model of
    gfx-planet7.asm and gfx-merid.asm's pc_circ): (PF_CLS, the records'
    bytes for PCB, PC_N, pc_inv, and the model's base and records)"""
    inwk = [0] * 36
    for k, v in enumerate(vecs[0] + vecs[1] + vecs[2]):
        q = min(abs(v), 32767)
        inwk[9 + 2 * k], inwk[10 + 2 * k] = q & 255, (q >> 8) | (0x80 if v < 0 else 0)
    base, circs = PCM.pf_records(inwk, qq2, typ)
    recs = [PCM.circ_consts(cx, cy, r, v, c8, cn, kn) for v, c8, cn, kn in circs]
    for c in recs:
        if c is not None:
            base ^= PCM.rec_parity(c)
    kept = [c for c in recs if c is not None and not c['none']]
    pcb = []
    for c in kept:
        pcb += le(c['a'], 4) + le(c['K2'], 4) + le(c['K0'], 4) + [c['s0'] & 255] + le(c['L0'], 2) + \
            le(c['C0'] >> 16, 2) + le(c['Yc'], 2) + [c['F'], c['T1'], c['T2'], c['M1'], c['M2']]
    cls = 0 if typ == 128 else 1
    return (cls | (0x80 if kept or base else 0)), pcb, len(kept), base, recs


def surface_rows(cx, cy, r, surf):
    """the model's rows of the planet's surface: {y: (colour at the left end,
    [boundaries])}, as PC_ROWS makes them for the clipped spans"""
    spans = disc_spans(cx, cy, r)
    if not spans:
        return {}
    ndt, ndb = min(spans), max(spans)
    ndl, ndr = [255] * 192, [0] * 192
    for y, (l, rr) in spans.items():
        ndl[y], ndr[y] = l, rr
    return PCM.body_rows(surf[3], surf[4], ndt, ndb, ndl, ndr)


def put_pixel(buf, x, y, byte):
    a = addr(x, y)
    m = 0x88 >> (x & 3)
    buf[a] = (buf[a] & ~m & 255) | (byte & m)


def model_discs(S, discs):
    """the window (rows 1..191, columns 2..253) as the frame draws discs =
    [(kind, cx, cy, r, surf)] (surf: surface()'s, a planet's circles, or
    None) with nothing else: the bigger (the sun if not smaller) as the
    layer, with its surface (a planet's, in its colours A and B), the other
    behind it, plain"""
    buf = bytearray(0x3000)
    sun = [d for d in discs if d[0] == 'sun']
    pl = [d for d in discs if d[0] == 'planet']
    lay = pl[0] if pl and (not sun or sun[0][3] < pl[0][3]) else sun[0] if sun else None
    if lay is None:
        return buf
    lspans = disc_spans(*lay[1:4])
    cb = fc_planet()
    for d in discs:
        kind, cx, cy, r, surf = d
        ce, co = (S['FC_SUNE'], S['FC_SUNO']) if kind == 'sun' else (S['FC_PLANE'], S['FC_PLANO'])
        rows = surface_rows(cx, cy, r, surf) if d is lay and kind == 'planet' and surf and surf[0] & 0x80 else {}
        for y, (xl, xr) in disc_spans(cx, cy, r).items():
            p, xs = rows.get(y, (0, []))
            for x in range(xl, xr + 1):
                if d is not lay and y in lspans and lspans[y][0] <= x <= lspans[y][1]:
                    continue                     # (behind the layer)
                b = (p + sum(1 for v in xs if v <= x)) & 1
                c = (cb[0], cb[1]) if b else (ce, co)
                put_pixel(buf, x, y, c[y & 1])
    return buf


def rand_frame(rnd):
    """a random orientation, scaled to &6000 with a few % noise, as Elite's"""
    q = [rnd.gauss(0, 1) for _ in range(4)]
    n = math.sqrt(sum(x * x for x in q))
    w, x, y, z = [v / n for v in q]
    R = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[int(round(R[j][i] * 24576 * (1 + rnd.uniform(-0.04, 0.04)))) for j in range(3)] for i in range(3)]


def spin(vecs, ang):
    """the frame turned about its own y axis (as the planet spins)"""
    c, s_ = math.cos(ang), math.sin(ang)
    return [[int(round(c * v[0] - s_ * v[2])), v[1], int(round(s_ * v[0] + c * v[2]))] for v in vecs]


def disc_scene(m, discs, ships_rec=(), lines=()):
    """record discs (as model_discs), their surface's circles in the mailbox
    as PF_HOOK leaves them, then ships and lines over them; no stars, text or
    sights"""
    S = m.S
    m['QQ11'] = 0
    m['VIEW'] = 1                                # (no lens flare)
    m['PF_CLS'] = 0
    for kind, cx, cy, r, surf in discs:
        m['TYPE'] = 129 if kind == 'sun' else 128
        m.put16('K3', cx & 0xFFFF)
        m.put16('K4', cy & 0xFFFF)
        m['K'] = r
        m.poke(S['INWK'] + 6, 0)                 # (its z, far: the ships are in front)
        m.poke(S['INWK'] + 7, 0x40)
        m.planet()
        if surf:
            m['PF_CLS'], pcb, n, base = surf[0], surf[1], surf[2], surf[3]
            for i, v in enumerate(pcb):
                m.poke(S['PCB'] + i, v)
            m['PC_N'], m['pc_inv'] = n, base
    if ships_rec:
        m.mem.blueprints('C')
    for i, (t, pos, ang) in enumerate(ships_rec):
        record_ship(m, t, pos, ang, i + 2)
    for x1, y1, x2, y2 in lines:
        m['X1'], m['Y1'], m['X2'], m['Y2'] = x1, y1, x2, y2
        m.call('F_LINE')
    for i in range(1, S['NOST'] + 1):
        m.poke(S['MB_SS'] + i, 0)
    m.call('F_CLRTEXT', a=0, y=23)
    m['GSIGHT'] = 0
    m['GLASV'] = 0


def fresh(discs, ships_rec=(), lines=(), buf=0):
    """a fresh machine's frame of the scene into buffer buf, after empty
    frames (the first frame starts buffer 0 afresh, F_INIT having marked it
    as a disc command's, which drops the planet's circles of that iteration:
    f_b0new); returns the machine and the buffer"""
    m = Machine()
    m.call('F_INIT')
    border(m)
    m.call('F_DIRECT')
    m.mem.main[m.S['FRIN'] + 1] = 0
    for _ in range(2 - buf):
        disc_scene(m, [])
        frame(m)
    disc_scene(m, discs, ships_rec, lines)
    b, _ = frame(m)
    return m, m.buffer(b)


def b6(m, name, off=0):
    return m.mem.banks[FBANK][m.S[name] + off - 0x8000]


def disc_tests(png_dir):
    import random
    rnd = random.Random(11)
    qq2s = ([0x4A, 0x5A, 0x48, 0x02, 0x53, 0xB7], [0x12, 0x34, 0x56, 0x78, 0x3E, 0xC5])
    print('the disc layer: single frames against the model')
    v1, v2, v3 = rand_frame(rnd), rand_frame(rnd), rand_frame(rnd)
    bb = lambda cx, cy, r, v: surface(cx, cy, r, v, 128, qq2s[0])
    cr = lambda cx, cy, r, v: surface(cx, cy, r, v, 130, qq2s[1])
    singles = [
        [('planet', 128, 96, 60, None)],
        [('sun', 40, 170, 90, None)],
        [('planet', 300, 50, 200, None)],                                  # off the right
        [('planet', -60, 100, 120, None), ('sun', 200, 30, 20, None)],     # the sun behind it
        [('sun', 128, 96, 70, None), ('planet', 60, 60, 30, None)],        # the sun the layer
        [('planet', 128, 96, 80, bb(128, 96, 80, v1))],                    # the beach ball
        [('planet', 20, 180, 150, cr(20, 180, 150, v2))],                  # craters, partly off
        [('planet', 110, 100, 90, bb(110, 100, 90, v3)), ('sun', 180, 50, 40, None)],   # and the sun
        [('planet', 128, 96, 250, bb(128, 96, 250, v2))],                  # filling the window
    ]
    for i, d in enumerate(singles):
        m, got = fresh(d)
        want = model_discs(m.S, d)
        bad = [(x, y) for y in range(1, 192) for x in range(2, 254) if pixel(got, x, y) != pixel(want, x, y)]
        check(not bad, 'disc scene %d: the window is the model%s' % (i, '' if not bad else ' (%d pixels differ, first %r)' % (len(bad), bad[0])))
        if bad:
            png(got, os.path.join(png_dir, 'disc-%d-got.png' % i))
            png(bytes(want), os.path.join(png_dir, 'disc-%d-want.png' % i))
        lay = [x for x in d if x[0] == 'planet' and x[4]]
        if lay and lay[0][4][0] & 0x80:                       # PC_ROWS' rows, as the model's
            _, cx, cy, r, surf = lay[0]
            rows = surface_rows(cx, cy, r, surf)
            rb = []
            for y, (p, xs) in rows.items():
                n = b6(m, 'R_NDN', y)
                gx = [b6(m, 'R_NDX%d' % k, y) for k in range(n & 0x7F)]
                if (n >> 7, gx) != (p & 1, xs):
                    rb.append((y, (n >> 7, gx), (p, xs)))
            check(not rb, 'disc scene %d: PC_ROWS\' rows are planet_caps.py\'s%s' % (i, '' if not rb else ' (row %d: %r, the model %r)' % rb[0]))
    print('the disc layer: a moving sequence (each frame against a fresh machine)')
    m = Machine()
    m.call('F_INIT')
    border(m)
    m.call('F_DIRECT')
    m.mem.main[m.S['FRIN'] + 1] = 0
    cx, cy, r = 100, 120, 50
    vecs = rand_frame(rnd)
    sx, sy, sr = 200, 40, 20
    for f in range(30):
        if f < 12 or 20 <= f < 26:               # (from 12 to 19, the disc stays put:
            cx += rnd.randint(-12, 12)           # only what the repair blacked is
            cy += rnd.randint(-10, 10)           # drawn again)
            r = max(6, min(250, r + rnd.randint(-6, 14)))
        vecs = spin(vecs, 0.25)
        kind = 'sun' if f in (6, 7) else 'planet'
        surf = None
        if kind == 'planet' and (f % 3 or f >= 20):
            surf = surface(cx, cy, r, vecs, 128 if f % 2 else 130, qq2s[f % 2])
        discs = [] if f == 10 else [(kind, cx, cy, r, surf)]
        if f in (4, 5, 13, 14, 21, 22, 23, 27):  # the second disc, moving
            sx, sy = sx - 7, sy + 5
            discs.append(('sun', sx, sy, sr + f % 3, None))
        if f in (24, 25):                        # the sun bigger: the planet behind it
            discs = [('sun', 128, 96, r + 10, None), ('planet', cx, cy, r, surf)]
        shp = [(11, (rnd.randint(-80, 80), rnd.randint(-40, 40), rnd.randint(300, 900)), (0.4 * f, 0.7, 0.2))] if f % 2 else []
        lns = [(rnd.randint(2, 253), rnd.randint(1, 191), rnd.randint(2, 253), rnd.randint(1, 191))] if f % 4 == 1 else []
        disc_scene(m, discs, shp, lns)
        b, _ = frame(m)
        got = m.buffer(b)
        _, want = fresh(discs, shp, lns, b)
        diff = [a for a in range(0x3000) if got[a] != want[a]]
        check(not diff, 'sequence frame %d (buffer %d): as a fresh frame%s' % (f, b, '' if not diff else ' (%d bytes differ, first at offset &%04X)' % (len(diff), diff[0])))
        if diff:
            png(got, os.path.join(png_dir, 'seq-%d-got.png' % f))
            png(want, os.path.join(png_dir, 'seq-%d-want.png' % f))

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
    m['QQ11'] = 1                                # text drawn directly: noted (the
    text(m, '15', 1, 1)                          # first three), then given to the
    text(m, 'DIRECT', 4, 3)                      # cells buffer 0 may show
    m.call('F_DIRECT')
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
    check(buf1 == b1_before, "buffer 1 (TTX66's) left as it was")
    cx, cy = look['cloud']
    check(sum(pixel(buf0, x, y) == 3 for x in range(max(cx - 24, 2), min(cx + 24, 253))
              for y in range(max(cy - 24, 1), min(cy + 24, 191))) >= 8, "the explosion's particles drawn")
    ty, pos, ang = look['last']                  # the nearest ship, projected last
    s = ships()[ty]
    r = rot(*ang)
    side, roof, nose = col(r, 0), col(r, 1), [-c for c in col(r, 2)]
    near = 0
    for vi, v in enumerate(s['verts']):
        p3 = [pos[i] + v['x'] * side[i] + v['y'] * roof[i] + v['z'] * nose[i] for i in range(3)]
        ex, ey = 128 + 256 * p3[0] / p3[2], 96 - 256 * p3[1] / p3[2]
        gx, gy = sx_sy(m, vi)
        near += abs(gx - ex) <= 4 and abs(gy - ey) <= 4
    check(near >= len(s['verts']) // 3, 'the frame projected the nearest ship (%d of %d vertices where they should be)' % (near, len(s['verts'])))
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

    print('frames 4 and 5: scenes D and E (the planet moving, alone) on buffers 1 and 0')
    scene(m, 3)
    frame(m, png_dir, 'frame-4.png')
    scene(m, 4)
    b, cyc5 = frame(m, png_dir, 'frame-5.png')
    got = m.buffer(0)
    m3 = Machine()
    m3.call('F_INIT')
    border(m3)
    m3.call('F_DIRECT')
    m3.mem.main[S['FRIN'] + 1] = 0
    scene(m3, 4)
    frame(m3)
    want = m3.buffer(0)
    diff = [a for a in range(0x3000) if got[a] != want[a]]
    check(b == 0 and not diff, 'the incremental disc: buffer 0 after scenes A, C and E is buffer 0 after E alone%s' % (
        '' if not diff else ' (%d bytes differ, first at offset &%04X)' % (len(diff), diff[0])))
    if diff:
        bad = bytearray(want)
        for a in diff:
            bad[a] = 0xF0
        png(bytes(bad), os.path.join(png_dir, 'frame-5-diff.png'))

    disc_tests(png_dir)

    print('cycles: F_FRAME %s (frame 1 includes clearing buffer 0); F_CHAR %d' % (
        ', '.join(str(c) for c in (cyc1, cyc2, cyc3, cyc5)), max(m.cycles['F_CHAR'])))
    print('PNGs in %s: frame-1.png, frame-2.png, frame-3.png' % png_dir)
    if FAILS:
        print('%d check(s) failed' % len(FAILS))
        sys.exit(1)
    print('all checks passed')


if __name__ == '__main__':
    main()
