\ ******************************************************************************
\
\ gfx-rws.asm - the rasteriser's bank R: its memory and its interface
\ (docs/renderer.md, "The rasteriser's bank R")
\
\ Port (Model B): the filled renderer's rasteriser is the BBC Master port's
\ (gfx-raster*.asm, from the Tube branch's Model B host versions, made NMOS),
\ in one sideways RAM bank, R, with all of its state. Its caller, the frame
\ layer, is in another bank (F) and cannot see bank R, so a call's inputs
\ go through the mailbox, MBOX (&7E00-&7E9F, main RAM), and its zero page:
\
\   zero page &06-&27   R_COLE, R_COLO (the colour pair), R_XL, R_XR (span
\                       ends), R_CL, R_CR, R_CT, R_CB (the clip window), and
\                       &10-&27 the rasteriser's scratch (the caller saves
\                       and restores the game's bytes there around a frame)
\   MBOX                R_POLY's vertices and colours, R_LINE's end points,
\                       the stars (and, unused, the disc layer's names)
\
\ The entry points are in a jump table at RJT (&BFC0), so that callers need
\ none of bank R's symbols; the frame layer enters it through the
\ trampolines in gfx-rtramp.asm (main RAM). Each routine is the Master
\ port's (gfx-raster.asm's header), except:
\
\   * there is no disc layer: R_DISCROWS (and its arrays) is gone, for room;
\     R_REPAIR does its other job, the repair of the buffer's dirty rows
\     (each row's dirty extent, widened to whole bytes, blacked through the
\     row runs, and R_WL/R_WR set to it), and a disc is drawn by the caller
\     as spans (R_SPAN, with R_MARKDIRTY for its repair next time);
\   * there is no lens flare (R_FLARE), for room.
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
R_SN     = MBOX + &4B   \ R_STARPLOT: the star count (0..24)
R_SCOL   = MBOX + &4C   \ R_STARPLOT: the stars' colour byte
R_SX     = MBOX + &50   \ R_STARPLOT: the stars' x, y and size (1..3), 24 each
R_SY     = MBOX + &68
R_SS     = MBOX + &80
R_PYS    = MBOX + &98   \ R_POLY's own: its first row, last row, last row + 1,
R_PYL1   = MBOX + &99   \ non-zero if some x is outside CL..CR (8-bit
R_PYE    = MBOX + &9A   \ polygons), CR + 1
R_PXC    = MBOX + &9B
R_PCR1   = MBOX + &9C
R_BY1    = MBOX + &9E   \ R_MARKBOX: the last row
MBOX_END = MBOX + &9F
 ASSERT R_SX = MB_SX AND R_SY = MB_SY AND R_SS = MB_SS   \ (elite-map.asm's names)

RJT = &BFC0             \ the entry points' jump table
