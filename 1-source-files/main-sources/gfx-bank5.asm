\ ******************************************************************************
\
\ gfx-bank5.asm - bank 5: the filled renderer's rasteriser (docs/renderer.md)
\
\ Port (Model B): the BBC Master port's rasteriser (gfx-raster*.asm), in NMOS
\ 6502 code, in one sideways RAM bank with all of its state. The Master port
\ spreads it over two windows (its polygon window in ANDY, its disc window
\ and shared region in bank 5); here bank 5 holds the rasteriser without its
\ disc layer, which the flight code's window in bank 7 holds:
\
\   &8000-&8FFF  R_POLY (both phases) and R_LINE (gfx-raster_poly.asm,
\                gfx-raster_line.asm), then the repair (R_REPAIR and
\                r7_rowrep: gfx-raster_rep.asm) and the disc layer's
\                requests (gfx-raster_dq.asm)
\   &9000-&95FF  the state: each buffer's dirty extents, this frame's written
\                extents (R_WL, R_WR) and R_POLY's edge tables (gfx-rws.asm)
\   &9600-&BFBF  the shared region (gfx-raster.asm): R_SETBUF and r_pgfix,
\                the spans, R_DOT, R_MARKDIRTY, the per-x tables at &9C00,
\                the 24 row runs at &A000 (with the stars' records and
\                variables in their tails), the stars, r_lput2 and the row
\                pages; R_LINE's cold part and R_RESETBUF in the room below
\                the per-x tables; R_INIT
\   &BFC0        RJT, the jump table
\
\ The row runs are assembled for buffer 1 (SCREEN%, &4000); r_pgfix moves a
\ run page's stores to the buffer it is used for (gfx-raster.asm).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"
 INCLUDE "1-source-files/main-sources/gfx-rws.asm"

 CPU 0                  \ (the NMOS 6502: no 65C02 instruction in this bank)

 CLEAR &8000, &C000
 ORG &9000

.R_DIRTYL0 SKIP 192     \ buffer 0's dirty extents (empty: L = 255, R = 0)
.R_DIRTYR0 SKIP 192
.R_WL      SKIP 192     \ this frame's written extents (R = 0: none)
.R_WR      SKIP 192
.R_DIRTYL1 SKIP 192     \ buffer 1's: buffer 0's + &300 (R_SETBUF patches only
.R_DIRTYR1 SKIP 192     \ operands' high bytes)
.R_PTA     SKIP 192     \ R_POLY's edge tables
.R_PTB     SKIP 192
 ASSERT R_DIRTYL1 = R_DIRTYL0 + &300 AND R_DIRTYR1 = R_DIRTYR0 + &300
 ASSERT P% = &9600

 INCLUDE "1-source-files/main-sources/gfx-raster.asm"
 INCLUDE "1-source-files/main-sources/gfx-raster_init.asm"
 INCLUDE "1-source-files/main-sources/gfx-raster_rep.asm"
 INCLUDE "1-source-files/main-sources/gfx-raster_dq.asm"
.R_HIEND
 ASSERT R_HIEND <= RJT

 CLEAR r_tfree, r_tables \ (gfx-raster.asm skips it)
 ORG r_tfree             \ R_LINE's cold part and the private state, then
 INCLUDE "1-source-files/main-sources/gfx-raster_lcold.asm"
 INCLUDE "1-source-files/main-sources/gfx-raster_reset.asm"
.R_GAPEND
 ASSERT R_GAPEND <= r_tables

 ORG &8000
 GUARD &9000
 INCLUDE "1-source-files/main-sources/gfx-raster_poly.asm"
 INCLUDE "1-source-files/main-sources/gfx-raster_line.asm"
.R_LOEND

 ORG RJT                \ the entry points (gfx-rws.asm), in this order
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
 JMP R_MARKBOX          \ RJT + 33
 JMP R_GETW             \ RJT + 36 (the disc layer's, gfx-raster_dq.asm)
 JMP R_DRAINQ           \ RJT + 39
.RJT_END

 PRINT "Bank 5 (rasteriser): &8000-", ~R_LOEND-1, " (free ", &9000-R_LOEND, "), &9600-", ~R_HIEND-1, " (free ", RJT-R_HIEND, "), R_LINE's cold part and R_RESETBUF to ", ~R_GAPEND-1, " (free ", r_tables-R_GAPEND, "), the jump table &", ~RJT, "-", ~RJT_END-1

 SAVE "3-assembled-output/BANK5.bin", &8000, &C000, &8000
