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

1. **Four sideways RAM banks**, named as the BBC Master port's: bank 4,
   the programs' home bank (their hot passes); bank 7, their cold bank
   (their cold passes); and banks 5 and 6, the renderer's. The loader finds four banks of sideways RAM
   (`PROBE`: the first four slots from 15 down that the MOS has no ROM in
   and that hold what is written to them) and keeps their numbers in
   `BANKS` (`BANK7`, `BANK6`, `BANK5`, `BANK4`, in the order found), as
   boards differ: on a machine with sideways RAM in slots 4 to 7, each bank
   is the slot of its name. All code that pages a bank reads its number from
   there. `&F4` always matches ROMSEL, and is written first.
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
   placing a new ship, a ship turning hostile, our shields being hit). The
   dashboard's indicators (`DIALS`) are drawn every iteration, but from the
   cold bank, through one far call an iteration: part 2 moved them there
   to make room for the speed-ups ([speedups.md](speedups.md)). `6-harness/hotset.py` lists each block's share of
   the gate's flight iterations; the rules above decide, block by block.
4. **Both home banks have one layout.** `S%`, the program's entry table,
   is at `&8000` (`HOME%`) in both, as the original's was at `&11E3` in
   both, so that the loader's resident code can enter either. The blueprint
   set is at `&B700-&BFFF` (`BPSLOT%`, the original's `XX21` at `&5600`) in
   both: 2,304 bytes, as the blueprints are assembled without their edge
   lists (the `EDGE` macro assembles nothing: every ship is drawn from its
   faces, and nothing reads the edges), so the largest set, `D.MOC`, takes
   1,693 bytes where the original's files take 2,560; the rest holds the
   renderer's data for the set's ships ("Per-set renderer data", below). The blueprints'
   headers, their edge counts included, are as they were. The flight code loads its set from a `D.MOx` file there; the docked
   code's set is its own, assembled with it. The missile's blueprint stays
   in main RAM at `&7F00`, as in the original, where both sets point.
5. **The MOS's vectors and the filing system see main RAM only.** WRCHV,
   BRKV and IRQ1V point at the loader's resident code, which pages the
   program's home bank in itself. Disc commands and file names must be in
   main RAM, as DFS reads them with its own ROM paged in at `&8000`. Files
   cannot be loaded straight into sideways RAM for the same reason: each is
   loaded into main RAM at `STAGE%` (`&1600`) and copied into its bank.
6. **Page `&0D`** holds only what the original puts there: DFS's NMI routine
   and the loader's `CATD` at `&0D7A`.

## The sources and their passes

`elite-source-flight.asm` and `elite-source-docked.asm` are Mark Moxon's
sources for the two programs, in the original's order. As in the BBC
Master port, each program is emitted in three passes, **low**, **hot** and
**cold**, and each routine or table's header names its pass:

    \       Name: TT219
    \       Type: Subroutine
    \   Category: Market
    \    Summary: Show the Buy Cargo screen (red key f1)
    \       Area: cold

* **No Area field** (or `Area: hot`) is the hot pass: the code that runs
  with the program's home bank, bank 4, paged. It flows through its
  containers: bank 4 from `S%` at `&8000` to the room the layout keeps at
  the bank's end, then main RAM (below).
* **`Area: low`** is the low pass: code that must be in main RAM, seen
  whatever bank is paged. The disc version's own code of that kind (the
  interrupt handler, the break handler, the last saved commander) is in the
  loader, and the port keeps it in its resident block A
  (`elite-resident.asm`), so a program's low pass holds only what both
  sides call and that needs nothing of either: the cold pass calls it
  directly, with no stub (`3-assembled-output/direct-flight.txt`,
  `direct-docked.txt`).
