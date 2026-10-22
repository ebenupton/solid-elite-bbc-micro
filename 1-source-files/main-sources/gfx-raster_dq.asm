\ ******************************************************************************
\
\ gfx-raster_dq.asm - bank R's side of the disc layer (Model B)
\
\ The disc layer (gfx-dlayer.asm, in the flight code's cold bank) cannot see
\ bank R, so it asks for the repair's extents a batch of rows at a time
\ (R_GETW) and has the long spans it queued drawn through the row runs
\ (R_DRAINQ), neither marking anything dirty (the disc stays on its buffer).
\ Both are reached through the trampolines T_GETW and T_DRAINQ.
\
\ ******************************************************************************

\ R_GETW: rows Y .. Y + A - 1 (A >= 1): (R_WL, R_WR) pairs into MBOX; or
\ with A = &80 + n, n spans marked dirty (the disc layer's small discs)

.R_GETW
{
  CMP #&80                \ A = &80 + n: mark n spans at MBOX + &28 (row,
  BCS mark                \ left, right, -) dirty instead
  STA RZ_T0
  LDX #0
.lp
  LDA R_WL,Y
  STA MBOX,X
  LDA R_WR,Y
  STA MBOX+1,X
  INY
  INX
  INX
  DEC RZ_T0
  BNE lp
  RTS
.mark
  AND #&7F
  ASL A
  ASL A
  STA RZ_T0
  LDX #0
.ml
  STX RZ_T1
  LDA MBOX+&29,X
  STA R_XL
  LDA MBOX+&2A,X
  STA R_XR
  LDY MBOX+&28,X
  JSR R_MARKDIRTY
  LDA RZ_T1
  CLC
  ADC #4
  TAX
  CMP RZ_T0
  BCC ml
  RTS
}

\ R_DRAINQ: A spans (A >= 1) at MBOX + &28, four bytes each: row, left
\ pixel, right pixel (left <= right), colour byte; drawn, not marked

.R_DRAINQ
{
  ASL A
  ASL A
  STA RZ_T0
  LDA #0
  STA RZ_T1
.lp
  LDX RZ_T1
  LDA MBOX+&29,X
  STA R_XL
  LDA MBOX+&2A,X
  STA R_XR
  LDA MBOX+&2B,X
  STA RZ_COL
  LDY MBOX+&28,X
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
