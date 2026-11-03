#!/usr/bin/env python3
"""Soak test for bank 5, the filled renderer's rasteriser (docs/renderer.md).

    python3 6-harness/test_raster.py [--seed N] [--quick] [--only spans,polys,...]

Port (Model B): a thin adapter over the BBC Master port's test (its
6-harness/test_raster.py, over the Demonstration Disc port's raster_model.py:
the pixel-exact Python reference, the write guard and the tests), pointed at
bank 5 as 2-build-files/bank5.py builds it (it is run first, so the test is
of the current sources):

  * the machine is py65's NMOS 6502 (the Model B's), with bank 5's image at
    &8000-&BFFF and nothing else paged; each entry point is called through
    bank 5's jump table, RJT, as the frame layer's trampolines call it;
  * the screen is buffer 0 at &1000 or buffer 1 at &4000 (gfx-rws.asm's
    BUF0 and SCREEN%), as the last R_SETBUF chose: the reference model's
    12K screen is that buffer's;
  * the inputs (vertices, line ends, stars) are in the mailbox, MBOX
    (&7E00), the state in bank R: the model reads and writes them by name, so
    it needs no change;
  * the write guard allows exactly the renderer's zero page (&06-&27), the
    stack page, the two screen buffers, the mailbox and bank 5; and the row
    runs must be left as they were (no RTS left planted), except that a
    page's stores may have been moved to the other buffer (r_pgfix: the
    high byte of each STA's operand, by &30);
  * there is no disc layer (no R_DISCROWS): the frames test runs its 'none'
    scenario (no disc), with R_REPAIR where the model calls R_DISCROWS;
  * R_POLY's 4-row colour: every polygon is drawn with R_COL2 = R_COLE and
    R_COL3 = R_COLO, the 2-row colour pair the reference models;
  * the stars are the Master port's: a star's pixels within one screen byte
    are set only if the whole byte is black (star_ref, as the Master port's
    test models it).

Needs py65 and BeebAsm ($BEEBASM, or beebasm on the path). Exit status 0
only if every test passes.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import raster_model as tr                        # noqa: E402  (the model and its tests)

MS = os.path.join(REPO, '1-source-files', 'main-sources')
BEEBASM = os.environ.get('BEEBASM', 'beebasm')
FILES = ['gfx-raster.asm', 'gfx-raster_poly.asm', 'gfx-raster_line.asm', 'gfx-raster_lcold.asm',
         'gfx-raster_reset.asm', 'gfx-raster_init.asm', 'gfx-raster_rep.asm', 'gfx-raster_dq.asm']
CONFIG = {}
tr.NSTARS = int(re.search(r'^\s*NOST\s*=\s*(\d+)', open(os.path.join(MS, 'elite-source-flight.asm'),
                encoding='latin-1').read(), re.M).group(1)) + 1   # (the stars the game records: MB_SX ..)
ENTRIES = ['R_INIT', 'R_SETBUF', 'R_RESETBUF', 'R_REPAIR', 'R_SPAN', 'R_MARKDIRTY', 'R_DOT',
           'R_POLY', 'R_LINE', 'R_STARERASE', 'R_STARPLOT']


def rws_constants():
    """elite-map.asm's and gfx-rws.asm's constants (the buffers, the
    mailbox's and bank R's state's addresses)"""
    out = {}
    for f in ('elite-map.asm', 'gfx-rws.asm'):
        for l in open(os.path.join(MS, f), encoding='latin-1'):
            m = re.match(r'^\s*([A-Za-z_][\w]*)\s*=\s*([^\\]+)', l)
            if m:
                e = re.sub(r'&([0-9A-Fa-f]+)', r'0x\1', m.group(2)).strip()
                try:
                    out[m.group(1)] = eval(e, {}, dict(out))
                except Exception:
                    pass                         # (not a plain address)
    return out


def build():
    """bank 5, as the game's build makes it: BANK5.bin and its symbols"""
    r = subprocess.run([sys.executable, os.path.join(REPO, '2-build-files', 'bank5.py'), BEEBASM],
                       capture_output=True, text=True)
    if r.returncode:
        print(r.stdout, r.stderr)
        raise SystemExit('bank 5 did not build')
    out = os.path.join(REPO, '3-assembled-output')
    syms = rws_constants()                       # (BeebAsm's symbol dump has labels only)
    for k, v in re.findall(r"'([^']+)':(-?\d+)L?", open(os.path.join(out, 'bank5-symbols.txt')).read()):
        syms.setdefault(k, int(v))
    for k in ('R_NDT', 'R_NDB', 'R_NDF', 'R_DBE', 'R_DBO', 'R_DCE', 'R_DCO'):
        syms.setdefault(k, syms['MBOX'] + 0x9D)  # (the disc layer's inputs, which the model's
                                                 # frames set: bank 5 has no disc layer)
    return syms, open(os.path.join(out, 'BANK5.bin'), 'rb').read(), r.stdout.strip()


def active_lines(path):
    """the lines of a source that bank 5 assembles (its IF conditions
    evaluated as CONFIG has them)"""
    out, stack = [], []
    for l in open(path, encoding='latin-1').read().split('\n'):
        t = l.split('\\')[0].strip()
        m = re.match(r'^IF\b(.*)$', t)
        if m:
            c = m.group(1).replace('<>', '!=').replace('=', '==').replace('!==', '!=')
            c = re.sub(r'\bAND\b', ' and ', re.sub(r'\bOR\b', ' or ', c))
            try:
                v = bool(eval(c, {}, dict(CONFIG)))
            except Exception:
                v = True                         # (a condition on anything else)
            stack.append([v, v])
            continue
        if re.match(r'^ELIF\b', t) and stack:
            raise SystemExit('ELIF in %s: not handled' % path)
        if re.match(r'^ELSE\b', t) and stack:
            stack[-1][0] = not stack[-1][1]
            continue
        if re.match(r'^ENDIF\b', t) and stack:
            stack.pop()
            continue
        if all(s[0] for s in stack):
            out.append(l)
    return out


def check_patch_sites():
    """every instruction of bank 5's code that names buffer 0's state must be
    a patch site that R_SETBUF (or its r_sbpoly) patches, with its own
    array's high byte (the Master port's check, over the lines bank R
    assembles)"""
    src = []
    for f in FILES:
        src += active_lines(os.path.join(MS, f))
    txt = '\n'.join(src)
    names = ('r_dl', 'r_dr', 'r_s0y', 'r_s0x', 'r_s0a', 'r_s0b')
    sites, listed = set(), set(re.findall(r'(r_pt\d+)\+2', txt))
    bad = []
    for ln in src:
        code = ln.split('\\')[0]
        m = re.match(r'\s*(\.\^?(r_pt\d+))?\s*([A-Z]{3})\s+([^ ;]+)', code)
        if not m:
            continue
        base = re.split(r'[,+\-]', m.group(4))[0]
        if base in names and 'nopatch' not in ln:
            if not m.group(2):
                bad.append(ln.strip())
            else:
                sites.add(m.group(2))
    assert not bad, 'unpatched buffer references: %s' % bad
    assert not sites - listed, 'patch sites not in R_SETBUF: %s' % (sites - listed)
    use = dict(re.findall(r'\.\^?(r_pt\d+)\s+[A-Z]{3}\s+(r_\w+)', txt))
    for start in ('.R_SETBUF', '.r_sbpoly'):
        if start not in txt:
            continue
        grp = None
        for ln in txt[txt.index(start):].splitlines():
            m = re.search(r'group (r_\w+)', ln)
            if m:
                grp = m.group(1)
            m = re.match(r'\s*STA (r_pt\d+)\+2', ln)
            if m and grp:
                assert use[m.group(1)] == grp, 'site %s patched as %s' % (m.group(1), grp)
            if ln.startswith('}'):
                break
    return len(sites)


class Machine(tr.Machine):
    """an NMOS 6502 with bank 5 at &8000 and both screen buffers"""

    def __init__(self, org=None, seed=1):
        import random
        from py65.devices.mpu6502 import MPU
        self.syms, image, self.sizemsg = build()
        rnd = random.Random(seed)
        self.mem = [rnd.randrange(256) for _ in range(65536)]
        self.mem[0x8000:0xC000] = list(image)
        self.mpu = MPU(memory=self.mem)
        self.cycles = 0
        self.guard = True
        self.buf = 0
        self.lo, self.hi = 0x8000, 0xC000
        self.image = list(image)
        self.jt = {n: self.syms['RJT'] + 3 * i for i, n in enumerate(ENTRIES)}
        b0, b1 = self.syms['BUF0'], 0x4000
        self.base = (b0, b1)

    def call(self, name, a=0, x=0, y=0, maxcyc=20_000_000):
        if name == 'R_DISCROWS':                 # (no disc layer: its repair)
            name = 'R_REPAIR'
        if name == 'R_SETBUF':
            self.buf = a & 1
        mpu, mem = self.mpu, self.mem
        if self.guard:
            snap = mem[:]
        mpu.a, mpu.x, mpu.y = a & 255, x & 255, y & 255
        mpu.p = 0x24
        ret = tr.RET - 1
        mem[0x1FF] = ret >> 8
        mem[0x1FE] = ret & 0xFF
        mpu.sp = 0xFD
        mpu.pc = self.jt[name] if isinstance(name, str) else name
        c0 = mpu.processorCycles
        step = mpu.step
        while mpu.pc != tr.RET:
            step()
            if mpu.processorCycles - c0 > maxcyc:
                raise RuntimeError('runaway in %s' % name)
        self.cycles = mpu.processorCycles - c0
        if self.guard:
            self.check_writes(snap, name)
        return self.cycles

    def check_writes(self, snap, name):
        mem, s = self.mem, self.syms
        allowed = [(0x06, 0x28), (0x100, 0x200), (s['BUF0'], 0x7000), (s['MBOX'], s['MBOX'] + 0x100),
                   (0x8000, 0xC000)]
        a0 = 0
        for lo, hi in sorted(allowed) + [(0x10000, 0x10000)]:
            if a0 < lo and mem[a0:lo] != snap[a0:lo]:
                for a in range(a0, lo):
                    if mem[a] != snap[a]:
                        raise AssertionError('%s wrote &%04X' % (name, a))
            a0 = max(a0, hi)
        r0 = s['r_run0']
        for r in range(24):
            b = r0 + 256 * r
            for i in range(189):
                if mem[b + i] != snap[b + i]:
                    if not (i % 3 == 2 and (mem[b + i] - snap[b + i]) & 255 in (0x30, 0xD0)):
                        raise AssertionError('%s left run %d modified at +%d' % (name, r, i))

    def screen(self):
        b = self.base[self.buf]
        return bytes(self.mem[b:b + 0x3000])

    def set_screen(self, data):
        """both buffers (the model sets a frame's screen before its R_SETBUF:
        on the Master both buffers are at one address)"""
        for b in self.base:
            self.mem[b:b + 0x3000] = list(data)


def star_ref(ref, x, y, s, scol):
    """A star (R_STARPLOT): per row, per byte, its in-window pixels are set to
    scol only if the whole byte is black. (The docking slot's box is the frame
    layer's: f_slot takes those stars out of R_SS before the plot.)"""
    rows = [y] + ([y + 1] if s == 3 and y < 255 else [])
    xs = [x] + ([x + 1] if s >= 2 and x < 255 else [])
    for py in rows:
        if not (ref.ct <= py <= ref.cb):
            continue
        byts = {}
        for px in xs:
            if ref.cl <= px <= ref.cr:
                byts.setdefault(px >> 2, []).append(px)
        for c, pxs in byts.items():
            if all(ref.getpix(4 * c + p, py) == 0 for p in range(4)):
                for px in pxs:
                    ref.setpix(px, py, scol, scol)


# the Master port's test's overrides (R_POLY's colours, R_LINE's end points
# in words, its extra line tests)
def set_col(self, ce, co):
    self.m.wzp('R_COLE', ce)
    self.m.wzp('R_COLO', co)
    self.m.wr('R_COL2', ce)
    self.m.wr('R_COL3', co)


def draw_line(self, x0, y0, x1, y1, ce, co, entry='R_LINE'):
    m = self.m
    for nm, v in (('R_X0', x0), ('R_Y0', y0), ('R_X1', x1), ('R_Y1', y1)):
        m.wr(nm, v & 0xFF)
        m.wr(nm, (v >> 8) & 0xFF, 1)
    self.set_col(ce, co)
    return m.call(entry)


_demo_test_lines = tr.Tester.test_lines


def test_lines(self, n):
    """the demo's random lines, then as many again aimed at R_LINE's
    clipping (the Master port's): ends on and next to the window's sides,
    long lines across it, points, horizontal, vertical and diagonal lines"""
    _demo_test_lines(self, n)
    m, rnd = self.m, self.rnd

    def end(kind):
        cl, cr, ct, cb = self.clip
        if kind == 0:
            return (rnd.choice((cl - 1, cl, cl + 1, cr - 1, cr, cr + 1, rnd.randrange(256))),
                    rnd.choice((ct - 1, ct, ct + 1, cb - 1, cb, cb + 1, rnd.randrange(192))))
        if kind == 1:
            return rnd.randrange(-300, 556), rnd.randrange(-300, 492)
        if kind == 2:
            return rnd.randrange(cl, cr + 1), rnd.randrange(ct, cb + 1)
        return rnd.randrange(-3000, 3256), rnd.randrange(-3000, 3192)
    b = 0
    for it in range(n):
        if it % 50 == 0:
            if rnd.random() < 0.5:
                cl = rnd.randrange(1, 120)
                ct = rnd.randrange(0, 120)
                self.set_clip((cl, rnd.randrange(cl, 255), ct, rnd.randrange(ct, 192)))
            else:
                self.set_clip((1, 254, 1, 191))
            b = rnd.randrange(2)
            m.call('R_SETBUF', a=b)
            m.set_screen(bytes(rnd.randrange(256) for _ in range(0x3000)))
            ref, dirt = self.reset_state(b)
        x0, y0 = end(rnd.randrange(4))
        x1, y1 = end(rnd.randrange(4))
        s = rnd.random()
        if s < 0.1:
            x1, y1 = x0, y0
        elif s < 0.2:
            y1 = y0
        elif s < 0.3:
            x1 = x0
        elif s < 0.4:
            d = rnd.randrange(-600, 600)
            x1, y1 = x0 + d, y0 + rnd.choice((d, -d))
        ce, co = rnd.randrange(256), rnd.randrange(256)
        pts = (x0, y0, x1, y1)
        self.draw_line(*pts, ce, co)
        rows = []
        for x, y in tr.line_pixels(*pts):
            if ref.inwin(x, y):
                ref.setpix(x, y, ce, co)
                dl, dr = dirt[y]
                dirt[y] = (min(dl, x), max(dr, x))
                rows.append(y)
        if m.screen() != bytes(ref.b):
            raise AssertionError('line %s' % (pts,))
        if self.dirty(b) != dirt:
            raise AssertionError('line dirty %s' % (pts,))
        if rows and not (m.rd('R_PRDYT', b) <= min(rows) and max(rows) <= m.rd('R_PRDYB', b)):
            raise AssertionError('line row range %s' % (pts,))


tr.Machine = Machine
tr.check_patch_sites = check_patch_sites
tr.star_ref = star_ref
tr.Tester.set_col = set_col
tr.Tester.draw_line = draw_line
tr.Tester.test_lines = test_lines


def main():
    import argparse, random
    ap = argparse.ArgumentParser()
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--quick', action='store_true')
    ap.add_argument('--only', default='')
    a = ap.parse_args()
    scale = 0.2 if a.quick else 1.0
    nsites = check_patch_sites()
    m = Machine(None, a.seed)
    print(m.sizemsg, '; %d R_SETBUF patch sites' % nsites)
    rnd = random.Random(a.seed)
    m.call('R_INIT')
    t = tr.Tester(m, rnd)
    only = a.only.split(',') if a.only else None

    def run(name, fn, *args):
        if only and name not in only:
            return
        r = fn(*args)
        print('%-8s ok%s' % (name, '' if r is None else ' (%s)' % r))
        sys.stdout.flush()
    run('spans', t.test_spans, int(3000 * scale))
    run('polys', t.test_polys, int(3000 * scale))
    run('meshes', t.test_meshes, int(60 * scale))
    run('lines', t.test_lines, int(2000 * scale))
    for _ in range(4):
        run('frames', t.test_frames, int(40 * scale) + 4, 'none')
    print(tr.summarize(t.stats))
    print('TEST_RASTER PASS')


if __name__ == '__main__':
    main()
