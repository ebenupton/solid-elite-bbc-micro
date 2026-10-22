// Per-iteration times and scenes of a build over the gate's run, for the
// speed by scene (6-harness/scenes.py, docs/renderer.md, "Speed").
//
// node 6-harness/bscenes.mjs [--build b] [--iters 10000] --out FILE.json
//
// At each MLOOP iteration: the emulated time, the flight iteration count
// (TT100s), QQ11, VIEW, the type in slot 1 (FRIN+1: the station or the sun),
// the high parts of the planet's (slot 0) and slot 1's coordinates (bytes 1
// and 2, 4 and 5, 7 and 8 of the ship data block: x, y, z as hi + 256 * the
// sign byte's low 7 bits, and z's sign), the number of other ships and the
// system (QQ0, QQ1).
import { writeFileSync } from "fs";
import { resolve } from "path";
import { runElite, loadBuild, CAND_BUILD } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
const args = parseArgs({ build: "value", iters: "value", out: "value" });
const b = loadBuild(resolve(args.build || CAND_BUILD));
const sy = b.progs.flight.sy;
const rows = [];
const r = await runElite({ build: b, pilot: makePilot(), iters: +(args.iters || 10000), maxSecs: 40000, patch: patchCommander, onIter: (i, s, res) => {
    const m = s._machine.processor.ramRomOs, K = sy["K%"];
    const blk = n => { const a = K + 37 * n; return { x: m[a + 1] | ((m[a + 2] & 127) << 8), y: m[a + 4] | ((m[a + 5] & 127) << 8), z: m[a + 7] | ((m[a + 8] & 127) << 8), zs: m[a + 8] >> 7 }; };
    let ships = 0; for (let k = 2; k < 12; k++) if (m[sy.FRIN + k]) ships++;
    rows.push({ i, t: res.iterTimes[res.iterTimes.length - 1], tt: res.tt100AtIter[res.tt100AtIter.length - 1], qq11: m[sy.QQ11], view: m[sy.VIEW], f1: m[sy.FRIN + 1], p: blk(0), s1: blk(1), ships, sys: [m[sy.QQ0], m[sy.QQ1]] });
} });
writeFileSync(args.out, JSON.stringify(rows));
console.log(`${r.iters} iterations${r.error ? ", stopped: " + r.error : ""} -> ${args.out}`);
process.exit(0);
