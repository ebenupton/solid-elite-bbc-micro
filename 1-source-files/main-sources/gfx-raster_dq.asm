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
