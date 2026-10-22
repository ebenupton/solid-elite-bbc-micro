\ ******************************************************************************
\
\ gfx-flare.asm - the lens flare (Model B: in bank F, the frame layer)
\
\ The BBC Master port's lens flare (its gfx-flare.asm and gfx-flare6.asm, from
\ the Demonstration Disc port's, with the same recipe, arithmetic and pixels),
\ rewritten for the NMOS 6502 and for bank F. When the sun is recorded this
\ frame, in the front view, with its centre on the screen (x 1..255, y
\ 0..191) and not inside the planet's disc, eight ghosts go over the frame
\ after the lasers and before the text, sights and stars: at C + k D / 8 (C =
\ (128, 96), D = sun - C), six dithered discs and two dotted rings, each
\ pixel of a disc's 4x4 Bayer mask (its density, rows shifted by the ghost's
\ number) ORed in its ink. OR only lifts the screen's two-bit inks (K = 00 <
\ C = 01, M = 10 < Y = 11): additive light in this palette. Three levels by
\ |dx| + |dy| step every density down the ladder 0, 1, 2, 4, 6, 8 / 16.
\
\ Model B: bank F writes the back buffer itself (main RAM), and as it cannot
\ reach bank R's dirty extents, each ghost's box (its rows by its columns,
\ clipped) is marked dirty through T_MARKBOX, so that the next frame on this
\ buffer repairs it: the flare keeps no state on the screen. (The Master
\ port marked each row's span exactly; a box marks a little more.)
\
\ ******************************************************************************

\ Zero page: the rasteriser's scratch &10-&27, which F_FRAME saves and
\ restores, and &06, &07 and &0E (saved too, and set again before any use
\ after the flare); R_XL and R_XR (&08, &09) are a span's ends

fl_lq   = &06           \ a span's first byte's mask (before the row's)
fl_rq   = &07           \ its last byte's
fl_t    = &0E
fl_dx   = &10           \ the sun's x - 128 (signed)
fl_dy   = &11           \ the sun's y - 96 (signed; fl_dx + 1)
fl_u    = &12           \ the ghost's ink
fl_i    = &13           \ the next ghost's number
fl_gx   = &16           \ the ghost's centre (on the screen when the sun's
fl_gy   = &17           \ centre is, as |k| <= 8: all 8-bit)
fl_r    = &18           \ a disc's radius (a ring: the step, 2 or 4)
fl_hw   = &19           \ a disc's half-width table (a ring: dx, dy)
fl_pat  = &1B           \ the ghost's ink masks for rows y AND 3 = 0..3
fl_d    = &1F           \ a disc's row offset d (a ring: the point's offset)
fl_m    = &20           \ the row's mask (fl_or: the middle bytes')
fl_sp   = &21           \ screen pointer (fl_or)
fl_n    = &23           \ 8 * (bytes - 1) (fl_or)
fl_ch   = &24           \ base + (a span's first byte's column >= 32)
fl_x    = &25           \ (X kept across fl_dots and fl_disc, for PHX/PLX)
fl_cl   = &27           \ 8 x a span's first byte's column, low byte

FLNG = 8                \ ghosts
FLHMAX = 26             \ the ring round the sun only for a sun this small

\ f_flt: F_FRAME's flare step, after the lasers. Without the sun it costs a
\ test. With it: when the view is the front one and the sun's centre is on
\ the screen (x 1..255, y 0..191) and not inside the planet's disc (F_HW has
\ the planet's half-widths, built this frame), the flare with fl_dx and
\ fl_dy (the centre less (128, 96)).

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
 LDA F_PLON             \ behind the planet? (inside its disc)
 BEQ flt1
 LDX #2
 JSR fl_pd              \ |sy - py|
 BNE flt1
 CPY F_PLR
 BEQ P%+4
 BCS flt1
 LDA F_HW,Y
 STA fl_t
 LDX #0
 JSR fl_pd              \ |sx - px|
 BNE flt1
 CPY fl_t
 BCC flt9
 BEQ flt9
.flt1
 JMP fl_flare
.flt9
 RTS

