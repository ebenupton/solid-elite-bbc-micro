\ ============================================================================
\ raster_poly.asm -- the rasteriser's polygon window: R_POLY (both phases;
\ phase A for 16-bit coordinates, r7_pf16, came from bank 7), in ANDY
\ (ROMSEL &85: ANDY over bank 5's &8000-&8FFF; bank 5's &9000-&BFFF, the
\ shared region gfx-raster.asm, stays visible: its arithmetic, r_div8,
\ rp_mul16 and rp_div32, is there).  The frame layer's T_POLY
\ pages it in.  R_SETBUF (shared) pages it in to patch phase B's DIRTY
\ operands.  INCLUDE it at &8000 in an assembly of its own (ANDY), after
\ gfx-raster.asm.
\
\       Area: bank 5
\ ============================================================================

\ ============================================================================
\ R_POLY.  One loop over the vertices tests their high bytes (the 8-bit path
\ if every one is zero) and, on the way, finds the top vertex, the largest y
\ and whether some x is outside CL..CR.
\ ============================================================================
.R_POLY
{
  LDA R_PN
  BNE pn1
  RTS
.pn1
  CMP #17
  BCC n_ok
  LDA #16
.n_ok
  STA r_n
  TAX
  DEX
  STX r_top               \ (the top vertex, if every y is 255)
  LDY R_CR                \ (NMOS: + 1 by INY, not INC A)
  INY
  STY r_cr1
  LDA #0                  \ (NMOS: no STZ)
  STA r_xclip
  STA r_ymaxL
  LDA #&FF
  STA r_yminL
\ The vertices, last to first: while every high byte is zero (the 8-bit
\ path), the top vertex (the last of the least y: the first met), the
\ largest y and whether some x is outside CL..CR are found on the way.
.vl
  LDA R_PXH,X
  ORA R_PYH,X
  BNE p16
  LDA R_PYL,X
  CMP r_yminL
  BCS s1
  STA r_yminL
  STX r_top
.s1
  CMP r_ymaxL
  BCC s2
  STA r_ymaxL
.s2
  LDA R_PXL,X
  CMP R_CL
  BCC s3
  CMP r_cr1
  BCC s4
.s3
  INC r_xclip
.s4
  DEX
  BPL vl
  JMP r_pf8
.p16                      \ some coordinate outside 0..255: phase A (r7_pf16)
  JSR r7_pf16
  BEQ out                 \ (A = 0: nothing to draw; NMOS: Z from its LDA)
  JMP r_pcbd
.out
  RTS
}

