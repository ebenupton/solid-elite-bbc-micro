\ ******************************************************************************
\
\ gfx-hangar.asm - the ship hangar: one frame of the renderer (Model B: bank F)
\
\ The BBC Master port's hangar (its gfx-hangar.asm), rewritten for the NMOS
\ 6502. The original's HALL draws the ships with LL9 and then the hangar's
\ lines directly, each line running in from the screen's edge until it meets
\ something already drawn. Here the hangar is a space-view frame: HALL clears
\ the screen with TT66 as before and calls F_HANG0, which empties the
\ frame's lists and sets the hangar's light; HAS1 places each ship as before,
\ and LL9 records it (record mode: QQ11 = 0, GFORCE = 0); TT66's view name is
\ in the text map. HALL then calls F_HANGAR in place of HANGER, which draws
\ the frame with F_FRAME, its call of f_lines pointed at f_hback for this
\ frame only: the hangar's background goes in after the discs and before the
\ ships, so the ships hide it where the original's lines stopped at them.
\
\ The background: the back wall magenta and black and the floor yellow and
\ magenta, each a flat 2x2 dither, with HANGER's lines over them in black:
\ the floor's at y = #Y + 130 DIV Q for Q = 2 to 12, from x = 2 to 253, and
\ the wall's every 8 pixels, x = 8 to 248, from the top to the floor's
\ furthest line. The wall starts below the view's name: a black band, rows 1
\ to 15, is left above it.
\
\ ******************************************************************************

HTOP = 16               \ the wall's top row: text row 1, the view's name, is on
                        \ black above it

\ F_HANGAR: the hangar's frame (from HALL)

.F_HANGAR
 STY fh_y               \ (every entry keeps Y)
 LDX #LO(f_hback)
 LDY #HI(f_hback)
 JSR fhg_pat
 LDY fh_y
 JSR F_FRAME
 LDX #LO(f_lines)
 LDY #HI(f_lines)
 JSR fhg_pat
 LDY fh_y
 RTS
.fhg_pat
 STX ff_lin+1
 STY ff_lin+2
 RTS
.fh_y EQUB 0

\ F_HANG0: before the hangar's ships are recorded: the hangar's light (LLT,
\ gfx-light.asm: towards the top right and the viewer), and the frame's
\ lists emptied

.F_HANG0
 STY f_ysav
 LDX #2
.fhg0
 LDA fhlt,X
 STA LLT,X
 DEX
 BPL fhg0
 JMP f_reset

.fhlt EQUB 24, 24, &E8

\ f_hback: the background, in place of f_lines's call (F_FRAME's ff_lin),
\ then the lines recorded (none: f_lines is the frame's own)

.f_hback
 LDX #3                 \ the rectangles' vertices' high bytes: 0
 LDA #0
.fhb0
 STA R_PXH,X
 STA R_PYH,X
 DEX
 BPL fhb0
 STA fz_t               \ x = 0 to 254 (the clip window stops at 253)
 LDA #255
 STA fz_u
 LDA #&A0               \ the wall: magenta and black, from row HTOP to the
 LDX #&50               \ floor's furthest line
 JSR fh_col
 LDA #HTOP
 LDY HFY
 JSR fh_rect
 LDA #&FA               \ the floor: yellow and magenta, from there to the
 LDX #&F5               \ bottom
 JSR fh_col
 LDA HFY
 LDY #192
 JSR fh_rect
 LDA #0                 \ the lines: black, solid
 TAX
 JSR fh_col
 LDA #2                 \ the floor's lines, x = 2 to 253, near to far (rows
 STA fz_t               \ HFY[10] to HFY[0]), as one-row rectangles (R_POLY
 LDA #254               \ fills a row much faster than R_LINE steps along it)
 STA fz_u
 LDX #10
.fhb2
 STX fz_i
 LDA HFY,X
 TAY
 INY
 JSR fh_rect
 LDX fz_i
 DEX
 BPL fhb2
 LDA #HTOP              \ the wall's lines, x = 248 down to 8, from row HTOP to
 STA fz_u               \ the floor's furthest line
 LDA #248
.fhb3
 STA fz_t
 TAX
 LDY HFY
 JSR f_line8
 LDA fz_t
 SEC
 SBC #8
 BNE fhb3
 JMP f_lines

\ fh_col: R_COLE = R_COL2 = A, R_COLO = R_COL3 = X: a 2x2 dither for both
\ R_POLY's rows and R_LINE's

.fh_col
 STA R_COLE
 STA R_COL2
 STX R_COLO
 STX R_COL3
 RTS

\ fh_rect: fill pixels fz_t to fz_u-1 of rows A to Y-1 (R_POLY's rule) in the
\ colour set

.fh_rect
 STA R_PYL
 STA R_PYL+1
 STY R_PYL+2
 STY R_PYL+3
 LDA fz_t
 STA R_PXL
 STA R_PXL+3
 LDA fz_u
 STA R_PXL+1
 STA R_PXL+2
 LDA #4
 STA R_PN
 JMP T_POLY

.HFY                    \ the floor's lines' rows, far to near
FOR q, 12, 2, -1
 EQUB 96 + 130 DIV q
NEXT
