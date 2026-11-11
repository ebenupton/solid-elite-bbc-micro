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
\     text tokens (QQ18, elite-text-tokens.asm's blocks tagged cold), the
\     overlay region, then the renderer's window (WIN7%: the bank 7 passes of
\     the renderer's files, the flight code's own parts of the renderer).
\
\ The renderer's files are placed by passes too (streams.py: each block's
\ "Area:" line names its place), and this file INCLUDEs their bank 4 and
\ bank 7 passes (3-assembled-output/<file>-bank4.asm, -bank7.asm).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"    \ The memory map
 INCLUDE "1-source-files/main-sources/gfx-rws.asm"      \ The renderer's mailbox
 INCLUDE "3-assembled-output/resident.asm"              \ The loader's resident
                                                        \ addresses


 PROGI% = BPSLOT%       \ The main RAM part's image, at the start of the
                        \ blueprint slot: needed only while PCLI loads the
                        \ program (LOMOD loads a set over it before the game
                        \ uses the slot)

 INCLUDE "3-assembled-output/elite-flight-config.asm"

IF _CIRCLES
 CIRCSZ = 2717          \ Room at bank 4's end for the planet's surface (the
ELSE                    \ circle engine's game part) in a build with _CIRCLES
 CIRCSZ = 0
ENDIF

 HOT_END% = QSL - CIRCSZ   \ (bank 4: the hot pass, the planet's surface in a
                        \ build with _CIRCLES, then the quarter squares and the
                        \ blueprint slot)

 ORG PROGM%

 INCLUDE "3-assembled-output/elite-flight-low.asm"

.LOW_END%

 HOTM% = LOW_END%       \ (the hot pass's container in main RAM: the rest of
 HOTM_END% = PROGM_END% \ the main RAM part)

 INCLUDE "3-assembled-output/elite-flight-hotm.asm"

.PROGM_USED%

 ORG PROGX%             \ (the hot pass's last container: the room after the
                        \ missile's blueprint)
 INCLUDE "3-assembled-output/elite-flight-hotx.asm"

.PROGX_USED%

 ASSERT PROGX_USED% <= PROGX_END%

 ASSERT PROGM_USED% <= PROGM_END%

 CLEAR &8000, &C000
 ORG HOME%

 INCLUDE "3-assembled-output/elite-flight-hot.asm"

.CIRC_START%

                        \ Port: in a build with _CIRCLES (make circles=on), the
                        \ planet's surface in game context at the hot pass's end:
                        \ PF_HOOK (gfx-planet7.asm), which H_CIRC calls, and the
                        \ circle engine's pc_circ (gfx-merid.asm's first part),
                        \ which reads the quarter squares (docs/renderer.md)

IF _CIRCLES
 _PLANET_MOON = FALSE
 _PLANET_RINGS = FALSE
 _PLANET_BANDS = FALSE
 ASSERT PF_INWK = INWK
 INCLUDE "3-assembled-output/gfx-planet7-bank4.asm"
 INCLUDE "3-assembled-output/gfx-merid-bank4.asm"
ENDIF

.HOME_END%

IF _CIRCLES             \ the circle engine's variables (elite-map.asm): the
 ORG PFVH%              \ main high, main low and bank 4 top passes
 INCLUDE "3-assembled-output/gfx-planet7-mainhigh.asm"
 INCLUDE "3-assembled-output/gfx-merid-mainhigh.asm"
.PFVH_END%
 ASSERT P% <= PFVH% + 64
 ORG PFVA%
 INCLUDE "3-assembled-output/gfx-merid-mainlow.asm"
.PFVA_END%
 ASSERT P% <= GLUE%
 ORG PFVS%
 INCLUDE "3-assembled-output/gfx-planet7-bank4top.asm"
 INCLUDE "3-assembled-output/gfx-merid-bank4top.asm"
.PFVS_END%
 ASSERT P% <= &C000
ENDIF


 PRINT "Flight bank 4: &8000-", ~CIRC_START%-1, " (the hot pass), ", HOME_END%-CIRC_START%, " (the planet's surface), free ", QSL-HOME_END%
 PRINT "Flight main RAM part: low pass ", ~PROGM%, "-", ~LOW_END%-1, ", hot pass to ", ~PROGM_USED%-1, ", free ", PROGM_END%-PROGM_USED%, ", then ", PROGX_END%-PROGX_USED%, " free of ", PROGX_END%-PROGX%
 ASSERT HOME_END% <= QSL AND CIRC_START% <= HOT_END% AND HOME_END% - CIRC_START% <= CIRCSZ

                        \ Port: the quarter squares, QSL and QSH, in bank 4 just
                        \ below the blueprint slot (elite-map.asm)

IF HOME_END% <= QSL    \ (else the ASSERT above stops the build, having
                          \ printed by how much bank 4 overflows)
 ORG QSL

 FOR I%, 0, 511
  EQUB LO(I% * I% DIV 4)
 NEXT

 FOR I%, 0, 511
  EQUB HI(I% * I% DIV 4)
 NEXT

 ASSERT QSH = QSL + &200 AND P% = BPSLOT%
ENDIF

 ORG PROGI%             \ the main RAM part's image, at the start of the
 COPYBLOCK PROGM%, PROGM_END%, PROGI%
 COPYBLOCK PROGX%, PROGX_END%, PROGI% + PROGM_END% - PROGM%   \ blueprint slot: the D.MOx file loads
                        \ over it afterwards

 SAVE "3-assembled-output/D.CODEH.bin", HOME%, &C000, HOME%
 SAVE "3-assembled-output/D.CODEM.bin", PROGM%, PROGM_END%, PROGM%   \ (the main
 SAVE "3-assembled-output/D.CODEX.bin", PROGX%, PROGX_END%, PROGX%   \ RAM part,
                        \ for the harness: it is on the disc in x.CODEH)

 CLEAR &8000, &C000
 ORG &8000

.COLD_START%

 INCLUDE "3-assembled-output/elite-flight-cold.asm"

 INCLUDE "3-assembled-output/elite-tokens-cold.asm"

.COLD_END%

                        \ Port: the overlay region (ovf1, ovload in the flight
                        \ source): each overlay is assembled at OVL% from its
                        \ copy and saved as D.OVn; overlay 1 last, so that
                        \ the bank 7 image holds it (OVLCUR starts as 1)

.OVL%

 INCLUDE "3-assembled-output/elite-flight-ovl2.asm"

.OVL2_END%

 SAVE "3-assembled-output/D.OV2.bin", OVL%, OVL2_END%, OVL%

 CLEAR OVL%, &C000
 ORG OVL%

 INCLUDE "3-assembled-output/elite-flight-ovl1.asm"

.OVL1_END%

 SAVE "3-assembled-output/D.OV1.bin", OVL%, OVL1_END%, OVL%

 OVL_END% = OVL% + (OVL1_END% - OVL% + OVL2_END% - OVL% + ABS(OVL1_END% - OVL2_END%)) DIV 2
 SKIP OVL_END% - P%     \ (the region: the bigger of the overlays)

 PRINT "Flight overlays: ", ~OVL%, "-", ~OVL_END%-1, " (1: ", OVL1_END%-OVL%, " bytes, 2: ", OVL2_END%-OVL%, ")"

                        \ Port: the renderer's window in bank 7, after the cold
                        \ pass: the parts of the renderer that only the flight
                        \ code uses and that banks 5 and 6 have no room for,
                        \ loaded with the flight code (docs/renderer.md): the
                        \ bank 7 passes of the disc layer's painter, the second
                        \ disc and their operands' patch (streams.py), then each
                        \ buffer's disc state, not in the image, to DFSSAVE%
                        \ (DPST%: gfx-raster_disc.asm)

.WIN7%

 INCLUDE "3-assembled-output/gfx-raster_disc-bank7.asm"
 INCLUDE "3-assembled-output/gfx-raster_disc2-bank7.asm"
 INCLUDE "3-assembled-output/gfx-raster_dpatch-bank7.asm"

.WIN7_END%

 PRINT "Flight bank 7: &8000-", ~COLD_END%-1, " (the cold pass), the overlays to ", ~OVL_END%-1, ", the renderer's window ", ~WIN7%, "-", ~WIN7_END%-1, " and its state ", ~DPST%, "-", ~DFSSAVE%-1, ", free ", DPST%-WIN7_END%
 ASSERT WIN7_END% <= DPST%         \ (the disc state, to DFSSAVE%: Port: PCLI keeps
                                   \ DFS's workspace in the last page)

 SAVE "3-assembled-output/D.CODEC.bin", &8000, WIN7_END%, &8000
