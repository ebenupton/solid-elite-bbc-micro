\ Port (Model B): copied from the Tube branch's master/src/gfx-raster_arith.asm (the BBC
\ Master port's rasteriser, with its _HOSTB support for a Model B host), for
\ bank R; made NMOS at build time by 2-build-files/nmos.py (bankr.sh). Notes
\ marked Port (bank R) are this copy's changes.

\ (gfx-raster.asm's polygon arithmetic, its own file so that the Tube's
\ parasite can assemble it for its phase A: tube/src/p-polya.asm)
\ ----------------------------------------------------------------------------
\ The polygon window's arithmetic (R_POLY's phase A, gfx-raster_poly.asm),
\ here for room: r_div8, r_dvq and the 32-bit multiply and divide with their
\ variables (none uses anything of the polygon window's)
\ ----------------------------------------------------------------------------
\ r_div8: A / r_v0 -> r_m0 quotient, A remainder (clobbers X).
.r_div8
{
  STA RZ_T6               \ dividend, becoming the quotient
  LDA r_v0
  STA RZ_T7
  LDA #0
  LDX #8
.lp
  ASL RZ_T6
  ROL A
  BCS sb
  CMP RZ_T7
  BCC ns
.sb
  SBC RZ_T7
  INC RZ_T6
.ns
  DEX
  BNE lp
  LDX RZ_T6
  STX r_m0
  RTS
}

\ r_dvq: A / RZ_T1 (A >= RZ_T1 >= 1) -> r_m0 quotient, A remainder.
\ Repeated subtraction when the quotient is small (divisor >= 16).
.r_dvq
{
  LDX RZ_T1
  CPX #16
  BCC small
  LDX #&FF                \ divisor >= 16: quotient < 16
  SEC
.lp
  INX
  SBC RZ_T1
  BCS lp
  ADC RZ_T1
  STX r_m0
  RTS
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
  STX r_m0
  RTS
.long
  LDA RZ_T6
  LDX RZ_T1
  STX r_v0
  JMP r_div8
}
\ the 32-bit multiply and divide
.rp_m0 EQUB 0           \ 32-bit dividend / product; quotient m0,m1
.rp_m1 EQUB 0
.rp_m2 EQUB 0           \ remainder m2,m3
.rp_m3 EQUB 0
.rp_v0 EQUB 0           \ divisor
.rp_v1 EQUB 0
.rp_ma EQUW 0           \ multiplicand
.rp_mb EQUW 0           \ multiplier
.rp_mul16
{
  LDA #0
  STA rp_m2
  STA rp_m3
  LDX #16
.lp
  LSR rp_mb+1
  ROR rp_mb
  BCC ns
  CLC
  LDA rp_m2
  ADC rp_ma
  STA rp_m2
  LDA rp_m3
  ADC rp_ma+1
  STA rp_m3
.ns
  ROR rp_m3
  ROR rp_m2
  ROR rp_m1
  ROR rp_m0
  DEX
  BNE lp
  RTS
}
.rp_div32
{
  LDX #16
.lp
  ASL rp_m0
  ROL rp_m1
  ROL rp_m2
  ROL rp_m3
  BCS sb
  LDA rp_m2
  CMP rp_v0
  LDA rp_m3
  SBC rp_v1
  BCC ns
.sb
  LDA rp_m2
  SBC rp_v0
  STA rp_m2
  LDA rp_m3
  SBC rp_v1
  STA rp_m3
  INC rp_m0
.ns
  DEX
  BNE lp
  RTS
}

