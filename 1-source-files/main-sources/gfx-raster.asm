\ ============================================================================
\ raster.asm -- filled-polygon / disc-layer / line / dot / star rasteriser for
\ the double-buffered CMYK MODE 1 Elite (BBC Master, 65C02).  See
\ docs/renderer.md for the screen layout and the frame model.
\
\ Files: raster_vars.asm and raster_scr.asm hold every variable and array the
\ caller reads or writes, and the state the rasteriser's parts share (the
\ shared workspace in main RAM, which every bank sees).  The code, tables and
\ private state are in three windows of sideways RAM (docs/memory-map.md):
\   this file, the shared region: bank 5 &9000-&BFFF (the per-x tables, the
\     boundary arrays, R_SETBUF, r_spc, the 24 row runs and their tails, the
\     stars), seen with either window below;
\   raster_disc.asm, the disc window: bank 5 &8000-&8FFF, paged with ROMSEL 5
\     (RASTBANK): R_DISCROWS and the dirty repair (R_INIT and R_RESETBUF
\     are in the shared region, raster_init.asm and raster_reset.asm);
\   raster_poly.asm and raster_line.asm, the polygon window: ANDY, paged with
\     ROMSEL &85 (RASTPOLY, ANDY over bank 5): R_POLY and R_LINE (R_LINE's
\     cold part, raster_lcold.asm, and R_POLY's arithmetic are here, for room).
\ The caller (the frame layer's T_ trampolines) pages ROMSEL &85 for R_POLY
\ and R_LINE and 5 for the rest; each returns with what it was entered with.
\ R_SETBUF pages the polygon window in for its operands there and 5 back.
\ Nothing calls between the two windows.  INCLUDE this file at &9000 (its
\ runs must start at a page whose number is a multiple of 32: asserted).  It
\ references no Elite symbol; all labels start with r_ / R_ / RZ_ (and r7_
\ for code that came from bank 7).  CPU 0 is selected (NMOS 6502: no 65C02
\ instruction), and CPU 1 again at the end.  The store runs are
\ self-modified (an RTS is planted and removed again), so it must run from
\ RAM.
\
\ ---------------------------------------------------------------- zero page
\ &06-&27 are used (the caller saves/restores them around rendering).
\   R_COLE, R_COLO  fill colour pair: byte for even rows, byte for odd rows
\   R_XL, R_XR      span ends for R_SPAN / R_MARKDIRTY (inclusive pixels)
\   R_CL, R_CR      clip window x min/max (inclusive). 1 <= CL <= CR <= 254
\   R_CT, R_CB      clip window y min/max (inclusive). 0 <= CT <= CB <= 191
\   R_DCE, R_DCO    disc colour pair (R_DISCROWS)
\   everything else in &10-&27 is internal scratch (RZ_*), clobbered by calls.
\ The clip window should stay constant from frame to frame; black the window
\ and R_RESETBUF both buffers after changing it.
\
\ ---------------------------------------------------------------- variables
\ (raster_vars.asm; empty span: L = 255, R = 0; for R_WL/R_WR, R = 0)
\   R_PN               polygon vertex count (1..16; more are ignored)
\   R_COL2, R_COL3     R_POLY's colour bytes for rows y AND 3 = 2, 3 (with
\                      R_COLE, R_COLO for rows 0, 1)
\   R_PXL/R_PXH/R_PYL/R_PYH  16-entry vertex arrays (signed 16-bit, y down)
\   R_X0,R_Y0,R_X1,R_Y1      line end points, signed 16-bit words (lo, hi)
\   R_SN               star count (0..24)
\   R_SX,R_SY,R_SS     24-entry star arrays: x, y (8-bit), size 1..3 (0: none)
\   R_SCOL             star colour byte (R_INIT sets &FF = logical colour 3)
\   R_NDT, R_NDB       new disc rows for R_DISCROWS (NDT > NDB: no disc)
\   R_NDISCL/R_NDISCR  new disc spans (rows NDT..NDB only) [192 each]
\   R_DIRTYL0/R0, R_DIRTYL1/R1  per-buffer dirty extents  [192 each]
\   R_DISCL0/R0,  R_DISCL1/R1   per-buffer disc spans     [192 each]
\   R_WL, R_WR         this frame's written extents (see R_DISCROWS) [192]
\   R_NDF              0: this frame's disc is plain colour A (the arrays
\                      below are ignored); else each disc row has:
\   R_NDN              bits 0-6: boundaries in the row, 0..4; bit 7: the
\                      colour at the span's left end before any flip
\                      (0 = A = R_DCE/R_DCO, 1 = B = R_DBE/R_DBO)    [192]
\   R_NDX0..R_NDX3     their x, ascending, inside (NDISCL, NDISCR]: pixels
\                      >= x take the other colour (flips at or left of
\                      NDISCL are folded into R_NDN's bit 7 by the
\                      caller)                                       [192]
\   R_DBE, R_DBO       colour B pair
\   (R_PTA/R_PTB, R_PYS..R_PCR1, R_BD*: private to the rasteriser.)
\ Coordinates passed to R_POLY / R_LINE must lie in -16384..16383.
\
\ ---------------------------------------------------------------- routines
\ Registers A, X, Y are not preserved unless stated.  Decimal mode must be off.
\
\ R_INIT       once at startup: clip window = 1..254 x 1..191, R_SCOL = &FF,
\              all per-buffer state empty, R_SETBUF 0.  Does not touch the
\              screen: follow with R_RESETBUF on a black window for each
\              buffer.
\ R_SETBUF     A = buffer 0/1 whose state arrays (dirty, disc, stars) the
\              following calls use.  Call it before drawing each frame.  It
\              self-modifies the code: ~85 operand high bytes are stored
\              (~400 cycles) when the buffer changes.
\ R_RESETBUF   forget the current buffer's state (no dirty, no disc, no
\              stars) without touching the screen; the caller guarantees the
\              buffer's clip window is black.  ~5000 cycles.  No R_INIT needed.
\ R_SPAN       Y = row, fill pixels R_XL..R_XR (within the clip window, XL<=XR)
\              with the colour pair.  Pure drawing: no state is updated.
\              Pass R_COLE = R_COLO = 0 for black.
\ R_POLY       filled convex polygon (R_PN, R_PXL..R_PYH), either winding, in
\              a 4-row colour: row y takes R_COLE, R_COLO, R_COL2, R_COL3 for
\              y AND 3 = 0, 1, 2, 3 (a 4x4 dither tile; set R_COL2 = R_COLE and
\              R_COL3 = R_COLO for a 2-row colour pair).  Pixel (x,y)
\              (centre at integer x,y) is filled when it
\              is inside, using a top-left rule: rows y0 <= y < y1 of each
\              edge, pixels ceil(xleft) <= x < ceil(xright), exact integer
\              edge stepping from the upper end point, so polygons sharing an
\              edge tile with no gaps or overlaps.  Clipped to the window.
\              Extends DIRTY of the current buffer.  Fast path when every
\              coordinate is 0..255.
\ R_LINE       1-pixel line R_X0,R_Y0 - R_X1,R_Y1 (inclusive), clipped; pixel
\              colour = the dither at its position.  Bresenham along the major
\              axis stepped in the increasing direction; minor coordinate =
\              round-half-up.  Extends DIRTY.  Fast path when both ends are
\              inside the window.
\ R_DOT        X = x, Y = y, A = size: 1 = 1x1, 2 = 2x1, 3 = 2x2 (right/down).
\              Clipped.  Extends DIRTY.
\ R_STARERASE  black every star pixel R_STARPLOT set last time in this buffer.
\ R_STARPLOT   plot stars R_SX/SY/SS (R_SN of them) in R_SCOL.  A star row's
\              pixels within one screen byte are set only if the whole byte
\              is black there (else that byte is left alone); remembered for
\              R_STARERASE.  Every fill the frame layer can draw that is not
\              pure black has a non-black pixel in every byte of every row
\              (2-build-files/starocc.py proves it over all of them), so no
\              star shows through one, even where its dither has black
\              pixels.  The one pure black fill, a station's docking slot,
\              is left in F_SLV by f_poly2: the frame layer takes the stars
\              in its bounding box out of R_SS for the plot (f_slot, bank
\              6).  It must be the frame's last drawing
\              (after the text overlay): stars then only ever replace black
\              that stays black, so neither plotting nor erasing them
\              touches R_WL/R_WR.
\ R_DISCROWS   the incremental disc layer for the current buffer (see below).
\              Enter with C clear: with C set it is R_DISC2, the second disc
\              behind the layer (gfx-raster_disc2.asm, in bank 5), after it.
\ R_MARKDIRTY  Y = row, extend this buffer's DIRTY[y] by R_XL..R_XR (use it
\              for anything else drawn into the buffer, e.g. text, so the next
\              R_DISCROWS on this buffer repairs it).
\
\ Frame order for buffer b:  R_SETBUF b; R_STARERASE; (fill R_NDISC*, R_NDT,
\ R_NDB, R_DCE/R_DCO) R_DISCROWS; R_POLY/R_LINE/R_DOT ...; text; R_STARPLOT.
\
\ R_DISCROWS first hands the dirty rows that are neither old nor new disc rows
\ to bank 7 (r7_crep): those rows hold only shapes over black there (text
\ cells under them are redrawn through R_WL/R_WR), so
\ the extent is widened to whole bytes and blacked by one row run, R_WL/R_WR
\ set to it; the row loop below then only visits the disc rows.
\ R_DISCROWS, per row y of the clip window: writes the disc colour on the new
\ span minus the intact part of the old one (old span minus old dirty) and
\ black on (old span + old dirty) minus the new span; then DISC[b][y] = new,
\ DIRTY[b][y] = empty.  Where the old disc is intact and an end moves, the
\ bytes between the old and new end are rewritten whole (black / disc / disc
\ from the new end on): pixels outside the disc there are black anyway.  It
\ also starts the frame's R_WL/R_WR (clearing last frame's rows): afterwards
\ they hold, per row, the extent of the disc-layer writes (and of the
\ dirty repair).  Shapes are NOT added to R_WL/R_WR: what was written this
\ frame is R_WL/R_WR[y] union DIRTY[b][y].
\ Rows of R_NDISCL/R in NDT..NDB with NDISCL = 255 are empty; spans are
\ within the clip window (the frame layer clamps them to it).
\ Two-colour discs (R_NDF <> 0): pixel x of a disc row has colour R_NDN's
\ bit 7 EOR (the number of its boundaries <= x).  Each buffer remembers its
\ rows' boundaries, up to three.  A changed row with no dirty extent is a
\ list of edges (span start, flips, span end + 1), each with an old and a
\ new position; old and new are made the same length with virtual flips (at
\ the left end if the colours there differ, then at the end), and each
\ edge's strip between its positions is written, cut short where a
\ neighbour's new position has passed into it: only the pixels whose
\ colour changed (r_dq if only boundaries moved, else r_dpe).  Rows with a
\ dirty extent, an unknown old count or more than three flips are repainted
\ whole (r_drg).  Pass new spans already clamped (with flips at or left of
\ NDISCL folded into R_NDN) so unchanged rows are recognised by the cheap
\ comparison.  A change of
\ the colours A/B must be handled by the caller as now: fold the old disc
\ into DIRTY (R_MARKDIRTY) first.
\ ============================================================================


