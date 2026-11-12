// Deterministic driver for BBC Micro disc Elite on an emulated BBC Model B
// with sideways RAM (jsbeeb "B-DFS1.2": DFS 1.2, sideways RAM in slots 0-7).
//
// Shared by 6-harness/bcompare.mjs and the pilot (6-harness/bpilot.mjs). It is
// the Model B counterpart of the Master port's mlib.mjs, and works the same
// way; the differences come from the disc version itself.
//
// Two programs
// ------------
// Disc Elite is two programs, the flight code (D.CODE) and the docked code
// (T.CODE), and only one is in memory at a time: the flight code loads the
// docked code when we dock or die, and the docked code loads the flight code
// when we launch. Each has its own symbols. A build is described by a JSON
// file (build.json: see loadBuild) that names each program's symbol table
// and the images its code is in (a file, where it is mapped, and the address
// of its first byte). A hook is a label of one program (plus an offset); it
// fires when the PC reaches the label's address, in the label's mapping
// (main RAM, or the sideways RAM bank that holds its image), and the three
// bytes there are the image's: so a hook of the docked program never fires
// in the flight program, even where their addresses coincide (both start at
// &11E3 in the original, and the port swaps both into the same bank).
//
// Input injection
// ---------------
// The disc version reads the keyboard in one place only: DKS4 tests one key
// by writing its internal number to the System VIA and reading back bit 7
// (pressed). DKS1 (the primary flight keys), RDKEY (a scan of keys 16-127,
// returning the first one pressed) and CTRL (key 1) all call DKS4 (the port's
// RDKEY scans a column at a time instead, so RDKEY's result is also set at
// Rd2, its end, in both runs: the lowest of the pilot's keys from 16 on). MT26 reads
// a commander name with OSWORD 0 (the pilot never goes there; the run stops
// with an error if it does). The hardware keyboard is never pressed after
// boot, and keys are injected at DKS4+17 (the LDA #%00001011 after the LDX
// VIA+&4F that reads the key): X is set to the key number, with bit 7 set if
// the key is in the set of keys that are down. That set is asked of the
// pilot:
//  * at DOKEY, once per main-loop iteration (site "DOKEY"); the set holds for
//    the iteration's other reads (DK4's RDKEY and its pause loop);
//  * at RDKEY, when RDKEY is called from anywhere but DOKEY's DK4 and FREEZE
//    (key waits: TT217's t and t2, with the routine that called TT217; the
//    title screens' TITLE loop; PAUSE2), with the call site;
//  * for CTRL (key 1), whose callers are the hyperspace routines, the pilot's
//    dks() answers.
// So both runs see the same keys at the same main-loop iteration, the same
// nth poll of a title loop and the same nth key wait, whatever the timing.
//
// Timing-dependent state
// ----------------------
//  * LASCT, the laser pulse counter, is counted down by the interrupt handler
//    (IRQ1, at each vsync) in the disc version, so how many frames pass per
//    iteration would leak into the game. The harness takes that count away
//    and puts one in a fixed place: the interrupt's DEC LASCT is undone (the
//    value is put back at the next instruction), and at each entry to M%,
//    the main flight loop, LASCT is decremented if it is non-zero. Both runs
//    see the same LASCT at the same iteration. (A pulse laser then pulses per
//    iteration rather than per frame, and the death animation, which waits
//    for LASCT to count down from 255, lasts 255 passes of M%.)
//  * DL, the vsync flag, is real time and is left out of the comparison.
//  * Sound: NOISE makes its sounds with OSWORD 7, whose time and returned
//    flags depend on the MOS's sound queue, which empties in real time. The
//    harness turns the sound off (DNOIZ = &FF) in both runs when the game
//    starts, so NOISE returns at once, and no sound reaches the MOS.
//  * Disc loads: the docked and flight programs, the ship blueprints and the
//    commander files are loaded by the filing system, which writes its own
//    scratch bytes into zero page, and CATD reads the disc catalogue over WP
//    (&0E00-&0FFF), relying on WP being dead then. A build with another disc
//    (another catalogue, other file sizes) leaves other bytes there. So a byte
//    of the compared state that the MOS, a ROM (DFS) or the NMI handler (page
//    &0D) writes is "filing system" until game code writes it again, and is
//    left out of the comparison meanwhile, in both runs. The original does
//    read some of them before writing them: the stardust's fractional parts
//    (SXL, SYL, SZL in WP) are never set when new stardust is made, so they
//    keep whatever the disc catalogue left there. So at each MLOOP and each
//    pass of M%, any filing-system byte above page 0 that the game has still
//    not written is set to 0, in both runs, and is game state from then on.
import { MachineSession } from "./jsbeeb.mjs";
import { readFileSync, existsSync } from "fs";
import { dirname, resolve } from "path";
import { createHash } from "crypto";

export const ROOT = decodeURIComponent(new URL("..", import.meta.url).pathname);
// The build that the tools look at by default (the Makefile's outputs), the
// released disc that it is compared with (with the symbols of the original
// source's build, which is byte for byte the released game), and the
// harness's working directory (logs, screenshots, the reference run's cache)
export const CAND_BUILD = `${ROOT}3-assembled-output/build.json`;
export const REF_BUILD = `${ROOT}4-reference-binaries/sth/build.json`;
export const WORK = `${ROOT}6-harness/work/`;

