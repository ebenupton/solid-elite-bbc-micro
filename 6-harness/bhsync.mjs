// The video timing proof: every horizontal sync of a gate-length run, timed.
//
// node 6-harness/bhsync.mjs [--build b] [--iters 10000] [--screens] [--views]
//                           [--maxsecs S] [--log FILE] [--ula]
//
// Runs the gate's pilot (bpilot.mjs) on a build, as verify.sh does, and
// timestamps every rising edge of the 6845's horizontal sync and every
// vertical sync start, in 2 MHz cycles, from the loader's handover to the
// rupture (its first switch, S2, a write of the game screen's control value
// to the video ULA) on, through the title, the docked screens and the game. jsbeeb clocks the 6845 once per 2 MHz cycle and skips every other
// clock while the video ULA's control register selects the 1 MHz character
// clock (bit 4 clear), so a change of clock in mid-line is modelled at 2 MHz
// cycle resolution (its video.js, Video.polltime). The tool rebuilds that
// method from jsbeeb's own source with three hooks (a clock count, and a call
// at each rising edge of the two syncs), so jsbeeb itself is not changed.
//
// It fails (exit status 1) on any horizontal sync interval other than 128
// cycles (64 microseconds), on any field whose line count (horizontal syncs
// from one vertical sync to the next) differs from the first's, and on a run
// that stops early. With --screens or --views the pilot also shows the
// flight screens or changes view (bcompare.mjs's regressions), so that the
// overlays' disc loads are in the run as well as the gate's launches,
// dockings, hyperspace jumps and the docked screens. --ula also lists the
// writes to the video ULA's control register by the line cycle they land on.
import { writeFileSync, readFileSync } from "fs";
import { resolve, dirname } from "path";
import { runElite, loadBuild, CAND_BUILD } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";

const JS = process.env.JSBEEB || decodeURIComponent(new URL("node_modules/jsbeeb", import.meta.url).pathname);
const V = await import(`${JS}/src/video.js`);

const args = parseArgs({ build: "value", iters: "value", screens: "flag", views: "flag", maxsecs: "value", log: "value", ula: "flag", inject: "value", t2skew: "value" });
const B = loadBuild(resolve(args.build || CAND_BUILD));
const ITERS = +(args.iters || 10000);

let gcpu = null, judging = false, iterNow = 0, lastH = -1, nH = 0, linesThisField = 0, fields = 0, fieldLines = null;
const intervals = new Map(), fieldCounts = new Map(), ulaWrites = new Map(), badH = [], badV = [], ulaSeq = [];

function onH(t) {
    if (!judging) { lastH = t; linesThisField++; return; }
    if (lastH >= 0) {
        const d = t - lastH;
        intervals.set(d, (intervals.get(d) || 0) + 1);
        if (d !== 128 && badH.length < 50) badH.push({ iter: iterNow, at: t, interval: d });
        for (const u of ulaSeq) if (u.iv.length < 3 && t > u.at) u.iv.push(d);
    }
    lastH = t;
    nH++;
    linesThisField++;
}

function onV() {
    if (!judging) { linesThisField = 0; return; }
    if (fields > 0) {
        fieldCounts.set(linesThisField, (fieldCounts.get(linesThisField) || 0) + 1);
        if (fieldLines === null) fieldLines = linesThisField;
        else if (linesThisField !== fieldLines && badV.length < 50) {
            badV.push({ iter: iterNow, lines: linesThisField });
            if (badV.length === 3 && gcpu) {
                const c = gcpu, m = c.ramRomOs;
                console.log(`  (at the third bad field: pc ${c.pc.toString(16)}, p ${c.p.asByte().toString(16)}, rphase ${m[LSY.rphase]} rstate ${m[LSY.rstate]} rdisc ${m[LSY.rdisc]}, sys VIA ier ${c.sysvia.ier.toString(16)} ifr ${c.sysvia.ifr.toString(16)} t1c ${c.sysvia.t1c} t1l ${c.sysvia.t1l}, acr ${c.sysvia.acr.toString(16)})`);
            }
        }
    }
    fields++;
    linesThisField = 0;
}

