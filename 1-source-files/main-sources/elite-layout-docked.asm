\ ******************************************************************************
\
\ elite-layout-docked.asm - the docked code's layout (docs/memory-map.md)
\
\ Port: the file that the Makefile assembles for the docked code (the
\ original's T.CODE), as elite-layout-flight.asm does for the flight code:
\
\   * the home bank (saved as T.CODEH): the configuration and the workspaces,
\     then the code from S% at &8000 (HOME%), and the docked code's own
\     blueprints (its blocks tagged "Area: blueprints", which followed the code
\     at &5600 in the original) in the blueprint slot at BPSLOT%;
\
\   * the cold bank (saved as T.CODEC): the cold blocks from &8000, then the
\     recursive text tokens (QQ18, elite-text-tokens.asm's blocks tagged cold).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"    \ The memory map
 INCLUDE "3-assembled-output/resident.asm"              \ The loader's resident
                                                        \ addresses

 INCLUDE "3-assembled-output/elite-docked-home.asm"

.HOME_END%

 PRINT "Docked home bank: &8000-", ~HOME_END%-1, ", free ", BPSLOT%-HOME_END%
 ASSERT HOME_END% <= BPSLOT%

 ORG BPSLOT%

 INCLUDE "3-assembled-output/elite-docked-blueprints.asm"

.BP_END%

 PRINT "Docked blueprints: ", ~BPSLOT%, "-", ~BP_END%-1, ", free ", &C000-BP_END%
 ASSERT XX21 = BPSLOT% AND BP_END% <= &C000

 SAVE "3-assembled-output/T.CODEH.bin", HOME%, BP_END%, HOME%

 CLEAR &8000, &C000
 ORG &8000

.COLD_START%

 INCLUDE "3-assembled-output/elite-docked-cold.asm"

 INCLUDE "3-assembled-output/elite-tokens-cold.asm"

.COLD_END%

 PRINT "Docked cold bank: &8000-", ~COLD_END%-1, ", free ", &C000-COLD_END%
 ASSERT COLD_END% <= &C000

 SAVE "3-assembled-output/T.CODEC.bin", &8000, COLD_END%, &8000
