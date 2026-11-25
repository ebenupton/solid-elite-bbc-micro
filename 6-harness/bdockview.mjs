// The last seconds of a docking run, posed (the Master port's mdockview.mjs,
// for the Model B and the Electron): the space station dead ahead with its
// slot towards us and level, the sun (parked, as in the safe zone) ahead
// beyond it, and the stardust, flown in at a steady speed until we dock.
//
// node 6-harness/bdockview.mjs [--build b] [--out dir] [--z z0] [--speed s]
//      [--sx x] [--sy y] [--every n] [--at k --out2 z] [--n iterations]
//
// Boots the build and launches under the gate's pilot (bpilot.mjs), as
// bbench.mjs does, then gives no more keys and puts the scene in at an MLOOP
// 20 iterations after the launch. At each MLOOP it notes the station's z, and
// every n iterations (and every one once the station is nearer than 400)
// keeps a screenshot of the screen on show, written at the end as
// <out>/dv-<iteration>-z<z>.png. With --at k --out2 z the station is put at z
// at iteration k (with --speed 0 and --z between 128 and the slot's face,
// 160, we sit inside the station until then, out of docking range).
import { resolve } from "path";
import { writeFileSync, mkdirSync, existsSync } from "fs";
import { deflateSync } from "zlib";
import { runElite, loadBuild, CAND_BUILD, WORK } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
const elib = existsSync(new URL("elib.mjs", import.meta.url)) ? await import("./elib.mjs") : null;
const a = parseArgs({ build: "value", out: "value", z: "value", speed: "value", sx: "value", sy: "value", every: "value", at: "value", out2: "value", n: "value" });
const b = loadBuild(resolve(a.build || CAND_BUILD));
const sy = b.progs.flight.sy;
const OUT = resolve(a.out || `${WORK}dockview`); mkdirSync(OUT, { recursive: true });
const NI = 37, SST = 2, unit = 0x6000;
const Z0 = +(a.z || 1400), SPEED = +(a.speed ?? 12), EVERY = +(a.every || 4), NMAX = +(a.n || 400);
function blockBytes({ x, y, z, nose = [0, 0, -1], roof = [0, 1, 0], side = [1, 0, 0], speed = 0, roll = 0, pitch = 0, heap = 0 }) {
    const q = new Array(NI).fill(0);
    const c = (o, v) => { const m = Math.abs(Math.round(v)); q[o] = m & 255; q[o + 1] = (m >> 8) & 255; q[o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
    c(0, x); c(3, y); c(6, z);
    const v = (o, w) => w.forEach((t, j) => { const m = Math.min(32767, Math.round(Math.abs(t) * unit)); q[o + 2 * j] = m & 255; q[o + 2 * j + 1] = (m >> 8) | (t < 0 ? 128 : 0); });
    v(9, nose); v(15, roof); v(21, side);
    q[27] = speed; q[29] = roll; q[30] = pitch; q[33] = heap & 255; q[34] = heap >> 8; q[35] = 100;
    return q;
}
const R = r => 24576 * 256 / r;
const pilot = makePilot();
let flying = false, cpu = null, launchedAt = -1, slspTop = 0, k = -1, docked = false;
const log = [], frames = [];
const opts = { build: b, pilot: { keys: c => flying ? [] : pilot.keys(c), dks: c => flying ? false : pilot.dks(c), observe: pilot.observe, P: pilot.P },
    iters: 100000, maxSecs: 100000, patch: patchCommander };
function pose(ram) {
    const K = sy["K%"];
    const put = (slot, type, q) => { for (let i = 0; i < NI; i++) ram[K + NI * slot + i] = q[i]; ram[sy.FRIN + slot] = type; };
    for (let i = 0; i <= 12; i++) ram[sy.FRIN + i] = 0;
    for (let i = 0; i < 32; i++) ram[sy.MANY + i] = 0;
    ram[sy.JUNK] = 0;
    put(0, 128, blockBytes({ x: 0, y: -20000, z: -80000 }));
    put(1, SST, blockBytes({ x: 0, y: 0, z: Z0, roof: [1, 0, 0], side: [0, -1, 0], heap: sy.LSO }));   // the slot level (ISDK: |roofv_x| large)
    ram[sy.SSPR] = 1;
    const p = blockBytes({ x: R(24) * +(a.sx || 0.05), y: R(24) * +(a.sy || 0.03), z: R(24) });
    for (let i = 0; i < NI; i++) ram[sy.SUNPK + i] = p[i];
    ram[sy.SUNPF] = 0x80;
    ram[sy.SLSP] = slspTop & 255; ram[sy.SLSP + 1] = slspTop >> 8;
    ram[sy.VIEW] = 0; ram[sy.DELTA] = SPEED; ram[sy.JSTX] = 128; ram[sy.JSTY] = 128;
    ram[sy.ENERGY] = 255; ram[sy.FSH] = 255; ram[sy.ASH] = 255; ram[sy.MCNT] = 1;
}
const z1 = ram => { const q = sy["K%"] + NI; return (ram[q + 6] | ram[q + 7] << 8 | (ram[q + 8] & 127) << 16) * (ram[q + 8] & 128 ? -1 : 1); };
const isElk = elib && elib.isElectron(b);
opts.onBoot = s => { cpu = s._machine.processor; };
opts.onIter = (i, s) => {
    const ram = cpu.ramRomOs;
    if (!flying) {
        if (ram[sy.QQ12] === 0 && pilot.P.phase !== "title" && pilot.P.phase !== "start" && (ram[sy.FRIN] & 0x80)) {
            if (launchedAt < 0) { launchedAt = i; slspTop = ram[sy.SLSP] | ram[sy.SLSP + 1] << 8; }
            if (i - launchedAt >= 20) { flying = true; pose(ram); k = 0; }
        }
        return;
    }
    if (ram[sy.QQ11] !== 0) { docked = true; opts.iters = i + 1; return; }
    k++;
    if (a.at && k === +a.at) { const q = sy["K%"] + NI, v = +a.out2; ram[q + 6] = v & 255; ram[q + 7] = v >> 8; }
    const z = z1(ram); log.push([k, z]);
    if (k % EVERY === 0 || z < 400) frames.push([k, z, isElk ? s.shot() : Buffer.from(s._completeFb8), s]);
    if (k >= NMAX) opts.iters = i + 1;
};
const r = await (isElk ? elib.runElite : runElite)(opts);
// (jsbeeb's frame: 1024 columns by 625 rows, every other column and row of
// the active area kept, as bshot.mjs does; clkh's shots are PNGs already)
const crcTab = Array.from({ length: 256 }, (_, n) => { let c = n; for (let j = 0; j < 8; j++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = buf => { let c = 0xffffffff; for (const x of buf) c = crcTab[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const t = Buffer.from(type), l = Buffer.alloc(4), c = Buffer.alloc(4); l.writeUInt32BE(data.length); c.writeUInt32BE(crc(Buffer.concat([t, data]))); return Buffer.concat([l, t, data, c]); };
const png = (wd, ht, rgb) => { const hd = Buffer.alloc(13); hd.writeUInt32BE(wd, 0); hd.writeUInt32BE(ht, 4); hd[8] = 8; hd[9] = 2;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", hd), chunk("IDAT", deflateSync(rgb)), chunk("IEND", Buffer.alloc(0))]); };
for (const [n, z, fb, s] of frames) {
    const f = `${OUT}/dv-${String(n).padStart(3, "0")}-z${z}.png`;
    if (isElk) { writeFileSync(f, fb); continue; }
    const v = s._video, W = 1024, H = 625, left = v.leftBorder, top = v.topBorder, w = W - left - v.rightBorder, h = H - top - v.bottomBorder;
    const cols = w >> 1, rows = h >> 1, rgb = Buffer.alloc((cols * 3 + 1) * rows);
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
        const o = ((top + 2 * y) * W + left + 2 * x) * 4, d = y * (cols * 3 + 1) + 1 + x * 3;
        rgb[d] = fb[o]; rgb[d + 1] = fb[o + 1]; rgb[d + 2] = fb[o + 2];
    }
    writeFileSync(f, png(cols, rows, rgb));
}
for (const [n, z] of log) console.log(`it ${n} z ${z}`);
console.log(docked ? "DOCKED" : "not docked", r.error ? `(stopped: ${r.error})` : "");
process.exit(0);
