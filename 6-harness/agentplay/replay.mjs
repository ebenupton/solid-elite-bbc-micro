#!/usr/bin/env node
// Replay a session's input log into both machines, without the agent: the same reads get
// the same keys, so the session (and any divergence) comes back exactly (the Master port's
// replay.mjs).
//
// node 6-harness/agentplay/replay.mjs --run DIR [--out DIR2] [--until ITER] [--keepgoing N]
//      [--cut ITER --save FILE] [--trace FROM,TO] [--shots N] [--noobserve] [--cand build.json] [--ref build.json] [--log inputs.jsonl]
// Defaults: the builds in DIR/inputs.jsonl's header, while they are still the builds the log
// was recorded with (their hashes in the header; --cand swaps in another build, to test a
// fix; --workaround none turns off a workaround the session used); --out DIR/replay. --until: stop after that iteration. --cut ITER --save FILE: write
// the log cut short after ITER (a minimal repro) and stop. Exit status as agentplay.mjs.
import { Session } from "./session.mjs";
import { parseArgs } from "../args.mjs";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { createHash } from "crypto";
import { loadBuild } from "../blib.mjs";
import { resolve } from "path";

const a = parseArgs({ run: "value", log: "value", out: "value", until: "value", keepgoing: "value", cut: "value", save: "value", trace: "value", shots: "value", noobserve: "flag", cand: "value", ref: "value", workaround: "value" });
const log = a.log || `${a.run}/inputs.jsonl`;
if (!a.run && !(a.log && (a.out || a.cut !== undefined))) { console.error("--run DIR, or --log FILE with --out DIR"); process.exit(2); }
const h = JSON.parse(readFileSync(log, "utf8").split("\n")[0]);
if (!h.header) { console.error("no header in", log); process.exit(2); }
if (a.cut !== undefined) {
    const it = +a.cut, lines = readFileSync(log, "utf8").split("\n").filter(Boolean).map(l => JSON.parse(l));
    const keep = lines.filter(e => e.header || (!e.end && (e.i === undefined || e.i <= it) && (e.poke === undefined || e.poke <= it + 1)));
    keep.push({ end: true, iter: it + 1, cut: true });
    writeFileSync(a.save, keep.map(e => JSON.stringify(e)).join("\n") + "\n");
    console.log(`${a.save}: ${keep.length} records, to iteration ${it + 1}`);
    process.exit(0);
}
const shaOf = (f, disc) => {
    const b = loadBuild(f); if (disc) b.disc = disc;
    const x = createHash("sha1"); x.update(readFileSync(b.file)); x.update(readFileSync(b.disc));
    for (const p of Object.values(b.progs)) for (const im of p.images) x.update(im.data);
    return x.digest("hex").slice(0, 12);
};
for (const d of ["ref", "cand"]) {
    if (a[d]) continue;
    if (!h[d] || !existsSync(h[d])) { console.error(`the log's ${d} build ${h[d]} is not there: pass --${d} build.json`); process.exit(2); }
    const now = shaOf(h[d], h[d + "disc"]);
    if (h[d + "Sha"] && now !== h[d + "Sha"]) { console.error(`the log's ${d} build ${h[d]} has changed since the log was recorded (${now}, recorded ${h[d + "Sha"]}): pass --${d} build.json`); process.exit(2); }
}
const cfg = {
    out: a.out || `${a.run}/replay`, replay: log, seed: h.seed, commander: h.commander, startFrame: h.startFrame, strict: h.strict,
    ref: a.ref ? resolve(a.ref) : h.ref, cand: a.cand ? resolve(a.cand) : h.cand, refdisc: h.refdisc, canddisc: a.cand ? undefined : h.canddisc,
    workarounds: a.workaround ? (a.workaround === "none" ? [] : String(a.workaround).split(",")) : (h.workarounds || []),
    trace: a.trace ? a.trace.split(",").map(Number) : undefined,
    until: a.until !== undefined ? +a.until : undefined, keepGoing: +(a.keepgoing || 0), shots: +(a.shots || 0), observe: !a.noobserve,
};
try {
    const S = new Session(cfg);
    await S.start();
    console.log(`ref ${S.builds.ref} (${S.builds.refSha}), cand ${S.builds.cand} (${S.builds.candSha})`);
    const s = await S.run();
    const bad = s.findings.filter(f => f.kind !== "observable" && f.kind !== "hang-both");
    console.log(`REPLAY ${bad.length ? "FINDINGS" : "CLEAN"} ${cfg.out}: ${s.compared} iterations compared, ${s.reads} reads, findings ${s.findings.length}${s.divergence ? `, first divergence at iteration ${s.divergence.iter}` : ""}`);
    for (const f of s.findings.slice(0, 20)) console.log(`  ${f.kind}: ${f.text}`);
    process.exit(bad.length ? 1 : 0);
} catch (e) { console.error(e.stack || e); process.exit(2); }
