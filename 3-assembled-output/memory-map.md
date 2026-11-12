| Place | Addresses | Holds | Used | Free |
|---|---|---|---:|---:|
| main RAM | `&0000-&00FF` | zero page: the game's (the rasteriser's &06-&27 and the frame layer's &D2-&E1 during a frame, kept) | 256 | 0 |
| main RAM | `&0100-&01FF` | the stack | 256 | 0 |
| main RAM | `&0300-&03CF` | `UP`, the game's workspace | 208 | 0 |
| main RAM | `&0400-&06E5` | resident block A (`elite-resident.asm`): `BANKS`, the far calls, `PCLI` with `dfsin`, `dfsout`, `pload`, `WRCHR`, `BRKR`, the last saved commander and the break handler, `IRQG` | 742 | 0 |
| main RAM | `&06E6-&0723` | the circle engine's variables (main low: `gfx-merid.asm`) | 62 | 0 |
| main RAM | `&0724-&07BF` | the glue: the trampolines into bank 5, `GCALL`; then `pcb_o`, the circle engine's table that banks 4 and 6 read (main: `gfx-merid.asm`) | 151 | 5 |
| main RAM | `&07C0-&07FF` | `SNE`, `ACT` | 64 | 0 |
| main RAM | `&0880-&08BF` | `QQ16` | 64 | 0 |
| main RAM | `&0900-&0CFF` | `K%` and the line heaps (the loader's `LOAD` at `&0B00` before the game) | 1024 | 0 |
| main RAM | `&0D7A-&0D9D` | `CATD` | 36 | 0 |
| main RAM | `&0E00-&0FD2` | `WP` | 467 | 0 |
| main RAM | `&1000-&3FFF` | buffer 0 (DFS's page `&1000` between disc commands kept in bank 7; `STAGE%` from `&1600` during a load) | 12288 | 0 |
| main RAM | `&4000-&6FFF` | buffer 1, the screen | 12288 | 0 |
| main RAM | `&7000-&76FF` | the dashboard (`P.DIALS`) | 1792 | 0 |
| main RAM | `&7700-&796F` | the rupture (`elite-rupture.asm`, copied there by the loader): the clock switches, the frames' registers, the flip, the display off during disc commands; its variables after its code | 624 | 0 |
| main RAM (flight) | `&7970-&7DFF` | the main RAM part: the low pass, then `hotm` | 1168 | 0 |
| main RAM (docked) | `&7970-&7DFF` | the main RAM part: the low pass, then `hotm` | 16 | 1152 |
| main RAM | `&7E00-&7E9F` | the mailbox, `MBOX`: the rasteriser's inputs (the stars at its end, `&67-&9F`); sharing its polygon vertices, `PCLI`'s command and OSFILE block, the circle records from `PF_HOOK` to the frame (`&00-&49`, `&52-&5D`) and the disc layer's batches (`&00-&65`) | 160 | 0 |
| main RAM | `&7EA0-&7EAF` | `GVARS`, the renderer's shared variables (the game's hooks, the interrupt and the frame layer's) | 16 | 0 |
| main RAM | `&7EB0-&7EBF` | the high resident block: the palette | 16 | 0 |
| main RAM | `&7EC0-&7EFF` | the circle engine's variables (main high: `gfx-planet7.asm`, `gfx-merid.asm`) | 59 | 5 |
| main RAM | `&7F00-&7F9F` | the missile's blueprint | 160 | 0 |
| main RAM (flight) | `&7FA0-&7FFD` | the main RAM part: `hotx` | 91 | 3 |
| main RAM (docked) | `&7FA0-&7FFD` | the main RAM part: `hotx` | 0 | 94 |
| main RAM | `&7FFE-&7FFF` | `VEC` | 2 | 0 |
| bank 4 (flight) | `&8000-&A862` | `S%` and the hot pass | 10339 | 0 |
| bank 4 (flight) | `&A863-&B2FF` | the planet's surface (bank 4 passes: `PF_HOOK`, `pc_circ`) | 2706 | 11 |
| bank 4 (flight) | `&B300-&B6FF` | the quarter squares `QSL`, `QSH` | 1024 | 0 |
| bank 4 (flight) | `&B700-&BFA1` | the blueprint set (`D.MOx`), its normals and `FC_NORMTAB` | 2210 | 0 |
| bank 4 (flight) | `&BFA2-&BFFF` | the circle engine's variables (bank 4 top) | 54 | 40 |
| bank 4 (docked) | `&8000-&AE11` | `S%` and the hot pass | 8720 | 3074 |
| bank 4 (docked) | `&AE12-&B2FF` | the main RAM part's image | 1262 | 0 |
| bank 4 (docked) | `&B300-&B6FF` | the quarter squares `QSL`, `QSH` | 1024 | 0 |
| bank 4 (docked) | `&B700-&BFA1` | the docked code's blueprints, their normals and `FC_NORMTAB` | 2144 | 66 |
| bank 7 (flight) | `&8000-&9F5D` | the cold pass, `QQ18` | 8030 | 0 |
| bank 7 (flight) | `&9F5E-&A3A7` | the overlay region (`D.OV1` 1098 bytes, `D.OV2` 783) | 1098 | 0 |
| bank 7 (flight) | `&A3A8-&B2FF` | the renderer's window (bank 7 passes: the disc layer's painter with its strips, the second disc, their operands' patch) | 3910 | 18 |
| bank 7 (flight) | `&B300-&BEFF` | each buffer's disc state (not in the image: `DP_BEGIN` sets it up) | 3072 | 0 |
| bank 7 | `&BF00-&BFFF` | DFS's workspace page between disc commands (`DFSSAVE%`) | 256 | 0 |
| bank 7 (docked) | `&8000-&BEFF` | the set's face lists, the cold pass, `QQ18` | 11397 | 4731 |
| bank 5 | `&8000-&8FFF` | `R_POLY`, `R_LINE` | 4049 | 47 |
| bank 5 | `&9000-&95FF` | the state: the dirty and written extents, `R_POLY`'s edge tables | 1536 | 0 |
| bank 5 | `&9600-&9932` | `R_SETBUF`, `r_pgfix`, the spans, the arithmetic | 819 | 0 |
| bank 5 | `&9933-&9BFF` | the room below the per-x tables: `R_LINE`'s cold part, the private state, `R_RESETBUF`, `r_wq`, `pf_tilt` | 700 | 17 |
| bank 5 | `&9C00-&BE98` | the per-x tables, the 24 row runs (the stars' records, variables and some code in their tails; free: the 9 tails with nothing in them, 65 bytes each), the row pages, the stars, `R_INIT`, the repair, `R_GETW` | 8272 | 585 |
| bank 5 | `&BE99-&BFFF` | `RJT`, the jump table | 42 | 317 |
| bank 6 | `&8000-&ABEC` | the frame layer's code (bank 6 passes) | 11245 | 0 |
| bank 6 | `&ABED-&AF0A` | the faces' and the lighting's tables | 798 | 0 |
| bank 6 | `&AF0B-&B1E8` | the state: the ship records, the zero page `F_FRAME` keeps, the faces' levels, the docking slot, the planet's records kept | 734 | 0 |
| bank 6 | `&B1E9-&B1FF` | (the page alignment of the state that follows) | 0 | 23 |
| bank 6 | `&B200-&BC70` | the state, page aligned: the discs' half-widths, the text map, the discs' rows | 2649 | 24 |
| bank 6 | `&BC71-&BFBF` | `FCSLOT`: the face lists of the set loaded | 847 | 0 |
| bank 6 | `&BFC0-&BFFF` | `FJT`, the dispatcher | 46 | 18 |

Free, by place: main RAM 10, main RAM (flight) 3, main RAM (docked) 1246, bank 4 (flight) 51, bank 4 (docked) 3140, bank 7 (flight) 18, bank 7 0, bank 7 (docked) 4731, bank 5 966, bank 6 65.
