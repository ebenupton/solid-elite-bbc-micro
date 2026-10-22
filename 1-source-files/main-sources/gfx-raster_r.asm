\ ******************************************************************************
\
\ gfx-raster_r.asm - bank R's own routines: R_INIT, R_RESETBUF and R_REPAIR
\ (NMOS code, written for bank R; gfx-rws.asm describes the bank)
\
\ Port (Model B): the Master port's R_INIT and R_RESETBUF were in the
\ rasteriser's disc window (gfx-raster_disc.asm), with R_DISCROWS, which bank
\ R does not have; these are the same without the disc layer's state, and
\ R_REPAIR is R_DISCROWS without a disc: the repair of the buffer's dirty
\ rows (r7_crep's case of no disc rows), through r7_rowrep.
\
\ ******************************************************************************

\ ============================================================================
\ R_INIT: once at startup (as the Master port's): clip window 1..254 x
\ 1..191, R_SCOL = &FF, both buffers' state empty, R_SETBUF 0. Does not
\ touch the screen: follow with R_RESETBUF on a black window for each buffer.
\ ============================================================================
.R_INIT
{
  LDA #1
  STA R_CL
  STA R_CT
  LDA #254
  STA R_CR
  LDA #191
  STA R_CB
  LDA #&FF
  STA R_SCOL
  LDA #0
  STA R_SN
  STA R_PN
  LDA #&FF                \ R_SETBUF 0, forcing the patch
  STA r_sbcur
  LDA #0
  JSR R_SETBUF
  LDY #191
.il
  LDA #&FF
  STA R_DIRTYL0,Y
  STA R_DIRTYL1,Y
  STA R_WL,Y
  LDA #0
  STA R_DIRTYR0,Y
  STA R_DIRTYR1,Y
  STA R_WR,Y
  DEY
  CPY #&FF
  BNE il
  LDX #1
.ib
  JSR r_reset1
  DEX
  BPL ib
  LDA #&FF
  STA R_PRWT
  LDA #0
  STA R_PRWB
  RTS
}

\ ============================================================================
\ R_RESETBUF: forget the current buffer's state (no dirty extents, no stars)
\ without touching the screen; the caller guarantees the buffer's clip
\ window is black.
\ ============================================================================
.R_RESETBUF
{
  LDY #191
  LDX R_PRBUF
  BNE b1
.c0
  LDA #&FF
  STA R_DIRTYL0,Y
  LDA #0
  STA R_DIRTYR0,Y
  DEY
  CPY #&FF
  BNE c0
  BEQ r_reset1            \ (X = 0)
.b1
  LDA #&FF
  STA R_DIRTYL1,Y
  LDA #0
  STA R_DIRTYR1,Y
  DEY
  CPY #&FF
  BNE b1
}
\ r_reset1: buffer X's scalars (keeps X)
.r_reset1
  LDA #&FF
  STA R_PRDYT,X
  STA R_PRDST,X
  LDA #0
  STA R_PRDYB,X
  STA R_PRDSB,X
  STA R_PRSCNT,X
  STA R_PRECNT,X
  STA R_PRBMODE,X
  RTS

\ ============================================================================
\ R_REPAIR: the start of a frame on the current buffer, after R_STARERASE
\ (in place of the Master port's R_DISCROWS, with no disc): clear last
\ frame's R_WL/R_WR, then black each dirty row's extent (widened to whole
\ bytes; the border bytes in columns 0 and 63 masked) through the row runs,
\ setting R_WL/R_WR to it and emptying it. Afterwards R_WL/R_WR hold, per
\ row, what the repair wrote (shapes drawn later are in DIRTY, not WL/WR).
\ ============================================================================
                          \ (c_YE: r7_rowrep's end row, gfx-raster_rep.asm)
.R_REPAIR
{
  JSR r_wclear            \ clear last frame's WL/WR rows
  LDA #&FF
  STA R_PRWT
  LDA #0
  STA R_PRWB
  LDX R_PRBUF
  LDA R_PRDYB,X           \ the dirty rows R_PRDYT .. R_PRDYB, if any
  CMP R_PRDYT,X
  BCC none
  STA R_PRWB              \ they become WL/WR's rows
  CLC
  ADC #1
  STA c_YE
  LDA R_PRDYT,X
  STA R_PRWT
  TAY
  JSR r7_rowrep
  LDX R_PRBUF             \ no dirty rows left
  LDA #&FF
  STA R_PRDYT,X
  LDA #0
  STA R_PRDYB,X
.none
  RTS
}

\ ============================================================================
\ r_wclear: R_WR[R_PRWT .. R_PRWB] = 0 (and the rest of their blocks of 8
\ rows, which are 0 already). Clobbers A, X. (The Master port's, NMOS.)
\ ============================================================================
.r_wclear
{
  LDA R_PRWB
  CMP R_PRWT
  BCC none
  ORA #7
  TAX
  LDA R_PRWT
  AND #&F8
  STA lim+1
.lp
  LDA #0
  STA R_WR,X
  STA R_WR-1,X
  STA R_WR-2,X
  STA R_WR-3,X
  STA R_WR-4,X
  STA R_WR-5,X
  STA R_WR-6,X
  STA R_WR-7,X
  TXA
  SEC
  SBC #8
  BCC none
  TAX
.lim
  CMP #0
  BCS lp
.none
  RTS
}

\ ============================================================================
\ R_SPANM: R_SPAN, then R_MARKDIRTY for the same row and ends (RJT's span
\ entry, so the frame layer fills and marks a disc's row in one call; R_XL
\ must be <= R_XR, as the frame layer's discs always are).
\ ============================================================================
.R_SPANM
  JSR R_SPAN
  LDY RZ_Y
  JMP R_MARKDIRTY

\ ============================================================================
\ R_MARKBOX (Model B): R_MARKDIRTY for rows Y .. R_BY1, each by R_XL..R_XR
\ (the lens flare's ghosts, which bank F draws itself: gfx-flare.asm)
\ ============================================================================
.R_MARKBOX
  STY rmb_y
.rmb1
  JSR R_MARKDIRTY
  LDY rmb_y
  CPY R_BY1
  INY
  STY rmb_y
  BCC rmb1
  RTS
.rmb_y EQUB 0
