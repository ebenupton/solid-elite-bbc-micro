\ ******************************************************************************
\
\ gfx-hangar.asm - the ship hangar: one frame of the renderer (bank 6)
\
\ Port (Model B): the BBC Master port's gfx-hangar.asm and gfx-hangar6.asm
\ (its tables, here at this file's end), in NMOS 6502 code. The original's
\ hangar (HALL, HAS1, HANGER) draws the ships with LL9 and then the
\ hangar's lines directly, each line running in from the screen's edge until
\ it meets something already drawn. Here the hangar is a space-view frame
\ (docs/renderer.md, "The hangar"): HALL clears the screen with TT66 as
\ before and calls F_HANG0 (GCALL), which empties the frame's lists (a
\ docking leaves the last flight iteration's records in them; the hangar's
\ light is the docked code's fixed light, LLT, gfx-light.asm);
\ HAS1 places each ship as before, and LL9 records it (record mode: QQ11 =
\ 0, GFORCE = 0); TT66's view name is in the text map. HALL then calls
\ F_HANGAR, which draws the frame with F_FRAME, its call of f_lines pointed
\ at f_hback for this frame only: the hangar's background goes in after the
\ (empty) disc layer and before the ships, so the ships hide it where the
\ original's lines stopped at them, and the flight's frames run exactly as
\ before (no test, no cost).
\
\ The background: the back wall a darker tan and the floor a light tan, each
\ a flat 2x2 dither (HPWL, HPWH, below), with HANGER's
\ lines over them in black: the floor's at y = #Y + 130 DIV Q for Q = 2 to
\ 12, from x = 2 to 253, and the wall's every 8 pixels, x = 8 to 248, from
\ the top to the floor's furthest line. The wall starts below the view's
\ name (TT66's, in yellow, which the wall's tan, half yellow, swallows): a
\ black band, rows 1 to 15, is left above it.
\
\ ******************************************************************************

HTOP = 16               \ the wall's top row: text row 1, the view's name, is on
                        \ black above it

\ F_HANGAR: the hangar's frame (from HALL). Keeps Y

.F_HANGAR
 STY fh_y
 LDX #LO(f_hback)
 LDY #HI(f_hback)
 JSR fhg_pat            \ (fhg_pat restores Y)
 JSR F_FRAME
 LDX #LO(f_lines)
 LDY #HI(f_lines)
 JMP fhg_pat            \ and returns with Y restored
.fhg_pat
 STX ff_lin+1
 STY ff_lin+2
 LDY fh_y               \ the caller's Y
 RTS
.fh_y EQUB 0

\ F_HANG0: before the hangar's ships are recorded: the frame's lists emptied.
\ Keeps Y

.F_HANG0
 STY f_ysav
 JMP f_reset

\ f_hback: the background, in place of f_lines's call (F_FRAME's ff_lin),
\ then the lines recorded (none: f_lines is the frame's own)

.f_hback
 LDA #0                 \ (NMOS: A = 0 for the clears)
 STA fz_t               \ x = 0 to 254 (the clip window stops at 253)
 LDX #3                 \ the rectangles' vertices' high bytes: 0
.fhb0
 STA R_PXH,X
 STA R_PYH,X
 DEX
 BPL fhb0
 ASSERT HI(HPWL) = HI(HPWH)
 LDA #LO(HPWL)          \ f_col's packed colours: the wall's and the floor's
 STA fcl+1
 LDA #LO(HPWH)
 STA fch+1
 LDA #HI(HPWL)          \ (the two tables share a page)
 STA fcl+2
 STA fch+2
 LDA #255
 STA fz_u
 INX                    \ the wall (X = 0: the loop left &FF): from row HTOP
 JSR fch                \ (rows 1 to HTOP-1 stay black, a band behind the
 LDA #HTOP              \ view's name: its yellow is the wall's own) to the
 LDY HFY                \ floor's furthest line
 JSR fh_rect
 LDX #1                 \ the floor: from there to the bottom
 JSR fch
 LDA HFY
 LDY #192
 JSR fh_rect
 LDA #FC_BLACK          \ the lines: black, solid
 JSR f_setcol
 STA R_COL3
 STA R_COL2
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
 STA fz_u               \ the floor's furthest line (R_LINE: a thin R_POLY is
 LDA #248               \ slower)
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

\ HFY: the floor's lines far to near (#Y + 130 DIV Q, Q = 12 down to 2, as
\ HANGER's DVID4K computed them); the first is the wall's foot

.HFY
FOR q, 12, 2, -1
 EQUB Y + 130 DIV q
NEXT

\ HPWL, HPWH: the wall's and the floor's colours in f_col's packed form
\ (hangarcols.py, docs/renderer.md): the wall a darker tan, two yellow, a magenta
\ and a black pixel in each 2x2 cell (RGB about 191, 128, 64), the floor a
\ light tan, two yellow, a magenta and a cyan (about 191, 191, 128). Ink
\ counts in quarters make f_col's 4x4 Bayer tile a 2x2 one, yellow on a
\ diagonal: a regular pattern, no banding

.HPWL
 EQUB &08, &88
.HPWH
 EQUB &31, &41

