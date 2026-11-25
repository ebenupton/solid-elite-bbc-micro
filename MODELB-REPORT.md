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

## The Electron port's general wins (branch `electron-wins`)

Branch `electron-wins` in `~/elite-modelb-ewins`, on `modelb-release`:
the general cycle wins of the Electron port (`~/elite-electron`,
`ELECTRON-REPORT.md`, "What transfers to the other ports"), each ported,
measured with `bbench.mjs` and landed as a gated commit, with the room
each needed made first.

**Landed** (the list's numbers): LL9's vertices (1), faces and first dot
products (2) and scaling without `LL28` (3); the circle engine's rows
with no call (4); the front view's stardust in one loop (5, without its
quotient cache); phase B one row loop and the row runs indexed by the
line (6, the part that fits); an 8-bit polygon's edges with no call (7);
a steep edge's own loops (8); a dot's two pixels at once (9); an
unclipped edge's row tests skipped (11); a star erased by a store (12);
the text rows bounded (13); `R_MARKBOX` in one loop and the query a byte
at a time (14); `PF_HOOK` keeping only `XX0` and `INF` (15); the ship
blocks through a patched address (16); fast trampolines (18); the
painter's batches by a direct call, not a far call; `L_REC`'s dot
products in line and LL9's projection division in line (the second
grind's e02ec17, 53b32b8); and two far calls cut where the Model B's
layout made them (`SCAN`'s early returns; the copy into `INWK` through
`X`, a cycle a byte).

**Gate**: VERIFY PASS at each of the branch's last four commits (game
state identical at all 10,000 iterations; redock, savetest, views,
screens, `bsunslot.mjs`'s scenes, the plain-disc build). At `86edb63` the
gate did not pass: `bsunslot.mjs`'s events scene stopped at a BRK
after the crash into the station, as `98b6ec1` had moved `INBAY` to the
cold pass, from where `PCLI`'s "L.T.CODE" returns into bank 7, over
which the docked code's cold image has just loaded (`394d5e9` puts it back
on the hot side). The gate's speed, flight iterations a second (cycles a
flight iteration): at `86edb63` 7.98 (250,714, its comparison step), at
the tip 7.99 (250,218, -0.2%); the original 11.47 (174,293) on this run.

**Left out, for room.** The flight code's hot side (bank 4 and main RAM)
has 9 bytes left, the cold side 13 (bank 7) and the renderer's banks 99
and 20 in fragments (bank 5, bank 6); every block that could move without
costing more than these would save is already on the side its use calls
for:

* **The ship blocks copied by unrolled code** (eb78c6f): 392 bytes of
  the hot side; measured with `make circles=off`, whose bank 4 has the
  room: flight 151,526 to 149,195 cycles an iteration (-1.5%), rear
  -1.3%, zone -0.7%.
* **The stardust's quotient cache** (`sd_qc`, 875222e): 256 bytes of
  table and its upkeep on the hot side; about 3,200 cycles an iteration
  in the flight scene (measured with `make circles=off`, fd2f425).
* **The row runs entered by a jump with a fixed exit** (d6c944b's first
  part): the line is the runs' index here, so the shift that replaces the
  planted RTS needs a second run for each character row's right half, about
  2,400 bytes of bank 5; phase B's character row kept between polygons
  (f6d4346) depends on that entry.
* **The disc layer made, kept and painted in one bank** (ae6c2ea,
  2c0201d, 1dbaa28): the Model B fills the batches' slots in bank 6 and
  hands them to the painter in bank 7 through the mailbox, as the Electron
  did before them (about 200 cycles a row, 90 rows an iteration over the
  gate's run: docs/renderer.md); making the rows with the painter moves
  the row maker's code into bank 7 (13 bytes free), a redesign of the
  layer for an estimated half of the Electron's 2-4% in the planet scenes.
* **The far-call cuts of the dashboard and `TIDY`'s family** (e297523,
  d964da0, f7cb9b3): about 1.3 far calls an iteration, 90 cycles, for
  about 500 bytes of the hot side.

**Not ported, as Electron-specific or with no gain here**: the
painter's one-caller routines (1c8774c: the Model B's painter has none of
those three routines; its `dp_st` has ten callers); and the main-RAM
avoidance and layout changes, which save no cycles on a 2 MHz machine with
fast zero page.