export function loadSyms(path) {
    const syms = {};
    for (const m of readFileSync(path, "utf8").matchAll(/'([^']+)':(\d+)L?/g)) if (!(m[1] in syms)) syms[m[1]] = +m[2];
    return syms;
}

// A build: { file, disc, progs: { flight, docked }, loader }, where each
// program is { name, sy (symbols), images: [{ data, map, base }] } and map is
// "m" (main RAM) or a sideways RAM bank's role, whose bank number the
// build's resident code keeps at the symbol named in banks (loader symbols).
export function loadBuild(file) {
    const d = JSON.parse(readFileSync(file, "utf8"));
    const p = f => resolve(dirname(file), f);
    // (o.banks: the build's file of each label's bank role, "label H" or
    // "label C", for labels in sideways RAM; without it, every label is in
    // its image's mapping by address, as in the original)
    const prog = (name, o) => {
        const sy = loadSyms(p(o.syms)), bank = {};
        if (o.banks) for (const l of readFileSync(p(o.banks), "utf8").split("\n")) { const [n, r] = l.trim().split(/\s+/); if (n && r) bank[n] = r; }
        return {
            name, sy, bank,
            images: o.images.map(([f, map, base]) => ({ data: readFileSync(p(f)), map, base: parseInt(base, 16) })),
        };
    };
    return {
        file, disc: p(d.disc), progs: { flight: prog("flight", d.flight), docked: prog("docked", d.docked) },
        loader: loadSyms(p(d.loader)), banks: d.banks || {}, patches: d.patches || [],
    };
}

// Patches to a build's behaviour, named in its build.json ("patches"), which
// runElite applies as hooks (a patch may give several): the gate's reference
// (the original disc) has three, where the port defines a value that the
// original leaves to what was drawn (ma93-q, ee51-c) or changes the game on
// purpose (mv8-half).
//
//  * "ma93-q": in the main flight loop's altitude check (MA93: STA R, JSR
//    LL5), the original takes SQRT(R Q) with Q left over from whatever ran
//    last, usually LOIN's division: so the altitude depends on what was
//    drawn. The port sets Q = 0 there (LDA #0, STA Q before the JSR), so
//    that its record mode need not work out the original's lines; the
//    reference gets the same: at the JSR LL5, Q = 0. The JSR is found from
//    MA93 by its bytes (STA R, JSR LL5: &85 R &20 LL5), which must be there
//    once, or the run fails; LL5 reads R and Q first, and no register, so
//    setting Q in memory at the JSR is the port's two instructions.
//  * "mv8-half": the planet's half spin. The port turns the planet by its
//    own pitch and roll (MVEIT part 8) by half the original's angle on
//    every iteration: for TYPE 128 or more, MVS5 takes 1/32 radian a step
//    in place of 1/16 (x' = x (1 - 1/2048) + d y / 32, y' = y (1 - 1/2048)
//    - d x / 32). The original gets the same: at part 8's first
//    instruction (LDA INWK+30, AND #&80, STA RAT2: &A5 INWK+30 &29 &80 &85
//    RAT2, found back from MV8, which must be there once, or the run
//    fails), for TYPE 128 or more, the half steps are worked out from its
//    vectors as the port works them out (halfPart8, below), and at MV5,
//    once its own part 8 has run (the counters damped, RAT2 and Q left as
//    the port leaves them), they are put in place of its vectors.
//  * "ee51-c": when LL9 starts a killed ship's explosion, its first random
//    number (EE55's first DORND) takes C from EE51, which removes the ship
//    from the screen: LL155 leaves C set after drawing a heap of lines but
//    clear after a heap of none, and EE51 leaves it as it was when the ship
//    was not on the screen. The port draws no heap, so it sets C = 1 there
//    (SEC after the JSR EE51); the reference gets the same: at the
//    instruction after that JSR (JSR EE51, LDY #1, LDA #18, STA (XX19),Y,
//    found from LL9, which must be there once, or the run fails), C = 1.
export const PATCHES = {
    "ma93-q": (prog) => {
        const sy = prog.sy, img = prog.images.find(im => sy.MA93 >= im.base && sy.MA93 < im.base + im.data.length);
        const want = [0x85, sy.R, 0x20, sy.LL5 & 255, sy.LL5 >> 8];
        const at = [];
        for (let a = sy.MA93; a < sy.MA93 + 96; a++) if (want.every((v, i) => img.data[a + i - img.base] === v)) at.push(a);
        if (at.length !== 1) throw new Error(`patch ma93-q: STA R, JSR LL5 found ${at.length} times after MA93`);
        const a = at[0] + 2;
        return { a, map: img.map, sig: [0x20, sy.LL5 & 255, sy.LL5 >> 8], apply: cpu => { cpu.ramRomOs[sy.Q] = 0; } };
    },
    "ee51-c": (prog) => {
        const sy = prog.sy, img = prog.images.find(im => sy.LL9 >= im.base && sy.LL9 < im.base + im.data.length);
        const want = [0x20, sy.EE51 & 255, sy.EE51 >> 8, 0xa0, 0x01, 0xa9, 0x12, 0x91, sy.XX19];
        const at = [];
        for (let a = sy.LL9; a < sy.LL9 + 160; a++) if (want.every((v, i) => img.data[a + i - img.base] === v)) at.push(a);
        if (at.length !== 1) throw new Error(`patch ee51-c: JSR EE51, LDY #1 found ${at.length} times after LL9`);
        const a = at[0] + 3;
        return { a, map: img.map, sig: [0xa0, 0x01, 0xa9], apply: cpu => { cpu.p.c = true; } };
    },
    "mv8-half": (prog) => {
        const sy = prog.sy, img = prog.images.find(im => sy.MV8 >= im.base && sy.MV8 < im.base + im.data.length);
        const want = [0xa5, sy.INWK + 30, 0x29, 0x80, 0x85, sy.RAT2];
        const at = [];
        for (let a = sy.MV8 - 6; a > sy.MV8 - 64; a--) if (want.every((v, i) => img.data[a + i - img.base] === v)) at.push(a);
        if (at.length !== 1) throw new Error(`patch mv8-half: MVEIT part 8 found ${at.length} times before MV8`);
        const sig = a => [0, 1, 2].map(i => img.data[a + i - img.base]);
        let vec = null;
        return [
            { a: at[0], map: img.map, sig: want.slice(0, 3), apply: cpu => {
                const m = cpu.ramRomOs;
                if (m[sy.TYPE] & 0x80) vec = halfPart8(i => m[sy.INWK + i]);
            } },
            { a: sy.MV5, map: img.map, sig: sig(sy.MV5), apply: cpu => {
                if (vec) { for (let i = 0; i < 18; i++) cpu.ramRomOs[sy.INWK + 9 + i] = vec[i]; vec = null; }
            } },
        ];
    },
};

