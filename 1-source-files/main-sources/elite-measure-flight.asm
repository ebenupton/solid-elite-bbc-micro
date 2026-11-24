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
 CIRCSZ = 2650
ELSE
 CIRCSZ = 0
ENDIF
 HOT_END% = BPSLOT% - CIRCSZ

 ORG PROGM%

 INCLUDE "3-assembled-output/elite-flight-low.asm"

.LOW_END%

 HOTM% = LOW_END%
 HOTM_END% = PROGH%

 CLEAR &8000, &C000
 ORG HOME%

 INCLUDE "3-assembled-output/elite-flight-measure.asm"

.FLOW_END

IF _CIRCLES             \ (the planet's surface at the hot pass's end, as the
                        \ layout has it, for the hot pass's reference to it)
 INCLUDE "3-assembled-output/gfx-planet7-bank4.asm"
 INCLUDE "3-assembled-output/gfx-merid-bank4.asm"
ENDIF

.M_CIRC_END

IF _CIRCLES             \ the circle engine's variables (elite-map.asm): the
 ORG PFVH%              \ main high, main low and bank 4 top passes
 INCLUDE "3-assembled-output/gfx-planet7-mainhigh.asm"
 INCLUDE "3-assembled-output/gfx-merid-mainhigh.asm"
 ASSERT P% <= &7FFE          \ (VEC)
 ORG PFVA%
 INCLUDE "3-assembled-output/gfx-merid-mainlow.asm"
 ASSERT P% <= GLUE%
 ORG PFVS%
 INCLUDE "3-assembled-output/gfx-merid-bank4top.asm"
 ASSERT P% <= QSL
ELSE
 ORG PFVS%
ENDIF

.M_HOT4                 \ (the hot pass's container at bank 4's top, after the
 ORG QSL                \ circle engine's variables, to the quarter squares)
.M_HOT4_END


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
 INCLUDE "3-assembled-output/gfx-raster_disc-bank7.asm"
 INCLUDE "3-assembled-output/gfx-raster_disc2-bank7.asm"
 INCLUDE "3-assembled-output/gfx-raster_dpatch-bank7.asm"

 CLEAR C6%, C6% + C6SZ  \ (the cold 6 pass, at the start of bank 6, for its
 ORG C6%                \ labels, which the hot pass's stubs name)
 INCLUDE "3-assembled-output/elite-flight-c6.asm"

 CLEAR &8000, &C000     \ (the cold 5 pass, in one piece: its blocks' sizes,
 ORG C5TAIL0            \ C5S_k to C5E_k, for streams.py's placing of it in
 INCLUDE "3-assembled-output/elite-flight-c5.asm"   \ the tails)

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
