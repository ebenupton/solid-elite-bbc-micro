\ ******************************************************************************
\
\ elite-layout-flight.asm - the flight code's layout (docs/memory-map.md)
\
\ Port: the file that the Makefile assembles for the flight code (the
\ original's D.CODE). elite-source-flight.asm is the original's source in the
\ original's order, and the header of each routine or table names the pass it
\ is emitted in (no Area field: the hot pass; "Area: low", "Area: cold",
\ "Area: none"). The banks share the addresses &8000-&BFFF and BeebAsm
\ assembles a file with one location counter, so 2-build-files/streams.py
\ writes a copy of the source for each container, with every other line
\ blanked (3-assembled-output/elite-flight-<copy>.asm; the line numbers are
\ the source's), and this file assembles them one after the other, each at
\ its own address. Every label is defined once, in its own copy, and every
\ block is assembled once; where a routine lives on the other side, each copy
\ holds the far-call stub that reaches it, at the routine's place:
\
\   * the configuration and the workspaces (config);
\
\   * the main RAM part, at PROGM% in the resident block: the low pass, then
\     the hot pass's container in main RAM (hotm), which the flow fills once
\     bank 4 is full; its bytes are copied into the bank 4 image at PROGI%,
\     and PCLI copies them to PROGM% when it loads the program;
\
\   * bank 4 (saved as D.CODEH): the hot pass from S% at &8000 (HOME%), then
\     the main RAM part's image, the quarter squares and the blueprint slot
\     at BPSLOT%, which LOMOD loads from a D.MOx file, as the original loaded
\     it at &5600;
\
\   * bank 7 (saved as D.CODEC): the cold pass from &8000, then the recursive
\     text tokens (QQ18, elite-text-tokens.asm's blocks tagged cold), then
\     the renderer's window (WIN7%: the flight code's own parts of the
\     renderer).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"    \ The memory map
 INCLUDE "3-assembled-output/resident.asm"              \ The loader's resident
                                                        \ addresses

 HOT_END% = QSL         \ (bank 4: the hot pass and the main RAM part's image,
                        \ then the quarter squares and the blueprint slot)

 INCLUDE "3-assembled-output/elite-flight-config.asm"

 ORG PROGM%

 INCLUDE "3-assembled-output/elite-flight-low.asm"

.LOW_END%

 HOTM% = LOW_END%       \ (the hot pass's container in main RAM: the rest of
 HOTM_END% = PROGM_END% \ the main RAM part)

 INCLUDE "3-assembled-output/elite-flight-hotm.asm"

.PROGM_USED%

 ASSERT PROGM_USED% <= PROGM_END%

 CLEAR &8000, &C000
 ORG HOME%

 INCLUDE "3-assembled-output/elite-flight-hot.asm"

.HOME_END%

.PROGI%                 \ The main RAM part's image, which PCLI copies to PROGM%

 SKIP PROGM_END% - PROGM%

.PROGI_END%

 CLEAR PROGI%, PROGI_END%
 COPYBLOCK PROGM%, PROGM_END%, PROGI%

 PRINT "Flight bank 4: &8000-", ~HOME_END%-1, " (the hot pass), the main RAM part's image to ", ~PROGI_END%-1, ", free ", HOT_END%-HOME_END%
 PRINT "Flight main RAM part: low pass ", ~PROGM%, "-", ~LOW_END%-1, ", hot pass to ", ~PROGM_USED%-1, ", free ", PROGM_END%-PROGM_USED%
 ASSERT HOME_END% <= HOT_END%

                        \ Port: the quarter squares, QSL and QSH, in bank 4 just
                        \ below the blueprint slot (elite-map.asm)

 ORG QSL

 FOR I%, 0, 511
  EQUB LO(I% * I% DIV 4)
 NEXT

 FOR I%, 0, 511
  EQUB HI(I% * I% DIV 4)
 NEXT

 ASSERT QSH = QSL + &200 AND P% = BPSLOT%

 SAVE "3-assembled-output/D.CODEH.bin", HOME%, BPSLOT%, HOME%

 CLEAR &8000, &C000
 ORG &8000

.COLD_START%

 INCLUDE "3-assembled-output/elite-flight-cold.asm"

 INCLUDE "3-assembled-output/elite-tokens-cold.asm"

.COLD_END%

                        \ Port: the renderer's window in bank 7, after the cold
                        \ pass: the parts of the renderer that only the flight
                        \ code uses and that banks 5 and 6 have no room for,
                        \ loaded with the flight code (docs/renderer.md)

.WIN7%

 INCLUDE "1-source-files/main-sources/gfx-dlayer.asm"

.WIN7_END%

 PRINT "Flight bank 7: &8000-", ~COLD_END%-1, " (the cold pass), the renderer's window ", ~WIN7%, "-", ~WIN7_END%-1, ", free ", DFSSAVE%-WIN7_END%
 ASSERT WIN7_END% <= DFSSAVE%      \ (Port: PCLI keeps DFS's workspace in the last page)

 SAVE "3-assembled-output/D.CODEC.bin", &8000, WIN7_END%, &8000