(Commit hashes in this section other than this branch's are the Electron
port's, in `~/elite-electron`.)

## Bytes for cycles: room for the skipped wins, the disc layer in one bank (status, 2026-11-24)

On `electron-wins` from 92b80d7: free bytes found at almost no cycle cost,
then spent on the two skipped wins with the best rates. Each commit was
checked with `bcompare.mjs` (1,500 to 10,000 iterations), bbench and, for
renderer changes, test_raster.py and test_frame.py; the full gate
(`verify.sh`, then `bhsync.mjs`) passed at d1e9906, a22423c and the tip
(below). agentplay sessions (pause, sun, jumps, views, charts, flight
screens, docking) were clean on the tip; one caught a bug in the first
version of the tail-call inlining, fixed before it was committed.

**The exchange rate.** The skipped wins are worth about 9.5 (the
stardust cache, 2,900 cycles in a front-view scene for 305 bytes) and 6
(the unrolled copy, 2,300 in bbench's flight scene for 392) cycles an
iteration a byte, 3 to 8 in the gate's run. The bytes were found at about
0 cycles: bbench's scenes before the first win (072ab16) were within 0.1%
of 92b80d7's (flight -58, combat +153, departure -541 cycles an
iteration), and the gate's run was 259 cycles faster at d1e9906.

**Reclaimed** (each a commit):

| Where | Bytes | How | Cycles |
|---|---:|---|---|
| bank 6 | 48 | PR_PUT calls pr_ins (no patched JMP) | -100 to -330 in the planet scenes |
| banks 5, 6 | 6, 12 | jumps to the next instruction, two branches | 0 or less |
| bank 5 | 66 | R_INIT and r_setup in R_PTA until the first polygon (bank 5 init place) | 0 |
| bank 5 | 209 | one row-page table, buffer 0's by a patched ADC | 0 (within noise) |
| hot | 34 | MULT3's third product without the second-page path (QSMUL7); two returns on this side | -54 in the gate |
| bank 7 | 66 (+4 hot) | ARCTAN not assembled (only PLS4, not run, called it) | 0 |
| bank 7 | 83 | LL145's copies, LASLI, LL118, CTWOD, SHAND's table, HL2; overlay 1's TT22 and TT15A | 0 (rare code) |
| bank 7 | 106, 130 | WARP and SHAND to the cold 5 pass | 0 |
| hot | 253 (-234 bank 7) | TACTICS part 1, VCSU1/VCSUB/TAS1, TAS2, TAS6 to the cold pass | about 1.6 far calls an iteration fewer in the gate |
| hot | 63 | a container at bank 4's top (the D.MOx files carry its bytes) | 0 |
| hot, bank 7 | 18, 24 | a tail call's stub at its one JMP (streams.py) | -3 a site |
| hot | 120 (-124 bank 7) | DK4's pause, CIRCLE's and WPLS's non-record paths to the cold pass; QSMULA | 0 |

Also: the renderer's bank 7 window at a fixed place (WIN7FIX%, its
92b80d7 address), so that cold-pass changes no longer move its loops'
page crossings (100-600 cycles an iteration either way in bbench); the
cold 5 placer's ORGs no longer hidden behind a comment (a latent bug: no
unit of the old layout was affected); the flow places main-RAM-only units
first. In all: the hot side about 490 bytes, bank 7 about 400 (spent on
the hot side's moves), banks 5 and 6 341.

**Landed**:

* The stardust's quotient cache (a22423c, the Electron's 875222e): flight
  -2,913 cycles an iteration (-1.65%), beachball -2,869, sun -2,799,
  docking -2,843, zone -2,916, approach -3,056, departure -2,942 (combat
  and rear unchanged); 305 bytes.
* The unrolled ship-block copy, its half from INWK back to K% (a6a8acd,
  half of eb78c6f): flight -1,194, combat -1,039, zone -951, rear -956,
  the planet scenes about -470; 197 bytes.