function install(s) {
    const cpu = s._machine.processor, video = cpu.video;
    gcpu = cpu;
    let src = V.Video.prototype.polltime.toString();
    const hook = (from, to) => {
        if (!src.includes(from)) throw new Error("jsbeeb's Video.polltime has changed: " + from);
        src = src.replace(from, to);
    };
    hook("this.oddClock = !this.oddClock;", "this.oddClock = !this.oddClock; this._clk++;");
    hook("this.inHSync = true;", "this.inHSync = true; this._onH(this._clk);");
    hook("this.inVSync = true;", "this.inVSync = true; this._onV();");
    const names = Object.keys(V).filter(k => /^[A-Z_0-9]+$/.test(k));
    const patched = new Function(...names, "return function " + src)(...names.map(k => V[k]));
    video._clk = 0;
    video._onH = onH;
    video._onV = onV;
    // (the CPU adds the clocks to currentCycles, which counts within the
    // emulated second, cycleSeconds, before it calls polltime)
    cpu.debugWrite.add((addr, val) => {
        // judge from the loader's handover to the rupture on: its switch S2,
        // the first write of the game screen's control value (&D8)
        if (addr === 0xfe20 && val === 0xd8 && !judging) { judging = true; nH = 0; }
        return false;
    });
    if (args.ula) cpu.debugWrite.add((addr, val) => {
        // --ula: each write to the video ULA's control register, with the
        // line cycle it lands on (the last sync was on cycle 90)
        if ((addr === 0xfe46 || addr === 0xfe47 || addr === 0xfe44 || addr === 0xfe45) && ulaSeq.length < 60 && judging) ulaSeq.push({ k: `T1w${(addr & 15).toString(16)}=${val.toString(16)}pc${cpu.pc.toString(16)}@x`, at: 0, iv: [] });
        if (addr === 0xfe45 && ulaSeq.length < 4) ulaSeq.push({ k: `T1start@${(272 + linesThisField - 1 + 312) % 312}`, at: cpu.cycleSeconds * 2000000 + cpu.currentCycles, iv: [] });
        if ((addr & 0xfff0) !== 0xfe20 || (addr & 1) || !judging) return false;   // (from the handover on)
        const t = cpu.cycleSeconds * 2000000 + cpu.currentCycles;
        // (the line: the vertical sync starts line 272, and linesThisField
        // counts the syncs since, the first being line 272's own, on its
        // cycle 90; the cycle is 90 at the last sync)
        const cyc = (((t - lastH + 90) % 128) + 128) % 128;
        const line = (272 + linesThisField - (cyc < 90 ? 0 : 1) + 312) % 312;
        const k = `${val.toString(16)}@${line}:${cyc}`;
        ulaWrites.set(k, (ulaWrites.get(k) || 0) + 1);
        if (ulaSeq.length < 4000) ulaSeq.push({ k, at: t, iv: [] });
        return false;
    });
    video.polltime = function (clocks) {
        this._clk = cpu.cycleSeconds * 2000000 + cpu.currentCycles - clocks;
        patched.call(this, clocks);
    };
}

