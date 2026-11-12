#!/usr/bin/env python3
# bmap.py [OUT.md]: the port's memory map as built (docs/memory-map.md, "The
# map"), from the build's symbols (3-assembled-output/<assembly>-symbols.txt),
# the constants of elite-map.asm and gfx-rws.asm and the generated
# gfx-faces.asm, and the sizes the assemblies print (compile.txt): every
# place in main RAM and in the four sideways RAM banks, with its addresses,
# what it holds, and the bytes used and free. Run by the Makefile after
# mapcheck.py; writes 3-assembled-output/memory-map.md (or OUT.md), the
# table that docs/memory-map.md's map is.
import re, sys

OUT = "3-assembled-output/"
SRC = "1-source-files/main-sources/"
dest = sys.argv[1] if len(sys.argv) > 1 else OUT + "memory-map.md"


def syms(name):
    d = {}
    for m in re.finditer(r"'([^']+)':(-?\d+)", open(OUT + name + "-symbols.txt").read()):
        d.setdefault(m.group(1), int(m.group(2)))
    return d


def constants(files):
    out = {}
    for f in files:
        for l in open(f, encoding="latin-1"):
            m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*([^\\]+)", l)
            if not m:
                continue
            e = re.sub(r"&([0-9A-Fa-f]+)", r"0x\1", m.group(2)).strip()
            e = re.sub(r"\bDIV\b", "//", e)
            e = re.sub(r"\bAND\b", "&", e).replace("%", "_P")
            try:
                out[m.group(1).replace("%", "_P")] = eval(e, {}, dict(out))
            except Exception:
                pass
    return out


C = constants([SRC + "elite-map.asm", SRC + "gfx-rws.asm", SRC + "gfx-faces.asm", SRC + "gfx-glue.asm"])
LD, FL, DK, B5, B6 = syms("loader"), syms("flight"), syms("docked"), syms("bank5"), syms("bank6")
cp = open(OUT + "compile.txt", encoding="latin-1").read()


def printed(pat):
    m = re.search(pat, cp)
    return [int(x, 16) for x in m.groups()] if m else None


rows = []


def row(space, start, end, what, used=None):
    """[start, end) holding what, used bytes from start (None: all)"""
    n = end - start
    u = n if used is None else used
    rows.append((space, start, end, what, u, n - u))


progm, progm_end, progx, progx_end = C["PROGM_P"], C["PROGM_END_P"], C["PROGX_P"], C["PROGX_END_P"]
resa_end, = printed(r"Resident block A: &0400-&([0-9A-F]+)")
row("main RAM", 0x0000, 0x0100, "zero page: the game's (the rasteriser's &06-&27 and the frame layer's &D2-&E1 during a frame, kept)")
row("main RAM", 0x0100, 0x0200, "the stack")
row("main RAM", 0x0300, 0x03D0, "`UP`, the game's workspace")
row("main RAM", 0x0400, C["PFVA_P"], "resident block A (`elite-resident.asm`): `BANKS`, the far calls, `PCLI` with `dfsin`, `dfsout`, `pload`, `WRCHR`, `BRKR`, the last saved commander and the break handler, `IRQG`", resa_end + 1 - 0x0400)
pfva_used = FL.get("PFVA_END%", C["PFVA_P"]) - C["PFVA_P"]
row("main RAM", C["PFVA_P"], C["GLUE_P"], "the circle engine's variables (main low: `gfx-merid.asm`)", pfva_used)
row("main RAM", C["GLUE_P"], 0x07C0, "the glue: the trampolines into bank 5, `GCALL`; then `pcb_o`, the circle engine's table that banks 4 and 6 read (main: `gfx-merid.asm`)", LD["pcb_o"] + 5 - C["GLUE_P"])
row("main RAM", 0x07C0, 0x0800, "`SNE`, `ACT`")
row("main RAM", 0x0880, 0x08C0, "`QQ16`")
row("main RAM", 0x0900, 0x0D00, "`K%` and the line heaps (the loader's `LOAD` at `&0B00` before the game)")
row("main RAM", 0x0D7A, 0x0D9E, "`CATD`")
row("main RAM", 0x0E00, 0x0FD3, "`WP`")
row("main RAM", C["BUF0"], C["SCREEN_P"], "buffer 0 (DFS's page `&1000` between disc commands kept in bank 7; `STAGE%` from `&1600` during a load)")
row("main RAM", C["SCREEN_P"], C["PANEL_P"], "buffer 1, the screen")
row("main RAM", C["PANEL_P"], C["PANEL_P"] + C["PANELROWS"] * 0x100, "the dashboard (`P.DIALS`)")
row("main RAM", C["RUPT_P"], progm, "the rupture (`elite-rupture.asm`, copied there by the loader): the clock switches, the frames' registers, the flip, the display off during disc commands; its variables after its code", LD["RUPT_END"] - C["RUPT_P"])
for prog, sy in (("flight", FL), ("docked", DK)):
    row("main RAM (%s)" % prog, progm, progm_end, "the main RAM part: the low pass, then `hotm`", sy["PROGM_USED%"] - progm)
