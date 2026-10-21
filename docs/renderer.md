# The filled renderer

The port's third part replaces the wireframe in flight with the BBC Master
port's filled, dithered, double-buffered renderer, rewritten for the NMOS
6502 and the Model B's memory. This page describes what is built so far.

## The rasteriser's bank R

The rasteriser is the Master port's (`gfx-raster*.asm`: filled convex
polygons, lines, spans, dots and stars into a MODE 1 buffer, each shape
extending its rows' dirty extents, and each buffer repairing its own dirty
rows at the start of its next frame). The copies here come from the Tube
branch's Model B host versions (`~/elite-full-tube`, `master/src`), which
already draw buffer 0 at `&1000` and need no ACCCON, and are made NMOS at
build time by `2-build-files/nmos.py` (also the Tube branch's), with the
same hand fixes. `2-build-files/bankr.py` converts them into
`3-assembled-output/nmos/`, assembles `gfx-bankr.asm`, makes long any
branch that the longer NMOS code put out of range (`longbr.py`), and writes
`3-assembled-output/R.bin` (the 16K bank image) and `bankr-symbols.txt`.
`make` runs it; nothing loads or calls bank R yet.

### The memory

| Where | What |
|---|---|
| main `&1000-&3FFF` | buffer 0 (`BUF0`, elite-map.asm) |
| main `&4000-&6FFF` | buffer 1 (`SCREEN%`, the direct-mode screen) |
| main `&7E00-&7E9D` | the mailbox, `MBOX`: each call's inputs (below) |
| zero page `&06-&27` | the colour pair, span ends and clip window (`&06-&0F`), and the rasteriser's scratch (`&10-&27`); the caller saves and restores the game's bytes there around a frame |
| bank R `&8000-&8FDC` | the polygon window: `R_POLY` (both phases), `R_LINE`'s loops, the dirty repair (`r7_rowrep`), `R_INIT`, `R_RESETBUF`, `R_REPAIR` (34 bytes free) |
| bank R `&9000-&947F` | the state: both buffers' dirty extents (`R_DIRTYL0`, `R_DIRTYR0`, `R_DIRTYL1` = `R_DIRTYL0` + `&300`, `R_DIRTYR1`), this frame's written extents (`R_WL`, `R_WR`) |
| bank R `&9480-&977F` | row set-up code, the scalars (`RDATA`: buffer, dirty and written row ranges, star record counts, the NMOS conversion's temporaries) and `R_POLY`'s edge tables |
| bank R `&9780-&9828` | `R_LINE`'s cold part (342 bytes free to `&997F`) |
| bank R `&9980-&BF9A` | `R_SETBUF`, the per-x tables, the 24 row runs at `&A000` (with the stars' records and `R_SPAN`, `R_DOT`, `R_MARKDIRTY`, `R_STARERASE`, `R_STARPLOT` in their tails), `R_LINE` (36 bytes free) |
| bank R `&BFC0-&BFDF` | `RJT`, the jump table |

Nothing of the rasteriser's state is in main RAM but the mailbox. Bank R
uses no zero page outside `&06-&27`: the NMOS conversion's temporaries
(`nmos.py --tmp`, `--tmpy`, and `R_LINE`'s cold part's `PHX`/`PLX`), which
the Tube's host kept at `&E5-&E7`, are in bank R (`R_NTMP`, `R_NTMPY`,
`R_NTMPX`).

### The interface

Bank R's entry points are in its jump table, `RJT` (`gfx-rws.asm`), in this
order; the frame layer calls them through the trampolines `T_INIT` to
`T_STARPLOT` (`gfx-rtramp.asm`, 136 bytes, for the resident block A), each
of which pages bank R in (`BANKR`), calls the entry and pages the caller's
bank back. A, X and Y are passed through; nothing is returned in them.

| RJT + | Routine | Inputs |
|---:|---|---|
| 0 | `R_INIT`: once; clip window 1..254 x 1..191, `R_SCOL` = `&FF`, both buffers' state empty, `R_SETBUF` 0 | |
| 3 | `R_SETBUF`: the buffer the next calls use (patches the code for it) | A = 0 or 1 |
| 6 | `R_RESETBUF`: forget the current buffer's state (its window must be black) | |
| 9 | `R_REPAIR`: start a frame on the current buffer: black each dirty row's extent (widened to whole bytes), set `R_WL`/`R_WR` to what it wrote, empty the dirty extents | |
| 12 | `R_SPAN`: fill pixels `R_XL`..`R_XR` of a row with the colour pair (no state updated) | Y = row; `R_XL`, `R_XR`, `R_COLE`, `R_COLO` (zero page) |
| 15 | `R_MARKDIRTY`: extend the row's dirty extent by `R_XL`..`R_XR` | Y = row; `R_XL`, `R_XR` |
| 18 | `R_DOT`: a dot of size 1 (1x1), 2 (2x1) or 3 (2x2) | X = x, Y = y, A = size; the colour pair |
| 21 | `R_POLY`: a filled convex polygon, either winding, in a 4-row colour | mailbox `R_PN` (1..16), `R_PXL`, `R_PXH`, `R_PYL`, `R_PYH` (16 each, signed 16-bit), `R_COL2`, `R_COL3`; zero page `R_COLE`, `R_COLO` |
| 24 | `R_LINE`: a one-pixel line, clipped exactly | mailbox `R_X0`, `R_Y0`, `R_X1`, `R_Y1` (signed 16-bit words); the colour pair |
| 27 | `R_STARERASE`: black what the last `R_STARPLOT` on this buffer set | |
| 30 | `R_STARPLOT`: the stars (last in a frame) | mailbox `R_SN` (0..24), `R_SX`, `R_SY`, `R_SS` (24 each), `R_SCOL` |

The clip window is `R_CL`, `R_CR`, `R_CT`, `R_CB` in zero page (`&0A-&0D`).
The mailbox's offsets are in `gfx-rws.asm`: vertices at `&00`, `&10`, `&20`
and `&30`, line ends at `&40`, `R_PN` `&48`, `R_COL2` `&49`, `R_COL3` `&4A`,
`R_SN` `&4B`, `R_SCOL` `&4C`, the stars at `&50`, `&68` and `&80`. A frame on
buffer b is: `R_SETBUF` b, `R_STARERASE`, `R_REPAIR`, the shapes
(`R_POLY`, `R_LINE`, `R_DOT`; `R_SPAN` with `R_MARKDIRTY` for anything
else, such as a disc or text), then `R_STARPLOT`.

### What is not there

* **The disc layer.** The Master port's `R_DISCROWS` drew the planet and the
  sun incrementally (only the bytes that change, with two-colour crater and
  meridian bands), with 3.9K of code, 1.5K of inputs and 2.4K of boundary
  arrays per buffer: with the rest it would need about 24K, and bank R is
  16K. `R_REPAIR` keeps its other job, the repair of each buffer's dirty
  rows. A disc can still be drawn, as spans (`R_SPAN`, then `R_MARKDIRTY` so
  that the next frame on the buffer repairs it): whole each frame, so a big
  planet costs more than on the Master, and with bands only if the caller
  splits each row's span into its colours.
* **The lens flare** (`R_FLARE`, `gfx-flare.asm`): no room.
* The page-crossing alignments of the Master port's arrays (`R_DIRTYR0` at a
  low byte of `&B5`) are not kept: only cycles depend on them.

### The test

`6-harness/test_raster.py` builds bank R (with `bankr.py`) and runs the
Master port's soak test (`raster_model.py`, the Demonstration Disc port's
pixel-exact Python model) on py65's NMOS 6502 with bank R at `&8000`: spans,
polygons (8-bit and 16-bit, with random clip windows), meshes that must tile
without gaps or overlaps, lines (with the Master port's clipping cases) and
dots, and multi-frame sequences on both buffers (shapes, lines, dots,
stars, the repair, the written extents), every result compared pixel for
pixel and every dirty extent checked. It also checks that every
instruction naming buffer 0's state is a patch site `R_SETBUF` patches, and
that nothing outside the zero page `&06-&27`, the stack page, the two
buffers, the mailbox and bank R is written, and that the row runs are left
as they were (but for `r_pgfix` moving a page's stores to the other
buffer). The gate runs it with `--quick`.
