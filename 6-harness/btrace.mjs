// Call tracing for bcompare.mjs --trace FROM,TO,LABEL[+LABEL...][,EXTRA+...]:
// at each entry of a LABEL (a label of either program, checked against the
// program's image as the hooks are) during main-loop iterations FROM..TO,
// log the program, label, A, X, Y, C, RAND and the EXTRA variables (NAME or
// NAME+offset, flight symbols), so that two runs' traces can be diffed to
// find where they part.
export function makeTracer(spec, build, out) {
    const [from, to, labels, extra] = spec.split(",");
    const sy = build.progs.flight.sy;
    const watch = new Map();
    for (const p of Object.values(build.progs)) for (const n of labels.split("+")) {
        const a = p.sy[n];
        if (a === undefined) continue;
        const img = p.images.find(im => a >= im.base && a + 3 <= im.base + im.data.length);
        if (!img) continue;
        (watch.get(a) || watch.set(a, []).get(a)).push({ n, p: p.name, map: img.map, sig: [0, 1, 2].map(i => img.data[a + i - img.base]) });
    }
    const ex = (extra || "").split("+").filter(Boolean).map(n => { const [b, o] = n.split("~"); return [n, sy[b] + (+o || 0)]; });
    let inst = false, it = 0;
    return (i, s, res) => {
        it = i;
        if (inst) return;
        inst = true;
        const cpu = res.cpu;
        cpu.debugInstruction.add(pc => {
            if (it < +from || it > +to || !watch.has(pc)) return false;
            for (const w of watch.get(pc)) {
                if (![0, 1, 2].every(k => cpu.readmem(pc + k) === w.sig[k])) continue;
                const ret = (cpu.ramRomOs[0x101 + cpu.s] | cpu.ramRomOs[0x102 + cpu.s] << 8) - 2;
                const r = a => cpu.ramRomOs[a].toString(16).padStart(2, "0");
                out.push(`${it} ${w.p} ${w.n} from &${ret.toString(16)} A=${cpu.a.toString(16)} X=${cpu.x.toString(16)} Y=${cpu.y.toString(16)} C=${cpu.p.c ? 1 : 0} RAND=${r(0)}${r(1)}${r(2)}${r(3)} ${ex.map(([n, a]) => n + "=" + r(a)).join(" ")}`);
            }
            return false;
        });
    };
}
