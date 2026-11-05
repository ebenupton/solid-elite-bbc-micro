# agentplay: the original and the port, played side by side by elite-agent

agentplay has [elite-agent](https://github.com/8bitkick/elite-agent) play the released BBC
Micro disc Elite (the gate's reference, `4-reference-binaries/sth`, with the gate's patches)
while the Model B port replays the same inputs at the same reads. It compares the two
machines' game state at every main-loop iteration, and their dashboards byte for byte. It
reports the first divergence, with the input log that reproduces it, and catches crashes,
hangs, BRKs, page `&0D` writes and differing save files.

It is the Master port's agentplay (`master/tools/agentplay` in that repository), for
`blib.mjs`'s Model B machines. It runs headless on jsbeeb, as the rest of `6-harness`.

## Quick start

```sh
git clone https://github.com/8bitkick/elite-agent ~/elite-agent      # the player (C): read only, its main branch
make                                                                  # 3-assembled-output: the port
sh 6-harness/agentplay/build.sh                                       # 6-harness/work/agentplay/agentd
node 6-harness/agentplay/agentplay.mjs --out 6-harness/work/agentplay/s1 --minutes 10 --seed 1 --mode curious
node 6-harness/agentplay/replay.mjs --run 6-harness/work/agentplay/s1     # the same session again, without the agent
node 6-harness/agentplay/campaign.mjs --out 6-harness/work/agentplay/soak --jobs 2
node 6-harness/agentplay/coverage.mjs 6-harness/work/agentplay/soak [--cand]
```

The reference is `4-reference-binaries/sth/build.json` and the candidate
`3-assembled-output/build.json`; `--ref`/`--cand` take other build.json files.

## How it works

**The agent.** elite-agent's player (`cplayer/`) is C. Once per 50 Hz frame it reads the
machine's 32 KB of main RAM and presses keys. `agentd.c` links the player without
elite-agent's emulator and speaks a pipe protocol (`agent.mjs`). The harness sends the
reference's RAM each frame; agentd answers with key changes, log lines and journal events.
The player knows the disc version, but as Mark Moxon's flicker-free build: twelve of the
addresses it reads differ in the release (the commander block from `QQ8` on, the
configuration bytes, `tek`, `QQ29`), and it recognises that build's code bytes, not the
release's. So `build.sh` makes the release's address table from its symbols
(`gen-ev.mjs`, into the build directory) and agentd sets it as the player's version, on a
Model B, without the player looking. Nothing in the elite-agent checkout is changed. The
player plays the disc version with the keys (no joystick). It never sees the port.

**Inputs at the read, not the frame.** The input model is `blib.mjs`'s: keys are never
pressed on the emulated keyboard; each read the game makes is answered. `lib.mjs` numbers
the reads ("polls"):

- `k`, at `DOKEY`, once an iteration: the keys held for the iteration. `DKS4`'s tests of
  single keys (at `DKS4+17`) and `DK4`'s `RDKEY` (the port's at `Rd2`) answer from it;
- `w`, `RDKEY` from anywhere else: a key wait (`t`, `t2` with `TT217`'s caller, the title
  screens, `PAUSE2`, the pause loop `FREEZE`);
- `d`, `DKS4` for CTRL, from the hyperspace routines;
- `c`, `OSRDCH`, which only `OSWORD 0` calls, from `MT26` (a commander's name in the disc
  menu, a system's name in the chart's search): the next character typed. The call is
  answered without running it, and `OSWORD 0` echoes the character through the game's
  `WRCHV` handler as it would a key. The characters are the keys that go down from the
  line's first read on (the agent's, or the chaos overlay's), as ASCII.

The reference answers each read from the agent's keys, and queues the answer with the
routine that made the read. The candidate takes the queue read for read; at a read the
reference hasn't made yet it stops at that instruction and waits. The kind and routine of
every read must match (a routine's cold body `name_C` and an overlay's copy `name_O` count
as `name`), which checks control flow.

The rest of blib's determinism measures are kept: the laser pulse counted per pass of `M%`,
the sound off from `TT170`, the reference's patches (`ma93-q`, `ee51-c`, `mv8-spin`), the
candidate's boot leftovers seeded from the reference at `TT170`, and the filing system's
bytes: a compared byte the MOS, DFS or the NMI handler wrote is left out of the comparison
until the game writes it, and is set to 0 (above page 0) at each `MLOOP` and pass of `M%`,
and also at each call of `DIALS`: a launch draws the dashboard before the first pass of
`M%`, its altitude from `ALTIT` (`&0FD1`, in `WP`), where the ship file's load has just left
a byte of the disc's catalogue, another on each build's disc.

**Game state.** At every `MLOOP` both machines' state is snapshotted with blib's regions
(zero page, `UP`, the `K%` slots and line heap, `WP`, `NA%`) and compared with the gate's
`--loose` exclusions (`--strict` for none). The first difference is reported field by
field; ship-slot bytes are named by slot and `INWK` field.

