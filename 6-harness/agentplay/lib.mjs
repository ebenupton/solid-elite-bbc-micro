// agentplay's machine for the Model B: BBC Micro disc Elite (the released disc or the
// port) on jsbeeb, with blib.mjs's input model and determinism measures, made
// steppable so that two machines can run side by side, one fed by elite-agent and the
// other replaying the first one's reads as they happen. It is the Master port's
// master/tools/agentplay/lib.mjs, for blib's machines: a build is a build.json
// (blib.loadBuild), with two programs, the flight code and the docked code, of which one
// is in memory at a time, and every hook is a label of one program (blib.progHooks).
//
// Every read of an input is a numbered "poll", in the order the game makes them:
//   k  DOKEY, once a main-loop iteration (either program): the keys held for the
//      iteration. The iteration's other reads take their answers from this set: DKS4's
//      tests of single keys (DKS1, the flight keys; SHIFT on the charts) at DKS4+17,
//      and DK4's RDKEY (the port's RDKEY result at Rd2, the lowest key from 16 on);
//   w  RDKEY called from anywhere but DK4 (or DOKEY): a key wait (TT217's t and t2, with
//      the routine that called TT217; the title screens' TITLE loop; PAUSE2; the pause
//      loop FREEZE), with the call site: the keys held now;
//   d  DKS4 for CTRL (key 1), whose callers are the hyperspace routines: held or not;
//   c  OSRDCH (&FFE0), which only OSWORD 0 calls, from MT26 (a commander's name for the
//      disc menu, a system's name for the chart's search): the next character typed.
//      The call is not run: the character is returned in A (C set for ESCAPE) and the
//      machine goes back to OSWORD's code, which echoes it through the game's WRCHV
//      handler as the keyboard would have, in both machines.
// A machine's input source answers each poll, or returns null to block: the machine
// then stops at that instruction and the poll is asked again on the next run().
//
// As blib (and for the same reasons, documented there): the laser pulse counter is
// counted per pass of M% rather than per vsync; the sound is off (DNOIZ) from TT170; a
// byte of the compared state that the filing system wrote and the game has not written
// since is set to 0 at each MLOOP, pass of M% and call of DIALS (above page 0; blib
// does it at MLOOP and M%) and left out of the
// comparison meanwhile; the reference's patches (ma93-q, ee51-c, mv8-half: build.json's
// "patches") are applied; and at TT170 the candidate's boot leftovers are seeded from the
// reference (seedFrom). At every MLOOP the game state (blib.regionsFor) is snapshotted.
//
// What it watches for besides: BRKs (any BRK instruction run once the game has started,
// with where it was and the error block after it), writes by game code to page &0D, and
// the routine labels of each poll (control flow).
import { progHooks, regionsFor, canonFor, excludeSet, TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE, PATCHES, bootModelB, physRead, loadSyms, page1Watch } from "../blib.mjs";
import { existsSync, readFileSync } from "fs";
import { dirname, resolve } from "path";
export { regionsFor };

export const ROOT = decodeURIComponent(new URL("../..", import.meta.url).pathname).replace(/\/$/, "") + "/";
export const NI = 37, NOSH = 12;
export const CYCLES_PER_FRAME = 40000;          // 2 MHz, 50 Hz
// routines whose entries are counted (coverage of the game's features), in either program
export const ROUTINES = ["LAUN", "DOENTRY", "TT18", "Ghy", "MJP", "WARP", "DEATH", "ESCAPE", "ECBLB2", "ECMOF",
    "FRMIS", "SFRMIS", "EXNO3", "GTHG", "EQSHP", "TT219", "TT208", "TT213", "TT25", "TT167", "STATUS", "TT22", "TT23",
    "SVE", "LOD", "CATS", "DELT", "MEBRK", "BRBR", "MT26", "HME2", "TITLE", "DEATH2",
    "BRIEF", "BRIEF2", "BRIEF3", "DEBRIEF", "DEBRIEF2", "FREEZE"];