row("main RAM", C["MBOX"], C["MBOX_END"], "the mailbox, `MBOX`: the rasteriser's inputs (the stars at its end, `&67-&9F`); sharing its polygon vertices, `PCLI`'s command and OSFILE block, the circle records from `PF_HOOK` to the frame (`&00-&49`, `&52-&5D`) and the disc layer's batches (`&00-&65`)")
row("main RAM", C["GVARS"], C["RESH_P"], "`GVARS`, the renderer's shared variables (the game's hooks, the interrupt and the frame layer's)", C["PF_CLS"] + 1 - C["GVARS"])
row("main RAM", C["RESH_P"], C["PFVH_P"], "the high resident block: the palette", LD["RESH_END"] - C["RESH_P"])
pfvh_used = FL.get("PFVH_END%", C["PFVH_P"]) - C["PFVH_P"]
row("main RAM", C["PFVH_P"], C["PFVH_P"] + 64, "the circle engine's variables (main high: `gfx-planet7.asm`, `gfx-merid.asm`)", pfvh_used)
row("main RAM", 0x7F00, progx, "the missile's blueprint")
for prog, sy in (("flight", FL), ("docked", DK)):
    row("main RAM (%s)" % prog, progx, progx_end, "the main RAM part: `hotx`", sy["PROGX_USED%"] - progx)
row("main RAM", 0x7FFE, 0x8000, "`VEC`")

qsl, bp, bp_end = C["QSL"], C["BPSLOT_P"], C["BPSLOT_END_P"]
circ = FL["CIRC_START%"]
row("bank 4 (flight)", 0x8000, circ, "`S%` and the hot pass")
row("bank 4 (flight)", circ, qsl, "the planet's surface (bank 4 passes: `PF_HOOK`, `pc_circ`)", FL["HOME_END%"] - circ)
row("bank 4 (flight)", qsl, bp, "the quarter squares `QSL`, `QSH`")
row("bank 4 (flight)", bp, bp_end, "the blueprint set (`D.MOx`), its normals and `FC_NORMTAB`")
pfvs_used = FL.get("PFVS_END%", C["PFVS_P"]) - C["PFVS_P"]
row("bank 4 (flight)", C["PFVS_P"], 0xC000, "the circle engine's variables (bank 4 top)", pfvs_used)
progis = progm_end - progm + progx_end - progx
row("bank 4 (docked)", 0x8000, qsl - progis, "`S%` and the hot pass", DK["HOME_END%"] - 0x8000)
row("bank 4 (docked)", qsl - progis, qsl, "the main RAM part's image")
row("bank 4 (docked)", qsl, bp, "the quarter squares `QSL`, `QSH`")
row("bank 4 (docked)", bp, bp_end, "the docked code's blueprints, their normals and `FC_NORMTAB`", C["NORMTAB"] - bp)
dfss = C["DFSSAVE_P"]
dpst = dfss - 0xC00
row("bank 7 (flight)", 0x8000, FL["OVL%"], "the cold pass, `QQ18`")
m = re.search(r"Flight overlays: &([0-9A-F]+) -&([0-9A-F]+)  \(1: (\d+)  bytes, 2: (\d+)", cp)
row("bank 7 (flight)", FL["OVL%"], FL["WIN7%"], "the overlay region (`D.OV1` %s bytes, `D.OV2` %s)" % (m.group(3), m.group(4)))
row("bank 7 (flight)", FL["WIN7%"], dpst, "the renderer's window (bank 7 passes: the disc layer's painter with its strips, the second disc, their operands' patch)", FL["WIN7_END%"] - FL["WIN7%"])
row("bank 7 (flight)", dpst, dfss, "each buffer's disc state (not in the image: `DP_BEGIN` sets it up)")
row("bank 7", dfss, 0xC000, "DFS's workspace page between disc commands (`DFSSAVE%`)")
row("bank 7 (docked)", 0x8000, dfss, "the set's face lists, the cold pass, `QQ18`", DK["COLD_END%"] - 0x8000)

