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
   set is at `&B300-&BBFF` (`BPSLOT%`, the original's `XX21` at `&5600`) in
   both: 2,304 bytes, as the blueprints are assembled without their edge
   lists (the `EDGE` macro assembles nothing: every ship is drawn from its
   faces, and nothing reads the edges), so the largest set, `D.MOC`, takes
   1,693 bytes where the original's files take 2,560; the rest holds the
   renderer's data for the set's ships ("Per-set renderer data", below). The blueprints'
   headers, their edge counts included, are as they were. The flight code loads its set from a `D.MOx` file there; the docked
   code's set is its own, assembled with it. The missile's blueprint stays
   in main RAM at `&7F00`, as in the original, where both sets point. Above
   the slot, `&BC00-&BFFF`, are the quarter squares (`QSL`, `QSH`), which
   both programs multiply with and the loader makes once at boot: neither
   program's home image reaches them, and `PCLI` copies a home image and a
   blueprint file into the bank no further.
5. **The MOS's vectors and the filing system see main RAM only.** WRCHV,
   BRKV and IRQ1V point at the loader's resident code, which pages the
   program's home bank in itself. Disc commands and file names must be in
   main RAM, as DFS reads them with its own ROM paged in at `&8000`. Files
   cannot be loaded straight into sideways RAM for the same reason: each is
   loaded into main RAM at `STAGE%` (`&1600`) and copied into its bank.
6. **Page `&0D`** holds only what the original puts there: DFS's NMI routine
   and the loader's `CATD` at `&0D7A`; the build fails if any instruction
   addresses the page outside `CATD` (`mapcheck.py`: "The map").

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
* **`Area: cold 6`** (flight code only) is the second cold pass, in bank 6
  from `C6%` (`&8000`), before the frame layer, in a room of `C6SZ` bytes
  (`elite-map.asm`): code that runs rarely, moved out of the hot side to
  make room there. Its copy, `elite-flight-c6.asm`, is assembled by the
  flight code's layout at `C6%` with its labels named `X_6` and saved as
  `C6.bin`, which bank 6's assembly takes in (`gfx-bank6.asm`), so the bank
  6 image the loader loads holds it; the flight code is the only program
  that reaches it. It is a side of its own, reached and reaching out only
  through stubs: `.X JSR farC6 : EQUW X_6` at its routines' places in the
  hot copies, `.xs_X JSR farC6 : EQUW X_6` in the cold copy (for the cold
  pass and the overlays), and in its own copy `.x6_H JSR farH : EQUW H` and
  `.x6c_C JSR farC : EQUW C_C` at the places of the hot and cold routines
  it calls (it calls the low pass's directly). A cold 6 block may not fall
  into another area, be fallen into, or branch out of its area, and it
  reads only main RAM and itself (`bankcheck.py`). Its routines' variables
  are in bank 6 as loaded once at boot, not reloaded with the flight code:
  a block that relies on its assembled data at each load does not belong
  here.
* **`Area: cold 5`** (flight code only) is the third cold pass, in bank
  5's row runs' tails: the 65 bytes after each run (`C5TAIL0`, `C5TSZ`),
  in the tails that `C5TAILS` lists (`elite-map.asm`: at present tails 7,
  8, 10, 15 and 17 to 23, the ones that hold nothing else, tails 8's and
  10's variables having moved to tail 16; `gfx-raster.asm`'s
  `R_ENDPAGE` fails the build if a listed tail holds a variable, and tails
  11 to 14 hold DFS's page). It is cold 6 again in another bank: its copy,
  `elite-flight-c5.asm`, has its labels named `X_5`, and it is reached
  through `.X JSR farC5 : EQUW X_5` in the hot copies and `.xs5_X` in the
  cold copy, and reaches out through `.x5_H` (`farH`) and `.x5c_C`
  (`farC`) in its own; the same rules hold (no fall into it, no branch
  across its edge, it reads only main RAM and itself, its variables are
  loaded once at boot), and cold 6 and cold 5 do not call each other. As
  the tails are not one room, `streams.py` places the copy in pieces: each
  unit (blocks that fall, branch or run on into one another, with the stub
  its last block falls into and any stub between its blocks) whole in one
  tail, then each other stub, first fit, the largest first, by the sizes
  the measure gives (`C5S_k`, `C5E_k` at each block's ends, the copy
  assembled in one piece); it writes an `ORG` at each piece and an `ASSERT`
  at each unit's end that it is as measured, and the packing, tail by tail,
  at the end of `3-assembled-output/flow-flight.txt`. A unit that fits no
  tail fails the build, naming itself and the room in each tail. The
  flight code's layout saves each tail as `C5_r.bin`, and `bank5.py`, run
  again after the flight code, assembles bank 5 with them in, so that
  `R.BANK` (the whole bank) carries them.
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
  blueprint slot at `&B300`.
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

The renderer's files are placed the same way: each is one file, whatever
places its blocks go to, and each block's place is named by its `Area:`
line: `bank 4` (the flight code's home bank: the planet's surface in game
context, `gfx-planet7.asm` and `gfx-merid.asm`'s first blocks), `bank 5
runs`, `bank 5`, `bank 5 gap` and `bank 5 end` (the row runs' pages, with
the state in their tails; the rasteriser's
code; the room below its per-x tables; the code after the disc layer's
requests), `bank 6` (the frame layer), `bank 7` (the flight code's cold bank:
the disc layer's painter in the renderer's window) and `main` (the glue, in
the resident block A, and after it `gfx-merid.asm`'s `pcb_o`, the records'
offsets, which bank 4's `pc_circ` and bank 6's `PC_ROWS` both read: one copy,
seen with either bank paged), and for the circle engine's variables `main low`
(`PFVA%`, in the resident block A's room), `main high` (`PFVH%`, after the
high resident block) and `bank 4 top` (`PFVS%`, in the flight code's home
bank after the blueprint slot, below the quarter squares), which the flight code's layout places (and
`gfx-bank5.asm` `pf_tilt`'s main high pass, at the same place); no
renderer file has an `ORG`. `streams.py` writes each file's pass for each place
it names (`3-assembled-output/<file>-<place>.asm`, the other lines blanked;
the lines before a file's first `Area:` line, its header, are in every pass
and may hold only comments), and each place's layout INCLUDEs its passes:
`gfx-bank5.asm`, `gfx-bank6.asm`, `elite-layout-flight.asm` and the
resident block. A block in two places' lists (`gfx-merid.asm`'s
definitions) is assembled in both; a table that two banks read is in main
RAM, once.

**The containers.** The passes go into these containers:

* the **main RAM part** of the program, `PROGM%` to `PROGM_END%`
  (`&7970-&7E5F`, after the rupture's code, in the room that the
  original's mode 5 dashboard leaves: main RAM's code is one run, from
  the rupture's to the workspace), with the low pass and then the hot
  pass's main RAM containers: `hotm`, to `PROGH%` (`&7E00`), and `hotx`,
  straight after `hotm`'s units, to the part's end (two containers in one
  run: as one, the flow would interleave `hotx`'s units with `hotm`'s in
  the source's order and move `hotm`'s across page boundaries, and three
  of their branches, `DVID4`'s among them, would cross pages). Main RAM's
  workspace is one run
  from there to `VEC`, around the missile's blueprint, which stays where
  the original has it (`&7F00`): the mailbox (`&7E60-&7EFF`), then the
  shared variables (`GVARS`, `&7FA0`), the palette (`RESH%`, `&7FB0`) and
  the circle engine's variables (`PFVH%`, `&7FC0`, to `VEC`).
  The program's layout file assembles the part there and copies its bytes
  into its bank 4 image at `PROGI%` (the flight code's at the start of its
  blueprint slot, which `LOMOD` then loads a set over; the docked code's
  below its blueprint slot); `S%+14` gives where that image is while
  `PCLI` stages the bank 4 image, and `PCLI` copies it to its place each time it loads the program;
* the hot pass's bank 4 container (`hot`), from `S%` at `&8000` (`HOME%`)
  to the room that the layout keeps at the bank's end: in the flight code
  with `_CIRCLES`, the planet's surface (`CIRCSZ`, 2,706 bytes); then the
  blueprint slot and the quarter squares (`QSL`, `QSH`, which the loader
  makes: in both programs, the lighting's `L_REC` reads them);
* the cold pass, bank 7 from `&8000`, then the text tokens `QQ18`, below
  `DFSSAVE%`.

**The flow.** The hot pass is cut into units: runs of blocks that must stay
together, because one falls through into the next (its last statement can
continue, or is a BIT skip, `EQUB &2C` or `&24`), branches into another
(the blocks from one to the other, or to the stub of a routine on the other
side, which sits at that routine's place), runs on into the next, or is
reached from before the next one's entry (the original's `BMI WPLS-1`,
which takes the `RTS` that ends `WP1`, the block before `WPLS`). `S%`'s
unit goes first, at the start of bank 4 (the entry table), and then each
other unit, the largest first, into the first container with room for it:
`hot`, `hotm`, `hotx` (code runs as fast in main RAM as in bank 4), but
a unit that the cold side, cold 6 or cold 5 reads (a table such as `UNIV`, not a
call, which goes through a stub) goes into `hotm` or `hotx`, as bank 4 is
not paged in there. Each
container's copy assembles its units in the source's order. The sizes are
measured, not estimated: the Makefile runs `2-build-files/streams.py`
twice. `streams.py measure` writes each program's hot pass as one copy,
with a label `FLOW_<n>` at each block, which `elite-measure-flight.asm` and
`elite-measure-docked.asm` assemble for each block's size
(`3-assembled-output/measure-<program>-symbols.txt`); `streams.py place`
then flows the units by those sizes. A block's size does not depend on
where it goes. `3-assembled-output/flow-flight.txt` and `flow-docked.txt`
list every container and its units.

The main RAM part is 1,264 bytes (`hotx` 96 of them): the rest of main RAM is
the screen's (both buffers, `&1000-&6FFF`, and the dashboard,
`&7000-&76FF`), the rupture's, the workspaces' and the resident block's.
The low pass holds `WSCAN` and `DELAY`, which the cold pass calls directly.
Without `_CIRCLES` bank 4 holds the whole of each hot pass, so the main RAM
containers are empty; with it, the flight code's hot pass fills `hotm`, and
all 96 of `hotx`.
A low block may not fall into a cold one (its stub would be in the low
pass); a hot block that falls into a low one falls into a `JMP` to it at
its place. The stubs for a cold block go in the copy of the nearest hot
block before it, so that a branch to them stays in reach.

**The copies.** BeebAsm assembles with one location counter, and the banks
share the addresses `&8000-&BFFF`. So `streams.py` writes one copy of each
program's source per container into `3-assembled-output`
(`elite-flight-config.asm`, `-low.asm`, `-hot.asm`, `-hotm.asm`,
`-hotx.asm`, `-blueprints.asm`, `-cold.asm`, and the same for the docked
code), with the other lines blanked, so that line numbers stay the
source's. `elite-layout-flight.asm` and `elite-layout-docked.asm`, which
the Makefile assembles, INCLUDE a program's copies in turn, each at its own
address. Each label is defined once and each block is assembled once.

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
block of its own pass (a block's last statement is the last that assembles
anything: a constant, a `PRINT` or an `ASSERT` after it does not end the
fall, and a label alone falls into the next block); that each hot block
that falls through ends where the block it falls into starts, by an
`ASSERT` in the copies, which BeebAsm checks; that a reference to the
bytes before a block's entry (`X-n`, with `X` a label at the block's
start) finds the block before it, which assembles, in the same pass, and
an `ASSERT` in its copy that it ends where `X` starts; that no block branches into another pass of its
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

Then `2-build-files/mapcheck.py` checks the map ("The map", below).

## Calls between regions

| Kind | Where | Pages |
|---|---|---|
| `farC` and `farCj` stubs (`.TT22 JSR farC : EQUW TT22_C`), generated into the home copies | each at its cold routine's place | the cold bank in, then the caller's bank back |
| `farC6` stubs (`.DET1 JSR farC6 : EQUW DET1_6`, or `.xs_DET1` in the cold copy), generated into the home and cold copies | each at its cold 6 routine's place | bank 6 in, then the caller's bank back |
| `farC5` stubs (`.TAS4 JSR farC5 : EQUW TAS4_5`, or `.xs5_X` in the cold copy), generated into the home and cold copies | each at its cold 5 routine's place | bank 5 in, then the caller's bank back |
| `farH` and `farHj` stubs (`.xh_TT26 JSR farH : EQUW TT26`), generated into the cold copies | each at its home routine's place | the home bank in, then the cold bank back |
| `WRCHR` (WRCHV) | the resident block | the home bank in, then `JSR S%+6` (`JMP TT26` in the flight code, `JMP CHPR` in the docked code), then the caller's ROM back |
| `BRKR` (BRKV) | the resident block | the home bank in, then `JMP S%+11` (`JMP BRBR1`, or in the docked code the handler that `BRKBK` and `SVE` set) |
| `PCLI` (the programs' `OSCLI`) | the resident block | loads a program or a blueprint file into its banks through `STAGE%`, or passes the command to the MOS from main RAM |

A far call costs about 110 cycles (`farC6` and `farC5` as `farC`) and three bytes of stack, and passes A, X,
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
four banks and makes the quarter squares at the top of the home bank
(`QSL`, `QSH`, `&BC00-&BFFF`). Its last part, `LOAD`, runs at `&0B00`, as the original's did
(two pages now): it copies the high resident block to `RESH%`, loads the
renderer's banks (`R.BANK`, `F.BANK`, through `STAGE%`) and starts the frame
layer (`F_INIT`), loads the docked code with "L.T.CODE" through `PCLI` and
the dashboard's image `P.DIALS` (the original's) to `PANEL%`, copies the
rupture's code to `RUPT%`, starts the user VIA's timer 2 and calibrates it
against the field (`rcal`), switches to the game's screen and starts the
rupture (`IRQG`, `RUPT`: [video-timing.md](video-timing.md)), points WRCHV and BRKV at
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
`&90-&E1` in bank 7's workspace at `OVSTASH` (`&B300`, buffer 0's disc
state, which the load makes dead), puts DFS's workspace back (`dfsin`),
reloads the catalogue (`CATD`), loads `D.OVn` to `STAGE%` with `pload` and
copies it to `OVL%`, keeps DFS's workspace (`dfsout`), puts the rest back
and marks buffer 0 as used (`GSTASH`: the next frame starts it afresh and
forgets its disc state). The bank 7
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

A type the set does not have has no normals and an empty face list, but
for one: the escape pod's launch (`ESCAPE`) shows our Cobra Mk III with
`TYPE` = `CYL`, and in a set without it (`D.MOA`, `D.MOH`, `D.MOI`,
`D.MOJ`, `D.MOM`) launches the pirate's (`CYL2`) with `TYPE` still `CYL`, so
in those sets type `CYL`'s entries are the pirate's normals and face lists,
whose blueprint `LL9` draws.

## The map

The map as built: `2-build-files/bmap.py` writes it at every build, from
the build's symbols, `elite-map.asm`'s constants and the sizes the
assemblies print, into `3-assembled-output/memory-map.md`; this is that
table for the standard build (with `_CIRCLES` and `_SSUN`). A place's used
bytes are what its contents take (a workspace's, what its declarations
take), its free bytes the room left in it. The places of the two programs
(flight, docked) hold one program at a time; the flight code's banks are
what the frames can use, the docked code's are free only while docked.

| Place | Addresses | Holds | Used | Free |
|---|---|---|---:|---:|
| main RAM | `&0000-&00FF` | zero page: the game's (the rasteriser's &06-&27 and the frame layer's &D2-&E1 during a frame, kept) | 256 | 0 |
| main RAM | `&0100-&01FF` | the stack, down from `&01FF`, and `XX3`, the heap of projected vertices, up from `&0100`, sharing the page as in the original (as measured over the gate's runs and an eight-session soak, `page1Watch`: in flight the stack down to `&01BA` and `XX3` up to `&016F`, 74 bytes untouched; docked the stack down to `&01B1`, `XX3` up to `&0193` and the filing system's writes up to `&010B`, 29 untouched) | 256 | 0 |
| main RAM | `&0300-&03CF` | `UP`, the game's workspace | 208 | 0 |
| main RAM | `&0400-&06E5` | resident block A (`elite-resident.asm`): `BANKS`, the far calls, `PCLI` with `dfsin`, `dfsout`, `pload`, `WRCHR`, `BRKR`, the last saved commander and the break handler, `IRQG` | 739 | 3 |
| main RAM | `&06E6-&0723` | the circle engine's variables (main low: `gfx-merid.asm`) | 50 | 12 |
| main RAM | `&0724-&07BF` | the glue: the trampolines into bank 5, `GCALL`; then `pcb_o`, the circle engine's table that banks 4 and 6 read (main: `gfx-merid.asm`) | 131 | 25 |
| main RAM | `&07C0-&07FF` | `SNE`, `ACT` | 64 | 0 |
| main RAM | `&0880-&08BF` | `QQ16` | 64 | 0 |
| main RAM | `&0900-&0CFF` | `K%` and the line heaps (the loader's `LOAD` at `&0B00` before the game) | 1024 | 0 |
| main RAM | `&0D7A-&0D9D` | `CATD` | 36 | 0 |
| main RAM | `&0E00-&0FD2` | `WP` | 467 | 0 |
| main RAM (flight) | `&0FD3-&0FF8` | the parked sun, `SUNPK` and `SUNPF`, in `WP`'s tail (DFS's catalogue's end between disc commands: `CATD` reads it back before each one, and `ovload` keeps `WP` across an overlay's load) | 38 | 0 |
| main RAM | `&1000-&3FFF` | buffer 0 (DFS's page `&1000` between disc commands kept in bank 5, `DFSTAIL%`; `STAGE%` from `&1600` during a load) | 12288 | 0 |
| main RAM | `&4000-&6FFF` | buffer 1, the screen | 12288 | 0 |
| main RAM | `&7000-&76FF` | the dashboard (`P.DIALS`) | 1792 | 0 |
| main RAM | `&7700-&796F` | the rupture (`elite-rupture.asm`, copied there by the loader): the clock switches, the frames' registers, the flip, the display off during disc commands; its variables after its code | 624 | 0 |
| main RAM (flight) | `&7970-&7E5F` | the main RAM part: the low pass, then `hotm` and `hotx` (main RAM's code is one run, from the rupture's) | 989 | 275 |
| main RAM (docked) | `&7970-&7E5F` | the main RAM part: the low pass, then `hotm` and `hotx` (main RAM's code is one run, from the rupture's) | 168 | 1096 |
| main RAM | `&7E60-&7EFF` | the mailbox, `MBOX`: the rasteriser's inputs (the stars at its end, `&67-&9F`); sharing its polygon vertices, `PCLI`'s command and OSFILE block, the circle records from `PF_HOOK` to the frame (`&00-&49`, `&52-&5D`) and the disc layer's batches (`&00-&65`) | 160 | 0 |
| main RAM | `&7F00-&7F9F` | the missile's blueprint (where the original has it) | 160 | 0 |
| main RAM | `&7FA0-&7FAF` | `GVARS`, the renderer's shared variables (the game's hooks, the interrupt and the frame layer's) | 16 | 0 |
| main RAM | `&7FB0-&7FBF` | the high resident block: the palette | 16 | 0 |
| main RAM | `&7FC0-&7FFD` | the circle engine's variables (main high: `gfx-planet7.asm`, `gfx-merid.asm`) | 59 | 3 |
| main RAM | `&7FFE-&7FFF` | `VEC` | 2 | 0 |
| bank 4 (flight) | `&8000-&A8A5` | `S%` and the hot pass | 10406 | 0 |
| bank 4 (flight) | `&A8A6-&B2FF` | the planet's surface (bank 4 passes: `PF_HOOK`, `pc_circ`) | 2650 | 0 |
| bank 4 (flight) | `&B300-&BBA1` | the blueprint set (`D.MOx`), its normals and `FC_NORMTAB` (the image holds the main RAM part's image here) | 2210 | 0 |
| bank 4 (flight) | `&BBA2-&BBFF` | the circle engine's variables (bank 4 top) | 31 | 63 |
| bank 4 (flight) | `&BC00-&BFFF` | the quarter squares `QSL`, `QSH` (made by the loader) | 1024 | 0 |
| bank 4 (docked) | `&8000-&AE0F` | `S%` and the hot pass | 8787 | 3005 |
| bank 4 (docked) | `&AE10-&B2FF` | the main RAM part's image | 1264 | 0 |
| bank 4 (docked) | `&B300-&BBA1` | the docked code's blueprints, their normals and `FC_NORMTAB` | 2144 | 66 |
| bank 4 (docked) | `&BBA2-&BBFF` | (free) | 0 | 94 |
| bank 4 (docked) | `&BC00-&BFFF` | the quarter squares `QSL`, `QSH` (made by the loader) | 1024 | 0 |
| bank 7 (flight) | `&8000-&9E6B` | the cold pass, `QQ18` | 7788 | 0 |
| bank 7 (flight) | `&9E6C-&A2B5` | the overlay region (`D.OV1` 1098 bytes, `D.OV2` 793) | 1098 | 0 |
| bank 7 (flight) | `&A2B6-&B3FF` | the renderer's window (bank 7 passes: the disc layer's painter with its strips, the second disc, their operands' patch) | 3910 | 516 |
| bank 7 (flight) | `&B400-&BFFF` | the workspace: each buffer's disc state (not in the image: `DP_BEGIN` sets it up), buffer 0's sharing its first `&2E2` bytes with `ovload`'s stash of `WP` and the zero page during an overlay's load (`OVSTASH`) | 3072 | 0 |
| bank 7 (docked) | `&8000-&BFFF` | the set's face lists, the cold pass, `QQ18` | 11397 | 4987 |
| bank 5 | `&8000-&97FF` | the 24 row runs, a page each; in their tails the stars' records and variables, `R_LINE`'s, DFS's workspace page between disc commands (`DFSTAIL%`: 64 bytes in each of four), and in tails 7, 8, 10, 15, 17, 18, 19, 20, 21, 22, 23 the flight code's cold 5 pass (`Area: cold 5`: `elite-flight-c5.asm`, `C5_r.bin`; `C5TAILS`), and in the ends of tails 0, 1, 2, 3, 4, 5, 6, 9, from byte 52 on, more of it (`C5_rp.bin`; `C5PTAILS`, `C5POFF`) (free: the 0 other tails with nothing in them, 65 bytes each, the rest of the others, and the cold 5 tails' room) | 6059 | 85 |
| bank 5 | `&9800-&A7FF` | `R_POLY`, `R_LINE`; at the top, the flight code's cold 5 pass's place `C5LO%` (62 bytes) | 3978 | 118 |
| bank 5 | `&A800-&ADFF` | the state: the dirty and written extents, `R_POLY`'s edge tables | 1536 | 0 |
| bank 5 | `&AE00-&B0A2` | `R_SETBUF`, `r_pgfix`, the spans' core, the arithmetic | 675 | 0 |
| bank 5 | `&B0A3-&B3FF` | the room below the per-x tables: `R_LINE`'s cold part, the private state, `R_RESETBUF`, `r_wq`, `R_MARKBOX`, `pf_tilt`; at the top, the cold 5 pass's place `C5GAP%` (25 bytes) | 861 | 0 |
| bank 5 | `&B400-&BF99` | the per-x tables, the row pages, the stars, `r_setup`, the repair, `R_GETW`, `r_pclip`, `r_pset`, `R_SPAN`, `R_DOT`, `R_MARKDIRTY`, `R_INIT` | 2970 | 0 |
| bank 5 | `&BF9A-&BFFF` | `RJT`, the jump table; at the top, the cold 5 pass's place `C5HI%` (35 bytes) | 77 | 25 |
| bank 6 | `&8000-&8102` | the flight code's cold 6 pass (`Area: cold 6`: `elite-flight-c6.asm`, `C6.bin`; the room `C6SZ`) | 259 | 0 |
| bank 6 | `&8103-&ABFF` | the frame layer's code (bank 6 passes) | 11005 | 0 |
| bank 6 | `&AC00-&AF1D` | the faces' and the lighting's tables | 798 | 0 |
| bank 6 | `&AF1E-&AF2B` | (free: the state that follows is placed as high as it goes) | 0 | 14 |
| bank 6 | `&AF2C-&B1FF` | the state: the ship records, the zero page `F_FRAME` keeps, the faces' levels, the docking slot, the planet's records kept | 724 | 0 |
| bank 6 | `&B200-&BC70` | the state, page aligned: the discs' half-widths (`F_INIT`'s code in the sun's until they are first written), the text map, the discs' rows | 2659 | 14 |
| bank 6 | `&BC71-&BFBF` | `FCSLOT`: the face lists of the set loaded | 847 | 0 |
| bank 6 | `&BFC0-&BFFF` | `FJT`, the dispatcher; in the last 12 bytes the hangar's background's jumps into the bank (`FHV%`) | 58 | 6 |

Free, by place: main RAM 43, main RAM (flight) 275, main RAM (docked) 1096, bank 4 (flight) 63, bank 4 (docked) 3165, bank 7 (flight) 516, bank 7 (docked) 4987, bank 5 228, bank 6 34.

**The build's check.** `2-build-files/mapcheck.py`, which `make` runs once
every program and bank is assembled, fails the build if a place is out of
order with, or overlaps, the next in its address space (main RAM; banks 4
and 7, once for each program; banks 5 and 6), or runs past its room; if a
label that a pass copy defines lies outside the place that the copy is for
(each program's low, hot, `hotm`, `hotx`, cold, overlay and blueprint
copies, and each renderer pass, its variables' passes included); if a pass
copy that defines a label is INCLUDEd by no assembly; or if an instruction
of any assembly addresses page `&0D` outside `CATD` (`&0D7A-&0D9D`), what
the original puts there.

Without `_CIRCLES` (`make circles=off`), the flight code's home bank has
1,527 bytes free and its main RAM part 1,198, the planet's surface
and the circle engine's variables being absent; the rest is as above.

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