export class BMachine {
    // opts: name, build (blib.loadBuild), input ({ poll(ctx) }: ctx.kind k|w|d|c),
    //       seedFrom (another BMachine whose TT170 state seeds this one's boot leftovers),
    //       rand (4 bytes written to RAND at TT170), patch(m) (called once, at the first QU5),
    //       watch0d (record page &0D writes by game code), cover (whole-code coverage)
    constructor(opts) {
        Object.assign(this, { name: opts.name, b: opts.build, input: opts.input, opts });
        this.sy = { ...this.b.loader, ...this.b.progs.docked.sy, ...this.b.progs.flight.sy };   // (the workspace: the same in both programs)
        this.iter = 0; this.polls = 0; this.tt100 = 0;
        this.snaps = [];            // [iteration, snapshot, filing-system offsets] not yet taken by the comparison
        this.events = [];           // [iteration, kind, detail]
        this.started = false; this.blocked = null; this.patched = false; this.inGame = false;
        this.lastProgressCycles = 0; this.page0d = []; this.brks = [];
        this.iterInfo = [];         // per iteration: [poll index at MLOOP, emulated seconds]
        this.keysDown = [];
        this.prog = "docked";
        this.wa = Object.fromEntries((opts.workarounds || []).map(w => [w, true]));
    }

    async boot() {
        this.s = await bootModelB(this.b.disc);
        const cpu = this.cpu = this.s._machine.processor, b = this.b;
        this.ram = cpu.ramRomOs;
        this.regions = regionsFor(b);
        this.canon = canonFor(b, this.regions);
        this.isRamBank = n => !!cpu.model.swram[n & 15];
        const { hookOf, hookLd, live, bankOf } = progHooks(b, cpu);
        Object.assign(this, { hookOf, live, bankOf });
        const P = b.progs, byPc = this.byPc = new Map();
        const tryHook = (p, n, off) => { try { return hookOf(p, n, off); } catch { return null; } };
        const add = (key, h, extra = {}) => { if (!h) return null; Object.assign(h, { key, ...extra }); (byPc.get(h.a) || byPc.set(h.a, []).get(h.a)).push(h); return h; };
        for (const p of [P.flight, P.docked]) {
            add("DOKEY", hookOf(p, "DOKEY"), { poll: true });
            add("RDKEY", hookOf(p, "RDKEY"), { poll: true });
            add("Rd2", hookOf(p, "Rd2"));
            add("DKS4", hookOf(p, "DKS4", 17), { poll: true });
            add("MLOOP", hookOf(p, "MLOOP"));
            add("TT100", hookOf(p, "TT100"));
            add("S", hookOf(p, "S%")); add("S", hookOf(p, "S%", 3));
            add("DIALS", tryHook(p, "DIALS"));
            for (const r of ROUTINES) add("R", tryHook(p, r), { routine: r });
        }
        add("Mpc", hookOf(P.flight, "M%"));
        add("TT170", hookOf(P.docked, "TT170"), { poll: true });
        add("QU5", hookOf(P.docked, "QU5"));
        // the interrupt handler's DEC LASCT (blib)
        const las = hookLd("LASDEC", 0, [0xce, 0x46, 0x03]) || hookLd("VNT3", 14, [0xce, 0x46, 0x03]);
        add("LAS", las); add("LASN", { ...las, a: las.a + 3, sig: [] });
        // OSRDCH (the MOS's entry, whatever RDCHV points at)
        add("RDCH", { prog: null, name: "OSRDCH", a: 0xffe0, map: "m", sig: [] }, { poll: true });
        for (const a of [0xffce, 0xffd1, 0xffd4, 0xffd7, 0xffda, 0xffdd, 0xfff7, 0xfff1]) add("FS", { prog: null, name: "FS", a, map: "m", sig: [] });
        for (const name of b.patches) for (const pt of [].concat(PATCHES[name](P.flight))) add("PATCH", { prog: P.flight, name, ...pt });
        this.hookTab = new Uint8Array(65536);
        for (const a of byPc.keys()) this.hookTab[a] = 1;
        this._labels();
        // compared bytes, and the filing system's (blib's settle)
        this.inRegion = new Uint8Array(65536);
        for (const [a, n] of this.regions) this.inRegion.fill(1, a, a + n);
        this.offOfAddr = new Map();
        { let o = 0; for (const [a, n] of this.regions) { for (let i = 0; i < n; i++) this.offOfAddr.set(a + i, o + i); o += n; } }
        this.dirty = new Set();
        this.stash = new Map();         // (settle()'s zeroed bytes and their values: unsettle())
        const sysWriter = () => {
            const pc = cpu.pc;
            if (pc >= 0xc000) return true;
            if (pc >= 0x8000) return !this.isRamBank(cpu.romsel);
            return pc >= 0x0d00 && pc < 0x0e00;
        };
        cpu.debugWrite.add(a => {
            if (!this.inGame || !this.inRegion[a]) return false;
            if (sysWriter()) this.dirty.add(a); else { this.dirty.delete(a); this.stash.delete(a); }
            return false;
        });
        this.written = new Set();
        this.bootWrites = cpu.debugWrite.add(a => { if (this.inGame && !this.started && a < 0x8000) this.written.add(a); return false; });
        this.page1 = page1Watch(cpu, sysWriter, () => this.prog, () => this.started);
        if (this.opts.watch0d) cpu.debugWrite.add(a => {
            if (!this.inGame || a < 0x0d00 || a > 0x0dff || sysWriter()) return false;
            const pc = cpu.oldPcArray[cpu.oldPcIndex];
            if (this.page0d.length < 20) { this.page0d.push([this.iter, pc, a]); this.event("page0d", `PC &${pc.toString(16)} (ROMSEL ${cpu.romsel & 15}) wrote &${a.toString(16)}`); }
            return false;
        });
        // (the instruction after the flight code's INBAY's JSR OSCLI, when INBAY is in main RAM:
        // --workaround inbay)
        const ib = P.flight.sy.INBAY;
        this.inbayRet = ib !== undefined && ib < 0x8000 && this.b.banks.H ? ib + 7 : -1;
        this._fastExec();
        this.s._video.frameSkipCount = +(process.env.FRAMESKIP || 25);
        this.cyclesNow = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
    }

