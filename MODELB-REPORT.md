# Filled colour Elite for the BBC Model B with 64K of sideways RAM: report

Branch `modelb-port` in `~/elite-modelb` (nothing pushed). It is a series of
commits on Mark Moxon's annotated source of BBC Micro disc Elite (the
Stairway to Hell release), following the BBC Master port's three-part
structure. The playable disc is `5-compiled-game-discs/elite-modelb.ssd`
(80 tracks, boots with SHIFT-BREAK on a Model B with DFS and four banks of
sideways RAM). The documentation is in `docs/` (README, memory-map,
modelb-memory, speedups, renderer) and `6-harness/README.md`.

## What was built

1. **The memory map (part 1).** Both programs, flight (`D.CODE`) and docked
   (`T.CODE`), moved out of main RAM into sideways RAM: each has a *home*
   bank (paged whenever it runs) and a *cold* bank (reached by far calls),
   with every routine kept in the original's source order and tagged by
   area in its header (`\       Area: cold`). `streams.py` emits the
   per-area sources and the far-call stubs; `bankcheck.py` enforces the
   rules (no cold code reading blueprints or home data). The loader finds
   the four banks (`PROBE`), and `PCLI` interprets the original's disc
   commands, loading each image through a staging area. The original's
   swap of programs at launch, dock and death is kept.
2. **The speed-ups (part 2).** Twenty game-logic speed-ups, one idea per
   commit, most from the Master port (quarter-square multiplication, the
   keyboard scan, unrolled divisions, the stardust loop), all keeping the
   original's wireframe pixel for pixel.
3. **The filled renderer (part 3).** A four-colour MODE 1 screen with the
   dashboard below it on a CRTC rupture, then the Master port's filled
   renderer rewritten for the NMOS 6502 in two banks: the rasteriser (bank
   R) and the frame layer (bank F), double-buffered in main RAM (buffer 0 at
   `&1000`, buffer 1 at `&4000`, the dashboard at `&7000`). In a space view
   the flight code records what it would draw; each main-loop iteration the
   frame layer draws the frame (lit, flat-shaded ships far to near; the sun
   and the planet as discs, the bigger kept from frame to frame by a disc
   layer in the flight code's cold bank, with a crater planet's crater as a
   dark band and a meridian planet's meridians as lines; stars,
   particles, beams, sights and text) into the buffer not on show and the
   interrupt flips. Everything else (charts, the launch and hyperspace
   rings, the docked code) draws directly on buffer 1 in colour.

## The commits, by part

Part 0, the harness: `ab7aecf` the determinism harness and gate, `331dd13`
build without the copy protection's checksums.

Part 1, the layout: `b5284ea` lay the game out in sideways RAM, `838e4a1`
remove unreachable code and unused tables, `9182bd2` document and refresh.

Part 2, the speed-ups (cycles per flight iteration after each, from the
gate): `c447640` MU11 (165,976), `a252ffe` FMLTU (159,564), `b319039` MULT1
(158,783), `d098a31` MULTS (157,517), `94cda78` dashboard indicators to the
cold bank (158,763), `0543444` MLTU2 and MULT3 (156,846), `30f9a3c` RDKEY
(151,562), `e46093c` LL28 (150,881), `c01b4ed` DVID4 (148,008), `4a7e8cc`
DVID3B2 (147,305), `d244586` TT26 to the cold bank (147,101), `4b4b7fe`
the bank profile (no code change), `a65d78d` fighting routines to the cold
bank (147,099), `6673f46` ADD's MU8 and MULT1 (145,180), `5bbe4d3` MVS4
(144,617), `c863540` LL5 (144,468), `199f9f8` LL38 (144,450), `e1188bb`
TIS2 (144,377), `37e3807` the stardust loop (139,778), `0733051` BLINE
(138,793), `55c8dc4` PIX1 and PIXEL2 (138,688), `c6ec142` the pitch and
roll bars (137,864), `37659c2` document and refresh.

