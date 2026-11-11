\ ============================================================================
\ raster_lcold.asm -- R_LINE's cold part (gfx-raster_line.asm, in the
\ polygon window), here in the shared region for room: rl_mdq, rl_mdqa (the
\ multiply-divide rl_gen's exact clipping uses, on the shared region's
\ rp_mul16 and rp_div32) and rl_long (lines with d > 255).  They use the
\ shared region (the arithmetic, r_pset, R_LINE's variables in a run page's
\ tail) and the zero page, nothing of the polygon window's.  INCLUDE it in
\ bank 5's assembly, after gfx-raster.asm (elite-gfx.asm: in the room below
\ the per-x tables, from r_tfree).
\
\       Area: bank 5 gap
\ ============================================================================

\ rl_mdqa: rl_mdq with rp_mb = d and rp_v = a (rl_gen's rl_i and rl_j bounds);
\ falls into rl_mdq
.rl_mdqa
  LDA rl_d
  STA rp_mb
  LDA rl_d+1
  STA rp_mb+1
  LDA rl_a
  STA rp_v0
  LDA rl_a+1
  STA rp_v1
\ rl_mdq: (rp_ma * rp_mb + rl_t) DIV / MOD rp_v -> quotient rp_m0,m1,
\ remainder rp_m2,m3 (rl_t signed; the quotient must fit 16 bits).  Clobbers
\ rp_mb.
.rl_mdq
{
  JSR rp_mul16
  CLC
  LDA rp_m0
  ADC rl_t
  STA rp_m0
  LDA rp_m1
  ADC rl_t+1
  STA rp_m1
  LDX #0                  \ rl_t's sign, extended
  LDA rl_t+1
  BPL p
  DEX
.p
  TXA
  ADC rp_m2
  STA rp_m2
  TXA
  ADC rp_m3
  STA rp_m3
  JMP rp_div32
}

\ rl_long: rl_gen's line with d > 255, pixel by pixel from the first pixel
\ inside the window (l_x0, l_y0), l_n pixels, with the 16-bit error term e =
\ r - d (A = its high byte, l_e its low byte; rl_t holds it)
.rl_long
{
  STA rl_t+1
  LDA l_e
  STA rl_t
  LDA rl_mo                \ X = the major axis (0 = x, 1 = y: l_x0,X), kept
  LSR A                   \ in l_e (NMOS: no PHX/PLX; rl_t has e now)
  STA l_e
  BPL lp                  \ (always)
.md
  DEC l_x0,X
.lp
  LDX l_x0
  LDY l_y0
  JSR r_pset
  LDX l_e
  DEC l_n
  BEQ done
  INC l_x0,X              \ major step
  CLC                     \ e += a
  LDA rl_t
  ADC rl_a
  STA rl_t
  LDA rl_t+1
  ADC rl_a+1
  STA rl_t+1
  BMI lp
  SEC                     \ e >= 0: e -= d, minor step
  LDA rl_t
  SBC rl_d
  STA rl_t
  LDA rl_t+1
  SBC rl_d+1
  STA rl_t+1
  TXA
  EOR #1
  TAX
  BIT rl_s
  BMI md                  \ (the minor step; X is reloaded at lp)
  INC l_x0,X
  JMP lp
.done
  RTS
}

\ The rasteriser's private state (only the rasteriser reads or writes it, and
\ R_INIT sets it up)
.R_PRBUF    SKIP 1          \ the current buffer
.R_PRDYT    SKIP 2          \ per buffer: the rows that may have a dirty extent
.R_PRDYB    SKIP 2
.R_PRSCNT   SKIP 2          \ per buffer: star records
.R_PRECNT   SKIP 2          \ per buffer: star records erased, not yet in WL
.R_PRWT     SKIP 1          \ the rows of WL/WR that may be non-empty
.R_PRWB     SKIP 1