    // jsbeeb's execute, with this machine's hooks tested inline (a table lookup per
    // instruction), whole-code coverage (by program: the flight and docked programs
    // share addresses) and BRKs. Other debugInstruction hooks (traces) are still called.
    _fastExec() {
        const cpu = this.cpu, tab = this.hookTab, self = this;
        cpu.execute = function (n) {
            this.halted = false;
            this.targetCycles += n;
            const smaller = Math.min(this.targetCycles, this.currentCycles) & 0xfffffffe;
            if (smaller >= 2 * 1000 * 1000) { this.targetCycles -= 2 * 1000 * 1000; this.currentCycles -= 2 * 1000 * 1000; this.cycleSeconds++; }
            let first = true;
            while (!this.halted && this.currentCycles < this.targetCycles) {
                const pc = this.pc;
                const vis = self.vis && self.vis[self.prog];
                if (vis) { if (pc < 0x8000) vis[pc] = 1; else if (pc < 0xc000) vis[0x10000 + ((this.romsel & 15) << 14) + pc - 0x8000] = 1; }
                this.oldPcIndex = (this.oldPcIndex + 1) & 0xff;
                this.oldPcArray[this.oldPcIndex] = pc;
                this.memStatOffset = this.memStatOffsetByIFetchBank & (1 << (pc >>> 12)) ? 256 : 0;
                const opcode = this.readmem(pc);
                if (!first) {
                    if (tab[pc] && self.tab(pc)) { this.halted = true; return false; }
                    if (this._debugInstruction && this._debugInstruction(pc, opcode)) return false;
                }
                if (opcode === 0 && self.started) {
                    // (--workaround inbay, the candidate: the BRK the port's INBAY falls into
                    // after a death, in a build that put INBAY in main RAM: on to the docked
                    // code's JMP SCRAM in its INBAY, at &801D in its home bank, where the
                    // original's INBAY returned)
                    if (pc === self.inbayRet && self.wa.inbay) { self.event("workaround", "INBAY's return after a death: sent to the docked INBAY's JMP SCRAM"); this.pc = 0x801d; first = false; continue; }
                    self._brk(pc);
                }
                first = false;
                this.incpc();
                this.runner.run(opcode);
                if (this.takeInt) this.brk(true);
                if (!this.resetLine) this.reset(false);
            }
            return !this.halted;
        };
    }
    _brk(at) {
        const cpu = this.cpu, rs = cpu.romsel & 15;
        const paged = at >= 0x8000 && at < 0xc000;
        const byte = a => paged ? physRead(cpu, rs, a) : cpu.readmem(a & 0xffff);
        let msg = ""; for (let i = 2; i < 40; i++) { const ch = byte((at + i) & 0xffff); if (!ch) break; msg += ch >= 32 && ch < 127 ? String.fromCharCode(ch) : "."; }
        // a filing-system or OS error: a BRK in a ROM (DFS, BASIC), on the stack page (where
        // DFS builds some of its errors), or in the MOS; one in Elite's code (main RAM or
        // its sideways RAM banks) is not expected
        const fromRom = (paged && !this.isRamBank(rs)) || (at >= 0x100 && at < 0x200) || at >= 0xc000;
        const rec = { iter: this.iter, at, bank: paged ? rs : "m", code: byte(at + 1), msg, polls: this.polls, label: fromRom ? null : this.labelOf(at), fromRom, prog: this.prog };
        this.brks.push(rec);
        this.event(fromRom ? "brk-rom" : "brk", `BRK at &${at.toString(16)} (bank ${rec.bank}${rec.label ? ", " + this.prog + " " + rec.label : ""}) error ${rec.code}: ${msg}`);
    }