* **`Area: cold`** is the cold pass, bank 7 from `&8000`.
* **`Area: overlay N`** (flight code only) is cold code that only runs at
  events: overlay 1 holds the charts, the hyperspace jump with the
  mis-jump, the launch and the escape pod; overlay 2 the data, status,
  market and inventory screens. Each overlay is assembled at the same
  place in bank 7, `OVL%`, after the cold pass (`D.OV1`, `D.OV2`); the
  region is as big as the bigger one, so the smaller one costs nothing.
  Calls into an overlay go through stubs `JSR ovfN : EQUW routine_O` at the
  routine's place in the other copies; `ovf1` (the low pass) loads overlay
  N from disc with `ovload` if the other is in the region (`OVLCUR`), then
  makes the call as `farC` does. An overlay's falls and branches into the
  cold pass become jumps (`routine_ob JMP routine_C`). An overlay may
  call any pass but not the other overlay, even through code in between:
  `2-build-files/ovlcheck.py` checks every path at build time.
* **`Area: blueprints`** (the docked code's own ship blueprints) is bank 4's
  blueprint slot at `&B700`.
* **`Area: none`** is code the port no longer runs: each copy has only its
  labels and one `RTS`, at its place, so a reference still assembles and
  returns at once.
* **`, again`** after any of these: the block is also emitted a second time
  (`3-assembled-output/elite-<program>-again.asm`), with no stubs, its own
  labels and the targets of its `JSR`s and `JMP`s named `A_<name>`, for the
  renderer to run the original's code with stand-ins of its own.
* **`, runs on`** after any of these marks a table that code reads past its
  end, so that the next block must follow it, as a fall-through would.

The blocks before `S%`'s are the configuration (the workspaces), assembled
first. The text tokens' source, `elite-text-tokens.asm` (the original's
`WORDS` file at `&0400`), is tagged the same way: its recursive token table
`QQ18` and the macros that build it are `Area: cold`, assembled into each
program's cold pass, and its sine and arctan tables `SNE` and `ACT` are
`Area: resident`, which stay at `&07C0` in the loader's resident block.

**The containers.** Each pass goes into its containers in the source's
order:

* the **main RAM part** of the program, `PROGM%` to `PROGM_END%`
  (`&7FA0-&7FFD`, between the missile's blueprint, which ends there without
  its edges, and `VEC`): the low pass, then the hot pass's main RAM
  container (`hotm`). The program's layout file assembles it there and
  copies its bytes into its bank 4 image at `PROGI%`; `S%+14` gives where
  that image is while `PCLI` stages the bank 4 image, and `PCLI` copies it
  to `PROGM%` each time it loads the program;
* the hot pass's bank 4 container (`hot`), from `S%` at `&8000` (`HOME%`)
  to the main RAM part's image, then the quarter squares (`QSL`, `QSH`, in
  both programs: the lighting's `L_REC` reads them) and the blueprint slot;
* the cold pass, bank 7 from `&8000`, then the text tokens `QQ18`, below
  `DFSSAVE%`.

**The flow.** The hot pass is cut into units: runs of blocks that must stay
together, because one falls through into the next (its last statement can
continue, or is a BIT skip, `EQUB &2C` or `&24`), branches into another
(the blocks from one to the other, or to the stub of a routine on the other
side, which sits at that routine's place), or runs on into the next. In the
source's order, each unit goes into the container the flow has reached if it
fits, and otherwise into the next one. The sizes are measured, not
estimated: the Makefile runs `2-build-files/streams.py` twice. `streams.py
measure` writes each program's hot pass as one copy, with a label
`FLOW_<n>` at each block, which `elite-measure-flight.asm` and
`elite-measure-docked.asm` assemble for each block's size
(`3-assembled-output/measure-<program>-symbols.txt`); `streams.py place`
then flows the units by those sizes. A block's size does not depend on
where it goes. `3-assembled-output/flow-flight.txt` and `flow-docked.txt`
list every container and its units.

The main RAM part is small (94 bytes): main RAM is the screen's (both
buffers and the dashboard, `&1000-&7DFF`), the workspaces' and the resident
block's. The low pass holds `WSCAN` and `DELAY`, which the cold pass calls
directly; bank 4 holds the whole of each hot pass, so the main RAM
container is empty. A low block may not fall into a cold one (its stub
would be in the low pass); a hot block that falls into a low one falls into
a `JMP` to it at its place. The stubs for a cold block go in the copy of
the nearest hot block before it, so that a branch to them stays in reach.