\ fl_pd: X = 0: |F_SUX - F_PLX|, X = 2: |F_SUY - F_PLY| in Y, with Z = 1 if
\ it is below 256 (Z = 0: further apart)

.fl_pd
 LDA F_SUX,X
 SEC
 SBC F_PLX,X
 TAY
 LDA F_SUX+1,X
 SBC F_PLX+1,X
 BEQ fl_ret             \ 0..255
 CLC
 ADC #1
 BNE fl_ret             \ (not -256..-1: Z = 0)
 TYA                    \ -255..-1: Y = - low byte (-256: Z = 0)
 BEQ fpq8
 EOR #&FF
 TAY
 INY
 LDA #0
.fl_ret
 RTS
.fpq8
 LDA #&FF
 RTS

\ fl_flare: the flare over this frame, on the back buffer F_BACK

.fl_flare
 LDX F_BACK             \ the buffer's screen base / 2, for fl_ch
 LDA fl_base,X
 STA fl_cb1+1
 STA fl_cb2+1
 LDA fl_dx              \ level 3 if |dx| + |dy| < 96, 2 if < 192, else 1
 JSR fl_abs
 STA fl_t
 LDA fl_dy
 JSR fl_abs
 CLC
 ADC fl_t
 LDX #3
 CMP #96
 BCC flm2
 DEX
 CMP #192
 BCC flm2
 DEX
.flm2
 STX fl_lev
 LDX #1                 \ the centres' sums (x, then y): S = 32 k D, k = 8
.flm0                   \ to start (S = 256 D), stepped down by 32 D (|S| <
 LDA fl_dx,X            \ 2^15: the centre's offset k D / 8, floored, is S's
 STA fl_sh,X            \ high byte)
 LDA #0
 STA fl_sl,X
 LDA fl_dx,X            \ 32 D: D >> 3 (arithmetic), (D AND 7) << 5
 CMP #&80
 ROR A
 CMP #&80
 ROR A
 CMP #&80
 ROR A
 STA fl_mh,X
 LDA fl_dx,X
 AND #7
 LSR A
 ROR A
 ROR A
 ROR A
 STA fl_ml,X
 DEX
 BPL flm0
 LDA #0
 STA fl_i
 JMP flm3

