\ ******************************************************************************
\
\ gfx-raster_dq.asm - bank 5's side of the disc layer (Model B)
\
\ The disc layer's row code (gfx-raster_disc.asm, the painter, in the flight
\ code's bank 7) cannot see bank 5, so the frame layer (bank 6), which hands
\ it its rows a batch at a time in the mailbox (gfx-rws.asm: DB_*), passes
\ what it needs of bank 5 with each batch in one call, R_GETW (T_GETW):
\ the long spans the painter queued for the row runs drawn, what it wrote
\ on the last batch's rows put into this frame's written extents (R_WL,
\ R_WR), and the next batch's dirty extents (which are emptied: the painter
\ repairs them) or written extents (for the second disc, R_DISC2) taken. The
\ frame layer also asks R_GETW, with A = &40, for what its text and sights
\ need of this frame's written and dirty extents (r_wq).
\
\       Area: bank 5
\
\ ******************************************************************************

\ R_GETW: A = &40: the frame layer's query (r_wq). Otherwise, in this order:
\
\   * the DB_QN bytes of spans queued at DB_Q (four each: row, left pixel,
\     right pixel, colour byte) drawn through the row runs (R_DRAINQ), not
\     marked dirty, and DB_QN emptied;
\
\   * X rows (0 to 16) from row DB_PY: DB_WL, DB_WR into R_WL, R_WR, and
\     into the rows of R_WL/R_WR that may be non-empty (R_PRWT .. R_PRWB);
\
\   * A AND &1F rows (0 to 16) from row Y: their dirty extents into DB_WL,
\     DB_WR, and emptied (A bit 7 clear: the disc layer's rows), or (A bit 7
\     set: the second disc's) their written extents.

r_gm = &24              \ (bank 5's zero page, the rasteriser's scratch)
r_gy = &25
r_gx = &26

.R_GETW
{
  CMP #&40
  BNE P%+5
  JMP r_wq
  STA r_gm
  STY r_gy
  STX r_gx
  LDA DB_QN               \ the queue
  BEQ q0
  LSR A
  LSR A
  JSR R_DRAINQ
  LDA #0
  STA DB_QN
.q0
  LDX r_gx                \ the last batch's writes
  BEQ g0
  LDY DB_PY
  CPY R_PRWT
  BCS q1
  STY R_PRWT
.q1
  LDX #0
.pl
  LDA DB_WL,X
  STA R_WL,Y
  LDA DB_WR,X
  STA R_WR,Y
  INY
  INX
  CPX r_gx
  BNE pl
  DEY
  CPY R_PRWB
  BCC g0
  STY R_PRWB
.g0
  LDA r_gm                \ the next batch's extents
  AND #&1F
  BEQ g9
  STA r_gx
  LDY r_gy
  LDX #0
  BIT r_gm
  BMI gw
.gd
.^r_pt601 LDA r_dl,Y              \ (patched: this buffer's)
  STA DB_WL,X
  LDA #&FF
.^r_pt602 STA r_dl,Y
.^r_pt603 LDA r_dr,Y
  STA DB_WR,X
  LDA #0
.^r_pt604 STA r_dr,Y
  INY
  INX
  CPX r_gx
  BNE gd
.g9
  RTS
.gw
  LDA R_WL,Y
  STA DB_WL,X
  LDA R_WR,Y
  STA DB_WR,X
  INY
  INX
  CPX r_gx
  BNE gw
  RTS
}

\ R_DRAINQ: A spans (A >= 1) at DB_Q, four bytes each: row, left pixel, right
\ pixel (left <= right), colour byte; drawn, not marked

.R_DRAINQ
{
  ASL A
  ASL A
  STA RZ_T0
  LDA #0
  STA RZ_T1
.lp
  LDX RZ_T1
  LDA DB_Q+1,X
  STA R_XL
  LDA DB_Q+2,X
  STA R_XR
  LDA DB_Q+3,X
  STA RZ_COL
  LDY DB_Q,X
  JSR r_rowset
  LDX R_XL
  JSR r_spc
  LDA RZ_T1
  CLC
  ADC #4
  STA RZ_T1
  CMP RZ_T0
  BCC lp
  RTS
}

\ ============================================================================
\ r_wq, R_GETW's query for the frame layer, in the room below the per-x tables
\
\       Area: bank 5 gap
\ ============================================================================

\ r_wq (R_GETW with A = &40): for the frame layer's text and sights, what was
\ written on this buffer this frame (R_WL..R_WR: the repair's writes) and
\ what is to be repaired next time (its dirty extents: this frame's shapes).
\ Inputs: MBOX+&30..&32, a mask of text rows (bit r AND 7 of byte r DIV 8 for
\ row r = 0..23); MBOX+&33 non-zero to look at the sights. Outputs: for each
\ text row r in the mask, MBOX + 2r and + 2r + 1 = the leftmost and
\ rightmost pixel of the union of both extents over its lines 8r..8r+7 (the
\ rightmost 0: none); MBOX+&34 bit 7 set if the sights are covered: on row 96,
\ an extent meeting x = 108..148, or on rows 76..116 one containing x = 128

QSGX = 128
QSGY = 96
QSGIN = 20

.r_wq
{
  LDA #HI(R_DIRTYL0)      \ this buffer's dirty extents (buffer 1's are &300 on)
  LDX R_PRBUF
  BEQ P%+4
  LDA #HI(R_DIRTYL1)
  STA dl1+2
  STA dl2+2
  STA sl1+2
  CLC
  ADC #HI(R_DIRTYR0) - HI(R_DIRTYL0)
  STA dr1+2
  STA dr2+2
  STA sr1+2
  LDA #0
  STA MBOX+&34
  LDX #23                 \ the text rows, 23 down to 0
.row
  TXA
  LSR A
  LSR A
  LSR A
  TAY
  TXA
  AND #7
  STX RZ_T2
  TAX
  LDA MBOX+&30,Y
  AND bits,X
  BEQ next
  LDA #255                \ the union over the row's eight lines
  STA RZ_T0
  LDA #0
  STA RZ_T1
  LDA RZ_T2
  ASL A
  ASL A
  ASL A
  TAY
  ADC #8                  \ (C = 0: 8 * 23 + 8 < 256)
  STA RZ_T3
.line
  LDA R_WR,Y
  BEQ ln2
  CMP RZ_T1
  BCC P%+4
  STA RZ_T1
  LDA R_WL,Y
  CMP RZ_T0
  BCS ln2
  STA RZ_T0
.ln2
.dr1
  LDA R_DIRTYR0,Y         \ (patched: this buffer's)
  BEQ ln3
  CMP RZ_T1
  BCC P%+4
  STA RZ_T1
.dl1
  LDA R_DIRTYL0,Y         \ (patched)
  CMP RZ_T0
  BCS ln3
  STA RZ_T0
.ln3
  INY
  CPY RZ_T3
  BCC line
  LDA RZ_T2
  ASL A
  TAX
  LDA RZ_T0
  STA MBOX,X
  LDA RZ_T1
  STA MBOX+1,X
.next
  LDX RZ_T2
  DEX
  BPL row
  LDA MBOX+&33            \ the sights
  BEQ done
  LDY #QSGY               \ row 96: an extent meeting 108..148
  LDA R_WR,Y
  BEQ s2
  CMP #QSGX-QSGIN
  BCC s2
  LDA R_WL,Y
  CMP #QSGX+QSGIN+1
  BCC hit
.s2
.dr2
  LDA R_DIRTYR0,Y         \ (patched)
  BEQ s3
  CMP #QSGX-QSGIN
  BCC s3
.dl2
  LDA R_DIRTYL0,Y         \ (patched)
  CMP #QSGX+QSGIN+1
  BCC hit
.s3
  LDY #QSGY-QSGIN         \ rows 76..116: an extent containing 128
.col
  LDA R_WR,Y              \ (WR >= 128: bit 7; then WL <= 128)
  BPL c2
  LDA R_WL,Y
  CMP #QSGX+1
  BCC hit
.c2
.sr1
  LDA R_DIRTYR0,Y         \ (patched)
  BPL c3
.sl1
  LDA R_DIRTYL0,Y         \ (patched)
  CMP #QSGX+1
  BCC hit
.c3
  INY
  CPY #QSGY+QSGIN+1
  BCC col
.done
  RTS
.hit
  LDA #&80
  STA MBOX+&34
  RTS
.bits EQUB 1, 2, 4, 8, 16, 32, 64, 128
}
