\ ******************************************************************************
\
\ gfx-bankr.asm - bank R: the filled renderer's rasteriser (docs/renderer.md)
\
\ Port (Model B): assembled by 2-build-files/bankr.sh (which makes the
\ rasteriser's sources NMOS first, into 3-assembled-output/nmos), as the
\ Tube branch's Model B host assembled its bank P (tube/src/hb-p.asm), with
\ the rest of what its bank D did (R_INIT, R_RESETBUF, and R_REPAIR in place
\ of the disc layer: gfx-raster_r.asm) and all of the state (gfx-rws.asm):
\
\   &8000-&8FFF  the polygon window: R_POLY (both phases), R_LINE's loops,
\                the dirty repair (r7_rowrep), R_INIT, R_RESETBUF, R_REPAIR
\   &9000-&BFBF  the shared region (gfx-raster.asm): the state, R_LINE's cold
\                part, R_SETBUF, the per-x tables, the 24 row runs at &A000
\                (with the stars' records and R_SPAN, R_DOT, R_MARKDIRTY,
\                R_STARERASE, R_STARPLOT in their tails), then R_LINE
\   &BFC0        RJT, the jump table
\
\ ******************************************************************************

_TPART = 0              \ (not the Tube's parasite: R_POLY does both phases)
_HOSTB = TRUE           \ (a Model B: buffer 0 at BUF0, no ACCCON)
_RBANK = 2              \ (the Tube host's bank P's layout, which this extends)

 INCLUDE "1-source-files/main-sources/elite-map.asm"
 INCLUDE "1-source-files/main-sources/gfx-rws.asm"

 CLEAR &8000, &C000
 ORG &9000
 INCLUDE "3-assembled-output/nmos/gfx-raster.asm"
 CPU 0
 INCLUDE "3-assembled-output/nmos/gfx-raster_line.asm"
 CPU 0
.R_HIEND

 ORG &8000
 GUARD &9000
 INCLUDE "3-assembled-output/nmos/gfx-raster_poly.asm"
 CPU 0
 INCLUDE "3-assembled-output/nmos/gfx-raster_lineb.asm"
 CPU 0
 INCLUDE "3-assembled-output/nmos/gfx-raster_rep.asm"
 CPU 0
 INCLUDE "1-source-files/main-sources/gfx-raster_r.asm"
.R_LOEND

 ORG RJT               \ the entry points (gfx-rws.asm), in this order
 JMP R_INIT             \ RJT + 0
 JMP R_SETBUF           \ RJT + 3
 JMP R_RESETBUF         \ RJT + 6
 JMP R_REPAIR           \ RJT + 9
 JMP R_SPANM            \ RJT + 12 (R_SPAN, then R_MARKDIRTY)
 JMP R_MARKDIRTY        \ RJT + 15
 JMP R_DOT              \ RJT + 18
 JMP R_POLY             \ RJT + 21
 JMP R_LINE             \ RJT + 24
 JMP R_STARERASE        \ RJT + 27
 JMP R_STARPLOT         \ RJT + 30
.RJT_END

 ASSERT R_HIEND <= RJT AND R_LOEND <= &9000 AND r_lcold_end <= &9980
 ASSERT RDATA_END <= r_lcold AND MBOX_END <= GVARS

PRINT "Bank R (rasteriser): &8000-", ~R_LOEND-1, " (free ", &9000-R_LOEND, "), &9000-", ~R_HIEND-1, " (free ", RJT-R_HIEND, "), R_LINE's cold part &", ~r_lcold, "-", ~r_lcold_end-1, " (free ", &9980-r_lcold_end, "), the jump table &", ~RJT, "-", ~RJT_END-1

 SAVE "3-assembled-output/R.bin", &8000, &C000, &8000
