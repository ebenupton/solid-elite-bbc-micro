// Play styles for the Model B's agentplay (the Master port's styles.mjs, for disc Elite):
// the commanders a session starts with (patched into both machines' NA%, the last saved
// commander, at the first QU5: DFAULT then copies it into the commander, and a death goes
// back to it too), elite-agent's own modes (environment for agentd), and the chaos
// overlay: extra keys and pokes, chosen from the reference's state with a seeded random
// number generator, that drive the game into what the agent rarely does on its own.
// Everything the overlay does goes through the same input log, so a session replays
// exactly.

// A commander patch: { symbol: bytes } written into the live commander and into NA% (the
// last saved copy: NA%+8 lines up with TP). The original checks NA%'s checksum in DFAULT
// and loops for ever if it is wrong, so the patch sets CHK as CHECK computes it, and CHK2
// to CHK EOR &A9 (or the game marks the commander as tampered with in COK)
export function patcher(fields) {
    return m => {
        const sy = m.sy, na = sy["NA%"];
        for (const [k, v] of Object.entries(fields)) {
            if (sy[k] === undefined) throw new Error(`commander patch: no symbol ${k}`);
            m.wr(sy[k], v);
            if (sy[k] >= sy.TP && sy[k] <= sy.SVC) m.wr(na + 8 + sy[k] - sy.TP, v);
        }
        // CHECK: X = NT% - 2 (SVC - TP), A = X, C = 0; A = A + NA%+7+X + C, A = A EOR NA%+8+X, for X down to 1
        let x = sy.SVC - sy.TP, a = x, c = 0;
        for (; x > 0; x--) { const t = a + m.rb(na + 7 + x) + c; a = t & 255; c = t > 255 ? 1 : 0; a ^= m.rb(na + 8 + x); }
        m.wr(sy.CHK, [a]); m.wr(sy.CHK2, [a ^ 0xa9]);
    };
}
export const cash = cr => { const t = Math.round(cr * 10); return [t >>> 24 & 255, t >>> 16 & 255, t >>> 8 & 255, t & 255]; };
// the galaxy seeds QQ21 of galaxy g (0-7): Lave's galaxy's, each byte rotated left g times
const twist = (b, n) => { for (let i = 0; i < n; i++) b = ((b << 1) | (b >> 7)) & 255; return b; };
const galaxy = g => ({ GCNT: [g], QQ21: [0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7].map(b => twist(b, g)) });
export const ALL = { ECM: [0xff], BST: [0xff], BOMB: [0x7f], ENGY: [1], DKCMP: [0xff], GHYP: [0xff], ESCP: [0xff], NOMSL: [4], CRGO: [37], QQ14: [70] };

export const COMMANDERS = {
    jameson: { what: "the default commander: 100 Cr, a pulse laser, 3 missiles" },
    trader: { what: "5000 Cr and a large cargo bay", patch: patcher({ CASH: cash(5000), CRGO: [37] }) },
    equipped: { what: "every piece of equipment, a beam laser, 4 missiles, 3000 Cr", patch: patcher({ ...ALL, LASER: [0x8f, 0, 0, 0], CASH: cash(3000) }) },
    rich: { what: "100000 Cr, nothing fitted", patch: patcher({ CASH: cash(100000) }) },
    // a tally of 5000 (Deadly): the Constrictor mission comes up at the first dock in galaxy 1
    deadly: { what: "Deadly (tally 5000), military laser, everything fitted, 20000 Cr", patch: patcher({ ...ALL, LASER: [0x97, 0x8f, 0, 0], CASH: cash(20000), TALLY: [5000 & 255, 5000 >> 8] }) },
    mission2: { what: "Constrictor mission done, tally 1400, all fitted: the Thargoid plans mission next (galaxy 3)", patch: patcher({ ...ALL, LASER: [0x97, 0, 0, 0], CASH: cash(20000), TALLY: [1400 & 255, 1400 >> 8], TP: [2] }) },
    // mission 1 done but not yet debriefed (TP bits 0-1 = 3): the next dock debriefs
    debrief1: { what: "the Constrictor destroyed, not yet debriefed (TP = 3): debriefing at the first dock", patch: patcher({ ...ALL, LASER: [0x97, 0, 0, 0], CASH: cash(5000), TALLY: [1000 & 255, 1000 >> 8], TP: [3] }) },
    // galaxy 3 at Ceerdi (215, 84) with mission 1 done and tally 1400: the Thargoid plans
    // briefing at the first dock, then Ceerdi (BRIEF3) and Birera (DEBRIEF2)
    galaxy3: { what: "galaxy 3 at Ceerdi, mission 1 done, tally 1400, all fitted: the Thargoid plans mission", patch: patcher({ ...ALL, ...galaxy(2), QQ0: [215], QQ1: [84], LASER: [0x97, 0x8f, 0, 0], CASH: cash(20000), TALLY: [1400 & 255, 1400 >> 8], TP: [2] }) },
    // galaxy 3 at Birera (63, 72) with the Thargoid plans aboard (TP = %1010): docking debriefs
    debrief2: { what: "galaxy 3 at Birera with the Thargoid plans (TP = 10): mission 2's debriefing at Birera", patch: patcher({ ...ALL, ...galaxy(2), QQ0: [63], QQ1: [72], LASER: [0x97, 0x8f, 0, 0], CASH: cash(20000), TALLY: [1500 & 255, 1500 >> 8], TP: [10] }) },
    // galaxy 2 at Orarra (144, 33) with the Constrictor mission under way (TP = 1): the
    // Constrictor is there at the launch (THERE), and its kill, then the debriefing
    orarra: { what: "galaxy 2 at Orarra with mission 1 under way (TP = 1), all fitted, military laser: the Constrictor", patch: patcher({ ...ALL, ...galaxy(1), QQ0: [144], QQ1: [33], LASER: [0x97, 0x8f, 0, 0], CASH: cash(20000), TALLY: [3000 & 255, 3000 >> 8], TP: [1] }) },
    wanted: { what: "a fugitive (legal status 80), 2000 Cr, ECM and pod", patch: patcher({ FIST: [80], CASH: cash(2000), ECM: [0xff], ESCP: [0xff] }) },
};

