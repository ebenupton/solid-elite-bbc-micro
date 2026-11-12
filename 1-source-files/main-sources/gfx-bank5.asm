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
\   &8000-&97FF  the 24 row runs, a page each, which R_INIT makes at start
\                (gfx-raster.asm's bank 5 runs: not in the image), with the
\                stars' records and variables, and R_LINE's, in their tails
\   &9800-&A7FF  R_POLY (both phases) and R_LINE (gfx-raster_poly.asm,
\                gfx-raster_line.asm)
\   &A800-&ADFF  the state: each buffer's dirty extents, this frame's written
\                extents (R_WL, R_WR) and R_POLY's edge tables
\   &AE00 on     the shared region (gfx-raster.asm): R_SETBUF and r_pgfix,
\                the spans' core, the arithmetic; in the room below the
\                per-x tables, R_LINE's cold part, the private state,
\                R_RESETBUF, the frame layer's query (r_wq) and pf_tilt;
\                the per-x tables at R_TAB% (&B400); the row pages, the
\                stars; then r_setup, the repair (R_REPAIR and r7_rowrep:
\                gfx-raster_rep.asm), the disc layer's requests
\                (gfx-raster_dq.asm), the code a span's rows run (r_pclip,
\                r_pset, R_SPAN, R_DOT, R_MARKDIRTY) and R_INIT, and RJT,
\                the jump table, its address for the glue from this
\                assembly (bank5.py)
\
\ Each region is where it was before the runs were made at start, moved by
\ whole pages (the runs came after the per-x tables), so that no branch or
\ indexed read crosses a page that it did not.
\
\ Each file is placed by its passes (2-build-files/streams.py: every block's
\ "Area:" line names its place): this file INCLUDEs the bank 5 runs pass, the
\ bank 5 passes, the bank 5 end passes and, in the room below the per-x
\ tables, the bank 5 gap passes (3-assembled-output/<file>-bank5runs.asm,
\ -bank5.asm, -bank5end.asm, -bank5gap.asm), which bank5.py has streams.py
\ write first.
\
\ The row runs are made for buffer 1 (SCREEN%, &4000); r_pgfix moves a run
\ page's stores to the buffer it is used for (gfx-raster.asm).
\
\ The image, BANK5.bin (R.BANK), is from R_IMG% (R_POLY) to the bank's end:
\ bank5.py writes R_IMG% for the loader, which copies it there.
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-map.asm"
 INCLUDE "1-source-files/main-sources/gfx-rws.asm"

 CPU 0                  \ (the NMOS 6502: no 65C02 instruction in this bank)

 R_IMG% = &9800         \ R_POLY and R_LINE, then the rest of the bank: the image
 R_ST% = &A800          \ the state
 R_TAB% = &B400         \ the per-x tables

 CLEAR &8000, &C000

 ORG &8000              \ the row runs (made at start) and their tails
 INCLUDE "3-assembled-output/gfx-raster-bank5runs.asm"
 ASSERT P% = R_IMG%

 ORG R_ST%

.R_DIRTYL0 SKIP 192     \ buffer 0's dirty extents (empty: L = 255, R = 0)
.R_DIRTYR0 SKIP 192
.R_WL      SKIP 192     \ this frame's written extents (R = 0: none)
.R_WR      SKIP 192
.R_DIRTYL1 SKIP 192     \ buffer 1's: buffer 0's + &300 (R_SETBUF patches only
.R_DIRTYR1 SKIP 192     \ operands' high bytes)
.R_PTA     SKIP 192     \ R_POLY's edge tables
.R_PTB     SKIP 192
 ASSERT R_DIRTYL1 = R_DIRTYL0 + &300 AND R_DIRTYR1 = R_DIRTYR0 + &300
 ASSERT P% = R_ST% + &600

 INCLUDE "3-assembled-output/gfx-raster-bank5.asm"
 INCLUDE "3-assembled-output/gfx-raster_init-bank5.asm"
 INCLUDE "3-assembled-output/gfx-raster_rep-bank5.asm"
 INCLUDE "3-assembled-output/gfx-raster_dq-bank5.asm"
 INCLUDE "3-assembled-output/gfx-raster-bank5end.asm"
 INCLUDE "3-assembled-output/gfx-raster_init-bank5end.asm"

.RJT                    \ the entry points, in this order (gfx-glue.asm's T_n:
 JMP R_INIT             \ RJT + 0, through bank5-entry.asm, which bank5.py
 JMP R_SETBUF           \ RJT + 3 writes from this assembly's symbols)
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
 JMP R_GETW             \ RJT + 36 (the disc layer's and the text's, gfx-raster_dq.asm)
 JMP pf_tilt            \ RJT + 39 (the planet's surface's, gfx-planet7.asm)
.RJT_END
 ASSERT HI(RJT) = HI(RJT_END - 1)   \ (the trampolines set only a JSR's low byte)

.R_HIEND
 ASSERT R_HIEND <= &C000

 CLEAR r_tfree, r_tables \ (gfx-raster.asm skips it)
 ORG r_tfree             \ R_LINE's cold part and the private state, then
 INCLUDE "3-assembled-output/gfx-raster_lcold-bank5gap.asm"
 INCLUDE "3-assembled-output/gfx-raster_reset-bank5gap.asm"
 INCLUDE "3-assembled-output/gfx-raster_dq-bank5gap.asm"
 INCLUDE "3-assembled-output/gfx-planet7-bank5gap.asm"  \ (pf_tilt, which the flight
                        \ code's PF_HOOK calls through T_TILT)
.R_GAPEND
 ASSERT R_GAPEND <= r_tables

 ORG PFVH%              \ (pf_tilt's variables in main RAM, as the flight code's
 INCLUDE "3-assembled-output/gfx-planet7-mainhigh.asm"   \ layout places them)

 ORG R_IMG%
 GUARD R_ST%
.R_IMAGE                \ (for bank5.py: the image's start)
 INCLUDE "3-assembled-output/gfx-raster_poly-bank5.asm"
 INCLUDE "3-assembled-output/gfx-raster_line-bank5.asm"
.R_LOEND

 PRINT "Bank 5 (rasteriser): the row runs &8000-", ~R_IMG%-1, " (made at start), ", ~R_IMG%, "-", ~R_LOEND-1, " (free ", R_ST%-R_LOEND, "), ", ~R_ST%+&600, "-", ~R_HIEND-1, " (the jump table &", ~RJT, "-", ~RJT_END-1, "; free ", &C000-R_HIEND, "), R_LINE's cold part, R_RESETBUF, r_wq and pf_tilt to ", ~R_GAPEND-1, " (free ", r_tables-R_GAPEND, ")"

 SAVE "3-assembled-output/BANK5.bin", R_IMG%, &C000, R_IMG%