    // whole-code coverage: per program, every label whose span (to the next label in the
    // same mapping) had an instruction run while that program was in memory, and the labels
    // that look like code (run, or the target of a JSR/JMP in the program's images) but were
    // never run; for the port, also its renderer banks (bank5/bank6-symbols.txt next to the
    // build.json, in banks 5 and 6), whichever program ran them. Labels are "prog:label".
    coverage() {
        if (!this.vis) return null;
        const b = this.b, reached = [], unreached = [];
        const groups = [];
        for (const p of Object.values(b.progs)) {
            const byMap = {}, targets = new Set();
            for (const im of p.images) for (let i = 0; i + 2 < im.data.length; i++) { const o = im.data[i]; if (o === 0x20 || o === 0x4c) targets.add(im.data[i + 1] | im.data[i + 2] << 8); }
            for (const [k, v] of Object.entries(p.sy)) {
                if (v < 0x1000 || v >= 0xc000 || /^(CODE|LOAD)/.test(k)) continue;
                let m = "m";
                if (v >= 0x8000) { const role = p.bank[k] || p.images.find(im => v >= im.base && v < im.base + im.data.length)?.map; if (!role || role === "m") continue; m = this.bankOf(role); }
                else if (!p.images.some(im => v >= im.base && v < im.base + im.data.length)) continue;     // (workspace)
                (byMap[m] ||= []).push([k, v]);
            }
            groups.push({ tag: p.name, byMap, targets, vis: [this.vis[p.name]] });
        }
        const dir = dirname(b.file);
        for (const n of [5, 6]) {
            const f = `${dir}/bank${n}-symbols.txt`, bin = `${dir}/BANK${n}.bin`;
            if (!existsSync(f)) continue;
            const sy = loadSyms(f), targets = new Set(), labs = [];
            if (existsSync(bin)) { const d = readFileSync(bin); for (let i = 0; i + 2 < d.length; i++) if (d[i] === 0x20 || d[i] === 0x4c) targets.add(d[i + 1] | d[i + 2] << 8); }
            for (const [k, v] of Object.entries(sy)) if (v >= 0x8000 && v < 0xc000 && !/^(CODE|LOAD)/.test(k)) labs.push([k, v]);
            groups.push({ tag: `bank${n}`, byMap: { [n]: labs }, targets, vis: Object.values(this.vis) });
        }
        for (const { tag, byMap, targets, vis } of groups) for (const [m, labs] of Object.entries(byMap)) {
            labs.sort((x, y) => x[1] - y[1]);
            const idx = a => m === "m" ? a : 0x10000 + (+m << 14) + a - 0x8000;
            for (let i = 0; i < labs.length; i++) {
                const [k, v] = labs[i];
                if (i + 1 < labs.length && labs[i + 1][1] === v) continue;       // (aliases: the last name)
                const end = i + 1 < labs.length ? labs[i + 1][1] : v + 1;
                let hit = false;
                for (let a = v; a < end && !hit; a++) for (const vv of vis) if (vv[idx(a)]) { hit = true; break; }
                if (hit) reached.push(`${tag}:${k}`); else if (targets.has(v)) unreached.push(`${tag}:${k}`);
            }
        }
        return { reached, unreached };
    }

