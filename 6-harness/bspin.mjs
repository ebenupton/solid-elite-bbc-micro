// The planet's turn over the gate's run: at each MLOOP iteration in flight,
// the planet's vectors (slot 0 of K%, with FRIN+0 128 or more and not the
// sun, 129), MCNT and the player's own roll and pitch (ALP1, BET1). Prints
// the median turn from one iteration to the next with the player still (the
// planet's own pitch and roll: MVEIT part 8, by half the original's angle
// every iteration) by MCNT's parity, and its spread; then the lengths of the
// planet's three vectors over the run (unit length 96 x 256) and the largest
// departure of a pair from right angles. Runs the reference too (with its
// patches: mv8-half), for the same figures.
//
// node 6-harness/bspin.mjs [--build b] [--iters 10000]
import { resolve } from "path";
import { runElite, loadBuild, CAND_BUILD } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
const args = parseArgs({ build: "value", iters: "value" });
const b = loadBuild(resolve(args.build || CAND_BUILD));
const sy = b.progs.flight.sy;
const rows = [];
const vec = (m, a) => [0, 1, 2].map(j => { const lo = m[a + 2 * j], hi = m[a + 2 * j + 1]; const v = lo | (hi & 127) << 8; return hi & 128 ? -v : v; });
const r = await runElite({ build: b, pilot: makePilot(), iters: +(args.iters || 10000), maxSecs: 40000, patch: patchCommander, onIter: (i, s) => {
    const m = s._machine.processor.ramRomOs, K = sy["K%"], t = m[sy.FRIN];
    if (m[sy.QQ11] !== 0 || t < 128 || t === 129) return;
    rows.push({ i, n: vec(m, K + 9), r: vec(m, K + 15), s: vec(m, K + 21), mcnt: m[sy.MCNT], still: !(m[sy.ALP1] & 127) && !(m[sy.BET1] & 127) });
} });
const ang = (u, v) => { const d = u[0] * v[0] + u[1] * v[1] + u[2] * v[2]; return Math.acos(Math.max(-1, Math.min(1, d / (Math.hypot(...u) * Math.hypot(...v))))) * 180 / Math.PI; };
const med = x => { const y = [...x].sort((p, q) => p - q); return y.length ? `${y[y.length >> 1].toFixed(2)} deg (n ${y.length})` : "none"; };
const spread = x => { const y = [...x].sort((p, q) => p - q); return y.length ? `${y[0].toFixed(2)}..${y[y.length - 1].toFixed(2)}` : "none"; };
const it = { even: [], odd: [] };
for (let k = 1; k < rows.length; k++) {
    const p = rows[k - 1], q = rows[k];
    if (q.i !== p.i + 1 || !q.still || !p.still) continue;
    it[q.mcnt & 1 ? "odd" : "even"].push(Math.max(ang(q.r, p.r), ang(q.s, p.s), ang(q.n, p.n)));
}
console.log(`${b.file}: ${r.iters} iterations${r.error ? ", stopped: " + r.error : ""}`);
console.log(`the planet's turn an iteration, player still: MCNT even ${med(it.even)}, MCNT odd ${med(it.odd)}; all ${spread([...it.even, ...it.odd])} deg`);
const len = { n: [], r: [], s: [] };
let orth = 0;
for (const c of rows) {
    for (const k of ["n", "r", "s"]) len[k].push(Math.hypot(...c[k]) / 24576);
    orth = Math.max(orth, ...[[c.n, c.r], [c.n, c.s], [c.r, c.s]].map(([u, v]) => Math.abs(90 - ang(u, v))));
}
const lr = x => { let lo = Infinity, hi = -Infinity, t = 0; for (const v of x) { lo = Math.min(lo, v); hi = Math.max(hi, v); t += v; } return `${lo.toFixed(4)}..${hi.toFixed(4)} (mean ${(t / x.length).toFixed(4)})`; };
console.log(`vector lengths over ${rows.length} iterations: nosev ${lr(len.n)}, roofv ${lr(len.r)}, sidev ${lr(len.s)}; off right angles at most ${orth.toFixed(2)} deg`);
process.exit(0);
