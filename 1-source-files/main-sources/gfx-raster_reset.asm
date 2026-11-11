\ ============================================================================
\ raster_reset.asm -- R_RESETBUF (T_RESETBUF, R_INIT) and r7_reset1 (bank 5,
\ in the room below the per-x tables, after gfx-raster_lcold.asm)
\
\       Area: bank 5 gap
\ ============================================================================
\ ============================================================================
\ R_RESETBUF: the current buffer's state, not the screen
\ ============================================================================
.R_RESETBUF
{
  LDY #191
  LDX R_PRBUF
  BNE b1
.c0
  LDA #&FF
  STA R_DIRTYL0,Y
  LDA #0
  STA R_DIRTYR0,Y
  DEY
  CPY #&FF
  BNE c0
  BEQ done                \ (NMOS: always)
.b1
  LDA #&FF
  STA R_DIRTYL1,Y
  LDA #0
  STA R_DIRTYR1,Y
  DEY
  CPY #&FF
  BNE b1
.done
  JMP r7_reset1
}
\ r7_reset1: buffer X's scalars (keeps X)
.r7_reset1
  LDA #&FF
  STA R_PRDYT,X
  LDA #0
  STA R_PRDYB,X
  STA R_PRSCNT,X
  RTS

