\ ******************************************************************************
\
\ gfx-frame.asm - the filled renderer's frame layer, in bank F
\ (docs/renderer.md, "The frame layer's bank F")
\
\ Port (Model B): the BBC Master port's frame layer (its gfx-frame.asm,
\ gfx-frame_cold.asm and gfx-light.asm, read from ~/elite-master-fork),
\ written for the NMOS 6502 and simplified for a bank that cannot see the
\ rasteriser's state: bank R is reached only through the trampolines in
\ main RAM (T_INIT to T_STARPLOT, gfx-rtramp.asm), with the inputs in its
\ mailbox (MBOX) and zero page (&06-&27).
\
\ The game's drawing routines, in a space view, record what they would
\ have drawn (F_SHIP, F_LINE, F_DOT, F_PLANET, F_SHPPT, F_PCURVE and
\ F_PPOINT, the text F_CHAR, F_DELCHAR and F_CLRTEXT) through GCALL
\ (gfx-glue.asm); once per main loop iteration F_FRAME draws the records
\ into the buffer not on show, asks the vertical sync interrupt to show it
\ (GFLIP, GPEND) and empties the lists. Each buffer is repaired by the
\ rasteriser at the start of its next frame (R_REPAIR blacks what the
\ previous frame on it marked dirty), so everything F_FRAME draws is either
\ a rasteriser shape (which marks itself) or spans and text marked with
\ R_MARKDIRTY.
\
\ What the Master port did and this does not:
\
\   * no disc layer: the sun and the planet are filled discs, drawn row by
\     row every frame (T_SPAN, which marks it dirty) from half-width tables
\     (F_HW, F_HW2), and the planet's meridians, equator and craters are
\     lines over it (FC_PLINE), not colour bands;
\   * no lens flare, no hangar, no docked-only drawing (LL9B, briefings);
\   * the text is redrawn every frame (every non-empty cell of the text
\     map, F_TM, then its row's extent marked dirty), and the sights too,
\     rather than drawn once per buffer and tracked;
\   * the lighting's quarter squares are its own (F_QSL, F_QSH, 0 to 255,
\     in this bank), as main RAM's QSL/QSH are under buffer 0;
\   * every entry keeps Y and takes its inputs in A, Y and memory (GCALL
\     carries the entry's number in X).
\
\ ******************************************************************************

FZ = &D2                \ &D2-&E1: the frame layer's zero page during F_FRAME
fz_p    = FZ            \ (the game's XX2, K3 and K4, dead between main loop
fz_q    = FZ+2          \ iterations; saved and restored with &06-&27)
fz_dl   = FZ+4          \ the ship's XX2 copy
fz_v3   = FZ+6          \ the ship's XX3 copy (and f_glyph's right byte)
fz_ft   = FZ+8          \ the face list
fz_dt   = FZ+10         \ the fin and detail list
fz_nm   = FZ+10         \ (f_glyph's left byte)
fz_i    = FZ+12
fz_n    = FZ+13
fz_t    = FZ+14
fz_u    = FZ+15

R_COLE  = &06           \ the rasteriser's zero page inputs (gfx-raster.asm's
R_COLO  = &07           \ names, which bank R assembles): the colour pair,
R_XL    = &08           \ the span ends and the clip window
R_XR    = &09
R_CL    = &0A
R_CR    = &0B
R_CT    = &0C
R_CB    = &0D

MAXSH = 13              \ ships per frame
MAXLN = 48              \ lines per frame
MAXDT = 64              \ dots per frame
MAXCV = 3               \ planet curves per frame
MAXPT = 64              \ planet curve points per frame

F_DODO = 32             \ GTYPE of the dodecahedron station (gfx-faces.asm)

\ Fixed colours (F_LC, F_DC, GLCOL and GDCOL hold these indices)

\ (FC_BLACK to FC_STAR are in elite-map.asm, for the game's hooks)

.F_CPE                  \ even rows' byte (the odd rows' are the same)
 EQUB &00, &FF, &F0, &0F, &FF, &0F, &FF
F_CPO = F_CPE

