// bbench.mjs: a speed benchmark that does not move when the game's random
// numbers do: frozen scenes (the BBC Master port's mbench.mjs, for the Model
// B). The gate's speed is its piloted run's, which is the game's own, and a
// change to the random numbers the reference or the port takes makes the
// pilot fly another run: its figure no longer compares with one taken before.
//
// Boots the build and launches under the gate's pilot (bpilot.mjs, its
// commander: the launch is at Lave), then gives no more keys, and for each
// scene puts the scene's state in at an MLOOP (the ship slots, the planet,
// slot 1's sun or station, the parked sun, the view, our speed, roll and
// pitch), lets it run WARM iterations and snapshots the game state (blib's
// regions). Then it runs N iterations in windows of M = 32: the snapshot is
// put back at the start of each window, so the scene starts the same in any
// build and moves for M iterations (the renderer does real work, and its
// memos hit as in play); within a window, at every MLOOP, RAND is put back
// and every slot after the scene's ships emptied (with MANY, JUNK and SLSP
// as in the snapshot), so that no ship spawns and no random number taken
// before (the original's sun's edge, explosion clouds ...) changes what
// follows. The figure is the emulated time from one MLOOP to the next,
// averaged over the N iterations, as cycles and iterations a second.
//
// The scenes (the front view unless said; positions in the game's units):
//   flight     cruising: the planet far off (radius about 20), three ships
//              ahead at 3000-6000, rolling a little
//   combat     five ships close round us (800-2000), turning, our rolling and
//              pitching; the planet small
//   beachball  the approach: the planet's beach ball filling the view
//              (radius about 110), one ship
//   sun        a visible sun (radius 32) beside the planet (radius 60)
//   docking    the station ahead at 1500, the planet behind it, the sun
//              parked
//   zone       the safe zone: the station near and ahead, the sun parked
//              behind us, two ships
//   rear       the beach ball in the rear view, with ships
//   approach   the gate's run's long approach to a planet (nearly half its
//              iterations): a crater planet (TYPE 130, radius 62) turning as
//              the game turns it, across the left edge of the view, swung
//              round the view's centre by our roll, which is held (about 5
//              pixels an iteration: from the bottom left to the top left in
//              a window); the sun far behind, full speed, no ships
//   departure  the gate's run after a launch (a fifth of its cycles): the
//              beach ball dead ahead (radius 105), still but turning as the
//              game turns it (about the axis and at a phase of the run's),
//              the station behind us, the sun parked
// The first seven scenes' planet turns once and stops (its roll and pitch
// counters 1), and our roll and pitch die away under the keyboard's damping
// (the scene's alpha and beta are JSTX and JSTY, which recentre within a
// few iterations); a scene's planet with roll and pitch 127 turns on every
// iteration, as the game's (SOLAR's), and a scene with hold has the damping
// off (DAMP) so that its roll and pitch stay. The approach scene's snapshot
// puts the disc back where the window started: each window's first two
// iterations paint it whole, in each buffer.
// The ships are of the types the launch system's blueprint file has (each
// scene's wanted types, in order, else the next fighter the file has), with
// the line heaps their blueprints ask for.
//
// node 6-harness/bbench.mjs [--build build.json] [--scene a,b] [--n 128]
//      [--warm 8] [--out file.json] [--dump DIR]
// --dump DIR writes main RAM &1000-&76FF (both screen buffers and the
// dashboard) at three iterations of each scene's first window, as
// DIR/<scene>-<n>.bin: two builds that draw the same have the same files.
// Prints "scene: cycles/iteration it/s" per scene.
import { runElite, loadBuild, regionsFor, physRead, progHooks, CAND_BUILD } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { resolve } from "path";

