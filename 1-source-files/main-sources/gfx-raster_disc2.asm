\ ******************************************************************************
\
\ gfx-raster_disc2.asm - the second disc (R_DISC2), in the flight code's bank
\ 7 with the disc layer's painter (gfx-raster_disc.asm)
\
\ Port (Model B): the BBC Master port's R_DISC2 (its bank 5's, in the
\ hand-converted NMOS 6502 code of its Model B branch). The second disc is
\ the smaller of the sun and the planet when both are on the screen (the
\ frame layer's f_disc2), drawn behind the disc layer, incrementally. The
\ frame layer does what R_DISC2 did once a frame (the rows, old and new:
\ R_S2T, R_S2B; the colour, R_S2C, whose change it passes in A, and a
\ buffer reset since, which DP_BEGIN's PB_RESET passes) and hands its rows to
\ DP_DISC2 a batch at a time, as it does the layer's (DP_ROWS): each slot's
\ new span (DB_NL, DB_NR: the second disc's, clamped to the window as for
\ the layer, empty on the old rows outside the new) and what was written on
\ the row so far this frame (DB_WL, DB_WR, from bank 5's R_WL, R_WR), which
\ comes back with this disc's writes added.
\
\ The disc layer (this buffer's R_DISCL/R, as DP_ROWS has just left them) is
\ in front of it: row y of the second disc shows its span a..b less the
\ layer's L..R, up to two pieces (the original's sun line heap keeps each
\ row's span the same way).
\
\ Each buffer remembers its rows' spans a..b (R_S2L/R) as drawn. What this
\ frame has written on a row (R_WL..R_WR: the layer's writes and the dirty
\ repair) is all that can have happened to the old pieces there since: the
\ shapes drawn over them were in the dirty extents, the layer's old span L0
\ never held them, and wherever the layer moved off (L0 less the new L) it
\ wrote black.  So on each row, with the old span a0..b0 and the new a1..b1,
\ less the layer's span each time:
\
\   * the same span and nothing written over it: nothing to do (a few
\     compares);
\   * the same span, written over: max(a, WL) .. min(b, WR) drawn again;
\   * the spans overlap: the ends that shrank black, the ends that grew in
\     the disc's colour; if this frame also wrote over the new span, one span
\     over the grown ends and that part instead (pixels between them that
\     are still the disc's are written again, harmlessly);
\   * apart, or one of them empty, or the colour changed (the sun and the
\     planet swapped which is the bigger, so this disc is the other one now):
\     the old span black, then the new span whole.
\   * both spans empty or behind the layer: nothing.
\
\ The writes are masked to their pixels (r_sw, never queued: they may
\ overlap) and added to the row's written extent, so the text and the
\ sights see them as written, as they see the disc layer's; nothing goes
\ into DIRTY, so the next frame on this buffer does not repair them.
\
\ ******************************************************************************

 CPU 0                  \ NMOS 6502: no 65C02 instructions in this file

d_a1 = &20              \ the row: new span a1..b1, old a0..b0, the layer's
d_b1 = &21              \ L..R (no layer: L = R = 255), in zero page that
d_a0 = &24              \ r_sw does not use
d_b0 = &25
d_L  = &1D
d_R  = &1F
d_p  = &26              \ d2put's first pixel
d_q  = &1A
d_mn = &23              \ this row's writes: pixels d_mn .. d_mx (none: d_mx = 0)
d_mx = &1E

\ DP_DISC2: Y = the first row, X = the rows (1 to 16), A = &FF if its colour
\ changed (d_fl), else 0: the second disc's batch (gfx-raster_disc.asm's
\ DP_ROWS, for the layer)

.DP_DISC2
{
  STA d_fl
  STX dp_n
  TYA
  TAX
  LDY #0
  STY r_qok               \ (its writes are never queued)
.lp                       \ unchanged and not written over: a few compares
  LDA DB_NL,Y
.^r_p2l22 CMP R_S2L0,X
  BNE ch
  LDA DB_NR,Y
.^r_p2r22 CMP R_S2R0,X
  BNE ch
  LDA DB_WR,Y
  ORA d_fl
  BNE wo
.nx
  INX
  INY
  CPY dp_n
  BNE lp
  RTS
.ch                       \ changed (or recoloured): nothing to draw if both
  LDA DB_NL,Y             \ spans are empty or behind the layer (an empty
.^r_psl40 CMP R_DISCL0,X  \ span, 255 .. 0, is); just remember the new one
  BCC cr
.^r_psr40 LDA R_DISCR0,X
  CMP DB_NR,Y
  BCC cr
.^r_p2l23 LDA R_S2L0,X
.^r_psl41 CMP R_DISCL0,X
  BCC cr
.^r_psr41 LDA R_DISCR0,X
.^r_p2r23 CMP R_S2R0,X
  BCC cr
  LDA DB_NL,Y
.^r_p2l24 STA R_S2L0,X
  LDA DB_NR,Y
.^r_p2r24 STA R_S2R0,X
  BCS nx                  \ (always: C set by the last CMP)
.cr
  JSR d2ld
  JSR row
  JSR dp_st
  JMP nx                  \ (NMOS: no BRA)
.wo                       \ recoloured: every row
  BIT d_fl
  BMI ch
  LDA DB_NL,Y             \ unchanged, written over this frame: nothing if
.^r_psl42 CMP R_DISCL0,X  \ the span is behind the layer (or empty), else
  BCC w0                  \ max(a, WL) .. min(b, WR), if any, drawn again
.^r_psr42 LDA R_DISCR0,X
  CMP DB_NR,Y
  BCS nx
.w0
  JSR d2ld
  LDA rw_r
  CMP rn_r
  BCC w1
  LDA rn_r
.w1
  STA d_b1
  LDA rw_l
  CMP rn_l
  BCS w2
  LDA rn_l
.w2
  CMP d_b1
  BEQ w3
  BCS w5
.w3
  STA d_a1
  JSR lay
  LDA d_a1                \ (all of it behind the layer: nothing)
  CMP d_L
  BCC w4
  LDA d_R
  CMP d_b1
  BCS w5
.w4
  JSR d2set
  LDA d_a1
  LDX d_b1
  JSR d2put
  JSR d2fin
.w5
  JSR dp_st
  JMP nx

.all
  STX d_c                 \ the old span black (none if empty) ... (X = 0:
                          \ d2set)
  LDA d_a0
  LDX d_b0
  JSR d2put
  LDA d_cs                \ ... then the new span whole
  STA d_c
  LDA d_a1
  LDX d_b1
  JMP wn


.row                      \ row X (= d_y): changed or recoloured, and some of
                          \ it in front of the layer
.^r_p2l25 LDY R_S2L0,X    \ the old span
  STY d_a0
.^r_p2r25 LDY R_S2R0,X
  STY d_b0
  LDA rn_l                \ the new one, remembered
  STA d_a1
.^r_p2l26 STA R_S2L0,X
  LDA rn_r
  STA d_b1
.^r_p2r26 STA R_S2R0,X
  JSR lay
.go
  JSR d2set
  BIT d_fl                \ recoloured, an empty span or the spans apart: all
  BMI all
  LDA d_b1
  CMP d_a1
  BCC all                 \ the new span empty
  LDA d_b0
  CMP d_a0
  BCC all                 \ the old one empty
  CMP d_a1
  BCC all                 \ b0 < a1
  LDA d_b1
  CMP d_a0
  BCC all                 \ b1 < a0
  LDY d_L                 \ the spans overlap: with no layer on the row and
  INY                     \ nothing written over it (the commonest case), the
  BNE gn                  \ ends' strips straight through r_sw (NMOS: Y, as
  LDA rw_r                \ there is no INC A, and so X = 0 still at .gn)
  BNE gn
  LDA d_a1                \ the left end: a0 .. a1-1 black, or a1 .. a0-1 in
  CMP d_a0                \ the disc's colour
  BEQ q2
  BCC q1
  TAY
  DEY
  LDX d_a0
  LDA #0
  BEQ q3                  \ (always)
.q1
  TAX
  LDY d_a0
  DEY
  LDA d_cs
.q3
  STX d_mn
  STY d_mx
  JSR r_sw
.q2
  LDA d_b1                \ the right end: b0+1 .. b1 in the disc's colour, or
  CMP d_b0                \ b1+1 .. b0 black
  BEQ q6
  BCC q4
  TAY
  LDX d_b0
  INX
  LDA d_cs
  BCS q5                  \ (always: C set by the CMP)
.q4
  TAX
  INX
  LDY d_b0
  LDA #0
.q5
  STY d_mx
  CPX d_mn
  BCS q7
  STX d_mn
.q7
  JSR r_sw
.q6
  LDA d_mn                \ (nothing was written on this row: rw_r was 0)
  STA rw_l
  LDA d_mx
  STA rw_r
  RTS
.gn
  STX d_c                 \ else the ends that shrank, black, through d2put
  LDA d_a1                \ (X = 0: d2set)
  CMP d_a0
  BEQ b2
  BCC b2
  TAX                     \ a0 .. a1-1
  DEX
  LDA d_a0
  JSR d2put
.b2
  LDA d_b0
  CMP d_b1
  BEQ b3
  BCC b3
  TAX                     \ b1+1 .. b0
  LDA d_b1
  ADC #0                  \ (C set: + 1)
  JSR d2put
.b3
  LDA d_cs                \ then the ends that grew, in the disc's colour
  STA d_c
  LDA rw_r                \ (written over too: max(a1, WL) .. min(b1, WR),
  BEQ h0                  \ if not empty, and they as one span)
  CMP d_b1
  BCC g4
  LDA d_b1
.g4
  STA d_t
  LDA rw_l
  CMP d_a1
  BCS g5
  LDA d_a1
.g5
  CMP d_t
  BEQ g6
  BCC g6
.h0
  LDA d_a1                \ the left end, a1 .. a0-1, if it grew
  CMP d_a0
  BCS h1
  LDX d_a0
  DEX
  JSR d2put
.h1
  LDA d_b0                \ the right, b0+1 .. b1
  CMP d_b1
  BCS h2
  ADC #1                  \ (C clear)
  LDX d_b1
  JSR d2put
.h2
  JMP d2fin
.g6
  STA d_p                 \ max(a1, WL) .. min(b1, WR) (d_p .. d_t), widened
  LDA d_a1                \ over the ends that grew: the left, a1 .. a0-1 ...
  CMP d_a0
  BCS g7
  STA d_p
  LDX d_a0
  DEX
  CPX d_t
  BCC g7
  STX d_t
.g7
  LDA d_b0                \ ... and the right, b0+1 .. b1
  CMP d_b1
  BCS g9
  ADC #1                  \ (C clear)
  CMP d_p
  BCS g8
  STA d_p
.g8
  LDA d_b1
  STA d_t
.g9
  LDA d_p
  LDX d_t
.wn
  JSR d2put               \ (NMOS: then into d2fin, which follows for that)
}

\ d2fin: the row's writes (d_mn .. d_mx) added to its written extent (rw_l,
\ rw_r)
.d2fin
{
  LDA d_mx
  BEQ f9                  \ (none)
  LDY rw_r
  BNE f1
  DEY                     \ (none written yet: no left end)
  STY rw_l
.f1
  CMP rw_r
  BCC f2
  STA rw_r
.f2
  LDA d_mn
  CMP rw_l
  BCS f9
  STA rw_l
.f9
  RTS
}

\ d2ld: slot Y's new span and written extent into the row's variables (rn_l,
\ rn_r, rw_l, rw_r), and d_y = X, the row (keeps X and Y)
.d2ld
  STY dp_s
  STX dp_x
  STX d_y
  LDA DB_NL,Y
  STA rn_l
  LDA DB_NR,Y
  STA rn_r
  LDA DB_WL,Y
  STA rw_l
  LDA DB_WR,Y
  STA rw_r
  RTS

\ lay: the layer's span on row X: d_L .. d_R (none: R = 255 too, so that a
\ piece is never right of it).  Keeps X.
.lay
{
.^r_psr43 LDA R_DISCR0,X  \ (NMOS: L in Y, as there is no INC A)
.^r_psl43 LDY R_DISCL0,X
  STY d_L
  INY
  BNE l1
  LDA #&FF
.l1
  STA d_R
  RTS
}

\ d2set: row d_y about to be written: its pointers (r_rowp), the disc's
\ colour on it (d_cs), no writes yet (d_mn .. d_mx)
.d2set
{
  LDX d_y
  JSR r_rowp
  TXA
  LSR A
  LDA R_COLE
  BCC s2
  LDA R_COLO
.s2
  STA d_cs
  STA d_c
  LDX #&FF                \ (NMOS: X, for a 0; returns X = 0)
  STX d_mn
  INX
  STX d_mx
  RTS
}

\ d2put: pixels A .. X (none if A > X) less the layer's span d_L .. d_R, in
\ colour d_c, on the row d2set set up; noted in d_mn .. d_mx.  Clobbers A,
\ X, Y and what r_sw does.
.d2put
{
  STA d_p
  STX d_q
  CPX d_p
  BCC x9                  \ X < A: none
  LDY d_L                 \ no layer on the row: all of it
  INY
  BEQ wr
  CMP d_L
  BCS rt                  \ A >= L: nothing left of the layer
  LDX d_L                 \ left of it: A .. min(X, L - 1)
  DEX
  CPX d_q
  BCC l1
  LDX d_q
.l1
  JSR wr
.rt
  LDA d_R                 \ right of it: max(A, R + 1) .. X, if X > R
  CMP d_q
  BCS x9
  ADC #1                  \ (C clear)
  CMP d_p
  BCS r1
  LDA d_p
.r1
  LDX d_q
.wr                       \ pixels A .. X (A <= X)
  CMP d_mn
  BCS w1
  STA d_mn
.w1
  CPX d_mx
  BCC w2
  STX d_mx
.w2
  STX R_XR                \ (r_sw: pixels X .. Y)
  TAX
  LDY R_XR
  LDA d_c
  JMP r_sw
.x9
  RTS
}

.d_c    EQUB 0          \ the colour d2put writes in
.d_cs   EQUB 0          \ this row's disc colour (R_COLE / R_COLO)
.d_y    EQUB 0          \ the row
.d_fl   EQUB 0          \ &FF: the colour changed (every row old black, new whole)
.d_t    EQUB 0