\ ------------------------------------------------------------------------------
\ Entries (docs/renderer.md has each one's inputs)
\ ------------------------------------------------------------------------------

\ F_INIT: once, before anything else: the rasteriser's state, empty lists and
\ text map, direct mode (the first F_FRAME blanks both buffers)

.F_INIT
 STY f_ysav
 JSR f_zsave            \ (T_INIT writes the rasteriser's zero page)
 JSR T_INIT
 JSR f_zrest
 LDA #0
 STA GMODE
 STA GFLIP
 STA GSIGHT
 STA GLASV
 STA GSTASH
 STA GFORCE
 STA GDL
 LDA #&FF
 STA GDRAWON
 LDA #1
 STA GFRONT
 JSR f_tmclear
 JMP f_reset

\ F_DIRECT: the screen is about to be cleared and drawn on directly (TT66):
\ direct mode, buffer 1 on show, no text, no stars

.F_DIRECT
 STY f_ysav
 PHP
 SEI
 LDA #0
 STA GMODE
 STA GFLIP
 STA GSIGHT
 STA GLASV
 LDA #1
 STA GFRONT
 PLP
 JSR f_tmclear          \ (A = 0)
 LDX #23
.fdi1
 STA R_SS,X             \ no stars recorded
 DEX
 BPL fdi1
 LDY f_ysav
 RTS

\ F_SHIP: record the ship LL9 is drawing: GTYPE, GNF faces, GNV vertices, XX2
\ (each face's visibility), XX3 (the projected vertices), XX4, INWK+6/7 (z)
\ and the orientation's high bytes (L_REC lights the faces into the record's
\ XX2 copy)

.fshx                   \ (no room: nothing recorded)
 LDY f_ysav
 RTS

.F_SHIP
 STY f_ysav
 LDX F_NSHIP
 CPX #MAXSH
 BCS fshx
 LDA GNV
 ASL A
 ASL A
 STA f_nv4
 CLC
 ADC GNF                \ nf + 4 nv bytes, from F_DLP: room before F_DLEND?
 BCS fshx
 ADC F_DLP
 LDA F_DLP+1
 ADC #0
 CMP #HI(F_DLEND)
 BCS fshx
 LDA F_DLP
 STA F_SPL,X
 STA fsh2+1
 STA fsh8+1
 LDA F_DLP+1
 STA F_SPH,X
 STA fsh2+2
 STA fsh8+2
 LDA INWK+7
 STA F_SZH,X
 LDA INWK+6
 STA F_SZL,X
 LDA GTYPE
 STA F_STYP,X
 LDA GNF
 STA F_SNF,X
 LDA XX4
 STA F_SX4,X
 LDY #0                 \ the XX2 copy
 LDX GNF
 BEQ fsh3
.fsh1
 LDA XX2,Y
.fsh2
 STA &FFFF,Y            \ patched
 INY
 DEX
 BNE fsh1
 LDA GTYPE              \ the alloy plate's one face has no normal, so LL9
 CMP #PLT               \ never marks it visible: fill it from both sides
 BNE fsh3
 LDA #1
.fsh8
 STA &FFFF              \ patched: the XX2 copy's first byte
.fsh3
 JSR L_REC              \ the faces' levels into the XX2 copy
 LDA fsh2+1             \ then the XX3 copy
 CLC
 ADC GNF
 STA fsh5+1
 LDA fsh2+2
 ADC #0
 STA fsh5+2
 LDY #0
 LDX f_nv4
 BEQ fsh6
.fsh4
 LDA XX3,Y
.fsh5
 STA &FFFF,Y            \ patched
 INY
 DEX
 BNE fsh4
.fsh6
 LDA fsh5+1
 CLC
 ADC f_nv4
 STA F_DLP
 LDA fsh5+2
 ADC #0
 STA F_DLP+1
 INC F_NSHIP
.fsh9
 LDY f_ysav
 RTS

\ F_BOMB: a new energy bomb bolt: drop the lines of the bolt recorded earlier
\ in this frame, if any

.F_BOMB
 BIT f_bomb
 BPL fbo1
 LDA f_bmark
 STA F_NLINE
 RTS
.fbo1
 LDA F_NLINE
 STA f_bmark
 LDA #&FF
 STA f_bomb
 RTS

\ F_LINE: record a line (X1, Y1) to (X2, Y2) in colour GLCOL

.F_LINE
 LDX F_NLINE
 CPX #MAXLN
 BCS fli9
 LDA X1
 STA F_LX0,X
 LDA Y1
 STA F_LY0,X
 LDA X2
 STA F_LX1,X
 LDA Y2
 STA F_LY1,X
 LDA GLCOL
 STA F_LC,X
 INC F_NLINE
.fli9
 RTS

\ F_DOT: record a dot at x = Y, y = A in colour GDCOL: a dash if ZZ >= 80, a
\ double-height dash below (as PIXEL)

.F_DOT
 LDX F_NDOT
 CPX #MAXDT
 BCS fdo9
 STA F_DY,X
 TYA
 STA F_DX,X
 LDA GDCOL
 STA F_DC,X
 LDA ZZ
 CMP #80
 LDA #2
 BCS fdo1
 LDA #3
.fdo1
 STA F_DS,X
 INC F_NDOT
.fdo9
 RTS

\ F_PLANET: record the planet (TYPE even) or the sun (TYPE odd): centre (K3,
\ K4) 16-bit, radius K, and the planet's z, INWK+6/7

.F_PLANET
 LDA TYPE
 LSR A
 BCS fpl1
 LDA K3
 STA F_PLX
 LDA K3+1
 STA F_PLX+1
 LDA K4
 STA F_PLY
 LDA K4+1
 STA F_PLY+1
 LDA K
 STA F_PLR
 LDA INWK+7
 STA F_PLZH
 LDA INWK+6
 STA F_PLZL
 LDA #&FF
 STA F_PLON
 RTS
.fpl1
 LDA K3
 STA F_SUX
 LDA K3+1
 STA F_SUX+1
 LDA K4
 STA F_SUY
 LDA K4+1
 STA F_SUY+1
 LDA K
 STA F_SUR
 LDA #&FF
 STA F_SUON
 RTS

\ F_SHPPT: record a distant ship as a 2x2 dot at (K3, K4), in TYPE's dot
\ colour

.F_SHPPT
 LDX F_NDOT
 CPX #MAXDT
 BCS fsp9
 LDA K3
 STA F_DX,X
 LDA K4
 STA F_DY,X
 LDA #3
 STA F_DS,X
 LDA TYPE
 ORA #&80               \ bit 7: a ship type, drawn in its dot colour
 STA F_DC,X
 INC F_NDOT
.fsp9
 RTS

\ F_PCURVE: start a planet curve (a meridian, the equator or a crater, as
\ PLS22 or CIRCLE begins one); F_PPOINT: its next point, (K6, K5+2) 16-bit
\ (as BLINE has them). Consecutive points are joined by lines.

.F_PCURVE
 LDX F_NCV
 CPX #MAXCV
 BCS fpc9
 LDA F_NPT
 STA F_CVS,X
 INC F_NCV
.fpc9
 RTS

.F_PPOINT
 LDA F_NCV
 BEQ fpp9
 LDX F_NPT
 CPX #MAXPT
 BCS fpp9
 LDA K6
 STA F_PXL,X
 LDA K6+1
 STA F_PXH,X
 LDA K5+2
 STA F_PYL,X
 LDA K5+3
 STA F_PYH,X
 INC F_NPT
.fpp9
 RTS

\ F_CHAR: character A in the text map at (XC - 1, YC), as the original's EOR
\ printing: the same character again removes it. Characters 32 to 127
\ only; A is kept

.F_CHAR
 STY f_ysav
 STA f_tch
 LDX XC
 DEX
 CPX #32
 BCS fch9
 LDY YC
 CPY #24
 BCS fch9
 CMP #32
 BCC fch9
 CMP #128
 BCS fch9
 STY f_trow
 JSR f_cell
 JSR f_tmget
 BEQ fch1               \ empty: store it
 CMP f_tch
 BEQ fch2               \ the same character: remove it
 LDA f_tch              \ another: replace it
 JSR f_tmput
 JMP fch9
.fch1
 LDA f_tch
 JSR f_tmput
 LDX f_trow
 INC F_TMR,X
 JMP fch9
.fch2
 LDA #0
 JSR f_tmput
 LDX f_trow
 DEC F_TMR,X
.fch9
 LDA f_tch
 LDY f_ysav
 RTS

\ F_DELCHAR: clear the text map's cell at column A, row Y

.F_DELCHAR
 STY f_ysav
 TAX
 CPX #32
 BCS fdc9
 CPY #24
 BCS fdc9
 STY f_trow
 JSR f_cell
 JSR f_tmget
 BEQ fdc9
 LDA #0
 JSR f_tmput
 LDX f_trow
 DEC F_TMR,X
.fdc9
 LDY f_ysav
 RTS

\ F_CLRTEXT: clear the text map's rows A to Y (inclusive)

.F_CLRTEXT
 STY f_ysav
 TAX
.fct1
 CPX #24
 BCS fct9
 STX f_trow
 LDA F_TMR,X
 BEQ fct5               \ (an empty row is clear already)
 LDA #0
 STA F_TMR,X
 LDY f_trow
 LDX #0
 JSR f_cell             \ f_tmput -> the row's first cell
 LDA f_tmput+1
 STA fct3+1
 LDA f_tmput+2
 STA fct3+2
 LDY #31
 LDA #0
.fct3
 STA &FFFF,Y            \ patched
 DEY
 BPL fct3
.fct5
 LDX f_trow
 CPX f_ysav
 INX
 BCC fct1
.fct9
 LDY f_ysav
 RTS

\ f_cell: X = column, Y = row: point f_tmget and f_tmput at the cell

.f_cell
 TYA
 LSR A
 LSR A
 LSR A
 CLC
 ADC #HI(F_TM)
 STA f_tmget+2
 STA f_tmput+2
 TYA
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A
 STA f_tmget+1
 TXA
 ORA f_tmget+1
 STA f_tmget+1
 STA f_tmput+1
 RTS
 ASSERT LO(F_TM) = 0

.f_tmget
 LDA F_TM               \ patched (sets Z on the content)
 RTS

.f_tmput
 STA F_TM               \ patched
 RTS

.f_tmclear              \ the text map empty (returns A = 0)
 LDA #0
 TAX
.ftm1
 STA F_TM,X
 STA F_TM+256,X
 STA F_TM+512,X
 INX
 BNE ftm1
 LDX #23
.ftm2
 STA F_TMR,X
 DEX
 BPL ftm2
 RTS

\ ------------------------------------------------------------------------------
\ F_FRAME: draw this frame's records into the buffer not on show and queue
\ the flip to it; once per main loop iteration. Not in a space view (QQ11
\ non-zero): just forget the records.
\ ------------------------------------------------------------------------------

.F_FRAME
 STY f_ysav
 LDA QQ11
 BEQ ff1
 JMP f_reset
.ff1
 JSR L_SUN              \ the light for the next iteration's ships
 JSR f_zsave            \ the game's &06-&27 and &D2-&E1
 LDA #2                 \ the clip window inside the border
 STA R_CL
 LDA #253
 STA R_CR
 LDA #1
 STA R_CT
 LDA #191
 STA R_CB
 BIT GMODE              \ the first frame since direct mode, or the buffers
 BPL ff3                \ used by something else: blank both
 BIT GSTASH
 BPL ff4
.ff3
 JSR f_enter
.ff4
 LDA F_BACK
 JSR T_SETBUF
.ff2
 LDA GFLIP              \ wait for the last flip, so that the back buffer is
 BNE ff2                \ no longer on show
 JSR T_STARERASE        \ last time's stars in this buffer
 JSR T_REPAIR           \ and the rest of what was drawn on it
 JSR f_discs            \ the sun and the planet
 JSR f_curves           \ the planet's meridians, equator and craters
.ff_lin                 \ (F_HANGAR points this call at f_hback for its frame)
 JSR f_lines            \ lines (enemy lasers, the energy bomb)
 JSR f_ships            \ filled ships, far to near
 JSR f_dots             \ particles, distant ships
 JSR f_lasers           \ our laser beams
 JSR f_flt              \ (Model B) the lens flare (gfx-flare.asm)
 JSR f_text             \ the text
 JSR f_sights           \ the sights
 JSR f_stars            \ the stardust, last (on black only)
 JSR f_zrest
 LDA F_BACK             \ show it at the next vertical sync
 STA GPEND
 EOR #1
 STA F_BACK
 LDA #&FF
 STA GFLIP

.f_reset                \ empty the lists (Y = f_ysav)
 LDA #0
 STA GLASV              \ (the beams show for one frame per LASLI)
 STA f_bomb
 STA F_NSHIP
 STA F_NLINE
 STA F_NDOT
 STA F_PLON
 STA F_SUON
 STA F_NCV
 STA F_NPT
 LDA #LO(F_DL)
 STA F_DLP
 LDA #HI(F_DL)
 STA F_DLP+1
 LDY f_ysav
 RTS

\ f_zsave, f_zrest: the zero page the rasteriser uses (&06-&27) and this
\ layer's (FZ, 16 bytes), kept in f_zb

.f_zsave
 LDX #&21
.fzs1
 LDA &06,X
 STA f_zb,X
 DEX
 BPL fzs1
 LDX #15
.fzs2
 LDA FZ,X
 STA f_zb+&22,X
 DEX
 BPL fzs2
 RTS

.f_zrest
 LDX #&21
.fzr1
 LDA f_zb,X
 STA &06,X
 DEX
 BPL fzr1
 LDX #15
.fzr2
 LDA f_zb+&22,X
 STA FZ,X
 DEX
 BPL fzr2
 RTS

\ f_enter: blank both buffers' windows (inside the border: lines 1 to 191,
\ pixels 2 to 253), keeping buffer 1's border (which the game drew there in
\ direct mode) and copying it to buffer 0, then forget both buffers'
\ rasteriser state and draw first into the one not on show

