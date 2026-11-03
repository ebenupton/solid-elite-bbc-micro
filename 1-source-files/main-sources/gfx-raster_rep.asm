\ ============================================================================
\ raster_rep.asm -- bank 5's repair and its other Model B entries: R_REPAIR,
\ r7_rowrep, r_wclear, R_SPANM and R_MARKBOX (NMOS 6502).
\
\ Model B: the BBC Master port repairs a buffer's dirty rows in R_DISCROWS
\ (its disc window: r7_crep for the rows that are no disc rows, then the
\ disc rows in the row loop).  Here the disc layer is not in bank 5, and
\ R_REPAIR repairs every dirty row of the buffer, as r7_crep repairs a row
\ that is no disc row: each row's extent, widened to whole bytes, blacked
\ by one run through the row runs (the border bytes in columns 0 and 63
\ masked), its R_WL/R_WR set to that and its DIRTY emptied.  Afterwards
\ R_WL/R_WR hold, per row, what the repair wrote (shapes drawn later are in
\ DIRTY, not R_WL/R_WR).
\ ============================================================================

c_L   = &18                 \ r7_rowrep's zero page (the rasteriser's scratch)
c_R   = &19
c_NL  = &1A
c_YE  = &1E
c_M   = &23
c_CO  = &22

\ ============================================================================
\ R_REPAIR: the start of a frame on the current buffer, after R_STARERASE:
\ clear last frame's R_WL/R_WR, then repair the buffer's dirty rows
\ ============================================================================
.R_REPAIR
{
  JSR r_wclear            \ clear last frame's WL/WR rows
  LDA #&FF
  STA R_PRWT
  LDX R_PRBUF
  LDA R_PRDYB,X           \ the dirty rows R_PRDYT .. R_PRDYB, if any
  CMP R_PRDYT,X
  BCC none
  STA R_PRWB              \ they become WL/WR's rows
  ADC #0                  \ (C = 1 from the CMP: + 1)
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
  RTS
.none
  LDA #0
  STA R_PRWB
  RTS
}

