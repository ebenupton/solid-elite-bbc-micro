\ ******************************************************************************
\
\ gfx-raster_dpatch.asm - dp_patch, the disc layer's painter's operands for a
\ buffer (gfx-raster_disc.asm, gfx-raster_disc2.asm: the r_p sites)
\
\ Port (Model B): as the Master port's R_SETBUF and r_dbm patch them: each
\ buffer's arrays are the same but for their high bytes (buffer 1's are
\ buffer 0's + &300, gfx-raster_disc.asm). X = the buffer.
\
\       Area: bank 7
\
\ ******************************************************************************

.dp_patch
 LDA dp_hpsl,X             \ R_DISCL
 STA r_psl20+2
 STA r_psl21+2
 STA r_psl22+2
 STA r_psl23+2
 STA r_psl24+2
 STA r_psl25+2
 STA r_psl26+2
 STA r_psl27+2
 STA r_psl28+2
 STA r_psl29+2
 STA r_psl30+2
 STA r_psl31+2
 STA r_psl32+2
 STA r_psl33+2
 STA r_psl40+2
 STA r_psl41+2
 STA r_psl42+2
 STA r_psl43+2
 LDA dp_hpsr,X             \ R_DISCR
 STA r_psr20+2
 STA r_psr21+2
 STA r_psr22+2
 STA r_psr24+2
 STA r_psr27+2
 STA r_psr28+2
 STA r_psr29+2
 STA r_psr30+2
 STA r_psr32+2
 STA r_psr33+2
 STA r_psr40+2
 STA r_psr41+2
 STA r_psr42+2
 STA r_psr43+2
 LDA dp_hp2l,X             \ R_S2L
 STA r_p2l20+2
 STA r_p2l22+2
 STA r_p2l23+2
 STA r_p2l24+2
 STA r_p2l25+2
 STA r_p2l26+2
 LDA dp_hp2r,X             \ R_S2R
 STA r_p2r20+2
 STA r_p2r22+2
 STA r_p2r23+2
 STA r_p2r24+2
 STA r_p2r25+2
 STA r_p2r26+2
 LDA dp_hpbn,X             \ R_BDN
 STA r_pbn20+2
 STA r_pbn21+2
 STA r_pbn22+2
 STA r_pbn23+2
 STA r_pbn24+2
 STA r_pbn25+2
 STA r_pbn26+2
 STA r_pbn27+2
 STA r_pbn28+2
 STA r_pbn29+2
 STA r_pbn30+2
 LDA dp_hpb0,X             \ R_BDX0
 STA r_pb020+2
 STA r_pb021+2
 STA r_pb022+2
 STA r_pb023+2
 STA r_pb024+2
 STA r_pb025+2
 STA r_pb026+2
 STA r_pb027+2
 LDA dp_hpb1,X             \ R_BDX1
 STA r_pb120+2
 STA r_pb121+2
 STA r_pb122+2
 STA r_pb123+2
 STA r_pb124+2
 STA r_pb125+2
 STA r_pb126+2
 STA r_pb127+2
 LDA dp_hpb2,X             \ R_BDX2
 STA r_pb220+2
 STA r_pb221+2
 STA r_pb222+2
 STA r_pb223+2
 STA r_pb224+2
 STA r_pb225+2
 STA r_pb226+2
 STA r_pb227+2
 LDA dp_hscr,X           \ the screen (r_rowp)
 STA dp_scr+1
 RTS
.dp_hpsl EQUB HI(R_DISCL0), HI(R_DISCL1)
.dp_hpsr EQUB HI(R_DISCR0), HI(R_DISCR1)
.dp_hp2l EQUB HI(R_S2L0), HI(R_S2L1)
.dp_hp2r EQUB HI(R_S2R0), HI(R_S2R1)
.dp_hpbn EQUB HI(R_BDN0), HI(R_BDN1)
.dp_hpb0 EQUB HI(R_BDX00), HI(R_BDX01)
.dp_hpb1 EQUB HI(R_BDX10), HI(R_BDX11)
.dp_hpb2 EQUB HI(R_BDX20), HI(R_BDX21)
.dp_hscr EQUB HI(BUF0), HI(SCREEN%)