.flm8                   \ the sums for the next ghost: S -= (k - k') 32 D
 LDY fl_dk,X
 STX fl_x
.flc1
 LDX #1
.flc2
 SEC
 LDA fl_sl,X
 SBC fl_ml,X
 STA fl_sl,X
 LDA fl_sh,X
 SBC fl_mh,X
 STA fl_sh,X
 DEX
 BPL flc2
 DEY
 BNE flc1
 LDX fl_x
 JMP flm4

.flm3                   \ the next ghost
 LDX fl_i
 CPX #FLNG
 BCC flm3a
 RTS
.flm3a
 INC fl_i
 TXA                    \ k = 8: the ring round the sun, if the sun is small
 BNE flm8
 LDA F_SUR
 CMP #FLHMAX+1
 BCS flm3
.flm4
 LDA fl_ni,X            \ density index + level - 3 (none if 0 or less)
 AND #&7F
 CLC
 ADC fl_lev
 SBC #2                 \ (C = 0: - 3)
 BEQ flm3
 BMI flm3
 STA fl_m
 LDA fl_sh              \ centre = (128, 96) + (k D) >> 3
 EOR #&80
 STA fl_gx
 LDA fl_sh+1
 CLC
 ADC #96
 STA fl_gy
 LDA fl_ink,X
 STA fl_u
 LDA fl_ni,X
 BPL flm5
 JSR fl_dots            \ a dotted ring, radius 15 << scale
 LDX fl_x
 LDA #15
 LDY fl_rad,X
 BEQ P%+3
 ASL A
 JMP flm6
.flm5
 JSR fl_disc            \ a disc
 LDX fl_x
 LDA fl_rad,X
.flm6
 JSR fl_box             \ its box, marked dirty
 JMP flm3

\ fl_box: mark rows gy - A .. gy + A by columns gx - A .. gx + A, clipped to
\ the window (2..253 by 1..191), dirty (T_MARKBOX)

.fl_box
 STA fl_t
 LDA fl_gx              \ R_XL = max(gx - r, 2)
 SEC
 SBC fl_t
 BCS P%+4
 LDA #0
 CMP #2
 BCS P%+4
 LDA #2
 STA R_XL
 LDA fl_gx              \ R_XR = min(gx + r, 253)
 CLC
 ADC fl_t
 BCS fbx1
 CMP #254
 BCC fbx2
.fbx1
 LDA #253
.fbx2
 STA R_XR
 LDA fl_gy              \ the last row, min(gy + r, 191)
 CLC
 ADC fl_t
 BCS fbx3
 CMP #192
 BCC fbx4
.fbx3
 LDA #191
.fbx4
 STA R_BY1
 LDA fl_gy              \ the first, max(gy - r, 1)
 SEC
 SBC fl_t
 BCC fbx5
 BNE fbx6
.fbx5
 LDA #1
.fbx6
 TAY
 CPY R_BY1
 BEQ P%+4
 BCS fbx9
 LDA R_XR
 CMP R_XL
 BCC fbx9
 JMP T_MARKBOX
.fbx9
 RTS

\ fl_abs: A = |A| (A from a load: N its sign; A > -128)

.fl_abs
 BPL P%+7
 EOR #&FF
 CLC
 ADC #1
 RTS

\ fl_disc: ghost X, a disc (centre fl_gx, fl_gy; ink fl_u; density index
\ fl_m): its radius, half-widths and four row masks, then rows max(gy - r,
\ 1)..min(gy + r, 191) whose mask is not zero, each the span gx - h..gx + h
\ (h = the half-width at |y - gy|) clipped to x = 2..253: by d = |y - gy|
\ from r down to 0, rows gy - d and gy + d sharing the span. Keeps X in fl_x.

.fl_disc
 STX fl_x
 LDA fl_rad,X           \ radius, half-widths
 STA fl_r
 LDA fl_hl,X
 STA fl_hw
 LDA #HI(fl_htab)
 STA fl_hw+1
 STX fl_d               \ masks[index][(j + number) AND 3] AND ink, j = 0..3
 LDA fl_m
 ASL A
 ASL A
 STA fl_t
 LDY #3
.flm7
 TYA
 CLC
 ADC fl_d
 AND #3
 ORA fl_t
 TAX
 LDA fl_mt,X
 AND fl_u
 STA fl_pat,Y
 DEY
 BPL flm7
 LDA fl_r
 STA fl_d
.fsd1                   \ d (r down to 0): either row's mask not zero?
 LDA fl_gy
 SEC
 SBC fl_d
 AND #3
 TAX
 LDA fl_pat,X
 BNE fsd5
 LDA fl_gy
 CLC
 ADC fl_d
 AND #3
 TAX
 LDA fl_pat,X
 BEQ fsd8
.fsd5                   \ the span gx - h..gx + h, clipped
 LDY fl_d
 LDA (fl_hw),Y
 TAX
 EOR #&FF               \ XL = max(gx - h, 2)
 SEC
 ADC fl_gx
 BCS P%+4
 LDA #0
 CMP #2
 BCS P%+4
 LDA #2
 STA R_XL
 TXA                    \ XR = min(gx + h, 253)
 CLC
 ADC fl_gx
 BCS P%+6
 CMP #254
 BCC P%+4
 LDA #253
 STA R_XR
 CMP R_XL
 BCC fsd8
 AND #3                 \ the last byte's mask, the first's, the first's
 TAX                    \ column (x 8) and 8 x (bytes - 1), shared by the
 LDA fl_rmt,X           \ two rows
 STA fl_rq
 LDA R_XL
 AND #3
 TAX
 LDA fl_lmt,X
 STA fl_lq
 LDA R_XL
 AND #&FC
 STA fl_t
 ASL A
 STA fl_cl
.fl_cb1
 LDA #&20               \ (patched: the buffer's base / 2; + C)
 ROL A
 STA fl_ch
 LDA R_XR
 AND #&FC
 SEC
 SBC fl_t
 ASL A
 STA fl_n
 BNE fsd2
 LDA fl_lq              \ one byte: both masks
 AND fl_rq
 STA fl_lq
.fsd2
 LDA fl_gy              \ row gy - d, if >= 1
 SEC
 SBC fl_d
 BCC fsd3
 BEQ fsd3
 JSR fl_row
.fsd3
 LDA fl_d               \ row gy + d, if d > 0 and gy + d <= 191
 BEQ fsd8
 CLC
 ADC fl_gy
 CMP #192
 BCS fsd8
 JSR fl_row
.fsd8
 DEC fl_d
 BMI P%+5
 JMP fsd1
 RTS

\ fl_dots: ghost X, a dotted ring (centre fl_gx, fl_gy; ink fl_u; density
\ index fl_m): fl_ring's points (times 2 ^ its scale), every one at density
\ index 3 or more, else every other one, in all four quadrants (the points
\ on the axes once each), each ORed in its ink where it is inside the clip
\ window. Keeps X in fl_x.

.fl_dots
 STX fl_x
 LDY #2                 \ the step: every point (2 bytes on) at index 3 or
 LDA fl_m               \ more, else every other one (4)
 CMP #3
 BCS P%+4
 LDY #4
 STY fl_r
 LDA fl_rad,X           \ (its scale)
 STA fl_t
 LDA #&FF               \ every row's mask: all (fl_lq has the pixel's), one
 STA fl_m               \ byte
 LDA #0
 STA fl_n
 LDX #0
.fsr1
 STX fl_d
 LDA fl_ring,X          \ dx, dy
 LDY fl_t
 BEQ P%+3
 ASL A
 STA fl_hw
 LDA fl_ring+1,X
 CPY #0
 BEQ P%+3
 ASL A
 STA fl_hw+1
 LDA fl_gx              \ columns gx + dx and gx - dx
 CLC
 ADC fl_hw
 BCS P%+5
 JSR fl_dcol
 LDA fl_hw              \ (dx = 0: the same column)
 BEQ fsr2
 LDA fl_gx
 SEC
 SBC fl_hw
 BCC P%+5
 JSR fl_dcol
.fsr2
 LDA fl_d
 CLC
 ADC fl_r
 TAX
 CPX #18
 BCC fsr1
 RTS

\ fl_dcol: a dotted ring's column A: rows gy + dy and gy - dy

.fl_dcol
 CMP #2
 BCC fsc9
 CMP #254
 BCS fsc9
 TAY
 AND #&FC               \ its byte's column (fl_cl, fl_ch), pixel mask
 ASL A
 STA fl_cl
.fl_cb2
 LDA #&20               \ (patched: the buffer's base / 2; + C)
 ROL A
 STA fl_ch
 TYA
 AND #3
 TAX
 LDA fl_pxm,X
 AND fl_u
 STA fl_lq
 LDA fl_gy              \ (gy + dy <= 191 + 30: no carry)
 CLC
 ADC fl_hw+1
 JSR fl_drow
 LDA fl_hw+1            \ (dy = 0: the same row)
 BEQ fsc9
 LDA fl_gy
 SEC
 SBC fl_hw+1
 BCC fsc9
.fl_drow                \ row A, if inside the clip window
 CMP #1
 BCC fsc9
 CMP #192
 BCS fsc9
 TAY
 JMP fl_row1
.fsc9
 RTS

\ fl_row: row A (inside the clip window), if its mask (fl_pat) is not zero:
\ point fl_sp at its first byte (column fl_cl / fl_ch) and OR the bytes
\ (fl_or, with the row's mask fl_m). Clobbers A, X, Y.

.fl_row
 TAY
 AND #3
 TAX
 LDA fl_pat,X
 BEQ fsc9
 STA fl_m
.fl_row1                \ (Y = row, fl_m = its mask)
 TYA                    \ base + (y DIV 8) * &200 + (y MOD 8) + 8 * (XL DIV 4)
 AND #7
 ORA fl_cl
 STA fl_sp
 TYA
 LSR A
 LSR A
 AND #&FE
 CLC                    \ (Model B: ADC, as buffer 0's base, &10, is not
 ADC fl_ch              \ aligned for the Master's ORA)
 STA fl_sp+1
                        \ (and on into fl_or)

\ fl_or: OR the span at fl_sp into the back buffer: its last byte (offset
\ fl_n) with fl_rq AND fl_m, then if fl_n > 0 the bytes between with fl_m and
\ its first with fl_lq AND fl_m (fl_n = 0: the one byte, with fl_lq AND
\ fl_m). Clobbers A, Y.

.fl_or
 LDY fl_n
 BEQ flo9
 LDA fl_rq
 AND fl_m
 ORA (fl_sp),Y
 STA (fl_sp),Y
 SEC
 BCS flo3
.flo2
 LDA (fl_sp),Y
 ORA fl_m
 STA (fl_sp),Y
.flo3
 TYA
 SBC #8
 TAY
 BNE flo2
.flo9
 LDA fl_lq
 AND fl_m
 ORA (fl_sp),Y
 STA (fl_sp),Y
 RTS

\ The tables (the Master port's 2-build-files/flare.py: GHOSTS, LADDER,
\ BAYER, RING, hw_table)

                        \ the ghosts, by number (k = 8, 5, 3, -1, -3, -4, -6,
                        \ -8: centre C + k D / 8; 8: the ring round the sun):
                        \ radius (a ring: its scale, 1 for 30, 0 for 15), ink,
                        \ density index (+ &80: a dotted ring), half-widths
.fl_rad EQUB 1, 4, 7, 3, 10, 5, 0, 18
.fl_ink EQUB &FF, &FF, &F0, &0F, &0F, &FF, &F0, &0F
.fl_ni  EQUB &83, 4, 3, 5, 3, 3, &83, 2
.fl_hl  EQUB 0, LO(fl_h4), LO(fl_h7), LO(fl_h3), LO(fl_h10), LO(fl_h5), 0, LO(fl_h18)

fl_mt = P% - 4          \ row masks of densities 1, 2, 4, 6, 8 / 16 (4x4
                        \ Bayer), by density index (1..5) and row
 EQUB &88, &00, &00, &00
 EQUB &88, &00, &22, &00
 EQUB &AA, &00, &AA, &00
 EQUB &AA, &44, &AA, &11
 EQUB &AA, &55, &AA, &55

.fl_dk  EQUB 0, 3, 2, 4, 2, 1, 2, 2 \ the k steps 8 -> 5 -> 3 -> -1 -> -3 ->
                                    \ -4 -> -6 -> -8, by ghost
.fl_lmt EQUB &FF, &77, &33, &11     \ pixels x AND 3..3 of a byte
.fl_rmt EQUB &88, &CC, &EE, &FF     \ pixels 0..x AND 3
.fl_pxm EQUB &88, &44, &22, &11     \ pixel x AND 3
.fl_ring                \ (dx, dy) of 9 points of a quarter circle of radius 15
 EQUB 15, 0, 15, 3, 14, 6, 12, 8, 11, 11, 8, 12, 6, 14, 3, 15, 0, 15
.fl_base EQUB HI(BUF0) DIV 2, HI(SCREEN%) DIV 2   \ (by buffer)

.fl_ml  SKIP 2          \ 32 D (x, y), low and high bytes
.fl_mh  SKIP 2
.fl_sl  SKIP 2          \ the centres' sums S (x, y)
.fl_sh  SKIP 2
.fl_lev SKIP 1          \ the level, 1..3

 ALIGN &100             \ (the half-widths: one page, fl_hw's high byte fixed)
.fl_htab                \ the widest x with x^2 + d^2 <= r^2 + r, d = 0..r
MACRO FLHW r
 FOR d, 0, r
  EQUB INT(SQR(r * r + r - d * d))
 NEXT
ENDMACRO
.fl_h3  FLHW 3
.fl_h4  FLHW 4
.fl_h5  FLHW 5
.fl_h7  FLHW 7
.fl_h10 FLHW 10
.fl_h18 FLHW 18
 ASSERT HI(fl_htab) = HI(P% - 1)
