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
`make` runs it. The loader's `LOAD` routine loads it from the disc's
`R.BANK` into bank R (through `STAGE%`, as `PCLI` loads a program).

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
`T_STARPLOT` (`gfx-rtramp.asm`, 108 bytes, in the resident block A: each `T_n` is four bytes, a `JSR` to a shared body and the low byte of `RJT`'s entry), each
of which pages bank R in (`BANKR`), calls the entry and pages the caller's
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

## The frame layer's bank F

The frame layer is the Master port's (`gfx-frame.asm`, `gfx-frame_cold.asm`
and `gfx-light.asm` there), rewritten for the NMOS 6502 and simplified for a
bank that cannot see bank R: it reaches the rasteriser only through the
trampolines, with the inputs in the mailbox and the zero page. The game's
drawing routines, in a space view, are to *record* what they would have
drawn; once per main loop iteration `F_FRAME` draws the records into the
buffer not on show and asks the vertical sync interrupt to show it.
`2-build-files/bankf.py` (a `make` step after the programs are assembled)
writes the game's addresses and constants that bank F reads into
`3-assembled-output/bankf-game.asm` (from `flight-symbols.txt`, checking
that `docked-symbols.txt` agrees, `loader-symbols.txt` for `BANKR` and
`BANKF`, and `elite-source-flight.asm` for `NOST`, `NI%`, `SST`, `PLT`),
assembles `gfx-bankf.asm`, and writes `F.bin` (the 16K bank), `GLUE.bin`
(the glue, below) and `bankf-symbols.txt`. The loader's `LOAD` routine
loads it from the disc's `F.BANK` into bank F and calls `F_INIT`.

### The memory

| Where | What |
|---|---|
| main `&0730-&07B9` | the glue, `GLUE%` (`gfx-glue.asm`): bank R's trampolines (108 bytes) and `GCALL` (30), at a fixed address at the end of the resident block A, which includes it |
| main `&7EB0-&7EF1` | PCLI's command and OSFILE block (`PCBUF`, `PBLK`) and the palette (`PALCMYK`), moved out of the resident block to make room for the glue |
| main `&7EA0-&7EFF` | the shared variables, `GVARS` (`elite-map.asm`) |
| zero page `&06-&27`, `&D2-&E1` | the rasteriser's, and the frame layer's pointers (the game's `XX2`, `K3` and `K4`, dead between iterations): `F_FRAME` and `F_INIT` keep the game's bytes in bank F and put them back |
| bank F `&8000-&95D5` | the code: the entries, the drawing steps, the lighting (5,590 bytes) |
| bank F `&95D6-&A482` | the tables: faces, details, fins and dot colours (`gfx-faces.asm`) and the hue ramps (`gfx-light6.asm`), both from `faces.py` (3,757 bytes) |
| bank F `&A500-&B3FF` | page-aligned: the lighting's quarter squares `F_QSL`/`F_QSH` (0 to 255; main RAM's are under buffer 0), the discs' half-widths `F_HW` (planet) and `F_HW2` (sun), the text map `F_TM` (24 x 32), the ships' records `F_DL` (2K) |
| bank F `&B400-&BFBF` | free (3,008 bytes) |
| bank F `&BFC0-&BFE7` | `FJT`, the dispatcher |

The ships' tables are by `GTYPE`: the ship type, 1 to 31 as in the flight
program's `XX21`, whatever blueprint set is loaded (`faces.py` reads all
sixteen, `D.MOA` to `D.MOP`, with the missile, and checks that each type is
the same ship in every set that has it), but 32 for the dodecahedron
station, which is type 2 in half of the sets: the hooks are to pass 32 for
a type 2 with 24 vertices. Type 15 (the rock hermit) is in no set and has
empty tables.

### The interface

The game calls an entry as `LDX #FG_xxx : JSR GCALL` (`gfx-glue.asm`), with
the inputs in A, Y and memory. `GCALL` pages bank F in, enters it through
`FJT` and pages the caller's bank back; it returns A and Y as the entry left
them, and every entry keeps Y. X and the flags are not kept. Not from an
interrupt.

