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
| bank 5 `&8000-&8FFF` | `R_POLY` (both phases) and `R_LINE`, the repair (`R_REPAIR`, `r7_rowrep`) and the disc layer's requests (`gfx-raster_dq.asm`) (43 bytes free) |
| bank 5 `&9000-&95FF` | the state: both buffers' dirty extents (`R_DIRTYL0`, `R_DIRTYR0`, `R_DIRTYL1` = `R_DIRTYL0` + `&300`, `R_DIRTYR1`), this frame's written extents (`R_WL`, `R_WR`), `R_POLY`'s edge tables |
| bank 5 `&9600-&BFBF` | the shared region (`gfx-raster.asm`): `R_SETBUF` and `r_pgfix`, the spans, `R_DOT`, `R_MARKDIRTY`, the per-x tables at `&9C00`, the 24 row runs at `&A000` (with the stars' records and variables in their tails), the stars, the row pages, `R_INIT` (180 bytes free); below the per-x tables, `R_LINE`'s cold part, `R_RESETBUF` and the frame layer's query, `r_wq` (`gfx-raster_wq.asm`) (272 bytes free) |
| bank 5 `&BFC0-&BFE9` | `RJT`, the jump table |

Nothing of the rasteriser's state is in main RAM but the mailbox. Bank 5
uses no zero page outside `&06-&27`: the NMOS conversion's temporaries are
in bank 5 (`R_NTMP`, `R_NTMPY`, `R_NTMPX`).

### The interface

Bank 5's entry points are in its jump table, `RJT` (`gfx-rws.asm`), in this
order; the frame layer calls them through the trampolines `T_INIT` to
`T_DRAINQ` (`gfx-rtramp.asm`, 116 bytes, in the resident block A: each `T_n` is four bytes, a `JSR` to a shared body and the low byte of `RJT`'s entry), each
of which pages bank 5 in (`BANK5`), calls the entry and pages the caller's
bank back. A, X and Y are passed through; nothing is returned in them.

| RJT + | Routine | Inputs |
|---:|---|---|
| 0 | `R_INIT`: once; clip window 1..254 x 1..191, `R_SCOL` = `&FF`, both buffers' state empty, `R_SETBUF` 0 | |
| 3 | `R_SETBUF`: the buffer the next calls use (patches the code for it) | A = 0 or 1 |
| 6 | `R_RESETBUF`: forget the current buffer's state (its window must be black) | |
| 9 | `R_REPAIR`: start a frame on the current buffer: black each dirty row's extent (widened to whole bytes), set `R_WL`/`R_WR` to what it wrote, empty the dirty extents | |
| 12 | `R_SPANM`: fill pixels `R_XL`..`R_XR` of a row with the colour pair (`R_SPAN`), and extend the row's dirty extent by them (`R_MARKDIRTY`), in one call; `R_XL` <= `R_XR` | Y = row; `R_XL`, `R_XR`, `R_COLE`, `R_COLO` (zero page) |
| 15 | `R_MARKDIRTY`: extend the row's dirty extent by `R_XL`..`R_XR` | Y = row; `R_XL`, `R_XR` |
| 18 | `R_DOT`: a dot of size 1 (1x1), 2 (2x1) or 3 (2x2) | X = x, Y = y, A = size; the colour pair |
| 21 | `R_POLY`: a filled convex polygon, either winding, in a 4-row colour | mailbox `R_PN` (1..16), `R_PXL`, `R_PXH`, `R_PYL`, `R_PYH` (16 each, signed 16-bit), `R_COL2`, `R_COL3`; zero page `R_COLE`, `R_COLO` |
| 24 | `R_LINE`: a one-pixel line, clipped exactly | mailbox `R_X0`, `R_Y0`, `R_X1`, `R_Y1` (signed 16-bit words); the colour pair |
| 27 | `R_STARERASE`: black what the last `R_STARPLOT` on this buffer set | |
| 30 | `R_STARPLOT`: the stars (last in a frame) | mailbox `R_SN` (0..24), `R_SX`, `R_SY`, `R_SS` (24 each), `R_SCOL` |
| 33 | `R_MARKBOX`: mark rows Y to `R_BY1` dirty from `R_XL` to `R_XR` (the lens flare's boxes) | Y; `R_BY1`, `R_XL`, `R_XR` |
| 36 | `R_GETW`: rows Y to Y + A - 1's repair extents (`R_WL`, `R_WR`) into the mailbox (pairs from `MBOX`); with A = `&80` + n, mark the n spans queued at `MBOX + &28` dirty (`R_MARKDIRTY` each); with A = `&40`, the frame layer's query (`r_wq`): for each text row whose bit is set in the mask at `MBOX + &30` to `+&32`, the union over its eight lines of this frame's written extents and the next buffer's dirty extents into `MBOX + 2r`, and whether anything covers the sights (`MBOX + &33` asks, bit 7 of `MBOX + &34` answers) | A, Y; the mailbox |
| 39 | `R_DRAINQ`: draw the A spans queued at `MBOX + &28` (row, left, right, colour byte each) through the row runs, not marked | A; the mailbox |

The clip window is `R_CL`, `R_CR`, `R_CT`, `R_CB` in zero page (`&0A-&0D`).
The mailbox's offsets are in `gfx-rws.asm`: vertices at `&00`, `&10`, `&20`
and `&30`, line ends at `&40`, `R_PN` `&48`, `R_COL2` `&49`, `R_COL3` `&4A`,
`R_SN` `&4B`, `R_SCOL` `&4C`, the stars at `&50`, `&68` and `&80`. A frame on
buffer b is: `R_SETBUF` b, `R_STARERASE`, `R_REPAIR`, the shapes
(`R_POLY`, `R_LINE`, `R_DOT`; `R_SPAN` with `R_MARKDIRTY` for anything
else, such as a disc or text), then `R_STARPLOT`.

### What is not there

* **The disc layer's window.** The Master port's `R_DISCROWS` drew the
  planet and the sun incrementally, with 3.9K of code, 1.5K of inputs and
  2.4K of boundary arrays per buffer: with the rest it would need about 24K,
  and bank 5 is 16K. `R_REPAIR` keeps its other job, the repair of each
  buffer's dirty rows. The Model B's disc layer is in the flight code's
  cold bank instead (`gfx-dlayer.asm`: "The disc layer", below), and bank 5
  only hands it the repair's extents and draws or marks the spans it queues
  (`R_GETW`, `R_DRAINQ`: `gfx-raster_dq.asm`).
* **The lens flare** (`R_FLARE`) is in bank 6, with the frame layer (below).
* **The kept solid rows** (`KF`): the Model B keeps only the disc layer's
  disc.
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
of its Model B branch), adapted to the Model B, without the Master port's
disc layer, kept solid rows, moons and rings. The game's drawing routines,
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
  reached only through the trampolines in main RAM (`T_INIT` to `T_DRAINQ`,
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
* **The discs** are the Model B's (below: "The discs").
* **The lighting** runs in the game's bank 4 (`L_SUN`, `L_REC`,
  `gfx-light.asm`, with the faces' normals, which the blueprint set
  carries), where the quarter squares are (the only copy): `F_SHIP` is
  given the faces' levels in `XX2`. Its face lists, loaded with the
  blueprint set into `FCSLOT` ([memory-map.md](memory-map.md), "Per-set
  renderer data"), hold no normals.
* **The lens flare** is in bank 6 with the frame layer (the Master port's
  `R_FLARE` is in its bank 7): it writes the back buffer itself, and marks
  each ghost's box dirty (`T_MARKBOX`) where the Master port writes each
  row's dirty extent. Its probes see the planet over a smaller sun by the
  planet's disc (`fl_inpl`, `F_HW`), as the Model B draws the smaller disc
  over the bigger one.
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
| then | the state: the ship records `F_RP` (29 bytes a ship, a field to an array of `MAXSH` = `NOSH`), the text map's row counts `F_TMR` (whole in a page), `f_zsv`, the faces' levels `F_SR`, the docking slot `F_SLV`, then page-aligned the discs' half-widths `F_HW` (the planet's) and `F_HW2` (the sun's) and the text map `F_TM` (24 x 32) |
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
| 2 | `F_FRAME`: draw this frame and empty the lists; not in a space view (`QQ11` non-zero), just empty them | `QQ11` |
| 3 | `F_SHIP`: record the ship LL9 is drawing, as its part 6 starts (`S_SHIP`) | `GTYPE`, `GNF`, `XX2` (the faces' levels, `L_REC`), `XX4`, `INWK` 0-8, `XX16`, `XX0` |
| 4 | `F_LINE`: record an enemy laser beam | `X1`, `Y1`, `X2`, `Y2` |
| 5 | `F_PDOT`: a particle of the frame's `PTCLS` (`H_DOT`) | A = x, `Y1` = y, `ZZ` |
| 6 | `F_PLANET`: record the planet (`TYPE` even) or the sun (odd) | `K3`, `K4` (centre, 16-bit), `K` (radius), `TYPE`; the planet's `INWK+6` to `+8` |
| 7 | `F_SHPPT`: record a distant ship as a 2x2 dot in its type's colour | `K3`, `K4`, `TYPE` |
| 8 | `F_PCURVE`: start a planet curve (a meridian planet's) | |
| 9 | `F_PPOINT`: its next point, joined to the last by a line | `K6`, `K5+2` (x, y, 16-bit) |
| 10 | `F_CHAR`: a character at (`XC` - 1, `YC`): into the text map in record or space mode; noted, or given to the cells buffer 0 may show, otherwise | A = the character |
| 11 | `F_DELCHAR`: clear a cell of the text map | A = column, Y = row |
| 12 | `F_CLRTEXT`: clear rows of the text map | A = first row, Y = last row |
| 13 | `F_GUN`: set up part 6's loop for a firing ship's gun vertex alone (`H_LL42`); returns Y = its offset in the vertex data | A = byte #6 of the blueprint; `XX0`, `XX16` |
| 14 | `F_HANG0`: empty the lists before the hangar's ships are recorded | |
| 15 | `F_HANGAR`: the hangar's frame | |
| 16 | `F_CLOUD`: an explosion cloud in record mode (`H_PTCLS`, C set: noted for the frame; `H_PTCLSE`, C clear): what the game keeps of `PTCLS` | `XX19`, `INF`, `XSAV` |

Limits per frame: `MAXSH` (`NOSH`, 12) ships, as many beams and as many
dots (distant ships and clouds); 3 planet curves with 64 points between
them. The stars are recorded by the hooks straight into the mailbox
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
* `GA`: `GCALL`'s A. `GDL`: the disc layer's (which buffers have its disc).

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
Then it waits for the last flip, and draws: `T_STARERASE`, `T_REPAIR`; the
discs and the meridians (`f_discs`, `f_curves`, below); the enemy beams;
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

The Model B's arrangement, which another disc layer is to replace, is in
one place, `f_discs` and `f_curves` (`gfx-frame.asm`, "The discs"): the
bigger of the sun and the planet (the sun if not smaller) through the disc
layer in the flight code's bank 7 (`gfx-dlayer.asm`, "The disc layer"
below: `DL_FRAME`, a far call, with A = the buffer and X = the discs
recorded, returning the disc it drew; its records come from the game's
hooks, `DL_PLAN`, `DL_CURVE`, `DL_POINT`), which keeps it on each buffer from
frame to frame; the other, if both are recorded, filled whole, a span a row
(`f_disc`, `T_SPAN`, which marks it dirty); and a meridian planet's
meridians and equator as lines over the planet (`f_curves`, from
`F_PCURVE`, `F_PPOINT`). The planet's half-widths (`F_HW`) are built
whichever draws it, for `f_behind` and the lens flare. As the disc layer
writes the screen itself, its writes are in no extent: `f_discs` keeps the
rows its disc covers on each buffer (`f_dlt`, `f_dlb`), and the text and the
sights over those rows, this frame's or the buffer's last, are drawn again
(`f_wq`).

### The disc layer

The sun or the planet, whichever is bigger (the sun if not smaller, the
Master port's choice), is kept on each screen buffer from frame to frame
by the disc layer, `gfx-dlayer.asm`, which is in the flight code's cold
bank (its code, records and state, then 11 page-aligned
tables of rows, crater extents and half-widths) and is
reached from bank 6 by a far call (`DL_FRAME`, after `T_REPAIR`). Its disc
is not marked dirty, so the repair leaves it alone except where something
else was drawn over it the frame before on that buffer.

* **Records.** `CIRCLE` and `SUN` record the disc for it too (`DL_PLAN`, a
  far call from the hook), and `PLS22` and `BLINE` record a crater planet's
  crater (`DL_CURVE`, `DL_POINT`) for it rather than for bank 6; a meridian
  planet's curves stay bank 6's, drawn as lines over the disc. `F_FRAME`
  calls `DL_FRAME` when a disc is recorded or the back buffer has the
  layer's disc on it (`GDL`, `GVARS + 15`: bit b for buffer b, cleared when
  `F_FRAME` blanks both buffers), with A = the buffer and X = which discs
  are recorded; it returns the one it drew, which bank 6 then leaves out
  (bank 6 still builds the planet's half-widths, which the lens flare
  reads).
* **Rows.** For each row of the old disc's or the new one's (twenty at a
  time, with the repair's extents `R_WL`/`R_WR` for them from bank 5,
  `T_GETW`), it works out the new span and the crater's band on it, and
  compares them with what the disc left on that row of this buffer (four
  page tables per buffer): the old disc's pixels that the new one does not
  cover go black, the new pixels and those the band moved over or the
  repair blacked are filled. A row that only moved its ends (the usual
  case) costs its two ends; a disc where it was two frames ago on this
  buffer (and with no band) fills only what the repair blacked. When the
  disc on the buffer was the other one, or none is known, all of the new
  disc is filled.
* **Writing.** The screen is main RAM, so it writes the spans itself: one
  byte with both masks, or the end bytes masked and the middle ones through
  an unrolled run (up to 32 bytes). A longer span would go to bank 5's row
  runs through a queue in the mailbox (`MBOX + &28`, nine spans, drained by
  `T_DRAINQ`); no disc that the frames draw needs it, so bank 5 is paged in
  only for the extents.
* **Small discs.** A disc with a radius under 40 is drawn whole each frame
  and marked dirty (the spans queued and marked by `T_GETW` with A = `&80`
  + n) after the buffer's kept disc, if any, is taken off: small discs
  move across the screen, and keeping them costs more than the repair.
* **The crater** is a band of the Master port's dark crater colour
  (`&50`/`&A0`) across the disc's rows: the closed ellipse that `PLS22`
  works out, each edge stepped row by row (halved while longer than 255),
  its x at each row widening the row's extent.

The tests are bank 6's (`6-harness/test_frame.py`): eight discs against a
model of the layer (the half-widths, the clipping, the crater's extents),
and a sequence of 23 frames on both buffers (moving, growing and static
discs, the sun and the planet swapping, small discs and back, no disc,
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
cold bank (with the disc layer); the MOS ROM at `&C000`. The ships are
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
0 after the second alone. With the disc layer against a model of it (eight
discs, and a sequence of 23 frames on both buffers). It writes the frames as
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
| `TT100`, `DEATH` (`MFRAME`), `ESCAPE` (`LL9F`) | home, cold | after each `M%` (or `LL9`), `L_SUN` (the light for the next iteration's ships, in a space view) and `F_FRAME` (`hframe`: A, X, Y and the flags as they were) |
| `LL9` part 5 | home | `GFAR` set when a face is shown without testing its normal |
| `LL9` part 6 (`H_LL42`), `S_SHIP`, `SPLV`, `SHAND`, `L_REC` | home, cold | the ship is recorded (above); a ship firing at us has its gun vertex projected (`F_GUN`, `LL48`) |
| `LL9` part 9 (`EE31`: `H_EE31`, `HEE31`) | home, cold | byte #31 set as `EE31` sets it, the beam recorded (`F_LINE`); returns as `LL155` |
| `LL155` | home | returns at once, with C set |
| `SHPPT` | home | the distant ship's dot is recorded (`F_SHPPT`) |
| `DOEXP` (`H_PTCLSE`), `PTCLS` (`H_PTCLS`), `PIXEL` in `PTCLS` (`H_DOT`) | home | the clouds (above) |
| `PIXEL2` (`PX2`, `px24r`) | home | star `Y` is recorded straight into the mailbox (`MB_SX`, `MB_SY`, `MB_SS`; size 1, 2 or 3 by `ZZ`, as `PIXEL` draws it), or marked absent if it is off screen |
| `SUN` (`HLS`, `HL2S`) | home | the sun is recorded as a disc (`F_PLANET`, and the disc layer's `DL_PLAN`); its rows are worked out as before (they take random numbers), but not drawn |
| `WPLS` | home | the sun's heap is emptied, nothing erased |
| `CIRCLE` | home | the planet is recorded as a disc (`F_PLANET`, and `DL_PLAN`), and `CIRCLE` returns as `CIRCLE2` would (FLAG = 0, C clear) |
| `PLS22`, `BLINE` | home | a new curve, and each point, without the clipping and the heap: a meridian planet's (`TYPE` 128) for bank 6 (`F_PCURVE`, `F_PPOINT`), a crater's for the disc layer (`DL_CURVE`, `DL_POINT`, far calls to the cold bank) |
| `WPLS2` | home | the heap is reset, nothing erased |
| `LASLI`, `LASLI2` | cold | `GLASV` is set (the frame draws the beams from `LASX`, `LASY`); nothing to draw or remove |
| `MA93` | home | (every mode) `Q = 0` before the altitude's `JSR LL5`; the reference is patched to match |
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

The rupture's interrupt (`IRQG`, `elite-resident.asm`) shows buffer
`GFRONT` (0: `BUF0`, 1: `SCREEN%`) in each frame A, and at its point 1 (the
start of frame B, the dashboard) carries out a pending flip: `GFRONT` =
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

The gate's run, 10,000 iterations: 201,735 cycles per flight iteration,
9.91 flight iterations per second, against the original's 168,749 and
11.85 (0.836 times; with the old frame layer, 226,316 cycles and 8.98).
By scene (`6-harness/bscenes.mjs` records each iteration's time and the
planet's, the station's and the ships' positions in a build's run;
`6-harness/scenes.py` compares two such runs, counting a flight iteration
in the front view that both put in the same scene, the first of these that
fits):

| Scene | Iterations | The original | The port | Against the original | The old frame layer |
|---|---:|---:|---:|---:|---:|
| Station close: the station ahead, nearer than 16 x 256 | 706 | 187,528 cycles, 10.67 it/s | 302,204 cycles, 6.62 it/s | 0.62 | 0.56 |
| Sun close: the sun ahead, nearer than 1,024 x 256 | 402 | 169,142, 11.82 | 200,011, 10.00 | 0.85 | 0.76 |
| Planet close: the planet ahead, nearer than 128 x 256 (mostly off the screen) | 1,032 | 146,033, 13.70 | 147,566, 13.55 | 0.99 | 0.81 |
| Big planet: the planet ahead, 128 x 256 to 512 x 256 (the big discs, 100 to 190 rows) | 6,681 | 181,260, 11.03 | 216,738, 9.23 | 0.84 | 0.76 |
| Open space: the planet at 512 x 256 or more, no station within 64 x 256, no ships | 270 | 103,168, 19.39 | 117,145, 17.07 | 0.88 | 0.70 |
| Ships about (the rest, with other ships in the bubble) | 745 | 137,912, 14.50 | 148,395, 13.48 | 0.93 | 0.81 |

The frames' gain is the Master port's: no ship line heap, clipping or
projection in the game's iteration (the frame projects only the ships it
draws), and the text drawn only where it changed or was drawn over (the
old layer drew every text row and the sights every frame). The cold bank's share grows a little
with the routines moved there for room (`PU1` in a side or rear view, once
an object; `TIDY`, one ship an iteration): a far call each, about 60 cycles.

### Where the time goes

A profile of the first 3,000 iterations (`bprofile.mjs`; mostly fighting
near the planet, then a hyperspace jump and an approach), per flight
iteration, at the renderer's first commit (345,647 cycles): bank 5
155,899 (the rasteriser), bank 6 33,125 (the frame layer), main RAM 43,264
(of which the trampolines into bank 5 about 25,600 and the far calls about
8,000), the flight code's home bank 91,419, its cold bank 8,613, and the
MOS (the interrupts) 13,327. In bank 5: the row runs 37,217 (the stores of
spans, polygons and the repair), `r_pgfix` 28,055, the repair's row code
22,569, polygons about 34,000, lines about 20,000.

* **`r_pgfix`.** The row runs are unrolled stores assembled for buffer 1;
  each time a run page is used for the other buffer, its 63 stores'
  addresses are patched. With a flip every frame, every page in use is
  patched every frame. Two sets of runs would end this, but bank 5 has no
  room for a second set (4.5K).
* **An alternate-column fill was tried instead** (a half-length run per
  buffer storing every other byte column, called twice per span, so that
  nothing is patched at a flip): it was slower, 257,536 cycles an
  iteration against 254,590, as the second call and its look-ups cost more
  per span than the patching saved (MODELB-REPORT.md has the numbers).
* **Most of it is drawn every frame.** Only the disc layer's disc (the
  bigger of the sun and the planet, with a radius of 40 or more) is kept
  from frame to frame. Before it, a trim of the repair inside a square that
  the new disc covers was tried and dropped (two repairs of a row cost more
  than they saved), and so was a plain kept disc in bank 5 (`R_DISCROW`, a
  call per row), slower than the whole fill (MODELB-REPORT.md).
* **Record mode was faithful at first.** The renderer's first commits
  still built the ship line heap, clipped its lines and worked out every
  line's `LOIN` division (`VLOIN`), so that the state stayed the
  original's; with the altitude's `Q` defined in both (above), that went.

### Speed-ups made

| Commit | Cycles per flight iteration | Saved |
|---|---:|---:|
| Draw the space view through the filled renderer | 322,228 | |
| Fill and mark a disc's row in one call, and clip in the home bank first | 308,463 | 13,765 |
| Drop record mode's line bookkeeping, with Q = 0 at the altitude in both | 254,590 | 53,873 |
| Check a run page once per buffer, and patch it without clearing the carry (`828b473`) | 247,931 | 6,659 |
| Keep the bigger disc on each buffer: the disc layer, in the flight code's cold bank (from `9bfefc3`'s 247,961) | 226,316 | 21,645 |
| The Master port's frame layer in bank 6: ships projected by the frame, clouds drawn by it, the text map | 201,735 | 24,581 |