    emuSecs() { return this.cpu.cycleSeconds + this.cpu.currentCycles / 2e6; }
    rb(a) { return this.ram[a & 0xffff]; }
    rd(a, n) { return Array.from(this.ram.subarray(a, a + n)); }
    wr(a, bytes) { for (let i = 0; i < bytes.length; i++) this.ram[a + i] = bytes[i] & 255; }
    event(kind, detail) { this.events.push([this.iter, kind, detail]); }

    // label lookup (blib's), in the program now in memory
    _labels() {
        const b = this.b, labs = {};
        for (const p of Object.values(b.progs)) {
            const l = {};
            for (const [k, v] of Object.entries(p.sy)) {
                if (v < 0x1000 || /^(CODE|LOAD)/.test(k)) continue;
                const m = v < 0x8000 || v >= 0xc000 ? "m" : (p.bank[k] || p.images.find(im => v >= im.base && v < im.base + im.data.length)?.map || "m");
                (l[m] ||= []).push([k, v]);
            }
            for (const x of Object.values(l)) x.sort((x, y) => x[1] - y[1]);
            labs[p.name] = l;
        }
        this.labs = labs;
    }
    _roleOf(romsel) { for (const r of Object.keys(this.b.banks)) if (this.bankOf(r) === (romsel & 15)) return r; return null; }
    labelOf(a, romsel = this.cpu.romsel, prog = this.prog) {
        const lab = this.labs[prog][a < 0x8000 || a >= 0xc000 ? "m" : (this._roleOf(romsel) || "m")] || [];
        let lo = 0, hi = lab.length - 1, r = null;
        while (lo <= hi) { const m = (lo + hi) >> 1; if (lab[m][1] <= a) { r = lab[m][0]; lo = m + 1; } else hi = m - 1; }
        return r && /_[CO]$/.test(r) ? r.slice(0, -2) : r;     // (a cold body, name_C, or an overlay's copy, name_O: the name)
    }
    _stackWord(k) { const s = this.cpu.s; return this.rb(0x100 + ((s + k) & 0xff)) | (this.rb(0x100 + ((s + k + 1) & 0xff)) << 8); }
    // the JSR whose return address is at S+k, through far-call frames (blib's callerAt)
    _callerAt(k, romsel = this.cpu.romsel) {
        let w = this._stackWord(k);
        const fr = this.b.loader.farret;
        while (fr !== undefined && w + 1 === fr) { romsel = this.rb(0x100 + ((this.cpu.s + k + 2) & 0xff)); k += 3; w = this._stackWord(k); }
        return { site: w + 1 - 3, k, romsel };
    }

    snapshot() {
        const parts = this.regions.map(([a, n]) => this.ram.subarray(a, a + n));
        const out = new Uint8Array(parts.reduce((s, p) => s + p.length, 0));
        let o = 0; for (const p of parts) { out.set(p, o); o += p.length; }
        return this.canon(out);
    }
    // the filing system's bytes above page 0 that the game has not written since: set to 0
    settle() { for (const a of this.dirty) if (a >= 0x100) { this.stash.set(a, this.ram[a]); this.ram[a] = 0; this.dirty.delete(a); } }
    // a filing-system call (OSFIND, OSGBPB, OSBPUT, OSBGET, OSARGS, OSFILE, OSCLI, and
    // OSWORD &7F, the disc controller): the bytes settle() zeroed that the game has not
    // written since are put back, and are the filing system's again. They are DFS's
    // catalogue (the game's WP holds it from CATD, or a load, until the game writes over
    // it), which DFS writes back to the disc when it saves a file: zeroed, it would wipe
    // the disc's catalogue, which the game would not have done
    unsettle() { for (const [a, v] of this.stash) { this.ram[a] = v; this.dirty.add(a); } this.stash.clear(); }
    dirtyOffsets() { return this.dirty.size ? [...this.dirty].map(a => this.offOfAddr.get(a)) : null; }