Part 3, the renderer:

| Commit | What | Gate |
|---|---|---|
| `f47c76e` | the four-colour MODE 1 screen with the dashboard, colour wireframes | PASS, 146,023 |
| `22d8b76` | the last saved commander and the break handler into resident block A (main RAM from `&1000` freed) | PASS, 146,023 |
| `c21349f` | DFS's workspace page kept across disc commands (`dfsin`, `dfsout`), for buffer 0 | PASS, 145,902 |
| `792b52b`, `db413cf`, `88d1891`, `c20e759`, `c651a19` | the NMOS tools; the rasteriser as bank R and its pixel-for-pixel test (not yet used) | PASS, 145,902 (at `c651a19`) |
| `557d0a2` | the CRTC rupture splitting the dashboard from the screen | PASS, 147,400 |
| `ade459e` | the quarter squares into the flight home bank; the wireframe drawing and the clipper to the cold bank | PASS, 172,638 |
| `244047e`, `5fda535`, `d3a9586`, `07102dc`, `4db0266` | the faces and lighting tables; the shared variables and glue; the frame layer as bank F, its test and docs (not yet used; the game's binaries unchanged) | PASS, 172,638 (at `4db0266`) |
| `53bef68` | the glue in resident block A | PASS, 172,638 |
| `1b1c8a9` | the loader loads banks R and F; the interrupt shows the frame layer's buffer and flips | PASS, 172,965 |
| `f4bdd51` | the space view drawn through the filled renderer | PASS, 322,228 |
| `270e60a` | a disc row filled and marked in one call; the clipper's first part back home | PASS, 308,463 |
| `76f97e4` | documentation of part 3 | (docs only) |
| `d1d23c1` | the assembled output and the disc refreshed | PASS, 308,463 |
| `4c6b936` | record mode's line bookkeeping dropped, with `Q` = 0 at the altitude in both the port and the (patched) reference | PASS, 254,590 |
| `828b473` | a run page checked once per buffer, and patched without clearing the carry | PASS, 247,931 |
| `48c5bfa` | the lens flare, in bank F | PASS, 247,951 |
| `edad30d` | the docked code's title, hangar and briefings as filled frames | PASS, 247,961 |
| `9bfefc3` | documentation of the flare, the docked frames and the banks; the output refreshed | (docs and output) |
| `c3e3f30` | the disc layer, in the flight code's cold bank; the big planet and sun close scenes | PASS, 226,316 (gated at `e0c1610`, the same binaries before the last comments and docs) |

## Gate results by part

The gate (`6-harness/verify.sh`) builds, runs the routine-equivalence tests
(py65), bank R's and bank F's tests, flies the original and the build side
by side for 10,000 main-loop iterations with a deterministic pilot (three
launches, a docking, three hyperspace jumps, twelve engagements, seventeen
kills, an escape pod) and requires the game state to be byte for byte the
original's at every iteration; then the redock, savetest and views
regressions.

* Part 1: PASS, game state and the screen identical at every iteration;
  168,533 cycles per flight iteration (11.87 it/s against 11.85).
* Part 2: every commit PASS, game state and screen identical (from
  `6673f46` the drawing temporaries are left out, as the port's arithmetic
  leaves them differently; the screen was still compared); end 137,864
  cycles, 14.51 it/s, 1.224 times the original.
* Part 3: every commit PASS with the loose comparison (the game state
  without the drawing's temporaries and line heaps; from the colour screen
  on the screen is no longer compared with the original's). Saved
  commander files byte for byte the original's throughout.

## Speed

| | Flight it/s | Against the original | Cycles per flight iteration |
|---|---:|---:|---:|
| The original | 11.85 | 1.000 | 168,749 |
| End of part 1 | 11.87 | 1.001 | 168,533 |
| End of part 2 | 14.51 | 1.224 | 137,864 |
| End of part 3, first | 6.48 | 0.547 | 308,463 |
| After the bookkeeping went (`4c6b936`) | 7.86 | 0.663 | 254,590 |
| `48c5bfa` | 8.07 | 0.681 | 247,951 |
| Now, with the disc layer (`c3e3f30`) | 8.84 | 0.746 | 226,316 |

By scene, over the gate's run (front-view flight iterations classified by
the game state, the first class that fits; `6-harness/bscenes.mjs` and
`scenes.py`), against the original (patched as below). The scenes were
redrawn for the disc layer: "big planet" and "sun close" are new (the big
discs had been in an unclassified remainder), so the iteration counts
differ from earlier tables:

| Scene | Iterations | Original | `9bfefc3` (before) | `c3e3f30` (now) | Ratio now |
|---|---:|---:|---:|---:|---:|
| Station close (ahead, z below 16 x 256) | 706 | 10.67 it/s | 6.00 | 6.01 | 0.56 |
| Sun close (ahead, z below 1,024 x 256) | 402 | 11.82 it/s | 9.00 | 9.02 | 0.76 |
| Planet close (ahead, z below 128 x 256) | 1,032 | 13.70 it/s | 11.10 | 11.16 | 0.81 |
| Big planet (ahead, z 128 to 512 x 256) | 6,681 | 11.03 it/s | 7.36 | 8.35 | 0.76 |
| Open space (planet far, no ships, no station near) | 270 | 19.39 it/s | 13.94 | 13.55 | 0.70 |
| Ships about (the rest) | 745 | 14.50 it/s | 11.87 | 11.70 | 0.81 |

(The "planet close" scene, the planet ahead nearer than 128 x 256, draws
few disc rows, 7.6 a frame on average: so close, the planet is mostly off
the screen or not drawn. The big discs, 100 to 190 rows a frame, are in
"big planet".)

The filled port is about three quarters as fast as the original wireframe
game. The speed-ups of part 2 are kept, but each frame is drawn (all of
it but the bigger disc) on the same 2 MHz CPU. A profile (docs/renderer.md, "Speed") put about 156K
cycles an iteration in the rasteriser, before the bookkeeping went. Of
that, about 26K goes to re-patching the unrolled row runs for the other
buffer at every flip, and about 26K to the trampolines into bank R.

## The reference's patch

Since `4c6b936` the gate's reference, the original disc, runs with one
patch, applied by the harness (`6-harness/blib.mjs`, `PATCHES`, named in
`4-reference-binaries/sth/build.json`):

* **`ma93-q`**: at the main flight loop's altitude check (`MA93`: `STA R`,
  `JSR LL5`), `Q` = 0 before the square root of `R Q`. The original leaves
  in `Q` whatever ran last, usually `LOIN`'s division (two times in five in
  a trace of the gate's run), so its altitude depends on what it drew. The
  port's source has `LDA #0 : STA Q` there. The harness finds the
  reference's `STA R`, `JSR LL5` after `MA93` by its bytes (it must be
  there exactly once, or the run fails) and sets `Q` to 0 when the `JSR`
  runs; `LL5` reads `R` and `Q` first and no register, so this is the
  port's two instructions. The altitude can differ from the unpatched
  original's by one unit. No other state diverged once the record mode
  stopped working out the original's lines (game state identical at all
  10,000 iterations).

