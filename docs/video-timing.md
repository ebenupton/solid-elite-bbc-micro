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

The port switches with p = 75 (S1) and p = 76 (S2):

| Switch | Line | Its R2 | Its R0 | p that keep the line 128 cycles |
|---|---|---|---|---|
| S1: 2 MHz to 1 MHz | 191 (frame A's last, the screen's last line shown; after its display ends on cycle 64) | 83 | 101 | 75 and 76 |
| S2: 1 MHz to 2 MHz | 311 (frame B's last, in the vertical blank) | 52 | 89 | 75 and 76 |

Each switch has a window of exactly one microsecond, two cycles. A write a
cycle out of it makes the switch line's sync interval wrong, and the error
grows from there (measured in jsbeeb, "Negative control" below).

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
write three cycles later):

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
| 311:72 | `&FE20` = &D8 (MODE 1: 2 MHz, four colours) | the switch: lands with p = 76 |
| 311:78 | R1 = 64 | line 311 is in the vertical blank; before line 0's C0 reaches 32 |
| 311:94 | R2 = 90 | after line 311's sync (cycle 90; its C0 stops at 89); before line 0's C0 reaches the old 52 (its cycle 52) |
| 0:2 | R0 = 127 | after line 311's last tick (cycle 127); before line 0's C0 reaches the old 89 (its cycle 89) |
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
   is: `rwait`, with the probe as its target), 170 microseconds earlier in
   the field than the first read, and then a field and a microsecond later
   each time, until it sees the flag set. That probe is the calibration.
3. The targets are fixed numbers of microseconds from the probe (`RD1`,
   `RD2`, with the odd cycle `RH1`, `RH2`, elite-map.asm), modulo 256.

In jsbeeb the flag is first seen 251 cycles after the 6845's vertical sync
starts: at the sync's end, two lines on. The constants were found in jsbeeb
so that S1 lands with p = 75 and S2 with p = 76, and the calibration was
checked by starting timer 2 at different points against the lines
(`bhsync.mjs --t2skew 1, 7, 33, 101`): the switches land on the same lines
and cycles every time.

Then the loader hands over: it starts timer 1 so that the first rupture
interrupt comes two lines before line 311, and the rupture's S2 turns the
loading screen (1 MHz) into the game's screen. From that switch on, every
line is 128 cycles.

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

`6-harness/bhsync.mjs` runs the gate's pilot and times every horizontal sync
and every vertical sync in 2 MHz cycles, from the loader's handover on (the
title, the docked screens and the game; before it, the original's loading
screen runs at the 1 MHz clock throughout). It fails on any sync interval
other than 128 cycles, on any field whose line count differs from the
first's, and on a run that stops early. It rebuilds jsbeeb's
`Video.polltime` from jsbeeb's own source with hooks, so jsbeeb itself is
not changed. Its options:

* `--screens`, `--views`: the pilot also shows the flight screens (the
  overlays' disc loads) or changes view.
* `--ula`: each write to the ULA's control register by line and cycle, the
  rupture's interrupts, and the intervals after each switch.
* `--inject N`: the fault injection (below).
* `--t2skew N`: holds the CPU N cycles before the loader starts timer 2.

Results on the gated build:

| Run | Iterations | Sync intervals | Lines a field |
|---|---|---|---|
| the gate's run | 10,000 | 13,172,186, all 128 | 312, all 42,217 whole fields |
| `--screens` | 1,500 | 2,913,087, all 128 | 312, all 9,335 |
| `--views` | 1,500 | 2,138,579, all 128 | 312, all 6,853 |
| `--inject 300` | 400 | 655,017, all 128 | 312, all 2,098 |

### Fault injection

`--inject N` holds the CPU for d cycles at each entry to `RUPT` (the clock
and every device go on, as for an interrupt that a `SEI` section or another
handler held off), d going 0, 1, 2, ... N in turn for S1 and for S2
separately. It skips the entries while the disc is in use: holding the
emulated CPU there would also hold off DFS's NMIs, which no `SEI` does on a
real machine. With N = 300 over 400 iterations (1,679 entries for S1 and
1,678 for S2), the switches slipped to later lines as designed, always on
the same cycle: S1 on line 191 (481 times), 192 (730), 193 (466) and 194
and 195 (once each, where an injected delay met another interrupt), S2 on
line 311 (556), 0 (719), 1 (403) and 2 (twice); every interval 128, every
field 312.

### Negative control

Builds with one switch's write a cycle or two off (`RTRIM1`, `RTRIM2`), over
three iterations:

| Build | p | The switch line's interval | Result |
|---|---|---|---|
| S1 - 2 cycles | 73 | 130 | FAIL |
| S1 - 1 | 74 | 130 | FAIL |
| S1 + 1 | 76 | 128 | PASS (in the window) |
| S1 + 2 | 77 | 126 | FAIL |
| S2 - 2 | 74 | 127 | FAIL |
| S2 - 1 | 75 | 128 | PASS (in the window) |
| S2 + 1 | 77 | 129 | FAIL |
| S2 + 2 | 78 | 129 | FAIL |

After a wrong switch the 6845 drifts against timer 2, the later switches
land elsewhere, and fields of 311 or 313 lines follow: the tool sees each.

### MAME

MAME (0.289) cannot check the switch line. Its `mc6845_device` schedules
each line's sync and end as timers when the line starts, at the clock of
that moment, and a change of clock (the BBC driver's `video_ula_w` calling
`set_unscaled_clock`) rescales only the lines after it. A switch line is
therefore always one whole line at one clock there, whatever the cycle of
the write.

## On a real Model B

The emulator fixes everything but two things that real hardware could do
differently from jsbeeb by a cycle: the 1 MHz clock's phase when the ULA
changes it, and when the VIA's CA1 flag sets after the 6845's vertical
sync. Each moves a switch by a whole number of 2 MHz cycles, which the
trims correct: `RTRIM1` (S1) and `RTRIM2` (S2), in elite-map.asm, in 2 MHz
cycles, positive for later.

What to check, with an oscilloscope on the 6845's HSYNC (pin 39) or the
composite sync, triggered on the vertical sync and delayed to line 191
(S1: the bottom of the space view and the top of the dashboard) and to line
311 (S2: the end of the vertical blank):

| The switch line's sync interval | S1: change `RTRIM1` by | S2: change `RTRIM2` by |
|---|---|---|
| 64 microseconds | nothing | nothing |
| 65 (the write is one or two cycles early) | +1, then +1 again if it still reads 65 | |
| 63 (one or two cycles late) | -2, then -1 more if it still reads 63 | |
| 63.5 (one or two cycles early) | | +1, then +1 again if it still reads 63.5 |
| 64.5 (one or two cycles late) | | -1, then -1 again if it still reads 64.5 |

(In jsbeeb S1's window is p = 75 and 76 and the build is on 75; S2's is 75
and 76 and the build is on 76.) The four trims to try, should the interval not read 64: -1 microsecond
(-2), -1/2 (-1), +1/2 (+1), +1 microsecond (+2). After a wrong switch the
next fields drift, so the first field after power-on is the one to read; a
good switch keeps every interval at 64 microseconds, field after field.

The picture: the dashboard's left edge lines up with the space view's, and
its top pixel row is whole and in its colour (yellow, or white with an
escape pod).
