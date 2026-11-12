\ ******************************************************************************
\
\ elite-measure-docked.asm - the docked code's hot pass, measured
\
\ Port: the Makefile assembles this first (beebasm -d, for its symbols:
\ 3-assembled-output/measure-docked-symbols.txt), with the copies that
\ 2-build-files/streams.py writes for the measure: the whole hot pass as one
\ copy (elite-docked-measure.asm), with a label FLOW_<n> at the start of each
\ block. streams.py then flows the hot pass's units through its containers
\ by these sizes, and the bounds of the containers (docs/memory-map.md).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"
 INCLUDE "3-assembled-output/resident.asm"

 PROGI% = QSL - PROGIS%
 HOT_END% = PROGI%

 INCLUDE "3-assembled-output/elite-docked-config.asm"

 ORG PROGM%

 INCLUDE "3-assembled-output/elite-docked-low.asm"

.LOW_END%

 HOTM% = LOW_END%
 HOTM_END% = PROGH%

 CLEAR &8000, &C000
 ORG HOME%

 INCLUDE "3-assembled-output/elite-docked-measure.asm"

.FLOW_END


 CLEAR &8000, &C000
 ORG &8000

 INCLUDE "3-assembled-output/elite-docked-cold.asm"
 INCLUDE "3-assembled-output/elite-tokens-cold.asm"

 CLEAR BPSLOT%, &C000
 ORG BPSLOT%

 INCLUDE "3-assembled-output/elite-docked-blueprints.asm"

                        \ The containers' bounds, as labels for the symbols
                        \ (bank 4 also holds the main RAM part's image)
 ORG HOME%
.M_HOT
 ORG HOT_END%
.M_HOT_END
 ORG HOTM%
.M_HOTM
 ORG HOTM_END%
.M_HOTM_END
 ORG PROGH%
.M_HOTX
 ORG PROGM_END%
.M_HOTX_END
