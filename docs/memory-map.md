# The memory map

This is where the port puts each part of BBC Micro disc Elite (the
Stairway to Hell release), why it goes there, and how code in one region
reaches another. [modelb-memory.md](modelb-memory.md) covers the hardware:
what the MOS and DFS use, and what the original and the port take.

The original is two programs that never share memory: the flight code
(`D.CODE`, 17,437 bytes) and the docked code (`T.CODE`, 19,997 bytes with
its own ship blueprints). Each loads at `&11E3` and runs to `&55FF` or
`&5FFF`, and each loads the other from disc when we launch, dock or die.
Main RAM is full: the screen takes `&6000-&7FFF`, and the loader's resident
block, the text tokens and the workspaces take what is below `&11E3`.

The port moves both programs out of main RAM into sideways RAM, so that
main RAM can hold a double-buffered colour screen (part 3,
[renderer.md](renderer.md)). It keeps the original's structure: two
programs, swapped from disc at the same moments, each in two sideways RAM
banks, a **home bank** that is paged in whenever the program runs and a
**cold bank** that is paged in only for far calls. The other two banks are
the filled renderer's. Every routine of the game stays at its place in its
program's source.

## The rules the layout follows

1. **Four sideways RAM banks.** The loader finds four banks of sideways RAM
   (`PROBE`: the first four slots from 15 down that the MOS has no ROM in
   and that hold what is written to them) and keeps their numbers in
   `BANKS`, as boards differ: the programs' home bank `BANKH`, their cold
   bank `BANKC`, and the renderer's `BANKR` and `BANKF`. All code that pages
   a bank reads its number from there. `&F4` always matches ROMSEL, and is
   written first.
2. **One bank at a time.** A program's home bank is paged whenever its code
   runs, so its home code calls itself and reads its own data directly, and
   main RAM is visible to everything. Its cold bank is reached only through
   a far-call stub that pages it in and pages the caller's bank back
   (`elite-far.asm`). Cold code reaches home code the same way.
3. **What is hot.** A program's home bank holds the code that runs in every
   flight iteration or in every iteration of an activity (fighting, the
   docking computer, the side views, the planet and the sun), the code that
   reads the ship blueprints (which are in the home bank), and the code that
   shares variables with it. Its cold bank holds the code that runs at most
   once per event: the screens other than the space view, the text and its
   tokens, the charts and the market, launching, hyperspace and docking,
   the in-flight messages, the missions, and the once-per-event parts of
   fighting (firing a missile, the dashboard's bulbs and missile blocks,
   placing a new ship). `6-harness/hotset.py` lists each block's share of
   the gate's flight iterations; the rules above decide, block by block.