.f_enter
 LDA GFLIP              \ (a flip may be pending if the buffers were taken)
 BNE f_enter
 LDA #0
 STA GSTASH
 STA GDL                \ (no disc layer on either buffer)
 TAX                    \ line 0: buffer 1's to buffer 0 (byte 8k of pages
.fen1                   \ &40 and &41)
 LDA SCREEN%,X
 STA BUF0,X
 LDA SCREEN%+&100,X
 STA BUF0+&100,X
 TXA
 CLC
 ADC #8
 TAX
 BNE fen1
 LDA #1                 \ lines 1 to 191
 STA fz_i
.fen2
 AND #7                 \ fz_p = buffer 1's line, fz_q = buffer 0's
 STA fz_p
 STA fz_q
 LDA fz_i
 LSR A
 LSR A
 LSR A
 ASL A
 ADC #HI(SCREEN%)       \ (C = 0)
 STA fz_p+1
 SEC
 SBC #HI(SCREEN%-BUF0)
 STA fz_q+1
 LDY #0                 \ byte column 0: the border's pixels 0-1 only
 LDA (fz_p),Y
 AND #&CC
 STA (fz_p),Y
 STA (fz_q),Y
 LDY #8                 \ columns 1 to 31
.fen3
 LDA #0
 STA (fz_p),Y
 STA (fz_q),Y
 TYA
 CLC
 ADC #8
 TAY
 BNE fen3
 INC fz_p+1
 INC fz_q+1
.fen4                   \ columns 32 to 62
 LDA #0
 STA (fz_p),Y
 STA (fz_q),Y
 TYA
 CLC
 ADC #8
 TAY
 CPY #&F8
 BNE fen4
 LDA (fz_p),Y           \ column 63: the border's pixels 254-255 only
 AND #&33
 STA (fz_p),Y
 STA (fz_q),Y
 INC fz_i
 LDA fz_i
 CMP #192
 BNE fen2
 LDA #1                 \ both buffers' state: empty
 JSR T_SETBUF
 JSR T_RESETBUF
 LDA #0
 JSR T_SETBUF
 JSR T_RESETBUF
 LDA GFRONT             \ draw into the one not on show
 EOR #1
 STA F_BACK
 LDA #&80
 STA GMODE
 RTS
 ASSERT BUF0 MOD &100 = 0 AND (SCREEN% - BUF0) MOD &100 = 0

\ ------------------------------------------------------------------------------
\ The sun and the planet: filled discs, row by row
\ ------------------------------------------------------------------------------

.f_discs
 LDA #0                 \ the disc layer (gfx-dlayer.asm, in the flight
 STA f_lay              \ code's cold bank: a far call) draws the bigger disc
 LDA F_SUON             \ if there is one, or takes the old one off the buffer
 AND #1                 \ if it has one (GDL); f_lay = the one it drew (1 the
 STA fz_t               \ sun, 2 the planet), which is not drawn below
 LDA F_PLON
 AND #2
 ORA fz_t
 TAX
 BNE fds0
 LDY F_BACK
 INY
 TYA
 AND GDL
 BEQ fds4
.fds0
 LDA F_BACK
 JSR f_dlframe
 STA f_lay
.fds4
 LDA F_SUON             \ the sun first (it is further away)
 BEQ fds1
 LDA f_lay
 CMP #1
 BEQ fds1
 LDA F_SUX
 STA f_cx
 LDA F_SUX+1
 STA f_cx+1
 LDA F_SUY
 STA f_cy
 LDA F_SUY+1
 STA f_cy+1
 LDA F_SUR
 STA f_r
 CMP f_hw2r             \ its half-widths, unless they are for this radius
 BEQ fds2
 STA f_hw2r
 LDA #HI(F_HW2)
 STA fhw_st+2
 JSR f_hwbuild
.fds2
 LDA #HI(F_HW2)
 STA fdh_ld+2
 LDA #FC_SUNE
 STA R_COLE
 LDA #FC_SUNO
 STA R_COLO
 JSR f_disc
.fds1
 LDA F_PLON
 BEQ fds9
 LDA F_PLX
 STA f_cx
 LDA F_PLX+1
 STA f_cx+1
 LDA F_PLY
 STA f_cy
 LDA F_PLY+1
 STA f_cy+1
 LDA F_PLR
 STA f_r
 CMP f_hwr
 BEQ fds3
 STA f_hwr
 LDA #HI(F_HW)
 STA fhw_st+2
 JSR f_hwbuild
