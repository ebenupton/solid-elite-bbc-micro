\ ******************************************************************************
\
\ gfx-frame_cold.asm - the frame layer's bookkeeping for screens drawn directly
\ (outside record mode, i.e. QQ11 or GFORCE non-zero), and for those that
\ then carry on in record mode without a TT66: DEATH and TITLE (TT66 13,
\ whose TTX66 may print the hyperspace countdown directly, then QQ11 = 0)
\ and the briefing's LL9B. FRAME must know what text buffer 0 (BUF0)
\ already shows.
\
\ Port (Model B): the BBC Master port's gfx-frame_cold.asm (in NMOS 6502
\ code), INCLUDEd in bank 6 after the frame layer (gfx-bank6.asm). The text
\ entries take the Model B's game hooks' inputs (F_CHAR: A = the character;
\ F_DELCHAR: A = the column, Y = the row; F_CLRTEXT: A = the first row, Y
\ the last). The Master port's notes of the stars drawn directly (F_DSTAR,
\ f_unstar) are not here: on the Model B the stardust is drawn only in a
\ space view (STARS), which is always in record mode.
\
\ ******************************************************************************

\ F_CHAR: TT26's (CHPR's) character A at (XC-1, YC): in record or space mode
\ into the text map (f_char1); otherwise TT26 draws it directly, and it is
\ noted (the first DLMAX after a screen clear) or given to the map's cells
\ that buffer 0 may show (f_drule). X is not kept; Y is

.F_CHAR
 STA f_k3
 STY f_chy              \ (not f_ysav, which f_drule uses)
 JSR fch0
 LDY f_chy
 RTS
.fch0
 BIT GMODE
 BMI fch_r
 LDA QQ11
 ORA GFORCE
 BNE fch_d
.fch_r
 JSR fsy1               \ (the direct text noted first, if any)
 LDA f_k3
 LDX XC
 DEX
 LDY YC
 JMP f_char1
.fch_d
 LDX f_dlog
 CPX #DLMAX
 BCS fchd2
 LDA XC
 SBC #0                 \ (NMOS: C = 0, so XC - 1)
 STA f_dlx,X
 LDA YC
 STA f_dly,X
 LDA f_k3
 STA f_dlk,X
 INC f_dlog
 RTS
.fchd2
 JSR f_dflush
 LDA f_k3
 LDX XC
 DEX
 LDY YC
 JMP f_drule