## The alternate-column fill: evaluated, not adopted

The idea: instead of re-patching each unrolled row run for the other
buffer at a flip, keep for each buffer a run that stores every other byte
column (stride 16 bytes), half the length, so that both fit in a page;
a span calls it twice, once indexed by the row (even columns) and once by
the row + 8 (odd columns). Measured first, over the gate's run (counters on
bank R, per flight iteration):

| Scene | `r_pgfix` calls | pages patched | patching, cycles | run calls | bytes stored by runs |
|---|---:|---:|---:|---:|---:|
| Open space | 72.8 | 8.4 | 12,952 | 71.8 | 729 |
| Planet close | 61.3 | 8.1 | 12,149 | 59.4 | 608 |
| Station close | 144.4 | 15.1 | 23,901 | 273.0 | 6,717 |
| Ships about | 122.1 | 11.8 | 19,081 | 123.4 | 2,044 |
| All | 190.8 | 15.0 | 25,873 | 201.3 | 5,740 |

(patching = pages patched x about 1,155 cycles + calls x about 45.) The
runs take 24 pages x 191 bytes (4,584); the two-buffer alternate-column
runs take 24 x 195 (4,680), which fitted after moving three run pages'
tails (R_SETBUF's high-byte tables and `R_SPAN`) and putting a second
256-byte offset table in the free room after `R_LINE`'s cold part. It was
built (`r_rcols`, used by the spans, the polygons' phase B and the repair),
and passed bank R's pixel-for-pixel test, bank F's test and the gate's
state comparison, but the gate's run took **257,536** cycles per flight
iteration against **254,590**: slower. The second call, the two entry and
two plant look-ups, the buffer's offset and the two plant and unplant pairs
(through `(zp),Y` on the NMOS 6502) add about 120 cycles to each of the
200 to 235 run calls an iteration (the two counts are over the whole run
and over its first 3,000 iterations), more than the 25,900 that patching
cost. A
tightened version (one plant when both halves end at the same store, the
call inlined) would still add about 80 cycles a call, for a gain of a few
thousand cycles at most. It was reverted.

What would do better, without its cost per span: checking the page's tag
inline in `r_rowset` instead of calling `r_pgfix` for every row (about 30
of the 45 cycles a call, so about 5,700 an iteration), and a patch loop
that sets the carry once (the additions never carry into or out of the
next) for about 130 of the 1,155 cycles a page. A second full-length copy
of only the most used rows' runs, if bank R has room after its cold parts
move out, would take a share of the rest.

## Bank R, the disc layer, the flare and the docked screens

Work queued after the two evaluations above, in the order asked:

1. **Moving bank R's cold parts out, to free it for hot code.** Not done:
   with the alternate-column fill slower, nothing on the hot path wanted
   the room, and what is cold in bank R mostly cannot leave it. `R_INIT`
   and `R_RESETBUF` work on bank R's own state, so they must run with bank
   R paged; `R_LINE`'s cold part is reached from `R_LINE`. Bank R's free
   space instead took the patching speed-up (`828b473`, which filled the
   high region) and two small entries (`R_SPANM` earlier, `R_MARKBOX` for
   the flare).
2. **The disc layer** (the Master port's `R_DISCROWS`, two-colour shaded
   discs updated row by row, with boundary arrays for both buffers): does
   not fit. Its window is about 4K of code, its arrays about 3K (the
   boundaries and the disc spans, per buffer), and on the Master it takes
   its per-row inputs from the frame layer through shared memory; bank R
   has under 400 bytes free and the Model B has no main RAM to share
   between banks F and R. A lighter version was built and measured instead:
   one plain disc kept on the screen from frame to frame (`R_DISCROW` in
   bank R, 293 bytes after `R_LINE`'s cold part; the frame layer keeping
   each buffer's spans, 1K in bank F), filling only what changed and what
   the repair blacked. It passed bank F's test (a new one: the planet
   moving alone over five frames, buffer 0 byte for byte the planet drawn
   alone) and the gate's state comparison, but it was slower: 259,111
   cycles per flight iteration against 247,931, and slower in every scene
   (`other`, with the biggest discs, 295,885 against 280,380). The planet's
   meridians and craters are lines over the disc, which dirty most of its
   rows each frame, so most of the disc is repaired and repainted anyway,
   and a call per row costs more than the old whole-row fill. It was
   reverted; the test stayed (`382af78`). The disc layer was then built
   in the flight code's cold bank instead (`c3e3f30`, next section).
3. **The lens flare**: back (`48c5bfa`), in bank F, pixel for pixel the
   Master model's.
4. **Filled docked screens**: the title, the hangar and the briefings are
   frames (`edad30d`). The title and the hangar were looked at; the
   briefings were not (no mission was run).

## The disc layer in the flight code's cold bank

Asked: the Master port's two-colour disc layer, made NMOS, with its code
and per-buffer arrays in the flight code's cold bank (7,558 bytes free),
its row changes queued as commands, bank R paged in only now and then to
drain them, and single edge bytes written directly where that pays.

**Measured first.** With the frame layer's disc drawing cut out (a
measurement build of `48c5bfa`, `f_discs` returning at once), the cycles per
iteration by scene: big planet 271,614 with the discs, 148,036 without
(the discs, filled and repaired, were 45% of those frames); ships about
168,471 and 138,909; open space 143,503 and 121,197; station close
332,277 and 315,975; planet close 180,108 and 170,016; sun close 220,362
and 222,122 (the sun close frames draw no disc). A profile of the big
planet frames put 87K cycles a frame in the discs' spans and 66K in the
repair.

**Built** (`c3e3f30`, `gfx-dlayer.asm`, 6,066 bytes of the cold bank: 2.9K
of code, records and state, and 11 page tables). The bigger of the sun and
the planet is kept on each buffer from frame to frame, not marked dirty.
Each frame `DL_FRAME` (a far call from bank F, after the repair) gets the
repair's extents from bank R twenty rows at a time (`T_GETW`, into the
mailbox), compares each row's new span and crater band with what the disc
left on that row of this buffer, blacks what the disc left and fills what
changed or was repaired. As the screen is main RAM, it writes all of
that itself (a byte with both masks, or the end bytes masked and the
middle through an unrolled run): the queue to bank R's row runs
(`T_DRAINQ`, nine spans at `MBOX + &28`) is there for spans over 32
bytes, which no disc the frames draw needs, so bank R is paged in only for
the extents, ten times a frame for a full-screen disc. A disc two frames
unchanged on its buffer only refills what the repair blacked. A disc with
a radius under 40 is drawn whole each frame and marked dirty (the marks
queued for bank R the same way), as small discs move about and keeping
them cost more. Bank R's side is 113 bytes (`R_GETW`, `R_DRAINQ`).

