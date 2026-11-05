# BBC Micro disc Elite on the Model B with 64K of sideways RAM: the port

This branch is a series of changes to Mark Moxon's annotated source for BBC
Micro disc Elite (the Stairway to Hell release), for a BBC Model B with
four 16K banks of sideways RAM. It follows the BBC Master port's series
(github.com/ebenupton/solid-elite-bbc-master) in three parts:

1. **The memory map.** Both of the game's programs, the flight code and the
   docked code, move out of main RAM into sideways RAM, two banks each,
   swapped from disc at the same moments as the original swapped them. Each
   program's source stays in the original's order, with each routine's
   header naming the area it lives in: the program's home bank, or its cold
   bank ([memory-map.md](memory-map.md)). Main RAM below the screen is left
   free for part 3, and two banks for the renderer.
2. **The speed-ups** of the game logic, one idea per commit, still drawing
   the original's wireframe, pixel for pixel.
3. **The filled renderer**: the Master port's renderer, rewritten for the
   NMOS 6502, on a double-buffered four-colour screen in main RAM.

Each commit builds, and each passes the gate in [6-harness](../6-harness).
The gate flies the released game and the new build side by side with a
deterministic pilot, and requires the game state to be byte for byte the
original's at every one of 10,000 main-loop iterations. While the port still
draws as the original does, it also requires the screen to match at every
iteration. Saved commander files must be byte for byte the original's. The
Model B's memory and what the MOS and DFS keep there are in
[modelb-memory.md](modelb-memory.md).

## Building

    make                        (BeebAsm 1.11 and Python 3, as upstream)
    make verify                 (the gate: Node.js, jsbeeb and py65, see 6-harness)

`make` writes the disc to `5-compiled-game-discs/elite-modelb.ssd` and the
binaries to `3-assembled-output`. The disc needs a BBC Model B with DFS and
four banks of sideways RAM, and boots with SHIFT-BREAK. The tracked outputs
in `3-assembled-output` and `5-compiled-game-discs` are refreshed at the end
of each part.

## The copy protection

The port is built without the copy protection. The original scrambles its
programs and loader and checks checksums of them, all tied to the original's
code and addresses, which the port changes. So the source is assembled with
`_REMOVE_CHECKSUMS` (as the original's `make encrypt=no`), the loader and
the programs are not scrambled (`DEEOR` has nothing to decrypt), the
loader's protection routines are gone, and `elite-checksum.py` only sets the
default commander's checksum.

## The results

| | Flight it/s | Against the original | Cycles per flight iteration |
|---|---:|---:|---:|
| The original (Stairway to Hell) | 11.85 | 1.000 | 168,749 |
| End of part 1: the memory map | 11.87 | 1.001 | 168,533 |
| End of part 2: the speed-ups ([speedups.md](speedups.md)) | 14.51 | 1.224 | 137,864 |
| Part 3: the four-colour screen, still drawing wireframes | 13.70 | 1.156 | 146,023 |
| Part 3: the wireframe drawing moved to the cold bank, for room | 11.58 | 0.977 | 172,638 |
| Part 3: the filled renderer | 6.21 | 0.524 | 322,228 |
| Part 3: one disc row in one call, the clipper's first part home | 6.48 | 0.547 | 308,463 |
| Part 3: record mode's line bookkeeping dropped | 7.86 | 0.663 | 254,590 |
| Part 3: a run page checked once per buffer | 8.07 | 0.681 | 247,931 |
| Part 3: the disc layer ([renderer.md](renderer.md)) | 8.84 | 0.746 | 226,316 |
| Part 3: the Master port's frame layer in bank 6 | 9.92 | 0.837 | 201,618 |
| Part 3: the Master port's disc layer, its row code in bank 7 ([renderer.md](renderer.md)) | 13.31 | 1.123 | 150,274 |
| Part 3: the sun near the planet (`S_SUN`) | 13.17 | 1.111 | 151,897 |
| Part 3: the original's dashboard in mode 5, at the 1 MHz clock ([video-timing.md](video-timing.md)) | 13.07 | 1.103 | 153,010 |
| Part 3: the main RAM part in the room the dashboard leaves | 13.06 | 1.102 | 153,097 |
| Part 3: the planets' surfaces, the beach ball and the craters, by default (`make circles=off` builds the plain discs of the line above) | 7.38 | 0.623 | 271,014 |

These are the gate's run: the pilot's mix of launches, fights, approaches to
the station and hyperspace jumps, over 10,000 iterations. Saved commander
files are byte for byte the original's. Since the renderer's record mode
stopped working out the original's lines, the reference is run with two
small patches (`Q` = 0 at the altitude check, and C = 1 for an explosion's
first random number, as the port's source has them;
[renderer.md](renderer.md)). From the four-colour screen on, the
gate compares the game state without the drawing's temporaries and line
heaps (`--loose`), and no longer the screen.

By scene, over the same run (iterations in the front view, classified by
the original's state; [renderer.md](renderer.md), "Speed"):

| Scene | Iterations | The original, it/s | The port, it/s | Against the original |
|---|---:|---:|---:|---:|
| Station close (nearer than 16 x 256, ahead) | 706 | 10.67 | 6.01 | 0.56 |
| Sun close (nearer than 1,024 x 256, ahead) | 402 | 11.82 | 9.02 | 0.76 |
| Planet close (nearer than 128 x 256, ahead; mostly off the screen) | 1,032 | 13.70 | 11.16 | 0.81 |
| Big planet (128 x 256 to 512 x 256, ahead) | 6,681 | 11.03 | 8.35 | 0.76 |
| Open space (planet far, no ships, no station near) | 270 | 19.39 | 13.55 | 0.70 |
| Ships about | 745 | 14.50 | 11.70 | 0.81 |

The filled renderer is slower than the original's wireframe: every frame
is drawn filled (all of it but the bigger disc, which is kept from frame
to frame) into the buffer not on show, on the same 2 MHz
6502 that runs the game.
