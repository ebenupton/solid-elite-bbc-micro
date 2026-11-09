# The video timing: a 2 MHz screen and a 1 MHz dashboard

The space view is a four-colour screen at the 6845's 2 MHz character clock
(MODE 1's format: 64 bytes, 256 pixels a line), and the dashboard is the
original Model B's, four colours at the 1 MHz character clock (mode 5's
format: 32 bytes, 128 pixels a line, 1,792 bytes, the original's P.DIALS).
The video ULA's control register (`&FE20`, bit 4) picks the character clock,
so the clock changes twice a field, in mid-line. This document is the
timing of those changes: how every horizontal sync stays exactly 64
microseconds from the last, on every line of every field, how that is
proved in the emulator, and how to check it on a real Model B.

Times are in 2 MHz cycles (half a microsecond) unless they say otherwise. A
line's cycle 0 is its first character tick (C0 = 0).

## The field

The field is 312 lines of 64 microseconds (128 cycles), as two CRTC frames,
the rupture (`RUPT`, elite-rupture.asm):

| Lines | CRTC frame | Character clock | What is shown |
|---|---|---|---|
| 0-191 | frame A: 24 rows (R4 = 23, R6 = 24, R7 = 127: no vertical sync) | 2 MHz | the screen buffer on show (`GFRONT`) |
| 192-311 | frame B: 15 rows (R4 = 14, R6 = `PANR`, R7 = 10) | 1 MHz | the dashboard (`PANEL%`, rows 0-6), then the vertical sync, from line 272 (row 10) |

Lines start on a tick of the 1 MHz clock (a line at the 1 MHz clock must,
and a 2 MHz line of 128 cycles keeps the phase), so the 1 MHz ticks fall on
a line's even cycles.

The horizontal registers at each clock put the horizontal sync on cycle 90
(45 microseconds) of every line, as in the original:

| Clock | R0 (total - 1) | R1 (displayed) | R2 (sync position) | R3 (sync widths) |
|---|---|---|---|---|
| 2 MHz | 127 | 64 | 90 | &28 (horizontal 8 characters: 4 microseconds) |
| 1 MHz | 63 | 32 | 45 | &24 (horizontal 4 characters: 4 microseconds) |

The sync pulse keeps its length, 4 microseconds, at both clocks, so R3's
horizontal width is halved at 1 MHz; its vertical width (2 lines) is the
same.

## A change of clock in mid-line

If the clock changes in a line, C0 counts every cycle on one side of the
change and only the even cycles on the other. The line's sync and its end
fall where C0 reaches R2 and R0 at the mixed rate, so the switch line needs
its own R2 and R0. Let the write land so that cycle p is the last cycle at
the old clock (jsbeeb's view: the 6845 is stepped up to and including
cycle p before the write takes effect).

**2 MHz to 1 MHz.** C0 = p at cycle p; the next tick is on the first even
cycle e after p, with C0 = p + 1; on an even cycle c from e on, C0 = p + 1 +
(c - e) / 2. The sync on cycle 90 needs R2' = p + 1 + (90 - e) / 2, and the
last tick on cycle 126 (the next line starting on 128) R0' = p + 1 + (126 -
e) / 2.

**1 MHz to 2 MHz.** The even cycles up to p are ticks, floor(p / 2) + 1 of
them; from p + 1 every cycle is a tick: C0 = floor(p / 2) + (c - p). The sync
on cycle 90 needs R2'' = floor(p / 2) + 90 - p, and the last tick on cycle
127 R0'' = floor(p / 2) + 127 - p.

The port switches with p = 75 at both switches, or with p = 76 at both:
which of the two depends on the half microsecond between the CPU's 1 MHz
bus and the 6845's 1 MHz clock ("Two phases of the 1 MHz clock", below):