* **The painter's order and the repair.** The layer draws first, after the
  repair, so ships, lines, text and sights go over it; whatever they cover
  is repaired black on that buffer's next frame and refilled by the layer
  from the repair's extents. The other disc, if both are recorded, is bank
  F's as before, drawn whole over the layer's: so where a smaller sun
  overlaps a bigger planet it shows in front of it, even when it is
  behind (before, the sun was drawn first).
* **Surface detail.** As the Master port draws a planet without meridians,
  a crater planet's crater is a band of the Master's dark crater colour
  across the disc (the closed ellipse that `PLS22` works out, recorded
  into the cold bank, `DL_CURVE`/`DL_POINT`); a meridian planet's meridians
  and equator are still lines over a plain disc (the beach ball is the next
  task). The sun is the same plain dithered disc as before.
* **Steps and their gates** (cycles per flight iteration, the gate's run):
  the first working version, which tracked every row, 249,521 (slower
  than 247,961: rows that only moved their ends cost about 1,000 cycles
  each); a fast path for rows with no band or repair, and the static disc's
  repair-only path, 237,834; the hot variables in the frame layer's zero
  page and the band's tables skipped when there is no band, 232,629; the
  unrolled middle bytes, and small discs drawn whole, 226,316.
* **Speeds** by scene, before (`9bfefc3`) and after: big planet 7.36 to
  8.35 it/s (271,629 to 239,431 cycles), planet close 11.10 to 11.16,
  sun close 9.00 to 9.02, station close 6.00 to 6.01, open space 13.94 to
  13.55 and ships about 11.87 to 11.70. The last two lose 3% and 1%: their
  planet is small and moving, the case the layer helps least, and every
  frame now makes a far call to the cold bank and its row bookkeeping for
  the disc's rows. Over the gate's run, 247,961 to 226,316 (8.07 to 8.84
  it/s, 0.681 to 0.746 of the original).
* **Checked**: bank F's test draws eight discs (on and off the screen's
  edges, the sun and the planet as the layer and over it, craters partly
  off the screen and with points far outside it) and compares every
  pixel with a Python model of the layer, and flies a 23-frame sequence on
  both buffers (moving, growing and still discs, the sun taking over, no
  disc, small discs and back, ships and lines over them), each frame's
  buffer byte for byte the same scene drawn on a fresh machine. The gate
  passes. Two big-planet frames with craters were looked at.