// The planet's half spin, as the port works it out (MVS5 for TYPE 128 or
// more), for the reference's patch mv8-half: MVEIT part 8 by half the
// original's angle, from INWK (inwk(i) = INWK+i, read before part 8 runs).
// For each of the pitch counter (INWK+30: roofv with nosev) and the roll
// counter (INWK+29: roofv with sidev) that is not 0 (bits 0-6), each pair of
// coordinates (x, y), in the direction d (the counter's sign), becomes
//   x' = x (1 - 1/2048) + d y / 32,  y' = y (1 - 1/2048) - d x / 32
// in sign-magnitude, exactly as the port's MVS5 for the planet: x less its
// high byte's magnitude over 8, y's magnitude shifted right five times, the
// two added as the original's ADD (and MU8) adds them. Returns INWK+9 to
// INWK+26 (nosev, roofv, sidev) after the turn. (The BBC Master port's
// harness has the same model, mlib.mjs's halfPart8.)
export function halfPart8(inwk) {
    const v = Array.from({ length: 18 }, (_, i) => inwk(9 + i));
    const lo = o => v[o - 9], hi = o => v[o - 8];
    // ADD: (A X) = (A P) + (S R), sign-magnitude, as the original's ADD and MU8
    const add = (A, P, S, R) => {
        const T = A & 0x80;
        if (!((T ^ S) & 0x80)) {
            const sum = R + P;
            return [((S + A + (sum >> 8)) & 0xff) | T, sum & 0xff];
        }
        const m1 = (A & 0x7f) << 8 | P, m2 = (S & 0x7f) << 8 | R;
        if (m1 >= m2) { const d = m1 - m2; return [(d >> 8) | T, d & 0xff]; }
        const d = m2 - m1; return [(d >> 8) | (T ^ 0x80), d & 0xff];
    };
    // (A X) = INWK(x) (1 - 1/2048) + INWK(y) / 32 with its sign EOR dir
    const mvh = (x, y, dir) => {
        const t = (hi(x) & 0x7f) >> 3, r = lo(x) - t;
        const R = r & 0xff, S = (hi(x) - (r < 0 ? 1 : 0)) & 0xff;
        const m = ((hi(y) & 0x7f) << 8 | lo(y)) >> 5;
        return add((m >> 8) | ((hi(y) & 0x80) ^ dir), m & 0xff, S, R);
    };
    const put = (o, [h, l]) => { v[o - 9] = l; v[o - 8] = h; };
    for (const [c, y0] of [[30, 9], [29, 21]]) {
        const cnt = inwk(c);
        if (!(cnt & 0x7f)) continue;
        const d = cnt & 0x80;
        for (let k = 0; k < 6; k += 2) {
            const x = 15 + k, y = y0 + k;
            const nx = mvh(x, y, d), ny = mvh(y, x, d ^ 0x80);
            put(y, ny); put(x, nx);
        }
    }
    return v;
}

