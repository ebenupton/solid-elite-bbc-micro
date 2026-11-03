\ ******************************************************************************
\
\ elite-measure-flight.asm - the flight code's hot pass, measured
\
\ Port: the Makefile assembles this first (beebasm -d, for its symbols:
\ 3-assembled-output/measure-flight-symbols.txt), with the copies that
\ 2-build-files/streams.py writes for the measure: the whole hot pass as one
\ copy (elite-flight-measure.asm), with a label FLOW_<n> at the start of each
\ block. streams.py then flows the hot pass's units through its containers
\ by these sizes, and the bounds of the containers (docs/memory-map.md).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"
 INCLUDE "3-assembled-output/resident.asm"

 HOT_END% = QSL

 INCLUDE "3-assembled-output/elite-flight-config.asm"

 ORG PROGM%

 INCLUDE "3-assembled-output/elite-flight-low.asm"

.LOW_END%

 HOTM% = LOW_END%
 HOTM_END% = PROGM_END%
 PROGI% = HOME%          \ (S%+14: the address of the main RAM part's image, as yet unknown)

 CLEAR &8000, &C000
 ORG HOME%

 INCLUDE "3-assembled-output/elite-flight-measure.asm"

.FLOW_END


 CLEAR &8000, &C000
 ORG &8000

 INCLUDE "3-assembled-output/elite-flight-cold.asm"
 INCLUDE "3-assembled-output/elite-tokens-cold.asm"

                        \ The containers' bounds, as labels for the symbols
                        \ (bank 4 also holds the main RAM part's image)
 ORG HOME%
.M_HOT
 ORG HOT_END% - (PROGM_END% - PROGM%)
.M_HOT_END
 ORG HOTM%
.M_HOTM
 ORG HOTM_END%
.M_HOTM_END