**The dashboard** (`observe.mjs`). The port's dashboard is the original's mode 5 image,
drawn by the same code, at `&7000` (`PANEL%`) rather than `&7800`. So at every `MLOOP` in
flight the two are compared byte for byte, and a difference is reported by part (left
dials, scanner and compass, right dials) with the character cells.

**Other checks:**

- **BRKs:** every BRK instruction run once the game has started, with where it was and the
  error after it. A filing-system or OS error (a BRK in a ROM, on the stack page, in the
  MOS) must come in both machines at the same read (else `brk-mismatch`); a BRK in Elite's
  code (main RAM or its sideways RAM banks) is a finding; the same one 20 times ends the
  session.
- **Page &0D writes** by the candidate's game code.
- **Hangs:** no read and no iteration for 30 emulated seconds (`HANG_SECS`); both at the same
  read is `hang-both`, the original's own behaviour (an empty drive), not a port finding.
- **Crashes:** the PC in page 0 or 1.
- **Save files:** after every disc access (`SVE`), once both machines are past the next
  `MLOOP`, and at the end, the commander files (directory `E`) on the two discs must match,
  catalogue and bytes.
- **Coverage:** whole-code coverage by program (the flight and docked programs share
  addresses), labels as `flight:NAME`, `docked:NAME`, and for the port its renderer banks,
  `bank5:NAME`, `bank6:NAME`; the routines entered (`ROUTINES`) and the features reached
  (`session.mjs`'s `features`: fuel and cargo scooped, pod, bomb, galaxies, witchspace,
  missiles, E.C.M., the docking computer, the missions' `TP`, the sun, the station and the
  planet close, Thargoids, Thargons, the Constrictor).

**Play styles** (`styles.mjs`): `--commander` (`jameson`, `trader`, `equipped`, `rich`,
`deadly`, `mission2`, `debrief1`, `galaxy3`, `debrief2`, `wanted`), patched into `NA%` with
its checksum at the first `QU5`; `--mode` (`efficient`, `curious`, `fair`, `nosave`,
`nomission`, `load`, which loads CLAUDE from a disc a session saved: `--refdisc`,
`--canddisc`); `--chaos`, a seeded overlay of keys and pokes for what the agent rarely does
(E.C.M., the energy bomb, the escape pod, the views, missiles, the galactic hyperdrive and
`ghypfill`, hyperspace, mis-jumps (`misjump`: the author names on in the pause, then CTRL
held through a jump), in-system jumps, the docking computer, the charts, the pause, the sun
put just ahead (`sun`), drained shields, heat, an empty tank; docked, from the Status screen,
`disc` (the disc menu: catalogue, a failed load, a failed delete, saves, deletes, bad drives,
names over-deleted) and `docked` (market, data, inventory, charts with the cursor and the
search, equipment, sales)); `--seed`, RAND at `TT170` and the overlay's seed. All of it goes
through the input log, so every session replays exactly.

**Workarounds.** `--workaround inbay` (candidate only, at run time; the port's source is not
changed) plays on past the death bug of a build whose flight code has `INBAY` in main RAM:
after a death, `INBAY`'s `*LOAD` of the docked code returns into the docked code's main RAM
part, a BRK, and the BRK handler hangs; the workaround sends the candidate to the docked
`INBAY`'s `JMP SCRAM` at `&801D`, where the original's `INBAY` returned. Each use is a
`workaround` event, and `summary.json` counts them. Campaigns pass it on (`campaign.mjs
--workaround inbay`), and replays take it from the log's header (`--workaround none` to
turn it off).

## Files a session writes

`config.json`, `inputs.jsonl` (a header with the builds and their hashes, then every read
with a key down or a character, chaos actions and pokes, and an end record), `agent.log`,
`journal.jsonl`, `events.jsonl`, `summary.json` (iterations compared, the divergence,
findings, routine counts, features, the dashboard's checks, save-file checks, the final
state), `coverage-ref.json`, `coverage-cand.json`, screenshots (`*-ref.png`, `*-cand.png`),
and with `--savediscs` both discs as the game left them.

## Repros

`replay.mjs --run DIR` (or `--log inputs.jsonl --out DIR`) plays a log into both machines
again, without the agent, from boot. `--until N` stops after iteration N, `--trace A,B`
writes every labelled routine each machine enters in iterations A to B, `--cut N --save
FILE` writes the log cut short (a minimal repro), and `--cand build.json` tries another
build against the same inputs. A replay refuses a header build that has changed since the
log was recorded.

`repro/` holds the input logs of the port bugs found, cut short after the finding:
`inbay-death.jsonl` (a death at iteration 170 of a session with the sun put close: the
candidate's BRK at `INBAY+7` and its hang in `BRBR1`), which replays with
`replay.mjs --log 6-harness/agentplay/repro/inbay-death.jsonl --out DIR --cand
3-assembled-output/build.json --workaround none`.