.f_k3 EQUB 0            \ (F_CHAR's character, and Y)
.f_chy EQUB 0

\ F_DELCHAR: clear the text map cell at column A, row Y (TT26's delete).
\ Keeps Y

.F_DELCHAR
 TAX
 JSR f_sync             \ (keeps X and Y)
 JMP f_delchar0

\ F_CLRTEXT: clear text map rows A to Y (CLYNS: 21 to 22 in the flight
\ code, 21 to 23 in the docked code). Keeps Y

.F_CLRTEXT
 STA f_ctx
 JSR f_sync             \ (keeps X and Y)
 LDX f_ctx
 JMP f_clrtext0

.f_ctx EQUB 0

\ F_DIRECT: TTX66 is about to blank buffer 1 and draw directly (f_direct0
\ clears the text map): no direct text noted yet. But for an in-system jump
\ (WARP, which sets GWARP before LOOK1's TT66) in space mode, double
\ buffering and the view on show are kept (the blank screen was all a held
\ J ever showed): only the text goes, as TTX66 would have cleared it (the
\ jump's TTX66 reprints the view's name and LOOK1 the sights), and TTX66
\ then skips its screen clear and border (GMODE bit 7 still set). Keeps Y

.F_DIRECT
IF _SSUN
 LDA QQ12               \ docked: S_SUN forgets where the sun is (after a
 BEQ P%+7               \ launch it takes it from the system's seeds)
 LDA #0
 STA SS_OK
ENDIF
 ASL GWARP              \ an in-system jump's TTX66 in space mode?
 BCC fdr1
 BIT GMODE
 BPL fdr1
 LDX #0
 STX GSIGHT
 JSR f_sync             \ (keeps X = 0 and Y)
 STY f_ysav
 LDY #23
 JSR f_clrtext0
 LDY f_ysav
 RTS
.fdr1
 JSR f_dflush           \ (the last screen's noted text given to the map)
 TYA                    \ (Y, for f_lists: f_direct0's f_clrtext0 uses f_ysav)
 PHA
 JSR f_direct0          \ (which clears R_SS: no stars recorded)
 STA f_dlog             \ nothing noted on the new screen (NMOS: A = 0)
 PLA
 STA f_ysav
 LDA #&80               \ and nothing recorded for the frame before the screen
 STA F_SLV+16           \ was cleared (DEATH's TT66 comes in the middle of an
                        \ iteration, ESCAPE's too: what it had recorded is
                        \ gone from the screen), so a frame's lists hold one
                        \ record a ship slot at most (MAXSH, MAXLN, MAXDT);
 JMP f_lists            \ (f_reset's lists, returning with Y kept)

\ f_poly2: f_item's polygon detail (T_POLY), and a station's docking slot
\ (the only unlit polygon detail: black, colour byte &80 + 4 * its fill
\ visibility, gfx-faces.asm) filled and outlined in yellow over that. A fill
\ only a pixel or two across can come out empty, so the slot vanished long
\ before Elite stopped drawing its edges; lines always show, so the slot is
\ seen as early as in the original (its item's visibility is the furthest
\ Elite draws any of its edges: beyond its fill visibility, where some of its
\ vertices are not projected, just its side from vertex 0 to 1, as Elite),
\ and stands out from the dithered face. f_itemv has left the vertices in
\ R_PXL/R_PXH/R_PYL/R_PYH, which T_POLY and T_LINE do not change, and n in
\ fz_n.

.f_poly2
 LDY #2
 LDA (fz_q),Y           \ the colour byte: a hue ramp (bit 7 clear), or the
 BPL fpo8               \ slot's
 LSR A
 LSR A
 AND #31                \ its fill visibility
 CMP f_x4
 LDA #1                 \ (beyond it, A = 1: the edge from vertex 0 to 1 only)
 BCC fpo2
 JSR T_POLY
 LDX #51                \ its vertices for R_STARPLOT, which plots no star
.fpo3                   \ over it (F_SLV: black, the screen cannot tell)
 LDA R_PXL,X
 STA F_SLV,X
 DEX
 BPL fpo3
 LDA fz_n
.fpo2
 PHA
 LDA #1                 \ yellow (F_CPE/F_CPO entry 1)
 JSR f_setcol
 PLA
.fpo1                   \ A = i + 1 (i = n-1 down to 0): the edge from vertex i
 STA fz_u               \ to vertex (i + 1) MOD n
 CMP fz_n               \ (NMOS: vertex (i + 1) MOD n first, then fz_u
 BCC P%+4               \ stepped down to i for vertex i, for DEC A)
 LDA #0
 LDX #7
 JSR fpo_ld             \ R_X1, R_Y1 = vertex (i + 1) MOD n
 DEC fz_u
 LDA fz_u
 LDX #3
 JSR fpo_ld             \ R_X0, R_Y0 = vertex i
 JSR T_LINE
 LDA fz_u
 BNE fpo1
 RTS
.fpo8
 JMP T_POLY

\ fpo_ld: A = vertex number, X = 3 (to R_X0, R_Y0) or 7 (to R_X1, R_Y1): the
\ vertex's R_PYH, R_PYL, R_PXH, R_PXL (16 bytes apart) to R_X0 + X, X-1,
\ X-2, X-3

.fpo_ld
 ORA #48
 TAY
 SEC
.fpol1
 LDA R_PXL,Y
 STA R_X0,X
 TYA
 SBC #16
 TAY
 DEX
 BCS fpol1
 RTS
 ASSERT R_PXH = R_PXL + 16 AND R_PYL = R_PXL + 32 AND R_PYH = R_PXL + 48
 ASSERT R_Y0 = R_X0 + 2 AND R_X1 = R_X0 + 4 AND R_Y1 = R_X0 + 6

\ f_enter2: the first record-mode frame since F_DIRECT, or a disc command
\ has used buffer 0: start buffer 0 afresh if so (f_b0new), copy the border
\ to it (f_enter), then give the text map the text drawn directly, if any

.f_enter2
 BIT GSTASH             \ after a disc command buffer 0 holds no frame: start it
 BPL fen2a              \ afresh (f_b0new)
 JSR f_b0new
.fen2a
 JSR f_enter
                        \ fall through into f_sync (QQ11 = 0 here)

\ f_sync: called before each change to the text map. Outside record and space
\ mode (GMODE bit 7: the frames are running, as in the mission briefing,
\ whose text is printed outside record mode while LL9B draws the ship as a
\ frame) CHPR draws the text directly, into shadow RAM (buffer 1): the
\ characters F_CHAR noted are given to the map's cells by f_drule before the
\ map changes otherwise (f_dflush). At the first change in record or space
\ mode (or the first frame), they go into the map as characters (f_char1),
\ erasing nothing in buffer 1, which shows them: so the screens that carry
\ on in record mode keep the hyperspace countdown TTX66K drew. Preserves X
\ and Y.

.f_sync
 BIT GMODE
 BMI fsy1
 LDA QQ11
 ORA GFORCE
 BNE f_dflush
.fsy1
 LDA f_dlog
 BEQ fsy9
 CMP #DLMAX+1
 BCS fsy8               \ (given to the map already: f_dflush)
 DEC f_mk0              \ (non-zero: f_mark leaves buffer 1 alone)
 CLC
 JSR fdl0
 INC f_mk0              \ (NMOS: &FF to 0)
.fsy8
 LDA #0
 STA f_dlog
.fsy9
 RTS

\ f_dflush: the noted direct text, if not yet given to the map, given to its
\ cells by f_drule; then nothing more is noted until the next screen clear
\ (F_DIRECT) or record-mode change (f_sync). Preserves X and Y.

.f_dflush
 LDA f_dlog
 CMP #DLMAX+1
 BCS fdl9
 SEC
 JSR fdl0
 LDA #DLMAX+1
 STA f_dlog
.fdl9
 RTS

.fdl0                   \ the noted characters, in order, to f_drule (C set)
 TXA                    \ or f_char1 (C clear); X and Y kept (NMOS: on the
 PHA                    \ stack through A, which is not kept)
 TYA
 PHA
 ROR f_dmode
 LDX #0
.fdl1
 CPX f_dlog
 BCS fdl8
 TXA
 PHA
 LDA f_dly,X
 TAY
 LDA f_dlk,X
 PHA
 LDA f_dlx,X
 TAX
 PLA
 JSR fdl4               \ (NMOS: f_drule or f_char1, for BRA)
 PLA
 TAX
 INX
 BNE fdl1
.fdl8
 PLA
 TAY
 PLA
 TAX
 RTS

.f_dlog EQUB 0          \ characters noted since the screen's clear (DLMAX + 1:
                        \ given to the map already)
.f_dmode EQUB 0         \ bit 7: fdl0 to f_drule
.f_dlx  SKIP DLMAX      \ their columns, rows and characters
.f_dly  SKIP DLMAX
.f_dlk  SKIP DLMAX

.fdl4                   \ (fdl0: NMOS, for BRA) to f_drule or f_char1
 BIT f_dmode
 BMI f_drule
 JMP f_char1

\ f_drule: character A drawn directly into the cell at column X, row Y. A
\ cell holding 0 or &80 is left alone (buffer 0 shows nothing there, or is
\ to erase it anyway); one holding A or &80 + A is toggled, as CHPR's EOR
\ and f_char1 do it; one holding another character, or remembering one,
\ becomes &80: buffer 0 may show that character, which is to go

.f_drule
 CPY #24
 BCS frl9
 CPX #32
 BCS frl9
 STA f_tmp
 STY f_row
 JSR f_cell
 JSR f_tmget
 STX f_ysav             \ (the cell)
 TXA
 AND #&7F
 BEQ frl9
 LDX f_row
 CMP f_tmp
 BNE frl2
 LDA f_ysav             \ the same character: drawn again or removed
 EOR #&80
 BMI frl1               \ (NMOS: frl1 is frl2's DEC, for BRA)
 INC F_TMR,X
 BNE frl4               \ (F_TMR <= 32: not zero)
.frl2
 LDA #&80               \ another: forgotten
 BIT f_ysav
 BMI frl4
.frl1
 DEC F_TMR,X
.frl4
 JSR f_tmst
 LDA #3
 STA F_TCH,X
.frl9
 RTS

\ f_b0new: a disc command has used buffer 0 (BUF0: the staging area for its
\ loads, STAGE%, and DFS's workspace page are in it; PCLI sets GSTASH), so it
\ no longer holds the last frame of the previous space-mode session that its
\ rasteriser state, disc layer and text notes describe: clear it and forget
\ that state, for f_enter to carry on from (it then copies the border across)

.f_b0new
 LDA #HI(BUF0)
 STA fbn1+2
 LDA #0
 STA GSTASH
 TAX
.fbn1
 STA BUF0,X             \ (patched) clear &1000-&3FFF
 INX
 BNE fbn1
 INC fbn1+2
 LDY fbn1+2
 CPY #HI(BUF0) + &30
 BNE fbn1
 STA F_SGS              \ no sights drawn in it (NMOS: A = 0)
 STA f_mkn              \ and no cells to erase: its text shows nothing,
                        \ right for any F_TCH (the text map)
 TAX                    \ no disc (f_dforget, X = 0)
 JSR f_dforget
 LDA PF_CLS             \ nor the planet's circles of this iteration, if the
 AND #&7F               \ disc command came after PF_HOOK made them (they are
 STA PF_CLS             \ in the mailbox, which PCLI uses)
 LDA #0                 \ its rasteriser state: empty
 JSR T_SETBUF
 JMP T_RESETBUF

\ ------------------------------------------------------------------------------
\ f_slot: the stars (T_STARPLOT) when a station's docking slot was filled this
\ frame. The slot is the frame's only pure black fill (2-build-files/
\ starocc.py), so the screen cannot tell a star there from one on the
\ background: f_poly2 copies the slot's four vertices, as T_POLY filled them,
\ to F_SLV (R_PXL .. R_PYH + 3's layout: x low at +0, x high at +16, y low at
\ +32, y high at +48). The stars with a pixel in the vertices' bounding box
\ (clamped to 0..255) are taken out of R_SS for this plot and put back after
\ it (the hooks write R_SS only when a star moves); f_reset then marks F_SLV
\ empty (x high of vertex 0 &80, which no projected vertex is).
\ ------------------------------------------------------------------------------

.f_slot
{
  LDX #&FF                \ r_sbb: x min, x max, y min, y max
  STX r_sbb
  STX r_sbb+2
  INX                     \ (NMOS: X = 0)
  STX r_sbb+1
  STX r_sbb+3
  LDX #35                 \ the y of vertices 3..0 (F_SLV+32..35), then the x
.v                        \ (F_SLV+3..0)
  LDY #2
  CPX #32
  BCS v1
  LDY #0
.v1
  LDA F_SLV+16,X          \ the coordinate clamped to 0..255
  BNE v3                  \ (NMOS: out of line, for BRA)
  LDA F_SLV,X
.v4
  CMP r_sbb,Y
  BCS v5
  STA r_sbb,Y
.v5
  CMP r_sbb+1,Y
  BCC v6
  STA r_sbb+1,Y
.v6
  DEX
  BMI v7
  CPX #31
  BNE v
  LDX #3
  BNE v
.v3
  ASL A                   \ (C = its sign: off the screen's top or left, 0;
  LDA #&FF                \ else 255)
  ADC #0
  JMP v4
.v7
  LDA r_sbb               \ a star's pixels are x..x+1, y..y+1: it meets
  BEQ v8                  \ the box if x >= x min - 1 (and y likewise)
  DEC r_sbb
.v8
  LDA r_sbb+2
  BEQ v9
  DEC r_sbb+2
.v9
  LDX R_SN                \ the stars in the box out of R_SS (R_SN >= 1:
.s                        \ the frame layer's NOST + 1)
  DEX
  BMI s3
  LDA R_SS,X
  STA r_ssv,X
  BEQ s
  LDA R_SX,X
  CMP r_sbb
  BCC s
  CMP r_sbb+1
  BEQ s1
  BCS s
.s1
  LDA R_SY,X
  CMP r_sbb+2
  BCC s
  CMP r_sbb+3
  BEQ s2
  BCS s
.s2
  LDA #0
  STA R_SS,X
  BEQ s
.s3
  JSR T_STARPLOT          \ plot the rest
  LDX R_SN                \ and put R_SS back (R_SN >= 1)
  DEX
.r
  LDA r_ssv,X
  STA R_SS,X
  DEX
  BPL r                   \ (and N set on return: F_FRAME)
  RTS
.r_sbb  SKIP 4
.r_ssv  SKIP NDSTAR
}