// Game state compared per iteration: [start, length, name]. The workspaces
// are at the same addresses in both programs (and the regions are found by
// the flight program's symbols, wherever a build puts them).
export function regionsFor(b) {
    const sy = b.progs.flight.sy, ld = b.loader;
    const naEnd = ld["NAEND%"] !== undefined ? ld["NAEND%"] : ld.CHK + 1;
    return [
        [0x0000, sy.K4 + 2, "ZP"],                       // zero page game variables (&00-&E1)
        [sy.UP, sy.CATF + 1 - sy.UP, "UP"],              // key logger, flight variables, commander (NAME..SVC), configuration
        [sy["K%"], 0x0d00 - sy["K%"], "K%"],             // ship data blocks and the ship line heap (down from LS% = &0CFF)
        [sy.WP, sy.CPIR + 1 - sy.WP, "WP"],              // line buffer, ball and sun line heaps, stardust
        [ld["NA%"], naEnd - ld["NA%"], "NA%"],           // the last saved commander and its checksums
    ];
}

// Addresses excluded from the comparison, by flight symbol: name -> [length, reason]
export const TIMING_EXCLUDE = {
    DL: [1, "the vsync flag, set by the interrupt handler and polled by WSCAN: real time"],
};
// Temporaries that hold addresses of code or data that a relocated build moves
// (they differ between builds without any difference in game state, and the
// game writes them before it reads them)
export const RELOC_EXCLUDE = {
    V: [2, "temporary; the token printers leave V(1 0) pointing into the token tables"],
    "P+1": [2, "temporary; BULB leaves P(2 1) pointing at a bulb's character data (SPBT, ECBT)"],
    "&A8": [1, "the port's drawing colour (LCOL, elite-map.asm), in the MOS's OSCLI workspace"],
};
// Drawing temporaries and heaps: excluded with --loose (for builds whose drawing
// differs; the pilot and the game logic never read them across iterations)
export const DRAW_EXCLUDE = {
    SC: [2, "screen address"], T1: [1, "temp"], P: [3, "temp"], Q: [1, "temp"], R: [1, "temp"], S: [1, "temp"],
    T: [1, "temp"], U: [1, "temp"], XX15: [6, "line ends"], XX12: [6, "temp"], K: [4, "temp"], K2: [4, "temp"],
    K3: [14, "temp"], K4: [2, "temp"], K5: [4, "temp"], K6: [5, "temp"], XX16: [18, "temp"], XX0: [2, "blueprint ptr"],
    XX: [2, "temp"], YY: [2, "temp"], XSAV: [1, "temp"], YSAV: [1, "temp"], XX17: [1, "temp"], XX13: [1, "temp"],
    CNT: [1, "temp"], CNT2: [1, "temp"], STP: [1, "temp"], XX4: [1, "temp"], XX20: [1, "temp"], ZZ: [1, "temp"],
    V: [2, "temp"], LSP: [1, "ball heap ptr"], XX14: [1, "temp"], SWAP: [1, "temp"], COL: [1, "colour"],
    XC: [1, "text cursor"], YC: [1, "text cursor"], LSX2: [78, "planet line heap"], LSY2: [78, "planet line heap"],
    LSO: [192, "sun line heap and line buffer"], XSAV2: [1, "temp"], YSAV2: [1, "temp"],
    COMX: [1, "compass dot"], COMY: [1, "compass dot"], XX18: [4, "temp"], XX19: [2, "temp"],
};

export function excludeSet(sy, lists) {
    const ex = new Map();
    for (const list of lists) for (const [n, [len0, why]] of Object.entries(list)) {
        const len = typeof len0 === "function" ? len0(sy) : len0;
        if (n.startsWith("&")) {                   // ("&hex": an address)
            for (let i = 0; i < len; i++) ex.set(parseInt(n.slice(1), 16) + i, `${n}: ${why}`);
            continue;
        }
        const [base, off] = n.split("+");          // ("name+offset")
        if (sy[base] === undefined) continue;
        for (let i = 0; i < len; i++) ex.set(sy[base] + (+off || 0) + i, `${n}: ${why}`);
    }
    // with the drawing exclusions, also the ship line heap (the K% blocks
    // end at K% + NOSH * NI%; the heap grows down from &0CFF)
    if (lists.includes(DRAW_EXCLUDE)) for (let a = sy["K%"] + 12 * 37; a < 0x0d00; a++) ex.set(a, "ship line heap");
    return ex;
}