    // the per-instruction hook; true stops the machine at pc (a blocked poll, or a redirect)
    tab(pc) {
        if (this.blocked) {
            // (a blocked poll is asked again; the other hooks at its address have fired)
            if (this.blocked.h.a !== pc) return false;
            return this.fire(this.blocked.h, pc);
        }
        const hs = this.byPc.get(pc);
        if (!hs) return false;
        for (const h of hs) if (this.live(h)) { if (h.prog) this.prog = h.prog.name; if (this.fire(h, pc)) return true; }
        return false;
    }
    _ask(h, ctx) {
        ctx = { m: this, poll: this.polls, iter: this.iter, ...ctx };
        const r = this.input.poll(ctx);
        if (r === null) { this.blocked = { h, ctx }; return null; }
        this.blocked = null;
        this.polls++; this.lastProgressCycles = this.cyclesNow();
        return r;
    }
    fire(h, pc) {
        const cpu = this.cpu, sy = this.sy;
        switch (h.key) {
            case "DOKEY": {
                if (!this.started) break;
                const k = this._ask(h, { kind: "k", site: "DOKEY" });
                if (k === null) return true;
                this.keysDown = k;
                break;
            }
            case "RDKEY": {
                if (!this.started) break;
                const c = this._callerAt(1);
                const site = this.labelOf(c.site, c.romsel);
                if (site === "DK4" || site === "DOKEY") break;      // (DOKEY's reads: the iteration's keys)
                let s = site;
                if (site === "t" || site === "t2") { const w = this._callerAt(c.k + 2, c.romsel); s = `${site}<${this.labelOf(w.site, w.romsel)}`; }
                const k = this._ask(h, { kind: "w", site: s });
                if (k === null) return true;
                this.keysDown = k;
                break;
            }
            case "Rd2":
                // RDKEY's result, the lowest pressed key from 16 on, with bit 7 set (or &80):
                // the port scans a column at a time, not through DKS4 (blib)
                if (this.started) { const ks = this.keysDown.filter(k => k >= 16 && k < 128); cpu.a = ks.length ? Math.min(...ks) | 0x80 : 0x80; }
                break;
            case "DKS4": {
                if (!this.started) break;
                const key = cpu.x & 0x7f;
                let down;
                if (key === 1) {
                    const c = this._callerAt(1);
                    const d = this._ask(h, { kind: "d", key, site: this.labelOf(c.site, c.romsel) });
                    if (d === null) return true;
                    down = !!d;
                } else down = this.keysDown.includes(key);
                cpu.x = down ? key | 0x80 : key;
                break;
            }
            case "RDCH": {
                if (!this.started) break;
                const ch = this._ask(h, { kind: "c", site: "OSRDCH" });
                if (ch === null) return true;
                // return from OSRDCH with the character: A, C set for ESCAPE, then RTS
                cpu.a = ch & 255; cpu.p.c = ch === 27;
                const s = cpu.s, ret = this.rb(0x100 + ((s + 1) & 0xff)) | this.rb(0x100 + ((s + 2) & 0xff)) << 8;
                cpu.s = (s + 2) & 0xff;
                this.redirectTo = (ret + 1) & 0xffff;
                return true;
            }
            case "FS": if (this.stash.size && (pc !== 0xfff1 || cpu.a === 0x7f)) this.unsettle(); break;
            case "PATCH": h.apply(cpu); break;
            case "Mpc": {
                const v = this.rb(sy.LASCT);
                if (v) this.ram[sy.LASCT] = v - 1;
                this.settle();
                this.lastProgressCycles = this.cyclesNow();     // (progress: the death animation runs M% 255 times, with no read or MLOOP)
                break;
            }
            case "LAS": this.lasSaved = this.rb(sy.LASCT); break;
            case "LASN": if (this.lasSaved >= 0) { this.ram[sy.LASCT] = this.lasSaved; this.lasSaved = -1; } break;
            case "MLOOP":
                if (!this.started) break;
                {
                    // harness pokes (styles.mjs chaos), at an iteration boundary in both machines
                    const pk = this.pokes && this.pokes.get(this.iter);
                    if (pk) for (const [sym, off, bytes] of pk) this.wr(sy[sym] + off, bytes);
                }
                this.settle();
                this.snaps.push([this.iter, this.snapshot(), this.dirtyOffsets()]);
                this.iterInfo.push([this.polls, this.emuSecs()]);
                if (this.onIter) this.onIter(this);
                this.iter++; this.lastProgressCycles = this.cyclesNow();
                break;
            case "TT100": if (this.started && h.prog.name === "flight") this.tt100++; break;
            case "QU5":
                // the commander patch, once: at QU5, before DFAULT copies NA% (the last saved
                // commander) into the commander
                if (!this.patched && this.opts.patch) { this.patched = true; this.opts.patch(this); this.event("patch", "commander patched at QU5"); }
                break;
            case "DIALS":
                // the dashboard drawn: the filing system's bytes the game has not written are
                // set to 0 now too, as at MLOOP and M% (a launch draws the dashboard's
                // altitude from ALTIT, at &0FD1 in WP, before the first pass of M%, and the
                // ship file's load, just before, leaves a byte of the disc's catalogue there
                // (CATD), another in each build's disc)
                if (this.started) this.settle();
                break;
            case "S":
                if (!this.inGame) {
                    this.inGame = true;
                    if (this.opts.cover) this.vis = { flight: new Uint8Array(0x50000), docked: new Uint8Array(0x50000) };
                    if (this.onEntry) this.onEntry(this);
                }
                break;
            case "TT170":
                if (this.started) break;
                if (this.opts.seedFrom && !this.opts.seedFrom.init) { this.blocked = { h, ctx: { kind: "tt170" } }; return true; }
                this.blocked = null;
                this.started = true;
                this.ram[sy.DNOIZ] = 0xff;              // sound off, in both machines
                if (this.opts.seedFrom) this.seeded = this._seed(this.opts.seedFrom);
                if (this.opts.rand) this.wr(sy.RAND, this.opts.rand);
                this.bootWrites.remove();
                this.dirty.clear();
                this.init = this.snapshot();
                this.lastProgressCycles = this.cyclesNow();
                break;
            case "R":
                if (this.started) { this.event("routine", h.routine); if (h.routine === "SVE") this.sveAt = this.iter; }
                break;
        }
        return false;
    }
    _seed(ref) {
        const out = [];
        let o = 0;
        for (const [, n, name] of ref.regions) {
            const c = this.regions.find(r => r[2] === name);
            if (c && c[1] === n) for (let i = 0; i < n; i++) if (!this.written.has(c[0] + i) && this.rb(c[0] + i) !== ref.init[o + i]) { out.push([c[0] + i, ref.init[o + i]]); this.ram[c[0] + i] = ref.init[o + i]; }
            o += n;
        }
        return out;
    }

