// Behavioural observables for the Model B: the dashboard as each machine has drawn it, read
// out of its screen memory at every MLOOP in flight (not docked, a space view, not the
// death screen).
//
// The port's dashboard is the original's (docs/memory-map.md, video-timing.md): the same
// mode 5 image (P.DIALS, seven character rows of 256 bytes, 128 x 56 pixels, four pixels a
// byte), drawn by the same game code (the bars and markers by DIALS, the scanner's dots and
// sticks and the compass's dot EORed on by SCAN and COMPAS, the missile blocks and bulbs),
// only kept at &7000 (PANEL%) rather than the original's &7800, as the port's screen
// buffers take the space above. So the two are compared byte for byte, not decoded into
// values as on the Master (whose port redraws the dashboard in another mode). A difference
// is reported by part: the left dials (shields, fuel, temperatures, altitude: character
// columns 0-7), the scanner and compass (8-23, with the missile blocks and bulbs on the
// bottom row) and the right dials (speed, roll, pitch, the energy banks: 24-31), with the
// rows and columns that differ.
export const DASH = { ref: 0x7800, cand: 0x7000, len: 0x700 };

export class Observer {
    // m: a BMachine (lib.mjs); base: where its dashboard is
    constructor(m, base) {
        this.m = m; this.base = base; this.q = [];
        const prev = m.onIter;
        m.onIter = mm => { if (prev) prev(mm); this.onIter(); };
    }
    onIter() {
        const m = this.m, sy = m.sy;
        if (m.rb(sy.QQ12) || m.rb(sy.QQ11) || m.rb(sy.MCNT) === 0xff) return;
        this.q.push({ iter: m.iter, dash: m.ram.slice(this.base, this.base + DASH.len) });
    }
    static part(o) {
        const col = (o & 0xff) >> 3, row = o >> 8;
        return col < 8 ? "left dials" : col >= 24 ? "right dials" : row === 6 && (col < 11 || col >= 21) ? "missiles and bulbs" : "scanner and compass";
    }
    // the differences between the original's record r and the port's c
    static compare(r, c) {
        const parts = {};
        for (let o = 0; o < DASH.len; o++) if (r.dash[o] !== c.dash[o]) {
            const p = Observer.part(o);
            (parts[p] ||= []).push(o);
        }
        return Object.entries(parts).map(([what, offs]) => ({
            what: `dashboard ${what}`, n: offs.length,
            cells: [...new Set(offs.map(o => `r${o >> 8}c${(o & 0xff) >> 3}`))].slice(0, 12),
            first: offs.slice(0, 4).map(o => `+&${o.toString(16)} ref &${r.dash[o].toString(16)} cand &${c.dash[o].toString(16)}`),
        }));
    }
}
