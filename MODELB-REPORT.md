# Filled colour Elite for the BBC Model B with 64K of sideways RAM: report

Branch `modelb-clean` in `~/elite-modelb` (nothing pushed). It is a series of
commits on Mark Moxon's annotated source of BBC Micro disc Elite (the
Stairway to Hell release), following the BBC Master port's structure: the
harness, the memory map, the speed-ups, the renderer, the three passes and
the Master's renderer. The playable disc is `5-compiled-game-discs/elite-modelb.ssd`
(80 tracks, boots with SHIFT-BREAK on a Model B with DFS and four banks of
sideways RAM). The documentation is in `docs/` (README, memory-map,
modelb-memory, speedups, renderer) and `6-harness/README.md`.

## Status

* **Gate** at the head of `modelb-clean`: VERIFY PASS 11.85 13.17 1.111
  151896.6 (game state identical to the original's at all 10,000
  iterations; regressions: redock, savetest, views, screens).
  Disc: `5-compiled-game-discs/elite-modelb.ssd`.
* **Not yet in**: the planets' surfaces (the circle engine's beach ball and
  craters: `make circles=on`) need 1,642 more bytes of flight bank 4 than
  there is. Planets are plain discs. The kept solid rows of the Master port
  (docking) are not in either. Both wait on a decision about memory (the
  dashboard's resolution, or the other options in the coordinator's
  table).
* **Free space** (flight): bank 4 904 bytes, bank 7 27, bank 6 305, bank 5
  43/56/260, main RAM part 23, the glue 7. Docked: bank 4 3,844, bank 7
  4,732.

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
4. **The Master's renderer (part 4).** Each program is emitted in three
   passes, low, hot and cold, by its routines' `Area:` tags, as the Master
   port does; then the Master port's current renderer, hand-converted to
   the NMOS 6502: its rasteriser in bank 5 (one set of row runs, patched
   for the buffer drawn), its frame layer in bank 6 (frame-time
   projection, explosion clouds, the text map, the lens flare, the hangar,
   the title and the briefings), its disc layer in bank 7 after the flight
   code's cold pass (every disc incremental, with three boundaries a row
   and the second disc), the sun near the planet (`S_SUN`), and the
   lighting in each program's home bank against the only copy of the
   quarter squares. To make room: the blueprints without their edge lists,
   the flight code's event-only cold code in two disc overlays, and the
   renderer's data for each ship type loaded with its blueprint set.

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
| `c3e3f30` | the disc layer, in the flight code's cold bank; the big planet and sun close scenes | PASS, 226,316 |

Part 4, the Master's renderer (gate: cycles per flight iteration):

| Commit | What | Gate |
|---|---|---|
| `28cb34d` | each program emitted in three passes (low, hot, cold) by its routines' `Area:` tags, the hot pass flowed into bank 4 and main RAM | PASS, 226,092 (8.85 it/s) |
| `7711036` | the disc layer in bank 7's renderer window, after the cold pass | PASS, 226,026 (8.85 it/s) |
| `24cbc63` | ship blueprints without their edge lists: the slot shrinks by 768 bytes | PASS, 225,954 (8.85 it/s) |
| `5cd0dcd` | the main RAM part after the missile's blueprint; the low pass; the 25 fps cap | PASS, 226,067 (8.85 it/s) |
| `4432b88` | bank 5: the Master port's rasteriser in hand-converted NMOS code, one set of row runs patched per buffer | PASS, 222,629 (8.98 it/s) |
| `3adb7f3` | one dashboard expansion table; the main RAM part's image in the slot; the hangar's lines gone | PASS, 222,723 (8.98 it/s) |
| `a80a587` | the flight code's event-only cold code in two disc overlays; the screens regression | PASS, 222,803 (8.98 it/s) |
| `832b813` | bank 6's sources and image named for the bank | PASS, 222,803 (8.98 it/s) |
| `b95a4ee` | bank 6: the Master port's frame layer; the lighting in the home bank against the only quarter squares | PASS, 201,634 (9.92 it/s) |
| `beff464` | the normals and face lists loaded with each blueprint set | PASS, 201,979 (9.90 it/s) |
| `2f1d7b1` | the Master port's disc layer, its row code in bank 7, every disc incremental | PASS, 150,651 (13.28 it/s) |
| `ac2ab4a` | the sun near the planet, `S_SUN`, in bank 6 | PASS, 151,897 (13.17 it/s) |

## Gate

