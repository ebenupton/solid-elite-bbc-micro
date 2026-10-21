// Screenshots of a build in flight, as jsbeeb's video shows them (the
// rupture, the palette and all), at given main-loop iterations of the gate's
// run (bpilot.mjs's pilot and commander patch).
//
// node 6-harness/bshot.mjs [--build b] --at N1,N2,... [--out DIR]
//
// At each MLOOP iteration N the frame that the video last completed is
// copied (the screen as it was shown just before that iteration's main
// loop), and written as DIR/it-N.png once the run is over.
import { mkdirSync, writeFileSync } from "fs";
import { resolve } from "path";
import { deflateSync } from "zlib";
import { runElite, loadBuild, CAND_BUILD, WORK } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
const args = parseArgs({ build: "value", at: "value", out: "value", after: "value" });
const B = loadBuild(resolve(args.build || CAND_BUILD));
const OUT = resolve(args.out || `${WORK}shots`);
const AT = (args.at || "200").split(",").map(Number);
mkdirSync(OUT, { recursive: true });
const frames = [];
let sess = null;
const r = await runElite({
    build: B, pilot: makePilot(), iters: Math.max(...AT) + 1, maxSecs: 4 * Math.max(...AT) + 60, patch: patchCommander,
    onIter: (i, s) => {
        sess = s;
        if (AT.includes(i)) frames.push([i, Buffer.from(s._completeFb8)]);
    },
});
// --after S: also run S emulated seconds past the end and take a last shot
// (for a run that stops: what the screen shows then)
if (args.after) { for (let k = 0; k < +args.after * 50; k++) await sess.runFor(40000); frames.push(["end", Buffer.from(sess._completeFb8)]); }
const v = sess._video;
const W = 1024, H = 625;
const left = v.leftBorder, top = v.topBorder, w = W - left - v.rightBorder, h = H - top - v.bottomBorder;
// a PNG of the active area: jsbeeb's frame is 1024 columns (16 a microsecond:
// a MODE 1 or MODE 4 pixel is two) by 625 rows (each scan line twice), so
// this takes every other column and row, one pixel each
const crcTab = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = buf => { let c = 0xffffffff; for (const b of buf) c = crcTab[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const t = Buffer.from(type), l = Buffer.alloc(4), c = Buffer.alloc(4); l.writeUInt32BE(data.length); c.writeUInt32BE(crc(Buffer.concat([t, data]))); return Buffer.concat([l, t, data, c]); };
const png = (wd, ht, rgb) => { const hd = Buffer.alloc(13); hd.writeUInt32BE(wd, 0); hd.writeUInt32BE(ht, 4); hd[8] = 8; hd[9] = 2;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", hd), chunk("IDAT", deflateSync(rgb)), chunk("IEND", Buffer.alloc(0))]); };
for (const [i, fb] of frames) {
    const cols = w >> 1, rows = h >> 1;
    const rgb = Buffer.alloc((cols * 3 + 1) * rows);
    for (let y = 0; y < rows; y++) {
        rgb[y * (cols * 3 + 1)] = 0;
        for (let x = 0; x < cols; x++) {
            const o = ((top + 2 * y) * W + left + 2 * x) * 4, d = y * (cols * 3 + 1) + 1 + x * 3;
            rgb[d] = fb[o]; rgb[d + 1] = fb[o + 1]; rgb[d + 2] = fb[o + 2];
        }
    }
    writeFileSync(`${OUT}/it-${i}.png`, png(cols, rows, rgb));
    console.log(`${OUT}/it-${i}.png (${cols}x${rows})`);
}
console.log(`iterations ${r.iters}${r.error ? ", stopped: " + r.error : ""}`);
process.exit(r.error ? 1 : 0);