| FG_ | Entry | Inputs |
|---:|---|---|
| 0 | `F_INIT`: once, first: `T_INIT`, empty lists and text map, direct mode (`GMODE` = 0, `GFRONT` = 1) | |
| 1 | `F_DIRECT`: the screen is about to be cleared and drawn on directly (TT66): direct mode, buffer 1 on show, no sights, no beams, no text, no stars | |
| 2 | `F_FRAME`: draw this frame (below) and empty the lists; not in a space view (`QQ11` non-zero), just empty them | `QQ11`, and what `L_SUN` reads: `FRIN+1`, the sun at `K%+NI%`, `ALPHA`, `BETA` |
| 3 | `F_SHIP`: record the ship LL9 is drawing (lit at once from its orientation) | `GTYPE`, `GNF`, `GNV`, `XX2` (each face's visibility: 0 hidden, 255 cull by winding), `XX3` (the projected vertices), `XX4`, `INWK+6/7` (z), the orientation vectors at `INWK+9` to `INWK+26` |
| 4 | `F_LINE`: record a line | `X1`, `Y1`, `X2`, `Y2`; `GLCOL` (a fixed colour index) |
| 5 | `F_DOT`: record a dot: a dash if `ZZ` >= 80, else a double-height dash | Y = x, A = y; `ZZ`, `GDCOL` |
| 6 | `F_PLANET`: record the planet (`TYPE` even) or the sun (odd) as a disc | `K3`, `K4` (centre, 16-bit), `K` (radius), `TYPE`; the planet's `INWK+6/7` (to hide ships behind it) |
| 7 | `F_SHPPT`: record a distant ship as a 2x2 dot in its type's colour | `K3`, `K4`, `TYPE` |
| 8 | `F_PCURVE`: start a planet curve (a meridian, the equator, a crater) | |
| 9 | `F_PPOINT`: its next point (BLINE's), joined to the last by a line | `K6`, `K5+2` (x, y, 16-bit) |
| 10 | `F_CHAR`: a character into the text map at (`XC` - 1, `YC`); the same character again removes it (as the original's EOR) | A = the character (32 to 127); `XC`, `YC` |
| 11 | `F_DELCHAR`: clear a cell of the text map | A = column, Y = row |
| 12 | `F_CLRTEXT`: clear rows of the text map | A = first row, Y = last row |
| 13 | `F_BOMB`: a new energy bomb bolt: drop the bolt recorded before it in this frame | |

Limits per frame: 13 ships (and 2K of ship records), 48 lines, 64 dots, 3
curves with 64 points between them; a record past a limit is dropped. The
stars are recorded by the hooks straight into the mailbox (`R_SX`, `R_SY`,
`R_SS`, entries 1 to `NOST`; `R_SS` = 0 for none). The fixed colour indices
(`FC_*` in `gfx-frame.asm`): 0 black, 1 our beams (yellow), 2 enemy lasers
(magenta), 3 the planet's curves (cyan), 4 particles (yellow), 5 the sights
(cyan), 6 stardust.

The shared variables (`elite-map.asm`) that the game's hooks and the
interrupt use:

* `GMODE` bit 7: space mode (the hooks record); clear: direct mode (the game
  draws on buffer 1, `SCREEN%`, as it always has). `F_DIRECT` clears it, the
  first `F_FRAME` after it sets it.
* `GDRAWON` (0 while the game is erasing: do not record) and `GFORCE`
  (non-zero: draw directly even in a space view): for the hooks only.
* `GSIGHT` (draw the sights), `GLASV` (draw our beams, from `LASX`, `LASY`;
  cleared after each frame).
* `GSTASH` bit 7: something else used the buffers (a disc load): the next
  `F_FRAME` blanks both, as on entering space mode.
* The flip: `F_FRAME` waits for `GFLIP` = 0 before drawing into its buffer,
  then sets `GPEND` = that buffer and `GFLIP` = &FF. At each vertical sync
  the interrupt must, if `GFLIP` is non-zero, set `GFRONT` = `GPEND` and
  `GFLIP` = 0, and show buffer `GFRONT` (buffer 1 in direct mode). Until an
  interrupt does this, a second `F_FRAME` waits for ever.

### A frame

`F_FRAME`: `L_SUN` (the light for the next iteration's ships); save the
game's zero page; clip window 2..253 x 1..191; on the first frame since
direct mode (or with `GSTASH` set) blank both buffers' windows, keeping
buffer 1's border and copying it to buffer 0, `T_RESETBUF` both, and draw
first into the buffer not on show; `T_SETBUF`; wait for the last flip;
`T_STARERASE`, `T_REPAIR`; then, in order, the sun and the planet (each a
filled disc, a span per row from its half-width table, `T_SPAN`, which
marks it dirty too), the planet's curves (`T_LINE`), the lines, the ships far to
near (insertion sort by z; faces flat-shaded and lit, fins and details, a
ship behind the planet skipped, as on the Master), the dots, our beams, the
text (every non-empty cell of the text map, ORed in yellow from the MOS's
font at `&C000`, then each row's extent marked dirty for its 8 lines), the
sights (four `T_LINE`s), the stars; put the zero page back; queue the flip.

### What is not there

* **The disc layer**: the planet's meridians, equator and craters are lines
  over a plain disc, not two-colour bands, and both discs are drawn whole
  every frame.
* **The lens flare, the hangar, LL9B and the briefings** (docked-only
  drawing).
* **Text and sights tracked per buffer**: the Master port drew each cell
  once per buffer and erased it when it changed; here both are redrawn
  every frame (a full text row costs 32 glyphs), which needs no per-buffer
  state.
* The Master port's ACCCON paging (the Model B sees both buffers).

### The test

`6-harness/test_frame.py` builds banks R and F and runs them on py65's NMOS
6502: main RAM with the glue (`GLUE.bin`), the bank numbers and the game's
variables at the flight program's addresses; `&8000-&BFFF` paged by ROMSEL
(`&FE30`) between the game's home bank, bank R and bank F; the MOS ROM at
`&C000`. Every entry is called as the game will call it, `LDX #n : JSR
GCALL` from main RAM with the home bank paged. Three synthetic frames
(ships with their real faces, projected from the blueprints; the sun and
the planet; a curve; lines, dots, a distant ship, stars, text, the sights
and the beams) check that nothing is written outside the renderer's zero
page, the stack, the buffers, `&7E00-&7EFF`, the glue's two bytes, `&F4`,
ROMSEL and banks R and F; that the zero page and Y are kept and the home
bank paged back after every call; the blanking and the border on entering
space mode; the flip handshake; what was drawn (the discs' colours, the
ships, the glyphs, the sights, nothing on the border); and the repair:
buffer 0 after one scene and then another is byte for byte buffer 0 after
the second alone. It writes the frames as PNGs (`--png DIR`, default
`3-assembled-output`) to look at. `F_FRAME` takes about 300K to 380K cycles
for these scenes (820K for the first frame, which blanks both buffers).

## The game's side

### Record mode

In a space view (`QQ11` = 0) the flight code's drawing is *recorded* for
the frame layer instead of drawn, unless `GFORCE` is set (only `HFS1`, the
launch and hyperspace rings, sets it: they are drawn directly, on buffer
1). `RECM` (home bank) returns `A` = `QQ11` OR `GFORCE`, zero in record
mode. Outside a space view the game draws on buffer 1 (`SCREEN%`) as
before, in direct mode. The docked code is unchanged: it never records, and
`PCLI` switches the renderer to direct mode (`F_DIRECT`) whenever it loads a
program.

### What record mode skips, and the reference's patch

In record mode the game skips its drawing and the drawing's own
bookkeeping: the ship line heap and the clipping of its lines, the
planet's outline and the clipping and heap of its curves, the erasing of
the sun's and the planet's old lines, and our lasers' lines. What is real
game state still runs: the sun's rows (which take random numbers for the
fringe), the explosion clouds (likewise), byte #31's bits.

One thing in the original depends on what the drawing leaves behind: the
altitude (`ALTIT`, in the main flight loop at `MA93`) is `SQRT(R Q)` with
`Q` left over from whatever ran last, which a trace of the gate's run
shows is `LOIN`'s division about two times in five. So the port sets
`Q = 0` before that `JSR LL5` (`LDA #0 : STA Q`), and the gate's reference
gets the same patch: the harness applies the named patch `ma93-q`
(`6-harness/blib.mjs`, `PATCHES`; listed in the reference's `build.json`)
as a hook at the reference's `JSR LL5` after `MA93`, which it finds by
its bytes (`STA R`, `JSR LL5`, which must be there exactly once) and at
which it sets `Q` to 0. Without it, a record mode that skips the line heap
diverges on `ALTIT` (at iteration 2,864 of the gate's run). The altitude
the patched game shows can differ from the original's by one unit.

(The first version of the renderer's integration kept the bookkeeping
instead, with `VLOIN` working out each line's `LOIN` division, which cost about
54,000 cycles an iteration.)

### The hooks

| Where | Bank | In record mode |
|---|---|---|
| `TT100`, `DEATH` (`JSR MFRAME`) | home | after each `M%`, `F_FRAME`: the frame is drawn into the buffer not on show, and shown at the next flip (A, X, Y and the flags as `M%` left them: the main loop's `DORND` reads C) |
| `ESCAPE` | cold | after each `LL9`, `F_FRAME` |
| `LL9` part 9 (`EE31`), `HEE31` | home, cold | the ship is recorded (`F_SHIP`, with its faces and vertices, read from the blueprint in the home bank), and its laser beam if it fires (`F_LINE`, clipped by `LL145`); byte #31 is left as `EE31` leaves it, and `LL9` returns without building the heap |
| `LL155` | home | returns at once, with C set |
| `SHPPT` | home | the distant ship's dot is recorded (`F_SHPPT`) |
| `DOEXP` (`PTCLSE`), `PTCLS` (`HDOT`) | home | the old cloud is run again with `GDRAWON` = 0, recording nothing; each particle of the new one is recorded (`F_DOT`) |
| `PIXEL2` (`PX2`, `px24r`) | home | star `Y` is recorded straight into the mailbox (`MB_SX`, `MB_SY`, `MB_SS`; size 1, 2 or 3 by `ZZ`, as `PIXEL` draws it), or marked absent if it is off screen |
| `SUN` (`HLS`, `HL2S`) | home | the sun is recorded as a disc (`F_PLANET`); its rows are worked out as before (they take random numbers), but not drawn |
| `WPLS` | home | the sun's heap is emptied, nothing erased |
| `CIRCLE` | home | the planet is recorded as a disc (`F_PLANET`), and `CIRCLE` returns as `CIRCLE2` would (FLAG = 0, C clear) |
| `PLS22`, `BLINE` | home | a new curve (`F_PCURVE`), and each point (`F_PPOINT`), without the clipping and the heap |
| `WPLS2` | home | the heap is reset, nothing erased |
| `LASLI`, `LASLI2` | home | `GLASV` is set (the frame draws the beams from `LASX`, `LASY`); nothing to draw or remove |
| `MA93` | home | (every mode) `Q = 0` before the altitude's `JSR LL5`; the reference is patched to match |
| `SIGHT` | cold | `GSIGHT` is set to the laser power, `QQ19` as `TT15` leaves it |
| `TTX66` | cold | (every mode) `F_DIRECT`: direct mode, buffer 1 on show, text map cleared |
| `TT26` (`RR3`) | cold | (every mode) the character goes into the text map (`F_CHAR`); in record mode it is not drawn |
| `CLYNS` | cold | (every mode) rows 21 and 22 of the text map are cleared (`F_CLRTEXT`); in record mode the screen is not touched |
| `HFS1` | cold | sets `GFORCE` while it draws the rings |
| `LOMOD`, `DEATH2` | cold, home | `CATD` is called with DFS's workspace put back at `&1000` (`dfsin`) and kept afterwards (`dfsout`), as `PCLI` does, as buffer 0 is drawn over it |

To make room in the flight code's home bank for these, `CLYNS` and `LYN`,
and the rarely run parts 1, 3 and 4 of the main game loop and 9 and 10 of
the main flight loop, moved to the cold bank (`MA61`'s `BNE MA26`, always
taken, became a `JMP`, as `MA26` stays in the home bank).

### The buffers and the flip

The rupture's interrupt (`IRQG`, `elite-resident.asm`) shows buffer
`GFRONT` (0: `BUF0`, 1: `SCREEN%`) in each frame A, and at its point 1 (the
start of frame B, the dashboard) carries out a pending flip: `GFRONT` =
`GPEND`, `GFLIP` = 0. `PCLI` sets `GSTASH` at every disc command (the staging
area and DFS's workspace page are in buffer 0), so the next frame blanks
both buffers. The dashboard, in its own memory at `PANEL%`, is drawn
directly in every mode.

### The test

`6-harness/test_routines.py` runs the port's routines with `GFORCE` set,
so that the drawing paths are compared with the original's, pixel for
pixel; the gate's run (record mode, in flight) compares the game's state
with the original's at every iteration, which checks that the record mode
leaves everything as the original's drawing does.

## Speed

The gate's run, 10,000 iterations: 254,590 cycles per flight iteration,
7.86 flight iterations per second, against the original's 168,749 and
11.85 (0.663 times). By scene (`6-harness/bscenes.mjs` records each
iteration's time and the planet's, the station's and the ships' positions
in a build's run; `6-harness/scenes.py` compares two such runs, counting a
flight iteration in the front view that both put in the same scene):

| Scene | Iterations | The original | The port | Against the original |
|---|---:|---:|---:|---:|
| Open space: the planet at 512 x 256 or more, no station within 64 x 256, no ships | 270 | 103,168 cycles, 19.39 it/s | 146,463 cycles, 13.66 it/s | 0.70 |
| Planet close: the planet ahead, nearer than 128 x 256 | 1,032 | 146,033, 13.70 | 182,610, 10.95 | 0.80 |
| Station close: the station ahead, nearer than 16 x 256 | 706 | 187,528, 10.67 | 337,173, 5.93 | 0.56 |
| Ships about | 2,662 | 169,996, 11.77 | 222,598, 8.98 | 0.76 |

### Where the time goes

A profile of the first 3,000 iterations (`bprofile.mjs`; mostly fighting
near the planet, then a hyperspace jump and an approach), per flight
iteration, at the renderer's first commit (345,647 cycles): bank R
155,899 (the rasteriser), bank F 33,125 (the frame layer), main RAM 43,264
(of which the trampolines into bank R about 25,600 and the far calls about
8,000), the flight code's home bank 91,419, its cold bank 8,613, and the
MOS (the interrupts) 13,327. In bank R: the row runs 37,217 (the stores of
spans, polygons and the repair), `r_pgfix` 28,055, the repair's row code
22,569, polygons about 34,000, lines about 20,000.

* **`r_pgfix`.** The row runs are unrolled stores assembled for buffer 1;
  each time a run page is used for the other buffer, its 63 stores'
  addresses are patched. With a flip every frame, every page in use is
  patched every frame. Two sets of runs would end this, but bank R has no
  room for a second set (4.5K).
* **Everything is drawn every frame.** The Master port's disc layer (which
  drew only the rows of the planet that changed) did not fit in bank R, so
  the sun and the planet are filled whole every frame, and the repair
  blacks last frame's whole disc first. A trim of the repair inside a
  square that the new disc covers (`R_REPAIR` repairing only the parts of a
  row's dirty extent outside it) was tried: two repairs of a row cost more
  than they saved for discs of the sizes the frames draw, and it was
  dropped.
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
