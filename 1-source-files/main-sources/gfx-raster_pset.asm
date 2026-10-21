\ Port (Model B): copied from the Tube branch's master/src/gfx-raster_pset.asm (the BBC
\ Master port's rasteriser, with its _HOSTB support for a Model B host), for
\ bank R; made NMOS at build time by 2-build-files/nmos.py (bankr.sh). Notes
\ marked Port (bank R) are this copy's changes.

\ r_pset (gfx-raster.asm's; its own file so that the Tube's Model B host can
\ place it out of run page 15's tail, where its NMOS code does not fit)
.r_pset
{
  TYA                     \ RZ_PP = screen address of (X, Y)
  AND #7
  ORA r_xo,X
  STA RZ_PP
  TYA
  LSR A
  LSR A
  AND #&FE
IF _HOSTB
  CLC
.^r_bs2
  ADC #&40
ELSE
  ORA #&40
ENDIF
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDA r_lm,X
  AND r_rm,X
  STA RZ_T6
  TYA
  LSR A
  LDA R_COLE
  BCC ev
  LDA R_COLO
.ev
  EOR (RZ_PP)
  AND RZ_T6
  EOR (RZ_PP)
  STA (RZ_PP)
  TXA
.^r_pt01 CMP r_dl,Y
  BCS n1
.^r_pt02 STA r_dl,Y
.n1
.^r_pt03 CMP r_dr,Y
  BCC n2
.^r_pt04 STA r_dr,Y
.n2
  RTS
}