const a = parseArgs({ build: "value", scene: "value", n: "value", warm: "value", out: "value", dump: "value" });
const BUILD = resolve(a.build || CAND_BUILD);
const b = loadBuild(BUILD);
const sy = b.progs.flight.sy;
const XX21 = sy.XX21 ?? b.progs.docked.sy.XX21;
const N = +(a.n || 128), WARM = +(a.warm || 8), M = 32, NI = 37;
// (ship types: elite-source-flight.asm's constants and the XX21 table)
const SST = 2, CYL = 11, PYTHON = 12, VIPER = 16, SIDE = 17, MAM = 18, KRA = 19, ADA = 20, GECKO = 21, COB1 = 22, CYL2 = 24, ASP = 25, FER = 27;
const FIGHTERS = [CYL, MAM, KRA, SIDE, VIPER, PYTHON, ADA, GECKO, COB1, CYL2, ASP, FER];

// a block: position, orientation (nosev, roofv, sidev as unit vectors), and the rest
const unit = 0x6000;
function blockBytes({ x, y, z, nose = [0, 0, -1], roof = [0, 1, 0], side = [1, 0, 0], speed = 0, roll = 0, pitch = 0, ai = 0, newb = 0, energy = 100, heap = 0 }) {
    const q = new Array(NI).fill(0);
    const c = (o, v) => { const m = Math.abs(Math.round(v)); q[o] = m & 255; q[o + 1] = (m >> 8) & 255; q[o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
    c(0, x); c(3, y); c(6, z);
    const v = (o, w) => w.forEach((t, j) => { const m = Math.min(32767, Math.round(Math.abs(t) * unit)); q[o + 2 * j] = m & 255; q[o + 2 * j + 1] = (m >> 8) | (t < 0 ? 128 : 0); });
    v(9, nose); v(15, roof); v(21, side);
    q[27] = speed; q[29] = roll; q[30] = pitch; q[32] = ai; q[33] = heap & 255; q[34] = heap >> 8; q[35] = energy; q[36] = newb;
    return q;
}
const R = r => 24576 * 256 / r;                    // the z for a disc of radius r (PLANET: 24576 / z)
const SCENES = {
    flight: { planet: { x: -R(20) * 0.3, y: R(20) * 0.2, z: R(20) }, slot1: { type: 129, x: R(8), y: R(8) * 0.4, z: -R(8) },
        ships: [[CYL, { x: 900, y: 300, z: 3000, speed: 10, roll: 2 }], [ADA, { x: -1200, y: -400, z: 4500, speed: 12 }], [VIPER, { x: 300, y: 900, z: 6000, speed: 14 }]], view: 0, delta: 15, alpha: 2, beta: 0 },
    combat: { planet: { x: R(15), y: R(15) * 0.5, z: R(15) }, slot1: { type: 129, x: -R(6), y: 0, z: -R(6) },
        ships: [[CYL, { x: 300, y: 200, z: 900, speed: 20, roll: 3, pitch: 2 }], [MAM, { x: -500, y: 100, z: 1200, speed: 25, roll: 130 }], [KRA, { x: 200, y: -600, z: 1500, speed: 22, pitch: 3 }],
            [SIDE, { x: -900, y: -200, z: 800, speed: 30, roll: 4 }], [ASP, { x: 700, y: 500, z: 2000, speed: 18, pitch: 130 }]], view: 0, delta: 20, alpha: 3, beta: 2 },
    beachball: { planet: { x: 0, y: -R(110) * 0.3, z: R(110) }, slot1: { type: 129, x: R(10), y: R(10), z: -R(10) },
        ships: [[PYTHON, { x: 800, y: 600, z: 2500, speed: 10 }]], view: 0, delta: 12, alpha: 1, beta: 0 },
    sun: { planet: { x: -R(60) * 0.4, y: -R(60) * 0.3, z: R(60) }, slot1: { type: 129, x: R(32) * 0.25, y: R(32) * 0.15, z: R(32) },
        ships: [], view: 0, delta: 1, alpha: 0, beta: 0 },
    docking: { planet: { x: 0, y: 0, z: 80000 }, slot1: { type: SST, x: 0, y: 0, z: 1500, roll: 255 }, park: { x: R(8), y: R(8), z: -R(8) },
        ships: [], view: 0, delta: 10, alpha: 0, beta: 0 },
    zone: { planet: { x: 0, y: -30000, z: 60000 }, slot1: { type: SST, x: 400, y: -500, z: 4000, roll: 255 }, park: { x: -R(7), y: R(7) * 0.2, z: -R(7) },
        ships: [[VIPER, { x: 500, y: 300, z: 2000, speed: 15, roll: 2 }], [CYL, { x: -800, y: 200, z: 3500, speed: 12 }]], view: 0, delta: 15, alpha: 2, beta: 1 },
    rear: { planet: { x: 0, y: R(100) * 0.3, z: -R(100) }, slot1: { type: 129, x: R(10), y: 0, z: R(10) },
        ships: [[CYL, { x: 500, y: 300, z: -2500, speed: 10, roll: 2 }], [ADA, { x: -700, y: -300, z: -3500, speed: 12 }]], view: 1, delta: 10, alpha: 2, beta: 0 },
    approach: { planet: { type: 130, x: -R(62) * 0.265, y: -R(62) * 0.353, z: R(62), roll: 127, pitch: 127 }, slot1: { type: 129, x: 400000, y: 300000, z: -700000 },
        ships: [], view: 0, delta: 38, alpha: 6, beta: 0, hold: true },
    departure: { planet: { x: 0, y: 0, z: R(105), roll: 127, pitch: 127, nose: [0.708, 0.643, -0.292], roof: [-0.643, 0.416, -0.643], side: [-0.292, 0.643, 0.708] },
        slot1: { type: SST, x: 0, y: -1, z: -5000, roll: 255 }, park: { x: -65280, y: 0, z: -530000 }, ships: [], view: 0, delta: 18, alpha: 0, beta: 0 },
};
const which = (a.scene || Object.keys(SCENES).join(",")).split(",");

const pilot = makePilot();
let benching = false, cpu = null, ph = null;
const keys = c => benching ? [] : pilot.keys(c);
const dks = c => benching ? false : pilot.dks(c);
const regions = regionsFor(b);
const opts = { build: b, pilot: { keys, dks, observe: pilot.observe, P: pilot.P }, iters: 100000, maxSecs: 100000, patch: patchCommander };

// the launch system's blueprints: present types and their line heap sizes
function blueprint(t) {
    const rd = x => XX21 < 0x8000 ? cpu.ramRomOs[x] : physRead(cpu, ph.bankOf("H"), x);
    const p = rd(XX21 + 2 * (t - 1)) | rd(XX21 + 2 * (t - 1) + 1) << 8;
    return p ? { heap: rd(p + 5) } : null;
}
function pose(sc) {
    const ram = cpu.ramRomOs, K = sy["K%"];
    const put = (slot, type, q) => { for (let i = 0; i < NI; i++) ram[K + NI * slot + i] = q[i]; ram[sy.FRIN + slot] = type; };
    for (let i = 0; i <= 12; i++) ram[sy.FRIN + i] = 0;
    for (let i = 0; i < 32; i++) ram[sy.MANY + i] = 0;
    ram[sy.JUNK] = 0; ram[sy.SSPR] = 0;
    put(0, sc.planet.type || 128, blockBytes({ roll: 1, pitch: 1, ...sc.planet }));
    put(1, sc.slot1.type, blockBytes({ ...sc.slot1, heap: sy.LSO }));
    if (sc.slot1.type === SST) ram[sy.SSPR] = 1;
    if (sy.SUNPK !== undefined) {
        const q = sc.park ? blockBytes(sc.park) : new Array(NI).fill(0);
        for (let i = 0; i < NI; i++) ram[sy.SUNPK + i] = q[i];
        ram[sy.SUNPF] = sc.park ? 0x80 : 0;
    }
    let heap = slspTop, n = 2;
    const used = [];
    for (const [want, d] of sc.ships) {
        const t = [want, ...FIGHTERS].find(x => blueprint(x) && !(used.includes(x) && x !== want));
        used.push(t);
        heap -= blueprint(t).heap;
        put(n++, t, blockBytes({ ...d, heap }));
        ram[sy.MANY + t]++;
    }
    ram[sy.SLSP] = heap & 255; ram[sy.SLSP + 1] = heap >> 8;
    ram[sy.VIEW] = sc.view; ram[sy.DELTA] = sc.delta;
    ram[sy.JSTX] = 128 + 8 * sc.alpha; ram[sy.JSTY] = 128 + 8 * sc.beta;
    if (damp === null) damp = ram[sy.DAMP];
    ram[sy.DAMP] = sc.hold ? 0xff : damp;
    ram[sy.ENERGY] = 255; ram[sy.FSH] = 255; ram[sy.ASH] = 255; ram[sy.MCNT] = 1;
    return used;
}

const results = {};
let si = 0, k = -1, snap = null, times = [], posed = false, rand, many, slsp, junk, slspTop = 0, launchedAt = -1, used = null, damp = null;
opts.onBoot = s => { cpu = s._machine.processor; ph = progHooks(b, cpu); };
opts.onIter = (i, s, res) => {
    const ram = cpu.ramRomOs;
    if (!benching) {
        // (after the launch: in flight, and 20 iterations on)
        if (ram[sy.QQ12] === 0 && pilot.P.phase !== "title" && pilot.P.phase !== "start" && (ram[sy.FRIN] & 0x80)) {
            if (launchedAt < 0) { launchedAt = i; slspTop = ram[sy.SLSP] | ram[sy.SLSP + 1] << 8; }
            if (i - launchedAt >= 20) benching = true;
        }
        if (!benching) return;
    }
    const sc = SCENES[which[si]];
    k++;
    if (!posed) { used = pose(sc); posed = true; k = 0; return; }
    if (k === WARM) {
        snap = regions.map(([q, n]) => Array.from(ram.subarray(q, q + n)));
        rand = Array.from(ram.subarray(sy.RAND, sy.RAND + 4)); many = Array.from(ram.subarray(sy.MANY, sy.MANY + 32));
        slsp = [ram[sy.SLSP], ram[sy.SLSP + 1]]; junk = ram[sy.JUNK];
    }
    if (snap) {
        times.push(res.iterTimes[res.iterTimes.length - 1]);
        // --dump DIR: both buffers and the dashboard (&1000-&76FF) as they are
        // at three iterations of the scene's first window, to compare two
        // builds' pictures byte for byte
        if (a.dump && [M / 2, M - 2, M - 1].includes(times.length)) { mkdirSync(a.dump, { recursive: true }); writeFileSync(`${a.dump}/${which[si]}-${times.length}.bin`, ram.subarray(0x1000, 0x7700)); }
        if (times.length > N) {
            const per = (times[times.length - 1] - times[0]) / (times.length - 1) * 2e6;
            results[which[si]] = { cycles: Math.round(per), its: +(2e6 / per).toFixed(3), n: times.length - 1, ships: used };
            console.log(`${which[si].padEnd(10)} ${String(Math.round(per)).padStart(7)} cycles/iteration  ${(2e6 / per).toFixed(2).padStart(6)} it/s   (ships ${used.join(",") || "none"})`);
            si++; k = -1; snap = null; times = []; posed = false;
            if (si === which.length) { opts.iters = i + 1; return; }
            return;
        }
        if ((times.length - 1) % M === 0) regions.forEach(([q], j) => snap[j].forEach((v, x) => { ram[q + x] = v; }));
        else {
            rand.forEach((v, x) => { ram[sy.RAND + x] = v; }); many.forEach((v, x) => { ram[sy.MANY + x] = v; });
            ram[sy.SLSP] = slsp[0]; ram[sy.SLSP + 1] = slsp[1]; ram[sy.JUNK] = junk;
            for (let x = 2 + sc.ships.length; x <= 12; x++) ram[sy.FRIN + x] = 0;
        }
    }
};
const r = await runElite(opts);
if (r.error) console.log(`error: ${r.error}`);
if (a.out) writeFileSync(a.out, JSON.stringify({ build: BUILD, N, WARM, results }, null, 1));
process.exit(Object.keys(results).length === which.length ? 0 : 1);