// --inject N: the fault injection. At each entry to the rupture's interrupt
// work (RUPT, from the loader's symbols), the CPU is held for d cycles before
// it runs (the clock and every device go on: as an interrupt that a SEI
// section or another handler held off), d going 0, 1, 2 ... N in turn for S1
// and for S2 separately, again and again, except while the disc is in use
// (the hold would hold off DFS's NMIs too, which no SEI does); the report
// gives the switches made late (the rupture's rslip, modulo 256) and the
// delays covered.
const LSY = {};
for (const m of readFileSync(resolve(dirname(resolve(args.build || CAND_BUILD)), "loader-symbols.txt"), "utf8").matchAll(/'([^']+)':(\d+)/g)) LSY[m[1]] = +m[2];
const INJ = args.inject !== undefined ? +args.inject : -1;
const injCount = [0, 0];
function installInject(s) {
    const cpu = s._machine.processor;
    // --t2skew N: hold the CPU N cycles just before the loader starts the
    // user VIA's timer 2 (its write of T2C-H), so that the timer's phase
    // against the lines differs from the usual run's: the loader's
    // calibration must find it
    if (args.t2skew) {
        let done = false;
        cpu.debugWrite.add(addr => { if (addr === 0xfe69 && !done) { done = true; cpu.polltime(+args.t2skew); } return false; });
    }
    if (args.ula) cpu.debugInstruction.add(pc => {
        if (pc === LSY.RUPT && ulaSeq.length < 4000) {
            const cyc = (((cpu.cycleSeconds * 2000000 + cpu.currentCycles - lastH + 90) % 128) + 128) % 128;
            ulaSeq.push({ k: `RUPT${cpu.ramRomOs[LSY.rphase]}L${(cpu.sysvia.t1l >> 1)}E${((cpu.sysvia.t1l - cpu.sysvia.t1c) >> 1)}D${((((cpu.uservia.t2c + 1) >>> 1) & 255) - cpu.ramRomOs[LSY.rtgt + 2 * cpu.ramRomOs[LSY.rphase]]) & 255}@${(272 + linesThisField - (cyc < 90 ? 0 : 1) + 312) % 312}:${cyc}`, at: 0, iv: [] });
        }
        return false;
    });
    if (INJ < 0) return;
    cpu.debugInstruction.add(pc => {
        // (not while the disc is in use: holding the CPU here would also hold
        // off DFS's NMIs, which nothing on a real machine can do, and lose
        // the disc's bytes)
        if (pc !== LSY.RUPT || !judging || cpu.ramRomOs[LSY.rdisc]) return false;
        const sw = cpu.ramRomOs[LSY.rphase];                // 0: S1, 1: S2
        const d = injCount[sw] % (INJ + 1);
        injCount[sw]++;
        if (d) cpu.polltime(d);
        return false;
    });
}
let hooked = false, sess = null;
const pilot = makePilot({ screens: !!args.screens, views: !!args.views });
const r = await runElite({ build: B, pilot, iters: ITERS, maxSecs: +(args.maxsecs || 4000), patch: patchCommander,
    onBoot: s => { hooked = true; install(s); installInject(s); sess = s; }, onIter: i => { iterNow = i; } });
if (INJ >= 0) console.log(`injected delays 0-${INJ} cycles: S1 ${injCount[0]} entries, S2 ${injCount[1]}; switches made late (rslip, to 255): ${sess._machine.processor.ramRomOs[LSY.rslip]}`);
const hist = [...intervals.entries()].sort((a, b) => b[1] - a[1]).map(([d, n]) => `${d}:${n}`).join(" ");
console.log(`iterations ${r.iters}${r.error ? " (stopped: " + r.error + ")" : ""}; horizontal syncs ${nH}; fields ${fields}`);
console.log(`hsync intervals (2 MHz cycles: count): ${hist}`);
console.log(`lines a field (count): ${[...fieldCounts.entries()].map(([l, n]) => `${l}:${n}`).join(" ")}`);
if (args.ula) {
    const by = new Map();
    for (const u of ulaSeq) { const key = `${u.k} -> ${u.iv.slice(0, 2).join(" ")}`; by.set(key, (by.get(key) || 0) + 1); }
    for (const [k, n] of [...by.entries()].sort()) console.log(`  ULA ${k} (${n})`);
    const sw = ulaSeq.filter(u => /^(d8|c4|T1start|RUPT\dL\d+E-?\d+D\d+|T1w\w+)@/.test(u.k));
    console.log(`the first switches: ${sw.slice(0, 30).map(u => `${u.k}->${u.iv.slice(0, 2).join("/")}`).join(" ")}`);
}
if (args.ula) console.log(`ULA control writes (value@line cycle: count): ${[...ulaWrites.entries()].map(([k, n]) => `${k}:${n}`).join(" ")}`);
for (const b of badH.slice(0, 10)) console.log(`  hsync interval ${b.interval} at cycle ${b.at} (iteration ${b.iter})`);
for (const b of badV.slice(0, 10)) console.log(`  a field of ${b.lines} lines (iteration ${b.iter})`);
if (args.log) writeFileSync(args.log, JSON.stringify({ intervals: Object.fromEntries(intervals), fieldCounts: Object.fromEntries(fieldCounts), badH, badV }));
const ok = !r.error && r.iters >= ITERS && badH.length === 0 && badV.length === 0;
console.log(ok ? "HSYNC PASS" : "HSYNC FAIL");
process.exit(ok ? 0 : 1);
