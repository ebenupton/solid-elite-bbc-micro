\ ******************************************************************************
\
\ elite-layout-docked.asm - the docked code's layout (docs/memory-map.md)
\
\ Port: the file that the Makefile assembles for the docked code (the
\ original's T.CODE). elite-source-docked.asm is the original's source in the
\ original's order, and the header of each routine or table names the pass it
\ is emitted in (no Area field: the hot pass; "Area: low", "Area: cold",
\ "Area: none"). The banks share the addresses &8000-&BFFF and BeebAsm
\ assembles a file with one location counter, so 2-build-files/streams.py
\ writes a copy of the source for each container, with every other line
\ blanked (3-assembled-output/elite-docked-<copy>.asm; the line numbers are
\ the source's), and this file assembles them one after the other, each at
\ its own address. Every label is defined once, in its own copy, and every
\ block is assembled once; where a routine lives on the other side, each copy
\ holds the far-call stub that reaches it, at the routine's place:
\
\   * the configuration and the workspaces (config);
\
\   * the main RAM part, at PROGM% after the rupture's code: the low pass, then
\     the hot pass's container in main RAM (hotm), which the flow fills once
\     bank 4 is full; its bytes are copied into the bank 4 image at PROGI%,
\     and PCLI copies them to PROGM% when it loads the program;
\
\   * bank 4 (saved as T.CODEH): the hot pass from S% at &8000 (HOME%), then
\     the main RAM part's image, and the docked code's own blueprints (its
\     blocks tagged "Area: blueprints", which followed the code at &5600 in
\     the original) in the blueprint slot at BPSLOT%; the image stops short
\     of the quarter squares, which the loader makes (the docked code's
\     lighting multiplies with them, L_REC);
\
\   * bank 7 (saved as T.CODEC): the cold pass from &8000, then the recursive
\     text tokens (QQ18, elite-text-tokens.asm's blocks tagged cold).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"    \ The memory map
 INCLUDE "3-assembled-output/resident.asm"              \ The loader's resident
                                                        \ addresses

 PROGI% = BPSLOT% - PROGIS%   \ The main RAM part's image, below the
                        \ blueprint slot (which holds this program's
                        \ blueprints)

 HOT_END% = PROGI%      \ (bank 4: the hot pass, the main RAM part's image, then
                        \ the blueprint slot and the quarter squares)

 INCLUDE "3-assembled-output/elite-docked-config.asm"

 ORG PROGM%

 INCLUDE "3-assembled-output/elite-docked-low.asm"

.LOW_END%

 HOTM% = LOW_END%       \ (the hot pass's containers in main RAM: hotm to
 HOTM_END% = PROGH%     \ PROGH%, then hotx, straight after hotm's units, to
                        \ the main RAM part's end: elite-map.asm)

 INCLUDE "3-assembled-output/elite-docked-hotm.asm"
 INCLUDE "3-assembled-output/elite-docked-hotx.asm"

.PROGM_USED%

 ASSERT PROGM_USED% <= PROGM_END%

 CLEAR &8000, &C000
 ORG HOME%

 INCLUDE "3-assembled-output/elite-docked-hot.asm"

.HOME_END%


 PRINT "Docked bank 4: &8000-", ~HOME_END%-1, " (the hot pass), free ", HOT_END%-HOME_END%
 PRINT "Docked main RAM part: low pass ", ~PROGM%, "-", ~LOW_END%-1, ", hot pass to ", ~PROGM_USED%-1, ", free ", PROGM_END%-PROGM_USED%
 ASSERT HOME_END% <= HOT_END%

 ORG BPSLOT%

 INCLUDE "3-assembled-output/elite-docked-blueprints.asm"

.BP_END%

 ASSERT XX21 = BPSLOT%

 SETN = 16              \ Port: the renderer's data for this set's ships: their
                        \ normals and FC_NORMTAB here (elite-shipset.asm's
                        \ parts 1 and 2), their face lists at the start of the
                        \ cold image (below)

 INCLUDE "1-source-files/main-sources/gfx-setnorm.asm"

 PRINT "Docked blueprints: ", ~BPSLOT%, "-", ~BP_END%-1, ", normals to ", ~P%-1, ", free ", NORMTAB-P%
 ASSERT P% <= NORMTAB

 ORG NORMTAB

 INCLUDE "1-source-files/main-sources/gfx-settab.asm"

 ASSERT P% = BPSLOT_END%

 ORG PROGI%             \ the main RAM part's image, below the blueprint slot
 ASSERT INBAYJ = INBAYJ%   \ (the flight code's INBAY returns there: elite-map.asm)

 COPYBLOCK PROGM%, PROGM_END%, PROGI%

 SAVE "3-assembled-output/T.CODEH.bin", HOME%, BPSLOT_END%, HOME%   \ (to the
                        \ slot's end, below the quarter squares, which the
                        \ loader makes)
 SAVE "3-assembled-output/T.CODEM.bin", PROGM%, PROGM_END%, PROGM%   \ (the main
                        \ RAM part, for the harness: it is on the disc in x.CODEH)

 CLEAR &8000, &C000

 ORG FCSLOT             \ Port: the face lists of this code's blueprint set,
                        \ assembled at bank 6's slot, FCSLOT, and moved to the
 INCLUDE "1-source-files/main-sources/gfx-setfaces.asm"   \ start of the cold image,
                        \ which PCLI loads at STAGE%: DEEOR has the frame layer
 SETF_END% = P%         \ copy them from there (F_SETLD)
 ASSERT SETF_END% <= FCSLOT + FCSLOT_SIZE
 COPYBLOCK FCSLOT, SETF_END%, &8000
 CLEAR FCSLOT, &C000

 ORG &8000 + SETF_END% - FCSLOT

.COLD_START%

 INCLUDE "3-assembled-output/elite-docked-cold.asm"

 INCLUDE "3-assembled-output/elite-tokens-cold.asm"

.COLD_END%

 PRINT "Docked bank 7: &8000-", ~COLD_END%-1, " (the cold pass), free ", DFSSAVE%-COLD_END%
 ASSERT COLD_END% <= DFSSAVE%      \ (Port: PCLI keeps DFS's workspace in the last page)

 SAVE "3-assembled-output/T.CODEC.bin", &8000, COLD_END%, &8000