\ ============================================================================
\ R_POLY 8-bit path: every vertex x, y in 0..255 (the scan above has set
\ r_top, r_yminL, r_ymaxL, r_xclip and r_cr1).
\ Phase A walks both chains from the top vertex, running each edge's exact
\ DDA (x = x0 + ceil(dx*k/dy)) down a per-row table: chain A (forward) into
\ r_ta, chain B (backward) into r_tb.  An edge's set-up and its division are
\ in line in the chain (r_e8, entered by a jump or by falling into it), and
\ its DDA loop ends with a jump back to the chain it is of (r_ex): an edge
\ makes no call, unless it starts above the window (r7_e8c) or its quotient
\ is 16 or more with a divisor under 16 (r_div8).  There are four loops:
\ r_lz for an edge with no remainder (x += a each row), r_sp and r_sn for a
\ steep edge (|dx| < dy: x in X steps by one when the error in A wraps, and
\ is stored through an operand whose low byte counts up the table, which is
\ within a page: gfx-bank5.asm), and r_lsh for the rest.  Phase B (r_pcbd) fills
\ each row from the left table to the right one (exclusive), keeping the
\ RTS planted in the current character row's store run until its position
\ changes.
\ ============================================================================
.r_pf8
{
  \ rows ystart..ylast
  LDA r_yminL
  CMP R_CT
  BCS y1
  LDA R_CT
.y1
  STA r_ystart
  CMP r_ymaxL
  BCS out
  CMP R_CB
  BEQ y2
  BCS out
.y2
  LDX r_ymaxL             \ (NMOS: in X, for DEX and INX)
  DEX
  CPX R_CB
  BCC y3
  LDX R_CB
.y3
  STX r_ylast
  INX
  STX r_yend
  \ chain A: forward into r_ta
  LDA #HI(r_ta)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r_sp_t+2
  STA r_sn_t+2
  LDA #LO(ca)
  STA r_exj+1
  LDA #HI(ca)
  STA r_exj+2
  LDX r_top
  BPL ca                  \ (always: X < 16)
.out
  RTS
.^r_ex                    \ an edge is done: on along its chain (or, for the
  LDX r_i1                \ 16-bit path, back to r7_pf16b: r_exr)
.^r_exj
  JMP ca                  \ (patched: ca, cb or r_exr)
.^r_exr
  RTS
.cl                       \ y0 < ystart: out if end row <= ystart, else clipped
  LDA RZ_T2
  CMP r_ystart
  BEQ r_ex
  BCC r_ex
  JMP clipped
.cad
  \ chain B: backward into r_tb
  LDA #HI(r_tb)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r_sp_t+2
  STA r_sn_t+2
  LDA #LO(cb)
  STA r_exj+1
  LDA #HI(cb)
  STA r_exj+2
  LDX r_top
.cb
  LDA R_PYL,X
  CMP r_ymaxL
  BEQ cbd
  TXA
  TAY                     \ Y = i0
  DEX
  BPL cb1
  LDX r_n
  DEX
.cb1
  STX r_i1
  JMP r_e8
.cbd
  JMP r_pcbd
.ca                       \ (from the top vertex, a vertex at ymax, the
  LDA R_PYL,X             \ largest of the vertices' y, comes within n - 1
  CMP r_ymaxL             \ edges either way: no count is needed)
  BEQ cad
  TXA
  TAY                     \ Y = i0
  INX
  CPX r_n
  BCC ca1
  LDX #0
.ca1
  STX r_i1

\ r_e8: the edge from vertex Y (i0) to vertex X (i1 = r_i1) of an 8-bit
\ polygon into the chain's table, then r_ex
.r_e8
  LDA R_PYL,X
  CMP R_PYL,Y
  BCC r_ex
  BEQ r_ex                \ not going down
  CMP r_yend
  BCC e1
  LDA r_yend
.e1
  STA RZ_T2               \ end row (exclusive)
  LDA R_PYL,Y
  CMP RZ_T2
  BCS r_ex                \ y0 >= end row
  CMP r_ystart
  BCC cl                  \ y0 < ystart (if y0 >= ystart then RZ_T2 > y0 >= ystart)
  STA RZ_T3               \ start row (A = y0, C = 1)
  EOR #&FF
  ADC R_PYL,X             \ dy = y1 - y0; C stays 1 (y1 > y0)
  STA RZ_T1               \ dy
  LDA R_PXL,Y
  STA RZ_T0               \ S = x0
  EOR #&FF
  ADC R_PXL,X             \ dx = x1 - x0, C = (x1 >= x0)
  BCS pos
  EOR #&FF
  ADC #1                  \ |dx| (NMOS: C = 0 here)
  LDY #&80                \ (Y's bit 7: dx < 0; i0 has it clear)
.pos
  CMP RZ_T1
  BCS div
  TAX                     \ steep: q = 0, r = |dx|
  BNE st
  STX r_lz_a+1            \ vertical: the loop with no remainder, a = 0
  JMP r_lzgo
.st
  CPY #&80
  BCS sneg
  STX r_sp_b+1            \ dx > 0: each row the error -= |dx|, and on a borrow
  LDA RZ_T1               \ += dy, x += 1
  STA r_sp_d+1
  SEC                     \ Y = the rows: the end row - the first (C = 1 after)
  LDA RZ_T2
  SBC RZ_T3
  TAY
  LDA RZ_T3               \ the table's first row (C = 0 after)
  ADC #LO(r_ta) - 1
  STA r_sp_t+1
  LDX RZ_T0
  LDA #0
  SEC
.r_sp                     \ X = x, A = the error, Y = rows to go, C = 1
.r_sp_t
  STX &FF00               \ (the table's row: its low byte counts up)
  INC r_sp_t+1
.r_sp_b
  SBC #0                  \ |dx|
  BCS sp1
.r_sp_d
  ADC #0                  \ dy (C = 0, then 1)
  INX
.sp1
  DEY
  BNE r_sp
  JMP r_ex
.sneg                     \ dx < 0: each row the error -= dy - |dx|, and x -= 1
  EOR #&FF                \ unless it borrows (then the error += dy)
  ADC RZ_T1               \ (C = 1: dy - |dx|)
  STA r_sn_b+1
  LDA RZ_T1
  STA r_sn_d+1
  SEC                     \ (as above)
  LDA RZ_T2
  SBC RZ_T3
  TAY
  LDA RZ_T3
  ADC #LO(r_ta) - 1
  STA r_sn_t+1
  LDX RZ_T0
  LDA #0
  SEC
.r_sn                     \ X = x, A = the error, Y = rows to go, C = 1
.r_sn_t
  STX &FF00               \ (the table's row: its low byte counts up)
  INC r_sn_t+1
.r_sn_b
  SBC #0                  \ dy - |dx|
  BCC sn1
  DEX
  DEY
  BNE r_sn
  JMP r_ex
.sn1
.r_sn_d
  ADC #0                  \ dy (C = 0, then 1)
  DEY
  BNE r_sn
  JMP r_ex
\ |dx| / dy (|dx| >= dy >= 1) -> X quotient, A remainder (Z set if it is 0).
\ Repeated subtraction when the quotient is small (divisor >= 16).
.div
  LDX RZ_T1
  CPX #16
  BCC small
  LDX #&FF                \ divisor >= 16: quotient < 16
  SEC
.dl
  INX
  SBC RZ_T1
  BCS dl
  ADC RZ_T1
  BNE rnz
  BEQ rz                  \ (always)
.long
  LDX RZ_T1
  STX r_v0
  JSR r_div8+2            \ (RZ_T6 holds the dividend: past r_div8's STA RZ_T6;
  CMP #0                  \ X = the quotient)
  BNE rnz
  BEQ rz                  \ (always)
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
  BEQ rz
\ x = x0 + ceil(dx * k / dy) per row: x += a, the error -= b, and on a
\ borrow the error += dy, x += 1, with a = floor(dx / dy), b = dx - a * dy
.rnz                      \ the remainder is not 0: X = q, A = r
  CPY #&80
  BCS nr
  TAY                     \ dx > 0: a = q, b = r (the loop's operands hold
  DEY                     \ a - 1 and b - 1)
  STY r_lsh_b+1
  DEX
  STX r_lsh_a+1
  BCC lsh0                \ (always: from the CPY)
.nr                       \ dx < 0: a = NOT q, b = dy - r (C = 1)
  SBC RZ_T1               \ r - dy = -b: NOT it is b - 1
  EOR #&FF
  STA r_lsh_b+1
  TXA
  EOR #&FF
  SBC #0                  \ (C = 0: - 1)
  STA r_lsh_a+1
.lsh0
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_TA
  BEQ r_lshgo             \ (always)
.rz                       \ the remainder is 0: X = q; a = q, or -q for dx < 0
  CPY #&80
  BCC rzp
  TXA
  EOR #&FF
  ADC #0                  \ (C = 1: + 1)
  TAX
.rzp
  STX r_lz_a+1
  BCC r_lzgo              \ (always: from the CPY, or the ADC, as q >= 1)
.clipped                  \ starts above the window: general set-up at ystart
  LDA r_ystart            \ (S -> RZ_T0, RZ_TA; dy -> RZ_T1; A = a, X = b)
  STA RZ_Y
  STA RZ_T3
  STX RZ_T7               \ (i1; Y = i0)
  JSR r7_e8c
  CPX #0
  BNE r_psh1
\ b = 0: A = a  (falls into r_lz)
.^r_pzl1
  STA r_lz_a+1
.r_lzgo
  LDA RZ_T2
  STA r_lz_e+1
  LDY RZ_T3
  LDA RZ_T0
  CLC
\ The DDA loops (Y = row, run to the patched end row)
.^r_lz                    \ b = 0: A = x
.^r_lz_t
  STA &FF00 + LO(r_ta),Y  \ (the chain's table: its high byte patched)
  INY
.^r_lz_a
  ADC #0                  \ a (C = 0)
.^r_lz_e
  CPY #0
  BCC r_lz
  JMP r_ex
\ shallow: X = b, A = a, RZ_TA = the error
.^r_psh1
  TAY                     \ (NMOS: a - 1 by DEY, not DEC A)
  DEY
  STY r_lsh_a+1
  DEX
  STX r_lsh_b+1
.r_lshgo
  LDA RZ_T1
  STA r_lsh_d+1
  LDA RZ_T2
  STA r_lsh_e+1
  LDY RZ_T3
  LDA RZ_T0
  CLC
.^r_lsh                   \ A = x, RZ_TA = error
.^r_lsh_t
  STA &FF00 + LO(r_ta),Y
  INY
  TAX
  LDA RZ_TA
.^r_lsh_b
  SBC #0                  \ b - 1 (C = 0)
  BCS lsh1
.^r_lsh_d
  ADC #0                  \ dy
  INX
.lsh1
  STA RZ_TA
  TXA
.^r_lsh_a
  ADC #0                  \ a - 1 (C = 1)
.^r_lsh_e
  CPY #0
  BCC r_lsh
  JMP r_ex
}

\ ----------------------------------------------------------------------------
\ r_pcbd: both chains' tables are made (phase A): the rows, then phase B
\ ----------------------------------------------------------------------------
{
.^r_pcbd
  \ which table is the left one?
  LDA r_ystart
  CLC
  ADC r_ylast
  ROR A
  TAY
  LDA r_ta,Y
  CMP r_tb,Y
  BCC aleft
  BNE bleft
  LDY r_ystart
.os
  LDA r_ta,Y
  CMP r_tb,Y
  BCC aleft
  BNE bleft
  INY
  CPY r_yend
  BCC os
  RTS                     \ no pixels
.aleft
  LDA #HI(r_ta)
  LDX #HI(r_tb)
  BNE ori                 \ (always)
.bleft
  LDA #HI(r_tb)
  LDX #HI(r_ta)
.ori
  STA r_pbl1+2
  STX r_pbr1+2
  STX r_pbr2+2
  \ horizontal clip: clamp both tables into CL..CR+1
  LDA r_xclip
  BEQ nocl
  LDY r_ystart
.cl
  LDA r_ta,Y
  CMP R_CL
  BCS cl1
  LDA R_CL
.cl1
  CMP r_cr1
  BCC cl2
  LDA r_cr1
.cl2
  STA r_ta,Y
  LDA r_tb,Y
  CMP R_CL
  BCS cl3
  LDA R_CL
.cl3
  CMP r_cr1
  BCC cl4
  LDA r_cr1
.cl4
  STA r_tb,Y
  INY
  CPY r_yend
  BCC cl
.nocl
  \ rows clamped to nothing at the top / bottom (ta = tb): trim them
  LDY r_ystart
.tt
  LDA r_ta,Y
  CMP r_tb,Y
  BNE tt1
  INY
  CPY r_yend
  BCC tt
  RTS                     \ (no pixels at all)
.tt1
  STY r_ystart
  LDY r_ylast
.tb
  LDA r_ta,Y
  CMP r_tb,Y
  BNE tb1
  DEY
  BCS tb                  \ (always: C = 1 from the CMP, equal)
.tb1
  STY r_ylast
  INY
  STY r_yend
  \ this buffer's dirty row range
  LDX R_PRBUF
  LDA r_ystart
  CMP R_PRDYT,X
  BCS d1
  STA R_PRDYT,X
.d1
  LDA r_ylast
  CMP R_PRDYB,X
  BCC d2
  STA R_PRDYB,X
.d2
  \ phase B set-up
  LDY r_ystart
  JSR r_rowset
  LDA RZ_PP+1
  STA r_jsr2+2
  LDA r_yend
  STA pb_ye+1
  LDA #R_NOPL             \ nothing planted
  STA RZ_PP
  LDA R_COLE              \ the colours by line: rows 4k, 4k+1 take COLE, COLO,
  STA r_c8                \ rows 4k+2, 4k+3 COL2, COL3
  STA r_c8+4
  LDA R_COLO
  STA r_c8+1
  STA r_c8+5
  LDA R_COL2
  STA r_c8+2
  STA r_c8+6
  LDA R_COL3
  STA r_c8+3
  STA r_c8+7
  JMP r_pbx               \ (Y = RZ_Y)
}


\ ----------------------------------------------------------------------------
\ Phase B: rows RZ_Y.. to the end row (pb_ye); left table r_pbl1, right
\ (exclusive) r_pbr1/r_pbr2.  Row pointers RZ_PA, RZ_PB (their low bytes the
\ row's line, row AND 7), the run page (RZ_PP+1, r_jsr2+2) and the colours
\ by line (r_c8: a 4-row dither) set; RZ_PP = the planted RTS (R_NOPL:
\ none).  One row loop: a row's colour is read from r_c8 by its line where
\ it is used (each edge and the run), and pb_cr moves to the next character
\ row.
\ ----------------------------------------------------------------------------

.pb_lb
  EOR (RZ_PB),Y
  AND r_lm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  JMP pb_l2
.pb_rb
  LDY r_xo,X              \ (A = the colour)
  EOR (RZ_PB),Y
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
.pb_skip
  LDY RZ_Y
  INY
.pb_ye
  CPY #0                  \ (patched: the end row)
  BEQ pb_end
  STY RZ_Y
  TYA                     \ RZ_PA/RZ_PB lo = row AND 7
  AND #7
  BEQ pb_cr
  STA RZ_PA
  STA RZ_PB
.r_pbx
.r_pbl1
  LDA &FF00 + LO(r_ta),Y  \ (the left table, the right: r_pcbd)
.r_pbr1
  CMP &FF00 + LO(r_ta),Y
  BCS pb_skip+2           \ empty row: Y = RZ_Y already, skip the LDY RZ_Y
  TAX
.r_pbr2
  LDA &FF00 + LO(r_ta),Y             \ NMOS: the right end first, while C = 0 (from
  SBC #0                  \ the BCS): - 1 by SBC #0, not DEC A
  STA R_XR
.r_pt62 CMP r_dr,Y
  BCC pb_d2
.r_pt63 STA r_dr,Y
.pb_d2
  TXA
.r_pt60 CMP r_dl,Y
  BCS pb_d1
.r_pt61 STA r_dl,Y
.pb_d1
  EOR R_XR
  CMP #4
  BCC pb_one
  LDY RZ_PA               \ the row's colour
  LDA r_c8,Y
  LDY r_xo,X
  CPX #&80
  BCS pb_lb
  EOR (RZ_PA),Y
  AND r_lm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
.pb_l2
  LDY R_XR                \ (no empty-run test: when no whole byte lies
  LDA r_j-4,Y             \ between the ends, the entry is the plant and the
  LDY r_j,X               \ JSR hits the RTS, as r_spc's)
  STY r_jsr2+1
  CMP RZ_PP
  BNE pb_plant
.pb_go
  LDY RZ_PA               \ (the run is indexed by the line, row AND 7)
  LDA r_c8,Y
.r_jsr2
  JSR &FFFF
  LDX R_XR                \ N = (XR >= &80); A = the colour still (NMOS: so the
  BMI pb_rb               \ right edge starts EOR (RZ_PA),Y, as r_spc's)
  LDY r_xo,X
  EOR (RZ_PA),Y
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  JMP pb_skip
.pb_end
  LDY #0                  \ (NMOS: for (RZ_PP),Y)
  LDA #r_opSTA            \ take the RTS out again
  STA (RZ_PP),Y
  RTS
.pb_cr
  TAX                     \ next character row: new run page (NMOS: X = 0
  LDA #r_opSTA            \ from A = row AND 7, for (RZ_PP,X), as Y = RZ_Y
  STA (RZ_PP,X)           \ is kept)
  STX RZ_PA               \ (line 0)
  STX RZ_PB
  LDA #R_NOPL
  STA RZ_PP
  LDX RZ_PA+1             \ (NMOS: the pages in X, for INX)
  INX
  INX
  STX RZ_PA+1
  INX
  STX RZ_PB+1
  INC RZ_PP+1
  INC r_jsr2+2            \ (Y = RZ_Y still)
  LDA RZ_PP+1             \ (Model B: the new run page's stores for this buffer:
  JSR r_pgfix             \ X and Y kept)
  JMP r_pbx
.pb_one
  LDA r_lm,X              \ both ends in one byte: its mask
  LDX R_XR
  AND r_rm,X
  STA RZ_T7
  LDY RZ_PA               \ the row's colour
  LDA r_c8,Y
  LDY r_xo,X              \ (the byte's offset: xr's is xl's)
  CPX #&80
  BCS pb_ob
  EOR (RZ_PA),Y
  AND RZ_T7
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  JMP pb_skip
.pb_ob
  EOR (RZ_PB),Y
  AND RZ_T7
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  JMP pb_skip
.pb_plant
  TAX                     \ (NMOS: X = the new plant, Y = 0; X is reloaded
  LDY #0                  \ after the run)
  LDA #r_opSTA
  STA (RZ_PP),Y
  STX RZ_PP
  LDA #r_opRTS
  STA (RZ_PP),Y
  JMP pb_go


\ R_POLY's phase A for 16-bit coordinates: its variables (its 32-bit maths,
\ rp_mul16 and rp_div32, are in the shared region, gfx-raster.asm)
.rp_ov SKIP 17          \ phase A's edge set-up (r7_edy .. r7_eb)
.r7_n EQUB 0            \ R_POLY's phase A (16-bit): vertices, top vertex,
.r7_top EQUB 0          \ y range, chain count, edge, side
.r7_yminL EQUB 0
.r7_yminH EQUB 0
.r7_ymaxL EQUB 0
.r7_ymaxH EQUB 0
.r7_cc EQUB 0
.r7_i0 EQUB 0
.r7_i1 EQUB 0
.r7_side4 EQUB 0        \ (only ever 0: NMOS: nothing stores it)
.r7_e8c                   \ bank 5's r_e8, an edge starting above the window: Y = i0,
  LDX RZ_T7               \ RZ_T7 = i1, RZ_Y = ystart -> S in RZ_T0 (t in RZ_TA), dy
  JSR r7_esgen            \ in RZ_T1, A = a, X = b (side r7_side4: always 0)
  LDA RZ_SA
  STA RZ_T0
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  RTS

\ ============================================================================
\ R_POLY's phase A for polygons with some coordinate outside 0..255: chain A
\ into r_ta, chain B into r_tb, rows r_ystart..r_ylast (the shared workspace); bank
\ R_POLY calls r7_pf16 and does phase B (r_pcbd)
\ ============================================================================
\ phase A's edge set-up (rp_ov)
r7_edy = rp_ov + 0
r7_ek0 = rp_ov + 2
r7_ex0 = rp_ov + 4
r7_eadx = rp_ov + 6
r7_eneg = rp_ov + 8
r7_eq = rp_ov + 9
r7_er = rp_ov + 11
r7_ea = rp_ov + 13
r7_eb = rp_ov + 15

.r7_pf16                  \ R_POLY, some coordinate outside 0..255: phase A (bank
{                         \ 5's r_pcbd does phase B); A = 0: nothing to draw
  LDA r_n                 \ (R_POLY's count, at most 16)
  STA r7_n
  \ reject when every x is left of CL or every x is right of CR
  TAX                     \ (NMOS: X from A, and RZ_T0 = 0 by LDA #0)
  LDA #0
  STA RZ_T0
  DEX
.xl
  LDA R_PXH,X
  BMI xlt
  BNE xgt
  LDA R_PXL,X
  CMP R_CL
  BCC xlt
  CMP R_CR
  BEQ xin
  BCC xin
.xgt
  LDA #2
  BNE xor                 \ (always)
.xin
  LDA #3
  BNE xor                 \ (always)
.xlt
  LDA #1
.xor
  ORA RZ_T0
  STA RZ_T0
  DEX
  BPL xl
  CMP #3
  BEQ xok
  LDA #0
  RTS
.xok
  LDA R_PYL
  STA r7_yminL
  STA r7_ymaxL
  LDA R_PYH
  STA r7_yminH
  STA r7_ymaxH
  LDX #0                  \ (NMOS: no STZ)
  STX r7_top
  INX
  CPX r7_n
  BEQ rows
.vl
  LDA R_PYL,X             \ y < ymin ?
  CMP r7_yminL
  LDA R_PYH,X
  SBC r7_yminH
  BVC v1
  EOR #&80
.v1
  BPL notless
  LDA R_PYL,X
  STA r7_yminL
  LDA R_PYH,X
  STA r7_yminH
  STX r7_top
  JMP notmore             \ (NMOS: no BRA)
.notless
  LDA r7_ymaxL             \ ymax < y ?
  CMP R_PYL,X
  LDA r7_ymaxH
  SBC R_PYH,X
  BVC v2
  EOR #&80
.v2
  BPL notmore
  LDA R_PYL,X
  STA r7_ymaxL
  LDA R_PYH,X
  STA r7_ymaxH
.notmore
  INX
  CPX r7_n
  BNE vl
.rows
  \ row range
  LDA r7_yminH
  BMI ys_ct
  BNE out0                \ ymin > 255
  LDA r7_yminL
  CMP R_CB
  BEQ ys_ok
  BCS out0                \ ymin > CB
.ys_ok
  CMP R_CT
  BCS ys_set
.ys_ct
  LDA R_CT
.ys_set
  STA r_ystart
  LDX r7_ymaxH
  BMI out0
  BNE yl_cb
  CMP r7_ymaxL
  BCS out0                \ ystart >= ymax : no rows
  LDX r7_ymaxL            \ (NMOS: in X, for DEX and INX)
  DEX
  CPX R_CB
  BCC yl_set
.yl_cb
  LDX R_CB
.yl_set
  STX r_ylast
  INX
  STX r_yend
  BNE go                  \ (always: X <= 192)
.out0
  LDA #0
  RTS
.go                       \ (into r7_pf16b)
}


\ ----------------------------------------------------------------------------
\ r7_pf16b: R_POLY with some coordinate outside 0..255 (rows r_ystart..r_ylast
\ already found).  Phase A as r_pf8 (chain A forward into r_ta, chain B
\ backward into r_tb) with 16-bit edges whose x is clamped into CL..CR+1 per
\ row; then bank 5's phase B (r_pcbd).
\ ----------------------------------------------------------------------------
.r7_pf16b
{
  LDA #LO(r_exr)          \ (the DDA loops' exit: back here; R_POLY has set
  STA r_exj+1             \ r_cr1)
  LDA #HI(r_exr)
  STA r_exj+2
  LDA #HI(r_ta)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r7_x16_t+2
  STA r7_x16_f+2
  LDA r7_n
  STA r7_cc
  LDX r7_top
.ca
  LDA R_PYL,X
  CMP r7_ymaxL
  BNE ca0
  LDA R_PYH,X
  CMP r7_ymaxH
  BEQ cad
.ca0
  DEC r7_cc
  BMI cad
  STX r7_i0
  INX
  CPX r7_n
  BCC ca1
  LDX #0
.ca1
  STX r7_i1
  JSR r7_e16
  LDX r7_i1
  BPL ca                  \ (always: X < 16)
.cad
  LDA #HI(r_tb)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r7_x16_t+2
  STA r7_x16_f+2
  LDA r7_n
  STA r7_cc
  LDX r7_top
.cb
  LDA R_PYL,X
  CMP r7_ymaxL
  BNE cb0
  LDA R_PYH,X
  CMP r7_ymaxH
  BEQ cbd
.cb0
  DEC r7_cc
  BMI cbd
  STX r7_i0
  DEX
  BPL cb1
  LDX r7_n
  DEX
.cb1
  STX r7_i1
  JSR r7_e16
  LDX r7_i1
  BPL cb                  \ (always: X < 16)
.cbd
  LDA #0                  \ (NMOS: no STZ)
  STA r_xclip
  LDA #1                  \ (bank 5: phase B)
  RTS
}

\ r7_e16: edge r7_i0 -> r7_i1 (16-bit) into the table (rows r_ystart..r_ylast)
.r7_e16
{
  LDY r7_i0
  LDX r7_i1
  LDA R_PYL,Y             \ going down? (y0 < y1)
  CMP R_PYL,X
  LDA R_PYH,Y
  SBC R_PYH,X
  BVC v1
  EOR #&80
.v1
  BPL out
  LDA R_PYH,X             \ end row = min(y1, yend)
  BMI out
  BNE e0
  LDA R_PYL,X
  CMP r_yend
  BCC e1
.e0
  LDA r_yend
.e1
  STA RZ_T2
  LDA R_PYH,Y             \ start row = max(y0, ystart)
  BMI s0
  BNE out
  LDA R_PYL,Y
  CMP r_ystart
  BCS s1
.s0
  LDA r_ystart
.s1
  STA RZ_T3
  CMP RZ_T2
  BCC go
.out
  RTS
.go
  STA RZ_Y
  JSR r7_esgen             \ (side r7_side4: always 0)             \ S, t -> RZ_SA, RZ_TA; a, b, dy -> r7_ea, r7_eb, r7_edy
  LDY r7_i0                \ both ends' x inside CL..CR+1 and dy < 256:
  LDX r7_i1                \ the 8-bit DDA
  LDA r7_edy+1
  BNE gen
  LDA R_PXH,Y
  ORA R_PXH,X
  BNE gen
  LDA R_PXL,Y
  CMP R_CL
  BCC gen
  CMP r_cr1
  BEQ x1
  BCS gen
.x1
  LDA R_PXL,X
  CMP R_CL
  BCC gen
  CMP r_cr1
  BEQ x2
  BCS gen
.x2
  LDA RZ_SA
  STA RZ_T0
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  CPX #0
  BNE sh
  JMP r_pzl1
.sh
  JMP r_psh1
.gen                      \ general: 16-bit S, t; x clamped into CL..CR+1
  LDA r7_eb
  STA bl+1
  LDA r7_eb+1
  STA bh+1
  LDA r7_edy
  STA dl+1
  LDA r7_edy+1
  STA dh+1
  LDA r7_ea
  STA al+1
  LDA r7_ea+1
  STA ah+1
  LDA RZ_T2
  STA ye+1
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_T4               \ bit 7: the far end is inside CL..CR+1 and dy < 256,
  LDX r7_i1                \ so once inside, x stays inside: the 8-bit DDA
  LDA r7_edy+1
  BNE g1
  LDA R_PXH,X
  BNE g1
  LDA R_PXL,X
  CMP R_CL
  BCC g1
  CMP r_cr1
  BEQ g0
  BCS g1
.g0
  DEC RZ_T4
.g1
  LDY RZ_T3
.lp
  LDA RZ_SA+1
  BMI lo
  BNE hi
  LDA RZ_SA
  CMP R_CL
  BCC lo
  CMP r_cr1
  BCC inw
.hi
  BIT r7_ea+1              \ right of the window, moving right: stays there
  BPL fh
  LDA r_cr1
  BNE st                  \ (always: CR + 1 >= 2)
.lo
  BIT r7_ea+1              \ left of it, moving left: stays there
  BMI fl
  LDA R_CL
.st
.^r7_x16_t
  STA &FF00 + LO(r_ta),Y
  INY
.ye
  CPY #0
  BCS done
  LDA RZ_TA               \ t -= b; borrow: t += dy, S += 1
  SEC
.bl
  SBC #0
  STA RZ_TA
  LDA RZ_TA+1
.bh
  SBC #0
  STA RZ_TA+1
  BCS nb
  LDA RZ_TA
.dl
  ADC #0
  STA RZ_TA
  LDA RZ_TA+1
.dh
  ADC #0
  STA RZ_TA+1
  BCS ad                  \ (always: t + dy >= 0 carries; C = 1 for S += 1)
.nb
  CLC
.ad
  LDA RZ_SA               \ S += a
.al
  ADC #0
  STA RZ_SA
  LDA RZ_SA+1
.ah
  ADC #0
  STA RZ_SA+1
  JMP lp                  \ (NMOS: no BRA)
.done
  RTS
.fh
  LDA r_cr1
  BNE fi                  \ (always: CR + 1 >= 2)
.fl
  LDA R_CL
.fi
.^r7_x16_f
  STA &FF00 + LO(r_ta),Y
  INY
  CPY ye+1
  BCC fi
  RTS
.inw
  BIT RZ_T4
  BMI sw
  JMP st
.sw                       \ inside for good: the 8-bit DDA from row Y
  STA RZ_T0
  STY RZ_T3
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  CPX #0
  BNE sw1
  JMP r_pzl1
.sw1
  JMP r_psh1
}

\ ----------------------------------------------------------------------------
\ r7_esgen: set up edge r7_i0 -> r7_i1 (y1 > row >= y0) for side r7_side4 at row
\ RZ_Y: x = x0 + ceil(dx*k/dy) with k = row - y0, kept as S and error t with
\ dx*k = dy*(S-x0) - t, 0 <= t < dy; per row S += a, t -= b (a = floor(dx/dy),
\ b = dx - a*dy), borrow: t += dy, S += 1.  Installs a, b, dy into the row loop.
\ ----------------------------------------------------------------------------
.r7_esgen                  \ Y = r7_i0, X = r7_i1
{
  SEC
  LDA R_PYL,X
  SBC R_PYL,Y
  STA r7_edy
  LDA R_PYH,X
  SBC R_PYH,Y
  STA r7_edy+1
  SEC
  LDA RZ_Y
  SBC R_PYL,Y
  STA r7_ek0
  LDA #0
  SBC R_PYH,Y
  STA r7_ek0+1
  LDA R_PXL,Y
  STA r7_ex0
  LDA R_PXH,Y
  STA r7_ex0+1
  SEC
  LDA R_PXL,X
  SBC R_PXL,Y
  STA r7_eadx
  LDA R_PXH,X
  SBC R_PXH,Y
  STA r7_eadx+1
  STA r7_eneg             \ (NMOS: bit 7: dx < 0, from dx's high byte; no
  BPL pos                 \ STZ, DEC)
  SEC
  LDA #0
  SBC r7_eadx
  STA r7_eadx
  LDA #0
  SBC r7_eadx+1
  STA r7_eadx+1
.pos
  \ q, r = adx / dy
  LDA r7_eadx
  CMP r7_edy
  LDA r7_eadx+1
  SBC r7_edy+1
  BCS ndiv
  LDA r7_eadx
  STA r7_er
  LDA r7_eadx+1
  STA r7_er+1
  LDA #0                  \ (NMOS: no STZ)
  STA r7_eq
  STA r7_eq+1
  BEQ ddone               \ (always)
.ndiv
  LDA r7_eadx+1
  ORA r7_edy+1
  BNE d16
  LDA r7_edy
  STA r_v0                \ (bank 5's r_div8, which uses r_v0 and r_m0)
  LDA r7_eadx
  JSR r_div8
  STA r7_er
  STX r7_eq               \ (NMOS: X = r_m0, the quotient, from r_div8)
  LDA #0
  STA r7_er+1
  STA r7_eq+1
  BEQ ddone               \ (always)
.d16
  LDA r7_eadx
  STA rp_m0
  LDA r7_eadx+1
  STA rp_m1
  LDA #0                  \ (NMOS: no STZ)
  STA rp_m2
  STA rp_m3
  LDA r7_edy
  STA rp_v0
  LDA r7_edy+1
  STA rp_v1
  JSR rp_div32
  LDA rp_m0
  STA r7_eq
  LDA rp_m1
  STA r7_eq+1
  LDA rp_m2
  STA r7_er
  LDA rp_m3
  STA r7_er+1
.ddone
  LDA r7_eneg
  BMI negab
  LDA r7_eq
  STA r7_ea
  LDA r7_eq+1
  STA r7_ea+1
  LDA r7_er
  STA r7_eb
  LDA r7_er+1
  STA r7_eb+1
  JMP abdone              \ (NMOS: no BRA)
.negab
  LDA r7_er
  ORA r7_er+1
  BNE rnz
  SEC                     \ a = -q, b = 0
  LDA #0
  STA r7_eb               \ (NMOS: from the LDA #0, no STZ)
  STA r7_eb+1
  SBC r7_eq
  STA r7_ea
  LDA #0
  SBC r7_eq+1
  STA r7_ea+1
  BCC abdone              \ (always: q >= 1, as r = 0 and adx >= 1)
.rnz
  LDA r7_eq                \ a = -q-1, b = dy - r
  EOR #&FF
  STA r7_ea
  LDA r7_eq+1
  EOR #&FF
  STA r7_ea+1
  SEC
  LDA r7_edy
  SBC r7_er
  STA r7_eb
  LDA r7_edy+1
  SBC r7_er+1
  STA r7_eb+1
.abdone
  LDX r7_side4
  LDA r7_ek0
  ORA r7_ek0+1
  BNE k0nz
  LDA r7_ex0
  STA RZ_SA,X
  LDA r7_ex0+1
  STA RZ_SA+1,X
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_TA,X
  STA RZ_TA+1,X
  RTS                     \ (NMOS: not JMP install)
.k0nz                     \ clipped start: q2, r2 = adx*k / dy
  LDA r7_eadx
  STA rp_ma
  LDA r7_eadx+1
  STA rp_ma+1
  LDA r7_ek0
  STA rp_mb
  LDA r7_ek0+1
  STA rp_mb+1
  JSR rp_mul16
  LDA r7_edy
  STA rp_v0
  LDA r7_edy+1
  STA rp_v1
  JSR rp_div32
  LDX r7_side4
  LDA r7_eneg
  BMI kneg
  LDA rp_m2
  ORA rp_m3
  BEQ kz
  SEC                     \ S = x0 + q2 + 1, t = dy - r2
  LDA r7_ex0
  ADC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  ADC rp_m1
  STA RZ_SA+1,X
  SEC
  LDA r7_edy
  SBC rp_m2
  STA RZ_TA,X
  LDA r7_edy+1
  SBC rp_m3
  STA RZ_TA+1,X
  RTS                     \ (NMOS: not JMP install)
.kz
  CLC                     \ S = x0 + q2, t = 0
  LDA r7_ex0
  ADC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  ADC rp_m1
  STA RZ_SA+1,X
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_TA,X
  STA RZ_TA+1,X
  RTS                     \ (NMOS: not JMP install)
.kneg
  SEC                     \ S = x0 - q2, t = r2
  LDA r7_ex0
  SBC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  SBC rp_m1
  STA RZ_SA+1,X
  LDA rp_m2
  STA RZ_TA,X
  LDA rp_m3
  STA RZ_TA+1,X
.install
  RTS
}

