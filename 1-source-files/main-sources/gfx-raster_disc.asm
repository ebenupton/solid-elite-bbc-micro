\ ******************************************************************************
\
\ gfx-raster_disc.asm - the disc layer's painter (docs/renderer.md, "The disc
\ layer"), in the flight code's bank 7 (the renderer's window: WIN7%,
\ gfx-window7.asm)
\
\ Port (Model B): the BBC Master port's R_DISCROWS (its bank 5's disc window,
\ gfx-raster_disc.asm, in the hand-converted NMOS 6502 code of its Model B
\ branch), the row code of the incremental disc layer: each buffer keeps the
\ disc's span on each row (R_DISCL/R) and its boundaries, up to three (R_BDN,
\ R_BDX0-2), and each frame writes only what changed. The frame layer (bank
\ 6) makes the rows (f_discs: the new spans, R_NDISCL/R, and the planet's
\ boundaries, R_NDN, R_NDX0-3, from PC_ROWS) and drives this a batch of rows
\ at a time through the mailbox (gfx-rws.asm: DB_*), with the rows' dirty
\ extents from bank 5 (R_GETW), as bank 5's repair leaves them to the disc
\ layer (R_REPAIR: the rows of the band, the old disc's and the new one's):
\
\   * DP_BEGIN (A = the buffer, X = the frame's flags, PB_*): the buffer's
\     arrays into the code's operands (as the Master port's R_SETBUF and
\     r_dbm patch them), and what the frame changes (a blanked buffer's
\     state forgotten, boundaries kept or not, a colour change);
\
\   * DP_ROWS (Y = the first row, X = the rows in the batch): the layer's
\     rows (one colour: r_dlb; with boundaries: r_dmb), with the batch's
\     slot in Y and the row in X (the Master port's code has the row in X
\     for both); a row that changed or is dirty has its slot's new data
\     taken into variables (dp_ld: rn_l, rn_r, rn_n, rn_x0-3, its dirty
\     extent rd_l, rd_r) and what it wrote put back (dp_st: rw_l, rw_r into
\     the slot's DB_WL, DB_WR, which bank 5 then puts into R_WL, R_WR);
\
\   * DP_DISC2: the second disc (gfx-raster_disc2.asm).
\
\ The screen is main RAM, so this writes it itself: a row's address worked
\ out (r_rowp), the pixels' byte offsets and masks from four-byte tables
\ (r_sw). A span of 16 whole bytes or more is queued in the mailbox for bank
\ 5's row runs (r_sq), which bank 5 draws at the next batch's R_GETW, while
\ there is room: the layer's writes on a row never overlap, so the order is
\ the pixels' own.
\
\ Not here: the kept solid rows (k_kill), and the repair of the dirty rows
\ outside the band (bank 5's R_REPAIR).
\
\ ******************************************************************************

 CPU 0                  \ NMOS 6502: no 65C02 instructions in this file

R_COLE  = &06           \ the rasteriser's zero page (gfx-raster.asm), which
R_COLO  = &07           \ F_FRAME keeps: the frame layer's inputs ...
R_XL    = &08
R_XR    = &09
R_CL    = &0A
R_CR    = &0B
R_CT    = &0C
R_CB    = &0D
R_DCE   = &0E
R_DCO   = &0F
RZ_PA   = &10           \ ... and this code's scratch (lo = y AND 7, hi = row
RZ_PB   = &12           \ page) bytes of columns 0..31, then 32..63
RZ_PP   = &14
RZ_COL  = &16           \ this row's colour byte
RZ_Y    = &17           \ current row
RZ_SA   = &18
RZ_TA   = &1A
RZ_SB   = &1C
RZ_T0   = &20
RZ_T1   = &21
RZ_T2   = &22
RZ_T3   = &23
RZ_T4   = &24
RZ_T5   = &25
RZ_T6   = &26
RZ_T7   = &27
rs_t0 = RZ_T0           \ raster_strips.asm: the boundaries, old, then new
rs_t1 = RZ_T1
rs_t2 = RZ_T2
rs_t3 = RZ_T3
rs_t4 = RZ_T4
rs_t5 = RZ_T5

\ DP_BEGIN's flags (X), from the frame layer's f_discs

PB_BON   = 1            \ this frame's layer has boundaries (or this buffer's
                        \ rows had them): r_dmb, and R_NDN's zero rows
PB_FOLD  = 2            \ the layer's colour changed: the old disc is dirty
PB_BCLR  = &40          \ no boundaries kept on this buffer's rows (r_dbm's
                        \ switch from plain rows)
PB_RESET = &80          \ the buffer was blanked: its disc state forgotten