**Speed** (92b80d7 -> a6a8acd): gate VERIFY PASS 11.47 8.11 0.707 246474.9 and bhsync PASS, against 7.99 (250,217.8) at 92b80d7 (-1.5%; 8.00 at
d1e9906, 8.10 at a22423c). bbench, cycles an iteration: flight 177065 ->
172896 (-2.35%), combat 98816 -> 97848 (-0.98%), beachball 215853 ->
212145 (-1.72%), sun 231618 -> 228267 (-1.45%), docking 418348 -> 414910
(-0.82%), zone 336569 -> 332599 (-1.18%), rear 210939 -> 209855 (-0.51%),
approach 232439 -> 228623 (-1.64%), departure 337035 -> 333104 (-1.17%).
No scene is slower.

Free now (flight): hot side 0, bank 7 64, bank 5 139 (the cold 5 pass's
places 92), bank 6 80.

**Second round (the user's two decisions).** The other half of the
unrolled copy landed (3213a70) after a commit of room (08f5eca) at the
costs the user accepted: DOEXP's cloud set-up and the laser hit to the
cold pass (about 720 cycles an exploding ship's frame, about 540 a hit),
f_gkeep and f_gback by loops (about 180 cycles a frame that runs game code,
50 an iteration in the gate) for bank 6's room, which the cold 6 pass took
with PU1; the circle engine's record in main RAM's free bytes, so that bank
4's top is all the hot pass's. The sound (NOS1, SFX) did not need to move.
Copy into INWK: flight -1,257 cycles an iteration, zone -999, rear -976.

**Speed now** (3213a70; gate VERIFY PASS 11.47 8.13 0.708 246116.7 and bhsync PASS, against 7.99 and 250,217.8 at 92b80d7 and 8.11 and 246,474.9 at a6a8acd): bbench, cycles an iteration:

| Scene | 92b80d7 | 4f302f2 | 3213a70 | vs 92b80d7 | vs 4f302f2 |
|---|---:|---:|---:|---:|---:|
| flight | 177,065 | 172,896 | 171,874 | -2.93% | -0.59% |
| combat | 98,816 | 97,848 | 97,566 | -1.26% | -0.29% |
| beachball | 215,853 | 212,145 | 211,521 | -2.01% | -0.29% |
| sun | 231,618 | 228,267 | 227,724 | -1.68% | -0.24% |
| docking | 418,348 | 414,910 | 414,535 | -0.91% | -0.09% |
| zone | 336,569 | 332,599 | 331,919 | -1.38% | -0.20% |
| rear | 210,939 | 209,855 | 209,039 | -0.90% | -0.39% |
| approach | 232,439 | 228,623 | 228,213 | -1.82% | -0.18% |
| departure | 337,035 | 333,104 | 332,588 | -1.32% | -0.15% |

Free now (flight): hot side 18, bank 7 4, bank 6 35, bank 5 139.

**The disc layer in one bank (done, third round).** The frame layer's disc
part (gfx-frame.asm's discs, gfx-merid.asm's PC_ROWS, the half-widths and
the rows' arrays) is now in the flight code's bank 7 with the painter, and
the painter reads the rows where they are made: no slots filled in bank 6,
no slot copies in the painter, no trampoline a batch, no far call to the
painter. The room, all found first and in the same commit:

| Where | Bytes | How | Cycles |
|---|---:|---|---|
| bank 7 | about 6,100 | the cold pass's event code to the cold 6 pass (streams.py: the rules extended, as the Electron port's were: falls and branches into a cold 6 block from the hot side, the cold pass and the overlays, calls between the cold 6 and cold 5 passes and from the cold 6 pass into the overlays) | 0 (the same far calls) |
| bank 6 | about 6,100 | the disc part out (4,200 of code with PC_ROWS; F_HW, F_HW2, the rows, the records kept) | the hand-over gone |
| bank 6 | about 440 | F_FRAME's zero page keep by a loop (three bytes a pass), not unrolled | about +350 a frame |
| bank 6 | 116, 52 | F_INIT's code in F_SR's room; the docking slot in the text map's page-aligned tail | 0 |
| main RAM | 23 | FT_DP: a frame's two calls of the disc part without a far call (both programs' low pass) | about -220 a frame |

bank 6 calls the disc part's entries (DPENT%, at the same place in both
programs' bank 7: the docked code's draw no disc), with the frame's discs
handed over in the zero page. The batches are 16 rows with boundaries too
(the slots now hold only bank 5's extents). The rows outside the new ones
are made empty in place before the painter reads them.

Two bugs found on the way, both fixed in the commit: streams.py's tail-call
inlining removed a stub that a block falls into (pr2 into TT11: the status
screen lost the fuel figure; bcompare.mjs --screens found it, the plain
lockstep runs did not), so a stub is now never inlined where the code
before it can fall into it; and the build without _CIRCLES needs the
circle engine's parts guarded in bank 7.

**Speed now** (gate VERIFY PASS 11.47 8.58 0.748 233148.2 and bhsync PASS, against 8.13 and 246,116.7 at aed0169 and 7.99 and 250,217.8 at 92b80d7: -5.27% and -6.82%): bbench, cycles an iteration:

| Scene | 92b80d7 | aed0169 | now | vs 92b80d7 | vs aed0169 |
|---|---:|---:|---:|---:|---:|
| flight | 177,065 | 171,874 | 166,810 | -5.79% | -2.95% |
| combat | 98,816 | 97,566 | 97,521 | -1.31% | -0.05% |
| beachball | 215,853 | 211,521 | 194,603 | -9.84% | -8.00% |
| sun | 231,618 | 227,724 | 213,009 | -8.03% | -6.46% |
| docking | 418,348 | 414,535 | 394,238 | -5.76% | -4.90% |
| zone | 336,569 | 331,919 | 322,516 | -4.18% | -2.83% |
| rear | 210,939 | 209,039 | 193,673 | -8.19% | -7.35% |
| approach | 232,439 | 228,213 | 214,086 | -7.90% | -6.19% |
| departure | 337,035 | 332,588 | 309,148 | -8.27% | -7.05% |

The combat scene waits for the flip about 13,000 cycles an iteration, so
its figure moves by a vertical sync's phase: its work is about 650 cycles
more than at aed0169 (the zero page loop, the hand-over's copies, FT_DP;
it has a small planet, so little of the disc layer's saving), and the
figure came out between -45 and +190 for builds of this design that
differed only in layout.

Free now (flight): hot side 15, bank 7 42 (23 before the tables, 19 in the
window), bank 6 31 (the text map's tail; the cold 6 pass's room is exactly
its size), bank 5 139.

**Fourth round: the painter's per-row copy gone (59ae4d7, 6f9bc21).** The
row code reads a changed row's span, count, colour and boundaries where the
disc part makes them, at the row in X (or Y, or RZ_Y), with no copy into
variables (dp_ld keeps only the slot's dirty extent, and not even that on
the paths that do not read it); the slot is put back as each loop's shared
tail, not a call; r_sw's long-span test is in line before its call.

**Speed now** (6f9bc21; gate VERIFY PASS 11.47 8.91 0.777 224364.9 and bhsync PASS, against 8.58 and
233,148.2 at 0f6b3c2; 59ae4d7's gate: VERIFY PASS 11.47 8.79 0.766
227432.8 and bhsync PASS): bbench, cycles an iteration:

| Scene | 92b80d7 | 0f6b3c2 | now | vs 92b80d7 | vs 0f6b3c2 |
|---|---:|---:|---:|---:|---:|
| flight | 177,065 | 166,810 | 166,340 | -6.06% | -0.28% |
| combat | 98,816 | 97,521 | 97,684 | -1.15% | +0.17% |
| beachball | 215,853 | 194,603 | 193,346 | -10.43% | -0.65% |
| sun | 231,618 | 213,009 | 210,184 | -9.25% | -1.33% |
| docking | 418,348 | 394,238 | 389,648 | -6.86% | -1.16% |
| zone | 336,569 | 322,516 | 320,790 | -4.69% | -0.54% |
| rear | 210,939 | 193,673 | 192,736 | -8.63% | -0.48% |
| approach | 232,439 | 214,086 | 202,563 | -12.85% | -5.38% |
| departure | 337,035 | 309,148 | 292,246 | -13.29% | -5.47% |

Combat's figure (+163) is the flip wait, not work: its profile, alone, has
the same work as 0f6b3c2 to a few cycles and 39 more waiting for the flip
(its small planet gives the painter almost nothing to do); it waits about
13,000 cycles an iteration, so a vertical sync's phase decides its figure.
It is reported for the user's decision, not hidden: 6f9bc21 can be reverted
alone if that is not acceptable (it moved combat 97619 -> 97684, and every
other scene down).

Free now (flight): bank 7 about 20 (window) and 23 (before the tables),
bank 6 31 (the text map's tail), hot side 15, bank 5 139.

**What is left (the profile of the gate's run, 227,433 cycles an
iteration at 59ae4d7):** r_sw, the painter's span writer, about 27,000
(about 160 calls an iteration: mostly its per-call set-up and masked end
bytes; its whole-byte loop, 20 cycles a byte, only about 3,800); the
strips about 6,800; r_dmb's unchanged-row compares about 6,800; R_GETW's
transfers in bank 5 about 7,000 (about 70 cycles a row, inherent while the
extents live in bank 5). An unrolled whole-byte writer (8 cycles a byte)
would take about 150 bytes and pays mainly in the docking and sun scenes
(an estimated 3,000-7,000 cycles there, little in the gate's run); bank 7
has about 40 free bytes in two pieces and bank 6 none, so it needs room
made first (more cold code to the cold 5 pass, or the tables and the
window relaid so the free bytes meet), which is the next decision. The
remaining per-row overheads (r_rowp, dp_ldc, dp_st) are about 40-60
cycles a changed row each, a few hundred to 2,000 cycles a scene.

**Fifth round: the long-span queue (2a7b945; gate VERIFY PASS 11.47 8.92 0.778 224160.9 and bhsync PASS, against 224,364.9 at 6f9bc21).** The painter hands a span
of 16 whole bytes or more to bank 5's row runs through a queue in the
mailbox. It held seven spans; in the docking scene 15 of the 20 offered an
iteration found it full and went to r_sw's loop (departure 8 of 14,
approach 2.5 of 5). With the rows' data no longer in the mailbox, the
queue now takes &20-&63, seventeen spans: docking still finds it full for
7 of 18 (rows of several segments), departure 1 of 10, approach none.

Thresholds measured (DB_QK - 1 whole bytes; queue of 17; bbench, cycles an
iteration):

| Threshold | sun | docking | approach | departure |
|---:|---:|---:|---:|---:|
| 6 bytes | 218,266 | 396,444 | 207,390 | 291,734 |
| 8 | 213,861 | 390,587 | 205,475 | 291,105 |
| 12 | 211,586 | 389,114 | 202,712 | 290,671 |
| **16 (kept)** | **210,185** | **388,880** | **202,297** | **290,477** |
| 20 | 210,194 | 388,981 | 202,211 | 290,353 |
| 24 | 210,185 | 388,985 | 202,209 | 290,487 |
| 16, queue of 12 | 210,194 | 389,251 | 202,461 | 291,266 |
| 16, queue of 7 (6f9bc21) | 210,184 | 389,648 | 202,563 | 292,246 |

Below 16 bytes bank 5's set-up for a span (the queue entry, R_DRAINQ's
loads, r_rowset, the run's planted RTS and the masked ends) costs more than
r_sw's loop saves, so the break-even is about 16 whole bytes; above it
nothing changes. The other scenes moved by 10 cycles or less (beachball
+10, its work the same), combat +47 in the full run (alone: 208 cycles
less flip wait, the same work).

**The bank 7 whole-byte writer, on top.** r_sw's loop (20 cycles a byte)
now writes, an iteration: docking 849 bytes (about 17,000 cycles), sun 413
(8,300), approach 387 (7,700), departure 203 (4,100), zone 145 (2,900),
flight, beachball and rear 11 to 25. An unrolled writer (about 8 cycles a
byte, entered and left by a planted RTS, about 30 cycles a call, used for
four whole bytes or more) would save an estimated 6,000 in docking (1.5%),
3,400 in sun (1.6%), 1,500 in approach, 1,000 in zone, 500 in departure,
nothing in flight, beachball, rear or combat, and about 1,000 in the
gate's run, for about 150 bytes of bank 7, which has about 40 free in two
pieces: room would have to be made first (more cold code to the cold 5
pass, or the tables and the window relaid). That is about 40 cycles a
byte in docking but 7 in the gate's run: the user's decision.

**Also remaining:**

* The row runs entered by a jump with a fixed exit (2.4K of bank 5): its
  gain here, estimated from the profile, is 0.2 to 0.4 cycles a byte, far
  below the exchange rate; item 10 depends on it.
* The far-call cuts for DIALS and TIDY: 0.18 cycles a byte.
* DEATH to the cold 5 pass (126 bytes of bank 7) needs a farC5j (9 bytes
  of resident block A, which has 3).

## The consistency sweep (2026-11-25)

Two commits on `mode5-panel` from 648c455: a fix, then a speed-up.

* **The rupture's race with the ADC (89ec7d3).** The web player's Model B
  found it: an interrupt that `IRQG` passes on to the MOS (the ADC's end of
  conversion, when its interrupt is on) could let timer 1 fire just before
  the MOS read the flags. The MOS then took the timer as its clock and
  cleared it, `RUPT` never ran, and the 6845 lost its vertical sync for
  fields. `IRQG` now hides timer 1 in the MOS's system VIA mask (`&0279`)
  for the interrupts it passes on, and puts the mask back on its way to
  `RUPT` (docs/video-timing.md). The joystick and the ADC work as before.
  The test is `bhsync.mjs --adcrace N`: with the ADC's interrupt on, it
  raises the end of conversion 0 to N cycles before each firing of the
  timer, in turn.
  * This build, N = 400 over 10,000 iterations: every field 312 lines and
    the rupture in all 61,447 of them.
  * The parent, the negative control: 5,102 fields missed out of 13,010.

  The cost is 12 cycles a field, which bbench shows as 14 to 47 cycles an
  iteration.
* **The disc rows kept (4c491bd: the Master's 4d5e721, the CPC port's
  finding 1.4).** The rows are kept when the disc is the one they were made
  for and nothing has written over them since.
  * The key is the build's own `f_cx` to `f_r` and the table's page in
    `fpr_ld2`, so a moving disc costs only a compare.
  * `f_disc2`'s batches and a frame with no disc clear the page.
  * `f_disc2` returns at once when there is no second disc to erase.

  bbench, cycles an iteration: flight -1,256, beachball -3,822, docking
  -3,520, zone -2,450, rear -3,752, departure -4,152, combat -168, approach
  -99, sun -11. It takes 2 fewer bytes of bank 7. Both screen buffers were
  identical to the parent's at every iteration over 10,000.

**Checked and not taken:**

* **Not applicable.** These are the Master's other CPC findings. The Model
  B's sound goes through the MOS (OSWORD 7), so it has no `LINSCN`/`SOINT`
  (cd9b5dc). Its dashboard indexes its own `DLAST` cache by `DLIX`
  (b8d8968). Its `PF_HOOK` has no `pf_cx` copy (63061d8).
* **Already here.** The Master's other wins of 2026-11-16..21 and its part
  9: the stardust's zero-product skips and `stl_pat` only on a change
  (7190f9c, d1049b4, 1d4fe0c), `MLTU2` returning at once for Q = 0
  (893514a), the compass dot moved only when it moves (1f655fe), the disc
  rows by thresholds (9833f1c), and `R_POLY`'s walks without the edge count
  (90393da).
* **Not applicable (the Electron's painter).** cg3/cg_bw (c2dd102,
  16903cd, ad63fa3, 1c8774c): the Model B's painter (`r_sw`, `dp_st`) has
  none of those routines.
* **Rejected by rate, unchanged.** The row runs' fixed exit (d6c944b) and
  phase B's kept character row (f6d4346), at 0.2 to 0.4 cycles a byte for
  2.4K of bank 5. The far-call cuts for DIALS and TIDY, at 0.18.
* **Left for the user's decision.** The bank 7 whole-byte writer (the
  fifth round).

**Gate at 4c491bd:** VERIFY PASS 11.47 8.96 0.781 223167.0; bhsync PASS on
the gate's run, --screens and --views. Free now (flight): main RAM 4, bank
4 15, bank 7 46 (14 in the window, 23 before the tables, 9 after them),
bank 5 139, bank 6 58.
