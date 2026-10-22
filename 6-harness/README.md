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
view in flight. It prints `VERIFY PASS` with the speed of both builds in
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
| `blib.mjs` | Boots a disc on the emulated Model B and runs the game under the pilot. Handles the two programs, input injection, the laser pulse counter, state snapshots and the screen hash, and walks far-call frames. |
| `bpilot.mjs` | The deterministic pilot and its commander patch. |
| `bcompare.mjs` | Compares the reference against a candidate and reports the first divergence, the speed per window and by pilot phase, and the cycles per flight iteration. |
| `bredock.mjs` | The regression check for docking, launching and docking again, with real key presses (each docking within `--limit` emulated seconds, 300 by default). |
| `bsavetest.mjs` | Exercises the disc menu: save, load, a failed load, a catalogue and a launch, and compares the saved commander file with the reference's. |
| `btrace.mjs` | Traces chosen routines and variables over chosen iterations (`bcompare.mjs --trace`). |
| `bprofile.mjs` | Profiles cycles by PC over exactly the gate's run, with the share of flight iterations that run each PC. |
| `test_routines.py` | Calls the speed-ups' routines in the original and the port on py65, for every input (or a sample, with `--quick`, as the gate does), and compares their results: registers, flags, variables, and for the drawing routines (STARS1, BLINE, PIX1) the screen (with the renderer's `GFORCE` set, so that the port draws directly). A port's routine in the cold bank runs from that bank's image, and a test can compare it with an original routine of another name. |
| `test_raster.py`, `raster_model.py` | The rasteriser's soak test (bank R, docs/renderer.md): builds it and checks every primitive pixel for pixel against `raster_model.py`'s reference (the Master port's, from the Demonstration Disc port), on py65's NMOS 6502, with a write guard; `--quick` for the gate. |
| `bshot.mjs` | Screenshots of a build at given iterations of the gate's run, from jsbeeb's video (headless), as PNG files: `--at N1,N2,...`, and `--after S` for the screen S emulated seconds after a run stops. |
| `test_frame.py` | Bank F's test (docs/renderer.md): runs banks R and F on py65 with ROMSEL paging and draws three synthetic frames through the game's entry `GCALL`, checking what each call writes, the zero page and Y kept, the flip, what was drawn and the repair; writes the frames as PNG files (`--png DIR`). The gate runs it. |
| `bscenes.mjs`, `scenes.py` | The speed by scene: `bscenes.mjs` records each iteration's time and the planet's, the station's and the ships' positions over a build's run of the gate; `scenes.py REF.json CAND.json` compares two such runs, scene by scene (open space, planet close, station close, ships about). |
| `hotset.py` | From a profile of the original (or, with `--port`, of the port's home bank), lists the flight program's blocks with their cycles, the share of flight iterations that run them and their calls per iteration: the hot and cold split, and what a far call into a block would cost. |
| `verify.sh` | The gate. |
