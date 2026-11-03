\ ******************************************************************************
\
\ gfx-flare6.asm - the lens flare's step in the frame (see gfx-flare.asm)
\
\ Port (Model B): the BBC Master port's gfx-flare6.asm; R_FLARE is in this
\ bank too, called directly.
\
\ ******************************************************************************

\ (Its zero page is defined in gfx-flare.asm, assembled first.)

\ f_flt: F_FRAME's text step, after the flare (in place of JSR f_text2).
\ Without the sun (F_SUON = 0) it costs a test. With it: when the view is the
\ front one and the sun's centre is on the screen (x 1..255, y 0..191), the
\ flare (R_FLARE) with fl_dx and fl_dy (the centre less (128, 96)), and
\ FL_BEH bit 7 if the sun is smaller than the planet, so further: behind it
\ (R_FLARE's probes then test the planet's disc).

.f_flt
 LDA F_SUON
 BEQ flt9
 LDA VIEW               \ the front view, and the sun's centre on the
 ORA F_SUX+1            \ screen: x 1..255, y 0..191
 ORA F_SUY+1
 BNE flt9
 LDA F_SUX
 BEQ flt9
 EOR #&80
 STA fl_dx
 LDA F_SUY
 CMP #192
 BCS flt9
 SBC #95                \ (C = 0: - 96)
 STA fl_dy
 LDA #0                 \ FL_BEH bit 7: the sun is smaller than the planet
 LDX F_PLON
 BEQ flt1
 LDX F_SUR
 CPX F_PLR
 ROR A                  \ (C clear: smaller)
 EOR #&80
.flt1
 STA FL_BEH
 JSR R_FLARE
.flt9
 JMP f_text2

.FL_BEH EQUB 0          \ bit 7: the sun is behind the planet (R_FLARE's probes)