The gate (`6-harness/verify.sh`) builds, runs the routine-equivalence tests
(py65), bank 5's and bank 6's tests, flies the original and the build side
by side for 10,000 main-loop iterations with a deterministic pilot (three
launches, a docking, three hyperspace jumps, twelve engagements, seventeen
kills, an escape pod) and requires the game state to be byte for byte the
original's at every iteration; then the regressions: redock, savetest,
views, and the flight screens (status, data, chart, market, inventory),
which load and swap the overlays.

* Part 1: PASS, game state and the screen identical at every iteration;
  168,533 cycles per flight iteration (11.87 it/s against 11.85).
* Part 2: every commit PASS, game state and screen identical (from
  `6673f46` the drawing temporaries are left out, as the port's arithmetic
  leaves them differently); end 137,864 cycles, 14.51 it/s.
* Parts 3 and 4: every commit PASS with the loose comparison (the game
  state without the drawing's temporaries and line heaps). Saved commander
  files byte for byte the original's throughout.

## Speed

| | Flight it/s | Against the original | Cycles per flight iteration |
|---|---:|---:|---:|
| The original | 11.85 | 1.000 | 168,749 |
| End of part 2 (wireframe, sped up) | 14.51 | 1.224 | 137,864 |
| End of part 3 (the first filled renderer) | 8.84 | 0.746 | 226,316 |
| Now | 13.17 | 1.111 | 151,897 |

By scene, over the gate's run (front-view flight iterations classified by
the game state; `6-harness/bscenes.mjs` and `scenes.py`):

| Scene | Iterations | Original | Now | Ratio |
|---|---:|---:|---:|---:|
| Open space | 270 | 19.39 | 21.03 | 1.085 |
| Planet close | 1,032 | 13.70 | 14.09 | 1.029 |
| Big planet | 6,681 | 11.03 | 13.38 | 1.212 |
| Sun close | 402 | 11.82 | 9.95 | 0.841 |
| Station close | 706 | 10.67 | 6.64 | 0.623 |
| Ships about | 745 | 14.50 | 18.14 | 1.251 |
| Window: Lave (just after launch) | 586 | 7.91 | 15.86 | 2.006 |

Station close is the slowest: the station covers nearly the whole window,
so every frame fills it and the next frame on that buffer repairs all of
it (about 100,000 cycles of bank 5's work an iteration, with 11,600 of
re-patching the row runs for the buffer). The Master port's kept solid
rows answer this; they are not in (Status).

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

## Compromises

* **The planets are plain discs** until the circle engine fits (Status).
* **The flight screens load from disc.** The charts, the hyperspace jump,
  the launch and the escape pod (overlay 1) and the data, status, market
  and inventory screens (overlay 2) share one region of bank 7; moving from
  one group to the other loads the other overlay: 1.6 to 2.7 seconds.
* **The altitude's leftover `Q` is defined.** The original's altitude takes
  a square root of `R` and of whatever its drawing left in `Q`; the port
  sets `Q` = 0 there, and the gate's reference is patched the same way.
* **The dashboard** is the original's, in mode 5 at its own resolution and
  in its own colours (and the escape pod's), shown at the 1 MHz clock
  below the 2 MHz screen by two switches of the clock in mid-line, each on
  an exact cycle ([docs/video-timing.md](docs/video-timing.md)); not the
  Master port's design.
* **Palette effects are not reproduced**: the hyperspace rings' mode change
  (`HFX`) and the colour flashes; the space view's palette is fixed
  (black, cyan, magenta, yellow).
* **The disc is 80 tracks.**
* **Key presses**: at a few frames a second near a large station a very
  short key press can fall between two keyboard scans (the redock test
  holds the docking computer's key for a second).

## Not verified

* **Real hardware.** Everything ran in jsbeeb (Model B, DFS 1.2, 8271),
  headless. The CRTC rupture's timing, the 80-track disc and real sideways
  RAM boards (the loader's `PROBE`) are untested on a real Model B.
* **The picture is not gated.** The gate checks the game state, not the
  screen. The renderer's output is checked by bank 5's and bank 6's py65
  tests (test_raster.py, test_frame.py: pixel models, the disc layer's
  rows and 30-frame sequences against fresh frames) and by eye on
  screenshots (flight, ships, explosions, the station and docking, the sun
  near the planet, the flight screens, the title, the hangar, a briefing).
* **Not looked at on screen**: the energy bomb, the escape pod's flight,
  the death screen, witchspace and Thargoids, the joystick. The escape pod
  and the death sequence run in the gate's state comparison.