| Switch | Line | Its R2 | Its R0 | p that keep the line 128 cycles |
|---|---|---|---|---|
| S1: 2 MHz to 1 MHz | 191 (frame A's last, the screen's last line shown; after its display ends on cycle 64) | 83 | 101 | 75 and 76 |
| S2: 1 MHz to 2 MHz | 311 (frame B's last, in the vertical blank) | 52 | 89 | 75 and 76 |

Each switch has a window of exactly one microsecond, two cycles. A write a
cycle out of it makes the switch line's sync interval wrong, and the error
grows from there (measured in jsbeeb, "Negative control" below). Both
switches land on the window's first cycle in one phase of the 1 MHz clock
and on its second in the other.

### The writes around a switch

A 6845 register write is two 1 MHz (stretched) accesses, `STX &FE00` (the
register) and `STX &FE01` (the value). Each register changes between two
points: after the last moment its old value is needed and before the first
moment its new one is. The hazard above all: C0 must never pass R0, or it
runs on to 255. So the switch line's R0 is written only once the line has
started (C0 is then below it), and the new clock's R0 only once the switch
line has ended, and before the next line's C0 reaches the switch line's R0.

The writes as they land in jsbeeb (the cycle each `STX` or `STA` starts on;
a 6845 write lands three cycles later plus its stretch of one or two, a ULA
write three cycles later), in the phase of the 1 MHz clock in which both
switches land with p = 75 (in the other, every write is a cycle later):

S1 (line 191, then line 192, frame B's first):

| Line:cycle | Write | Its window |
|---|---|---|
| 191:21 | R3 = &24 | after line 190's sync has ended (its width counts at 2 MHz); line 191's sync, on cycle 90, counts at 1 MHz |
| 191:36 | R2 = 83 | after line 190's sync; before line 191's C0 reaches 83 |
| 191:52 | R0 = 101 | after line 190 has ended; before line 191's C0 reaches 101 |
| 191:71 | `&FE20` = &C4 (mode 5: 1 MHz, four colours) | the switch: lands with p = 75 |
| 191:83-107 | the dashboard's colour 2, four palette entries | after line 191's display ends (cycle 64); before line 192, whose pixels are all colour 2 |
| 191:113 | R1 = 32 | after line 191's C0 has passed 64; before line 192's C0 reaches 32 |
| 192:0 | R2 = 45 | after line 191's sync; before line 192's C0 reaches 45 (its cycle 90) |
| 192:26 | R0 = 63 | after line 191's last tick (cycle 126); before line 192's C0 reaches 63 (cycle 126) |
| 192:44-100 | colours 1 and 3, eight palette entries | line 192 shows colour 2 only; line 193 shows them |
| 192:115 on | R4 = 14, R7 = 10, R6 = `PANR`, R12 = the buffer to show next | after frame B has started; R12 before frame A starts |

S2 (line 311, then line 0, frame A's first):

| Line:cycle | Write | Its window |
|---|---|---|
| 311 (as S1) | R3 = &28 | after line 310's sync has ended; line 311's sync counts at 2 MHz |
| 311 | R2 = 52 | after line 310's C0 has passed 52; before line 311's C0 reaches 52 (its cycle 90) |
| 311 | R0 = 89 | after line 310 has ended; before line 311's C0 reaches 89 |
| 311:71 | `&FE20` = &D8 (MODE 1: 2 MHz, four colours) | the switch: lands with p = 75 |
| 311:77 | R1 = 64 | line 311 is in the vertical blank; before line 0's C0 reaches 32 |
| 311:93 | R2 = 90 | after line 311's sync (cycle 90; its C0 stops at 89); before line 0's C0 reaches the old 52 (its cycle 52) |
| 0:1 | R0 = 127 | after line 311's last tick (cycle 127); before line 0's C0 reaches the old 89 (its cycle 89) |
| 0:27 on | R4 = 23, R7 = 127, R6 = 24, R12 = the dashboard | after frame A has started |

The screen's palette (CMYK) goes back at the vertical sync's interrupt
(IRQG), on lines 274-275, in the vertical blank.

## Placing the write on the cycle

### The clock: the user VIA's timer 2

The user VIA's timer 2 runs free (one-shot mode counts on down through 0:
a 16-bit count of microseconds), with its interrupt disabled. It runs from
the same 16 MHz crystal as the 6845's clocks, so it is phase-locked to the
lines: a field is exactly 19,968 counts, &4E00, so a point of the field
has the same low byte in every field. Reading the low byte (`&FE68`) is a
1 MHz access, so the 6502 is in step with the 1 MHz clock after it, and
every cycle from there to the `&FE20` write is counted.

The rupture's interrupts stay on the system VIA's timer 1, free running,
its latch alternating between 192 lines (`RPA`) and 120 (`RPB`), twice a
field: on lines 309 and 189, two lines before each switch. They also drive
the MOS's 100 Hz work, as before: `RUPT` makes the switch first and then
passes the interrupt on to the MOS, so the MOS's own timer work runs just
after a switch, never into one. (Reading timer 2 leaves timer 1's flag for
the MOS.)

### The switch: rwait

`RUPT` comes from `IRQG` with interrupts disabled. `rwait` reads timer 2's
low byte and subtracts the switch's target: the difference is the wait in
microseconds before the fixed sequence of writes, which then lands the
`&FE20` write on its cycle. `rdelay` waits exactly that long: blocks of 8
microseconds in a loop, then a jump into a run of `NOP`s.

If the difference is more than `RWMAX` (80 microseconds), the interrupt came
after the target (another interrupt was being handled, or a `SEI` section
held it off): the wait is then the difference modulo 64, and the switch is
made on the first line after that with the target's phase, a whole number
of lines late, with the same writes in the same order relative to it.
`rslip` counts these. The late path and the on-time path take the same
number of cycles. A late switch is a whole line late, never a fraction:
every line stays 128 cycles. The cost is in the picture only: until the
switch, the dashboard's first lines (S1) or the screen's (S2) show at the
other clock.

The switches together cost about 1,350 cycles per flight iteration (the
gate: 153,010 against 151,657 before the change, 0.89%), mostly the waits.

### Calibration

At start-up the loader (`rcal`, in `LOAD`) finds where the field falls on
timer 2's count, while the loading screen (the original's, at 1 MHz) is up:

1. It waits for the system VIA's CA1 flag (the vertical sync) in a loop and
   notes timer 2.
2. A field later it reads the flag at an exact time (made exact as a switch
   is: `rwait`, with the probe as its target), and then a field and a
   microsecond later each time, until it sees the flag set. That probe is
   the calibration. The first probe is 94 microseconds earlier in the field
   than the first read; a probe reads the flag 45 microseconds after its
   time, so the probes run from about 47 microseconds before the flag sets
   to 49 after.
3. The targets are fixed numbers of microseconds from the probe (`RD1`,
   `RD2`, with the odd cycle `RH1`, `RH2`, elite-map.asm), modulo 256.

Every probe must be on time: `rwait`'s wait to it must be between 0 and
`RWMAX` microseconds, so that the flag is read at the probe's time. A loop
that reads timer 2 (49 microseconds a pass, 65 when the two reads of the
high byte differ) waits until the probe is `RCW` (122) microseconds or
fewer away, and `rwait` reads timer 2 50 microseconds after the loop's last
read, so its wait is 8 to 72 microseconds. As a backstop, a probe that
`rwait` finds late (it counts it in `rslip`) is made again a field later.

In jsbeeb the flag is first seen about 250 cycles after the 6845's vertical
sync starts: at the sync's end, two lines on. The constants were found in
jsbeeb so that both switches land with p = 75 in one phase of the 1 MHz
clock and p = 76 in the other. The calibration is checked at sixteen boot
phases on both jsbeeb versions (`bversions.sh`, below) and by starting
timer 2 at different points against the lines (`bhsync.mjs --t2skew`): the
switches land on the same lines and cycles every time, for each phase of
the 1 MHz clock.

Then the loader hands over: it starts timer 1 so that the first rupture
interrupt comes two lines before line 311, and the rupture's S2 turns the
loading screen (1 MHz) into the game's screen. From that switch on, every
line is 128 cycles.

### Two phases of the 1 MHz clock

The CPU's 1 MHz bus (the cycle stretching of its accesses to the VIAs and
the 6845, and the VIAs' count) and the 6845's character clock at 1 MHz both
tick once a microsecond, on alternate 2 MHz cycles. Whether their ticks fall
on the same cycles or on the other cycles is the half microsecond that the
calibration cannot see: it reads the vertical sync's flag through the VIA,
to the microsecond, on the bus's ticks. If the two are a cycle apart rather
than in step, every write lands a cycle later against the lines than the
calibration expects.

In jsbeeb the two are separate counters: the CPU's cycle count (`polltimeAddr`
in its 6502.js stretches a 1 MHz access by `1 + ((cycles ^
this.currentCycles) & 1)`) and the video's `oddClock` (`Video.polltime`
skips the 6845 on alternate cycles while `halfClock` is set). A hard reset
(`reset(true)` in its 6502.js: power on, the web page's autoboot when a disc
is loaded, or the harness's SHIFT+BREAK) sets the CPU's `currentCycles` to 0
and leaves the video's `oddClock` as it was, so the phase between the two
depends on whether the reset came on an odd or an even cycle: about half of
all boots have each. Both jsbeeb 1.6.0 and 2.19.0 do this (1.6.0: src/6502.js
line 1269, the reset, and 1296, the stretch; src/video.js lines 852-856,
`oddClock`, which its `reset` at line 535 leaves alone; 2.19.0: src/6502.js
lines 1700-1703 and 1722, src/video.js lines 675-684 and 1221-1225). On a BBC Micro
the two clocks come from the one divider chain in the video ULA, from the
16 MHz crystal, which no reset touches, so a given machine has one phase,
always; which one is the 6845 clock that the ULA gates for its 1 MHz modes
against the 1 MHz system clock, and is not known for a real ULA (Ferranti or
VLSI) here.

The port works in either phase. Each switch's window is two cycles, p = 75
and 76, and the switches land on 75 in the phase in which the calibration
is exact and on 76 in the other (`bhsync.mjs` prints the phase of each run,
as "the 6845's 1 MHz clock against the CPU's 1 MHz bus": 0 or 1).

### Disc access

DFS transfers sectors on NMIs, which no `SEI` holds off, so a switch could
be broken in its middle. Every disc command in the port starts with `dfsin`
and ends with `dfsout` (elite-resident.asm), so `dfsin` stops the switching:
`rdin` sets `rdisc` and waits, if frame B is at 1 MHz, until S2 has switched
back. From then on the rupture leaves the whole field at 2 MHz, frame B
with no rows shown: the dashboard is blank while the disc is in use.
`dfsout` clears `rdisc` (`rdout`), and the next S1 switches again. A disc
error ends at the break handler instead, `BRKR`, which clears it too.

Every route to a disc command:

* `PCLI` (the programs' `OSCLI`: `OSCLI = PCLI` in both sources): program
  loads (`L.` and `R.`), the blueprint loads (`LOMOD`), the docked code's
  disc menu (`*CAT`, `*DELETE`) and other `*` commands, which it passes to
  the MOS; it calls `dfsin` first and ends through `dfsout` on every path.
* `ovload`, the flight code's overlay loader: `dfsin`, `CATD`, `pload`,
  `dfsout`.
* `CATD` (the catalogue): in `LOMOD`, in the flight code at its other call,
  and in the docked code's disc menu, each between `dfsin` and `dfsout`.
* The commander's save and load (`OSFILE`, in the docked code), between
  `dfsin` and `dfsout`.
* The loader's own disc commands come before the rupture starts.

The game's other `OSWORD` calls are the sound (7) and the line input (0).
No other NMI source fires in the game: the Model B has no Econet station
fitted here, and the 8271 raises NMIs only during a command.

## The proof

### jsbeeb

jsbeeb models a change of clock within a line at 2 MHz-cycle resolution: its
`Video.polltime` steps the 6845 once per 2 MHz cycle and skips the odd
cycles while the ULA's control register selects the 1 MHz clock, so C0, the
sync and the line's end follow the clock from the cycle of the write. Its
accesses to `&FE00` (the 6845) and the VIAs are stretched to the 1 MHz
clock, and `&FE20` is not (`is1MHzAccess` in its 6502.js).

Both jsbeeb 1.6.0 (the harness's) and jsbeeb 2.19.0 (the web emulator's,
at bbc.xania.org) model all of this the same way: between the two, the
video ULA's and the 6845's code gained a repaint of the second half of a 1
MHz cell after a ULA write (rendering only), buffered cell drawing, and
fixes to the 6845's interlace, none of which this screen uses, and the
VIAs changed in timer 2's pulse counting and shift register modes and
the keyboard's CA2, none of which the port uses. The two run the port's video identically: the
same sync intervals, the same switches on the same cycles, the same
screenshots, byte for byte (`bversions.sh`, below). Runs that load from
the disc differ in their length between the two (the disc's emulation
changed), and each passes.

`6-harness/bhsync.mjs` runs the gate's pilot and times every horizontal sync
and every vertical sync in 2 MHz cycles, from the loader's handover on (the
title, the docked screens and the game; before it, the original's loading
screen runs at the 1 MHz clock throughout). It fails on any sync interval
other than 128 cycles, on any field whose line count differs from the
first's, and on a run that stops early. It rebuilds jsbeeb's
`Video.polltime` from jsbeeb's own source with hooks (and takes the
vertical sync from the system VIA's CA1), so jsbeeb itself is not changed;
it runs on either version (`JSBEEB`). It prints the run's phase of the 1
MHz clock. Its options:

* `--screens`, `--views`: the pilot also shows the flight screens (the
  overlays' disc loads) or changes view.
* `--ula`: each write to the ULA's control register by line and cycle, the
  rupture's interrupts, and the intervals after each switch.
* `--inject N`: the fault injection (below).
* `--t2skew N`: holds the CPU N cycles before the loader starts timer 2.

`BOOTPRE=N` in the environment boots N cycles later (as every harness
tool does): another phase of timer 2 against the field, and of the 1 MHz
clock. `6-harness/bversions.sh` runs `bhsync.mjs` at sixteen boot phases
(`BOOTPRE` 0, 1, 2, 3, 5, 8 ... 987) on both jsbeeb versions, 20 iterations
each, about half of them in each phase of the 1 MHz clock, and compares
`bshot.mjs`'s screenshots at iterations 50, 200 and 400 between the two
versions.

Results on the gated build:

| Run | jsbeeb | Iterations | Sync intervals | Lines a field |
|---|---|---|---|---|
| the gate's run | 1.6.0 | 10,000 | 22,005,740, all 128 | 312, all 70,530 whole fields |
| the gate's run | 2.19.0 | 10,000 | 21,914,846, all 128 | 312, all 70,239 |
| `--screens` | 1.6.0 | 1,500 | 4,471,602, all 128 | 312, all 14,331 |
| `--screens` | 2.19.0 | 1,500 | 4,530,505, all 128 | 312, all 14,519 |
| `--views` | 1.6.0 | 1,500 | 3,665,150, all 128 | 312, all 11,746 |
| `--views` | 2.19.0 | 1,500 | 3,647,052, all 128 | 312, all 11,688 |
| `--inject 300` | 1.6.0 | 400 | 1,352,745, all 128 | 312, all 4,334 |
| `--inject 300` | 2.19.0 | 400 | 1,330,804, all 128 | 312, all 4,264 |
| `--inject 300`, the other phase (`BOOTPRE=1`) | 1.6.0 | 400 | 1,352,746, all 128 | 312, all 4,334 |
| `--t2skew` 1, 7, 33, 101 | 1.6.0, and 2.19.0 in the other phase | 20 each | 92,693 each, all 128 | 312 |
| `bversions.sh`: sixteen boot phases | both | 20 each | 92,693 each, all 128 | 312 |

The screenshots at iterations 50, 200 and 400 are the same on both
versions, byte for byte.

### Fault injection

`--inject N` holds the CPU for d cycles at each entry to `RUPT` (the clock
and every device go on, as for an interrupt that a `SEI` section or another
handler held off), d going 0, 1, 2, ... N in turn for S1 and for S2
separately. It skips the entries while the disc is in use: holding the
emulated CPU there would also hold off DFS's NMIs, which no `SEI` does on a
real machine. With N = 300 over 400 iterations (3,903 entries for S1 and
3,902 for S2), the switches slipped to later lines as designed, always on
the same cycle; every interval 128, every field 312, on both versions and
in both phases of the 1 MHz clock.

### Negative control

Builds with one switch's write a cycle or two off (`RTRIM1`, `RTRIM2`), over
three iterations, in each phase of the 1 MHz clock (`BOOTPRE` 0 and 1):

| Build | p, phase 0 | Result | p, phase 1 | Result |
|---|---|---|---|---|
| S1 - 2 cycles | 73 | FAIL (130) | 74 | FAIL (130) |
| S1 - 1 | 74 | FAIL (130) | 75 | PASS |
| as built | 75 | PASS | 76 | PASS |
| S1 + 1 | 76 | PASS | 77 | FAIL (126) |
| S1 + 2 | 77 | FAIL (126) | 78 | FAIL |
| S2 - 2 | 73 | FAIL (127) | 74 | FAIL (127) |
| S2 - 1 | 74 | FAIL (127) | 75 | PASS |
| as built | 75 | PASS | 76 | PASS |
| S2 + 1 | 76 | PASS | 77 | FAIL (129) |
| S2 + 2 | 77 | FAIL (129) | 78 | FAIL (129) |

(the switch line's interval in brackets). Each switch's window is the two
cycles 75 and 76, and the build is on 75 in phase 0 and 76 in phase 1:
no trim works in both phases but the one built.

After a wrong switch the 6845 drifts against timer 2, the later switches
land elsewhere, and fields of 311 or 313 lines follow: the tool sees each.

### MAME

MAME (0.289) cannot check the switch line. Its `mc6845_device` schedules
each line's sync and end as timers when the line starts, at the clock of
that moment, and a change of clock (the BBC driver's `video_ula_w` calling
`set_unscaled_clock`) rescales only the lines after it. A switch line is
therefore always one whole line at one clock there, whatever the cycle of
the write.

### b2

Tom Seddon's b2 (https://github.com/tom-seddon/b2, at commit `2cd8e53a`)
runs the port as jsbeeb does, switch for switch: every horizontal sync
interval 128 cycles, every field 312 lines, and b2's TV locked throughout.

b2 models what the screen depends on at 2 MHz-cycle resolution too.
`BBCMicro::UpdateTemplated` (src/beeb/src/BBCMicro_Update.inl) steps the
6845 on every 2 MHz cycle while the ULA's control register selects the fast
clock, and on the 1 MHz clock's cycles only otherwise, so a change of clock
takes effect in mid-line, from the cycle of the write. Its 6845
(src/beeb/src/crtc.cpp) ends a line where C0 equals R0, starts the sync
where it equals R2, and latches the end of a frame (R4, R9) at column 1 of
the frame's last line; the port writes R4 a line or more away from that.
Unlike jsbeeb, b2 takes the CPU bus's 1 MHz clock (the stretched accesses,
the VIAs) and the 6845's 1 MHz clock from the same bits of one cycle count,
so it has one phase between the two, whatever the boot. Its TV
(src/beeb/src/TVOutput.cpp) is driven by the syncs: a horizontal sync
during a line's 52 microseconds of scan starts the retrace at once, and the
TV ignores the input for the next 12 microseconds (retrace and back porch);
a line with no sync retraces on its own after 64 microseconds, so a sync
interval longer than 128 cycles makes the TV miss the next sync, and it
then runs a cycle out of step with the syncs, ignoring them, until its next
vertical retrace. A vertical sync is taken only 1/65 to 1/45 of a second
after the last (else it is ignored), and after 500 lines with none the TV
retraces anyway. b2 is strict about a long line, then, and lenient about a
short one; the port's lines are all 64 microseconds exactly.

The check is `6-harness/b2/` (no window, ever): `build.sh` builds b2's core
library (libbeeb) and `b2drive.cpp`, a headless driver against it, through
b2's own CMake build with `b2drive.cmake` hooked in (b2 is not changed or
copied into this repository); `b2drive` makes b2's default Model B (OS 1.20,
BASIC II, Acorn's 1770 DFS 2.26, the "B/Acorn 1770 DFS" configuration) with
sideways RAM in banks 4 to 7, boots the disc with SHIFT+BREAK, plays a
script of key presses (`fly.txt`: the title, the docked screen, a launch,
the four views, the docking computer, the hangar, the docked screens), and
writes b2's TV picture as PNG files. It times every edge of the 6845's
syncs as b2 emits them, runs a mirror of the TV's state machine on the same
signal (its retraces on a sync and on its own, the syncs it ignores, the
vertical syncs it takes and rejects), and lists the ULA's control writes by
the line and cycle they land on. `b2sweep.sh` runs it at boot phases, as
`bversions.sh` does for jsbeeb: SHIFT+BREAK after 0, 1, 2, 3, 5, 8 ... 987
cycles more, and cold boots (power on with SHIFT held) at the four phases
of b2's 4 MHz count, each to the script's end, 155 emulated seconds.

Results on the gated build (48e3f9f):

| Run | Sync intervals | Lines a field | b2's TV |
|---|---|---|---|
| `b2sweep.sh`, 16 warm boot phases | 2,217,844 to 2,218,816 each, all 128 | 312, all (7,108 to 7,111 fields) | every retrace on a sync, no sync ignored, every vertical sync taken: 300 lines and 39,936 cycles a field |
| `b2sweep.sh`, 4 cold boots | 2,214,241 each, all 128 | 312, all 7,097 | the same |

In every run both switches land with p = 76, the window's second cycle, as
jsbeeb's runs in its phase 1 do; a switch made a line or more late (`rslip`,
9 to 23 in a run of 155 seconds, held off by the disc's interrupts and the
MOS's `SEI` sections)
lands on the same cycle. The negative control behaves as jsbeeb's phase 1
does: with `RTRIM1` and `RTRIM2` at -1 the switches land with p = 75 and
pass; at +1, S2 lands with p = 77 and its line is 129 cycles, and b2's TV
then loses the horizontal sync for most of every field (the long line
above). So b2's window is p = 75 and 76, the same as jsbeeb's, and b2 sits
in jsbeeb's phase 1; which of the two phases a real ULA has is still the
oscilloscope's question ("On a real Model B", below).

The picture matches the original's: in the original disc (the Stairway to
Hell release) on b2, the space view's frame and the dashboard start and end
on the same pixel columns (112 and 623 of b2's 736) and the same rows as
the port's, and the port's dashboard on the docked screen is pixel for
pixel the original's but for one bar's length (the game's state at that
moment), its first line (line 192) whole and yellow, where the original's
shows the mode 4 screen's white for its first eight pixels. The original runs at the
MOS's interlaced timing, fields of 312 and 313 lines in turn, which b2's TV
takes as well; the port's fields are all 312 lines (R8 = 0).

Two things show on b2 as they do on jsbeeb, and are the port's, not the
timing's: while a disc command runs (the screen is blank and frame B shows
no rows, "Disc access", above), the space view's last line (line 191) shows
the bytes that the load stages through the buffers; and the first frame
after the docked code loads (the docking tunnel, for a few fields before the
hangar) shows such bytes in its top rows.