rjt = B5["RJT"]
row("bank 5", 0x8000, 0x9000, "`R_POLY`, `R_LINE`", B5["R_LOEND"] - 0x8000)
row("bank 5", 0x9000, 0x9600, "the state: the dirty and written extents, `R_POLY`'s edge tables")
row("bank 5", 0x9600, B5["r_tfree"], "`R_SETBUF`, `r_pgfix`, the spans, the arithmetic")
row("bank 5", B5["r_tfree"], B5["r_tables"], "the room below the per-x tables: `R_LINE`'s cold part, the private state, `R_RESETBUF`, `r_wq`, `pf_tilt`", B5["R_GAPEND"] - B5["r_tfree"])
run0 = B5["r_run0"]                    # (a run page's tail, after its 190-byte run and the
empty = [p for p in range(24)           # spare byte: empty if no label is in it)
         if not any(run0 + 0x100 * p + 191 <= v < run0 + 0x100 * (p + 1) for v in B5.values())]
row("bank 5", B5["r_tables"], rjt, "the per-x tables, the 24 row runs (the stars' records, variables and some code in their tails; free: the %d tails with nothing in them, 65 bytes each), the row pages, the stars, `R_INIT`, the repair, `R_GETW`" % len(empty),
    rjt - B5["r_tables"] - 65 * len(empty))
row("bank 5", rjt, 0xC000, "`RJT`, the jump table", B5["RJT_END"] - rjt)

fcslot, fjt = C["FCSLOT"], C["FJT"]
row("bank 6", 0x8000, B6["F_CODEEND"], "the frame layer's code (bank 6 passes)")
row("bank 6", B6["F_CODEEND"], B6["F_TABEND"], "the faces' and the lighting's tables")
row("bank 6", B6["F_TABEND"], B6["f_plm"] + 1, "the state: the ship records, the zero page `F_FRAME` keeps, the faces' levels, the docking slot, the planet's records kept")
row("bank 6", B6["f_plm"] + 1, B6["F_HW"], "(the page alignment of the state that follows)", 0)
row("bank 6", B6["F_HW"], fcslot, "the state, page aligned: the discs' half-widths, the text map, the discs' rows", B6["F_END"] - B6["F_HW"])
row("bank 6", fcslot, fjt, "`FCSLOT`: the face lists of the set loaded")
row("bank 6", fjt, 0xC000, "`FJT`, the dispatcher", B6["FJT_END"] - fjt)

L = ["| Place | Addresses | Holds | Used | Free |", "|---|---|---|---:|---:|"]
for space, s, e, what, u, f in rows:
    L.append("| %s | `&%04X-&%04X` | %s | %d | %d |" % (space, s, e - 1, what, u, f))
tot = {}
for space, s, e, what, u, f in rows:
    k = space.split(" (")[0] if space.startswith("main") else space
    tot.setdefault(space, 0)
    tot[space] += f
L.append("")
L.append("Free, by place: " + ", ".join("%s %d" % (k, v) for k, v in tot.items()) + ".")
open(dest, "w").write("\n".join(L) + "\n")
print("bmap: %d places, written to %s" % (len(rows), dest))
