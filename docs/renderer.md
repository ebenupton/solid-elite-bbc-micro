# The filled renderer

The port's third part replaces the wireframe in flight with the BBC Master
port's filled, dithered, double-buffered renderer, rewritten for the NMOS
6502 and the Model B's memory. This page describes what is built so far.

## The rasteriser's bank 5

The rasteriser is the Master port's (`gfx-raster*.asm`: filled convex
polygons, lines, spans, dots and stars into a MODE 1 buffer, each shape
extending its rows' dirty extents, and each buffer repairing its own dirty
rows at the start of its next frame), in NMOS 6502 code, with buffer 0 at
`&1000` and no ACCCON. `2-build-files/bank5.py` assembles `gfx-bank5.asm`
(making long any branch that the longer NMOS code put out of range) and
writes `3-assembled-output/BANK5.bin` (the 16K bank image) and
`bank5-symbols.txt`; `make` runs it. The loader's `LOAD` routine loads it
from the disc's `R.BANK` into bank 5 (through `STAGE%`, as `PCLI` loads a
program).

### The memory

| Where | What |
|---|---|
| main `&1000-&3FFF` | buffer 0 (`BUF0`, elite-map.asm) |
| main `&4000-&6FFF` | buffer 1 (`SCREEN%`, the direct-mode screen) |
| main `&7E00-&7E9F` | the mailbox, `MBOX`: each call's inputs (below) |
| zero page `&06-&27` | the colour pair, span ends and clip window (`&06-&0F`), and the rasteriser's scratch (`&10-&27`); the caller saves and restores the game's bytes there around a frame |
| bank 5 `&8000-&8FFF` | `R_POLY` (both phases) and `R_LINE` (43 bytes free) |
| bank 5 `&9000-&95FF` | the state: both buffers' dirty extents (`R_DIRTYL0`, `R_DIRTYR0`, `R_DIRTYL1` = `R_DIRTYL0` + `&300`, `R_DIRTYR1`), this frame's written extents (`R_WL`, `R_WR`), `R_POLY`'s edge tables |
| bank 5 `&9600-&BFBF` | the shared region (`gfx-raster.asm`): `R_SETBUF` and `r_pgfix`, the spans, `R_DOT`, `R_MARKDIRTY`, the per-x tables at `&9C00`, the 24 row runs at `&A000` (with the stars' records and variables in their tails), the stars, the row pages, `R_INIT`, the repair (`R_REPAIR`, `r7_rowrep`) and the disc layer's transfer (`R_GETW`, `R_DRAINQ`: `gfx-raster_dq.asm`) (56 bytes free); below the per-x tables, `R_LINE`'s cold part, `R_RESETBUF` and the frame layer's query, `r_wq` (`gfx-raster_wq.asm`) (260 bytes free) |
| bank 5 `&BFC0-&BFE9` | `RJT`, the jump table |

Nothing of the rasteriser's state is in main RAM but the mailbox. Bank 5
uses no zero page outside `&06-&27`: the NMOS conversion's temporaries are
in bank 5 (`R_NTMP`, `R_NTMPY`, `R_NTMPX`).

### The interface

Bank 5's entry points are in its jump table, `RJT` (`gfx-rws.asm`), in this
order; the frame layer calls them through the trampolines `T_INIT` to
`T_GETW` (`gfx-rtramp.asm`, 112 bytes, in the resident block A: each `T_n` is four bytes, a `JSR` to a shared body and the low byte of `RJT`'s entry), each
of which pages bank 5 in (`BANK5`), calls the entry and pages the caller's
bank back. A, X and Y are passed through; nothing is returned in them.

| RJT + | Routine | Inputs |
|---:|---|---|
| 0 | `R_INIT`: once; clip window 1..254 x 1..191, `R_SCOL` = `&FF`, both buffers' state empty, `R_SETBUF` 0 | |
| 3 | `R_SETBUF`: the buffer the next calls use (patches the code for it) | A = 0 or 1 |
| 6 | `R_RESETBUF`: forget the current buffer's state (its window must be black) | |
| 9 | `R_REPAIR`: start a frame on the current buffer: clear the last frame's `R_WL`/`R_WR`; black each dirty row's extent (widened to whole bytes) outside the band of rows A to Y (the disc layer's, which it repairs itself), set `R_WL`/`R_WR` to what it wrote; no dirty rows are left to repair but the band's | A = the band's first row, Y = its last (none if A > Y) |
| 12 | `R_SPANM`: fill pixels `R_XL`..`R_XR` of a row with the colour pair (`R_SPAN`), and extend the row's dirty extent by them (`R_MARKDIRTY`), in one call; `R_XL` <= `R_XR` | Y = row; `R_XL`, `R_XR`, `R_COLE`, `R_COLO` (zero page) |
| 15 | `R_MARKDIRTY`: extend the row's dirty extent by `R_XL`..`R_XR` | Y = row; `R_XL`, `R_XR` |
| 18 | `R_DOT`: a dot of size 1 (1x1), 2 (2x1) or 3 (2x2) | X = x, Y = y, A = size; the colour pair |
| 21 | `R_POLY`: a filled convex polygon, either winding, in a 4-row colour | mailbox `R_PN` (1..16), `R_PXL`, `R_PXH`, `R_PYL`, `R_PYH` (16 each, signed 16-bit), `R_COL2`, `R_COL3`; zero page `R_COLE`, `R_COLO` |
| 24 | `R_LINE`: a one-pixel line, clipped exactly | mailbox `R_X0`, `R_Y0`, `R_X1`, `R_Y1` (signed 16-bit words); the colour pair |
| 27 | `R_STARERASE`: black what the last `R_STARPLOT` on this buffer set | |
| 30 | `R_STARPLOT`: the stars (last in a frame) | mailbox `R_SN` (0..19), `R_SX`, `R_SY`, `R_SS` (19 each), `R_SCOL` |
| 33 | `R_MARKBOX`: mark rows Y to `R_BY1` dirty from `R_XL` to `R_XR` (the lens flare's boxes) | Y; `R_BY1`, `R_XL`, `R_XR` |
| 36 | `R_GETW`: the disc layer's batch transfer (below, "The discs"): first the `DB_QN` bytes of spans queued at `DB_Q` (row, left, right, colour byte each) drawn through the row runs, not marked (`R_DRAINQ`); then X rows from row `DB_PY`: the slots' `DB_WL`, `DB_WR` into `R_WL`, `R_WR` (and `R_PRWT`..`R_PRWB`); then A AND `&1F` rows from row Y: their dirty extents into `DB_WL`, `DB_WR`, emptied (A bit 7 clear), or their written extents (A bit 7 set). With A = `&40`, the frame layer's query (`r_wq`): for each text row whose bit is set in the mask at `MBOX + &30` to `+&32`, the union over its eight lines of this frame's written extents and the next buffer's dirty extents into `MBOX + 2r`, and whether anything covers the sights (`MBOX + &33` asks, bit 7 of `MBOX + &34` answers) | A, X, Y; the mailbox |

The clip window is `R_CL`, `R_CR`, `R_CT`, `R_CB` in zero page (`&0A-&0D`).
The mailbox's offsets are in `gfx-rws.asm`: vertices at `&00`, `&10`, `&20`
and `&30`, line ends at `&40`, `R_PN` `&48`, `R_COL2` `&49`, `R_COL3` `&4A`,
`R_SN` `&4B`, `R_POLY`'s own and `R_BY1` at `&4C` to `&51`, `R_SCOL` `&66`, the
stars at `&67`, `&7A` and `&8D` (19 each, at the end, so that the disc layer's
batches have `&00` to `&65`). A frame on
buffer b is: `R_SETBUF` b, `R_STARERASE`, `R_REPAIR`, the disc layer's
batches (`R_GETW`), the shapes
(`R_POLY`, `R_LINE`, `R_DOT`; `R_SPAN` with `R_MARKDIRTY` for anything
else, such as a disc or text), then `R_STARPLOT`.

### What is not there

* **The disc layer's window.** The Master port's `R_DISCROWS` drew the
  planet and the sun incrementally, with 3.9K of code, 1.5K of inputs and
  2.4K of boundary arrays per buffer: with the rest it would need about 24K,
  and bank 5 is 16K. `R_REPAIR` keeps its other job, the repair of each
  buffer's dirty rows outside the disc layer's rows. The disc layer's row
  code (the painter) and its arrays are in the flight code's bank 7 (below,
  "The discs"), and bank 5 hands it its rows' dirty or written extents,
  takes back what it wrote and draws the long spans it queues (`R_GETW`).
* **The lens flare** (`R_FLARE`) is in bank 6, with the frame layer (below).
* **The kept solid rows** (`KF`, the station close): bank 5 has no room for
  them; the Model B keeps only the discs.
* The page-crossing alignments of the Master port's arrays are not kept:
  only cycles depend on them.

### The test

`6-harness/test_raster.py` builds bank 5 (with `bank5.py`) and runs the
Master port's soak test (`raster_model.py`, the Demonstration Disc port's
pixel-exact Python model) on py65's NMOS 6502 with bank 5 at `&8000`: spans,
polygons (8-bit and 16-bit, with random clip windows), meshes that must tile
without gaps or overlaps, lines (with the Master port's clipping cases) and
dots, and multi-frame sequences on both buffers (shapes, lines, dots,
stars, the repair, the written extents), every result compared pixel for
pixel and every dirty extent checked. It also checks that every
instruction naming buffer 0's state is a patch site `R_SETBUF` patches, and
that nothing outside the zero page `&06-&27`, the stack page, the two
buffers, the mailbox and bank 5 is written, and that the row runs are left
as they were (but for `r_pgfix` moving a page's stores to the other
buffer). The gate runs it with `--quick`.

## The frame layer's bank 6

The frame layer is the BBC Master port's current one (its `gfx-frame.asm`,
`gfx-frame_cold.asm`, `gfx-finit.asm`, `gfx-hangar.asm` and its tables,
`gfx-flare.asm` and `gfx-flare6.asm`, in the hand-converted NMOS 6502 code
of its Model B branch), adapted to the Model B, with the Master port's disc
layer (its row code in the flight code's bank 7: "The discs", below) and
its planets' surfaces, without its kept solid rows, moons and rings. The game's drawing routines,
in a view that draws ships (`QQ11` = 0 and `GFORCE` = 0: record mode),
record what they would have drawn; once per main loop iteration `F_FRAME`
draws the records into the buffer not on show and asks the vertical sync
interrupt to show it.

`2-build-files/bank6.py` (a `make` step after the programs are assembled)
writes the game's addresses and constants that bank 6 reads into
`3-assembled-output/bank6-game.asm` (from `flight-symbols.txt`, checking
that `docked-symbols.txt` agrees, `loader-symbols.txt` for the bank
numbers and the far calls, and `elite-source-flight.asm` for `NOST`,
`NOSH`, `NI%`, `SST`, `PLT`, `X` and `Y`), assembles `gfx-bank6.asm`, and
writes `BANK6.bin` (the 16K bank), `GLUE.bin` (the glue, below) and
`bank6-symbols.txt`. The loader's `LOAD` routine loads it from the disc's
`F.BANK` into bank 6 and calls `F_INIT`.

What differs from the Master port's frame layer:

* **The buffers.** Both are in main RAM, buffer 0 at `BUF0` (`&1000`) and
  buffer 1 at `SCREEN%` (`&4000`, the direct-mode screen), so there is no
  ACCCON paging: what bank 6 writes to the screen itself (the text's
  glyphs, the sights' vertical arms, the lens flare, the border at
  `f_enter`) takes the back buffer's base, which `f_bufpatch` sets each
  frame (`f_scr`, and the sights' addresses).
* **The rasteriser's state is in bank 5,** which bank 6 cannot see: it is
  reached only through the trampolines in main RAM (`T_INIT` to `T_GETW`,
  `gfx-rtramp.asm`), with the inputs in the mailbox and the zero page. What
  the Master port's frame layer read or wrote of the rasteriser's arrays
  goes through bank 5 instead: a text cell that `f_mark` must erase in both
  buffers is noted per buffer and text row (`f_mkl`, `f_mkr`) and marked
  dirty at that buffer's next frame (`f_tmark`, `R_MARKBOX`), before its
  repair; and what `f_text2` and `f_sight2` need of this frame's written and
  dirty extents comes from one query (`f_wq`: `R_GETW` with A = `&40`,
  `gfx-raster_wq.asm`), the union over each text row's eight lines for the
  rows asked for, and whether anything covers the sights.
* **The game's zero page overlaps the rasteriser's** (`XX16` is `&09-&1A`,
  `XX0` `&1E`) and this layer's (`XX2`, which part 6 reads, is `FZ` at
  `&D2`): the frame's runs of game code go through `f_gproj` and `f_gcloud`
  (the far call `farH` to the program's `S% + 16` and `S% + 19`, bank 4),
  after which the clip window is put back (`f_clip`), and nothing of `FZ`
  is kept across them (`f_ship` projects first and sets up its pointers
  after; the loops that run game code count in bank 6, `f_ii`, `f_di`).
* **The discs** are the Master port's, with the disc layer's row code (the
  painter) and each buffer's disc state in the flight code's bank 7, driven
  a batch of rows at a time through the mailbox (below: "The discs"). The
  sun near the planet (`S_SUN`) is in this bank (`make ssun=off` leaves it
  out), calling the game's `MV40` and `ZINF` through far-call stubs.
* **The lighting** runs in the game's bank 4 (`L_SUN`, `L_REC`,
  `gfx-light.asm`, with the faces' normals, which the blueprint set
  carries), where the quarter squares are (the only copy): `F_SHIP` is
  given the faces' levels in `XX2`. Its face lists, loaded with the
  blueprint set into `FCSLOT` ([memory-map.md](memory-map.md), "Per-set
  renderer data"), hold no normals.
* **The lens flare** is in bank 6 with the frame layer (the Master port's
  `R_FLARE` is in its bank 7): it writes the back buffer itself, and marks
  each ghost's box dirty (`T_MARKBOX`) where the Master port writes each
  row's dirty extent. Its probes see the planet in front of a smaller sun by
  the planet's disc (`fl_inpl`, `F_HW`), where the Master port reads the
  disc layer's spans (in bank 7 here).
* **Not here**, as the Model B has no use for them: the energy bomb's bolt
  (`F_BOMB`: disc Elite's bomb flashes the screen and draws no bolt), the
  notes of stars drawn directly (`F_DSTAR`, `f_unstar`: on the Model B the
  stardust is drawn only in a space view, always in record mode), the
  hangar's substitutions (`HSUB`: of the ships the disc version's hangar can
  show, none blends into its tan; the Master port's two, the Sidewinder and
  the Mamba, are not in the docked code's blueprint set), and the kept solid
  rows (bank 5's `KF`, which the Model B's rasteriser does not have).

### The memory

| Where | What |
|---|---|
| main `&0724-&07B9` | the glue, `GLUE%` (`gfx-glue.asm`): bank 5's trampolines and `GCALL`, at a fixed address at the end of the resident block A, which includes it |
| main `&7E00-&7E9F` | the mailbox (the rasteriser's inputs; the stars, which the game's hooks write; `f_wq`'s query and answer) |
| main `&7EA0-&7EAF` | the shared variables, `GVARS` (`elite-map.asm`) |
| zero page `&06-&27`, `&D2-&E1` | the rasteriser's, and the frame layer's pointers (`FZ`: the game's `XX2`, `K3` and `K4`, dead between iterations): `F_FRAME` keeps the game's bytes in bank 6 (`f_zsv`) and puts them back |
| bank 6 `&8000` on | the code: the frame layer, the lens flare, the screens drawn directly (`gfx-frame_cold.asm`), the hangar, `F_INIT`; then the faces' and the lighting's tables (`gfx-faces.asm`, `gfx-light6.asm`) |
| then | the state: the ship records `F_RP` (29 bytes a ship, a field to an array of `MAXSH` = `NOSH`), the text map's row counts `F_TMR` (whole in a page), `f_zsv`, the faces' levels `F_SR`, the docking slot `F_SLV`, then page-aligned the discs' half-widths `F_HW` (the planet's) and `F_HW2` (the sun's), the text map `F_TM` (24 x 32), and the discs' rows this frame: `R_NDISCR`, `R_NDISCL` (the spans), `R_NDN`, `R_NDX0` to `R_NDX3` (the planet's boundaries) |
| bank 6 `&BFC0` | `FJT`, the dispatcher |

The ships' tables are by `GTYPE`: the ship type, 1 to 31 as in the flight
program's `XX21`, whatever blueprint set is loaded (`faces.py` reads all
sixteen, `D.MOA` to `D.MOP`, with the missile, and checks that each type is
the same ship in every set that has it), but 32 for the dodecahedron
station, which is type 2 in half of the sets (`S_SHIP` gives 32 for a type
2 with 24 vertices). Type 15 (the rock hermit) is in no set and has empty
tables. The splinter's normals are worked out from its vertices, as its
blueprint's are not its own (`faces.py`'s `GEOM_NORMALS`).

### The interface

The game calls an entry as `LDX #FG_xxx : JSR GCALL` (`gfx-glue.asm`), with
the inputs in A, Y and memory. `GCALL` pages bank 6 in, enters it through
`FJT` and pages the caller's bank back; it returns A and Y as the entry left
them, and every entry keeps Y (but `F_GUN`). X is not kept; C reaches the
entry. Not from an interrupt.

| FG_ | Entry | Inputs |
|---:|---|---|
| 0 | `F_INIT`: once, first: `T_INIT`, empty lists, direct mode, buffer 0 marked as used (`GSTASH`) | |
| 1 | `F_DIRECT`: the screen is about to be cleared and drawn on directly (`TTX66`): direct mode, buffer 1 on show, no sights, beams, text or stars; but for an in-system jump in space mode (`GWARP`), the frames go on and only the text goes | |
| 2 | `F_FRAME`: draw this frame and empty the lists; not in a space view (`QQ11` non-zero), just empty them; with C set (the flight code's `hframe`), the sun near the planet first (`S_SUN`) | `QQ11`, C |
| 3 | `F_SHIP`: record the ship LL9 is drawing, as its part 6 starts (`S_SHIP`) | `GTYPE`, `GNF`, `XX2` (the faces' levels, `L_REC`), `XX4`, `INWK` 0-8, `XX16`, `XX0` |
| 4 | `F_LINE`: record an enemy laser beam | `X1`, `Y1`, `X2`, `Y2` |
| 5 | `F_PDOT`: a particle of the frame's `PTCLS` (`H_DOT`) | A = x, `Y1` = y, `ZZ` |
| 6 | `F_PLANET`: record the planet (`TYPE` even) or the sun (odd) | `K3`, `K4` (centre, 16-bit), `K` (radius), `TYPE`; the planet's `INWK+6` to `+8` |
| 7 | `F_SHPPT`: record a distant ship as a 2x2 dot in its type's colour | `K3`, `K4`, `TYPE` |
| 8 | `F_CHAR`: a character at (`XC` - 1, `YC`): into the text map in record or space mode; noted, or given to the cells buffer 0 may show, otherwise | A = the character |
| 9 | `F_DELCHAR`: clear a cell of the text map | A = column, Y = row |
| 10 | `F_CLRTEXT`: clear rows of the text map | A = first row, Y = last row |
| 11 | `F_GUN`: set up part 6's loop for a firing ship's gun vertex alone (`H_LL42`); returns Y = its offset in the vertex data | A = byte #6 of the blueprint; `XX0`, `XX16` |
| 12 | `F_HANG0`: empty the lists before the hangar's ships are recorded | |
| 13 | `F_HANGAR`: the hangar's frame | |
| 14 | `F_CLOUD`: an explosion cloud in record mode (`H_PTCLS`, C set: noted for the frame; `H_PTCLSE`, C clear): what the game keeps of `PTCLS` | `XX19`, `INF`, `XSAV` |

Limits per frame: `MAXSH` (`NOSH`, 12) ships, as many beams and as many
dots (distant ships and clouds). The stars are recorded by the hooks straight into the mailbox
(`R_SX`, `R_SY`, `R_SS`, entries 1 to `NOST`; `R_SS` = 0 for none).

The shared variables (`GVARS`, `elite-map.asm`):

* `GMODE` bit 7: space mode (the frames run); clear: direct mode (the game
  draws on buffer 1). `F_DIRECT` clears it, the first `F_FRAME` after it
  sets it (`f_enter`).
* `GFRONT`, `GFLIP`, `GPEND`: the flip, with the interrupt (below).
* `GFORCE` (non-zero: draw directly even in a space view), `GSIGHT` (draw
  the sights), `GLASV` (draw our beams, from `LASX`, `LASY`; cleared after
  each frame), `GWARP` (bit 7: `TT66` is an in-system jump's).
* `GNF`, `GTYPE`: `F_SHIP`'s and `L_REC`'s inputs.
* `GSTASH` bit 7: a disc command has used buffer 0 (`PCLI`): the next frame
  starts it afresh (`f_b0new`).
* `GA`: `GCALL`'s A. `PF_CLS`: the planet's class, as `PF_HOOK` made it
  this iteration (bit 7: it made the surface's circles, in the mailbox).

`GVARS + 8`, `+ 9` and `+ 11` are free.

### A frame

`F_FRAME`: keep the zero page (`f_zsv`); on the first frame since direct
mode, or after a disc command has used buffer 0, `f_enter2` (buffer 0
cleared if it was used, `f_b0new`; buffer 1's border copied to buffer 0; on
entering space mode buffer 1's state forgotten, as `TTX66` has just
cleared it, while buffer 0 keeps the last frame of the previous space-mode
session, which its state still describes, and is repaired from it; the
text drawn directly given to the text map, `f_sync`); `f_bufpatch`; the
clip window 2..253 x 1..191; `T_SETBUF`; the text cells to be erased and
the sights if they have gone, marked dirty (`f_text1`, `f_sight1`); the
ships sorted far to near and the first projected (`f_sort`, `f_proj0`).
Before that wait, the discs' rows are made (`f_dprep`, below), first of
all, as the planet's circles are in the mailbox. Then it waits for the last
flip, and draws: `T_STARERASE`; the repair and the discs (`f_ddraw`,
below); the enemy beams;
the ships, far to near, each projected as it is drawn (`f_proj`: the game's
`LL42F`, part 6 on), its faces flat-shaded and lit, culled by their winding
in the ship's handedness when Elite showed them without testing their
normals, with details and fins, its distant dot under its faces from
`FC_DOTZ` out (`f_sdot`), and a ship behind the planet skipped
(`f_behind`); the distant ships' dots and the explosion clouds, each cloud
drawn by the game's own `PTCLS` from the ship line heap (`f_gcloud`, its
particles through `H_DOT` and `F_PDOT`); our beams; the lens flare; the text
(`f_text2`: the rows that changed for this buffer whole, elsewhere the cells
something was drawn over); the sights (when wanted and not shown, or drawn
over); the stars, only into black screen bytes (`T_STARPLOT`; with a
docking slot filled this frame, `f_slot` leaves out the stars in it). Then
the game's zero page back (`f_gback`, `f_zsv`), and the flip queued.

The text map (`F_TM`, `F_TMR`, `F_TCH`, and the notes of direct text `f_dlog`
...) is the Master port's, with its `EOR` undo (`f_eor`, so the hyperspace
countdown counts down) and its hand-over of the text drawn directly
(`f_sync`, `f_drule`): docs of the Master port's renderer, "The text map".

### The discs

The sun and the planet are the Master port's discs (`gfx-frame.asm`, "The
discs", whose comments describe them): the bigger (the sun if not smaller)
is the disc layer, kept on each buffer from frame to frame and drawn only
where it changed, and the other, if both are on the screen, the second
disc, behind it, incremental too (`R_DISC2`). A planet that is the layer
has its surface as colour boundaries along each row (`R_NDN`, `R_NDX0-3`),
which the circle engine's `PC_ROWS` makes from the circles `PF_HOOK` made
in the game's iteration (the beach ball of a meridian planet, a crater
planet's craters: "Planet surfaces" in the Master port's docs); with no
circles (a build without `_CIRCLES`) it is a plain disc. The bank holds
what the Master port's frame layer does of it and the rows' arrays; the
row code, the painter, which compares each row with what the buffer holds
and writes only the pixels that changed (the edges' strips, the repair of
dirty rows, the second disc's pieces), is in the flight code's bank 7 with
each buffer's state (`gfx-window7.asm`: `gfx-raster_disc.asm` with the
strips, `gfx-raster_disc2.asm`), as bank 5 has no room for it.

* **`f_dprep`** (before the wait): which disc is the layer (`f_lay`) and
  which the second (`f_sec`); the layer's spans, clipped to the window
  (`f_sunrows`, `f_plrows`, `f_discspans`: `R_NDISCL/R`, `R_NDT`, `R_NDB`,
  with the half-width tables `F_HW`, `F_HW2` rebuilt when a radius
  changes), and the planet's boundaries (`f_bounds`: `PC_ROWS`, which reads
  the records where `PF_HOOK` left them, in the mailbox: `PCB`, `PC_N`,
  `pc_inv`, before the frame uses the mailbox for anything else; a disc
  command in the iteration, which takes the mailbox, drops them: `f_b0new`).
* **`f_ddraw`** (after the wait, in place of `T_REPAIR`): the band of rows
  (the layer's on this buffer last time, `f_dlt`, `f_dlb`, and this frame's);
  `T_REPAIR` repairs the dirty rows outside it; the painter's frame
  (`DP_BEGIN`, a far call: the buffer, whether its rows keep boundaries,
  a change of the layer's colour, which makes the old disc dirty, and a
  buffer blanked since, which it forgets); then the band's rows in batches
  (`f_dbat`): for each, one `T_GETW` (bank 5 draws the spans the painter
  queued, puts what it wrote on the last batch's rows into `R_WL`/`R_WR`,
  and gives this batch's dirty extents, emptying them) and one far call to
  `DP_ROWS`, the slots filled from the row arrays (empty spans outside
  `R_NDT`..`R_NDB`). Then `f_disc2`: the second disc's spans into the same
  arrays, its rows (old, `R_S2T`..`R_S2B`, and new) in batches to
  `DP_DISC2`, with the rows' written extents instead (what the layer and
  the repair wrote on them), and a last `T_GETW` for the last batch.
* **The batches** are in the mailbox (`gfx-rws.asm`, `DB_*`), `&00` to `&65`:
  16 rows (one colour: the new span, `DB_NL`, `DB_NR`, and the dirty or
  written extent in, what was written out, `DB_WL`, `DB_WR`) or 8 (with the
  boundaries' count and colour, `DB_NN`, and `DB_X0` to `DB_X3`); the queue
  of spans of 16 whole bytes or more for bank 5's row runs, seven at a time
  (`DB_Q`, `DB_QN`); `DB_PY`, the row of the batch whose writes `T_GETW`
  puts. The stars are at the mailbox's end, out of the way.
* **The painter** is the Master port's `R_DISCROWS` row code (`r_dlb` for
  one colour, `r_dmb` with boundaries, `r_dp2`, `r_dq`, `r_dpe` with the
  strips, `r_drg`, `r_segw`, `r_dp1`) and `R_DISC2`, with the row in X for
  each buffer's arrays and the slot in Y for the batch: a row that changed
  has its slot's data taken into variables and what it wrote put back
  (`dp_ld`, `dp_st`). It writes the screen itself (a row's address worked
  out, `r_rowp`; the masks from four-byte tables, `r_sw`), queueing the
  layer's long spans while the queue has room (the layer's writes on a row
  never overlap, so their order does not matter; the second disc's may, so
  it writes all of its own). Each buffer's arrays (`R_DISCL/R`, `R_BDN`,
  `R_BDX0-2`, `R_S2L/R`) are the other's but for their high bytes, which
  `DP_BEGIN` patches into the code (`dp_patch`, generated from the sites'
  labels into `gfx-raster_dpatch.asm`). The window's state is not in the
  `D.CODEC` image: a buffer is blanked whenever a program is loaded (a disc
  command uses buffer 0, `TTX66` blanks buffer 1), and `DP_BEGIN` sets up
  each buffer's state at the first frame after (`f_dpr`, `f_dforget`).
* **The rest of the frame** sees the discs' writes as any others: they are
  in `R_WL`/`R_WR` (so the text and the sights over them are drawn again),
  and the planet's half-widths (`F_HW`) are there for `f_behind` and the
  lens flare's probes.

The flight code records the discs as before (`F_PLANET`, from `SUN` and
from `CIRCLE`'s `H_CIRC`); the docked code records none, so the painter
(which only the flight code's bank 7 has) is never called while docked.

The tests are bank 6's (`6-harness/test_frame.py`): nine single frames
against a model (the layer in front, the second disc behind, a beach ball
and craters from circle records as `planet_caps.py` makes them, `PC_ROWS`'
rows checked against that model's), and a sequence of 30 frames on both
buffers (moving, growing and still discs, the sun and the planet swapping,
the second disc coming and going, surfaces spinning and going, no disc,
ships and lines over them), each frame's buffer byte for byte the same
scene drawn on a fresh machine.

### The lens flare

The Master port's lens flare with its probes (`gfx-flare.asm`,
`gfx-flare6.asm`), in bank 6: `f_flt` runs it after the beams, when the sun
is recorded, the view is the front one and the sun's centre is on the
screen. `R_FLARE` probes the back buffer as drawn so far at nine points of
the sun's disc (its centre, and eight round it at about 0.62 R): a probe
outside the clip window, or, when the sun is smaller than the planet and so
behind it, inside the planet's disc (`FL_BEH`, `fl_inpl`), is out of sight;
one inside is in sight if its pixel is still the sun's colour for its row.
None in sight: no flare. Otherwise eight ghosts along the line from the sun
through the screen's centre, six dithered discs and two dotted rings, ORed
into the back buffer, every ghost's density stepped down by the probes not
in sight (`fl_vred`), each ghost's box marked dirty (`T_MARKBOX`) so that
the next frame on the buffer repairs it.

### The test

`6-harness/test_frame.py` builds banks 5 and 6 and runs them on py65's NMOS
6502: main RAM with the resident block A (the far calls) and the glue, the
bank numbers and the game's variables; `&8000-&BFFF` paged by ROMSEL
(`&FE30`) between the flight code's home bank (`D.CODEH`, with a blueprint
set from a `D.MOx` file in its slot), bank 5, bank 6 and the flight code's
cold bank (with the disc layer's painter); the MOS ROM at `&C000`. The ships are
recorded by the game's own `LL9` (with a ship firing at us and one just
killed, exploding); every other entry is called as the game calls it,
`LDX #n : JSR GCALL` from main RAM with the home bank paged; and the frame
runs part 6 on and `PTCLS` in the home bank. It checks that nothing is
written outside the renderer's zero page, the stack, the buffers,
`&7E00-&7EFF`, the glue's and the far calls' own bytes, `&F4`, ROMSEL and
the banks (and, for the frame, the game's zero page, `UP` and `K%`); that
the zero page is as it was after every entry but `F_FRAME`, and after it
but for the drawing's temporaries; that Y is kept and the home bank paged
back; entering space mode and the flip; what was drawn (the sun's colour,
the ships, the explosion's particles, the nearest ship's vertices where
they should be, the glyphs, the sights); and the repair, the text
included: buffer 0 after one scene and then another is byte for byte buffer
0 after the second alone. With the discs against a model of them (nine
scenes, and a sequence of 30 frames on both buffers: "The discs"). It writes the frames as
PNGs (`--png DIR`, default `3-assembled-output`).

## The game's side

### Record mode

In a view that draws ships (`QQ11` = 0) the game's drawing is *recorded*
for the frame layer instead of drawn, unless `GFORCE` is set (only `HFS1`,
the launch and hyperspace rings, sets it: they are drawn directly, on
buffer 1). `RECM` (home bank) returns `A` = `QQ11` OR `GFORCE`, zero in
record mode. Outside it the game draws on buffer 1 (`SCREEN%`) as before,
in direct mode. Every `LL9` records its ship: in the flight code `LL9` runs
only in a space view, and the docked code's ships (the title's, the
hangar's, the briefings') are frames too (below), so nothing draws a ship
directly, and `LL9`'s line drawing (the rest of part 9, parts 10 and 11,
and part 12's drawing of the ship line heap) is `Area: none`, as the BBC
Master port removed it; `LL155` returns at once with C set.

### What record mode skips, and the reference's patch

In record mode the game skips its drawing and the drawing's own
bookkeeping: the ship line heap and the clipping of its lines, the
projection of a ship's vertices (which the frame does, as it draws the
ship), the explosion clouds' particles (the frame draws them), the
planet's outline and the clipping and heap of its curves, the erasing of
the sun's and the planet's old lines, and our lasers' lines. What is real
game state still runs, or is worked out as the skipped code would leave
it: the sun's rows (which take random numbers for the fringe), the random
numbers and the variables `PTCLS` leaves (`F_CLOUD`), byte #31's bits.

One thing in the original depends on what the drawing leaves behind: the
altitude (`ALTIT`, in the main flight loop at `MA93`) is `SQRT(R Q)` with
`Q` left over from whatever ran last, which a trace of the gate's run
shows is `LOIN`'s division about two times in five. So the port sets
`Q = 0` before that `JSR LL5` (`LDA #0 : STA Q`), and the gate's reference
gets the same patch: the harness applies the named patch `ma93-q`
(`6-harness/blib.mjs`, `PATCHES`; listed in the reference's `build.json`)
as a hook at the reference's `JSR LL5` after `MA93`, which it finds by
its bytes (`STA R`, `JSR LL5`, which must be there exactly once) and at
which it sets `Q` to 0. The altitude the patched game shows can differ
from the original's by one unit.

A second: when `LL9` starts a killed ship's explosion, the explosion's
first random number (`EE55`'s first `DORND`) takes the C flag from `EE51`,
which removes the ship from the screen: `LL155` leaves it set after drawing
a heap of lines but clear after a heap of none (a ship whose edges were all
clipped away), and `EE51` leaves it as it was when the ship was not on the
screen. The port draws no heap, so it sets C = 1 after that `JSR EE51`,
and the reference gets the same (the named patch `ee51-c`, at the
instruction after the `JSR`, which it finds from `LL9` by its bytes).

### The frame's records

**Ships.** `LL9` records each ship that is not exploding as its part 6
starts (`H_LL42`, at `LL42`): `S_SHIP` shows the splinter's four faces
(`SPLV`: its blueprint's normals are not its own), works out the ship's
handedness when a face is to be culled by its winding (`SHAND`, as `TIDY`
gives a ship the other one), gives the type (`GTYPE`: 32 for the
dodecahedron station) and the alloy plate's face (shown from both sides),
lights the faces (`L_REC`: their levels in `XX2`) and records the ship
(`F_SHIP`: `INWK` 0-8, `XX16` as part 3 scaled it, `XX0`, `XX4` and the
levels). `LL9` then returns through `H_EE31`, which sets byte #31 as `EE31`
does and records the ship's laser beam if it fires at us (`HEE31`, clipped
by `LL145`, from the gun vertex, which part 6 has projected alone:
`F_GUN`). The frame projects the ship as it draws it: it puts the record
back and calls `LL42F` (`S% + 16`), which runs part 6 on with `GPRJ` set, so
that `H_EE31` returns at once; part 6 on changes nothing the game reads but
`XX3`, and the frame keeps and puts back the game's zero page it changes
(`f_gkeep`, `f_gback`; `RAND`, `Q`, `TGT`, `INWK` 0-8 and 31, `XX19`, with
`&06-&27` and `&D2-&E1` in `f_zsv`). `XX3` is page 1, under the stack: the
frame keeps the zero page in bank 6, not on the stack.

**Explosion clouds.** A cloud's record is the exploding ship's line heap,
which the game keeps anyway. In record mode `DOEXP`'s two passes of
`PTCLS` do only what the game keeps of them (`H_PTCLS`, `H_PTCLSE`:
`F_CLOUD`, the random numbers `PTCLS` would leave, and `Q`, `U`, `TGT` and
`CNT`), and the draw pass notes the cloud (its slot and data block); the
frame runs `PTCLS` on the heap again (`PTCLR`, `S% + 19`), whose `PIXEL`
calls plot the particles (`H_DOT`, `F_PDOT`), so the frame draws every
particle the original draws.

### The hooks

| Where | Bank | In record mode |
|---|---|---|
| `TT100`, `DEATH` (`MFRAME`), `ESCAPE` (`LL9F`) | home, cold | after each `M%` (or `LL9`), `L_SUN` (the light for the next iteration's ships, in a space view) and `F_FRAME` with C set (`hframe`: A, X, Y and the flags as they were; the docked code's `hframe` clears C, so that only the flight code's frame runs `S_SUN`) |
| `LL9` part 5 | home | `GFAR` set when a face is shown without testing its normal |
| `LL9` part 6 (`H_LL42`), `S_SHIP`, `SPLV`, `SHAND`, `L_REC` | home, cold | the ship is recorded (above); a ship firing at us has its gun vertex projected (`F_GUN`, `LL48`) |
| `LL9` part 9 (`EE31`: `H_EE31`, `HEE31`) | home, cold | byte #31 set as `EE31` sets it, the beam recorded (`F_LINE`); returns as `LL155` |
| `LL155` | home | returns at once, with C set |
| `SHPPT` | home | the distant ship's dot is recorded (`F_SHPPT`) |
| `DOEXP` (`H_PTCLSE`), `PTCLS` (`H_PTCLS`), `PIXEL` in `PTCLS` (`H_DOT`) | home | the clouds (above) |
| `PIXEL2` (`PX2`, `px24r`) | home | star `Y` is recorded straight into the mailbox (`MB_SX`, `MB_SY`, `MB_SS`; size 1, 2 or 3 by `ZZ`, as `PIXEL` draws it), or marked absent if it is off screen |
| `SUN` (`HLS`, `HL2S`) | home | the sun is recorded as a disc (`F_PLANET`); its rows are worked out as before (they take random numbers), but not drawn |
| `WPLS` | home | the sun's heap is emptied, nothing erased |
| `CIRCLE` (`H_CIRC`) | home | the planet is recorded as a disc (`F_PLANET`) and its surface as circles (`PF_HOOK`, in a build with `_CIRCLES`: at the end of the home bank, with the circle engine's `pc_circ`, which reads the quarter squares), and `H_CIRC` returns from `PL9` as its parts 2 and 3 would, leaving what the game reads of them (`K2`, `TGT`, `FLAG`, `LSX2`, `STP`, `CNT`, as the Master port's `H_CIRC`): `PL9` parts 2 and 3, `PLS2`, `PLS22`, `PLS3`, `PLS4` and `PLS5` are `Area: none` (outside record mode, the launch and hyperspace rings' frames, the planet is its circle alone) |
| `WPLS2` | home | the heap is reset, nothing erased |
| `LASLI`, `LASLI2` | cold | `GLASV` is set (the frame draws the beams from `LASX`, `LASY`); nothing to draw or remove |
| `MA93` | home | (every mode) `Q = 0` before the altitude's `JSR LL5`; the reference is patched to match |
| `LL9` part 1 | home | (every mode) C = 1 after the kill path's `JSR EE51`, for the explosion's first random number; the reference is patched to match |
| `SIGHT` | cold | `GSIGHT` is set to the laser power, `QQ19` as `TT15` leaves it |
| `TTX66` | cold | (every mode) `F_DIRECT`: direct mode, buffer 1 on show, the text map cleared; for an in-system jump in space mode (`WARP` sets `GWARP`), the frames go on, and `TTX66` neither clears the screen nor draws the border |
| `TT26` (`RR3`) | cold | (every mode) the character goes to the text map (`F_CHAR`); in record mode it is not drawn |
| `CLYNS` | cold | (every mode) rows 21 and 22 of the text map are cleared (`F_CLRTEXT`); in record mode the screen is not touched |
| `HFS1` | cold | sets `GFORCE` while it draws the rings |
| `LOMOD`, `DEATH2` | cold, home | `CATD` is called with DFS's workspace put back at `&1000` (`dfsin`) and kept afterwards (`dfsout`), as `PCLI` does, as buffer 0 is drawn over it |

The flight code's home bank is full (its hot pass and the lighting, with
the faces' normals, 1,956 bytes, at `&8000-&B4FF`, the quarter squares and
the blueprint slot after it). For room, besides `CLYNS`, `LYN` and the
rarely run parts of the main loops, these are in the cold bank: `DEATH`
(its read of `XX21` through `DPLT`, at home), `LASLI`, `PU1` (a side or rear
view's axes, once an object an iteration there), `TIDY` with `TIS1`,
`TIS2`, `TIS3`, `DVIDT` and `NORM` (a ship's orientation tidied, one ship
an iteration at most), `MAS1`, `PIXEL` (drawn directly only), `LL145`'s
first part (the beams and the rings' clipping), `ARCTAN` (the meridian
planet's), `SHAND` and `SPLV` (the few ships with untested faces, far away).

### The docked code

The docked code records its ships too, with its own copies of the hooks
(`H_LL42`, `S_SHIP`, `L_REC` with the fixed light, `H_EE31`, `LL155`,
`SHPPT`), its text (`CHPR`'s `RR3` and `RRD`, `CLYNS`: the text map in
every mode, the screen only outside record mode and space mode, `DRAWQ`)
and `TTX66` (direct mode). It has the quarter squares too (`QSL`, `QSH`, in
its home bank, for `L_REC`). Its cold bank's `S% + 19` entry is `DOEXP`,
which returns at once there. Three screens are frames:

* **The title** (`TITLE`, which sets `QQ11` = 0): `LL9F`, a frame after
  each `LL9`.
* **The hangar** (`HALL`): `F_HANG0` empties the frame's lists before `HAS1`
  places and records the ships (with `TYPE` set from `XX0` while its `LL9`
  records each, as `HAS1` sets only `XX0`, and put back after); then, in place of `HANGER`'s lines,
  `F_HANGAR` draws one frame whose background (`gfx-hangar.asm`, the
  Master port's: a darker tan wall and a light tan floor, each a 2x2
  dither, with `HANGER`'s lines in black) goes in between the discs and the
  ships, through `F_FRAME`'s `ff_lin`, so the ships hide it where
  `HANGER`'s lines stopped at them.
* **The briefings** (`BRIEF`, `PAUSE`, `PAS1`): `LL9B` sets `QQ11` = 0 for
  `LL9` and a frame (`LL9F`), and puts it back; the briefing's text,
  printed outside record mode while the frames run, goes into the text map,
  which the frames draw.

As these draw into buffer 0, over DFS's workspace page, the docked code's
own disc calls (the commander file's `OSFILE`, and `CATD`) keep the page as
`PCLI` does (`dfsin`, `dfsout`).

### The buffers and the flip

The rupture (`RUPT`, `elite-rupture.asm`, which `IRQG` calls at timer 1)
shows buffer `GFRONT` (0: `BUF0`, 1: `SCREEN%`) in each frame A, and at the
start of frame B (the dashboard) carries out a pending flip: `GFRONT` =
`GPEND`, `GFLIP` = 0. As in the BBC Master port, the frame rate is capped at
25 frames a second: a flip pending at the field straight after a flip is
held for one field (`rflip`), so each frame is on show for two fields at
least, and a frame quicker than that waits at its flip while the next
iteration's game code runs. `PCLI` sets `GSTASH` at every disc command (the
staging area and DFS's workspace page are in buffer 0), so the next frame
starts buffer 0 afresh. The dashboard, in its own memory at `PANEL%`, is
drawn directly in every mode.

### The test

`6-harness/test_routines.py` runs the port's routines with `GFORCE` set,
so that the drawing paths are compared with the original's, pixel for
pixel; the gate's run (record mode, in flight) compares the game's state
with the original's at every iteration, which checks that the record mode
and the frame's runs of game code leave everything as the original does.

## Speed

The gate's run, 10,000 iterations: 271,014 cycles per flight iteration,
7.38 flight iterations per second, against the original's 168,749 and
11.85 (0.623 times). The build has the planets' surfaces (`_CIRCLES`,
the default) and the sun near the planet (`S_SUN`). With plain discs
(`make circles=off`) it is 153,097 cycles, 13.06 it/s (1.102 times), of
which the dashboard's clock switches take about 1,350 cycles
([video-timing.md](video-timing.md)).
By scene (`6-harness/bscenes.mjs` records each iteration's time and the
planet's, the station's and the ships' positions in a build's run;
`6-harness/scenes.py` compares two such runs, counting a flight iteration
in the front view that both put in the same scene, the first of these that
fits), without `_CIRCLES` (`make circles=off`: plain discs) and with it
(the default: the beach ball and the craters):

| Scene | Iterations | The original | The port | Against the original | With `_CIRCLES` | Against the original |
|---|---:|---:|---:|---:|---:|---:|
| Station close: the station ahead, nearer than 16 x 256 | 706 | 187,528 cycles, 10.67 it/s | 304,405 cycles, 6.57 it/s | 0.62 | 327,396, 6.11 | 0.57 |
| Sun close: the sun ahead, nearer than 1,024 x 256 | 402 | 169,142, 11.82 | 201,544, 9.92 | 0.84 | 202,336, 9.88 | 0.84 |
| Planet close: the planet ahead, nearer than 128 x 256 (mostly off the screen) | 1,032 | 146,033, 13.70 | 142,698, 14.02 | 1.02 | 165,223, 12.10 | 0.88 |
| Big planet: the planet ahead, 128 x 256 to 512 x 256 (the big discs, 100 to 190 rows) | 6,681 | 181,260, 11.03 | 150,690, 13.27 | 1.20 | 307,764, 6.50 | 0.59 |
| Open space: the planet at 512 x 256 or more, no station within 64 x 256, no ships | 270 | 103,168, 19.39 | 95,355, 20.97 | 1.08 | 147,291, 13.58 | 0.70 |
| Ships about (the rest, with other ships in the bubble) | 745 | 137,912, 14.50 | 110,727, 18.06 | 1.25 | 186,966, 10.70 | 0.74 |
| The first system's front view (Lave, a beach ball, combat after launch) | 586 | 252,929, 7.91 | 126,960, 15.75 | 1.99 | 421,480, 4.75 | 0.60 |

With `_CIRCLES` the surface's rows are worked out from the
circles and painted in every frame the planet turns.

The disc layer keeps both discs on each buffer and writes only what
changed. Its batches cost, over the gate's run (`bprofile.mjs`), about 90
disc rows a flight iteration in 6 batches, 18,300 cycles a flight
iteration, about 200 cycles a row: filling the slots in bank 6 (52 a row),
`R_GETW` in bank 5 (the dirty extents taken and emptied, the writes put
back: about 70 a row), a changed row's data taken and put back in the
painter (`dp_ld`, `dp_st`: 84 a changed row, about half the rows), and a
trampoline and a far call a batch (about 220 cycles).

The station close is the slowest scene. A profile of its iterations
(`bprofile.mjs --scenes`, each flight iteration put in the scene of the
iteration it ends; 272,546 cycles an iteration that way) has bank 5 at
133,853: `R_POLY` about 55,000 (mostly phase B, the station's faces filling
most of the window), the row runs' stores 19,302, the repair 17,365,
`r_pgfix` 11,600 (the run pages patched for the other buffer at each
flip), `R_MARKDIRTY` 6,896 and `R_LINE` 5,542; the game's home bank 80,347
(the docking computer's arithmetic, the stardust, the station's dot
products and `L_REC`), bank 6 22,711, bank 7 15,452 (the cold code and the
painter), main RAM 11,353 (the far calls, the trampolines and the
interrupt) and the MOS 8,828. Each frame fills nearly the whole window and
repairs it on the next: the Master port's kept solid rows take that cost
away (7.6% to 10.6% over a docking there), and bank 5 has no room for them.

* **`r_pgfix`.** The row runs are unrolled stores assembled for buffer 1;
  each time a run page is used for the other buffer, its 63 stores'
  addresses are patched. Two sets of runs would end this, but bank 5 has
  no room for a second set (4.5K).
* **The frames' gain** is the Master port's: no ship line heap, clipping or
  projection in the game's iteration (the frame projects only the ships it
  draws), and text drawn only where it changed or was drawn over. The cold
  bank's share grows a little with the routines moved there for room
  (`PU1` in a side or rear view, once an object; `TIDY`, one ship an
  iteration): a far call each, about 60 cycles.