4. **Both home banks have one layout.** `S%`, the program's entry table,
   is at `&8000` (`HOME%`) in both, as the original's was at `&11E3` in
   both, so that the loader's resident code can enter either. The blueprint
   set is at `&B600-&BFFF` (`BPSLOT%`, the original's `XX21` at `&5600`) in
   both. The flight code loads its set from a `D.MOx` file there; the docked
   code's set is its own, assembled with it. The missile's blueprint stays
   in main RAM at `&7F00`, as in the original, where both sets point.
5. **The MOS's vectors and the filing system see main RAM only.** WRCHV,
   BRKV and IRQ1V point at the loader's resident code, which pages the
   program's home bank in itself. Disc commands and file names must be in
   main RAM, as DFS reads them with its own ROM paged in at `&8000`. Files
   cannot be loaded straight into sideways RAM for the same reason: each is
   loaded into main RAM at `STAGE%` (`&1200`) and copied into its bank.
6. **Page `&0D`** holds only what the original puts there: DFS's NMI routine
   and the loader's `CATD` at `&0D7A`.

## The sources and their emissions

`elite-source-flight.asm` and `elite-source-docked.asm` are Mark Moxon's
sources for the two programs, in the original's order. Each routine or
table's header names the area it lives in:

    \       Name: TT219
    \       Type: Subroutine
    \   Category: Market
    \    Summary: Show the Buy Cargo screen (red key f1)
    \       Area: cold

* **No Area field** means the program's home bank, from `S%` at `&8000` on.
* **`Area: cold`** is the program's cold bank, from `&8000` on.
* **`Area: blueprints`** (the docked code's own ship blueprints) is the home
  bank's blueprint slot at `&B600`.

The text tokens' source, `elite-text-tokens.asm` (the original's `WORDS`
file at `&0400`), is tagged the same way: its recursive token table `QQ18`
and the macros that build it are `Area: cold`, assembled into each
program's cold bank, and its sine and arctan tables `SNE` and `ACT` are
`Area: resident`, which stay at `&07C0` in the loader's resident block.

The two banks share the addresses `&8000-&BFFF`, and BeebAsm assembles with
one location counter. So `2-build-files/streams.py` writes one copy of each
source per area into `3-assembled-output` (`elite-flight-home.asm`,
`elite-flight-cold.asm`, `elite-docked-home.asm` and so on), with the other
areas' lines blanked, so that line numbers stay the source's.
`elite-layout-flight.asm` and `elite-layout-docked.asm`, which the Makefile
assembles, INCLUDE a program's copies in turn, each at its own address.
Each label is defined once and each block is assembled once.

**Stubs at their routines' places.** Each emission is the original in its
order, with a far-call stub wherever a routine lives on the other side. The
source calls everything by the original's names. In the cold copy
`streams.py` renames each cold label `X` to `X_C`, and turns each call from
cold code to home code `H` into a call of `xh_H`. It then writes the stubs
into the copies, on the line that defines each routine:

    .TT22    JSR farC : EQUW TT22_C     (home copy: the cold routine's place)
    .xh_TT26 JSR farH : EQUW TT26       (cold copy: the home routine's place)

A routine that never returns (`DEATH`, `RSHIPS` in the flight code; `TT170`,
`BR1`, `BAY` and the others in the docked code) gets a jump stub (`farCj`,
`farHj`). A routine that falls through into a routine on the other side
falls into the stub at the next routine's place; the stub calls the routine,
which returns to the falling routine's caller with the caller's bank back,
just as the fall-through did. The docked code's token jump table `JMTB`,
which `DETOK2` calls in the cold bank, names the stubs of its home entries
itself (`xh_NLIN4`, `xh_MT26`).

**Checks at every build.** `streams.py` checks that each block's IF ...
ENDIF nesting is balanced; that a block that can fall through its end is
followed by a block of its own area, or by a block of the other side whose
first statement is its entry label; that a block ending in the original's
skip trick (`EQUB &2C`, which makes the next instruction the operand of a
`BIT`) is followed by a block of its own area; and that every stub has its
own line. Then `2-build-files/bankcheck.py` checks every reference in the
per-area copies:

* branches never cross areas;
* each side reaches the other only through stubs, and never reads the other
  side's data (it may take an address, `#LO`/`#HI`);
* a stub is only called, jumped or branched to, or its address taken: code
  that reads or writes a stub's label, or an offset from it, is reading the
  stub, not the other side's routine or variable;
* cold code never reads through `XX0`, which always points at a blueprint
  in the home bank;
* main RAM is visible to everything, and the constants that are addresses in
  the home bank (`XX21` and `E%` in the flight code) are home data.

## Calls between regions

| Kind | Where | Pages |
|---|---|---|
| `farC` and `farCj` stubs (`.TT22 JSR farC : EQUW TT22_C`), generated into the home copies | each at its cold routine's place | the cold bank in, then the caller's bank back |
| `farH` and `farHj` stubs (`.xh_TT26 JSR farH : EQUW TT26`), generated into the cold copies | each at its home routine's place | the home bank in, then the cold bank back |
| `WRCHR` (WRCHV) | the resident block | the home bank in, then `JSR S%+6` (`JMP TT26` in the flight code, `JMP CHPR` in the docked code), then the caller's ROM back |
| `BRKR` (BRKV) | the resident block | the home bank in, then `JMP S%+11` (`JMP BRBR1`, or in the docked code the handler that `BRKBK` and `SVE` set) |
| `PCLI` (the programs' `OSCLI`) | the resident block | loads a program or a blueprint file into its banks through `STAGE%`, or passes the command to the MOS from main RAM |

A far call costs about 110 cycles and three bytes of stack, and passes A, X,
Y and the flags both ways. The harness (`6-harness/blib.mjs`) sees through
far-call frames by the label `farret`.

## Loading

The original's loader, `ELITE4` (`elite-loader3.asm`), is the port's
loader, and the disc's `!Boot` runs it directly (the copy protection's first
two loaders are gone, and the port does the two things they did for the
game: closing `*SPOOL` and `*EXEC` files, and reading the keyboard
translation table's address into `TRTB%`). As in the original, it sets up
the screen and the interrupt handler, installs the resident block at
`&1100`, `CATD` at `&0D7A` and the dashboard image at `&7800`. In place of
the text tokens it installs the port's resident block A at `&0400`
(`elite-resident.asm`), then finds the four banks. Its last part runs at
`&0B00`, as the original's did: it loads the docked code with "L.T.CODE"
through `PCLI`, points WRCHV and BRKV at `WRCHR` and `BRKR`, and starts the
game at `S%+3` in the docked code's home bank.

`PCLI` interprets the original's commands:

* "L.T.CODE" and "L.D.CODE" load a program: its home image (`T.CODEH`,
  `D.CODEH`) into the home bank and its cold image (`T.CODEC`, `D.CODEC`)
  into the cold bank, each through `STAGE%`. Then it returns to its caller,
  in the bank that was paged, which now holds the new program. This keeps
  the original's trick: when the flight code dies, its `INBAY` loads the
  docked code with "L.T.CODE" and returns into the docked code's `INBAY`,
  at the same address in both, which jumps to `SCRAM`.
* "R.T.CODE" and "R.D.CODE" do the same, then run the program at `S%`, as
  `*RUN` did.
* "L.D.MOx" loads a blueprint file into the home bank's blueprint slot.
* Anything else (`*CAT`, `*DELETE`, `*DIR`) is copied into main RAM and
  passed to the MOS.

## The map

| Region | Addresses | What |
|---|---|---|
| Zero page, stack | `&0000-&00E1`, `&0100-&01FF` | as in the original |
| `UP` | `&0300-&03CF` | as in the original |
| Resident block A | `&0400-&07BF` | the port's: `BANKS`, the far calls, `PCLI`, `WRCHR`, `BRKR` (`elite-resident.asm`, `elite-far.asm`); the original's text tokens are in the cold banks |
| `SNE`, `ACT` | `&07C0-&07FF` | as in the original |
| `QQ16` | `&0880-&08BF` | as in the original (the docked code copies it there for the flight code) |
| `K%` and the line heaps | `&0900-&0CFF` | as in the original |
| `CATD` | `&0D7A-&0D9D` | as in the original |
| `WP` | `&0E00-&0FD2` | as in the original |
| Resident block B | `&1100-&11E2` | as in the original: `TVT1`, `LINSCN`, `IRQ1`, `NA%`, `BRBR1` |
| Staging | `&1200-&51FF` | where `PCLI` loads each file before copying it into its bank; otherwise free in parts 1 and 2, and the screen buffers in part 3 |
| Screen | `&6000-&7EFF` | as in the original in parts 1 and 2 |
| The missile's blueprint | `&7F00-&7FFF` | as in the original (with `VEC` at `&7FFE`) |
| Home bank | `&8000-&BFFF`, ROMSEL `BANKH` | the flight or docked code's home image: `S%` and the home code from `&8000`, the blueprint set at `&B600` |
| Cold bank | `&8000-&BFFF`, ROMSEL `BANKC` | the flight or docked code's cold image: the cold code from `&8000`, then `QQ18` |
| Renderer banks | ROMSEL `BANKR`, `BANKF` | free in parts 1 and 2 |

Free space at the end of part 1: 324 bytes in the flight code's home bank,
11,112 in its cold bank, 5,474 in the docked code's home bank (below its
blueprints) and 6,025 in its cold bank, and 473 in resident block A.

## What is not in the original's order

* **Stubs.** Each emission holds a far-call stub at the place of each
  routine that lives on the other side. `streams.py` generates them; they
  are not in the source.
* **Changed for the layout**, each marked "Port:" in the source:
  * the configuration: `CODE%` is `HOME%`, `XX21` is in the home bank,
    `OSCLI` is `PCLI`, `QQ18` comes from the cold bank;
  * `DEEOR` has nothing to decrypt;
  * a few short branches into a routine that is now on the other side
    return through their own `RTS` instead (`BPRNT`'s `bpr9`, `mes9r` for
    `mes9` and `OUCH`, `DIALS` part 3 in the docked code), and `WARP`'s
    `BNE NOISE` is a `JMP`;
  * `JMTB` names its home entries' stubs.
* **The loader** keeps the original's look and set-up, without the copy
  protection, and adds the resident block A, `PROBE` and the loading of the
  port's images.