**The copies.** BeebAsm assembles with one location counter, and the banks
share the addresses `&8000-&BFFF`. So `streams.py` writes one copy of each
program's source per container into `3-assembled-output`
(`elite-flight-config.asm`, `-low.asm`, `-hot.asm`, `-hotm.asm`,
`-blueprints.asm`, `-cold.asm`, and the same for the docked code), with the
other lines blanked, so that line numbers stay the source's.
`elite-layout-flight.asm` and `elite-layout-docked.asm`, which the Makefile
assembles, INCLUDE a program's copies in turn, each at its own address.
Each label is defined once and each block is assembled once.

**Stubs at their routines' places.** Each pass is the original in its
order, with a far-call stub wherever a routine lives on the other side. The
low and hot passes are one side, the hot side (main RAM and bank 4, which
is paged whenever the program's code runs), and the cold pass the other.
The source calls everything by the original's names. In the cold copy
`streams.py` renames each cold label `X` to `X_C`, and turns each call from
cold code to hot code `H` into a call of `xh_H` (but for the low routines it
calls directly). It then writes the stubs into the copies, on the line that
defines each routine:

    .TT22    JSR farC : EQUW TT22_C     (hot copy: the cold routine's place)
    .xh_TT26 JSR farH : EQUW TT26       (cold copy: the hot routine's place)

A cold block's stubs go in the copy of the nearest hot block before it, so
that a routine that falls through into a routine on the other side falls
into the stub at the next routine's place; the stub calls the routine,
which returns to the falling routine's caller with the caller's bank back,
just as the fall-through did. A branch to a routine on the other side
reaches its stub the same way. A routine that never returns (`DEATH`,
`RSHIPS` in the flight code; `TT170`, `BR1`, `BAY` and the others in the
docked code) gets a jump stub (`farCj`, `farHj`). The docked code's token
jump table `JMTB`, which `DETOK2` calls in the cold pass, names the stubs of
its hot entries itself (`xh_NLIN4`, `xh_MT26`). The stubs are 5 bytes each,
as the far calls they use (`elite-far.asm`) are in main RAM; the BBC Master
port's stubs are themselves in main RAM, 9 bytes each, which the Model B has
no main RAM for.

**Checks at every build.** `streams.py` checks that each block's IF ...
ENDIF nesting is balanced; that a block that can fall through its end is
followed by a block of its own pass (in the hot pass, its unit), or by a
block of the other side whose first statement is its entry label; that a
block ending in the original's skip trick (`EQUB &2C`, which makes the next
instruction the operand of a `BIT`), or that runs on, is followed by a
block of its own pass; that no block branches into another pass of its
side; that every stub has its own line; and that every unit fits a
container. Then `2-build-files/bankcheck.py` checks every reference in the
copies:

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
translation table's address into `TRTB%`). As in the original, it shows
the loading screen with its own interrupt handler (block B, at `&1100`),
and installs `CATD` at `&0D7A`. In place of the text tokens it installs the
port's resident block A at `&0400` (`elite-resident.asm`), then finds the
four banks. Its last part, `LOAD`, runs at `&0B00`, as the original's did
(two pages now): it copies the high resident block to `RESH%`, loads the
renderer's banks (`R.BANK`, `F.BANK`, through `STAGE%`) and starts the frame
layer (`F_INIT`), loads the docked code with "L.T.CODE" through `PCLI` and
the dashboard's image `P.PANEL` to `PANEL%`, switches to the game's
four-colour screen and starts the rupture (`IRQG`), points WRCHV and BRKV at
`WRCHR` and `BRKR`, and starts the game at `S%+3` in the docked code's home
bank. The disc is an 80-track one: it holds 520 sectors.

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

The flight code also loads its overlays itself, at any time in flight
(`ovload`, cold pass): it keeps `WP` (`&0E00-&0FFF`) and zero page
`&90-&E1` in buffer 0 at `OVSTASH` (`&3C00`), puts DFS's workspace back
(`dfsin`), reloads the catalogue (`CATD`), loads `D.OVn` to `STAGE%` with
`pload` and copies it to `OVL%`, keeps DFS's workspace (`dfsout`), puts the
rest back and marks the screen buffers as used (`GSTASH`). The bank 7
image in `D.CODEC` holds overlay 1, so a load of the flight code starts
with it (`OVLCUR` = 1). In the gate's run the loads cost about 85 cycles
an iteration on average (two loads a hyperspace jump at most).
* Anything else (`*CAT`, `*DELETE`, `*DIR`) is copied into main RAM and
  passed to the MOS.

## Per-set renderer data

Only one blueprint set's ships exist at a time, so the renderer's data for
each ship type is loaded with its set, as the blueprints are, rather than
kept for all 33 types: `2-build-files/faces.py` writes it by set
(`gfx-setnorm.asm`, `gfx-settab.asm`, `gfx-setfaces.asm`) and
`elite-shipset.asm` assembles each set's part at the end of its ship file:

* the ships' unit normals after the blueprints, and their table
  `FC_NORMTAB` at `NORMTAB` (the slot's last 66 bytes), which the lighting
  (`L_REC`) reads as before (`LDA FC_NORMTAB,X`: the same instructions);
* the face and detail lists with `FC_FACETAB` and `FC_DETTAB`, assembled
  at bank 6's `FCSLOT` (847 bytes below the dispatcher, the largest set's)
  and carried in the file after the slot's pages: `PCLI` copies the slot's
  nine pages into bank 4 and leaves the file at `STAGE%`, and `LOMOD` then
  has the frame layer copy the lists into `FCSLOT` (`F_SETLD`). The docked
  code's set has its lists at the start of its cold image, and `DEEOR`,
  which every start of the docked code after a load runs first, has them
  copied the same way.

`2-build-files/setcheck.py` (run by `make`) reads every set's data as built,
from its own `XX21`, and checks it byte for byte against faces.py's tables
of all types (`faces-master.json`). Against tables of all types this saves
466 bytes of bank 4 (the 978-byte normals table, less the slot's two more
pages) and 1,201 of bank 6. The lookups are unchanged; the larger files and
the copy cost about 14,400 cycles per hyperspace iteration in the gate's
run (375 per flight iteration on average).

## The map

The map at the end of part 3 (the parts before it differed below `&8000`:
see the history of this file).

| Region | Addresses | What |
|---|---|---|
| Zero page, stack | `&0000-&00E1`, `&0100-&01FF` | as in the original; the rasteriser uses `&06-&27` and the frame layer `&D2-&E1` during a frame, and put the game's bytes back |
| `UP` | `&0300-&03CF` | as in the original |
| Resident block A | `&0400-&07BF` | the port's (`elite-resident.asm`): `BANKS`, the far calls, `PCLI` with `dfsin` and `dfsout`, `WRCHR`, `BRKR`, the last saved commander and the break handler (`S1%`, `NA%`, `CHK2`, `CHK`, `BRBR1`, block B's in the original), the interrupt handler `IRQG` (the rupture and the flip), and at `GLUE%` = `&0724` the renderer's glue (`GCALL` and the trampolines into bank 5); the dashboard's workspace at `&07BD-&07BF` |
| `SNE`, `ACT` | `&07C0-&07FF` | as in the original |
| `QQ16` | `&0880-&08BF` | as in the original |
| `K%` and the line heaps | `&0900-&0CFF` | as in the original (the loader's `LOAD` runs at `&0B00-&0CFF` before the game starts) |
| `CATD` | `&0D7A-&0D9D` | as in the original |
| `WP` | `&0E00-&0FD2` | as in the original |
| Buffer 0 | `&1000-&3FFF` | the renderer's second screen buffer (`BUF0`); also DFS's workspace page (`&1000-&10FF`, which `PCLI` puts back for each disc command and keeps in `DFSSAVE%` between them) and, during a load, the staging area `STAGE%` (`&1600`, up to 16K, into buffer 1) |
| Buffer 1 | `&4000-&6FFF` | the screen (`SCREEN%`): the space view's first buffer, and the only one outside a space view |
| The dashboard | `&7000-&7DFF` | `PANEL%`: the dashboard's seven character rows, shown by the rupture's frame B |
| The mailbox | `&7E00-&7E9F` | the rasteriser's inputs (`MBOX`, `gfx-rws.asm`), the stars at its end (`&67-&9F`); `PCLI`'s command and OSFILE block (`PCBUF`, `PBLK`) share its polygon vertices, as do the planet's circle records from `PF_HOOK` to the frame (`PCB`, `PC_N`, `pc_inv`: `&00-&49`) and, during the frame, the disc layer's batches (`&00-&65`) |
| The shared variables | `&7EA0-&7EAF` | `GVARS`: the renderer's state that the game's hooks, the interrupt and the frame layer share (the last, `PF_CLS`, the planet's class as `PF_HOOK` made it) |
| The high resident block | `&7EB0-&7EF0` | `RESH%` (`elite-resident-high.asm`): the palette and the rupture's register routine and tables |
| The missile's blueprint | `&7F00-&7F9F` | as in the original, without its edges; then the programs' main RAM part, `PROGM%` (`&7FA0-&7FFD`); `VEC` at `&7FFE` |
| Home bank | `&8000-&BFFF`, ROMSEL `BANK4` | the flight or docked code's home image: `S%` and the home code from `&8000`, with the lighting (`gfx-light.asm`: `L_REC`, and in the flight code `L_SUN`); in a build with `_CIRCLES`, the planet's surface after the hot pass (`PF_HOOK`, `gfx-planet7.asm`, and the circle engine's `pc_circ`, `gfx-merid.asm`); the quarter squares at `&B300-&B6FF` (`QSL`, `QSH`); the blueprint set at `&B700`, with its ships' normals and `FC_NORMTAB` (`NORMTAB`) |
| Cold bank | `&8000-&BFFF`, ROMSEL `BANK7` | the flight or docked code's cold image: the cold code from `&8000` (in the docked code, after its set's face lists), then `QQ18`; in the flight code, then the overlay region (`OVL%`) and the renderer's window (`WIN7%`, `gfx-window7.asm`: the disc layer's painter and the second disc, `&A387` on, and each buffer's disc state in the twelve pages `&B300-&BEFF`, not in the image); `DFSSAVE%` at `&BF00` |
| Bank 5 | ROMSEL `BANK5` | the rasteriser, from `R.BANK` ([renderer.md](renderer.md)): the polygons, lines and repair (`&8000-&8FFF`), the state, the tables, the 24 row runs and the stars (`&9000-&BFBF`), the jump table `RJT` |
| Bank 6 | ROMSEL `BANK6` | the frame layer, from `F.BANK`: its code with the discs, the circle engine's rows (`PC_ROWS`), the lens flare, the screens drawn directly and the hangar's background (`&8000-&A656`), the lighting's ramps and the faces' small tables, its state with the discs' rows, the face lists of the blueprint set loaded (`FCSLOT`, the 847 bytes below the dispatcher), the dispatcher `FJT` (`&BFC0`); in a build with `_SSUN`, also the sun near the planet (`S_SUN`, `gfx-ssun.asm`), which it has no room for yet |

Free space now: 438 bytes in the flight code's home bank (the lighting and
the faces' normals take 1,956 there, for which `DEATH`, `LASLI`, `PU1`,
`TIDY` and its routines, `MAS1`, `PIXEL`, `LL145`'s first part and `ARCTAN`
moved to the cold bank: [renderer.md](renderer.md), "The hooks"; the
planet's surface, 2,543 bytes with `_CIRCLES`, does not fit yet, by 2,108),
34 in its cold bank (the renderer's window takes 3,927 and its state 3,072:
[renderer.md](renderer.md), "The discs"), 3,385 in the docked code's home
bank (below `QSL`) and 18 after its blueprints, 5,568 in its cold bank, 1 in
resident block A and 7 in the glue, 17 in the high resident block, 78 in
each program's main RAM part, 128 in bank 6 (without `S_SUN`, 1,151 bytes,
which would leave it 896 short), and in bank 5 43 in its low region
(`&8000-&8FFF`), 56 in its high region (`&9600-&BFBF`) and 260 after
`R_LINE`'s cold part, `R_RESETBUF` and `r_wq`. The flight code's banks are
what the frames can
use; the docked code's are free only while docked.

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
