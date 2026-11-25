# The determinism harness and the gate

This folder holds the tools that check a change to BBC Micro disc Elite
against the released game. They run the original disc (the Stairway to Hell
release, `4-reference-binaries/sth`) and the new build side by side on an
emulated BBC Model B with sideways RAM, fly both with the same deterministic
pilot, and compare the game state at every iteration of the main loop.

They are the Model B counterparts of the BBC Master port's harness
(`mlib.mjs`, `mpilot.mjs`, `mcompare.mjs` in that repository), and work the
same way; the differences come from the disc version (two programs, the
keyboard read through one routine, the laser pulse counted by the interrupt
handler).

Every commit of the port passes the gate, `6-harness/verify.sh`.

## Requirements

* Node.js 20 or later.
* jsbeeb 1.6.0, the emulator, which the harness runs headless (it never
  opens a window), as a "B-DFS1.2" machine: a Model B with DFS 1.2 and
  sideways RAM in slots 0 to 7. Run `npm install` in this folder, or point
  `JSBEEB` at a jsbeeb checkout or package directory.
* For `bversions.sh`, also jsbeeb 2 (2.19.0), the version that the web
  emulator at bbc.xania.org runs: `npm install` in `6-harness/jsbeeb2`, or
  point `JSBEEB2` at it. Every tool also runs on it, with `JSBEEB` pointing
  there. `BOOTPRE=N` in the environment makes every tool's boot run N
  cycles more before its SHIFT+BREAK (another boot phase: `bversions.sh`).
* Python 3 and BeebAsm 1.11 for the build, as for the rest of the
  repository, and py65 (`pip install py65`) for the rasteriser's test.

## The gate

    make verify                 (or: sh 6-harness/verify.sh [iterations])

