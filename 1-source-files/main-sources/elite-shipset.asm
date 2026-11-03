\ ******************************************************************************
\
\ elite-shipset.asm - Port: the renderer's data that a blueprint set carries
\
\ INCLUDEd at the end of each ship file (elite-ships-?.asm, SETN = 0 to 15) and
\ after the docked code's blueprints (SETN = 16), with P% after the set's
\ blueprints. Only one blueprint set's ships exist at a time, so the
\ renderer's per-type data for the ships is loaded with their set, rather
\ than kept for all 33 types (gfx-setnorm.asm, gfx-settab.asm and
\ gfx-setfaces.asm, from 2-build-files/faces.py):
\
\   * the ships' unit normals (part 1), here, after the blueprints, and their
\     table by type, FC_NORMTAB (part 2), at NORMTAB at the slot's end: the
\     lighting (L_REC, bank 4) reads them as it would a table of all types;
\
\   * the face lists with their tables (part 3), assembled at bank 6's
\     FCSLOT and moved to SETF% here, after the slot's last page (in the
\     ship files: the file's ninth page on, which PCLI leaves at STAGE% after
\     it copies the slot's pages into bank 4; LOMOD then has the frame layer
\     copy them to FCSLOT, F_SETLD). The docked code's layout moves its part
\     3 to the start of its cold image instead.
\
\ 2-build-files/setcheck.py checks each set's data, as built, against the
\ tables of all types.
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/gfx-setnorm.asm"

 ASSERT P% <= NORMTAB   \ (the blueprints and normals fit the slot)
 SETFREE% = NORMTAB - P%

 ORG NORMTAB
 INCLUDE "1-source-files/main-sources/gfx-settab.asm"
 ASSERT P% = BPSLOT_END%

 ASSERT HI(BPSLOT%) * 256 = BPSLOT% AND SETF% = &C000   \ (part 3 after the slot's pages)

 COPYBLOCK BPSLOT%, &C000, &3000   \ (keep the slot while part 3 is assembled
 CLEAR BPSLOT%, &C000              \ over it, at bank 6's addresses)
 ORG FCSLOT
 INCLUDE "1-source-files/main-sources/gfx-setfaces.asm"
 ASSERT P% <= FCSLOT + FCSLOT_SIZE
 COPYBLOCK FCSLOT, P%, SETF%
 SETF_END% = SETF% + P% - FCSLOT
 COPYBLOCK &3000, &3000 + &C000 - BPSLOT%, BPSLOT%

 PRINT "Set ", SETN, ": slot free ", SETFREE%, ", face lists ", P% - FCSLOT, " of ", FCSLOT_SIZE
