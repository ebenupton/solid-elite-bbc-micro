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
| main RAM (flight) | `&7970-&7E5F` | the main RAM part: the low pass, then `hotm` and `hotx` (main RAM's code is one run, from the rupture's) | 1260 | 4 |
| main RAM (docked) | `&7970-&7E5F` | the main RAM part: the low pass, then `hotm` and `hotx` (main RAM's code is one run, from the rupture's) | 194 | 1070 |
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
| bank 4 (docked) | `&8000-&AE0F` | `S%` and the hot pass | 8792 | 3000 |
| bank 4 (docked) | `&AE10-&B2FF` | the main RAM part's image | 1264 | 0 |
| bank 4 (docked) | `&B300-&BBA1` | the docked code's blueprints, their normals and `FC_NORMTAB` | 2144 | 66 |
| bank 4 (docked) | `&BBA2-&BBFF` | (free) | 0 | 94 |
| bank 4 (docked) | `&BC00-&BFFF` | the quarter squares `QSL`, `QSH` (made by the loader) | 1024 | 0 |
| bank 7 (flight) | `&8000-&A062` | the cold pass, `QQ18` | 8291 | 0 |
| bank 7 (flight) | `&A063-&A4AC` | the overlay region (`D.OV1` 1098 bytes, `D.OV2` 793) | 1098 | 0 |
| bank 7 (flight) | `&A4AD-&B3FF` | the renderer's window (bank 7 passes: the disc layer's painter with its strips, the second disc, their operands' patch) | 3910 | 13 |
| bank 7 (flight) | `&B400-&BFFF` | the workspace: each buffer's disc state (not in the image: `DP_BEGIN` sets it up), buffer 0's sharing its first `&2E2` bytes with `ovload`'s stash of `WP` and the zero page during an overlay's load (`OVSTASH`) | 3072 | 0 |
| bank 7 (docked) | `&8000-&BFFF` | the set's face lists, the cold pass, `QQ18` | 11397 | 4987 |
| bank 5 | `&8000-&97FF` | the 24 row runs, a page each; in their tails the stars' records and variables, `R_LINE`'s, DFS's workspace page between disc commands (`DFSTAIL%`: 64 bytes in each of four), and in tails 7, 8, 10, 15, 17, 18, 19, 20, 21, 22, 23 the flight code's cold 5 pass (`Area: cold 5`: `elite-flight-c5.asm`, `C5_r.bin`; `C5TAILS`), and in the ends of tails 0, 1, 2, 3, 4, 5, 6, 9, from byte 52 on, more of it (`C5_rp.bin`; `C5PTAILS`, `C5POFF`) (free: the 0 other tails with nothing in them, 65 bytes each, the rest of the others, and the cold 5 tails' room) | 6062 | 82 |
| bank 5 | `&9800-&A7FF` | `R_POLY`, `R_LINE`; at the top, the flight code's cold 5 pass's place `C5LO%` (180 bytes) | 4094 | 2 |
| bank 5 | `&A800-&ADFF` | the state: the dirty and written extents, `R_POLY`'s edge tables | 1536 | 0 |
| bank 5 | `&AE00-&B0A2` | `R_SETBUF`, `r_pgfix`, the spans' core, the arithmetic | 675 | 0 |
| bank 5 | `&B0A3-&B3FF` | the room below the per-x tables: `R_LINE`'s cold part, the private state, `R_RESETBUF`, `r_wq`, `R_MARKBOX`, `pf_tilt`; at the top, the cold 5 pass's place `C5GAP%` (25 bytes) | 861 | 0 |
| bank 5 | `&B400-&BF99` | the per-x tables, the row pages, the stars, `r_setup`, the repair, `R_GETW`, `r_pclip`, `r_pset`, `R_SPAN`, `R_DOT`, `R_MARKDIRTY`, `R_INIT` | 2970 | 0 |
| bank 5 | `&BF9A-&BFFF` | `RJT`, the jump table; at the top, the cold 5 pass's place `C5HI%` (45 bytes) | 87 | 15 |
| bank 6 | `&8000-&80FE` | the flight code's cold 6 pass (`Area: cold 6`: `elite-flight-c6.asm`, `C6.bin`; the room `C6SZ`) | 255 | 0 |
| bank 6 | `&80FF-&AC0D` | the frame layer's code (bank 6 passes) | 11023 | 0 |
| bank 6 | `&AC0E-&AF2B` | the faces' and the lighting's tables | 798 | 0 |
| bank 6 | `&AF2C-&B1FF` | the state: the ship records, the zero page `F_FRAME` keeps, the faces' levels, the docking slot, the planet's records kept | 724 | 0 |
| bank 6 | `&B200-&BC70` | the state, page aligned: the discs' half-widths (`F_INIT`'s code in the sun's until they are first written), the text map, the discs' rows | 2659 | 14 |
| bank 6 | `&BC71-&BFBF` | `FCSLOT`: the face lists of the set loaded | 847 | 0 |
| bank 6 | `&BFC0-&BFFF` | `FJT`, the dispatcher; in the last 12 bytes the hangar's background's jumps into the bank (`FHV%`) | 58 | 6 |

Free, by place: main RAM 43, main RAM (flight) 4, main RAM (docked) 1070, bank 4 (flight) 63, bank 4 (docked) 3160, bank 7 (flight) 13, bank 7 (docked) 4987, bank 5 99, bank 6 20.