The gate builds the game with `make`. It then compares the released disc
(`4-reference-binaries/sth/build.json`: the disc, with the symbols of the
original source's build) against the new build
(`3-assembled-output/build.json`) for 10,000 main-loop iterations. Then it
runs the regression checks: dock, launch and dock again; save, load, fail
to load and catalogue through the game's disc menu, with the saved file
compared byte for byte with the one the released game saves; and change
view in flight. In the comparison and the views run, and in `bsunslot.mjs`'s
scenes, the candidate runs with `--deadregs`: at the return from each routine
whose port leaves registers or flags other than the original's and claims
them dead there (`blib.mjs`'s `DEAD_AFTER`: `DIALS`, `SUN`, `PTCLS`, `WPLS`,
the stardust's skips, `MAD`), those are scrambled, so a read of any of them
diverges. It also builds the option with plain disc planets (`make
circles=off`) in a copy of the tree, which must build and fly 1,500
iterations in step with the reference, so that the option cannot break
unseen. The steps that fly only the reference (`bsunref.mjs` and the release against the release with the passive and the edge variants) depend on the reference, the patch's files, the harness and the iteration count, not on the candidate's code: a pass is kept under the hash of those in `6-harness/work/refonly` and taken from there when the same inputs come again (`NOCACHE=1` in the environment runs them anyway). It prints `VERIFY PASS` with the speed of both builds in
flight-loop iterations per emulated second, their ratio, and the new build's
cycles per flight iteration.

`MODE` sets how much the comparison covers:

* `strict` compares every byte of the recorded game state, the drawing
  temporaries and line heaps included.
* `loose` leaves out the drawing temporaries and the line heaps. This is
  for a build whose drawing code differs from the original's.
* `screen` also compares the screen (`&6000-&7EFF`) at every iteration.
  This is for a build that draws exactly as the original does (up to the
  end of part 2: the four-colour screen of part 3 is another format).

`verify.sh` sets the mode the port's current state must meet.

## How the comparison works

* **Two programs** (`blib.mjs`). Disc Elite is two programs, the flight
  code and the docked code, and only one is in memory at a time. A build is
  described by a `build.json`: the disc, and for each program its symbols
  and the images its code is in, with where each image is mapped (main RAM
  in the original; the home and cold banks in the port, whose numbers the
  harness reads from the port's `BANKS`, with a file of each label's bank).
  A hook is a label of one program (a routine that the port moved into its
  cold bank is hooked at its body, `name_C`); it fires only when the PC is
  at the label, in the label's bank, and the bytes there are that program's,
  so the two programs never confuse each other. Call sites are named
  through the port's far-call frames.
* **Input injection.** The keyboard is never pressed. The disc version
  reads keys only in `DKS4`, one key at a time; at `DKS4+17`, just after the
  read, the harness sets the result for the pilot's keys. The pilot is asked
  for the keys at `DOKEY` (once per iteration) and at each key wait
  (`RDKEY` called from `TT217`, the title screens, `PAUSE2`), and for `CTRL`
  in the hyperspace routines. Both builds see the same keys at the same
  main-loop iteration, or at the same poll of a key wait, however fast they
  run.
* **The pilot** (`bpilot.mjs`). The pilot's keys are a function of the game
  state at the start of the iteration only, so equal states give equal
  keys. It launches, fights, docks with the docking computer, trades and
  equips, and makes hyperspace and galactic jumps. It also patches the
  commander identically at `BAY` in both runs.
* **The state** (`blib.mjs`, `regionsFor`). This is zero page, the `UP`
  workspace (the key logger, the flight variables, the commander and the
  configuration), the ship slots `K%` and the ship line heap, the workspace
  `WP`, and the saved commander `NA%`. Each region is found by symbol,
  wherever a build puts it. The state is recorded at every `MLOOP`, in
  either program.
* **What is left out.** `DL`, the vsync flag, is real time. The
  temporaries `V` (left pointing into the token tables) and `P(2 1)` (left
  pointing at a dashboard bulb's character data) depend on where a build
  puts those. The station's line heap pointer `LSO` and the blueprint
  pointer `XX0` are compared as the original's.
* **The laser pulse counter.** The disc version counts `LASCT` down in the
  interrupt handler, once per vsync, so a faster build would see it count
  down in fewer iterations. The harness undoes that decrement and instead
  counts `LASCT` down once per pass of `M%`, the main flight loop, in both
  runs.
* **Sound.** `NOISE` makes its sounds through OSWORD 7, whose time and
  flags depend on the MOS's sound queue. The harness turns the sound off
  (`DNOIZ`) in both runs when the game starts.
* **Disc loads.** The filing system writes scratch bytes into zero page
  during a load, and `CATD` reads the catalogue over `WP`: the original
  relies on these bytes being dead. A build with another disc leaves other
  bytes there. So a byte that the MOS, a ROM or the NMI handler writes is
  left out of the comparison until game code writes it again. The original
  does read some of them first: new stardust gets only its whole parts, and
  its fractional parts are whatever the catalogue left in `WP`. So at each
  `MLOOP` and each pass of `M%`, any such byte above page 0 that the game
  has not written is set to 0, in both runs, and is compared from then on.
* **Boot leftovers.** At `TT170`, any byte of the compared state that the
  new build has not yet written is seeded from the reference (`--seed
  boot`). Such a byte was left by the boot and the loader, not by the game.
* **Page `&0D`.** Once the game has started, a write to page `&0D` by any
  code but the filing system's (the MOS, DFS, the NMI handler at `&0D00`)
  and the original's `CATD` fails the run.

## The tools

| File | What it does |
|---|---|
| `blib.mjs` | Boots a disc on the emulated Model B and runs the game under the pilot. Handles the two programs, input injection, the laser pulse counter, state snapshots and the screen hash, and walks far-call frames. Applies a build's named patches (`PATCHES`, listed in its `build.json`): the reference has three, `ma93-q`, which sets `Q` to 0 at the altitude check's `JSR LL5`, `ee51-c`, which sets C to 1 after the kill path's `JSR EE51` (the explosion's first random number), as the port's source does, and `mv8-half`, which turns the planet by half the original's angle on every iteration, as the port's `MVS5` does for it: at `MVEIT` part 8's first instruction, for `TYPE` 128 or more, it works out the half steps from the planet's vectors exactly as the port does (`halfPart8`: 1/32 radian a step, x(1 - 1/2048) + d y/32 and y(1 - 1/2048) - d x/32, added as the original's `ADD` adds them), and at `MV5`, once the original's own part 8 has run (its counters, `RAT2` and `Q` as the port leaves them), puts them in place of its vectors (docs/renderer.md). And the reference's fourth patch, `sunref`, the sun's parking, as assembled code (`loadRefPatch`, `applyRefPatch`; the reference's patches are then `ma93-q`, `ee51-c` and `mv8-half`, the JS hooks named in its `build.json`, and `sunref`, from the candidate's `sunref.json`): `2-build-files/sunref.py` writes it beside the candidate's `build.json` (`sunref.json`), and `bcompare.mjs` and agentplay give it to the reference; at `RSHIPS`, where the release's flight program goes once `DEEOR` has decrypted it after each load, each of its sites is checked against the release's bytes and written (same length), its code is put in sideways RAM slot 0 and the slot paged in (ROMSEL and `&F4`, which the MOS restores ROMSEL from); the parked sun (`SUNPK`, `SUNPF`, `&0FD3`, in `WP`'s tail) is compared as a region of both machines, and the station's line heap, which the patch moves into the slot, is held as `LSO`. |
| `bsunslot.mjs` | The sun's parking in scenes the gate's run does not reach, in the gate: the gate's pilot on the patched reference and the candidate, with pokes at `MLOOP` that are functions of the game state alone, in five scenes: `zone` and `views` (the station sent far away, `KS4` and `SUNBK`; the planet brought to where part 14 spawns the station, `SUNUP`; then the pilot docks and launches, `SUNLAU`, the programs swapped; with the flight screens' overlays loaded while the sun is parked, or the views changed; 8,000 iterations each), `full` (every other slot filled below the parked sun, then six ships removed: the slots shuffle, spawns fail; 2,500), `clouds` (every 40 iterations a killed cargo canister put ahead, so that its explosion cloud is drawn: the reference's `keepRand` must restore, and the reference without it must differ from the candidate; 1,500), `handback` (the parked sun put ahead, then the station sent away: the candidate's frame must draw the sun in every frame across the hand-back and move it by no more than 2 pixels a frame; 400) and `events` (from the safe zone in turn: the escape pod, a mis-jump and the way out of witchspace, a crash into the station with the death, the title and a new game, a hyperspace jump, the energy bomb and the E.C.M., the galactic hyperdrive; 14,000); the game state compared at every `MLOOP` (`--loose`), the station's invariant, `MVEIT` once for the sun in each flight iteration with a sun (but one in which a jump arrives), and the routines' and events' counts equal in both machines. |
| `bsunref.mjs` | The fourth patch's proofs, in the gate (each proof shows that what it patched ran: the comparison of the gate's run requires `MV40`'s two sites to have run, and a control, the reference without them, must differ within 1,500 iterations; `bsunslot.mjs`'s clouds scene requires `keepRand`'s restores, and its control, the reference without `keepRand`, must differ; `bsunedge.mjs` counts the edge's site and has its own control): at the flight program's first start, the release's main RAM and the slot change only at the sites and the patch's code; over the gate's run, each site's new instruction runs with the slot paged, the station's heap is read and written only with the slot paged, the parked sun is written only by the patch's code, `MAL1`'s body and the filing system, the code is never written, and with the station present in flight `SUNPF` is `&80`. The gate also runs the release against the release with the patch's passive variant (`bcompare.mjs --refpatch none --candpatch sunref-passive.json`: the station never parks the sun), game state identical, and against the release with the sun's edge site alone (`sunref-edge.json`, with `randAt`: `blib.mjs` advances `RAND` at that site as the `JSR DORND` it replaced would, with the C flag the call would have had), game state identical over the gate's run and the views run; as the gate's pilot never faces the sun, so that the site never runs there, `bsunedge.mjs` flies the release with the sun put ahead of it: plain, with the site and `randAt` (identical, the site run tens of thousands of times), with the site and no `randAt` (which must differ), and the candidate against the release with its whole patch (identical). |
| `bpilot.mjs` | The deterministic pilot and its commander patch. |
| `bcompare.mjs` | Compares the reference against a candidate and reports the first divergence, the speed per window and by pilot phase, and the cycles per flight iteration. With the reference's fourth patch it prints how often each changed site ran and `keepRand`'s restores (`blib.mjs` counts them, a site by its new bytes, so the docked program's code at its address is not counted); `--needsites REGEX` fails the comparison if a matching site (or `keepRand`) never ran, and `--nosites REGEX` and `--nokeep` drop those parts of the reference's patch, for the controls, which must differ. |
| `bredock.mjs` | The regression check for docking, launching and docking again, with real key presses (each docking within `--limit` emulated seconds, 300 by default). |
| `bsavetest.mjs` | Exercises the disc menu: save, load, a failed load, a catalogue and a launch, and compares the saved commander file with the reference's. |
| `btrace.mjs` | Traces chosen routines and variables over chosen iterations (`bcompare.mjs --trace`). |
| `bprofile.mjs` | Profiles cycles by PC over exactly the gate's run, with the share of flight iterations that run each PC; with `--scenes FILE` (a `bscenes.mjs` run of the same build), also by `scenes.py`'s scene. |
| `test_routines.py` | Calls the speed-ups' routines in the original and the port on py65, for every input (or a sample, with `--quick`, as the gate does), and compares their results: registers, flags, variables, and for the drawing routines (STARS1, BLINE, PIX1) the screen (with the renderer's `GFORCE` set, so that the port draws directly). A port's routine in the cold bank runs from that bank's image, and a test can compare it with an original routine of another name. `MVS5H` checks the port's `MVS5` for the planet (`TYPE` 128 or more: half steps) against a model of the BBC Master port's `MVS5H`, the same as `blib.mjs`'s `halfPart8`. |
| `test_raster.py`, `raster_model.py` | The rasteriser's soak test (bank 5, docs/renderer.md): builds it and checks every primitive pixel for pixel against `raster_model.py`'s reference (the Master port's, from the Demonstration Disc port), on py65's NMOS 6502, with a write guard; `--quick` for the gate. |
| `bshot.mjs` | Screenshots of a build at given iterations of the gate's run, from jsbeeb's video (headless), as PNG files: `--at N1,N2,...`, and `--after S` for the screen S emulated seconds after a run stops. |
| `bhsync.mjs` | The video timing proof (docs/video-timing.md): times every horizontal and vertical sync of a run of the gate's pilot, from the rupture's handover on, and fails on any sync interval other than 128 cycles or any field other than 312 lines. `--screens`, `--views` as `bcompare.mjs`; `--ula` lists the switches by line and cycle; `--inject N` and `--t2skew N` for the fault injection and the timer's skew; `--adcrace N` raises the ADC's end of conversion (with its interrupt on) 0 to N cycles before each firing of the rupture's timer, in turn, and also fails unless the rupture runs twice a field. It prints the run's phase of the 6845's 1 MHz clock against the CPU's 1 MHz bus. |
| `bversions.sh` | `bhsync.mjs` at sixteen boot phases (`BOOTPRE`) on jsbeeb 1.6.0 and jsbeeb 2, and `bshot.mjs`'s screenshots of the two compared byte for byte. |
| `b2/` | The video timing on Tom Seddon's b2 (docs/video-timing.md, "b2"), headless: `build.sh` builds b2's core library and `b2drive.cpp`, a driver that boots a disc on b2's default Model B with sideways RAM, plays a script of key presses (`fly.txt`), writes b2's TV picture as PNG files, times the 6845's syncs, mirrors b2's TV's sync handling and lists the ULA's control writes by line and cycle (`B2SYNC PASS` or `FAIL`); `b2sweep.sh` runs it at sixteen warm boot phases and four cold boots (`B2SWEEP PASS` or `FAIL`). b2 itself is cloned and built outside the repository, at the commit in `build.sh`. Not part of the gate. |
| `test_frame.py` | Bank 6's test (docs/renderer.md): runs banks 5 and 6 on py65 with ROMSEL paging, with the flight code's home bank (and a blueprint set) and cold bank, records ships through the game's own `LL9` and calls every entry through `GCALL`, drawing frames whose ships are projected and whose clouds are drawn by the game's code; checks what each call writes, the zero page and Y kept, the flip, what was drawn (ships, vertices, particles, text, sights), the repair, and the discs against their model (the layer, the second disc, the planet's surface from circle records made by `planet_caps.py`, and incremental sequences against fresh frames); and the circle engine's arithmetic in the flight code's home bank (a build with `_CIRCLES`) against exact models: `pm_isqrt` for every 16-bit n, `pm_fdiv` against `planet_caps.py`'s `fdiv`, `pm_mul16` (and `pm_sq16`, once the engine has it) against the product, for random operands of every length, and `pf_tilt` (in bank 5, through `T_TILT`) against `planet_caps.py`'s; writes the frames as PNG files (`--png DIR`). The gate runs it. |
| `planet_caps.py` | The Master port's bit-for-bit model of the circle engine (`gfx-merid.asm`) and the planet's styles (`gfx-planet7.asm`): `test_frame.py` makes the circles' records with it and checks `PC_ROWS`' rows against it. |
| `bscenes.mjs`, `scenes.py` | The speed by scene: `bscenes.mjs` records each iteration's time and the planet's, the station's and the ships' positions over a build's run of the gate; `scenes.py REF.json CAND.json` compares two such runs, scene by scene (open space, planet close, station close, ships about). |
| `bbench.mjs` | A speed benchmark that does not move when the game's random numbers do (the BBC Master port's `mbench.mjs`): it launches under the gate's pilot, then for each of nine frozen scenes (flight, combat, beachball, sun, docking, zone, rear, and the two that are most of the gate's run: approach, a crater planet turning at the view's edge and swung round it by our roll, and departure, the beach ball turning dead ahead after a launch) puts the scene's state in, snapshots it after 8 iterations and runs 128 in windows of 32 from the snapshot, with `RAND` put back and no ship spawned within a window; it prints the cycles from one `MLOOP` to the next and the iterations a second, per scene. The scenes run in that order in one session (a scene run alone can differ by a few thousand cycles: the frame layer's state carries over). |
| `bspin.mjs` | The planet's turn over the gate's run: its turn from one iteration to the next with the player still, by `MCNT`'s parity, and the lengths of its vectors and how far they are from right angles; `--build` the reference for its figures. |
| `hotset.py` | From a profile of the original (or, with `--port`, of the port's home bank), lists the flight program's blocks with their cycles, the share of flight iterations that run them and their calls per iteration: the hot and cold split, and what a far call into a block would cost. |
| `agentplay/` | elite-agent plays the released disc while the port replays its inputs read for read, game state and dashboard compared at every iteration, with save-file, BRK, hang and coverage checks: sessions, replays, campaigns ([agentplay/README.md](agentplay/README.md)). Not part of the gate. |
| `verify.sh` | The gate. |