* **Free space after**: the flight code's home bank 230 bytes (the hooks
  and their far calls took 45), its cold bank 1,492, bank R 6, 0 and 229
  (after `R_LINE`'s cold part and the two new entries), bank F 1,728, the
  glue 3 (the two trampolines took 8), resident block A 13, the high
  resident block 15; `GVARS` is full (`GDL`, which buffers hold the
  layer's disc, took the last byte). The docked code's banks are
  unchanged (4,484 and 5,756).
* **The harness**: `scenes.py` gained the big planet and sun close
  scenes; the bank map now lists the labels of files that a cold block
  INCLUDEs (without that, the pilot read a key wait in the home bank as a
  call from the disc layer's code at the same address, and the run
  diverged).

## Compromises

* **The beach ball is not drawn.** A meridian planet's meridians and
  equator are cyan lines over a plain dithered disc, not two-colour bands;
  a crater planet's crater is a dark band (the disc layer, above), except
  when the sun is the bigger disc and the planet is drawn whole over it
  without its crater.
* **The altitude's leftover `Q` is defined.** The original's altitude takes
  a square root of `R` and of whatever its drawing left in `Q`; the port
  sets `Q` = 0 there, and the gate's reference is patched the same way
  (above), so that the record mode need not work out the original's lines.
* **The dashboard** is the original's, doubled to the four-colour screen and
  recoloured (red to magenta, green to cyan), not the Master port's design.
* **Palette effects are not reproduced**: the hyperspace rings' mode change
  (`HFX`) and the colour flashes; the palette is fixed (black, cyan,
  magenta, yellow).
* **Text and sights are redrawn every frame** from the frame layer's text
  map, not tracked per buffer.
* **The disc is 80 tracks** (520 sectors: the renderer's two banks add 128).
* **Key presses**: at a few frames a second near a large station a very
  short key press can fall between two keyboard scans (the redock test now
  holds the docking computer's key for a second).
* **The redock test's limit** went from 120 to 300 emulated seconds per
  docking, for the slower flight.

## Not verified

* **Real hardware.** Everything ran in jsbeeb (Model B, DFS 1.2, 8271), headless.
  The CRTC rupture's timing, the 80-track disc and real sideways RAM
  boards (the loader's `PROBE`) are untested on a real Model B.
* **The picture is not gated.** In part 3 the gate checks the game state,
  not the screen. A bug in the bank-loading commit (the high resident
  block copied after the loads had overwritten its source, so the palette
  and the rupture's registers were garbage) passed its first gate. It was
  found from screenshots and fixed by amending that commit. The renderer's
  output was checked by eye only on a sample of screenshots (the launch,
  the planet, the station in the rear view, the side view, the charts, the
  hyperspace rings, the docked screens of the savetest, the title and
  the hangar), and by bank R's and bank F's py65 tests (and the flare
  against the Master's model).
* **Not looked at on screen**: the energy bomb, the escape pod's flight, the
  death screen, witchspace and Thargoids, the missions and their
  briefings (now frames), the joystick. The
  escape pod and the death sequence run in the gate's state comparison
  (an escape is in the pilot's run), not visually.
* **The frame layer's five commits** (`244047e` to `4db0266`) leave the
  game's binaries unchanged. They were gated as one, at `4db0266`, not
  one by one (PASS, as the table above shows).