// Pointers in the compared state to data that a relocated build moves, put
// back to the original's addresses in each snapshot (the reference's are
// unchanged), so builds that move the data compare equal:
//  * the space station's ship line heap is LSO, in WP (NWSPS sets bytes
//    #33-#34 of its ship data block to LSO's address);
//  * XX0 points at the current ship's blueprint, and INF at the current ship's
//    data block; a build that moves the blueprints (XX21) has its XX0 moved
//    back by the difference.
const LSO_ORIG = 0x0e00, XX21_ORIG = 0x5600, BP_END_ORIG = 0x6000;
export function canonFor(b, regions) {
    const sy = b.progs.flight.sy;
    const offOf = a => { let o = 0; for (const [s, n] of regions) { if (a >= s && a + 1 < s + n) return o + a - s; o += n; } return -1; };
    const offs = [sy.INWK + 33, ...Array.from({ length: 12 }, (_, i) => sy["K%"] + 37 * i + 33)].map(offOf).filter(o => o >= 0);
    const xx0 = offOf(sy.XX0);
    // (the flight code's XX21 is a constant, which BeebAsm does not list
    // with the symbols; the docked code's is a label at the same place)
    const xx21 = sy.XX21 ?? b.progs.docked.sy.XX21;
    const bpLo = xx21, bpHi = xx21 + (BP_END_ORIG - XX21_ORIG);
    return buf => {
        if (sy.LSO !== LSO_ORIG) for (const o of offs) if ((buf[o] | buf[o + 1] << 8) === sy.LSO) { buf[o] = LSO_ORIG & 255; buf[o + 1] = LSO_ORIG >> 8; }
        if (xx21 !== XX21_ORIG && xx0 >= 0) {
            const v = buf[xx0] | buf[xx0 + 1] << 8;
            if (v >= bpLo && v < bpHi) { const w = v - xx21 + XX21_ORIG; buf[xx0] = w & 255; buf[xx0 + 1] = w >> 8; }
        }
        return buf;
    };
}

// Machine set-up: boot the Model B, insert the disc, SHIFT+BREAK
// (pre: run that many cycles more before the SHIFT+BREAK, so that the game
// starts at another phase of the field: BOOTPRE in the environment sets it
// for every tool)
export async function bootModelB(disc, pre = +(process.env.BOOTPRE || 0)) {
    const s = new MachineSession("B-DFS1.2");
    await s.initialise();
    await s.boot(30);
    s.loadDisc(disc);
    if (pre) await s.runFor(pre);
    // (SHIFT: jsbeeb 1 names keys by key code, jsbeeb 2 by KeyboardEvent.code)
    let shift = 16;
    try { s.keyDown(shift); } catch { shift = "ShiftLeft"; s.keyDown(shift); }
    s.reset(true); await s.runFor(2000000); s.keyUp(shift);
    return s;
}

// Read a byte of a given mapping regardless of what is paged ("m": main RAM
// and the MOS; a number: that sideways RAM bank)
export function physRead(cpu, map, addr) {
    if (map === "m" || addr < 0x8000 || addr >= 0xc000) return cpu.ramRomOs[addr & 0xffff];
    return cpu.ramRomOs[cpu.romOffset + map * 16384 + addr - 0x8000];
}

// Hooks into a build's programs, for runElite and the other tools:
// hookOf(prog, name, off) is a program's label (+ offset), its mapping, and
// the three bytes its image has there; live(h) says whether the PC at h.a is
// that hook now (the label's bank is paged in, and its bytes are in memory).
// hookLd(name, off, bytes) is a label of the loader's resident code (main
// RAM), with the bytes it must hold.
export function progHooks(b, cpu) {
    const rb = a => cpu.ramRomOs[a & 0xffff];
    // the bank number of a mapping role (read from the build's resident table)
    const bankOf = map => {
        if (map === "m") return "m";
        const v = b.banks[map];
        if (v === undefined) throw new Error(`no bank for ${map}`);
        return typeof v === "number" ? v : rb(b.loader[v]);
    };
    const sig = (img, a) => [0, 1, 2].map(i => img.data[a + i - img.base]);
    // (a routine that lives in the cold bank is hooked at its body, name_C:
    // the home bank reaches it through a stub of the old name; one in the
    // program's main RAM part is in its "m" image whatever its role)
    const hookOf = (prog, name, off = 0) => {
        if (typeof prog === "string") prog = b.progs[prog];
        if (prog.sy[name + "_C"] !== undefined) name += "_C";
        const a0 = prog.sy[name];
        if (a0 === undefined) return null;
        const a = a0 + off;
        const role = prog.bank[name];
        const img = prog.images.find(im => (role === undefined || im.map === role || im.map === "m") && a >= im.base && a + 3 <= im.base + im.data.length);
        if (!img) throw new Error(`${prog.name} ${name}: not in any image`);
        return { prog, name, a, map: img.map, sig: sig(img, a) };
    };
    const hookLd = (name, off = 0, bytes) => {
        if (b.loader[name] === undefined) return null;
        return { prog: null, name, a: b.loader[name] + off, map: "m", sig: bytes };
    };
    const live = h => {
        if (!h) return false;
        if (h.map !== "m") { const n = bankOf(h.map); if ((cpu.romsel & 15) !== n) return false; }
        for (let i = 0; i < 3; i++) if (h.sig[i] !== undefined && cpu.readmem(h.a + i) !== h.sig[i]) return false;
        return true;
    };
    return { hookOf, hookLd, live, bankOf };
}

