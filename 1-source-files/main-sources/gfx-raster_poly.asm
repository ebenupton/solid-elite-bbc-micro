\ Port (Model B): copied from the Tube branch's master/src/gfx-raster_poly.asm (the BBC
\ Master port's rasteriser, with its _HOSTB support for a Model B host), for
\ bank R; made NMOS at build time by 2-build-files/nmos.py (bankr.sh). Notes
\ marked Port (bank R) are this copy's changes.

\ ============================================================================
\ raster_poly.asm -- the rasteriser's polygon window: R_POLY (both phases;
\ phase A for 16-bit coordinates, r7_pf16, came from bank 7), in ANDY
\ (ROMSEL &85: ANDY over bank 5's &8000-&8FFF; bank 5's &9000-&BFFF, the
\ shared region gfx-raster.asm, stays visible: its arithmetic, r_div8,
\ r_dvq, rp_mul16 and rp_div32, is there).  The frame layer's T_POLY
\ pages it in.  R_SETBUF (shared) pages it in to patch phase B's DIRTY
\ operands.  INCLUDE it at &8000 in an assembly of its own (ANDY), after
\ gfx-raster.asm.
\ ============================================================================

\ ============================================================================
\ R_POLY
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
  \ fast path when every high byte is zero
  TAX
  DEX
  LDA #0
.hl
  ORA R_PXH,X
  ORA R_PYH,X
  DEX
  BPL hl
  TAX
  BNE p16
  JMP r_pf8
.p16                      \ some coordinate outside 0..255: phase A (r7_pf16)
  JSR r7_pf16
  CMP #0                  \ (A = 0: nothing to draw)
  BEQ out
IF _TPART = 1
  JMP p_spans             \ (Tube: the tables to the host, tube/src/p-polya.asm)
ELSE
  JMP r_pcbd
ENDIF
.out
  RTS
}

\ ============================================================================
\ R_POLY 8-bit path: every vertex x, y in 0..255.
\ Phase A walks both chains from the top vertex, running each edge's exact
\ DDA (x = x0 + ceil(dx*k/dy)) down a per-row table: chain A (forward) into
\ r_ta, chain B (backward) into r_tb.  Phase B fills each row from the left
\ table to the right one (exclusive), keeping the RTS planted in the current
\ character row's store run until its position changes.
\ ============================================================================
.r_pf8
{
  LDA R_CR
  INC A
  STA r_cr1
  LDX r_n
  DEX
  STX r_top
  LDA R_PYL,X
  STA r_yminL
  STA r_ymaxL
  STZ r_xclip
.sc
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
  BPL sc
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
  LDA r_ymaxL
  DEC A
  CMP R_CB
  BCC y3
  LDA R_CB
.y3
  STA r_ylast
  INC A
  STA r_yend
  \ chain A: forward into r_ta
  LDA #LO(r_ta)
  STA r_lsh_t+1
  STA r_lz_t+1
  LDA #HI(r_ta)
  STA r_lsh_t+2
  STA r_lz_t+2
  LDA r_n
  STA r_cc
  LDX r_top
.ca
  LDA R_PYL,X
  CMP r_ymaxL
  BEQ cad
  DEC r_cc
  BMI cad
  STX r_i0
  INX
  CPX r_n
  BCC ca1
  LDX #0
.ca1
  STX r_i1
  JSR r_e8
  LDX r_i1
  BRA ca
.out
  RTS
.cad
  \ chain B: backward into r_tb
  LDA #LO(r_tb)
  STA r_lsh_t+1
  STA r_lz_t+1
  LDA #HI(r_tb)
  STA r_lsh_t+2
  STA r_lz_t+2
  LDA r_n
  STA r_cc
  LDX r_top
.cb
  LDA R_PYL,X
  CMP r_ymaxL
  BEQ cbd
  DEC r_cc
  BMI cbd
  STX r_i0
  DEX
  BPL cb1
  LDX r_n
  DEX
.cb1
  STX r_i1
  JSR r_e8
  LDX r_i1
  BRA cb
.cbd
IF _TPART = 1
  JMP p_spans             \ (Tube: the rest is the host's)
}
ELSE
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
  LDX #0
  BRA ori
.bleft
  LDX #2
.ori
  LDA otab,X
  STA r_pbl1_e+1
  STA r_pbl1_o+1
  LDA otab+1,X
  STA r_pbl1_e+2
  STA r_pbl1_o+2
  LDA otab+2,X
  STA r_pbr1_e+1
  STA r_pbr2_e+1
  STA r_pbr1_o+1
  STA r_pbr2_o+1
  LDA otab+3,X
  STA r_pbr1_e+2
  STA r_pbr2_e+2
  STA r_pbr1_o+2
  STA r_pbr2_o+2
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
  BRA tb
.tb1
  STY r_ylast
  INY
  STY r_yend
  \ this buffer's dirty row range
  LDX r_buf
  LDA r_ystart
  CMP r_dyt,X
  BCS d1
  STA r_dyt,X
.d1
  LDA r_ylast
  CMP r_dyb,X
  BCC d2
  STA r_dyb,X
.d2
  \ phase B set-up
  LDY r_ystart
  JSR r_rowset
  LDA RZ_PP+1
  STA r_jsr2_e+2
  STA r_jsr2_o+2
  LDA r_yend
  STA pb_ye_e+1
  STA pb_ye_o+1
  LDA #190                \ nothing planted
  STA RZ_PP
  LDA R_COLE              \ rows 4k, 4k+1 take COLE, COLO; rows 4k+2, 4k+3
  EOR R_COL2              \ COL2, COL3: RZ_CE/RZ_CO = this row pair's, toggled
  STA RZ_XE               \ by RZ_XE/RZ_XO at each pair
  LDA R_COLO
  EOR R_COL3
  STA RZ_XO
  TYA
  AND #2
  BEQ p01
  LDA R_COL2
  LDX R_COL3
  BRA pc
.p01
  LDA R_COLE
  LDX R_COLO
.pc
  STA RZ_CE
  STX RZ_CO
  TYA
  LSR A
  BCC ev
  JMP r_pbx_o             \ odd first row (Y = RZ_Y)
.ev
  JMP r_pbx_e             \ even first row
.otab
  EQUW r_ta, r_tb, r_ta
}
ENDIF

IF _TPART <> 1
 INCLUDE "3-assembled-output/nmos/gfx-raster_polyb.asm"
ENDIF