// elite-agent's modes, as agentd's environment (no keyboard or moon modes: the disc
// version's player always plays with the keys, and the disc version has no moons)
export const MODES = {
    efficient: {},
    curious: { CURIOUS: "1" },
    fair: { FAIR: "1" },
    nosave: { SAVE: "0" },
    nomission: { NOMISSION: "1" },
    load: { LOAD: "CLAUDE" },           // load commander CLAUDE from the disc when first docked (a disc from --savediscs)
};

// ---- the chaos overlay
// Keys (BBC internal numbers)
const K = { E: 0x22, TAB: 0x60, ESC: 0x70, F0: 0x20, F1: 0x71, F2: 0x72, F3: 0x73, F4: 0x14, F5: 0x74, T: 0x23, M: 0x65, U: 0x35, J: 0x45, H: 0x54, CTRL: 0x01, C: 0x52, SPACE: 0x62, SLASH: 0x68, X: 0x42, S: 0x51, COPY: 0x69, DEL: 0x59 };
// actions: when they may happen (the reference's RAM), the keys and for how many frames,
// and how often (mean frames between, while allowed)
const ACTIONS = {
    ecm:     { every: 1500, when: (r, sy) => flying(r, sy) && r[sy.ECM], keys: [[K.E, 4]] },
    bomb:    { every: 6000, when: (r, sy) => flying(r, sy) && r[sy.BOMB], keys: [[K.TAB, 3]] },
    pod:     { every: 20000, when: (r, sy) => flying(r, sy) && r[sy.ESCP], keys: [[K.ESC, 6]] },
    views:   { every: 1200, when: flying, keys: () => [[[K.F1, K.F2, K.F3][Math.floor(rng() * 3)], 3], [null, 120], [K.F0, 3]] },
    missile: { every: 2500, when: (r, sy) => flying(r, sy) && r[sy.NOMSL], keys: [[K.T, 3], [null, 25], [K.M, 3]] },
    unarm:   { every: 4000, when: (r, sy) => flying(r, sy) && r[sy.NOMSL], keys: [[K.T, 3], [null, 25], [K.U, 3]] },
    ghyp:    { every: 30000, when: (r, sy) => flying(r, sy) && r[sy.GHYP] && !r[sy.QQ22 + 1], keys: [[K.CTRL, 1], [[K.CTRL, K.H], 4], [K.CTRL, 2]] },
    hyper:   { every: 15000, when: (r, sy) => flying(r, sy) && !r[sy.QQ22 + 1], keys: [[K.H, 4]] },
    jump:    { every: 2000, when: flying, keys: [[K.J, 30]] },
    // a hyperspace jump with CTRL held as it ends: a mis-jump into witchspace (which the
    // disc version allows only with the author names configured, PATG: X in the pause)
    misjump: { every: 15000, when: (r, sy) => flying(r, sy) && !r[sy.QQ22 + 1] && !r[sy.MJ],
        keys: (r, sy) => [...(r[sy.PATG] ? [] : [[K.COPY, 3], [null, 30], [K.X, 3], [null, 10], [K.DEL, 3], [null, 20]]), [K.H, 4], [K.CTRL, 1000]] },
    dock:    { every: 8000, when: (r, sy) => flying(r, sy) && r[sy.DKCMP], keys: [[K.C, 3]] },
    charts:  { every: 3000, when: flying, keys: () => [[[K.F4, K.F5][Math.floor(rng() * 2)], 3], [null, 100], [K.F0, 3]] },
    spin:    { every: 2500, when: flying, keys: () => [[[[0x66, K.X], [0x67, K.S], [0x66, K.S]][Math.floor(rng() * 3)], 40]] },
    // the pause (COPY), with a configuration toggle in it sometimes (author names, X, or flashing bars, F: not CAPS LOCK, A, Y, J or K, which would change how the agent flies, or S, the sound), then DELETE to go on
    pause:   { every: 9000, when: flying, keys: () => [[K.COPY, 3], [null, 30], ...(rng() < 0.5 ? [[pick([0x42, 0x43]), 3], [null, 10]] : []), [K.DEL, 3]] },
};
// pokes (both machines, at an iteration boundary, three iterations after the reference's
// state chose them): drained shields and energy (a fight then kills us), cabin heat near
// the limit, an empty tank
const POKES = {
    hurt: { every: 15000, when: flying, poke: () => [["FSH", 0, [0]], ["ASH", 0, [0]], ["ENERGY", 0, [12]]] },
    heat: { every: 20000, when: flying, poke: () => [["CABTMP", 0, [230]]] },
    fuel: { every: 20000, when: flying, poke: () => [["QQ14", 0, [3]]] },
    // a galactic hyperdrive again, so that a session can cross several galaxies
    ghypfill: { every: 12000, when: (r, sy) => flying(r, sy) && !r[sy.GHYP], poke: () => [["GHYP", 0, [0xff]]] },
    // a cargo canister in the bubble put just ahead and below, slow: scooped (with the scoops)
    scoop:   { every: 2500, when: (r, sy) => flying(r, sy) && r[sy.BST] && canister(r, sy) >= 0,
        poke: (r, sy) => [["K%", 37 * canister(r, sy), [0, 0, 0, 0x30, 0, 0x80, 0x80, 0, 0]], ["K%", 37 * canister(r, sy) + 27, [1]]] },
    // the sun (slot 1, when it is the sun) put ahead, its centre 84 to 125 x 256 away: the
    // cabin heats up (CABTMP is 30 plus 255 less the high byte of the distance's square),
    // fuel scooping from 224 (with the scoops: nearer than about 125 x 256), and death by
    // the heat when that overflows (nearer than about 86 x 256)
    sun:     { every: 9000, when: (r, sy) => flying(r, sy) && r[sy.FRIN + 1] === 129, poke: () => [["K%", 37, [0, Math.floor(rng() * 20), Math.floor(rng() * 2) << 7, 0, Math.floor(rng() * 20), Math.floor(rng() * 2) << 7, 0, 84 + Math.floor(rng() * 42), 0]]] },
};
// the disc menu (disc Elite's: 1 load, 2 save, 3 catalogue, 4 delete, anything else
// exits), while docked on the Status screen (up to three such actions a dock, and the
// agent's keys are held back while it runs). Steps: [keys, frames], or { until(r, sy),
// keys, max } (hold keys until the condition, at most max frames), or { pulse, until, max }
// (tap a key every 12 frames until the condition)
const D = { 0: 0x27, 1: 0x30, 2: 0x31, 3: 0x11, 4: 0x12, 5: 0x13, 6: 0x34, 7: 0x24, 8: 0x15, 9: 0x26, RET: 0x49, Y: 0x44, N: 0x55, AT: 0x47 };
const LETTER = { A: 0x41, B: 0x64, C: 0x52, D: 0x32, E: 0x22, F: 0x43, G: 0x53, H: 0x54, I: 0x25, J: 0x45, K: 0x46, L: 0x56, M: 0x65, N: 0x55, O: 0x36, P: 0x37, Q: 0x10, R: 0x33, S: 0x51, T: 0x23, U: 0x35, V: 0x63, W: 0x21, X: 0x42, Y: 0x44, Z: 0x61 };
const press = k => [[k, 3], [null, 5]];
// ("~" is DELETE)
const typed = t => [...t].flatMap(ch => press(LETTER[ch] ?? D[ch] ?? { "~": 0x59 }[ch]));
const fumble = t => rng() < 0.4 ? t.slice(0, -1) + "QZ~~" + t.slice(-1) : t;        // (sometimes a slip, deleted)
const inMenu = (r, sy) => r[sy.QQ11] === 1;
const atStatus = (r, sy) => r[sy.QQ12] && r[sy.QQ11] === 8;
const menu = () => [{ until: inMenu, keys: [D.AT], max: 150 }, [null, 20]];
// (5 leaves the menu; RETURN ends a name, or leaves the menu too)
const leave = () => [[null, 20], { pulse: [D[5], D.RET], until: atStatus, max: 1500 }];
const drive = k => [...press(k), [null, 10]];
let saveNo = 0;
const DISC = {
    dcat:   () => [...menu(), ...press(D[3]), ...drive(D[0]), [null, 250], ...press(0x62), ...leave()],
    // (drive 1 is empty: DFS waits for the drive for ever, in the original too, so the
    // session ends there with hang-both. Not in "disc")
    dcat1:  () => [...menu(), ...press(D[3]), ...drive(D[1]), [null, 400], ...press(0x62), ...leave()],
    dbad:   () => [...menu(), ...press(D[rng() < 0.5 ? 3 : 4]), ...drive(D[rng() < 0.5 ? 7 : 9]), [null, 30], ...leave()],
    dnoload: () => [...menu(), ...press(D[1]), [null, 12], ...typed(fumble("NOFILE")), ...press(D.RET), [null, 200], ...leave()],
    dnodel: () => [...menu(), ...press(D[4]), ...drive(D[0]), [null, 250], ...typed("NOFILE"), ...press(D.RET), [null, 200], ...leave()],
    dsave:  () => { const n = "CH" + (saveNo++ % 40); return [...menu(), ...press(D[2]), [null, 12], ...typed(fumble(n)), ...press(D.RET), [null, 250], ...leave()]; },
    ddel:   () => { const n = "CH" + Math.floor(rng() * Math.max(1, saveNo)); return [...menu(), ...press(D[4]), ...drive(D[0]), [null, 250], ...typed(n), ...press(D.RET), [null, 200], ...leave()]; },
    // a name typed and over-deleted (DELETE with nothing left)
    dname:  () => [...menu(), ...press(D[rng() < 0.5 ? 1 : 2]), [null, 12], ...typed(rng() < 0.5 ? "AB~~~~C" : "XY~~~~"), ...press(D.RET), [null, 200], ...leave()],
    dexit:  () => [...menu(), ...press(D[rng() < 0.5 ? 5 : 8]), ...leave()],
};
for (const [nm, f] of Object.entries(DISC)) ACTIONS[nm] = { every: 150, disc: true, exclusive: true, when: atStatus, keys: f };
// the docked screens the agent never visits or never gets wrong (as the disc menu: from the
// Status screen, up to three a dock, the agent held back): the market (f7), the system
// data (f6), the inventory (f9), the charts with the cursor moved (with SHIFT, sometimes),
// a search by name (F) and hyperspace asked for (not allowed while docked), equipment that
// is fitted already or can't be afforded, a sale
const F = { f2: 0x72, f3: 0x73, f4: 0x14, f5: 0x74, f6: 0x75, f7: 0x16, f8: 0x76, f9: 0x77, L: 0x19, R: 0x79, U: 0x39, Dn: 0x29, H: 0x54, F: 0x43, D: 0x32 };
const toStatus = () => [[null, 20], { pulse: [F.f8, D.RET, F.f8, D[0]], until: atStatus, max: 900 }];
const pick = a => a[Math.floor(rng() * a.length)];
const DOCKED = {
    dmarket: () => [...press(F.f7), [null, 80], ...press(F.f6), [null, 80], ...press(F.f9), [null, 60], ...toStatus()],
    dchart:  () => [...press(pick([F.f4, F.f5])), [null, 60], [[pick([F.L, F.R]), pick([F.U, F.Dn]), ...(rng() < 0.5 ? [0x00] : [])], 20 + Math.floor(rng() * 80)], [null, 20], ...press(pick([F.H, F.D])), [null, 80], ...toStatus()],
    dfind:   () => [...press(F.f4), [null, 60], ...press(F.F), [null, 12], ...typed(pick(["LAVE", "DISO", "ZAONCE", "RIEDQUAT", "QQQ", "LEESTI"])), ...press(D.RET), [null, 80], ...toStatus()],
    dequip:  () => [...press(F.f3), [null, 150], ...typed(String(1 + Math.floor(rng() * 6))), ...press(D.RET), [null, 60], ...press(D.RET), [null, 20], ...toStatus()],
    dsell:   () => [...press(F.f2), [null, 40], ...[0, 1, 2].flatMap(() => [...press(pick([D.Y, D.N, D[1], D.RET])), [null, 10]]), [null, 20], ...toStatus()],
};
for (const [nm, f] of Object.entries(DOCKED)) ACTIONS[nm] = { every: 150, disc: true, exclusive: true, when: atStatus, keys: f };

