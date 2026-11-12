\ ============================================================================
\ raster_init.asm -- R_INIT, the rasteriser's set-up, run once (T_INIT, from
\ F_INIT): it makes the row runs (below), then sets up the state (r_setup)
\
\       Area: bank 5
\ ============================================================================
.r_setup
{
  LDA #1
  STA R_CL
  STA R_CT
.ib                       \ buffer 1's state, then buffer 0's (each R_SETBUF
  PHA                     \ patching, as R_PRBUF starts as 0), ending with 0
  JSR R_SETBUF            \ (NMOS: here, with A = 1 from above, and ended by
  JSR R_RESETBUF          \ LSR A, not DEC A; they use nothing set below)
  PLA
  LSR A
  BCS ib
  STA R_SN                \ (NMOS: A = 0, no STZ)
  STA R_PN
  STA R_PRWB
  LDA #254
  STA R_CR
  LDA #191
  STA R_CB
  LDA #&FF
  STA R_SCOL
  STA R_PRWT
  LDX #192
.il
  LDA #&FF
  STA R_WL-1,X
  LDA #0                  \ (NMOS: no STZ)
  STA R_WR-1,X
  DEX
  BNE il
  RTS
}

\ ============================================================================
\ R_INIT: make the 24 row runs (gfx-raster.asm), which R.BANK does not
\ carry: in run page r, STA &4000 + &200 r + 8 c - 8 r, Y for c = 1 to 63,
\ an RTS and a 0, for buffer 1 (as r_pgtag has them); row r + 1's first
\ store is row r's last + 8. Then R_LINE's buffer (none yet) and the state.
\
\       Area: bank 5 end
\ ============================================================================
.R_INIT
{
  LDA #LO(&4008)          \ RZ_T0(1 0) = row 0's first store's address
  STA RZ_T0
  LDA #HI(&4008)
  STA RZ_T1
  LDA #0                  \ RZ_PP(1 0) = run page 0
  STA RZ_PP
  LDA #HI(r_run0)
  STA RZ_PP+1
.pg
  LDY #0
.st
  LDA #r_opSTA            \ STA RZ_T0(1 0),Y
  STA (RZ_PP),Y
  INY
  LDA RZ_T0
  STA (RZ_PP),Y
  INY
  LDA RZ_T1
  STA (RZ_PP),Y
  INY
  LDA RZ_T0               \ the next store's address, 8 on
  CLC
  ADC #8
  STA RZ_T0
  BCC nc
  INC RZ_T1
.nc
  CPY #R_RUNSZ - 2
  BNE st
  LDA #r_opRTS            \ the RTS and the spare 0
  STA (RZ_PP),Y
  INY
  LDA #0
  STA (RZ_PP),Y
  INC RZ_PP+1             \ the next row's page
  LDA RZ_PP+1
  CMP #HI(r_run0) + 24
  BNE pg
  LDA #&FF                \ R_LINE's DIRTY operands are for no buffer yet
  STA rl_lbuf
  JMP r_setup
}