\ ******************************************************************************
\
\ DP_BEGIN: A = the buffer, X = the flags (PB_*), RZ_T0 and RZ_T1 the
\ colour B pair (R_DBE, R_DBO). PB_RESET forgets the second disc's spans
\ too (as R_RESETBUF and R_DISC2's colour 0 do in the Master port)
\
\ ******************************************************************************

.DP_BEGIN
{
  STA dp_buf
  STX dp_fl
  LDA RZ_T0
  STA R_DBE
  LDA RZ_T1
  STA R_DBO
  LDX dp_buf
  JSR dp_patch            \ the buffer's arrays into the operands
  LDA dp_fl
  AND #PB_BON
  STA r_bon
  LDY #191
  BIT dp_fl               \ a blanked buffer: no spans, no boundaries (as the
  BPL b2                  \ Master port's R_RESETBUF)
.b1
  LDA #&FF
.^r_psl20 STA R_DISCL0,Y
.^r_p2l20 STA R_S2L0,Y
  LDA #0
.^r_psr20 STA R_DISCR0,Y
.^r_p2r20 STA R_S2R0,Y
.^r_pbn20 STA R_BDN0,Y
  DEY
  CPY #&FF
  BNE b1
  BEQ b5                  \ (always)
.b2
  BVC b5                  \ plain last time: its rows had no boundaries
  LDA #0                  \ (every row: a row with no old span has none,
.b3                       \ which r_dpe relies on)
.^r_pbn21 STA R_BDN0,Y
  DEY
  CPY #&FF
  BNE b3
.b5
  RTS
}

\ ******************************************************************************
\
\ DP_ROWS: Y = the first row, X = the rows (1 to DB_N): the layer's batch
\
\ ******************************************************************************

.DP_ROWS
{
  STX dp_n
  STY dp_y0
  LDA #&80                \ (the layer's long spans may be queued)
  STA r_qok
  LDA dp_fl               \ the colour changed: nothing of the old disc is
  AND #PB_FOLD            \ intact, so its span is folded into each row's
  BEQ f9                  \ dirty extent (the Master port's f_discdirty)
  TYA
  TAX
  LDY #0
.f1
.^r_psl21 LDA R_DISCL0,X
  CMP DB_WL,Y
  BCS f2
  STA DB_WL,Y
.f2
.^r_psr21 LDA R_DISCR0,X
  CMP DB_WR,Y
  BCC f3
  STA DB_WR,Y
.f3
  INX
  INY
  CPY dp_n
  BNE f1
  LDY dp_y0
.f9
  TYA
  TAX
  LDY #0
  LDA r_bon
  BEQ r_dlb
  JMP r_dmb
}

\ dp_ld: slot Y's data into the row's variables (keeps X and Y); dp_ldp:
\ without the boundaries; dp_st: what the row wrote into its slot, and X =
\ the row, Y = the slot back

.dp_ld
  LDA DB_NN,Y
  STA rn_n
  LDA DB_X0,Y
  STA rn_x0
  LDA DB_X1,Y
  STA rn_x1
  LDA DB_X2,Y
  STA rn_x2
  LDA DB_X3,Y
  STA rn_x3
.dp_ldp
  STY dp_s
  STX dp_x
  LDA DB_NL,Y
  STA rn_l
  LDA DB_NR,Y
  STA rn_r
  LDA DB_WL,Y
  STA rd_l
  LDA DB_WR,Y
  STA rd_r
  LDA #0                  \ (nothing written yet)
  STA rw_r
  RTS

.dp_st
  LDY dp_s
  LDA rw_l
  STA DB_WL,Y
  LDA rw_r
  STA DB_WR,Y
  LDX dp_x
  RTS

\ ============================================================================
\ r_dlb: one-colour rows X on, slots Y = 0 to dp_n - 1 (any dirty)
\ ============================================================================
.r_dlb
{
.lp
  LDA DB_WL,Y             \ (a dirty extent's left end is not 255)
  CMP #&FF
  BNE gd
  LDA DB_NL,Y
.^r_psl22 CMP R_DISCL0,X
  BNE ch
  LDA DB_NR,Y
.^r_psr22 CMP R_DISCR0,X
  BNE ch
.nx
  INX
  INY
  CPY dp_n
  BNE lp
  RTS
.ch
  JSR dp_ldp
  JSR r_dp2               \ (returns X = RZ_Y)
  JSR dp_st
  JMP nx                  \ (NMOS: no BRA; JMP is 3 cycles too)
.gd
  JSR dp_ldp
  LDA rn_l
.^r_psl23 AND R_DISCL0,X
  CMP #&FF
  BNE gg
  JSR r_dp1               \ no disc, old or new: black the dirty extent
  JSR dp_st
  JMP nx
.gg
  TXA
  TAY
  JSR r_drg
  JSR dp_st
  JMP nx
}

\ ============================================================================
\ Two-colour discs.  r_dmb: rows X on, slots Y = 0 to dp_n - 1, when this
\ frame or this buffer's last one has boundaries.  Unchanged rows cost a few
\ compares.
\ ============================================================================
.r_dmb
{
.lp
  LDA DB_NL,Y
.^r_psl24 CMP R_DISCL0,X
  BNE ch
  LDA DB_NR,Y
.^r_psr24 CMP R_DISCR0,X
  BNE ch
  LDA DB_NN,Y             \ the count and the colour, new and old
.^r_pbn22 CMP R_BDN0,X
  BNE ch
  ASL A                   \ (A = 2 count; no boundaries, the usual case: on)
  BNE nz
.sm
  LDA DB_WL,Y             \ unchanged: dirty? then repaint only the dirty part
  CMP #&FF
  BNE smd
.nx
  INX
  INY
  CPY dp_n
  BNE lp
  RTS
.smd
  JSR dp_ld
  JSR r_smx
  JSR dp_st
  JMP nx
.ch
  LDA DB_WL,Y
  CMP #&FF
  BNE gd                  \ dirty
  JSR dp_ld
  JSR r_dpe
  JSR dp_st
  JMP nx                  \ (NMOS: no BRA; JMP is 3 cycles too)
.nz                       \ 1 to 3 boundaries, as stored (A = 2 count; 4
  STA r_cn                \ are never stored: r_bstore)
  LDA DB_X0,Y
.^r_pb020 CMP R_BDX00,X
  BNE chb
  LDA r_cn
  CMP #4
  BCC sm
  LDA DB_X1,Y
.^r_pb120 CMP R_BDX10,X
  BNE chb
  LDA r_cn
  CMP #6
  BCC sm
  LDA DB_X2,Y
.^r_pb220 CMP R_BDX20,X
  BEQ sm
.chb
  LDA DB_WL,Y
  CMP #&FF
  BNE gd                  \ dirty
  JSR dp_ld
  JSR r_dq
  JSR dp_st
  JMP nx
.gd
  JSR dp_ld
.^r_dmgd                  \ (r_smx's way in, with the row's data loaded)
  LDA rn_l
.^r_psl25 AND R_DISCL0,X
  EOR #&FF
  BNE gg
  STA r_dsub              \ (A = 0; r_smx's way in, r_gd1, has r_dsub = 0)
.^r_gd1
  JSR r_dp1               \ no disc, old or new: black the dirty extent
  JSR dp_st
  JMP nx
.gg
  TXA
  TAY
  JSR r_drg
  JSR dp_st
  JMP nx                  \ (out of BRA range; JMP is 3 cycles too)
}

\ r_smx: r_dmb, an unchanged dirty row (X, its data loaded): a dirty extent
\ clear of the span only needs blacking (r_dp1, as r_drg would); otherwise
\ only the dirty part of the span is repainted (r_dsub)
.r_smx
{
  LDA rd_l
  CMP rn_r
  BEQ sms
  BCS smf                 \ dL > sR
  LDA rd_r
  CMP rn_l
  BCC smf                 \ dR < sL
.sms
  INC r_dsub
  PLA                     \ (into r_dmb's gd path, as its own: r_dmgd, which
  PLA                     \ returns through dp_st)
  JMP r_dmgd
.smf
  JMP r_dp1
}

\ r_dq: X = row of a two-colour disc whose span, colour and boundary count
\ (r_cn = 2 count: one to three) are unchanged, no dirty, a boundary moved
\ (r_dmb): each moved boundary's strip (old .. new) in the colour on the
\ side it moved from, cut short where its neighbour's new place has passed
\ into it (as r_dpe: the span's ends stay put).  Returns X = RZ_Y.
.r_dq
{
  JSR r_rowp              \ row pointers, the segments' colours, no writes
  LDY #&FF                \ (NMOS: in Y, as there is no INC A)
  STY r_wmin
  INY
  STY r_wmax
  TXA
  AND #1
  TAY
  LDA rn_n
  BMI cb
  LDA R_DCE,Y
  STA r_c0
  LDA r_dbe,Y
  STA r_c1
  JMP go                  \ (NMOS: no BRA)
.cb
  LDA r_dbe,Y
  STA r_c0
  LDA R_DCE,Y
  STA r_c1
.go
  LDA rn_x0               \ the first: moved right, old .. new-1 in segment
.^r_pb021 CMP R_BDX00,X   \ 0's colour; left, new .. old-1 (or up to the
  BEQ n0                  \ second's new place) in 1's
  BCC l0
  TAY
  DEY
.^r_pb022 LDA R_BDX00,X
  TAX
  LDA r_c0
  BCS p0                  \ (always: C set by the CMP)
.l0
.^r_pb023 LDA R_BDX00,X
  LDY r_cn
  CPY #4
  BCC l0b
  CMP rn_x1
  BCC l0b
  LDA rn_x1
.l0b
  CMP rn_x0
  BEQ n0
  TAY
  DEY
  LDX rn_x0
  LDA r_c1
.p0
  JSR rs_put
  LDX RZ_Y
.n0
  LDA r_cn
  CMP #4
  BCS b1
  JMP fin
.b1
  LDA rn_x1               \ the second: right, from the first's new place on,
.^r_pb121 CMP R_BDX10,X   \ in 1's; left, up to the third's, in 2's (0's)
  BEQ n1
  BCC l1
  TAY
  DEY
.^r_pb122 LDA R_BDX10,X
  CMP rn_x0
  BCS P%+5
  LDA rn_x0
  CMP rn_x1
  BCS n1
  TAX
  LDA r_c1
  BCC p1                  \ (always)
.l1
.^r_pb123 LDA R_BDX10,X
  LDY r_cn
  CPY #6
  BCC l1b
  CMP rn_x2
  BCC l1b
  LDA rn_x2
.l1b
  CMP rn_x1
  BEQ n1
  TAY
  DEY
  LDX rn_x1
  LDA r_c0
.p1
  JSR rs_put
  LDX RZ_Y
.n1
  LDA r_cn
  CMP #6
  BCC fin
  LDA rn_x2               \ the third: right, from the second's new place
.^r_pb221 CMP R_BDX20,X   \ on, in 2's (0's); left, in 3's (1's)
  BEQ fin
  BCC l2
  TAY
  DEY
.^r_pb222 LDA R_BDX20,X
  CMP rn_x1
  BCS P%+5
  LDA rn_x1
  CMP rn_x2
  BCS fin
  TAX
  LDA r_c0
  BCC p2                  \ (always)
.l2
.^r_pb223 LDY R_BDX20,X
  DEY
  TAX
  LDA r_c1
.p2
  JSR rs_put
  LDX RZ_Y
.fin
  LDA rn_x0               \ the new boundaries; what was written
.^r_pb024 STA R_BDX00,X
  LDA rn_x1
.^r_pb124 STA R_BDX10,X
  LDA rn_x2
.^r_pb224 STA R_BDX20,X
  LDA r_wmax
  BEQ fx
  STA rw_r
  LDA r_wmin
  STA rw_l
.fx
  RTS
}

\ rs_cols (raster_strips.asm's): X = row, A's bit 7: colour B at the left
\ end: r_c0 and r_c1, the colours of the segment at the left end and of the
\ next, by the row's parity (keeps X)
.rs_cols
{
  ASL A                   \ (C: colour B at the left end)
  TXA
  AND #1
  TAY                     \ (Y: an odd row)
  BCS b
  LDA R_DCE,Y
  STA r_c0
  LDA r_dbe,Y
  STA r_c1
  RTS
.b
  LDA r_dbe,Y
  STA r_c0
  LDA R_DCE,Y
  STA r_c1
  RTS
}

\ rs_put (raster_strips.asm's, and r_dq's): r_sw, noting the strip in r_wmin ..
\ r_wmax (strips come left to right: the first sets r_wmin, the last r_wmax)
.rs_put
  CPX r_wmin
  BCS P%+5
  STX r_wmin
  STY r_wmax
  JMP r_sw

\ ******************************************************************************
\
\ r_sw: pixels X .. Y (X <= Y) of the row (r_rowp: RZ_Y, RZ_PA, RZ_PB set)
\ in colour A, each end's byte masked.  Clobbers A, X, Y, RZ_COL, RZ_SA,
\ RZ_SA+1, RZ_PP+1, RZ_T7.  With r_qok bit 7 set, a span of 16 whole bytes or
\ more is queued for bank 5's row runs while the queue has room (r_sq).
\
\ Port (Model B): the Master port's, with the byte offsets worked out and
\ the masks from four-byte tables (r_lm4, r_rm4), and the row's two pages
\ (columns 0..31 and 32..63) as one pointer, RZ_PP, to the half that the
\ pixels are in: a span across the halves is written as two (r_lput2 was
\ bank 5's).
\
\ ******************************************************************************
{
.cross                    \ X in columns 0..31, Y in 32..63: queued, or the
  BIT r_qok               \ two halves
  BPL c1
  LDA RZ_SA               \ (whole bytes: Y DIV 4 - X DIV 4 - 1 >= 16, as
  LSR A                   \ (Y DIV 4) - (X DIV 4) >= 17)
  LSR A
  STA RZ_T7
  TXA
  LSR A
  LSR A
  EOR #&FF
  SEC
  ADC RZ_T7
  CMP #17
  BCC c1
  JSR r_sq
  BCC c9                  \ (queued)
.c1
  LDA RZ_SA
  STA r_sws
  LDA #127
  STA RZ_SA
  JSR hf
  LDX #128
  LDA r_sws
  STA RZ_SA
  BNE hf                  \ (always)

.^r_sw
  STA RZ_COL
  STY RZ_SA
.hf                       \ (X .. RZ_SA in RZ_COL)
  LDA RZ_PA+1             \ the half's page: RZ_PA's, or RZ_PB's for X >= 128
  CPX #&80
  ADC #0
  STA RZ_PP+1
  TXA
  EOR RZ_SA
  BMI cross               \ X in columns 0..31, Y in 32..63
  CMP #4
  BCC one                 \ one byte (the rarer case: the commoner multi-byte
                          \ case falls through)
  BIT r_qok               \ long and queued?
  BPL m1
  JSR r_sql
  BCC c9
.m1
  LDA RZ_SA               \ the last byte's offset
  ASL A
  AND #&F8
  STA RZ_SA+1
  TXA                     \ the first byte
  AND #3
  STA RZ_T7
  TXA
  ASL A
  AND #&F8
  TAY
  LDX RZ_T7
  LDA RZ_COL
  EOR (RZ_PP),Y
  AND r_lm4,X
  LDX RZ_COL              \ X = colour from here to .ls
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  TYA
  CLC
  ADC #8
  TAY
  TXA                     \ A = colour
  CPY RZ_SA+1
  BCS ls
.la                       \ the whole bytes between
  STA (RZ_PP),Y
  TYA
  ADC #8                  \ (C = 0 from the CPY)
  TAY
  TXA
  CPY RZ_SA+1
  BCC la
.ls
  LDA RZ_SA               \ the last byte
  AND #3
  TAX
  LDA RZ_COL
  EOR (RZ_PP),Y
  AND r_rm4,X
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
.c9
  RTS

.one
  LDA RZ_SA               \ one byte: both masks
  AND #3
  TAY
  LDA r_rm4,Y
  STA RZ_T7
  TXA
  AND #3
  TAY
  LDA r_lm4,Y
  AND RZ_T7
  STA RZ_T7
  TXA
  ASL A
  AND #&F8
  TAY
  LDA RZ_COL
  EOR (RZ_PP),Y
  AND RZ_T7
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  RTS
}

\ r_sql: pixels X .. RZ_SA in one half of the row, in RZ_COL: queued (C
\ clear) if 16 whole bytes or more lie between the ends and the queue has
\ room, else C set (X kept). r_sq: queued if there is room (C clear), else C
\ set (X kept)
.r_sql
{
  LDA RZ_SA
  SEC
  STX RZ_T7
  SBC RZ_T7               \ Y - X >= 68 pixels: perhaps; the exact test below
  CMP #68
  BCC no
  LDA RZ_SA
  LSR A
  LSR A
  STA RZ_T7
  TXA
  LSR A
  LSR A
  EOR #&FF
  SEC
  ADC RZ_T7
  CMP #17
  BCS r_sq
.no
  SEC
  RTS
}
.r_sq
{
  LDY DB_QN
  CPY #DB_QE - DB_Q
  BCS no
  LDA RZ_Y
  STA DB_Q,Y
  TXA
  STA DB_Q+1,Y
  LDA RZ_SA
  STA DB_Q+2,Y
  LDA RZ_COL
  STA DB_Q+3,Y
  TYA
  ADC #4                  \ (C = 0 from the CPY)
  STA DB_QN
.no
  RTS
}

.r_lm4  EQUB &FF, &77, &33, &11   \ pixels (x AND 3) .. 3 of a byte
.r_rm4  EQUB &88, &CC, &EE, &FF   \ pixels 0 .. (x AND 3)

\ r_rowp: X = row: RZ_Y, and RZ_PA, RZ_PB its screen address in the buffer
\ (columns 0..31 and 32..63; the row's page &10 or &40 + 2 (row DIV 8), its
\ line row AND 7).  Keeps X and Y.
.r_rowp
  STX RZ_Y
  TXA
  AND #7
  STA RZ_PA
  STA RZ_PB
  STA RZ_PP               \ (r_sw's pointer to either half)
  TXA
  LSR A
  LSR A
  AND #&FE
  CLC
.^dp_scr
  ADC #HI(SCREEN%)        \ (patched: the buffer's screen)
  STA RZ_PA+1
  ADC #1
  STA RZ_PB+1
  RTS

\ ============================================================================
\ r_dpe: X = row of a two-colour disc, no dirty, its span, count or colour
\ changed (r_dmb).  A row is a list of edges: its span's left end, its
\ boundaries, the end after its right end; a pixel takes the colour after
\ the last edge at or before it (black after the last).  The old list and
\ the new are made alike, three boundaries each and the same colour at the
\ left end, with virtual boundaries (segments of no width): one at the left
\ end of the list with fewer if the colours there differ, then at the end
\ after the right end of each list as many as it lacks.  Then each edge's
\ strip, old .. new, is written in the colour on the side it moved from,
\ cut short where the edge before's new place (moving right) or the edge
\ after's (moving left) has passed into it: exactly the pixels whose
\ colour changed (each such pixel lies in one strip, as the edges are in
\ order, old and new).  More than three boundaries after that, or an
\ unknown old count: r_drg, a repaint.  No old span: the new one segment by
\ segment (r_segw); a row with no old span has a count of none (DP_BEGIN,
\ the switch from plain rows and every write of an empty span keep it so),
\ so the same count means both spans there.  No new span: r_dp2 blacks the
\ old.  No boundaries, old or new, and the same colour: r_dp2's one-colour
\ row.
\ ============================================================================
\ r_dpb: r_dp2 for a one-colour row in colour B (X = row): R_DCE / R_DCO and
\ R_DBE / R_DBO swapped round it.  Returns X = RZ_Y.
.r_dpb
  JSR r_dsw
  JSR r_dp2
.r_dsw                    \ swap the colour pairs (X kept)
  LDA R_DCE
  LDY R_DBE
  STA R_DBE
  STY R_DCE
  LDA R_DCO
  LDY R_DBO
  STA R_DBO
  STY R_DCO
  RTS
.r_dpe
{
  STX RZ_Y
  LDA rn_n                \ the count and the colour (bit 7), new and old
.^r_pbn23 CMP R_BDN0,X
  BEQ sm
  JMP df
.sm
  ASL A                   \ the same (A = 2 count, C = the colour): no
  BNE sc                  \ boundaries: a one-colour row, which r_dp2 does
  BCS r_dpb               \ in less time, in colour A (R_DCE / R_DCO) or,
  JMP r_dp2               \ with the pairs swapped round it, B
.sc
  LSR A                   \ (both spans there: a count of one to three)
  STA r_ok
  STA r_nk
  JSR ld
  LDA rn_n
  JMP rs_cs
.df                       \ another count or colour
.^r_pbn24 LDA R_BDN0,X
  CMP #&40
  BEQ rp                  \ (the old count unknown)
  LDA rn_l
  CMP #&FF
  BEQ ne
  LDA rn_n                \ the counts (the new at most three)
  AND #7
  CMP #4
  BCS rp
  STA r_nk
.^r_pbn25 LDA R_BDN0,X
  AND #3
  STA r_ok
.^r_psl26 LDA R_DISCL0,X
  CMP #&FF
  BEQ oe
  JSR ld
  LDA rn_n                \ (C: the colours at the left end differ)
.^r_pbn26 EOR R_BDN0,X
  ASL A
  LDA rn_n
  JMP rs_df
.rp
  TXA                     \ a repaint
  TAY
  JMP r_drg
.ne
  JSR r_dp2               \ no new span: the old one black, then the row's
  LDY RZ_Y                \ count and colour
  JMP r_bstore
.oe
  JSR r_rowp              \ no old span: the new one segment by segment
  TXA                     \ (r_segw)
  TAY
  JSR r_bcols
  LDA rn_l
  STA r_nL
  LDA rn_r
  STA r_nR
  LDX #&FF                \ (NMOS: X, for a 0)
  STX r_wmin
  INX
  STX r_wmax
  JSR r_segw
  JMP r_dpst
\ ld: row X's edges as raster_strips.asm wants them, the row pointers and
\ nothing written yet (r_wmin, r_wmax); keeps X (NMOS: clobbers Y)
.ld
.^r_psl27 LDA R_DISCL0,X
  STA r_ol
.^r_pb025 LDA R_BDX00,X
  STA rs_t0
.^r_pb125 LDA R_BDX10,X
  STA rs_t1
.^r_pb225 LDA R_BDX20,X
  STA rs_t2
.^r_psr27 LDY R_DISCR0,X  \ (NMOS: in Y, as there is no INC A)
  INY
  STY r_oe
  LDA rn_l
  STA r_nl
  LDA rn_x0
  STA rs_t3
  LDA rn_x1
  STA rs_t4
  LDA rn_x2
  STA rs_t5
  LDY rn_r
  INY
  STY r_ne
  JSR r_rowp
  LDY #&FF
  STY r_wmin
  INY
  STY r_wmax
  RTS
}
.rs_ov                    \ (raster_strips.asm: more than three boundaries,
  LDY RZ_Y                \ nothing written: a repaint)
  JMP r_drg
 INCLUDE "1-source-files/main-sources/gfx-raster_strips.asm"
\ r_dpst: (falling from raster_strips.asm's strips, or from r_dpe) the row's
\ new span, count, colour and boundaries; what was written
.r_dpst
{
  LDY RZ_Y                \ the row's new span, count, colour and boundaries;
  LDA rn_l                \ what was written
.^r_psl28 STA R_DISCL0,Y
  LDA rn_r
.^r_psr28 STA R_DISCR0,Y
  LDA rn_n
.^r_pbn27 CMP R_BDN0,Y
  BNE e5
  LDA rn_x0               \ (the same count and colour)
.^r_pb026 STA R_BDX00,Y
  LDA rn_x1
.^r_pb126 STA R_BDX10,Y
  LDA rn_x2
.^r_pb226 STA R_BDX20,Y
  BCS e6                  \ (always: C set by the CMP)
.e5
  JSR r_bstore
.e6
  LDA r_wmax
  BEQ e7
  STA rw_r
  LDA r_wmin
  STA rw_l
.e7
  LDX RZ_Y
  RTS
}

\ r_segw: r_drg with boundaries: the whole new span r_nL..r_nR, segment by
\ segment in colours A / B (row RZ_Y, r_cA/r_cB set; the boundaries r_bv:
\ the row's, rn_x0 .. rn_x3)
.r_segw
{
  LDA r_nR
  CMP r_nL
  BCS go
  RTS
.go
  LDA rn_n                \ the count (at most 4) and the colour (bit 7)
  AND #&7F
  STA r_cn
  LDA rn_n
  ROL A
  ROL A
  AND #1
  STA r_np                \ colour now
  LDA r_nL
  STA r_ba                \ segment start
  LDX #0
.lp
  CPX r_cn
  BCS last
  LDA r_bv,X
  CMP r_nL
  BEQ flip
  BCC flip
  CMP r_nR
  BEQ s2
  BCS last
.s2
  CMP r_ba
  BEQ flip                \ empty segment
  STX r_nn
  TAX
  DEX
  JSR seg
  LDX r_nn
  LDA r_bv,X
  STA r_ba
.flip
  LDA r_np
  EOR #1
  STA r_np
  INX
  BNE lp                  \ (always: X <= 4)
.last
  LDX r_nR
.seg                      \ r_ba .. X in colour r_np
  LDA r_np
  LSR A
  LDA r_cA
  BCC c1
  LDA r_cB
.c1
  STA RZ_COL
  LDA r_ba
  JMP r_dw
}

\ r_dlx: (r_dp2 and r_drg's) the row's new span empty: its boundaries none
\ too, as a row with no old span must have (r_dpe), when the layer keeps
\ boundaries (r_bon)

\ r_dp2: X = row, dirty empty, disc changed (one colour, R_DCE / R_DCO by
\ row parity).  The old span is intact, so only the difference between it
\ and the new one is written: pixels in the new span but not the old take
\ the disc colour, pixels in the old but not the new go black, each piece by
\ r_sw (masked at its end bytes, so the pieces can share bytes, and the
\ window's border columns keep their pixels).  At most two pieces: the two
\ ends' strips when the spans overlap, else the old span and the new one.
\ rw_l/rw_r = the bytes written (none: left as they are).  Returns X = RZ_Y.
.r_dp2
{
  JSR r_rowp              \ row pointers (RZ_Y = X)
.^r_psl29 LDA R_DISCL0,X
  STA RZ_T0               \ oL
.^r_psr29 LDY R_DISCR0,X  \ (Y = oR kept until the TYA below; emp leaves Y alone)
  STY RZ_T1               \ oR
  LDA rn_l                \ nL, nR: clamped to the window (empty: 255, 0)
  CMP R_CL
  BCS c0
  LDA R_CL
.c0
  STA RZ_T2
.^r_psl30 STA R_DISCL0,X  \ (before r_sr: nothing reads either in between)
  LDA rn_r
  CMP R_CR
  BCC c1
  LDA R_CR
.c1
  CMP RZ_T2
  BCC emp                 \ nR < nL: empty (out of line)
.c1b
  STA RZ_T3
.^r_psr30 STA R_DISCR0,X
  TYA                     \ old empty: the new span (A = oR)
  BCC empd                \ (C clear: from emp, the new span empty)
  CMP RZ_T0
  BCC jonew
  CMP RZ_T2               \ (nR >= nL here: the new span is not empty)
  BCC jboth               \ apart (oR < nL or nR < oL): both
.ovl
  LDA RZ_T2               \ overlapping: the left end (rw_l/rw_r noted here,
  CMP RZ_T0               \ the left end's strip before the right end's)
  BEQ requal              \ (nL >= oL: nR >= nL >= oL, so not apart)
  BCS lshr
  LDY RZ_T0               \ nL < oL: apart if nR < oL, i.e. oL-1 >= nR
  DEY
  CPY RZ_T3
  BCS jboth
  AND #&FC                \ grown: nL .. oL-1 in the disc colour
  STA r_wmin
  TYA
  ORA #3
  STA rw_r                \ rw_r: the left end's bytes (the right end's strip, if
  TXA                     \ any, overwrites it) (X = RZ_Y; the row's disc colour:
                          \ R_DCE / R_DCO by parity)
  AND #1
  TAX
  LDA R_DCE,X
  LDX RZ_T2
  JSR r_sw
  JMP right               \ (NMOS: no BRA)
.jboth
  JMP both
.jonew
  JMP onew0
.empd                     \ new empty (A = oR): old empty too: onew0, else
  CMP RZ_T0               \ the old span black
  BCC jonew
  LDA RZ_T0               \ (as oblk: X = oL, r_wmin = oL AND &FC, then
  BCS rqs1                \ .rshr2: Y = oR, rw_r = oR OR 3, black; always)
.emp
  LDA #&FF                \ empty new span: (255, 0)
  STA RZ_T2
.^r_psl31 STA R_DISCL0,X
  LDA #0                  \ (A = 0, C clear: BCC emp)
  BEQ c1b
.requal                   \ left ends equal: r_wmin from the right end's strip
  LDA RZ_T3
  CMP RZ_T1
  BEQ none                \ same span: nothing written (X = RZ_Y)
  BCC rqs
  LDA RZ_T1               \ grown: r_wmin = (oR + 1) AND &FC
  ADC #0                  \ (C set: + 1)
  AND #&FC
  STA r_wmin
  LDA RZ_T3
  BNE rgr                 \ (always: nR > oR)
.rqs                      \ shrunk: r_wmin = (nR + 1) AND &FC, X = nR + 1
  ADC #1                  \ (C clear)
.rqs1                     \ (entered here from .empd with A = oL)
  TAX
  AND #&FC
  STA r_wmin
  JMP rshr2               \ (NMOS: no BRA)
.lshr
  SBC #1                  \ shrunk: oL .. nL-1 black (C set)
  TAY
  ORA #3
  STA rw_r
  LDA RZ_T0
  TAX
  AND #&FC
  STA r_wmin
  LDA #0                  \ (black: NMOS has no STZ, so through r_sw's
  JSR r_sw                \ STA RZ_COL)
.right                    \ (r_wmin and rw_r already set by the left end's strip)
  LDA RZ_T3
  CMP RZ_T1
  BEQ fin
  BCS rgr
.rshr
  ADC #1                  \ shrunk: nR+1 .. oR black (C clear)
  TAX
.rshr2                    \ (entered here from .rqs1 with X = nR+1 or oL)
  LDY RZ_T1
  LDA #0                  \ (black, through r_sw's STA RZ_COL)
  JSR r_sw
  LDX RZ_Y
  LDA RZ_T1               \ rw_r: the bytes written
  ORA #3
.wr
  STA rw_r
  BNE fin2                \ (always: A >= 3)
.rgr
  TAY                     \ (Y = nR for r_sw)
  ORA #3                  \ grown: oR+1 .. nR in the disc colour
  STA rw_r                \ rw_r: the bytes written (the right end's strip is the max)
  LDA RZ_Y                \ the row's disc colour
  AND #1
  TAX
  LDA R_DCE,X
  LDX RZ_T1
  INX
  JSR r_sw
.fin                      \ (rw_r set and a strip written on every path here)
  LDX RZ_Y                \ (X = RZ_Y on return)
.fin2
  LDA r_wmin              \ rw_l: the bytes written
  STA rw_l
.none
  RTS
.onew0                    \ old span empty: nothing noted yet
  LDY #&FF                \ (NMOS: Y, for a 0)
  STY r_wmin
  INY
  STY r_wmax
  BEQ onew                \ (always)
.both
  JSR oblk
.onew
  LDA RZ_T3
  CMP RZ_T2
  BCC none                \ both spans empty (only from onew0, X = RZ_Y still)
  TAY
  LDA RZ_Y                \ the row's disc colour
  AND #1
  TAX
  LDA R_DCE,X
  STA RZ_COL
  LDX RZ_T2
  JSR put
  LDX RZ_Y
  LDA r_wmax              \ rw_r: the bytes written (r_wmax >= 3: a strip was written)
  BNE wr                  \ (always)
.oblk                     \ the old span black (always the first strip)
  LDX #&FF                \ (NMOS: X, for a 0)
  STX r_wmin
  INX
  STX r_wmax
  STX RZ_COL
  LDX RZ_T0
  LDY RZ_T1
.put                      \ pixels X .. Y in colour RZ_COL (X <= Y), noted
  TXA
  AND #&FC
  CMP r_wmin
  BCS p1
  STA r_wmin
.p1
  TYA
  ORA #3
  CMP r_wmax
  BCC p2
  STA r_wmax
.p2
  LDA RZ_COL
  JMP r_sw
}

\ r_drg: general disc row, Y = row (its data loaded)
.r_drg
{
  TYA
  TAX
  JSR r_rowp
  LDX #&FF                \ (NMOS: X, for a 0, kept 0 to .idone or .iempty:
  STX r_wmin              \ X = 0 below)
  INX
  STX r_wmax
  TYA
  LSR A
  LDA R_DCE
  BCC e
  LDA R_DCO
.e
  STA r_dcol
  STX r_segs
  LDA r_bon
  BEQ dn
  JSR r_bcols             \ boundaries: plain only if none, old and new,
  LDA rn_n                \ and the same colour
.^r_pbn28 CMP R_BDN0,Y
  BNE sg
  ASL A                   \ (A = 2 count, C = the colour)
  BNE sg
  LDA r_cA
  BCC sg1
  LDA r_cB
.sg1
  STA r_dcol
  JMP dn                  \ (NMOS: no BRA)
.sg
  INC r_segs
.dn
.^r_psl32 LDA R_DISCL0,Y
  STA r_oL
.^r_psr32 LDA R_DISCR0,Y
  STA r_oR
  LDA rd_l
  STA r_dL
  LDA rd_r
  STA r_dR
  LDA rn_l
  CMP R_CL
  BCS n1
  LDA R_CL
.n1
  STA r_nL
  LDA rn_r
  CMP R_CR
  BCC n2
  LDA R_CR
.n2
  STA r_nR
  CMP r_nL
  BCS n3
  LDA #&FF
  STA r_nL
  STX r_nR                \ (X = 0)
.n3
  \ intact = old - dirty (the larger piece)
  LDA r_oR
  CMP r_oL
  BCC iempty
  LDA r_dR
  CMP r_dL
  BCC iwhole
                          \ (A = r_dR still)
  CMP r_oL
  BCC iwhole
  LDA r_oR
  CMP r_dL
  BCC iwhole
  LDA r_dL
  SEC
  SBC r_oL
  BCS i1
  TXA                     \ (X = 0)
.i1
  STA r_tl
  LDA r_oR
  SEC
  SBC r_dR
  BCS i2
  TXA
.i2
  CMP r_tl
  BEQ usel
  BCC usel
  LDX r_dR
  INX
  STX r_iL
  LDA r_oR
  STA r_iR
  BCS idone               \ (always: C set by the CMP)
.usel
  LDA r_tl
  BEQ iempty
  LDA r_oL
  STA r_iL
  LDX r_dL
  DEX
  STX r_iR
  JMP idone               \ (NMOS: no BRA)
.iwhole
  LDA r_oL
  STA r_iL
  LDA r_oR
  STA r_iR
  BCC idone               \ (always: from BCC iwhole)
.iempty
  LDA #&FF
  STA r_iL
  STX r_iR                \ (X = 0)
.idone
  LSR r_dsub              \ (0 or 1: cleared, C = the old value)
  LDA r_segs
  BEQ dc0
  BCC whole               \ span and boundaries unchanged (r_dmb): only the
                          \ dirty part of the span
  LDA r_nL
  PHA
  LDA r_nR
  PHA
  LDA r_dL
  CMP r_nL
  BCC sb1
  STA r_nL
.sb1
  LDA r_dR
  CMP r_nR
  BCS sb2
  STA r_nR
.sb2
  JSR r_segw
  PLA
  STA r_nR
  PLA
  STA r_nL
  JMP nodisc
.whole
  JSR r_segw              \ boundaries: repaint the whole new span
  JMP nodisc
.dc0
  \ disc colour on new - intact
  LDA r_nR
  CMP r_nL
  BCC nodisc
  LDA r_dcol
  STA RZ_COL
  LDA r_iR
  CMP r_iL
  BCC full
                          \ (A = r_iR still)
  CMP r_nL
  BCC full
  LDA r_nR
  CMP r_iL
  BCC full
  LDA r_nL
  CMP r_iL
  BCS d2
  LDX r_iL
  DEX
  JSR r_dw
.d2
  LDA r_iR
  CMP r_nR
  BCS nodisc
  ADC #1                  \ (C clear)
  LDX r_nR
  BCC dw                  \ (always: r_dw, as .full)
.full
  LDA r_nL
  LDX r_nR
.dw
  JSR r_dw
.nodisc
  \ black on (old + dirty) - new
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_COL
  LDA r_oR
  CMP r_oL
  BCC oe
  LDA r_dR
  CMP r_dL
  BCC de
  LDX r_oR
  INX
  CPX r_dL
  BCC sep
  LDX r_dR
  INX
  CPX r_oL
  BCC sep
  LDA r_oL
  CMP r_dL
  BCC h1
  LDA r_dL
.h1
  STA r_ba
  LDA r_oR
  CMP r_dR
  BCS h2
  LDA r_dR
.h2
  STA r_bb
  JMP bm                  \ (NMOS: no BRA, so to .oe's r_bmn)
.sep
  LDA r_dL
  STA r_ba
  LDA r_dR
  STA r_bb
  JSR r_bmn
.de
  LDA r_oL
  STA r_ba
  LDA r_oR
  STA r_bb
  JMP bm
.oe
  LDA r_dR
  CMP r_dL
  BCC fin
  LDA r_dL
  STA r_ba
  LDA r_dR
  STA r_bb
.bm
  JSR r_bmn
.fin
  LDY RZ_Y
  LDA r_nL
.^r_psl33 STA R_DISCL0,Y
  LDA r_nR
.^r_psr33 STA R_DISCR0,Y
  LDA r_bon
  BEQ nb1
  JSR r_bstore            \ remember this row's boundaries
.nb1
  LDA r_wmax
  STA rw_r
  BEQ nw
  LDA r_wmin
  STA rw_l
.nw
  LDX RZ_Y
  RTS
}

\ r_bcols: Y = row: r_cA, r_cB = colour A, B bytes of the row (keeps X, Y; r_drg,
\ r_dpe)
.r_bcols
  TYA
  LSR A                   \ (C: an odd row)
  LDA R_DCE
  BCC P%+4
  LDA R_DCO
  STA r_cA
  LDA R_DBE
  BCC P%+5
  LDA R_DBO
  STA r_cB
  RTS

\ r_bstore: Y = row: remember the row's new boundaries (raw) and colour in
\ this buffer; a row with more than three is stored as unknown (count &40)
.r_bstore
  LDA rn_n
  ASL A                   \ (2 count)
  CMP #8
  BCS bsu
  LDA rn_n
.^r_pbn29 STA R_BDN0,Y
  LDA rn_x0
.^r_pb027 STA R_BDX00,Y
  LDA rn_x1
.^r_pb127 STA R_BDX10,Y
  LDA rn_x2
.^r_pb227 STA R_BDX20,Y
  RTS
.bsu
  LDA #&40
.^r_pbn30 STA R_BDN0,Y
  RTS

\ r_dp1: X = row with a dirty extent and no disc (old or new): the extent
\ black, and what was written
.r_dp1
  JSR r_rowp
  LDA rd_l
  STA rw_l
  TAX
  LDA rd_r
  STA rw_r
  TAY
  LDA #0
  JSR r_sw
  LDX RZ_Y
  RTS

\ r_dw: span A..X (A <= X) in RZ_COL on the row set up; tracks wmin/wmax
.r_dw
{
  CMP r_wmin
  BCS w1
  STA r_wmin
.w1
  CPX r_wmax
  BCC w2
  STX r_wmax
.w2
  STX r_dwx
  TAX
  LDY r_dwx
  LDA RZ_COL
  JMP r_sw
}

\ r_bmn: black on [r_ba, r_bb] minus [r_nL, r_nR]
.r_bmn
{
  LDA r_nR
  CMP r_nL
  BCC whole
  LDA r_nR
  CMP r_ba
  BCC whole
  LDA r_bb
  CMP r_nL
  BCC whole
  LDA r_ba
  CMP r_nL
  BCS b2
  LDX r_nL
  DEX
  JSR r_dw
.b2
  LDA r_nR
  CMP r_bb
  BCS done
  ADC #1                  \ (C clear)
  LDX r_bb
  JMP r_dw
.whole
  LDA r_ba
  LDX r_bb
  JMP r_dw
.done
  RTS
}

\ The painter's variables

.dp_buf  EQUB 0         \ the buffer (DP_BEGIN)
.dp_fl   EQUB 0         \ its flags (PB_*)
.dp_n    EQUB 0         \ the batch: its rows, its first row
.dp_y0   EQUB 0
.dp_s    EQUB 0         \ the slot and row in hand (dp_ld, dp_st)
.dp_x    EQUB 0
.r_qok   EQUB 0         \ bit 7: long spans may be queued (r_sw)
.r_sws   EQUB 0         \ (r_sw's)
.r_dwx   EQUB 0         \ (r_dw's)
.R_DBE   EQUB 0         \ colour B, even and odd rows (DP_BEGIN)
.R_DBO   EQUB 0
r_dbe = R_DBE
.r_bon   EQUB 0         \ this frame's rows use boundaries
.r_dsub  EQUB 0         \ r_dmb -> r_drg: repaint only the dirty part
.rn_l    EQUB 0         \ the row's new span, count and colour (R_NDN's form)
.rn_r    EQUB 0         \ and boundaries (dp_ld)
.rn_n    EQUB 0
.rn_x0   EQUB 0
.rn_x1   EQUB 0
.rn_x2   EQUB 0
.rn_x3   EQUB 0
.rd_l    EQUB 0         \ its dirty extent (none: 255, 0)
.rd_r    EQUB 0
.rw_l    EQUB 0         \ what it wrote (rw_r = 0: nothing)
.rw_r    EQUB 0
r_bv = rn_x0            \ r_segw: the new boundaries (4)
.r_oL    EQUB 0         \ R_DISCROWS' row variables (the Master port's r_ov)
.r_oR    EQUB 0
.r_dL    EQUB 0
.r_dR    EQUB 0
.r_nL    EQUB 0
.r_nR    EQUB 0
.r_iL    EQUB 0
.r_iR    EQUB 0
.r_wmin  EQUB 0
.r_wmax  EQUB 0
.r_dcol  EQUB 0
.r_ba    EQUB 0
.r_bb    EQUB 0
.r_tl    EQUB 0
.r_nn    EQUB 0         \ r_segw: the boundary count; the colour now
.r_np    EQUB 0
.r_cA    EQUB 0         \ this row's colour A, B bytes (r_bcols)
.r_cB    EQUB 0
r_c0 = r_cA             \ rs_cols: the colour at the left end, the other
r_c1 = r_cB
.r_segs  EQUB 0         \ r_drg: repaint the new span segment by segment
.r_cn    EQUB 0         \ r_dq: 2 count
.r_oe    EQUB 0         \ raster_strips.asm: the ends after the right ends, old, new
.r_ne    EQUB 0
.r_ok    EQUB 0         \ raster_strips.asm: the boundary counts, old, new
.r_nk    EQUB 0
.r_ol    EQUB 0         \ raster_strips.asm: the left ends, old, new
.r_nl    EQUB 0
