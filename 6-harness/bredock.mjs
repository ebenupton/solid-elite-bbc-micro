// Regression test: dock, launch, dock again (the docking computer), from a
// fresh boot, with real key presses. node 6-harness/bredock.mjs [--build b]
// [--out dir]. Exit status 0 if both dockings happen (the docked program's
// DOENTRY reached twice) within 120 emulated seconds each; screenshots of
// each stage.
import { BBC } from "./jsbeeb.mjs";
import { loadBuild, bootModelB, progHooks, CAND_BUILD, WORK } from "./blib.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ build: "value", out: "value" });
const b = loadBuild(a.build || CAND_BUILD);
const sy = b.progs.flight.sy;
const OUT = a.out || `${WORK}redock`; mkdirSync(OUT, { recursive: true });
const s = await bootModelB(b.disc);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
const snap = async n => writeFileSync(`${OUT}/${n}.png`, await s.screenshotActive({ scale: 1 }));
const { hookOf, live } = progHooks(b, cpu);
const DOE = hookOf("docked", "DOENTRY");
let docks = 0;
cpu.debugInstruction.add(pc => { if (pc === DOE.a && live(DOE)) docks++; return false; });
await secs(40); await key("N"); await secs(3); await key("SPACE"); await secs(4);
await snap("0-docked");
cpu.ramRomOs[sy.DKCMP] = 0xff;
let ok = true;
for (let n = 1; n <= 2; n++) {
    await key("F0", 0.2, 15); await snap(`${n}-launched`);
    await key("C", 0.2, 1);
    let t = 0; while (docks < n && t < 120) { await secs(1); t++; if (t === 10) await snap(`${n}-docking`); }
    console.log(`docking ${n}: ${docks >= n ? `docked after ${t} s` : "NOT DOCKED after 120 s"}`);
    if (docks < n) { ok = false; await snap(`${n}-failed`); break; }
    await secs(10); await key("SPACE", 0.2, 3); await snap(`${n}-docked`);
}
console.log(ok ? "REDOCK PASS" : "REDOCK FAIL");
process.exit(ok ? 0 : 1);
