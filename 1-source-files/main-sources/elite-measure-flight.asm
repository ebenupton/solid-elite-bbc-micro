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
 INCLUDE "1-source-files/main-sources/gfx-rws.asm"
 INCLUDE "3-assembled-output/resident.asm"

 PROGI% = BPSLOT%

 INCLUDE "3-assembled-output/elite-flight-config.asm"

IF _CIRCLES
 CIRCSZ = 2560
ELSE
 CIRCSZ = 0
ENDIF
 HOT_END% = QSL - CIRCSZ

 ORG PROGM%

 INCLUDE "3-assembled-output/elite-flight-low.asm"

.LOW_END%

 HOTM% = LOW_END%
 HOTM_END% = PROGM_END%

 CLEAR &8000, &C000
 ORG HOME%

 INCLUDE "3-assembled-output/elite-flight-measure.asm"

.FLOW_END

IF _CIRCLES             \ (the planet's surface at the hot pass's end, as the
 _PLANET_MOON = FALSE   \ layout has it, for the hot pass's reference to it)
 _PLANET_RINGS = FALSE
 _PLANET_BANDS = FALSE
 MERID_PART = 1
 INCLUDE "1-source-files/main-sources/gfx-planet7.asm"
 INCLUDE "1-source-files/main-sources/gfx-merid.asm"
ENDIF

.M_CIRC_END


 CLEAR &8000, &C000
 ORG &8000

 INCLUDE "3-assembled-output/elite-flight-cold.asm"
 INCLUDE "3-assembled-output/elite-tokens-cold.asm"
.OVL%
 INCLUDE "3-assembled-output/elite-flight-ovl2.asm"
 CLEAR OVL%, &C000
 ORG OVL%
 INCLUDE "3-assembled-output/elite-flight-ovl1.asm"
 OVL_END% = &BE00
 CLEAR OVL%, &C000
 ORG OVL%
 INCLUDE "1-source-files/main-sources/gfx-window7.asm"

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
 ORG PROGX%
.M_HOTX
 ORG PROGX_END%
.M_HOTX_END