R_COLE  = &06
R_COLO  = &07
R_XL    = &08
R_XR    = &09
R_CL    = &0A
R_CR    = &0B
R_CT    = &0C
R_CB    = &0D
R_DCE   = &0E
R_DCO   = &0F
RZ_PA   = &10           \ (lo = y AND 7, hi = row page)  bytes of columns 0..31
RZ_PB   = &12           \ (lo = y AND 7, hi = row page+1) columns 32..63
RZ_PP   = &14           \ RTS plant pointer / pixel pointer
RZ_COL  = &16           \ this row's colour byte
RZ_Y    = &17           \ current row
RZ_SA   = &18           \ edge A: x (16)            } side 0 (offset 0)
RZ_CE   = &18           \ (phase B: this row pair's colours, even and odd rows)
RZ_CO   = &19
RZ_TA   = &1A           \ edge A: error term (16)   }
RZ_XE   = &1A           \ (phase B: COLE EOR COL2, COLO EOR COL3)
RZ_XO   = &1B
RZ_SB   = &1C           \ edge B: x (16)            } side 1 (offset 4)
RZ_TB   = &1E           \ edge B: error term (16)   }
RZ_T0   = &20
RZ_T1   = &21
RZ_T2   = &22
RZ_T3   = &23
RZ_T4   = &24
RZ_T5   = &25
RZ_T6   = &26
RZ_T7   = &27
\ R_LINE's (gfx-raster_line.asm; here, as gfx-raster_lcold.asm uses them too)
l_x0 = &18              \ (rl_gen's pixel-by-pixel loop: x, y, as l_x0,X)
l_y0 = &19
l_x1 = &1A
l_y1 = &1B
l_e  = &1C
l_m  = &1D
l_n  = &1E
l_a  = &1F
l_b  = &20
l_x  = &21
l_k  = &22              \ kind (0..3)

r_opSTA = &99           \ STA abs,Y (the row runs are indexed by the row, as bank 7's)
r_opRTS = &60


.r_start

\ (Model B: bank 5's state, from &9000, comes first: gfx-rws.asm; this file's
\ code starts after it)
\ Row set-up.  Y = row (0..191; kept).  Sets RZ_Y, RZ_PA, RZ_PB, the run page
\ (RZ_PP+1, r_jsr+2 and r_spc's r_spl+2, r_spr+2).  Clobbers A; C = 0 on exit
\ (R_POLY's phase B set-up relies on it).
.r_rowset
  STY RZ_Y
  TYA
  AND #7
  STA RZ_PA
  STA RZ_PB
.^r_yp1
  LDA r_ypg,Y             \ NMOS: the row's screen page from r_ypg (&40 +
  STA RZ_PA+1             \ 2 * (Y DIV 8): even; Model B: r_ypg0's &10 + ... for
  ORA #1                  \ buffer 0, R_SETBUF's), + 1 by ORA, not INC A
  STA RZ_PB+1
  LSR A                   \ &20 + Y DIV 8 (buffer 0: &08 + ...), C = 1 (bit 0)
.^r_yp1r
  ADC #HI(r_run0) - &21   \ (+ 1 from C: HI(r_run0) + Y DIV 8; C = 0; buffer 0:
  STA RZ_PP+1             \ R_SETBUF's - &09)
  STA r_jsr+2
  STA r_spl+2
  STA r_spr+2
  JMP r_pgfix             \ (Model B: the run page's stores for this buffer)
ASSERT r_s1y = r_s0y + &300 AND r_s1x = r_s0x + &300
ASSERT r_s1a = r_s0a + &300 AND r_s1b = r_s0b + &300

\ ============================================================================
\ Per-buffer row arrays: buffer 1's are buffer 0's + &300 (R_SETBUF adds 3 to
\ the high byte of every patched operand).
\ ============================================================================
r_ta = R_PTA            \ polygon edge tables (raster_scr)
r_ystart = R_PYS        \ polygon rows ystart..ylast, yend = ylast + 1, any x
r_ylast = R_PYL1        \ outside CL..CR (raster_scr: bank 7's phase A sets
r_yend = R_PYE          \ them for 16-bit polygons), CR + 1
r_xclip = R_PXC
r_cr1 = R_PCR1
r_tb = R_PTB

\ the API arrays live in raster_vars.asm; the rasteriser's private state,
\ R_PRBUF (the current buffer), R_PRDYT/R_PRDYB (per buffer: rows that may
\ have a dirty extent), R_PRDST/R_PRDSB (per buffer: rows of its disc),
\ R_PRSCNT (per buffer: star records), R_PRECNT (per buffer: star records
\ erased, not yet in WL), R_PRWT/R_PRWB (rows of WL/WR that may be non-empty)
\ and R_PRBMODE (per buffer: its rows may hold boundaries), is at the end of
\ the shared region (gfx-raster_lcold.asm)
r_dl = R_DIRTYL0
r_dr = R_DIRTYR0
r_dl1 = R_DIRTYL1
r_dr1 = R_DIRTYR1

\ ============================================================================
\ R_SETBUF: A = buffer.  Patches every buffer-dependent operand (high byte).
\ ============================================================================
.R_SETBUF
{
  AND #1
  CMP R_PRBUF
  BNE go
  RTS
.go
  STA R_PRBUF
  TAX
  LDA r_sbh_dl,X          \ group r_dl
  STA r_pt01+2
  STA r_pt02+2
  STA r_pt05+2
  STA r_pt06+2
  STA r_pt601+2           \ (R_GETW's: gfx-raster_dq.asm)
  STA r_pt602+2
  LDA r_sbh_dr,X          \ group r_dr
  STA r_pt03+2
  STA r_pt04+2
  STA r_pt07+2
  STA r_pt08+2
  STA r_pt603+2
  STA r_pt604+2
  LDA r_sbh_s0a,X          \ group r_s0a
  STA r_pt32+2
  STA r_pt36+2
  STA r_pt416+2
  STA r_pt418+2
  LDA r_sbh_s0b,X          \ group r_s0b
  STA r_pt33+2
  STA r_pt37+2
  LDA r_sbh_s0x,X          \ group r_s0x
  STA r_pt31+2
  STA r_pt35+2
  STA r_pt415+2
  LDA r_sbh_s0y,X          \ group r_s0y
  STA r_pt30+2
  STA r_pt34+2
  STA r_pt414+2
  LDA r_sbl_ypg,X         \ Model B: the screen's row pages, r_ypg0 (buffer 0,
  STA r_yp1+1             \ BUF0) or r_ypg (buffer 1, SCREEN%)
  STA r_yp2+1
  STA r_yp3+1
  STA r_yp4+1
  STA r_yp5+1
  STA r_yp6+1
  LDA r_sbh_ypg,X
  STA r_yp1+2
  STA r_yp2+2
  STA r_yp3+2
  STA r_yp4+2
  STA r_yp5+2
  STA r_yp6+2
  LDA r_sbrun,X           \ r_rowset's run page from the screen page
  STA r_yp1r+1
  LDA #&FF                \ no run page checked for this buffer yet (r_pgfix)
  STA r_pglast
  JMP r_sbpoly             \ (phase B's operands)
}
.r_sbl_ypg EQUB LO(r_ypg0), LO(r_ypg)
.r_sbh_ypg EQUB HI(r_ypg0), HI(r_ypg)
.r_sbrun EQUB HI(r_run0) - &09, HI(r_run0) - &21
ASSERT HI(BUF0) = &10 AND HI(SCREEN%) = &40   \ (r_ypg0's and r_ypg's pages)

\ ============================================================================
\ r_pgfix (Model B): A = a run page.  The runs are assembled for buffer 1
\ (SCREEN%, &4000); buffer 0's screen (BUF0, &1000) is &3000 lower.  If this
\ bank's copy of the page is not for the buffer R_SETBUF chose, the high byte
\ of each of its 63 stores' addresses has &30 taken off or added, seven
\ stores a pass, by SBC or ADC #&30 with the carry left as it was set (the
\ high bytes are &10-&3F or &40-&6F: nothing carries out), X counting the
\ passes (the Tube's Model B host's patcher: about 12 cycles a store).  The
\ page last checked for the buffer is noted, so a run of rows in one
\ character row costs one test.  Keeps X and Y, and leaves C = 0 (as
\ r_rowset must).
\ ============================================================================
.r_pgfix
{
  EOR r_pglast            \ the page last checked: nothing to do (A = 0; EOR
  BNE chk                 \ keeps C)
  RTS
.chk
  EOR r_pglast            \ (A = the page again)
  STA r_pglast
  STX pfx
  TAX
  LDA r_pgtag-HI(r_run0),X
  CMP R_PRBUF
  BNE fix
  LDX pfx                 \ the page's stores are for this buffer already
  CLC
  RTS
.fix
  LDA R_PRBUF             \ the page is now for this buffer
  STA r_pgtag-HI(r_run0),X
  STY pfy
  TXA                     \ the page into the loop's loads and stores
FOR k, 0, 6
  STA lp + 5 + 8 * k
  STA lp + 10 + 8 * k
NEXT
  LDX R_PRBUF
  LDA r_pgop,X            \ buffer 0: SBC #&30, carry set; buffer 1: ADC #&30,
FOR k, 0, 6               \ carry clear
  STA lp + 6 + 8 * k
NEXT
  TXA
  EOR #1
  LSR A
  LDX #8                  \ the stores' high bytes: offsets 2, 5, .. 188, seven
.lp                       \ a pass, 21 apart
  LDY r_pgy,X
FOR k, 0, 6
  LDA &FF02 + 3 * k,Y
  ADC #&30
  STA &FF02 + 3 * k,Y
NEXT
  DEX
  BPL lp
  LDY pfy
  LDX pfx
  CLC                     \ (r_rowset's C = 0)
  RTS
.pfx EQUB 0
.pfy EQUB 0
}
.r_pglast EQUB &FF        \ the run page last checked for buffer R_PRBUF (&FF: none)
.r_pgtag                  \ per run page: the buffer its stores are for (as
FOR i, 0, 23              \ assembled: 1)
  EQUB 1
NEXT
.r_pgop EQUB &E9, &69     \ to buffer 0: SBC #; to buffer 1: ADC #
.r_pgy                    \ the loop's passes' Y
FOR i, 0, 8
  EQUB 21 * i
NEXT

\ ============================================================================
\ r_spc: the span core.  Row set up (r_rowset), RZ_COL = colour byte,
\ X = R_XL = left pixel, R_XR = right pixel, R_XL <= R_XR.  Clobbers A, X, Y.
\ NMOS: the RTS is planted and taken out again by STA run page,X (r_spl,
\ r_spr: their high bytes are the run page, from r_rowset), X = the plant's
\ offset, which the run keeps, not by STA (RZ_PP): the same cycles a span.
\ ============================================================================
.r_spc
{
  TXA                     \ N = xl >= &80 (from TXA)
  BMI lb
  EOR R_XR
  CMP #4
  BCC one                 \ both ends in one byte
  LDY r_xo,X
  LDA (RZ_PA),Y           \ left edge, columns 0..31
  EOR RZ_COL
  AND r_lm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
.run
  LDA r_j,X               \ entry: column xl DIV 4 + 1 (= the plant when no
  STA r_jsr+1             \ whole byte lies between: the JSR hits the RTS)
  LDY R_XR
  LDX r_j-4,Y             \ plant: column xr DIV 4
  LDA #r_opRTS
.^r_spl
  STA &FF00,X             \ (high byte: the run page)
  LDY RZ_Y                \ (the run is indexed by the row)
  LDA RZ_COL
.^r_jsr
  JSR &FFFF
  LDA #r_opSTA            \ (X = the plant still)
.^r_spr
  STA &FF00,X             \ (high byte: the run page)
  LDA RZ_COL
  LDX R_XR                \ right edge (N = XR >= &80)
  BMI rb
  LDY r_xo,X
  EOR (RZ_PA),Y
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.rb
  LDY r_xo,X
  EOR (RZ_PB),Y
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
.lb                       \ xl >= &80 (A = xl)
  EOR R_XR
  CMP #4
  BCC one                 \ both ends in one byte
  LDY r_xo,X
  LDA (RZ_PB),Y           \ left edge, columns 32..63
  EOR RZ_COL
  AND r_lm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  BCS run                 \ (NMOS: C = 1 from the CMP #4)
.one
  LDY r_xo,X
  CPX #&80                \ XL, XR differ only in bits 0-1 (XL EOR XR < 4)
  BCS ob
  LDA (RZ_PA),Y
  EOR RZ_COL
  AND r_lm,X
  LDX R_XR
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.ob
  LDA (RZ_PB),Y
  EOR RZ_COL
  AND r_lm,X
  LDX R_XR
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
}

\ ============================================================================
\ R_SPAN: Y = row, R_XL..R_XR, colour pair R_COLE/R_COLO.
\ ============================================================================

\ ============================================================================
\ Pixel address: X = x, Y = y -> RZ_PP = address of the byte.  Keeps X, Y.
\ ============================================================================

\ ============================================================================
\ r_pset: X = x, Y = y (inside the clip window): pixel in the colour pair's
\ dither, extends DIRTY[y] and the buffer's row range.  Clobbers A, RZ_PP,
\ RZ_T6, RZ_T7; keeps X, Y.
\ ============================================================================

\ r_pclip: X = x, Y = y: r_pset (and row range) if inside the clip window

\ ============================================================================
\ R_DOT: X = x, Y = y, A = size (1 = 1x1, 2 = 2x1, 3 = 2x2)
\ ============================================================================

\ ============================================================================
\ R_MARKDIRTY: Y = row, extend DIRTY[b][y] by R_XL..R_XR.
\ ============================================================================


\ R_SETBUF's last part: phase B's DIRTY operands (gfx-raster_poly.asm; X =
\ buffer)
.r_sbpoly
  LDA r_sbh_dl,X          \ group r_dl
  STA r_pt60+2
  STA r_pt410+2
  STA r_pt61+2
  STA r_pt411+2
  LDA r_sbh_dr,X          \ group r_dr
  STA r_pt62+2
  STA r_pt412+2
  STA r_pt63+2
  STA r_pt413+2
  RTS


\ ----------------------------------------------------------------------------
\ The polygon window's arithmetic (R_POLY's phase A, gfx-raster_poly.asm),
\ here for room: r_div8, r_dvq and the 32-bit multiply and divide with their
\ variables (none uses anything of the polygon window's)
\ ----------------------------------------------------------------------------
\ r_div8: A / r_v0 -> r_m0 quotient (and X: r7_esgen uses it), A remainder.
.r_div8
{
  STA RZ_T6               \ dividend, becoming the quotient
  LDA r_v0
  STA RZ_T7
  LDA #0
  LDX #8
.lp
  ASL RZ_T6
  ROL A
  BCS sb
  CMP RZ_T7
  BCC ns
.sb
  SBC RZ_T7
  INC RZ_T6
.ns
  DEX
  BNE lp
  LDX RZ_T6
  STX r_m0
  RTS
}

\ r_dvq: A / RZ_T1 (A >= RZ_T1 >= 1) -> r_m0 quotient, A remainder.
\ Repeated subtraction when the quotient is small (divisor >= 16).
.r_dvq
{
  LDX RZ_T1
  CPX #16
  BCC small
  LDX #&FF                \ divisor >= 16: quotient < 16
  SEC
.lp
  INX
  SBC RZ_T1
  BCS lp
  ADC RZ_T1
  STX r_m0
  RTS
.small
  STA RZ_T6               \ divisor < 16: quotient < 16 unless A >= 16 * d
  TXA
  ASL A
  ASL A
  STA RZ_T7               \ 4d
  ASL A
  ASL A                   \ 16d (< 256)
  CMP RZ_T6
  BEQ long
  BCC long
  LDA RZ_T6
  LDX #&FC
  SEC
.l4
  INX
  INX
  INX
  INX
  SBC RZ_T7
  BCS l4
  ADC RZ_T7
  DEX
.l1
  INX
  SBC RZ_T1
  BCS l1
  ADC RZ_T1
  STX r_m0
  RTS
.long
  LDX RZ_T1
  STX r_v0
  JMP r_div8+2            \ (RZ_T6 already holds the dividend: skip r_div8's STA RZ_T6)
}
\ the 32-bit multiply and divide
.rp_m0 EQUB 0           \ 32-bit dividend / product; quotient m0,m1
.rp_m1 EQUB 0
.rp_m2 EQUB 0           \ remainder m2,m3
.rp_m3 EQUB 0
.rp_v0 EQUB 0           \ divisor
.rp_v1 EQUB 0
.rp_ma EQUW 0           \ multiplicand
.rp_mb EQUW 0           \ multiplier
.rp_mul16
{
  LDA #0
  STA rp_m2
  STA rp_m3
  LDX #16
.lp
  LSR rp_mb+1
  ROR rp_mb
  BCC ns
  CLC
  LDA rp_m2
  ADC rp_ma
  STA rp_m2
  LDA rp_m3
  ADC rp_ma+1
  STA rp_m3
.ns
  ROR rp_m3
  ROR rp_m2
  ROR rp_m1
  ROR rp_m0
  DEX
  BNE lp
  RTS
}
.rp_div32
{
  LDX #16
.lp
  ASL rp_m0
  ROL rp_m1
  ROL rp_m2
  ROL rp_m3
  BCS sb
  LDA rp_m2
  CMP rp_v0
  LDA rp_m3
  SBC rp_v1
  BCC ns
.sb
  LDA rp_m2
  SBC rp_v0
  STA rp_m2
  LDA rp_m3
  SBC rp_v1
  STA rp_m3
  INC rp_m0
.ns
  DEX
  BNE lp
  RTS
}

\ (free to the per-x tables)
.r_tfree

\ ============================================================================
\ Page-aligned per-x tables, at &9C00: the row runs after them start at &A000
\ (a page whose number is a multiple of 32: asserted below)
\ ============================================================================
ASSERT P% <= &9C00
SKIP &9C00 - P%
.r_tables
.r_xo                   \ (8 * (x DIV 4)) AND &FF : edge byte offset
FOR x, 0, 255
  EQUB (x * 2) AND &F8
NEXT
.r_jm                   \ 3 * (x DIV 4) - 3 = r_j[x - 4]: run plant offset (column x DIV 4)
FOR x, 0, 255           \ (read as r_j-4,Y with Y = xr >= 4: page-aligned, no crossing)
  IF x < 4
    EQUB &F8              \ (what r_j-4,Y read here before: r_xo[252..255])
  ELSE
    EQUB 3 * (x DIV 4) - 3
  ENDIF
NEXT
r_j = r_jm + 4          \ r_j,X = 3 * (x DIV 4) for X = xl <= 251 (never crosses the page)
.r_lm                   \ pixels (x AND 3)..3 of a byte
FOR x, 0, 255
  EQUB ((&F0 >> (x AND 3)) AND &F0) OR (&0F >> (x AND 3))
NEXT
.r_rm                   \ pixels 0..(x AND 3) of a byte
FOR x, 0, 255
  EQUB ((&F0 << (3 - (x AND 3))) AND &F0) OR ((&0F << (3 - (x AND 3))) AND &0F)
NEXT

\ ============================================================================
\ The store runs: one page per character row r (24), STA &4000+&200r+8c-8r,Y (Y =
\ the row: the same form as bank 7's r7_rrun) for
\ c = 1..63 then RTS (190 bytes).  The 66 bytes after each run hold variables.
\ ============================================================================
MACRO R_RUN r
  FOR c, 1, 63
    STA &4000 + r * &200 + c * 8 - r * 8, Y
  NEXT
  RTS
  EQUB 0                  \ spare: the 'nothing planted' target (offset 190)
ENDMACRO

MACRO R_ENDPAGE r
  ASSERT P% <= r_run0 + (r + 1) * &100
  ALIGN &100
ENDMACRO

.r_run0 R_RUN 0
.r_s0y SKIP 48          \ star records, buffer 0: row
.r_dsz EQUB 0           \ R_DOT
.r_dx EQUB 0
.r_dy EQUB 0
.r_k EQUB 0             \ stars
R_ENDPAGE 0
.r_run1 R_RUN 1
.r_s0x SKIP 48          \ buffer 0: x of first pixel
R_ENDPAGE 1
.r_run2 R_RUN 2
.r_s0a SKIP 48          \ buffer 0: mask set in column x DIV 4
R_ENDPAGE 2
.r_run3 R_RUN 3
.r_s1y SKIP 48          \ buffer 1 (= buffer 0 + &300)
R_ENDPAGE 3
.r_run4 R_RUN 4
.r_s1x SKIP 48
R_ENDPAGE 4
.r_run5 R_RUN 5
.r_s1a SKIP 48
R_ENDPAGE 5
.r_run6 R_RUN 6
.r_s0b SKIP 48          \ buffer 0: mask set in column x DIV 4 + 1
R_ENDPAGE 6
.r_run7 R_RUN 7
.r_s0r SKIP 48          \ star records, buffer 0: row
R_ENDPAGE 7
.r_run8 R_RUN 8
.r_s1r SKIP 48          \ buffer 1: row
.r_m0 EQUB 0            \ r_div8, r_dvq: quotient
.r_v0 EQUB 0            \ r_div8: divisor
R_ENDPAGE 8
.r_run9 R_RUN 9
.r_s1b SKIP 48
R_ENDPAGE 9
.r_run10 R_RUN 10
.r_n EQUB 0
.r_i0 EQUB 0
.r_i1 EQUB 0
.r_yminL EQUB 0
.r_yminH EQUB 0
.r_ymaxL EQUB 0
.r_ymaxH EQUB 0
.r_top EQUB 0
.r_cc EQUB 0
R_ENDPAGE 10
.r_run11 R_RUN 11
R_ENDPAGE 11
.r_run12 R_RUN 12
.r_s1k SKIP 48          \ buffer 1: star's first pixel
R_ENDPAGE 12
.r_run13 R_RUN 13
.r_s0k SKIP 48          \ buffer 0: star's first pixel
R_ENDPAGE 13
.r_run14 R_RUN 14
.r_pclip
{
  CPX R_CL
  BCC out
  CPX R_CR
  BEQ ok1
  BCS out
.ok1
  CPY R_CT
  BCC out
  CPY R_CB
  BEQ ok2
  BCS out
.ok2
  TYA                     \ extend the buffer's row range by row Y
  LDY R_PRBUF
  CMP R_PRDYT,Y
  BCS n3
  STA R_PRDYT,Y
.n3
  CMP R_PRDYB,Y
  BCC n4
  STA R_PRDYB,Y
.n4
  TAY                     \ Y = row again
  JMP r_pset1             \ tail call (NMOS: past r_pset's TYA, A = row)
.out
  RTS
}
\ R_SETBUF's and r_dbm's high bytes of each buffer's arrays
.r_sbh_dl EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
ASSERT LO(R_DIRTYL0) = LO(R_DIRTYL1)
.r_sbh_dr EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
ASSERT LO(R_DIRTYR0) = LO(R_DIRTYR1)
.r_sbh_s0a EQUB HI(r_s0a), HI(r_s1a)
ASSERT LO(r_s0a) = LO(r_s1a)
.r_sbh_s0x EQUB HI(r_s0x), HI(r_s1x)
ASSERT LO(r_s0x) = LO(r_s1x)
.r_sbh_s0y EQUB HI(r_s0y), HI(r_s1y)
ASSERT LO(r_s0y) = LO(r_s1y)
.r_sbh_s0k EQUB HI(r_s0k), HI(r_s1k)
ASSERT LO(r_s0k) = LO(r_s1k)
.r_sbh_s0r EQUB HI(r_s0r), HI(r_s1r)
ASSERT LO(r_s0r) = LO(r_s1r)
.r_sbh_s0b EQUB HI(r_s0b), HI(r_s1b)
ASSERT LO(r_s0b) = LO(r_s1b)
R_ENDPAGE 14
.r_run15 R_RUN 15
.r_pset
{
  TYA                     \ RZ_PP + (Y AND 1) = screen address of (X, Y)
.^r_pset1
  AND #6                  \ (NMOS: the row's bit 0 is the index below)
  ORA r_xo,X
  STA RZ_PP
.^r_yp2
  LDA r_ypg,Y
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDA r_lm,X
  AND r_rm,X
  STA RZ_T6
  STY RZ_T7               \ (NMOS: Y kept here)
ASSERT R_COLO = R_COLE + 1
  TYA
  AND #1
  TAY
  LDA R_COLE,Y            \ R_COLE, or R_COLO for an odd row
  EOR (RZ_PP),Y
  AND RZ_T6
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  LDY RZ_T7
  TXA
.^r_pt01 CMP r_dl,Y
  BCS n1
.^r_pt02 STA r_dl,Y
.n1
.^r_pt03 CMP r_dr,Y
  BCC n2
.^r_pt04 STA r_dr,Y
.n2
  RTS
}
R_ENDPAGE 15
.r_run16 R_RUN 16
.R_SPAN
{
  LDA R_XR
  CMP R_XL
  BCC out
  JSR r_rowset
  TYA
  AND #1
  TAX
  LDA R_COLE,X            \ R_COLE, or R_COLO for an odd row
  STA RZ_COL
  LDX R_XL
  JMP r_spc
.out
  RTS
}
\ R_LINE's variables (gfx-raster_line.asm, gfx-raster_lcold.asm)
.rl_lct SKIP 8          \ R_LINE: colour byte by row AND 7
.rl_lbuf EQUB &FF       \ buffer R_LINE's DIRTY operands are patched for
\ rl_gen's variables (16-bit: lo, hi)
.rl_dx SKIP 2            \ P1 - P0: x, y (rl_dx + 2)
.rl_dy SKIP 2
.rl_ax SKIP 2            \ |dx|, |dy| (rl_ax + 2)
.rl_ay SKIP 2
.rl_d  SKIP 2            \ |d major|
.rl_a  SKIP 2            \ |d minor|
.rl_h  SKIP 2            \ d DIV 2
.rl_m0 SKIP 2            \ the left / top end: major, minor
.rl_n0 SKIP 2
.rl_i  SKIP 2            \ the first pixel inside, the last (i)
.rl_j  SKIP 2
.rl_t  SKIP 2            \ rl_mdq's signed addend
.rl_mo SKIP 1            \ major axis: 0 = x, 2 = y (an offset into R_X0.., R_CL..)
.rl_s  SKIP 1            \ bit 7: the minor coordinate decreases
.rl_lo SKIP 1            \ major window lo, hi; minor window lo, hi
.rl_hi SKIP 1
.rl_nl SKIP 1
.rl_nh SKIP 1
R_ENDPAGE 16
.r_run17 R_RUN 17
.R_DOT
{
  STA r_dsz
  STX r_dx
  STY r_dy
  JSR r_pclip
  LDA r_dsz
  CMP #2
  BCC done
  LDX r_dx
  INX
  BEQ row2
  LDY r_dy
  JSR r_pclip
.row2
  LDA r_dsz
  CMP #3
  BCC done
  LDY r_dy
  INY
  BEQ done
  LDX r_dx
  JSR r_pclip
  LDX r_dx
  INX
  BEQ done
  JSR r_pclip
.done
  RTS
}
R_ENDPAGE 17
.r_run18 R_RUN 18
.R_MARKDIRTY
{
  LDA R_XL
.^r_pt05 CMP r_dl,Y
  BCS n1
.^r_pt06 STA r_dl,Y
.n1
  LDA R_XR
.^r_pt07 CMP r_dr,Y
  BCC n2
.^r_pt08 STA r_dr,Y
.n2
  LDX R_PRBUF
  TYA
  CMP R_PRDYT,X
  BCS n3
  STA R_PRDYT,X
.n3
  CMP R_PRDYB,X
  BCC n4
  STA R_PRDYB,X
.n4
  RTS
}
R_ENDPAGE 18
.r_run19 R_RUN 19
R_ENDPAGE 19
.r_run20 R_RUN 20
R_ENDPAGE 20
.r_run21 R_RUN 21
R_ENDPAGE 21
.r_run22 R_RUN 22
R_ENDPAGE 22
.r_run23 R_RUN 23
R_ENDPAGE 23
ASSERT (HI(r_run0) AND 31) = 0   \ (the repair: the row's run page is Y DIV 8 OR HI(r_run0))


\ ============================================================================
\ R_STARERASE: black the pixels R_STARPLOT set last time in this buffer.
\ Records: row (+&80: also the next byte), x, mask set in x's byte.
\ ============================================================================
.R_STARERASE
{
  LDY R_PRBUF             \ NMOS: the records last to first (the ANDs
  LDX R_PRSCNT,Y          \ commute), Y = 0 for (RZ_PP),Y
  BEQ edone               \ (none: the count is 0 already)
  LDA #0
  STA R_PRSCNT,Y
  TAY
  DEX
.el
.^r_pt30 LDA r_s0y,X      \ byte address (bit 7 of the high byte: one byte)
  STA RZ_PP
.^r_pt31 LDA r_s0x,X
  BMI e1
  STA RZ_PP+1
  LDA (RZ_PP),Y
.^r_pt32 AND r_s0a,X      \ inverse mask
  STA (RZ_PP),Y
.^r_pt33 LDA r_s0b,X
  CMP #&FF
  BEQ en
  LDY #8
  AND (RZ_PP),Y
  STA (RZ_PP),Y
  LDY #0
  BEQ en                  \ (always)
.e1
  AND #&7F
  STA RZ_PP+1
  LDA (RZ_PP),Y
.^r_pt418 AND r_s0a,X
  STA (RZ_PP),Y
.en
  DEX
  BPL el                  \ (fewer than 48 records)
.edone
  RTS
}

\ ============================================================================
\ Stars
\ ============================================================================

{
.sdone
  LDX R_PRBUF
  LDA r_k
  STA R_PRSCNT,X
  RTS
.slow
  STX RZ_SA               \ (X = x, Y = y on every branch here)
  STY RZ_SA+1
  JSR r_strow
  LDA RZ_TA
  CMP #3
  BCC sd1
  INC RZ_SA+1
  BEQ sd1
  JSR r_strow
.sd1
  LDX RZ_TA+1
  BPL snext               \ (always: X < 24)
.^R_STARPLOT
  LDX R_CB                \ (NMOS: CB + 1 by INX, not INC A)
  INX
  STX cb1+1
  LDA R_SN                \ star count (only ever 0 or 19, so <= 24)
  STA sl+1                \ (patched: the loop limit)
  STA nl+1                \ (and its copy at .nl)
  LDX #0                  \ (NMOS: no STZ) no records yet; RZ_PA's low byte
  STX r_k                 \ 0 for the fast path's (RZ_PA),Y
  STX RZ_PA
  DEX
.snext
  INX
.sl
  CPX #0                  \ (R_SN)
  BCS sdone
.sl2
  LDA R_SS,X
  BEQ snext
.some
  STX RZ_TA+1
  STA RZ_TA
  LDY R_SY,X
  LDA R_SX,X
  TAX                     \ fast path: x .. x+1 inside the window, in one byte,
  CPX R_CL                \ the row(s) inside
  BCC slow
  CPX R_CR
  BCS slow
  CPY R_CT                \ (two pixels split across bytes, x AND 3 = 3 with
  BCC slow                \ size >= 2: caught by the mask being 0 at .two)
.cb1
  CPY #0                  \ (CB + 1)
  BCS slow
  LDA RZ_TA
  LSR A                   \ size 1..3: C = 0 for 2; else A = 0 for 1, 1 for 3
  BCC two2                \ (size 2)
  BEQ one                 \ size 1: one pixel; 2, 3: two
  CPY R_CB                \ size 3: the second row inside too? (y + 1 <= CB)
  BCS slow
.two2
  LDA r_lm,X
  AND r_rm+1,X            \ two pixels: 0 only when split across bytes
  BEQ slow                \ (x AND 3 = 3: r_lm = &11, r_rm(x+1) = &88)
.msk
  STA RZ_SB               \ the mask
.row
.^r_yp3
  LDA r_ypg,Y             \ NMOS: RZ_PA + Y = byte of (x, y): RZ_PA's high
  CPX #&80                \ byte the page, its low byte 0 and Y the byte's
  ADC #0                  \ low byte
  STA RZ_PA+1
  TYA
  AND #7
  ORA r_xo,X
  TAY
.chk
  LDA (RZ_PA),Y           \ the whole byte black?
  BNE nx
  LDX r_k                 \ (< 48 always: R_SN <= 24, <= 2 records a star)
  LDA R_SCOL
  AND RZ_SB
  STA (RZ_PA),Y
  TYA
.^r_pt414 STA r_s0y,X
  LDA RZ_PA+1
  ORA #&80                \ (bit 7: no second byte)
.^r_pt415 STA r_s0x,X
  LDA RZ_SB
  EOR #&FF
.^r_pt416 STA r_s0a,X
  INC r_k
.nx
  LDA RZ_TA               \ size 3: the next row
  CMP #3
  BEQ third
  LDX RZ_TA+1             \ (snext inlined: INX, then the loop test)
  INX
.nl
  CPX #0                  \ (R_SN)
  BCC sl2
  JMP sdone
.third
  DEC RZ_TA               \ (NMOS: 2, no longer 3; no STZ)
  INY                     \ the next row: the next byte down ...
  TYA
  AND #7
  BNE chk                 \ ... in the same character row, else 8 bytes
  TYA                     \ back (C = 1 from the CMP #3) and two pages on
  SBC #8
  TAY
  INC RZ_PA+1
  INC RZ_PA+1
  BNE chk                 \ (always)
.one
  LDA r_lm,X
  AND r_rm,X
  BNE msk                 \ (always: one pixel)
}

\ one row of a star: row RZ_SA+1, pixel RZ_SA (and RZ_SA+1 if size >= 2).
\ Each of the (one or two) bytes it touches is set only if the whole byte is
\ black; the byte address and inverse masks are recorded.
.r_strow
{
  LDY RZ_SA+1
  CPY R_CT
  BCC o1
  CPY R_CB
  BEQ r1
  BCC r1
.o1
  RTS
.r1
  LDX RZ_SA
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_SB+1
  LDA RZ_TA
  CMP #2
  BCS two
  CPX R_CL                \ one pixel
  BCC o1
  CPX R_CR
  BEQ one
  BCS o1
.one
  LDA r_lm,X
  AND r_rm,X
  BNE mset                \ (always: one pixel)
.two
  CPX R_CL                \ two pixels, both inside: the fast case
  BCC clip
  CPX R_CR
  BCS clip
  TXA
  AND #3
  CMP #3
  BEQ split
  LDA r_lm,X
  AND r_rm+1,X
  BNE mset                \ (always: two pixels in one byte)
.split
  LDA #&88
  STA RZ_SB+1
  LDA #&11
  BNE mset                \ (always)
.clip
  LDA #0                  \ general: pixel by pixel (NMOS: RZ_SB = 0 or the
  CPX R_CL                \ first pixel's mask, stored at c2)
  BCC c2
  CPX R_CR
  BEQ c1
  BCS c2
.c1
  LDA r_lm,X
  AND r_rm,X
.c2
  STA RZ_SB
  INX
  BEQ c4
  CPX R_CL
  BCC c4
  CPX R_CR
  BEQ c3
  BCS c4
.c3
  LDA r_lm,X
  AND r_rm,X
  PHA
  TXA
  AND #3
  BEQ c5
  PLA
  ORA RZ_SB
  STA RZ_SB
  BNE c4                  \ (always: a pixel's mask)
.c5
  PLA
  STA RZ_SB+1
.c4
  LDX RZ_SA
  LDA RZ_SB
  ORA RZ_SB+1
  BNE ms2
  RTS
.ms2
  LDA RZ_SB
.mset
  STA RZ_SB
  TYA                     \ RZ_PP = byte of (X, Y)
  AND #7
  ORA r_xo,X
  STA RZ_PP
.^r_yp4
  LDA r_ypg,Y             \ (NMOS: the page from r_ypg)
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDX r_k                 \ (record slot; X = x is in RZ_SA)
  CPX #48
  BCS o2
  LDA #&FF                \ byte A
  STA RZ_T0
  LDY #0                  \ (NMOS: for (RZ_PP),Y)
  LDA RZ_SB
  BEQ ba
  LDA (RZ_PP),Y           \ (the whole byte black)
  BNE ba
  LDA R_SCOL
  AND RZ_SB
  STA (RZ_PP),Y
  LDA RZ_SB
  EOR #&FF
  STA RZ_T0
.ba
  LDA #&FF                \ byte B (next column)
  LDY RZ_SB+1
  BEQ bb
  LDY #8
  LDA (RZ_PP),Y           \ (the whole byte black)
  BNE bf
  LDA R_SCOL
  AND RZ_SB+1
  STA (RZ_PP),Y
  LDA RZ_SB+1
  EOR #&FF
  BNE bb                  \ (always: a pixel's mask inverted)
.bf
  LDA #&FF
.bb
.^r_pt37 STA r_s0b,X
  AND RZ_T0
  CMP #&FF
  BEQ o2                  \ nothing set
  LDA RZ_PP
.^r_pt34 STA r_s0y,X
  LDA RZ_PP+1
.^r_pt35 STA r_s0x,X
  LDA RZ_T0
.^r_pt36 STA r_s0a,X
  INC r_k
.o2
  RTS
}

\ r_lput2: pixels RZ_SB .. RZ_TA+1 of row RZ_Y in RZ_COL (row pointers set).
\ Clobbers A, X, Y.
.r_lput2
{
  LDA RZ_TA+1
  TAY                     \ Y = last pixel
  LDX RZ_SB               \ X = first
  EOR RZ_SB
  CMP #4
  BCS two
  LDA r_lm,X              \ one byte
  AND r_rm,Y
  STA RZ_T7
  LDY r_xo,X
  CPX #&80
  BCS h1
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND RZ_T7
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.h1
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND RZ_T7
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
.two
  STY R_XR
  TYA                     \ adjacent bytes?
  AND #&FC
  STA RZ_T7
  TXA
  AND #&FC
  ADC #3                  \ (C = 1 from the CMP)
  CMP RZ_T7
  BEQ adj
  JMP long                \ (r_ypg and r_ypg0 sit between here and .long)
.adj
  LDY r_xo,X              \ first byte: from X on
  CPX #&80
  BCS h2
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND r_lm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  BCC s2                  \ (NMOS: C = 0 from the CPX #&80)
.h2
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND r_lm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
.s2
  LDX R_XR                \ second byte: up to the last
  LDY r_xo,X
  CPX #&80
  BCS h3
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.h3
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
.^r_ypg                   \ high byte of row y's byte 0, buffer 1 (SCREEN%)
FOR y, 0, 191
  EQUB &40 + 2 * (y DIV 8)
NEXT
.^r_ypg0                  \ (Model B) the same, buffer 0 (BUF0): R_SETBUF points
FOR y, 0, 191             \ the readers at one or the other
  EQUB HI(BUF0) + 2 * (y DIV 8)
NEXT
.long
  STX R_XL                \ up to 4 bytes: masked ends, whole bytes stored
  TYA                     \ through a byte pointer
  SEC
  SBC R_XL
  CMP #16                 \ (16 pixels or more: the run, 5 cycles a byte and
  BCS span                \ about 90 to set up, against 26 a byte here)
  LDA RZ_PP               \ (RZ_PP holds a planted RTS's address: keep it)
  PHA
  LDA RZ_PP+1
  PHA
  LDA r_xo,X
  ORA RZ_PA
  STA RZ_PP
  LDA RZ_PA+1
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDY #0                  \ (NMOS: the bytes are (RZ_PP),Y, Y = 0, 8, ...)
  LDA RZ_COL              \ first byte: from X on
  EOR (RZ_PP),Y
  AND r_lm,X
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  LDA R_XR                \ whole bytes: last/4 - first/4 - 1
  LSR A
  LSR A
  STA RZ_T7
  TXA
  LSR A
  LSR A
  SEC
  SBC RZ_T7               \ (C = 0: last/4 >= first/4 + 2)
  EOR #&FF
  TAX
  BEQ lb
.wl
  TYA                     \ (C = 0: Y < 32)
  ADC #8
  TAY
  LDA RZ_COL
  STA (RZ_PP),Y
  DEX
  BNE wl
.lb
  TYA                     \ last byte: up to the last pixel
  ADC #8
  TAY
  LDX R_XR
  LDA RZ_COL
  EOR (RZ_PP),Y
  AND r_rm,X
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  PLA
  STA RZ_PP+1
  PLA
  STA RZ_PP
  RTS
.span
  LDY RZ_Y                \ a span (r_rowset for the run page)
  JSR r_rowset
  LDX R_XL
  JMP r_spc
}

.r_end
PRINT "raster.asm: ", r_end - r_start, " bytes from ", ~r_start, " to ", ~r_end