.fds3
 LDA f_lay              \ (the layer's: its half-widths only, for the flare)
 CMP #2
 BEQ fds9
 LDA #HI(F_HW)
 STA fdh_ld+2
 LDA #FC_PLANE
 STA R_COLE
 LDA #FC_PLANO
 STA R_COLO
 JMP f_disc
.fds9
 RTS

.f_dlframe              \ DL_FRAME, in the flight code's cold bank
 JSR farC
 EQUW DL_FRAME
.f_lay EQUB 0

\ f_disc: the disc at (f_cx, f_cy) (16-bit) of radius f_r, its half-widths at
\ fdh_ld's page, in the colour pair: each row inside the clip window a span,
\ marked dirty

.fdi_x0
 RTS

.f_disc
 LDA f_cy               \ fz_p = the top row, cy - r, clipped
 SEC
 SBC f_r
 STA fz_p
 LDA f_cy+1
 SBC #0
 BMI fdi_t              \ above the screen: the window's top
 BNE fdi_x0             \ below row 255: nothing
 LDA fz_p
 CMP R_CT
 BCS fdi_t2
.fdi_t
 LDA R_CT
 STA fz_p
.fdi_t2
 LDA f_cy               \ fz_q = the bottom row, cy + r, clipped
 CLC
 ADC f_r
 STA fz_q
 LDA f_cy+1
 ADC #0
 BMI fdi_x0             \ above the screen: nothing
 BNE fdi_b              \ below row 255: the window's bottom
 LDA fz_q
 CMP R_CB
 BCC fdi_b2
.fdi_b
 LDA R_CB
 STA fz_q
.fdi_b2
 LDA fz_q
 CMP fz_p
 BCC fdi_x0             \ none
 LDY fz_p
.fdi_row
 STY fz_i               \ Y = the row
 TYA                    \ X = |row - cy| (<= r)
 SEC
 SBC f_cy
 STA fz_t
 LDA #0
 SBC f_cy+1
 BPL fdi_d
 LDA fz_t
 EOR #&FF
 CLC
 ADC #1
 STA fz_t
.fdi_d
 LDX fz_t
.fdh_ld
 LDA F_HW,X             \ patched: the half-width table's page
 STA fz_n
 CLC                    \ R_XR = cx + n, clipped
 LDA f_cx
 ADC fz_n
 STA R_XR
 LDA f_cx+1
 ADC #0
 BMI fdi_nx             \ left of the screen: none
 BNE fdi_rc             \ right of it: the window's right
 LDA R_XR
 CMP R_CL
 BCC fdi_nx
 CMP R_CR
 BCC fdi_r2
.fdi_rc
 LDA R_CR
 STA R_XR
.fdi_r2
 SEC                    \ R_XL = cx - n, clipped
 LDA f_cx
 SBC fz_n
 STA R_XL
 LDA f_cx+1
 SBC #0
 BMI fdi_lc             \ left of the screen: the window's left
 BNE fdi_nx             \ right of it: none
 LDA R_XL
 CMP R_CR
 BEQ fdi_l2
 BCS fdi_nx
 CMP R_CL
 BCS fdi_l2
.fdi_lc
 LDA R_CL
 STA R_XL
.fdi_l2
 LDY fz_i
 JSR T_SPAN             \ (which marks the span dirty too)
.fdi_nx
 LDY fz_i
 CPY fz_q
 INY
 BCC fdi_row
.fdi_x
 RTS

\ f_hwbuild: table[d] = floor(sqrt(r * r - d * d)) for d = 0 to r (r = f_r,
\ the table's page patched into fhw_st), by walking x down from r while
\ x * x + d * d > r * r (e = r * r - d * d - x * x, 16-bit signed)

.f_hwbuild
 LDX f_r                \ x = r
 LDA #0
 STA fz_p               \ e = 0 (d = 0, x = r)
 STA fz_p+1
 LDY #0                 \ d
.fhw1
 TXA
.fhw_st
 STA F_HW,Y             \ patched
 CPY f_r
 BEQ fhw9
 TYA                    \ e -= 2d + 1 ; d++
 ASL A
 STA fz_t
 LDA #0
 ROL A
 STA fz_u
 LDA fz_p
 CLC                    \ (C = 0: SBC takes the + 1 too)
 SBC fz_t
 STA fz_p
 LDA fz_p+1
 SBC fz_u
 STA fz_p+1
 INY
.fhw2
 LDA fz_p+1             \ while e < 0: e += 2x - 1 ; x--
 BPL fhw1
 TXA
 ASL A
 STA fz_t
 LDA #0
 ROL A
 STA fz_u
 LDA fz_t
 SEC
 SBC #1
 STA fz_t
 BCS fhw3
 DEC fz_u
.fhw3
 LDA fz_p
 CLC
 ADC fz_t
 STA fz_p
 LDA fz_p+1
 ADC fz_u
 STA fz_p+1
 DEX
 JMP fhw2
.fhw9
 RTS

\ f_curves: each planet curve's points joined by lines

.f_curves
 LDA F_NCV
 BEQ fcv9
 LDA #FC_PLINE
 JSR f_setcol
 LDX #0
.fcv1
 STX fz_i               \ the curve
 LDA F_CVS,X            \ its first point
 STA fz_n
 INX                    \ and its end: the next curve's first point, or the
 LDA F_NPT              \ last recorded
 CPX F_NCV
 BCS fcv3
 LDA F_CVS,X
.fcv3
 STA fz_t
.fcv4
 LDX fz_n               \ the line from point n to point n + 1, if there
 INX                    \ is one
 CPX fz_t
 BCS fcv8
 STX fz_n
 LDA F_PXL-1,X
 STA R_X0
 LDA F_PXH-1,X
 STA R_X0+1
 LDA F_PYL-1,X
 STA R_Y0
 LDA F_PYH-1,X
 STA R_Y0+1
 LDA F_PXL,X
 STA R_X1
 LDA F_PXH,X
 STA R_X1+1
 LDA F_PYL,X
 STA R_Y1
 LDA F_PYH,X
 STA R_Y1+1
 JSR T_LINE
 JMP fcv4
.fcv8
 LDX fz_i
 INX
 CPX F_NCV
 BCC fcv1
.fcv9
 RTS

\ ------------------------------------------------------------------------------
\ Lines, ships, dots, lasers, stars
\ ------------------------------------------------------------------------------

.f_setcol               \ A = fixed colour index -> R_COLE, R_COLO
 TAX
 LDA F_CPE,X
 STA R_COLE
 LDA F_CPO,X
 STA R_COLO
 RTS

.f_line8                \ a line from (fz_t, fz_u) to (X, Y), 8-bit
 STX R_X1
 STY R_Y1
 LDA fz_t
 STA R_X0
 LDA fz_u
 STA R_Y0
 LDA #0
 STA R_X0+1
 STA R_Y0+1
 STA R_X1+1
 STA R_Y1+1
 JMP T_LINE

.f_lines
 LDA #0
 STA fz_i
.fln1
 LDX fz_i
 CPX F_NLINE
 BCS fln9
 LDA F_LC,X
 JSR f_setcol
 LDX fz_i
 LDA F_LX0,X
 STA fz_t
 LDA F_LY0,X
 STA fz_u
 LDA F_LY1,X
 TAY
 LDA F_LX1,X
 TAX
 JSR f_line8
 INC fz_i
 BNE fln1
.fln9
 RTS

\ f_ships: insertion-sort the ships far to near, then draw each one

.f_ships
 LDX F_NSHIP
 BNE fss0
 RTS
.fss0
 LDX #0                 \ F_ORD = 0, 1, 2, ... then sorted by z, descending
.fss1
 TXA
 STA F_ORD,X
 INX
 CPX F_NSHIP
 BCC fss1
 LDX #1
.fss2
 CPX F_NSHIP
 BCS fss6
 LDA F_ORD,X            \ insert element X
 STA fz_t
 TXA
 TAY
.fss3
 DEY
 BMI fss5
 LDA F_ORD,Y            \ further than F_ORD,Y? then shift that one up
 STA fz_u
 STX fz_n
 LDX fz_t
 LDA F_SZL,X
 STA fz_i
 LDA F_SZH,X
 LDX fz_u
 CMP F_SZH,X
 BCC fss4               \ nearer: stop
 BNE fss7               \ further: shift
 LDA fz_i
 CMP F_SZL,X
 BCC fss4
 BEQ fss4
.fss7
 LDX fz_n
 LDA fz_u
 STA F_ORD+1,Y
 JMP fss3
.fss4
 LDX fz_n
.fss5
 INY                    \ (Port: the Master port's STA F_ORD+1,Y wrote
 LDA fz_t               \ F_ORD+&100 when Y = &FF, the new ship the furthest
 STA F_ORD,Y            \ so far, and left F_ORD+0 as it was)
 INX
 BNE fss2
.fss6
 LDA #0
 STA fz_i
.fss8
 LDX fz_i
 CPX F_NSHIP
 BCS fss9
 LDA F_ORD,X
 JSR f_ship
 INC fz_i
 BNE fss8
.fss9
 RTS

\ f_ship: draw ship A. Every face is flat-shaded (FC_FACETAB: n + 16 * hue
\ ramp, unit normal, n XX3 offsets; the record's XX2 copy holds the face's
\ level, and f_col its ramp entry). Fins standing behind the body first, then
\ the visible faces, the surface details over them and the other fins
\ (gfx-faces.asm has the order).

.f_ship
 TAX
 STX f_si
 LDY F_STYP,X
 LDA F_SX4,X            \ skip a ship whose polygon vertices may be stale
 STA f_x4
 CMP FC_MINVIS,Y
 BEQ fsh_ok
 BCC fsh_ok
 RTS
.fsh_ok
 TYA
 ASL A
 TAY
 LDA FC_FACETAB,Y
 STA fz_ft
 LDA FC_FACETAB+1,Y
 STA fz_ft+1
 LDA FC_DETTAB,Y        \ fins, then details
 STA fz_dt
 LDA FC_DETTAB+1,Y
 STA fz_dt+1
 LDA F_SPL,X            \ the XX2 copy, then the XX3 copy
 STA fz_dl
 LDA F_SPH,X
 STA fz_dl+1
 LDA F_SNF,X
 STA f_nf
 CLC
 ADC fz_dl
 STA fz_v3
 LDA fz_dl+1
 ADC #0
 STA fz_v3+1
 LDA fz_v3              \ the vertex gather's operands: the XX3 copy + 0..3
 STA fsh_x0+1
 LDA fz_v3+1
 STA fsh_x0+2
 FOR k, 1, 3
  CLC
  LDA fz_v3
  ADC #k
  STA fsh_x0+1+6*k
  LDA fz_v3+1
  ADC #0
  STA fsh_x0+2+6*k
 NEXT

 JSR f_behind           \ hidden behind the planet?
 BCC fsh_nb
 RTS
.fsh_nb

 LDY #0                 \ fins behind the body (neither of their faces visible)
 LDA (fz_dt),Y
 BEQ fsh_nf0
 TYA
 JSR f_fins
.fsh_nf0

 LDA #0
 STA f_f
 BEQ fsh_face
.fsh_skip               \ a hidden face: just step over its entry
 LDY #0
 LDA (fz_ft),Y
 AND #15
 STA fz_n
 JMP fsh_next
.fsh_face
 LDY f_f
 CPY f_nf
 BCC fsh_f1
 JMP fsh_done
.fsh_f1
 LDA (fz_dl),Y          \ its level (0: hidden)
 BEQ fsh_skip
 STA fz_t
 LDY #0
 LDA (fz_ft),Y          \ n + 16 * ramp
 AND #15
 STA fz_n
 CMP #3
 BCC fsh_next
 STA R_PN
 LDA fz_t
 AND #31
 TAX
 LDA (fz_ft),Y          \ its hue ramp
 LSR A
 LSR A
 LSR A
 LSR A
 JSR f_col              \ lit: R_COLE, R_COLO, R_COL2, R_COL3
 CLC                    \ the face's vertex offsets at fz_ft + 4
 LDA fz_ft
 ADC #4
 STA fsh_o+1
 LDA fz_ft+1
 ADC #0
 STA fsh_o+2
 LDX #0                 \ gather the vertices
.fsh_v
.fsh_o
 LDY &FFFF,X            \ patched: an XX3 offset
.fsh_x0
 LDA &FFFF,Y            \ patched: the XX3 copy + 0..3
 STA R_PXL,X
.fsh_x1
 LDA &FFFF,Y
 STA R_PXH,X
.fsh_x2
 LDA &FFFF,Y
 STA R_PYL,X
.fsh_x3
 LDA &FFFF,Y
 STA R_PYH,X
 ASSERT fsh_x1 = fsh_x0 + 6 AND fsh_x2 = fsh_x0 + 12 AND fsh_x3 = fsh_x0 + 18
 INX
 CPX fz_n
 BCC fsh_v
 BIT fz_t               \ XX2 was 255 (Elite skipped the normal test): cull a
 BVC fsh_draw           \ back face by its winding, but not on a station
 LDX f_si               \ (mirrored until its first TIDY)
 LDA F_STYP,X
 CMP #SST
 BEQ fsh_draw
 CMP #F_DODO
 BEQ fsh_draw
 JSR f_winding
 BCC fsh_next
.fsh_draw
 JSR T_POLY
.fsh_next
 LDA fz_n               \ the next face's entry: n + 4 bytes on
 CLC
 ADC #4
 ADC fz_ft
 STA fz_ft
 BCC fsh_n1
 INC fz_ft+1
.fsh_n1
 INC f_f
 JMP fsh_face

.fsh_done               \ details: skip the fins (7 bytes each) to the count
 LDY #0
 LDA (fz_dt),Y
 STA f_cnt
 ASL A
 ASL A
 ASL A
 SEC
 SBC f_cnt              \ 7 * count (C = 1: no borrow)
 SEC
 ADC fz_dt
 STA fz_q
 LDA fz_dt+1
 ADC #0
 STA fz_q+1
 LDA (fz_q),Y
 BEQ fdt8
 STA f_cnt
 INC fz_q
 BNE fdt1
 INC fz_q+1
.fdt1
 JSR f_item
 DEC f_cnt
 BNE fdt1
.fdt8
 LDY #0                 \ the other fins: one face visible, then both (the
 LDA (fz_dt),Y          \ fin nearest the viewer)
 BEQ fdt9
 LDA #1
 JSR f_fins
 LDA #2
 JMP f_fins
.fdt9
 RTS

\ f_item: draw the detail at (fz_q) if it is within its visibility distance
\ and face1 or face2 is visible: n = 2 a line, else a polygon (culled by its
\ winding if XX2 = 255). Then fz_q -> the next item.

.f_item
 LDY #0
 LDA (fz_q),Y           \ visibility distance
 CMP f_x4
 BCC fit8
 INY
 LDA (fz_q),Y           \ face1 + 16 * face2
 AND #15
 TAY
 LDA (fz_dl),Y
 BNE fit1
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 BEQ fit8
.fit1
 STA fz_t
 JSR f_itemv            \ colour and vertices
 LDA fz_n
 CMP #3
 BCC fit3
 STA R_PN
 BIT fz_t               \ (XX2 = 255: cull by winding)
 BVC fit2
 JSR f_winding
 BCC fit8
.fit2
 JSR f_poly2            \ (T_POLY, and the docking slot's outline)
 JMP fit8
.fit3
 LDA R_PXL              \ a line
 STA R_X0
 LDA R_PXH
 STA R_X0+1
 LDA R_PYL
 STA R_Y0
 LDA R_PYH
 STA R_Y0+1
 LDA R_PXL+1
 STA R_X1
 LDA R_PXH+1
 STA R_X1+1
 LDA R_PYL+1
 STA R_Y1
 LDA R_PYH+1
 STA R_Y1+1
 JSR T_LINE
.fit8
 LDY #3                 \ the next item: 4 + n bytes on
 LDA (fz_q),Y
 CLC
 ADC #4
 ADC fz_q
 STA fz_q
 BCC fit9
 INC fz_q+1
.fit9
 RTS

\ f_itemv: the item at (fz_q): its colour (lit at the brighter of its two
\ faces' levels, or unlit), fz_n = n, R_PX/R_PY[0..n-1]

.f_itemv
 LDY #1                 \ face1 + 16 * face2: the brighter level (a hidden
 LDA (fz_q),Y           \ face's is 0)
 AND #15
 TAY
 LDA (fz_dl),Y
 AND #31
 STA fz_u
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 AND #31
 CMP fz_u
 BCS fiv0
 LDA fz_u
.fiv0
 TAX
 LDY #2
 LDA (fz_q),Y           \ colour byte: a hue ramp, or &80 + an unlit colour
 JSR f_col
 LDY #3
 LDA (fz_q),Y
 STA fz_n
 INY
 LDX #0
.fiv1
 STY fz_u
 LDA (fz_q),Y           \ XX3 offset
 TAY
 LDA (fz_v3),Y
 STA R_PXL,X
 INY
 LDA (fz_v3),Y
 STA R_PXH,X
 INY
 LDA (fz_v3),Y
 STA R_PYL,X
 INY
 LDA (fz_v3),Y
 STA R_PYH,X
 LDY fz_u
 INY
 INX
 CPX fz_n
 BCC fiv1
 RTS

\ f_fins: A = k: draw the fins (two-sided triangles standing on the body edge
\ between face1 and face2) with exactly k of those two faces visible

.f_fins
 STA f_k
 LDY #0
 LDA (fz_dt),Y
 STA f_cnt
 LDA fz_dt
 CLC
 ADC #1
 STA fz_q
 LDA fz_dt+1
 ADC #0
 STA fz_q+1
.ffi1
 LDY #0
 LDA (fz_q),Y           \ visibility distance
 CMP f_x4
 BCC ffi8
 LDX #0                 \ X = how many of the two faces are visible
 INY
 LDA (fz_q),Y
 AND #15
 TAY
 LDA (fz_dl),Y
 BEQ ffi2
 INX
.ffi2
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 BEQ ffi3
 INX
.ffi3
 CPX f_k
 BNE ffi8
 JSR f_itemv
 LDA #3
 STA R_PN
 JSR T_POLY
.ffi8
 LDA fz_q               \ the next fin: 7 bytes on
 CLC
 ADC #7
 STA fz_q
 BCC ffi9
 INC fz_q+1
.ffi9
 DEC f_cnt
 BNE ffi1
 RTS

\ f_col: A = a face's or item's colour byte, X = the level (0..31): the
\ colour R_COLE, R_COLO, R_COL2, R_COL3 (rows y AND 3 = 0..3). A = 0..8:
\ entry X of that hue ramp (gfx-light6.asm), a 4x4 dither packed as w = a +
\ 32 b + 1024 c, whose rows are H[a] EOR H[c] EOR HL[b] (H = HL AND &F0);
\ A = &80 + k: the unlit colour k (black, cyan, magenta, yellow)

.fc_fix
 AND #3
 TAY
 LDA LT_FIX,Y
 STA R_COLE
 STA R_COLO
 STA R_COL2
 STA R_COL3
 RTS
.f_col
 TAY
 BMI fc_fix
 LDA LT_RL,Y
 STA fcl+1
 CLC
 ADC #32
 STA fch+1
 LDA LT_RH,Y
 STA fcl+2
 ADC #0
 STA fch+2
.fch
 LDA &FFFF,X            \ patched: w's high byte: c = hi >> 2
 STA fc_hi
 LSR A
 LSR A
 TAY
.fcl
 LDA &FFFF,X            \ patched: w's low byte: a = lo AND 31
 STA fc_lo
 AND #31
 TAX
 FOR r, 0, 3            \ H[a] EOR H[c]
  LDA LT_HL0+17*r,X
  EOR LT_HL0+17*r,Y
  AND #&F0
  STA fc_row+r
 NEXT
 LDA fc_hi              \ b = (hi AND 3) * 8 + lo DIV 32
 AND #3
 ASL fc_lo
 ROL A
 ASL fc_lo
 ROL A
 ASL fc_lo
 ROL A
 TAY
 LDA LT_HL0,Y           \ EOR HL[b]
 EOR fc_row
 STA R_COLE
 LDA LT_HL0+17,Y
 EOR fc_row+1
 STA R_COLO
 LDA LT_HL0+34,Y
 EOR fc_row+2
 STA R_COL2
 LDA LT_HL0+51,Y
 EOR fc_row+3
 STA R_COL3
 RTS
 ASSERT LT_HL1 = LT_HL0 + 17 AND LT_HL2 = LT_HL0 + 34 AND LT_HL3 = LT_HL0 + 51

\ f_poly2: f_item's polygon detail (T_POLY), and a station's docking slot
\ (the only unlit polygon detail: black, colour byte &80 + 4 * its fill
\ visibility) filled and outlined in yellow over that; beyond its fill
\ visibility, just its side from vertex 0 to vertex 1, as Elite draws it.
\ f_itemv has left the vertices in R_PXL..R_PYH and n in fz_n.

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
 LDA fz_n
.fpo2
 PHA
 LDA #1                 \ yellow
 JSR f_setcol
 PLA
.fpo1                   \ A = i + 1 (i = n-1 down to 0): the edge from vertex i
 STA fz_u               \ to vertex (i + 1) MOD n
 SEC
 SBC #1
 LDX #3
 JSR fpo_ld             \ R_X0, R_Y0 = vertex i
 LDA fz_u
 CMP fz_n
 BCC fpo3
 LDA #0
.fpo3
 LDX #7
 JSR fpo_ld             \ R_X1, R_Y1 = vertex (i + 1) MOD n
 JSR T_LINE
 DEC fz_u
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

\ f_behind: C set if the ship being drawn is behind the planet (further away,
\ and its first visible face's first vertex inside the planet's disc)

.f_behind
 LDA F_PLON
 CMP #1                 \ C clear (not behind) if there is no planet
 BCS fbh0
 RTS
.fbh0
 LDX f_si               \ further away than the planet?
 LDA F_PLZL
 CMP F_SZL,X
 LDA F_PLZH
 SBC F_SZH,X
 BCS fbh8               \ planet z >= ship z: in front
 LDY #0                 \ the first visible face: its first vertex
 STY f_f
 LDA fz_ft
 STA fz_p
 LDA fz_ft+1
 STA fz_p+1
.fbh1
 LDY f_f
 CPY f_nf
 BCS fbh8
 LDA (fz_dl),Y
 BNE fbh2
 LDY #0                 \ skip this face's entry (n + 4 bytes)
 LDA (fz_p),Y
 AND #15
 CLC
 ADC #4
 ADC fz_p
 STA fz_p
 BCC fbh1a
 INC fz_p+1
.fbh1a
 INC f_f
 JMP fbh1
.fbh2
 LDY #4                 \ the XX3 offset of the vertex
 LDA (fz_p),Y
 TAY
 LDA (fz_v3),Y          \ dx = x - planet x (16-bit)
 SEC
 SBC F_PLX
 STA fz_t
 INY
 LDA (fz_v3),Y
 SBC F_PLX+1
 JSR f_abs16            \ -> A = |dx| if < 256, else C set
 BCS fbh8
 STA f_bdx
 INY
 LDA (fz_v3),Y          \ dy = y - planet y
 SEC
 SBC F_PLY
 STA fz_t
 INY
 LDA (fz_v3),Y
 SBC F_PLY+1
 JSR f_abs16
 BCS fbh8
 CMP F_PLR              \ |dy| <= r and |dx| <= half-width(|dy|)?
 BEQ fbh3
 BCS fbh8
.fbh3
 TAX
 LDA F_HW,X
 CMP f_bdx
 BCC fbh8
 SEC
 RTS
.fbh8
 CLC
 RTS

\ f_abs16: (A fz_t) 16-bit signed -> A = |value| and C clear if < 256, else
\ C set

.f_abs16
 BPL fab1
 EOR #&FF
 STA fz_u
 LDA fz_t
 EOR #&FF
 CLC
 ADC #1
 STA fz_t
 LDA fz_u
 ADC #0
.fab1
 BNE fab9
 LDA fz_t
 CLC
 RTS
.fab9
 SEC
 RTS

\ f_winding: the face just gathered into R_PXL/R_PYL (low bytes; a far ship is
\ small, so differences fit in 8 bits): C set if it is clockwise on screen
\ (front-facing), i.e. (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0) > 0

.f_winding
 LDA R_PXL+1
 SEC
 SBC R_PXL
 STA fw_a
 LDA R_PYL+2
 SEC
 SBC R_PYL
 JSR f_smul             \ (x1 - x0) * (y2 - y0)
 STA fw_h
 STX fw_l
 LDA R_PYL+1
 SEC
 SBC R_PYL
 STA fw_a
 LDA R_PXL+2
 SEC
 SBC R_PXL
 JSR f_smul             \ (y1 - y0) * (x2 - x0)
 STA fw_t
 STX fw_t+1
 LDA fw_l               \ first - second, 16-bit signed
 SEC
 SBC fw_t+1
 STA fw_l
 LDA fw_h
 SBC fw_t
 BVC fwn1
 EOR #&80
.fwn1
 BMI fwn9               \ negative: a back face
 ORA fw_l
 BEQ fwn9               \ zero: edge-on
 SEC
 RTS
.fwn9
 CLC
 RTS

\ f_smul: A * fw_a, both signed 8-bit -> A (high), X (low), signed 16-bit

.f_smul
 STA fw_b
 STA fw_bo
 LDA #0
 STA fw_t2
 LDX #8
.fsm1                   \ unsigned (fw_a * fw_b), then correct for signs
 LSR fw_b
 BCC fsm2
 CLC
 ADC fw_a
.fsm2
 ROR A
 ROR fw_t2
 DEX
 BNE fsm1
 TAX                    \ A = high byte of the unsigned product
 LDA fw_a               \ if fw_a < 0, high -= original b; if b < 0, high -= a
 BPL fsm3
 TXA
 SEC
 SBC fw_bo
 TAX
.fsm3
 LDA fw_bo
 BPL fsm4
 TXA
 SEC
 SBC fw_a
 TAX
.fsm4
 TXA
 LDX fw_t2
 RTS

.f_dots
 LDA #0
 STA fz_i
.fdo2
 LDX fz_i
 CPX F_NDOT
 BCS fdo8
 LDA F_DC,X
 BPL fdo3
 AND #&7F               \ a ship type: its dot colour
 TAY
 LDA FC_DOTE,Y
 STA R_COLE
 LDA FC_DOTO,Y
 STA R_COLO
 JMP fdo4
.fdo3
 JSR f_setcol
.fdo4
 LDX fz_i
 LDA F_DY,X
 TAY
 LDA F_DS,X
 PHA
 LDA F_DX,X
 TAX
 PLA
 JSR T_DOT
 INC fz_i
 BNE fdo2
.fdo8
 RTS

\ f_lasers: our laser beams (LASLI's four lines from (LASX, LASY) to the
\ bottom of the view)

.f_lasers
 LDA GLASV
 BEQ fla9
 LDA #FC_LASER
 JSR f_setcol
 LDA LASX
 STA fz_t
 LDA LASY
 STA fz_u
 LDX #32
 LDY #191
 JSR f_line8
 LDX #224
 LDY #191
 JSR f_line8
 LDX #48
 LDY #191
 JSR f_line8
 LDX #208
 LDY #191
 JSR f_line8
.fla9
 RTS

\ f_sights: the laser sights, four short arms about (128, 96)

SGX = 128
SGY = 96
SGIN = 11               \ the arms run from SGIN to SGOUT pixels from the centre
SGOUT = 20

.f_sights
 LDA GSIGHT
 BEQ fsg9
 LDA #FC_SIGHT
 JSR f_setcol
 LDX #0
.fsg1
 STX f_sgi
 LDA fsg_x0,X
 STA fz_t
 LDA fsg_y0,X
 STA fz_u
 LDY fsg_y1,X
 LDA fsg_x1,X
 TAX
 JSR f_line8
 LDX f_sgi
 INX
 CPX #4
 BCC fsg1
.fsg9
 RTS

.fsg_x0 EQUB SGX-SGOUT, SGX+SGIN, SGX, SGX
.fsg_x1 EQUB SGX-SGIN, SGX+SGOUT, SGX, SGX
.fsg_y0 EQUB SGY, SGY, SGY-SGOUT, SGY+SGIN
.fsg_y1 EQUB SGY, SGY, SGY-SGIN, SGY+SGOUT

.f_stars                \ stars 1..NOST, recorded by the hooks straight into
 LDA #NOST+1            \ the mailbox's R_SX, R_SY, R_SS (R_SS = 0: none)
 STA R_SN
 JMP T_STARPLOT

\ ------------------------------------------------------------------------------
\ The text: every non-empty cell of the text map, each frame
\ ------------------------------------------------------------------------------

.f_text
 LDA #HI(BUF0)          \ the back buffer's base
 LDX F_BACK
 BEQ ftx0
 LDA #HI(SCREEN%)
.ftx0
 STA f_tbase
 LDA #0
 STA fz_i
.ftx1
 LDX fz_i
 LDA F_TMR,X
 BEQ ftx8               \ an empty row
 TXA                    \ fz_p = the row's cells
 LSR A
 LSR A
 LSR A
 CLC
 ADC #HI(F_TM)
 STA fz_p+1
 TXA
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A
 STA fz_p
 LDA #&FF               \ the drawn columns' extent
 STA f_tmin
 LDA #0
 STA f_tmax
 LDY #0
.ftx2
 LDA (fz_p),Y
 BEQ ftx3
 STY f_tcol
 CPY f_tmin
 BCS ftx2a
 STY f_tmin
.ftx2a
 STY f_tmax
 JSR f_glyph
 LDY f_tcol
.ftx3
 INY
 CPY #32
 BCC ftx2
 LDA f_tmin             \ mark the row's lines dirty over that extent
 ASL A
 ASL A
 ASL A
 CMP R_CL
 BCS ftx4
 LDA R_CL
.ftx4
 STA R_XL
 LDA f_tmax
 ASL A
 ASL A
 ASL A
 ORA #7
 CMP R_CR
 BCC ftx5
 LDA R_CR
.ftx5
 STA R_XR
 LDA fz_i
 ASL A
 ASL A
 ASL A
 TAY
.ftx6
 CPY R_CT
 BCC ftx7
 CPY R_CB
 BEQ ftx6a
 BCS ftx7
.ftx6a
 STY f_tcol
 JSR T_MARKDIRTY
 LDY f_tcol
.ftx7
 INY
 TYA
 AND #7
 BNE ftx6
.ftx8
 INC fz_i
 LDA fz_i
 CMP #24
 BCS ftx9
 JMP ftx1
.ftx9
 RTS

\ f_glyph: character A (32 to 127, from the MOS's font at &C000) at column Y,
\ text row fz_i of the back buffer (f_tbase), in yellow, only on the glyph's
\ pixels and only inside the clip window

F_FONT = &C000

.f_glyph
 SEC
 SBC #32                \ the glyph: F_FONT + 8 * (char - 32)
 STA fz_t
 LDA #0
 STA fz_u
 ASL fz_t
 ROL fz_u
 ASL fz_t
 ROL fz_u
 ASL fz_t
 ROL fz_u
 LDA fz_t
 STA fgl1+1
 STA fglr+1
 LDA fz_u
 CLC
 ADC #HI(F_FONT)
 STA fgl1+2
 STA fglr+2
 TYA                    \ the cell: base + row * &200 + 16 * column
 ASL A
 ASL A
 ASL A
 ASL A
 STA fz_nm              \ (C = bit 4 of the column)
 ORA #8                 \ fz_v3 = the cell's right byte (ORA keeps C)
 STA fz_v3
 LDA fz_i
 ROL A                  \ 2 * row + C (C = 0 after: row <= 23)
 ADC f_tbase
 STA fz_nm+1
 STA fz_v3+1
 LDA #&FF               \ the border columns' masks
 STA fglm+1
 STA fgrm+1
 CPY #0
 BNE fgl5
 LDA #&33               \ pixels 0-1 of column 0 are the border
 STA fglm+1
.fgl5
 CPY #31
 BNE fgl6
 LDA #&CC               \ pixels 254-255 are the border
 STA fgrm+1
.fgl6
 LDA fz_i               \ the first line, y = 8 * row
 ASL A
 ASL A
 ASL A
 STA f_gy               \ (C = 0)
 LDA R_CT               \ the lines inside the clip window: from
 SBC f_gy               \ max(0, R_CT - 8 * row) (less 1: the loop is entered
 BCS fgl7               \ at its INY)
 LDA #&FF
.fgl7
 TAY
 LDA R_CB               \ to min(7, R_CB - 8 * row), none if R_CB < 8 * row
 SEC
 SBC f_gy
 BCC fgl9
 CMP #7
 BCC fgl8
 LDA #7
.fgl8
 CLC
 ADC #1
 STA fgl4+1
 JMP fgl3
.fgl0
.fgl1
 LDA &FFFF,Y            \ patched: the glyph
 BEQ fgl3
 LSR A
 LSR A
 LSR A
 LSR A
 TAX
 LDA f_nib,X
.fglm
 AND #&FF               \ patched: the left border mask
 ORA (fz_nm),Y
 STA (fz_nm),Y
.fglr
 LDA &FFFF,Y            \ patched: the same address as fgl1
 AND #15
 TAX
 LDA f_nib,X
.fgrm
 AND #&FF               \ patched: the right border mask
 ORA (fz_v3),Y
 STA (fz_v3),Y
.fgl3
 INY
.fgl4
 CPY #8                 \ patched: the last line + 1
 BCC fgl0
.fgl9
 RTS

.f_nib                  \ 4 font bits (bit 3 the leftmost) -> MODE 1 pixels in
FOR n, 0, 15            \ yellow (logical colour 3)
 EQUB n * &11
NEXT

\ ------------------------------------------------------------------------------
\ Variables (renderer state, not game state)
\ ------------------------------------------------------------------------------

.F_BACK     EQUB 1      \ the buffer being drawn (the one not on show)
.f_ysav     EQUB 0      \ the entry's Y
.f_zb       SKIP &22+16 \ the game's zero page during a frame (f_zsave)

.F_NSHIP    EQUB 0      \ the ships recorded this frame
.F_SZH      SKIP MAXSH  \ z (hi, lo), for the sort
.F_SZL      SKIP MAXSH
.F_STYP     SKIP MAXSH  \ GTYPE
.F_SNF      SKIP MAXSH  \ number of faces
.F_SPL      SKIP MAXSH  \ -> in F_DL: the XX2 copy (nf bytes), then XX3's
.F_SPH      SKIP MAXSH
.F_ORD      SKIP MAXSH  \ the drawing order (far to near)
.F_SX4      SKIP MAXSH  \ XX4
.F_DLP      EQUW 0      \ the next free byte of F_DL
.f_nv4      EQUB 0

.F_NLINE    EQUB 0      \ the lines recorded this frame
.F_LX0      SKIP MAXLN
.F_LY0      SKIP MAXLN
.F_LX1      SKIP MAXLN
.F_LY1      SKIP MAXLN
.F_LC       SKIP MAXLN  \ colour index
.f_bomb     EQUB 0      \ the energy bomb's bolt: bit 7 set if recorded
.f_bmark    EQUB 0      \ and F_NLINE before it

.F_NDOT     EQUB 0      \ the dots recorded this frame
.F_DX       SKIP MAXDT
.F_DY       SKIP MAXDT
.F_DS       SKIP MAXDT  \ size 1..3
.F_DC       SKIP MAXDT  \ colour index, or &80 + a ship type

.F_PLON     EQUB 0      \ the planet recorded this frame:
.F_PLX      EQUW 0      \ its centre (16-bit signed)
.F_PLY      EQUW 0
.F_PLR      EQUB 0      \ its radius
.F_PLZH     EQUB 0      \ and its z (hi, lo), to hide ships behind it
.F_PLZL     EQUB 0
.F_SUON     EQUB 0      \ the sun recorded this frame:
.F_SUX      EQUW 0      \ its centre
.F_SUY      EQUW 0
.F_SUR      EQUB 0      \ its radius

.F_NCV      EQUB 0      \ the planet curves recorded this frame
.F_CVS      SKIP MAXCV  \ each one's first point
.F_NPT      EQUB 0      \ their points
.F_PXL      SKIP MAXPT
.F_PXH      SKIP MAXPT
.F_PYL      SKIP MAXPT
.F_PYH      SKIP MAXPT

.F_TMR      SKIP 24     \ the text map's non-empty cells, by row
.f_tch      EQUB 0
.f_trow     EQUB 0
.f_tcol     EQUB 0
.f_tmin     EQUB 0
.f_tmax     EQUB 0
.f_tbase    EQUB 0      \ the back buffer's high byte
.f_gy       EQUB 0
.f_sgi      EQUB 0

.f_cx       EQUW 0      \ f_disc's disc
.f_cy       EQUW 0
.f_r        EQUB 0
.f_hwr      EQUB 0      \ the radius F_HW was built for (0 at first: all 0)
.f_hw2r     EQUB 0      \ the radius F_HW2 was built for

.f_si       EQUB 0      \ the ship being drawn
.f_nf       EQUB 0
.f_f        EQUB 0      \ face number
.f_x4       EQUB 0
.f_cnt      EQUB 0      \ item counter (details, fins)
.f_k        EQUB 0      \ fin pass: how many of its two faces are visible
.f_bdx      EQUB 0
.fc_lo      EQUB 0
.fc_hi      EQUB 0
.fc_row     SKIP 4
.fw_a       EQUB 0
.fw_b       EQUB 0
.fw_bo      EQUB 0
.fw_t       EQUW 0
.fw_t2      EQUB 0
.fw_h       EQUB 0
.fw_l       EQUB 0
