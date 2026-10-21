# The speed-ups

The port's second part makes the flight code's game logic faster, one idea
per commit, without changing what it computes. Each commit keeps the game
state byte for byte the original's at every one of the gate's 10,000
iterations, and the original's wireframe is still drawn, so the screen is
checked too: it is the original's, pixel for pixel, at every iteration.
Most of the ideas are the BBC Master port's (its `docs/speedups.md`),
rewritten for the NMOS 6502 (no `STZ`, `BRA`, `INC A` or `BIT #`) and for
the disc version's code, which multiplies and divides with exact loops
where the Master version uses log tables. The rest are the Model B's own:
the keyboard scan, and the moves that make room for them.

## How a speed-up is measured

The gate's run is deterministic: the same build gives the same cycles to
the cycle, and the emulated Model B runs at 2 MHz. So the cycles per flight
iteration that the gate prints (2,000,000 divided by the flight iterations
per emulated second) are an exact measure, and as the game state is
identical, both builds fly the same iterations. Each figure below is the
cycles per flight iteration after the commit, and the saving against the
commit before it. Page crossings move with the code, by a few cycles
either way, and are included; nothing is padded to keep code in place.

## How a speed-up is checked

Before the gate runs, `6-harness/test_routines.py` runs each changed
routine of the original and of the port on py65, for every input or for a
large random sample, and compares everything the routine leaves that
anything reads: the registers, the flags (V only where a caller reads it)
and the variables, and for STARS1, BLINE and PIX1 the screen. The gate
runs the quick form of these checks before it flies the game.

The first commits pass the gate's strict comparison: every recorded byte,
the drawing temporaries included, with the screen. From ADD's MU8 on, the
port's arithmetic leaves some temporaries that the drawing code shares
with it (`U`, for example) differently, though nothing reads them before
writing them again. So the gate compares the game state without the
drawing temporaries and line heaps (`MODE=loose-screen`), and still the
screen.

## The commits

| Commit | Cycles per flight iteration | Saved | Flight it/s |
|---|---:|---:|---:|
| (the end of part 1) | 168,533 | | 11.87 |
| Multiply in MU11 by quarter squares | 165,976 | 2,557 | 12.05 |
| Multiply in FMLTU by quarter squares | 159,564 | 6,412 | 12.53 |
| Multiply in MULT1 by quarter squares | 158,783 | 781 | 12.60 |
| Multiply in MULTS by quarter squares | 157,517 | 1,266 | 12.70 |
| Draw the dashboard's indicators from the flight code's cold bank | 158,763 | -1,246 | 12.60 |
| Multiply in MLTU2 and MULT3 by quarter squares | 156,846 | 1,917 | 12.75 |
| Scan only the keyboard columns that have a key down in RDKEY | 151,562 | 5,284 | 13.20 |
| Unroll LL28's division | 150,881 | 681 | 13.26 |
| Take DVID4's common quotient of 0 without dividing | 148,008 | 2,873 | 13.51 |
| Shift DVID3B2's operands a byte at a time while their top bytes are 0 | 147,305 | 703 | 13.58 |
| Print the flight code's characters from its cold bank | 147,101 | 204 | 13.60 |
| Move the flight code's once-per-event fighting routines to its cold bank | 147,099 | 2 | 13.60 |
| Subtract the common way round in ADD's MU8, and skip MULT1 for Q = 0 | 145,180 | 1,918 | 13.78 |
| Skip MVS4's multiply when the roll or pitch is zero | 144,617 | 563 | 13.83 |
| Take LL5's square root in four-step halves | 144,468 | 149 | 13.84 |
| Negate LL38's underflowed sum without the stack | 144,450 | 18 | 13.85 |
| Unroll TIS2's division | 144,377 | 72 | 13.85 |
| Specialise the stardust loop's arithmetic | 139,778 | 4,599 | 14.31 |
| Copy BLINE's points once | 138,793 | 985 | 14.41 |
| Inline ADD in PIX1, and tighten PIXEL2 | 138,688 | 105 | 14.42 |
| Draw the dashboard's pitch and roll bars without far calls | 137,864 | 824 | 14.51 |

(The commit that adds the bank profile to `bprofile.mjs` and `hotset.py`
changes no code and is left out.) In all, the speed-ups save 30,669
cycles per flight iteration, 18% of the game's time in flight:
14.51 flight iterations per emulated second, against the original's
11.85 (1.224 times), with the original's wireframe drawn pixel for
pixel. Each commit's message explains its idea, and the source carries
"Port:" comments at each change.

## Where the cycles went

The biggest wins are the multiplications. A quarter-square table (2K, page
aligned, built by the loader in main RAM, where both of the flight code's
banks can read it) replaces the shift-and-add loops of MU11, FMLTU, MULT1,
MULTS, MLTU2 and MULT3, which every rotation, projection and stardust step
uses: a * b = QS(a + b) - QS(|a - b|), with QS(n) = n * n / 4, and the
second term patched into the subtraction's operand. Each keeps the
original's exact results and the registers and flags it leaves.

Then come the keyboard, which tested 112 keys every iteration and now finds
the columns with a key down from the system VIA's interrupt flag and scans
only those, the stardust loop (STL1), where the multipliers are fixed for a
whole pass or particle and are patched into the code, and divisions that
take their common case first (DVID4) or unroll (LL28, TIS2).

## What the room cost

The flight code's home bank held 191 bytes free at the end of part 1. To
make room, the dashboard's indicators (DIALS and its helpers), TT26 and the
dashboard's bulbs, and the once-per-event parts of fighting move to the
cold bank (memory-map.md's rule 3 decides what can go). Of these only the
dashboard runs every iteration: it costs one far call an iteration into
DIALS and, at first, four calls back (ADD and DIL2 for the pitch and roll
bars), 1,246 cycles in all, of which the last commit wins back
824 by keeping the bars' work in the cold bank.

## What waits for the renderer

The home bank now has 121 bytes free, and some of the Master port's
speed-ups need more than that. The renderer (part 3) takes the wireframe
drawing (LOIN, PIXEL, HLOIN and the sun's lines) out of the home bank, and
these follow it there:

| Master port's speed-up | Saved on the Master | Room it needs |
|---|---:|---:|
| Unroll the main loop's copies of the ship data blocks | 1,372 | ~380 bytes |
| Patch the curve's multipliers into the planet's PLL4 | 2,109 | ~250 bytes (quarter squares in place of logs) |
| Inline both of MVS5's ADDs | 656 | ~150 bytes |
| LL51's dot products with the coordinates' products patched in | 1,085 | ~200 bytes (quarter squares in place of logs) |
| Project only the visible vertices' coordinates in LL9 | 210 | small |
| Keep XX13 in X in LL145, and inline MAS4 in the main flight loop | 52 | small |

Two of the Master port's speed-ups do not apply: keeping FMLTU's argument
in an operand and starting ex's token search nearer (the disc version's
FMLTU has no log tables, and its text is in the cold bank).
