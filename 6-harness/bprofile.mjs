// Cycle profile of disc Elite per (mapping, PC), over exactly the run the gate
// (6-harness/verify.sh) times: blib.mjs runElite with bpilot.mjs's pilot and
// its commander patch, --iters MLOOP iterations (the gate's 10000).
//
// node 6-harness/bprofile.mjs [--build b] [--iters 10000] [--out work/profile.json]
//
// Attribution: the cycles between two consecutive instruction hooks go to the
// earlier PC (its own cycles, plus an interrupt entry that followed it),
// keyed by what was mapped there: "m:<pc>" (main RAM, &0000-&7FFF), "b<n>:<pc>"
// (sideways RAM bank n), "rom:<pc>" (the MOS, DFS, BASIC).
//
// Scenarios, as the gate's speed figure (bcompare.mjs) counts them:
//   "flight"    the flight iterations: TT100 to the next TT100 when exactly one
//               MLOOP iteration lies between them
//   "phase:<p>" the same split by the pilot's phase
//   "other"     every other cycle from the first MLOOP on (docked screens,
//               title, launch, death)
// For each scenario and PC: the cycles, and the number of iterations in
// which the PC ran ("iters"), from which 6-harness/hotset.py tells the hot
// code (run in most flight iterations) from the cold.
import { writeFileSync, mkdirSync } from "fs";
import { dirname, resolve } from "path";
import { runElite, loadBuild, CAND_BUILD, WORK } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
const args = parseArgs({ build: "value", iters: "value", out: "value" });
const B = loadBuild(resolve(args.build || CAND_BUILD));
const OUT = resolve(args.out || `${WORK}profile.json`);
const ITERS = +(args.iters || 10000);
const t0 = Date.now();

const NM = 18, SZ = NM * 65536;      // 0: main RAM, 1-16: banks 0-15, 17: ROM
const key = k => (k >> 16) === 0 ? `m:${(k & 0xffff).toString(16)}` : (k >> 16) === 17 ? `rom:${(k & 0xffff).toString(16)}` : `b${(k >> 16) - 1}:${(k & 0xffff).toString(16)}`;
const mk = () => ({ iterations: 0, total_cycles: 0, c: new Float64Array(SZ), n: new Uint32Array(SZ) });
const scen = { flight: mk(), other: mk() };
const cur = new Float64Array(SZ), stamp = new Uint32Array(SZ);
let touched = [], gen = 1, curTotal = 0;
const pilot = makePilot();
let cpu = null, installed = false, last = 0, lastIdx = -1, swram = null;
let myIter = 0, prevTT = -1, ttHook = null, live = null;
const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
const idxOf = pc => {
    if (pc < 0x8000) return pc;
    if (pc < 0xc000) { const b = cpu.romsel & 15; return swram[b] ? (1 + b) * 65536 + pc : 17 * 65536 + pc; }
    return 17 * 65536 + pc;
};
const closeInto = dests => {
    for (const sc of dests) { sc.iterations++; sc.total_cycles += curTotal; }
    for (const k of touched) { const v = cur[k]; for (const sc of dests) { sc.c[k] += v; sc.n[k]++; } cur[k] = 0; }
    touched = []; gen++; curTotal = 0;
};
const { progHooks } = await import("./blib.mjs");
const r = await runElite({
    build: B, pilot, iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander,
    onIter: (i, s) => {
        myIter = i + 1;          // (blib counts the MLOOP after this call)
        if (installed) return;
        installed = true;
        cpu = s._machine.processor;
        swram = cpu.model.swram;
        const h = progHooks(B, cpu);
        ttHook = h.hookOf("flight", "TT100"); live = h.live;
        last = cyc();
        cpu.debugInstruction.add(pc => {
            const now = cyc();
            if (lastIdx >= 0) {
                const d = now - last;
                if (stamp[lastIdx] !== gen) { stamp[lastIdx] = gen; touched.push(lastIdx); }
                cur[lastIdx] += d; curTotal += d;
            }
            last = now;
            if (pc === ttHook.a && live(ttHook)) {
                // a flight TT100: close the interval since the previous one
                if (prevTT >= 0 && myIter === prevTT + 1) closeInto([scen.flight, (scen["phase:" + pilot.P.phase] ||= mk())]);
                else closeInto([scen.other]);
                prevTT = myIter;
            }
            lastIdx = idxOf(pc);
            return false;
        });
    },
});
closeInto([scen.other]);
const out = { build: B.file, iters: r.iters, tt100: r.tt100, error: r.error || null, emulated_secs: r.emuSecs,
    wall_secs: (Date.now() - t0) / 1000, pilot: { ...pilot.P.stats, systems: [...pilot.P.stats.systems] }, scenarios: {} };
for (const [n, sc] of Object.entries(scen)) {
    const pcs = {}, iters = {};
    for (let k = 0; k < SZ; k++) if (sc.c[k]) { pcs[key(k)] = Math.round(sc.c[k]); iters[key(k)] = sc.n[k]; }
    out.scenarios[n] = { iterations: sc.iterations, total_cycles: sc.total_cycles,
        cycles_per_iteration: sc.iterations ? sc.total_cycles / sc.iterations : null, pcs, iters };
    console.log(`${n}: ${sc.iterations} iterations, ${sc.total_cycles.toFixed(0)} cycles` +
        (sc.iterations ? `, ${(sc.total_cycles / sc.iterations).toFixed(0)} cycles/iteration` +
            (n === "other" ? "" : `, ${(2e6 * sc.iterations / sc.total_cycles).toFixed(2)} it/s`) : ""));
}
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out));
console.log(`-> ${OUT} (${r.iters} MLOOP iterations, ${r.tt100} TT100, emulated ${out.emulated_secs.toFixed(1)} s, wall ${out.wall_secs.toFixed(1)} s${r.error ? ", STOPPED: " + r.error : ""})`);
process.exit(r.error || r.iters !== ITERS ? 1 : 0);
