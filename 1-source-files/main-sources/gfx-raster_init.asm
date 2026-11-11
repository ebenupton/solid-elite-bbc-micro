\ ============================================================================
\ raster_init.asm -- R_INIT, the rasteriser's set-up, run once (T_INIT, from
\ F_INIT)
\
\       Area: bank 5
\ ============================================================================
.R_INIT
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