## The web emulator, and why it showed the screen torn

On bbc.xania.org (jsbeeb 2.19.0, its "BBC B": the B-DFS1.2 model, as the
harness's) the build before this one could show the space view at the 1
MHz clock and the dashboard at 2 MHz: the space view's lines doubled in
width, with the right half of each shown before the left half (a planet
in two halves, the screen's right border as a bar down the middle, "Front"
and "View" a row apart), and the dashboard as two half-width copies side by
side (each line of it shows two of its character rows at 2 MHz), half its
height, with the memory after it shown below. The emulator's speed readout
("virtual MHz", 10.0 then) is how fast the host runs it, cycles per second
of the time spent emulating; it is not a speed setting and changes nothing.

The harness never saw this because its boot is always the same: the same
cycle for the hard reset and for the loader's start of timer 2. The web
page's boot is a hard reset at whatever moment the disc goes in (its
autoboot, or BREAK), and with `BOOTPRE` the harness shows the same picture
at most boot phases, on jsbeeb 1.6.0 as on 2.19.0. Two faults, both the
port's:

* About half of all boots had the other phase of the 1 MHz clock ("Two
  phases of the 1 MHz clock", above), in which S2 landed with p = 77, a
  cycle out of its window.
* The calibration's wait loop stopped 40 microseconds ahead of each probe,
  less than the 50 after which `rwait` reads timer 2, so `rwait` always
  took its late path and read the flag a whole number of lines after the
  probe's time: one line when it found the probe's time already 10 to 64
  microseconds past, two when 65 to 75. Which depends on where timer 2 falls against
  the field when the loader starts it. At two lines, about one boot in six,
  the first probe already saw the flag, the calibration came out early, and
  the switches landed several microseconds out of their windows. Now every
  probe is on time ("Calibration", above).

Once a switch line's interval is wrong, the lines no longer start on the 1
MHz clock's ticks, the later switches land elsewhere, and the field drifts:
the rupture's frames come out at the wrong clocks. Neither jsbeeb version
is at fault for what the port did; the one emulator difference from real
hardware here is the 1 MHz phase changing with a hard reset, which a real
machine's ULA does not do, and the port now works in either phase. A real
machine would have shown the fault too: the calibration's on every boot in
which timer 2 started at the wrong point, and the phase's if its ULA has
the other phase.

## On a real Model B

The emulator fixes everything but what real hardware could do differently
from jsbeeb by a cycle or so: the phase of the 6845's 1 MHz clock against
the CPU's 1 MHz bus (one of the two in jsbeeb, but fixed on a given
machine), the 1 MHz clock's phase when the ULA changes it, and when the
VIA's CA1 flag sets after the 6845's vertical sync. Each moves a switch by
a whole number of 2 MHz cycles. In jsbeeb, each switch's window is p = 75
and 76, and the build lands both switches on 75 in one phase of the 1 MHz
clock and on 76 in the other, so either phase is right with no trim. The
trims correct anything else: `RTRIM1` (S1) and `RTRIM2` (S2), in
elite-map.asm, in 2 MHz cycles, positive for later.