function canister(r, sy) { for (let i = 2; i < 12; i++) if (r[sy.FRIN + i] === 5) return i; return -1; }
function flying(r, sy) { return !r[sy.QQ12] && !r[sy.QQ11] && r[sy.MCNT] !== 0xff; }

let rng = Math.random;
function mulberry(a) { return () => { a |= 0; a = a + 0x6d2b79f5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

// spec: "all" or a comma list of action and poke names, with an optional *factor on the
// rate ("ecm,bomb*2"); "disc" and "docked" are the disc menu's and the docked screens' sets
export function makeChaos(spec, seed) {
    const r = mulberry(seed * 7919 + 17);
    const names = spec === "all" ? [...Object.keys(ACTIONS).filter(n => !ACTIONS[n].disc), ...Object.keys(POKES)]
        : spec.split(",").flatMap(n => {
            // (a set's name takes a factor too: "disc*2" is each of its actions at twice the rate)
            const [set, f] = n.split("*"), x = f ? "*" + f : "";
            return set === "disc" ? Object.keys(DISC).filter(k => k !== "dcat1").map(k => k + x) : set === "docked" ? Object.keys(DOCKED).map(k => k + x)
                : set === "all" ? [...Object.keys(ACTIONS).filter(k => !ACTIONS[k].disc), ...Object.keys(POKES)].map(k => k + x) : [n];
        });
    const acts = names.map(n => { const [nm, f] = n.split("*"); const a = ACTIONS[nm] || POKES[nm]; if (!a) throw new Error(`unknown chaos ${nm}`); return { nm, a, rate: (+f || 1) / a.every }; });
    let seq = null, seqLeft = 0, cur = [], step = null, excl = false, discDone = 0;
    const done = {};
    const next = () => {
        if (!seq.length) { seq = null; cur = []; step = null; excl = false; return; }
        const e = seq.shift();
        if (Array.isArray(e)) { const [k, n] = e; cur = k === null ? [] : Array.isArray(k) ? k : [k]; seqLeft = n; step = null; }
        else { step = e; seqLeft = e.max; cur = e.keys || []; }
    };
    return {
        counts: done,
        exclusive() { return excl; },
        // once a frame (after the agent): maybe start an action
        frame(S) {
            rng = r;
            const ram = S.ref.ram, sy = S.rsy;
            if (flying(ram, sy)) discDone = 0;
            if (seq) {
                if (step) {
                    if (step.until(ram, sy) || --seqLeft <= 0) { next(); return; }
                    if (step.pulse !== undefined) { const t = step.max - seqLeft, p = step.pulse; cur = t % 12 < 3 ? [Array.isArray(p) ? p[Math.floor(t / 12) % p.length] : p] : []; }
                    return;
                }
                if (--seqLeft > 0) return;
                next();
                return;
            }
            for (const { nm, a, rate } of acts) {
                if (a.disc && discDone >= 3) continue;
                if (r() >= rate || !a.when(ram, sy)) continue;
                if (a.disc) discDone++;
                excl = !!a.exclusive;
                done[nm] = (done[nm] || 0) + 1;
                S.logInput({ chaos: nm, frame: S.frame, i: S.ref.iter });
                if (a.poke) {
                    const at = S.ref.iter + 3;
                    const pk = a.poke(ram, sy);
                    for (const m of [S.ref, S.cand]) { (m.pokes ||= new Map()).set(at, pk); }
                    S.logInput({ poke: at, v: pk });
                    return;
                }
                seq = (typeof a.keys === "function" ? a.keys(ram, sy) : a.keys).map(x => Array.isArray(x) ? [...x] : { ...x });
                next();
                return;
            }
        },
        keys() { return cur; },
    };
}