\ ============================================================================
\ r7_rowrep: rows Y .. c_YE - 1, each with a dirty extent blacked through its
\ row run (the BBC Master port's, made NMOS, and for the Model B's two
\ buffers: the run page checked for this buffer, r_pgfix, and the border
\ bytes' screen page from the buffer's row pages)
\ ============================================================================
.r7_rowrep
{
  LDX R_PRBUF
  LDA dlh,X
  STA ld1+2
  STA sd1+2
  STA fl1+2
  STA fs1+2
  LDA drh,X
  STA ld2+2
  STA sd2+2
  STA fl2+2
  STA fs2+2
.frow                     \ fast path: extent inside columns 1..62
.fl2
  LDA R_DIRTYR0,Y
  BEQ fnx
  CMP #252
  BCS slow
  TAX                     \ X = R
  ORA #3
  STA R_WR,Y
.fl1
  LDA R_DIRTYL0,Y
  AND #&FC                \ L AND &FC = 0 <=> L < 4
  BEQ slow
  STA R_WL,Y
  STX c_R                 \ (R)
  TAX
  LDA r_j-4,X             \ enter at column L DIV 4
  STA fj+1
  LDX c_R                 \ plant the RTS after column R DIV 4 (X: its
  LDA r_j,X               \ offset, which the run keeps)
  TAX
  LDA #&FF
.fs1
  STA R_DIRTYL0,Y
  TYA                     \ the run page of row Y
  LSR A
  LSR A
  LSR A
  ORA #HI(r_run0)         \ (= ADC: Y DIV 8 < 32)
  STA fj+2
  STA fpl+2
  STA fpr+2
  JSR r_pgfix             \ (Model B: its stores for this buffer; keeps X, Y)
  LDA #r_opRTS
.fpl
  STA &FF00,X             \ (the run page)
  LDA #0
.fs2
  STA R_DIRTYR0,Y
.fj
  JSR &FFFF               \ patched: straight into the row run (the run keeps
  LDA #r_opSTA            \ X and Y)
.fpr
  STA &FF00,X             \ (the run page)
.fnx
  INY
  CPY c_YE
  BCC frow
  RTS
.slow                     \ an end in column 0 or 63: the general row code
  JSR row1
  JMP fnx

\ row1: row Y, general (the border columns' bytes masked)
.row1
.ld2
  LDA R_DIRTYR0,Y
  STA c_R
  ORA #3
  STA R_WR,Y
.ld1
  LDX R_DIRTYL0,Y
  STX c_L
  TXA
  AND #&FC
  STA R_WL,Y
  LDA #&FF
.sd1
  STA R_DIRTYL0,Y
  LDA #0
.sd2
  STA R_DIRTYR0,Y
  TXA                     \ first byte column (0: the border's)
  LSR A
  LSR A
  BEQ e0
.nl1
  STA c_NL
  LDA c_R                 \ last byte column (63: the border's)
  LSR A
  LSR A
  CMP #63
  BEQ e63
.nr1                      \ (A = the last column, C = 0 or 1)
  CMP c_NL
  BCC nx                  \ (NR = last + 1 <= NL: no whole byte)
  ADC #0                  \ NR = the last column + 1 (C = 1 here: CMP)
  ASL A                   \ plant the RTS at column NR (r_jm at 4 NR: 3 (NR - 1))
  ASL A
  TAX
  LDA r_jm,X
  STA r1p+1               \ (its offset)
  TYA                     \ the run page of row Y
  LSR A
  LSR A
  LSR A
  ORA #HI(r_run0)         \ (= ADC: Y DIV 8 < 32)
  STA rj+2
  STA rpl+2
  STA rpr+2
  JSR r_pgfix             \ (Model B: its stores for this buffer; keeps X, Y)
  LDA c_NL
  ASL A
  ASL A
  TAX
  LDA r_jm,X
  STA rj+1
.r1p
  LDX #0                  \ (the plant's offset)
  LDA #r_opRTS
.rpl
  STA &FF00,X
  LDA #0
  JSR rj
  LDA #r_opSTA
.rpr
  STA &FF00,X
.nx
  RTS
.rj
  JMP &FFFF
.e0
  STY RZ_Y
  JSR edge0
  LDY RZ_Y
  LDA #1
  BNE nl1                 \ (always)
.e63
  STY RZ_Y
  JSR edge63
  LDY RZ_Y
  LDA #62
  BNE nr1                 \ (always)
\ edge0 / edge63: black pixels c_L .. c_R of row RZ_Y within column 0 / 63
.edge0
  LDX c_R
  CPX #4
  BCC e0a
  LDX #3
.e0a
  LDA r_rm,X
  LDX c_L
  AND r_lm,X
  LDX #0
  BEQ eg                  \ (always)
.edge63
  LDA c_L
  CMP #252
  BCS e6a
  LDA #252
.e6a
  AND #3
  TAX
  LDA c_R                 \ (>= 252)
  AND #3
  TAY
  LDA r_lm,X
  AND r_rm,Y
  LDX #&F8
.eg
  EOR #&FF
  STA c_M
  STX c_CO
  LDY RZ_Y
  TYA
  AND #7
  ORA c_CO
  STA RZ_PA
.^r_yp6
  LDA r_ypg,Y             \ (Model B: the buffer's row page, R_SETBUF's)
  CPX #0
  BEQ eg1
  ORA #1                  \ (column 63: the page's second half; the page is
.eg1                      \ even)
  STA RZ_PA+1
  LDY #0
  LDA (RZ_PA),Y
  AND c_M
  STA (RZ_PA),Y
  RTS
.dlh EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.drh EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
}

\ ============================================================================
\ r_wclear: R_WR[R_PRWT .. R_PRWB] = 0, in blocks of 8 rows from (R_PRWB OR 7)
\ down to (R_PRWT AND &F8): the rows of those blocks outside R_PRWT..R_PRWB
\ are 0 already.  Clobbers A, X.
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
\ R_SPANM (Model B): R_SPAN, then R_MARKDIRTY for the same row and ends (so
\ the frame layer fills and marks a row in one call; R_XL <= R_XR)
\ ============================================================================
.R_SPANM
  JSR R_SPAN
  LDY RZ_Y
  JMP R_MARKDIRTY

\ ============================================================================
\ R_MARKBOX (Model B): R_MARKDIRTY for rows Y .. R_BY1, each by R_XL..R_XR
\ (the lens flare's ghosts, which bank 6 draws itself)
\ ============================================================================
.R_MARKBOX
{
  STY rmb_y
.lp
  JSR R_MARKDIRTY
  LDY rmb_y
  CPY R_BY1
  INY
  STY rmb_y
  BCC lp
  RTS
.rmb_y EQUB 0
}
