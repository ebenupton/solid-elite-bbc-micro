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
R_NDT    = MBOX + &98   \ (the disc layer's inputs: names only, as the
R_NDB    = MBOX + &99   \ shared code that bank R keeps refers to them;
R_NDF    = MBOX + &9A   \ nothing reads them)
R_DBE    = MBOX + &9B
R_DBO    = MBOX + &9C
R_NDN    = MBOX + &9D
R_NDP    = MBOX + &9D
R_NDX0   = MBOX + &9D
R_NDX1   = MBOX + &9D
R_NDX2   = MBOX + &9D
R_NDX3   = MBOX + &9D
R_NDISCL = MBOX + &9D
R_NDISCR = MBOX + &9D
R_BY1    = MBOX + &9E   \ R_MARKBOX: the last row
MBOX_END = MBOX + &9F
 ASSERT R_SX = MB_SX AND R_SY = MB_SY AND R_SS = MB_SS   \ (elite-map.asm's names)

\ Bank R's state (gfx-raster.asm lays the bank out around it)
R_DIRTYL0 = &9000       \ buffer 0's dirty extents (empty: L = 255, R = 0)
R_DIRTYR0 = &90C0
R_WL      = &9180       \ this frame's written extents (R = 0: none)
R_WR      = &9240       \ (whole in a page)
R_DIRTYL1 = &9300       \ buffer 1's: buffer 0's + &300 (R_SETBUF patches only
R_DIRTYR1 = &93C0       \ operands' high bytes)
R_DISCL0 = R_DIRTYL0    \ (the disc spans: names only, for code that bank R
R_DISCR0 = R_DIRTYR0    \ keeps but never runs)
R_DISCL1 = R_DIRTYL1
R_DISCR1 = R_DIRTYR1

RDATA = &9500           \ the rest of the state, where the Tube's bank P had
R_PRBUF   = RDATA       \ its inputs (PDATA): the scalars ...
R_PRDYT   = RDATA + 1
R_PRDYB   = RDATA + 3
R_PRDST   = RDATA + 5
R_PRDSB   = RDATA + 7
R_PRSCNT  = RDATA + 9
R_PRECNT  = RDATA + 11
R_PRWT    = RDATA + 13
R_PRWB    = RDATA + 14
R_PRBMODE = RDATA + 15
R_PRNT    = RDATA + 17
R_PRNB    = RDATA + 18
R_PRLO    = RDATA + 19
R_PRHI    = RDATA + 20
R_PRDYA   = RDATA + 21
R_PRDYZ   = RDATA + 22
R_PRCWB   = RDATA + 23
R_NTMP    = RDATA + &18 \ ... the NMOS conversion's temporaries (nmos.py's
R_NTMPY   = RDATA + &19 \ --tmp and --tmpy; the Tube's were in zero page) and
R_NTMPX   = RDATA + &1A \ R_LINE's cold part's (its PHX and PLX) ...
R_PYS     = RDATA + &20 \ ... R_POLY's private scalars ...
R_PYL1    = RDATA + &21
R_PYE     = RDATA + &22
R_PXC     = RDATA + &23
R_PCR1    = RDATA + &24
R_PTA     = RDATA + &100 \ ... and its edge tables
R_PTB     = RDATA + &1C0
RDATA_END = RDATA + &280

RJT = &BFC0             \ the entry points' jump table
