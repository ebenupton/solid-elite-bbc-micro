# The Model B's memory, and what the MOS, DFS and the original use

The port runs on a BBC Model B with DFS (as jsbeeb's "B-DFS1.2": MOS 1.20,
DFS 1.20, the 8271 controller) and 64K of sideways RAM in four banks.
[memory-map.md](memory-map.md) describes how the port lays itself out.

## Main RAM below the screen

| Range | MOS and DFS | The original | The port |
|---|---|---|---|
| `&0000-&00E1` | user zero page, and the MOS's and filing system's scratch from `&90` | Elite's zero page | the same |
| `&0100-&01FF` | the stack | the stack, and `XX3` at its bottom | the same |
| `&0200-&02FF` | the MOS's vectors and variables (`&02A1-&02B0`: the ROM type table) | WRCHV, BRKV, IRQ1V point at its code | WRCHV and BRKV point at the resident block; `PROBE` reads the ROM table |
| `&0300-&03CF` | VDU and cassette workspace | `UP` (Elite never uses the MOS's VDU drivers: WRCHV is its own) | the same |
| `&0400-&07FF` | the language's workspace | `WORDS`: the text tokens `QQ18`, `SNE`, `ACT` | resident block A, then `SNE` and `ACT` |
| `&0800-&08FF` | sound workspace and buffers, printer buffer | `QQ16` at `&0880` | the same |
| `&0900-&0CFF` | RS423, cassette and speech buffers, user characters | `K%` and the line heaps; the loader's last part at `&0B00`; the commander file at `&0B00` and its OSFILE block at `&0C00` | the same |
| `&0D00-&0DFF` | DFS's NMI routine, and the MOS's ROM workspace table | `CATD` at `&0D7A` | the same, and nothing else |
| `&0E00-&0FFF` | DFS's copy of the catalogue | `WP` to `&0FD2`; `CATD` reads the catalogue back before each disc command | the same |
| `&1000-&10FF` | DFS's workspace | untouched | the same |
| `&1100-&18FF` | DFS's file buffers (for OSFIND only) | the resident block at `&1100`, then the program from `&11E3` | the resident block at `&1100`; from `&1200`, the staging area |

## The catalogue in WP

`CATD` reads sectors 0 and 1 of the disc into `&0E00-&0FFF`, over the
workspace `WP`, before every disc command, so that DFS finds its catalogue
where it expects it. The original relies on `WP` being dead at those times.
It is not quite: when new stardust is made, only the stardust's whole parts
are set, and the fractional parts (`SXL`, `SYL`, `SZL`) keep whatever the
catalogue left there. On another disc, with another catalogue, the stardust
starts a fraction of a unit elsewhere. The harness sets such bytes to 0 in
both runs before the game uses them (6-harness/README.md, "Disc loads").

## Page &0D

DFS keeps its NMI routine at `&0D00`, which the 8271 calls for every byte
of a transfer, and the MOS keeps the ROM workspace table at `&0DF0`. The
original's loader puts `CATD` at `&0D7A`, between them, and `CATD` keeps its
OSWORD block there. The port leaves the page as the original does, and
writes nothing else there; the harness fails a run in which code other than
the filing system's and `CATD` writes to it.

## Sideways RAM

The four banks must be RAM that the MOS has no ROM in. The MOS builds its
ROM table at a reset, from the ROMs' headers; a bank of sideways RAM that
holds no ROM image has no entry, so the MOS never pages it in for a service
call. The game's banks hold no ROM header, so they stay invisible to the MOS
after a soft BREAK too. While a bank is paged in, the MOS and DFS can still
run: they page their own ROMs in and page back the bank in `&F4`, which the
port keeps equal to ROMSEL at all times.