    // Run up to `cycles` emulated cycles; stops early (returns "blocked") at a poll its
    // input cannot answer yet. The hook is called by hand for the first instruction of
    // each slice, as jsbeeb skips it for the first instruction it executes.
    run(cycles) {
        const cpu = this.cpu, end = this.cyclesNow() + cycles;
        for (;;) {
            const now = this.cyclesNow();
            if (this.blocked || now !== this.tabAt) {
                this.tabAt = now;
                if (this.hookTab[cpu.pc] && this.tab(cpu.pc)) {
                    cpu.targetCycles = cpu.currentCycles;
                    if (this.redirectTo !== undefined) { cpu.pc = this.redirectTo; this.redirectTo = undefined; this.tabAt = -1; continue; }
                    return "blocked";
                }
            }
            const left = end - now;
            if (left <= 0) return "ok";
            cpu.execute(Math.max(16, Math.min(left, 20000)));
            if (cpu.halted && this.redirectTo !== undefined) { cpu.targetCycles = cpu.currentCycles; cpu.pc = this.redirectTo; this.redirectTo = undefined; this.tabAt = -1; continue; }
            if (cpu.halted && this.blocked) { cpu.targetCycles = cpu.currentCycles; return "blocked"; }
        }
    }
    // record each labelled routine entered, with A X Y, while from <= iteration <= to
    startTrace(from, to, out) {
        const cpu = this.cpu, byAddr = new Map();
        for (const [pn, l] of Object.entries(this.labs)) for (const [m, x] of Object.entries(l)) for (const [k, v] of x) { const key = `${pn}:${m}:${v}`; if (!byAddr.has(key)) byAddr.set(key, k); }
        this.traceHook = cpu.debugInstruction.add(pc => {
            if (this.iter < from || this.iter > to) return false;
            const m = pc < 0x8000 || pc >= 0xc000 ? "m" : (this._roleOf(cpu.romsel) || "m");
            const lab = byAddr.get(`${this.prog}:${m}:${pc}`);
            if (lab) out.push(`${this.iter} ${lab} pc=${pc.toString(16)} A=${cpu.a.toString(16)} X=${cpu.x.toString(16)} Y=${cpu.y.toString(16)} S=${cpu.s.toString(16)}`);
            return false;
        });
    }
    async screenshot() { return this.s.screenshotActive({ scale: 1 }); }
    renderAll() { this.s._video.frameSkipCount = 1; }
}

