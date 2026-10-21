\ Port (Model B): copied from the Tube branch's master/src/gfx-raster_rep.asm (the BBC
\ Master port's rasteriser, with its _HOSTB support for a Model B host), for
\ bank R; made NMOS at build time by 2-build-files/nmos.py (bankr.sh). Notes
\ marked Port (bank R) are this copy's changes.

\ ============================================================================
\ raster_rep.asm -- r7_rowrep, the repair of dirty rows that are no disc rows
\ (black through the row runs), split from gfx-raster_disc.asm (which
\ INCLUDEs it) so that the Tube's Model B host can put it with the runs, in
\ its bank P (tube/src/hb-p.asm)
\ ============================================================================

IF _HOSTB AND _RBANK = 2   \ (Model B, bank P: gfx-raster_disc.asm's equates)
c_L   = &18
c_R   = &19
c_NL  = &1A
c_YE  = &1E
c_M   = &23
c_CO  = &22
ENDIF
\ r7_rowrep: rows Y .. c_YE - 1 (see above)
.r7_rowrep
{
  LDX R_PRBUF
  LDA dlh,X
  STA ld1+2
  STA sd1+2
  STA fl1+2
  STA fs1+2
  LDA drh,X
  STA ld2+2
  STA sd2+2
  STA fl2+2
  STA fs2+2
.frow                     \ fast path: extent inside columns 1..62
.fl2
  LDA R_DIRTYR0,Y
  BEQ fnx
  CMP #252
  BCS slow
  TAX
  ORA #3
  STA R_WR,Y
  LDA r_j,X             \ plant the RTS after column R DIV 4
  STA RZ_PP
.fl1
  LDA R_DIRTYL0,Y
  AND #&FC                \ L AND &FC = 0 <=> L < 4
  BEQ slow
  STA R_WL,Y
  TAX
  LDA r_j-4,X           \ enter at column L DIV 4
  STA fj+1
  LDA #&FF
.fs1
  STA R_DIRTYL0,Y
  TYA                     \ the run page of row Y
  LSR A
  LSR A
  LSR A
  ORA #HI(r_run0)         \ (= ADC: Y DIV 8 < 32)
IF _HOSTB
  JSR r_pgfix             \ (Model B: the page for the buffer)
ENDIF
  STA fj+2
  STA RZ_PP+1
  LDA #&60
  STA (RZ_PP)
  LDA #0
.fs2
  STA R_DIRTYR0,Y
.fj
  JSR &FFFF               \ patched: straight into the row run (the run keeps Y)
  LDA #r_opSTA
  STA (RZ_PP)
.fnx
  INY
  CPY c_YE
  BCC frow
  RTS
.slow                     \ an end in column 0 or 63: the general row code
  JSR row1
  BRA fnx
\ row1: row Y, general (the border columns' bytes masked)
.row1
.ld2
  LDA R_DIRTYR0,Y
  STA c_R
  ORA #3
  STA R_WR,Y
.ld1
  LDX R_DIRTYL0,Y
  STX c_L
  TXA
  AND #&FC
  STA R_WL,Y
  LDA #&FF
.sd1
  STA R_DIRTYL0,Y
  LDA #0
.sd2
  STA R_DIRTYR0,Y
  TXA                     \ first byte column (0: the border's)
  LSR A
  LSR A
  BEQ e0
.nl1
  STA c_NL
  LDA c_R                 \ last byte column (63: the border's)
  LSR A
  LSR A
  CMP #63
  BEQ e63
.nr1
  INC A
  CMP c_NL
  BEQ nx
  BCC nx
  TAX                     \ plant the RTS at column NR
  LDA r7_j3,X
  STA RZ_PP
  TYA                     \ the run page of row Y
  LSR A
  LSR A
  LSR A
  ORA #HI(r_run0)         \ (= ADC: Y DIV 8 < 32)
IF _HOSTB
  JSR r_pgfix             \ (Model B: the page for the buffer)
ENDIF
  STA RZ_PP+1
  STA rj+2
  LDX c_NL
  LDA r7_j3,X
  STA rj+1
  LDA #&60
  STA (RZ_PP)
  STY RZ_Y
  LDA #0
  JSR rj
  LDA #r_opSTA
  STA (RZ_PP)
  LDY RZ_Y
.nx
  RTS
.rj
  JMP &FFFF
.e0
  STY RZ_Y
  JSR edge0
  LDY RZ_Y
  LDA #1
  BRA nl1
.e63
  STY RZ_Y
  JSR edge63
  LDY RZ_Y
  LDA #62
  BRA nr1
\ edge0 / edge63: black pixels c_L .. c_R of row RZ_Y within column 0 / 63
.edge0
  LDX c_R
  CPX #4
  BCC e0a
  LDX #3
.e0a
  LDA r_rm,X
  LDX c_L
  AND r_lm,X
  LDX #0
  BRA eg
.edge63
  LDA c_L
  CMP #252
  BCS e6a
  LDA #252
.e6a
  AND #3
  TAX
  LDA c_R                 \ (>= 252)
  AND #3
  TAY
  LDA r_lm,X
  AND r_rm,Y
  LDX #&F8
.eg
  EOR #&FF
  STA c_M
  STX c_CO
  LDA RZ_Y
  AND #7
  ORA c_CO
  STA RZ_PA
  LDA RZ_Y
  LSR A
  LSR A
  AND #&FE
IF _HOSTB
  CLC
.^r_bs7
  ADC #&40
ELSE
  ORA #&40
ENDIF
  CPX #0
  BEQ eg1
  INC A
.eg1
  STA RZ_PA+1
  LDA (RZ_PA)
  AND c_M
  STA (RZ_PA)
  RTS
.dlh EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.drh EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
}



\ the repair's run offset of byte column k (1..63; r7_rowrep's row1)
.r7_j3                    \ run offset of byte column k (1..63)
FOR k, 0, 63
  EQUB LO(3 * (k - 1))
NEXT


