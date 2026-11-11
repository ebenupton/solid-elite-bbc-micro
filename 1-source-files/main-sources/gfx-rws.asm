\ ******************************************************************************
\
\ gfx-rws.asm - the rasteriser's bank 5: its memory and its interface
\ (docs/renderer.md, "The rasteriser's bank 5")
\
\ Port (Model B): the filled renderer's rasteriser is the BBC Master port's
\ (gfx-raster*.asm, in NMOS 6502 code), in one sideways RAM bank, 5, with all
\ of its state. Its caller, the frame layer, is in another bank (6) and
\ cannot see bank 5, so a call's inputs go through the mailbox, MBOX
\ (&7E00-&7E9F, main RAM), and its zero page:
\
\   zero page &06-&27   R_COLE, R_COLO (the colour pair), R_XL, R_XR (span
\                       ends), R_CL, R_CR, R_CT, R_CB (the clip window), and
\                       &10-&27 the rasteriser's scratch (the caller saves
\                       and restores the game's bytes there around a frame)
\   MBOX                R_POLY's vertices and colours, R_LINE's end points,
\                       the stars, R_MARKBOX's last row, the disc layer's
\                       batches and the frame layer's query (R_GETW)
\
\ The entry points are in a jump table, RJT, after the code (gfx-bank5.asm),
\ so that callers need only its address, which bank5.py writes for the glue
\ (3-assembled-output/bank5-entry.asm); the frame layer enters it through
\ the trampolines in gfx-glue.asm (main RAM). Each routine is the Master
\ port's (gfx-raster.asm's header), except:
\
\   * there is no disc layer: R_DISCROWS' row code (and its arrays) is the
\     flight code's bank 7's (gfx-raster_disc.asm, the painter, which the
\     frame layer drives); R_REPAIR does its other job, the repair of the
\     buffer's dirty rows outside the band of the disc layer's rows (each
\     row's dirty extent, widened to whole bytes, blacked through the row
\     runs, and R_WL/R_WR set to it);
\   * the lens flare (R_FLARE) is the frame layer's, in bank 6;
\   * there are no kept solid rows;
\   * the Model B's own entries: R_SPANM, R_MARKBOX and R_GETW (the disc
\     layer's batches: its queued spans drawn, its writes taken into R_WL
\     and R_WR, the next rows' extents given; and with A = &40 the frame
\     layer's query of this frame's written and dirty extents, r_wq).
\
\ ******************************************************************************

\ (BUF0, buffer 0's screen, and MBOX, the mailbox, are elite-map.asm's;
\ buffer 1's screen is SCREEN%, &4000, which gfx-raster.asm assumes)

ASSERT SCREEN% = &4000

R_PXL    = MBOX        \ R_POLY: vertex x, y (signed 16-bit), 16 each
R_PXH    = MBOX + &10
R_PYL    = MBOX + &20
R_PYH    = MBOX + &30
R_X0     = MBOX + &40   \ R_LINE: end points (signed 16-bit words, lo hi)
R_Y0     = MBOX + &42
R_X1     = MBOX + &44
R_Y1     = MBOX + &46
R_PN     = MBOX + &48   \ R_POLY: the vertex count (1..16)
R_COL2   = MBOX + &49   \ R_POLY: the colours of rows y AND 3 = 2, 3
R_COL3   = MBOX + &4A
R_SN     = MBOX + &4B   \ R_STARPLOT: the star count (0..19)
R_PYS    = MBOX + &4C   \ R_POLY's own: its first row, last row, last row + 1,
R_PYL1   = MBOX + &4D   \ non-zero if some x is outside CL..CR (8-bit
R_PYE    = MBOX + &4E   \ polygons), CR + 1
R_PXC    = MBOX + &4F
R_PCR1   = MBOX + &50
R_BY1    = MBOX + &51   \ R_MARKBOX: the last row
R_SCOL   = MBOX + &66   \ R_STARPLOT: the stars' colour byte
R_SX     = MBOX + &67   \ R_STARPLOT: the stars' x, y and size (1..3), 19 each
R_SY     = MBOX + &7A   \ (the game's hooks write stars 1 to NOST, 18)
R_SS     = MBOX + &8D
MBOX_END = MBOX + &A0
 ASSERT R_SX = MB_SX AND R_SY = MB_SY AND R_SS = MB_SS   \ (elite-map.asm's names)
 ASSERT R_SS + 19 = MBOX_END

\ The frame's disc layer (gfx-raster_disc.asm, in the flight code's bank 7,
\ docs/renderer.md "The disc layer") is given a batch of rows at a time in
\ the mailbox, &00 to &65 (R_SN is set for the stars after it, and R_SCOL,
\ R_SX, R_SY and R_SS are kept): a row of the batch is a slot, 0 to DB_N - 1
\ (16 for a disc of one colour, 8 with boundaries), each with its new span
\ (DB_NL, DB_NR: L = 255, R = 0 for none), its dirty extent going in and
\ what the layer wrote on it coming back (DB_WL, DB_WR: R = 0 for none; for
\ the second disc, R_DISC2, what was written on it so far going in), and
\ with boundaries its count and colour (DB_NN, as R_NDN) and its boundaries
\ (DB_X0 to DB_X3). Long spans the layer leaves to bank 5's row runs are
\ queued after them (DB_Q: row, left, right, colour byte), DB_QN bytes of
\ them. PCB, the planet's circles' records (gfx-merid.asm), PC_N
\ and pc_inv take &00 to &49, and their unclamped thresholds PC_TU &52 to
\ &5D, from PF_HOOK (in the game's iteration) to the frame's f_hrec, which
\ keeps them, and f_bounds (PC_ROWS).
DB_NL    = MBOX         \ (slots: 16 apart, the boundaries' between them)
DB_NN    = MBOX + &08
DB_NR    = MBOX + &10
DB_X0    = MBOX + &18
DB_WL    = MBOX + &20
DB_X1    = MBOX + &28
DB_WR    = MBOX + &30
DB_X2    = MBOX + &38
DB_X3    = MBOX + &40
DB_Q     = MBOX + &48   \ the queue (seven spans)
DB_QE    = MBOX + &64   \ (its end)
DB_PY    = MBOX + &64   \ R_GETW: the row of the batch whose writes it puts
DB_QN    = MBOX + &65   \ the queue's length in bytes (4 a span)
 ASSERT DB_QN < R_SCOL
PCB      = MBOX         \ the planet's circles' records (3 of 24 bytes)
PC_N     = MBOX + &48   \ how many
pc_inv   = MBOX + &49   \ the base colour
PC_TU    = MBOX + &52   \ their thresholds T1, T2 unclamped (16-bit, 4 a record)
PCX_END  = PC_TU + 4 * 3  \ (the frame's f_hrec keeps &00 to here)
 ASSERT PC_TU >= R_BY1 + 1 AND PCX_END <= DB_QE
