\ ******************************************************************************
\
\ elite-layout-flight.asm - the flight code's layout (docs/memory-map.md)
\
\ Port: the file that the Makefile assembles for the flight code (the
\ original's D.CODE). elite-source-flight.asm is the original's source in the
\ original's order, and the header of each routine or table names the area it
\ lives in (no Area field: the home bank; "Area: cold": the cold bank). The
\ two banks share the addresses &8000-&BFFF and BeebAsm assembles a file with
\ one location counter, so 2-build-files/streams.py writes a copy of the
\ source for each area, with the other areas' lines blanked
\ (3-assembled-output/elite-flight-home.asm and -cold.asm; the line numbers
\ are the source's), and this file assembles them one after the other, each
\ at its own address. Every label is defined once, in its own area's copy,
\ and every block is assembled once; where a routine lives on the other side,
\ each copy holds the far-call stub that reaches it, at the routine's place:
\
\   * the home bank (saved as D.CODEH): the configuration and the workspaces,
\     then the code from S% at &8000 (HOME%); the blueprint slot at BPSLOT% is
\     loaded from a D.MOx file by LOMOD, as the original loaded it at &5600;
\
\   * the cold bank (saved as D.CODEC): the cold blocks from &8000, then the
\     recursive text tokens (QQ18, elite-text-tokens.asm's blocks tagged cold).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"    \ The memory map
 INCLUDE "3-assembled-output/resident.asm"              \ The loader's resident
                                                        \ addresses

 INCLUDE "3-assembled-output/elite-flight-home.asm"

.HOME_END%

 PRINT "Flight home bank: &8000-", ~HOME_END%-1, ", free ", BPSLOT%-HOME_END%
 ASSERT HOME_END% <= BPSLOT%

 SAVE "3-assembled-output/D.CODEH.bin", HOME%, HOME_END%, HOME%

 CLEAR &8000, &C000
 ORG &8000

.COLD_START%

 INCLUDE "3-assembled-output/elite-flight-cold.asm"

 INCLUDE "3-assembled-output/elite-tokens-cold.asm"

.COLD_END%

 PRINT "Flight cold bank: &8000-", ~COLD_END%-1, ", free ", &C000-COLD_END%
 ASSERT COLD_END% <= &C000

 SAVE "3-assembled-output/D.CODEC.bin", &8000, COLD_END%, &8000
