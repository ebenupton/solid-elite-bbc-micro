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
   and the planet as discs with the planet's meridians and craters; stars,
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
| End of part 3 | 6.48 | 0.547 | 308,463 |

By scene, over the gate's run (front-view flight iterations classified by
the game state; `6-harness/bscenes.mjs` and `scenes.py`), the final build
against the original:

| Scene | Iterations | Original | Port | Ratio |
|---|---:|---:|---:|---:|
| Open space (planet far, no ships, no station near) | 270 | 19.39 it/s | 12.06 it/s | 0.62 |
| Planet close (ahead, z below 128 x 256) | 1,032 | 13.70 it/s | 9.63 it/s | 0.70 |
| Station close (ahead, z below 16 x 256) | 706 | 10.67 it/s | 5.51 it/s | 0.52 |
| Ships about | 2,662 | 11.77 it/s | 7.50 it/s | 0.64 |

The filled port is about half as fast as the original wireframe game. The
speed-ups of part 2 are kept, but each frame is drawn in full on the same
2 MHz CPU. A profile (docs/renderer.md, "Speed") puts about 156K cycles an
iteration in the rasteriser. Of that, 28K goes to re-patching the unrolled
row runs for the other buffer at every flip, and about 26K to the
trampolines into bank R. Another 10K goes to keeping the record mode
faithful.

## Compromises

* **The disc layer and the lens flare are cut** (the rasteriser only fits
  bank R without them). The sun and the planet are plain dithered discs
  filled whole every frame, with the planet's meridians, equator and
  craters as cyan lines over it, not two-colour bands.
* **Record mode does all the drawing's bookkeeping.** The game still builds
  the ship line heap, clips lines, works out the sun's rows and does each
  line's `LOIN` division (`VLOIN`), because the original's state depends on
  what its drawing leaves. Its altitude takes a square root of `R` and of
  whatever `LOIN` left in `Q`; a first version that skipped this diverged.
  This costs speed.
* **The dashboard** is the original's, doubled to the four-colour screen and
  recoloured (red to magenta, green to cyan), not the Master port's design.
* **Palette effects are not reproduced**: the hyperspace rings' mode change
  (`HFX`) and the colour flashes; the palette is fixed (black, cyan,
  magenta, yellow).
* **The docked code is unchanged in kind**: the title screen and the hangar
  are coloured wireframes drawn directly, not filled.
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
  hyperspace rings, the docked screens of the savetest), and by bank R's
  and bank F's py65 tests.
* **Not looked at on screen**: the energy bomb, the escape pod's flight, the
  death screen, witchspace and Thargoids, the missions, the joystick. The
  escape pod and the death sequence run in the gate's state comparison
  (an escape is in the pilot's run), not visually.
* **The frame layer's five commits** (`244047e` to `4db0266`) leave the
  game's binaries unchanged. They were gated as one, at `4db0266`, not
  one by one (PASS, as the table above shows).
