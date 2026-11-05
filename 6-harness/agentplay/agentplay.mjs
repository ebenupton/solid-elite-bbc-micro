#!/usr/bin/env node
// One agentplay session on the Model B: elite-agent plays the released disc Elite (with the
// gate's patches) while the port replays its inputs read for read; game state compared every
// iteration (session.mjs).
//
// node 6-harness/agentplay/agentplay.mjs --out DIR [--minutes 10] [--seed N]
//      [--commander jameson|trader|equipped|rich|deadly|mission2|debrief1|galaxy3|debrief2|wanted]
//      [--mode efficient,curious,fair,nosave,nomission,load]
//      [--chaos all|ecm,bomb,...|disc|docked] [--start FRAMES] [--shots N] [--keepgoing N] [--strict] [--noobserve]
//      [--savediscs] (write both machines' discs, with their saves, at the end: ref-disc.ssd, cand-disc.ssd)
//      [--workaround inbay] (candidate-side runtime workaround for a known port bug, to play on past it)
//      [--ref build.json] [--cand build.json] [--refdisc disc] [--canddisc disc] [--iters N]
// (--refdisc/--canddisc: boot that disc instead of the build's own, e.g. one a session saved)
// Writes DIR/{config.json, inputs.jsonl, agent.log, journal.jsonl, events.jsonl, summary.json, coverage-*.json, *.png}.
// Exit status: 0 no findings, 1 a finding (divergence, crash, hang, BRK, page &0D, save file), 2 error.
import { Session } from "./session.mjs";
import { parseArgs } from "../args.mjs";
import { MODES } from "./styles.mjs";
import { resolve } from "path";

const a = parseArgs({ out: "value", minutes: "value", seed: "value", commander: "value", mode: "value", chaos: "value", start: "value", shots: "value", keepgoing: "value", strict: "flag", noobserve: "flag", savediscs: "flag", ref: "value", cand: "value", refdisc: "value", canddisc: "value", iters: "value", workaround: "value" });
if (!a.out) { console.error("--out DIR required"); process.exit(2); }
const env = {};
for (const m of String(a.mode || "efficient").split(",")) { if (!MODES[m]) { console.error(`unknown mode ${m}`); process.exit(2); } Object.assign(env, MODES[m]); }
const cfg = {
    out: a.out, minutes: +(a.minutes || 10), seed: a.seed !== undefined ? +a.seed : undefined, commander: a.commander || "jameson",
    agentEnv: env, mode: String(a.mode || "efficient"), chaos: a.chaos || null, startFrame: +(a.start || 700), shots: +(a.shots || 0), keepGoing: +(a.keepgoing || 0),
    workarounds: a.workaround ? String(a.workaround).split(",") : [], strict: !!a.strict, saveDiscs: !!a.savediscs, observe: !a.noobserve, iters: a.iters ? +a.iters : undefined,
};
for (const k of ["ref", "cand", "refdisc", "canddisc"]) if (a[k]) cfg[k] = resolve(a[k]);     // (absolute, for the log's header)
try {
    const S = new Session(cfg);
    await S.start();
    const s = await S.run();
    const bad = s.findings.filter(f => f.kind !== "observable" && f.kind !== "hang-both");
    console.log(`AGENTPLAY ${bad.length ? "FINDINGS" : "CLEAN"} ${cfg.out}: ${s.gameMinutes} game min, ${s.compared} iterations compared (${s.flight} in flight), ${s.reads} reads (${s.keyReads} with keys), findings ${s.findings.length}` +
        `${s.divergence ? `, first divergence at iteration ${s.divergence.iter}` : ""}; final ${JSON.stringify(s.final)}`);
    console.log(`features ${JSON.stringify(s.features)} agent ${JSON.stringify(s.agentNotes)}`);
    process.exit(bad.length ? 1 : 0);
} catch (e) { console.error(e.stack || e); process.exit(2); }