// ---- comparing two machines' game state

// mask over the snapshot's offsets: 1 = excluded (blib's exclusion lists, by the reference's symbols)
export function compareSetup(rb, regions, loose = true) {
    const rsy = rb.progs.flight.sy;
    const ex = excludeSet(rsy, loose ? [TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE] : [TIMING_EXCLUDE, RELOC_EXCLUDE]);
    const offAddr = [];
    for (const [a, n] of regions) for (let i = 0; i < n; i++) offAddr.push(a + i);
    const mask = new Uint8Array(offAddr.length);
    offAddr.forEach((a, o) => { if (ex.has(a)) mask[o] = 1; });
    const kOff = offAddr.indexOf(rsy["K%"]), fOff = offAddr.indexOf(rsy.FRIN);
    const all = { ...rb.loader, ...rb.progs.docked.sy, ...rsy };
    const byAddr = {};
    for (const [k, v] of Object.entries(all)) if (v < 0x1000 && !(v in byAddr) && !/^(CODE|LOAD)/.test(k)) byAddr[v] = k;
    for (const [k, v] of Object.entries(rb.loader)) if (v >= 0x1000 && v < 0x1200 && !(v in byAddr)) byAddr[v] = k;
    return { ex, offAddr, mask, kOff, fOff, byAddr, loose, rsy: all };
}

// The differing compared bytes of two snapshots: not the excluded ones, not the
// filing system's in either machine (fsA, fsB: offsets), and with loose, not an empty K%
// slot's (FRIN = 0 in the reference: the line heap grows into them, as bcompare)
export function diffSnaps(cs, a, b, fsA, fsB) {
    const out = [];
    const fs = fsA || fsB ? new Set([...(fsA || []), ...(fsB || [])]) : null;
    for (let o = 0; o < a.length; o++) {
        if (a[o] === b[o] || cs.mask[o]) continue;
        if (fs && fs.has(o)) continue;
        if (cs.loose && o >= cs.kOff && o < cs.kOff + NOSH * NI && a[cs.fOff + Math.floor((o - cs.kOff) / NI)] === 0) continue;
        out.push(o);
    }
    return out;
}

const INWK = ["x_lo", "x_hi", "x_sign", "y_lo", "y_hi", "y_sign", "z_lo", "z_hi", "z_sign",
    "nosev_x_lo", "nosev_x_hi", "nosev_y_lo", "nosev_y_hi", "nosev_z_lo", "nosev_z_hi",
    "roofv_x_lo", "roofv_x_hi", "roofv_y_lo", "roofv_y_hi", "roofv_z_lo", "roofv_z_hi",
    "sidev_x_lo", "sidev_x_hi", "sidev_y_lo", "sidev_y_hi", "sidev_z_lo", "sidev_z_hi",
    "speed", "acceleration", "roll_counter", "pitch_counter", "flags(exploding/killed/scanner/lasers)", "AI/aggression/ECM", "heap_lo", "heap_hi", "energy", "NEWB"];
export function fieldName(cs, a) {
    const k = cs.rsy["K%"];
    if (a >= k && a < k + NOSH * NI) return `K% slot ${Math.floor((a - k) / NI)} ${INWK[(a - k) % NI]}`;
    for (let b = a; b >= Math.max(0, a - 64); b--) if (cs.byAddr[b] !== undefined) return b === a ? cs.byAddr[b] : `${cs.byAddr[b]}+${a - b}`;
    return `&${a.toString(16)}`;
}
export function groupOf(cs, a) {
    const sy = cs.rsy, k = sy["K%"];
    if (a >= k && a < k + NOSH * NI) return "ship slots (K%)";
    if (a >= k + NOSH * NI && a < 0x0d00) return "ship line heap";
    if (a >= sy.FRIN && a < sy.FRIN + NOSH + 1) return "ship slots (FRIN)";
    if (a >= sy.NAME && a <= sy.SVC + 1) return "commander";
    if (a >= sy["NA%"] && a < 0x1200) return "saved commander (NA%)";
    if (a >= sy.COMC && a <= sy.CATF) return "configuration";
    if (a < 0x100) return "zero page";
    if (a >= sy.WP) return "WP (line buffer, heaps, stardust)";
    return "flight variables (UP)";
}