What to check, with an oscilloscope on the 6845's HSYNC (pin 39) or the
composite sync, triggered on the vertical sync and delayed to line 191
(S1: the bottom of the space view and the top of the dashboard) and to line
311 (S2: the end of the vertical blank). Check several power-ons and
several boots (SHIFT+BREAK after a delay), as the calibration's timer 2
falls differently against the field each time:

| The switch line's sync interval | S1: change `RTRIM1` by | S2: change `RTRIM2` by |
|---|---|---|
| 64 microseconds | nothing | nothing |
| 65 (the write is one or two cycles early) | +1, then +1 again if it still reads 65 | |
| 63 (one or two cycles late) | -1, then -1 again if it still reads 63 | |
| 63.5 (one or two cycles early) | | +1, then +1 again if it still reads 63.5 |
| 64.5 (one or two cycles late) | | -1, then -1 again if it still reads 64.5 |

A trim of one cycle moves a switch out of its window in one of the two
phases (the negative control above), so on a machine whose switches read 64
microseconds untrimmed, leave the trims at 0. The four trims to try, should
the interval not read 64: -1 microsecond (-2), -1/2 (-1), +1/2 (+1), +1
microsecond (+2). After a wrong switch the next fields drift, so the first
field after the handover is the one to read; a good switch keeps every
interval at 64 microseconds, field after field.

The picture: the dashboard's left edge lines up with the space view's, and
its top pixel row is whole and in its colour (yellow, or white with an
escape pod).