// Run one build under the pilot.
//   opts.build (loadBuild), opts.pilot (object with keys(ctx), dks(ctx), observe(ctx)),
//   opts.onBoot(session) (called once the disc has booted, before the game),
//   opts.iters (MLOOP iterations to record), opts.maxSecs (emulated), opts.seedBoot(regions,
//   written, rb) (at TT170: returns [addr, bytes] to write, given the set of addresses
//   written since the game's entry), opts.patch({ wr, rb, sy }) (called at BAY after
//   QU5, i.e. after the title screens: the commander patch), opts.onIter(i, s, res),
//   opts.screen (hash the screen at each MLOOP), opts.trace (log injected keys),
//   opts.shots / opts.onShot(s, i) (screenshot every N)
// Returns { snaps (per iteration, regions concatenated), fsDirty (per iteration,
//   the offsets that hold filing-system bytes), screens, iterTimes, tt100Times
//   ([emulated s, iteration] per flight TT100), init (snapshot at TT170), keyLog,
//   events, iters, tt100, emuSecs, error, page0d }
export async function runElite(opts) {
    const b = opts.build;
    const s = await bootModelB(b.disc);
    const cpu = s._machine.processor;
    if (opts.onBoot) opts.onBoot(s);      // (bhsync.mjs: hooks from the loader on)
    const regions = regionsFor(b);
    const canon = canonFor(b, regions);
    const rd = (a, n = 1) => { const r = new Array(n); for (let i = 0; i < n; i++) r[i] = cpu.ramRomOs[(a + i) & 0xffff]; return r; };
    const rb = a => cpu.ramRomOs[a & 0xffff];
    const wr = (a, bytes) => { for (let i = 0; i < bytes.length; i++) cpu.ramRomOs[a + i] = bytes[i] & 255; };
    const fsy = b.progs.flight.sy;
    const isRamBank = n => !!s._machine.processor.model.swram[n & 15];

    const { hookOf, hookLd, live, bankOf } = progHooks(b, cpu);
    const P = b.progs;
    const H = {};
    for (const p of [P.flight, P.docked]) {
        H[p.name] = {
            RDKEY: hookOf(p, "RDKEY"), Rd2: hookOf(p, "Rd2"), DKS4: hookOf(p, "DKS4", 17), DOKEY: hookOf(p, "DOKEY"),
            MLOOP: hookOf(p, "MLOOP"), TT100: hookOf(p, "TT100"),
        };
    }
    H.flight.Mpc = hookOf(P.flight, "M%");
    Object.assign(H.docked, { TT170: hookOf(P.docked, "TT170"), QU5: hookOf(P.docked, "QU5"), BAY: hookOf(P.docked, "BAY"),
        MT26: hookOf(P.docked, "MT26"), S0: hookOf(P.docked, "S%"), S3: hookOf(P.docked, "S%", 3) });
    // the interrupt handler's DEC LASCT (&CE &46 &03): LASDEC in a build that
    // names it, else the original's, VNT3+14 (loader symbols)
    const lasHook = hookLd("LASDEC", 0, [0xce, 0x46, 0x03]) || hookLd("VNT3", 14, [0xce, 0x46, 0x03]);
    const lasNext = { ...lasHook, a: lasHook.a + 3, sig: [] };
    // pc -> hooks
    const byPc = new Map();
    const add = (key, h) => { if (!h) return; h.key = key; (byPc.get(h.a) || byPc.set(h.a, []).get(h.a)).push(h); };
    for (const pn of ["flight", "docked"]) for (const [k, h] of Object.entries(H[pn])) add(k, h);
    add("LAS", lasHook); add("LASN", lasNext);
    // the build's patches (PATCHES above), on the flight program
    for (const name of b.patches) {
        if (!PATCHES[name]) throw new Error(`unknown patch ${name}`);
        for (const pt of [].concat(PATCHES[name](P.flight))) add("PATCH", { prog: P.flight, name, ...pt });
    }

    // label lookup for call sites, per program and mapping ("m": main RAM,
    // or a bank role; a cold body's label, name_C, is reported as name)
    const labs = {};
    for (const p of [P.flight, P.docked]) {
        const l = {};
        for (const [k, v] of Object.entries(p.sy)) {
            if (v < 0x1000 || /^(CODE|LOAD)/.test(k)) continue;
            const m = v < 0x8000 || v >= 0xc000 ? "m" : (p.bank[k] || p.images.find(im => v >= im.base && v < im.base + im.data.length)?.map || "m");
            (l[m] ||= []).push([k, v]);
        }
        for (const x of Object.values(l)) x.sort((x, y) => x[1] - y[1]);
        labs[p.name] = l;
    }
    const roleOf = romsel => { for (const r of Object.keys(b.banks)) if (bankOf(r) === (romsel & 15)) return r; return null; };
    const labelOf = (prog, a, romsel = cpu.romsel) => {
        const lab = labs[prog.name][a < 0x8000 || a >= 0xc000 ? "m" : (roleOf(romsel) || "m")] || [];
        let lo = 0, hi = lab.length - 1, r = null;
        while (lo <= hi) { const m = (lo + hi) >> 1; if (lab[m][1] <= a) { r = lab[m][0]; lo = m + 1; } else hi = m - 1; }
        return r && r.endsWith("_C") ? r.slice(0, -2) : r;
    };
    const stackWord = k => rb(0x100 + ((cpu.s + k) & 0xff)) | (rb(0x100 + ((cpu.s + k + 1) & 0xff)) << 8);
    // the JSR whose return address is at S+k and the ROMSEL it ran with,
    // seeing through far-call frames, if the build has them: a far call runs
    // its target with the stack holding the return into the far-call code
    // (farret), then the caller's ROMSEL, then the caller's own return
    // address (romsel: what the code that owns S+k ran with)
    const callerAt = (k, romsel = cpu.romsel) => {
        let w = stackWord(k);
        while (b.loader.farret !== undefined && w + 1 === b.loader.farret) { romsel = rb(0x100 + ((cpu.s + k + 2) & 0xff)); k += 3; w = stackWord(k); }
        return { site: w + 1 - 3, k, romsel };
    };

    const res = { snaps: [], fsDirty: [], screens: [], iterTimes: [], tt100Times: [], tt100AtIter: [], init: null, keyLog: [], events: [], s, cpu, regions, page0d: [] };
    let started = false, done = false, armPatch = false, iter = 0, tt100 = 0, inGame = false;
    let keysDown = [], lasSaved = -1;
    const ctxBase = { rb, rd, sy: fsy, iterOf: () => iter, tt100Of: () => tt100 };
    const ask = ctx => {
        const keys = opts.pilot.keys({ ...ctxBase, ...ctx }) || [];
        if (keys.length) res.keyLog.push([iter, ctx.site + (ctx.waitFor ? "<" + ctx.waitFor : ""), keys.map(k => k.toString(16)).join("+")]);
        if (opts.trace && keys.length) console.log(`iter ${iter} ${ctx.site}${ctx.waitFor ? "<" + ctx.waitFor : ""}: ${keys.map(k => "&" + k.toString(16)).join(" ")}`);
        return keys;
    };

    const fire = (h, pc) => {
        const pn = h.prog ? h.prog.name : null;
        switch (h.key) {
            case "DOKEY":
                if (started) keysDown = ask({ kind: "dokey", site: "DOKEY", prog: pn, psy: h.prog.sy });
                break;
            case "RDKEY": {
                if (!started) break;
                const c = callerAt(1);
                const site = labelOf(h.prog, c.site, c.romsel);
                if (site === "DK4" || site === "FREEZE" || site === "DOKEY") break;   // (DOKEY's reads: the iteration's keys)
                let waitFor = null;
                if (site === "t" || site === "t2") { const w = callerAt(c.k + 2, c.romsel); waitFor = labelOf(h.prog, w.site, w.romsel); }
                keysDown = ask({ kind: "rdkey", site, callSite: c.site, waitFor, prog: pn, psy: h.prog.sy });
                break;
            }
            case "Rd2":
                // RDKEY's result, the lowest pressed key from 16 on, with bit 7
                // set (or &80 for none), just before its EOR #&80 and TAX: the
                // port scans the keyboard a column at a time, not through
                // DKS4, so the result is set here, in both runs
                if (started) {
                    const ks = keysDown.filter(k => k >= 16 && k < 128);
                    cpu.a = ks.length ? Math.min(...ks) | 0x80 : 0x80;
                }
                break;
            case "DKS4": {
                if (!started) break;
                const key = cpu.x & 0x7f;
                let down;
                if (key === 1) {
                    const c = callerAt(1);
                    const site = labelOf(h.prog, c.site, c.romsel);
                    const w = site;
                    down = opts.pilot.dks ? !!opts.pilot.dks({ ...ctxBase, kind: "dks4", key, site: w, prog: pn }) : false;
                    if (down) res.keyLog.push([iter, "CTRL:" + w, "1"]);
                } else down = keysDown.includes(key);
                cpu.x = down ? key | 0x80 : key;
                break;
            }
            case "PATCH": h.apply(cpu); break;
            case "Mpc": {
                const v = rb(fsy.LASCT);
                if (v) cpu.ramRomOs[fsy.LASCT] = v - 1;
                settle();
                break;
            }
            case "LAS": lasSaved = rb(fsy.LASCT); break;
            case "LASN": if (lasSaved >= 0) { cpu.ramRomOs[fsy.LASCT] = lasSaved; lasSaved = -1; } break;
            case "MLOOP":
                if (!started) break;
                settle();
                res.snaps.push(snapshot());
                res.fsDirty.push(dirtyOffsets());
                if (opts.screen) res.screens.push(screenHash());
                res.iterTimes.push(emuSecs());
                res.tt100AtIter.push(tt100);
                if (opts.pilot.observe) opts.pilot.observe({ ...ctxBase, kind: "iter", prog: pn });
                if (opts.onIter) opts.onIter(iter, s, res);
                iter++;
                if (iter >= opts.iters) { done = true; return true; }
                break;
            case "TT100":
                if (started && pn === "flight") { res.tt100Times.push([emuSecs(), iter]); tt100++; }
                break;
            case "QU5": armPatch = true; break;
            case "BAY":
                if (armPatch) {
                    armPatch = false;
                    if (opts.patch) opts.patch({ wr, rb, sy: fsy });
                    res.events.push([iter, "commander patched at BAY"]);
                }
                break;
            case "MT26":
                if (started) { res.events.push([iter, "MT26 (OSWORD line input) reached: not supported"]); res.error = "MT26"; done = true; return true; }
                break;
            case "S0": case "S3":
                if (!inGame) { inGame = true; }
                break;
            case "TT170":
                if (!started) {
                    started = true;
                    cpu.ramRomOs[fsy.DNOIZ] = 0xff;           // sound off, in both runs
                    if (opts.seedBoot) { res.seeded = opts.seedBoot(regions, written, rb); for (const [a, bytes] of res.seeded) wr(a, bytes); }
                    bootWrites.remove();
                    for (const a of [...dirty]) dirty.delete(a);
                    res.init = snapshot();
                }
                break;
        }
        return false;
    };
    // The run loop below calls the handler by hand for the first instruction of
    // each slice of execute(), which jsbeeb 1.6.0 does not pass to its
    // instruction hooks; jsbeeb 2 does pass it, so there the handler would see
    // that instruction twice, at the same cycle, whenever a slice ends on a
    // hooked instruction: an iteration counted twice at MLOOP (every later
    // snapshot one iteration behind), LASCT decremented twice at M%, the pilot
    // asked twice. A hook fires once per instruction executed: the second call
    // at the same PC and the same cycle is ignored.
    let seenPc = -1, seenAt = -1;
    const handler = pc => {
        const hs = byPc.get(pc);
        if (!hs) return false;
        const at = cpu.cycleSeconds * 2e6 + cpu.currentCycles;
        if (pc === seenPc && at === seenAt) return false;
        seenPc = pc; seenAt = at;
        for (const h of hs) if (live(h) && fire(h, pc)) return true;
        return false;
    };
    // compared offsets
    const offOfAddr = new Map();
    { let o = 0; for (const [a, n] of regions) { for (let i = 0; i < n; i++) offOfAddr.set(a + i, o + i); o += n; } }
    function snapshot() {
        const out = [];
        for (const [a, n] of regions) out.push(...rd(a, n));
        return canon(Uint8Array.from(out));
    }
    // filing-system bytes: written by the MOS, a ROM or the NMI handler, and
    // not yet written by the game since
    const dirty = new Set();
    const sysWriter = () => {
        const pc = cpu.pc;
        if (pc >= 0xc000) return true;
        if (pc >= 0x8000) return !isRamBank(cpu.romsel);
        return pc >= 0x0d00 && pc < 0x0e00;
    };
    cpu.debugWrite.add(a => {
        if (!inGame || !offOfAddr.has(a)) return false;
        if (sysWriter()) dirty.add(a); else dirty.delete(a);
        return false;
    });
    // the filing system's bytes above page 0 that the game has not written
    // since: set to 0 (see the header)
    function settle() {
        for (const a of dirty) if (a >= 0x100) { cpu.ramRomOs[a] = 0; dirty.delete(a); }
    }
    function dirtyOffsets() {
        if (!dirty.size) return null;
        return [...dirty].map(a => offOfAddr.get(a)).sort((x, y) => x - y);
    }
    // opts.screen: a hash of the screen memory at each MLOOP (the original's:
    // the space view and the dashboard at &6000-&7EFF), for builds that draw as
    // the original does
    function screenHash() {
        return createHash("sha1").update(cpu.ramRomOs.subarray(opts.screenLo ?? 0x6000, opts.screenHi ?? 0x7f00)).digest("hex").slice(0, 16);
    }
    function emuSecs() { return cpu.cycleSeconds + cpu.currentCycles / 2e6; }
    // the addresses written between the game's entry and TT170, by the game
    // or by the MOS on its behalf: anything else in the compared state at
    // TT170 was left by the boot and the loader (opts.seedBoot)
    const written = new Set();
    const bootWrites = cpu.debugWrite.add(a => { if (inGame && a < 0x8000) written.add(a); return false; });
    // Page &0D: once the game has started, nothing but the filing system (the
    // MOS, DFS, and the NMI handler that DFS puts at &0D00) and the original's
    // own code there (CATD, at &0D7A) may write it. Writes by any other code in
    // RAM are recorded in res.page0d, and bcompare fails the candidate on any.
    cpu.debugWrite.add(a => {
        if (!inGame || a < 0x0d00 || a > 0x0dff) return false;
        const pc = cpu.pc;
        if (sysWriter()) return false;
        if (res.page0d.length < 20) res.page0d.push([iter, pc, a]);
        return false;
    });
    cpu.debugInstruction.add(handler);
    const maxSecs = opts.maxSecs || 7200;
    let shotAt = 0;
    while (!done && emuSecs() < maxSecs) {
        for (let k = 0; k < 40 && !done; k++) { if (handler(cpu.pc)) break; cpu.execute(50000); }
        if (opts.shots && iter >= shotAt + opts.shots) { shotAt = iter; await opts.onShot(s, iter); }
    }
    res.emuSecs = emuSecs();
    res.iters = iter; res.tt100 = tt100;
    return res;
}

// Snapshot helpers
export function offsetToAddr(regions, o) {
    for (const [a, n] of regions) { if (o < n) return a + o; o -= n; }
    return -1;
}
