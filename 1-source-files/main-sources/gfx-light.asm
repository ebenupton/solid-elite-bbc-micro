\ ******************************************************************************
\
\ gfx-light.asm - flat-shaded lighting of the ships (docs/renderer.md,
\ "Lighting")
\
\ Port (Model B): the BBC Master port's gfx-light.asm (from the Demonstration
\ Disc port's shade7.asm, branch lighting), in NMOS 6502 code, INCLUDEd in
\ the hot pass of each program (bank 4: the game's context, where the game's
\ quarter squares QSL/QSH are, the only copy), from the block L_REC of
\ elite-source-flight.asm (with L_SUN: LIGHT_SUN = TRUE) and
\ elite-source-docked.asm (without). The model is lightramps.py: a face's
\ light is I = 0.5 + 0.5 max(0, n.L) for its unit normal n and L the unit
\ vector towards the light, entry round(31 max(0, n.L)) of its hue's
\ 32-entry ramp of 4x4 dithers (one pool of nine hue ramps shared by every
\ ship, each from 50% to 100% of the hue's own full brightness:
\ gfx-light6.asm, bank 6). The frame layer's f_col (gfx-frame.asm, bank 6)
\ turns a level into the four row bytes at drawing time.
\
\ L_SUN (MFRAME, once per main-loop iteration in a space view, before the
\ frame) keeps LV, the unit vector towards the sun in view space (x right, y
\ up, z in; 16-bit signed, 1 = &4000), and LLT = LV * 41.3 (signed bytes)
\ for the next iteration's ships:
\   * slot 1 (FRIN+1) is the sun (type 129): LV = the sun's position,
\     normalised, when it has just appeared and every 32nd iteration; on the
\     others LV is rotated by our roll and pitch as MV40 rotates the planet
\     and sun (the sun is so far away that our own movement does not turn it);
\   * slot 1 is the space station (the safe zone: the station has replaced
\     the sun): LV keeps being rotated, so the light stays continuous, and is
\     re-seeded from the sun when it is back;
\   * slot 1 is empty (no local universe): the fixed light (1, 1, -1) /
\     sqrt 3, from the top right into the screen. The docked code's light
\     (the title, the hangar, the briefings) is always this one.
\
\ L_REC (S_SHIP, as LL9's part 6 starts, before the ship is recorded): the
\ light in the ship's own coordinates, Ls[a] = (a . LLT + 16) >> 5 for the
\ orientation vectors a = sidev, roofv, nosev (their high bytes halved: 48 =
\ 1), |Ls| <= 64, 62 for a unit vector; then for each visible face, d = (n .
\ Ls + 16) >> 5 for its unit normal n in blueprint coordinates (magnitude 61,
\ FC_NORMTAB, loaded with the blueprints, from faces.py) is about 118 (n . L), and its
\ level is min(31, (d + d / 16 + 2) / 4), or 0 if n . Ls < 0 (a ship vertex
\ v is v_x sidev + v_y roofv + v_z nosev in view space, and so is a normal,
\ whether the orientation is a rotation or, as the station's until its
\ first TIDY, a reflection). The level replaces the face's byte in XX2,
\ which the frame layer's F_SHIP then copies into the ship's record:
\   0                    hidden (as before)
\   &80 + level          visible
\   &C0 + level          visible, XX2 was 255 (Elite skipped the normal
\                        test: the frame layer culls it by its winding),
\                        plus &20 if the ship is mirrored from the face
\                        lists' handedness (GHAND: TIDY's, not ZINF's)
\ so a face stays visible (non-zero) or hidden (zero) for LL9's part 6, and
\ a hidden face's level is 0 (ambient), which the fins standing on it take.
\
\ Products are exact: a * b = QS(|a + b|) - QS(|a - b|) for the quarter
\ squares QS(n) = n^2 / 4 (QSL/QSH, rounded down: the roundings cancel, as
\ a + b and a - b have the same parity), summed in 16 bits and rounded once.
\
\ Only the lighting's own variables (below) and XX2 (a drawing temporary,
\ written by LL9's part 5 before every use) are written: none of it is game
\ state.
\
\ ******************************************************************************

IF LIGHT_SUN            \ (the flight code only: the docked code's light is fixed)
\ ------------------------------------------------------------------------------
\ L_SUN
\ ------------------------------------------------------------------------------

.L_SUN
 LDA FRIN+1
 BEQ ls_fix             \ no slot 1 (title screen): the fixed light
 CMP #129
 BNE ls_rot             \ the station: keep rotating LV
 BIT lv_ok              \ the sun: seed LV from it when it has just appeared
 BVC ls_seed            \ (bit 6 clear) and every 32nd iteration
 INC lv_cnt
 LDA lv_cnt
 AND #31
 BEQ ls_seed
.ls_rot
 BIT lv_ok
 BMI ls_r1
 LDX #2                 \ LV not set up yet (the safe zone from the start):
.ls_r0                  \ start from the fixed light, (1, 1, -1) / sqrt 3
 LDA lv_defl,X
 STA LVL,X
 LDA lv_defh,X
 STA LVH,X
 DEX
 BPL ls_r0
 LDA #&80
 STA lv_ok
.ls_r1
 JSR lv_rot
 JMP lv_ll
.ls_fix
 STA lv_ok              \ (NMOS: A = 0, FRIN+1)
 LDA #24
 STA LLT
 STA LLT+1
 LDA #&E8               \ -24
 STA LLT+2
 RTS

.lv_x3   EQUB 0, 3, 6   \ (lse9)
.lv_defl EQUB LO(&24F3), LO(&24F3), LO(-&24F3)    \ &4000 / sqrt 3
.lv_defh EQUB HI(&24F3), HI(&24F3), HI(-&24F3)

.ls_seed                \ LV = the sun's position (K% + NI%), normalised
 LDX #8                 \ |x|, |y|, |z| as 24-bit (lo, hi, top) in lv_w,
.lse1                   \ their signs in lv_sg
 LDA K%+NI%,X
 STA lv_w,X
 DEX
 BPL lse1
 LDX #2
 LDY #8
.lsa
 LDA lv_w,Y
 STA lv_sg,X
 AND #&7F
 STA lv_w,Y
 DEY
 DEY
 DEY
 DEX
 BPL lsa
 LDA #0                 \ all zero (the sun here)? keep LV
 STA lv_cnt             \ (NMOS: here, with A = 0, for STZ at ls_seed)
 LDX #8
.lsz
 ORA lv_w,X
 DEX
 BPL lsz
 TAX
 BEQ ls_rot
.lse2
 LDA lv_w+2             \ shift all three left until one has bit 22 set
 ORA lv_w+5
 ORA lv_w+8
 AND #&40
 BNE lse3
 LDX #6
.lse4
 ASL lv_w,X
 ROL lv_w+1,X
 ROL lv_w+2,X
 DEX
 DEX
 DEX
 BPL lse4
 BMI lse2
.lse3
 INY                    \ (NMOS: Y = &FF, lsa's end, so Y = 0 for STZ; and
 STY lv_s               \ lv_l's 0 below, here)
 STY lv_t               \ S = QS(x) + QS(y) + QS(z) for the top bytes t
 STY lv_l               \ (0..127; one of them 64 or more)
 LDX #6
.lsq
 LDY lv_w+2,X
 LDA QSL,Y              \ bankcheck: ok
 CLC
 ADC lv_t
 STA lv_t
 LDA QSH,Y              \ bankcheck: ok
 ADC lv_s
 STA lv_s
 DEX
 DEX
 DEX
 BPL lsq
 LDA #&80               \ the length, sqrt(x^2 + y^2 + z^2) in units of t
 STA lv_m               \ (64..220, lv_l): the smallest n with QS(n) >= S,
.lsb                    \ by a binary search for the largest with QS(n) < S
 LDA lv_l
 ORA lv_m
 TAX
 LDA QSL,X              \ QS(n) - S (bankcheck: ok)
 CMP lv_t
 LDA QSH,X              \ bankcheck: ok
 SBC lv_s
 BCS P%+5
 STX lv_l
 LSR lv_m
 BNE lsb
 INC lv_l               \ (>= the largest t, so 128 t / length <= 128)
 LDX #2                 \ LV = +/- (128 t / length) * 128
.lse9
 LDY #0                 \ (NMOS: Y = 0 for STZ)
 STY lv_a
 LDY lv_x3,X            \ (3 X: NMOS, a table, making up for the bytes)
 LDA lv_w+2,Y           \ t: the dividend 128 t is (t >> 1, (t AND 1) << 7)
 LSR A
 ROR lv_a
 LDY #8
.lsd
 ASL lv_a
 ROL A
 BCS lsd1
 CMP lv_l
 BCC lsd2
.lsd1
 SBC lv_l
 INC lv_a
.lsd2
 DEY
 BNE lsd
 TYA                    \ (lv_a+1 A) = quotient * 128 (NMOS: Y = 0)
 LSR lv_a
 ROR A
 STA lv_a+1
 LDY lv_a
 LDA lv_sg,X            \ the sign
 BPL lse10
 SEC
 LDA #0
 SBC lv_a+1
 STA lv_a+1
 LDA #0
 SBC lv_a
 TAY
.lse10
 LDA lv_a+1
 STA LVL,X
 TYA
 STA LVH,X
 DEX
 BPL lse9
 LDA #&C0
 STA lv_ok

.lv_ll                  \ LLT = LV * 41 / &4000 = (h >> 1) + (h >> 3) + (h >> 6)
 LDX #2                 \ for h = LV's high byte (arithmetic shifts)
.lvl1
 LDA LVH,X
 CMP #&80
 ROR A                  \ h >> 1
 STA lv_t
 CMP #&80
 ROR A
 CMP #&80
 ROR A                  \ h >> 3
 STA lv_s
 CMP #&80
 ROR A
 CMP #&80
 ROR A
 CMP #&80
 ROR A                  \ h >> 6
 CLC
 ADC lv_s
 CLC
 ADC lv_t
 STA LLT,X
 DEX
 BPL lvl1
 RTS

\ lv_rot: rotate LV by our roll and pitch, as MV40 rotates the planet:
\   K2 = y - alpha x / 256, z = z + beta K2 / 256,
\   y = K2 - beta z / 256, x = x + alpha y / 256

.lv_rot
 LDA ALPHA
 ORA BETA
 AND #&7F
 BEQ lvr9               \ no rotation
 LDX #0                 \ K2 = y + x * (-alpha) / 256
 LDA ALPHA
 EOR #&80
 JSR lv_mul
 CLC
 ADC LVL+1
 STA lv_k2
 TXA
 ADC LVH+1
 STA lv_k2+1
 LDX #&FF               \ z = z + K2 * beta / 256  (X = &FF: v = K2)
 LDA BETA
 JSR lv_mul
 CLC
 ADC LVL+2
 STA LVL+2
 TXA
 ADC LVH+2
 STA LVH+2
 LDX #2                 \ y = K2 + z * (-beta) / 256
 LDA BETA
 EOR #&80
 JSR lv_mul
 CLC
 ADC lv_k2
 STA LVL+1
 TXA
 ADC lv_k2+1
 STA LVH+1
 LDX #1                 \ x = x + y * alpha / 256
 LDA ALPHA
 JSR lv_mul
 CLC
 ADC LVL
 STA LVL
 TXA
 ADC LVH
 STA LVH
.lvr9
 RTS

\ lv_mul: (X A) = v * a / 256 (16-bit signed; v = LV component X, or K2 if
\ X = &FF; A = a, sign-magnitude), truncated towards zero

.lv_mul
 STA lv_s               \ sign of the product in bit 7, then of v
 AND #&7F
 STA lv_m
 CPX #&FF
 BNE lvm1
 LDA lv_k2
 LDY lv_k2+1
 BCS lvm2               \ (NMOS: C = 1, X = &FF)
.lvm1
 LDA LVL,X
 LDY LVH,X
.lvm2
 STA lv_u
 STY lv_u+1
 LDX #0                 \ (NMOS: X = 0 for STZ)
 STX lv_u+2
 TYA
 EOR lv_s
 STA lv_s
 TYA
 BPL lvm3
 SEC                    \ |v|
 LDA #0
 SBC lv_u
 STA lv_u
 LDA #0
 SBC lv_u+1
 STA lv_u+1
.lvm3
 STX lv_a
 STX lv_a+1
 STX lv_a+2
.lvm4
 LSR lv_m               \ (NMOS: its Z for lv_m = 0 when the bit is clear,
 BCC lvm5               \ making up for LDX #0 above)
 CLC
 LDA lv_a
 ADC lv_u
 STA lv_a
 LDA lv_a+1
 ADC lv_u+1
 STA lv_a+1
 LDA lv_a+2
 ADC lv_u+2
 STA lv_a+2
 LDA lv_m
.lvm5
 BEQ lvm6
 ASL lv_u
 ROL lv_u+1
 ROL lv_u+2
 BCC lvm4               \ (NMOS: |v| << 6 at most: C = 0)
.lvm6
 LDA lv_a+1             \ (X A) = acc / 256, signed
 LDX lv_a+2
 BIT lv_s
 BPL lvm7
 EOR #&FF
 ADC #1                 \ (C = 0: the accumulator's last ADC, or BCC lvm5)
 PHA
 TXA
 EOR #&FF
 ADC #0
 TAX
 PLA
.lvm7
 RTS


\ L_SUN's variables (renderer state, not game state; LLT, its result, which
\ L_REC reads, is in the glue area: gfx-gvars.asm)
.LVL     SKIP 3         \ LV: the unit vector towards the sun (16-bit, 1 = &4000)
.LVH     SKIP 3
.lv_ok   EQUB 0         \ bit 7: LV is set up; bit 6: from the sun
.lv_cnt  SKIP 1         \ iterations since LV was last seeded from the sun
.lv_t    SKIP 1
.lv_s    SKIP 1
.lv_w    SKIP 9         \ L_SUN: the sun's |x|, |y|, |z| (24-bit each)
.lv_sg   SKIP 3         \ and their signs (bit 7)
.lv_l    SKIP 1         \ the length, in units of the top byte
.lv_m    SKIP 1         \ lv_mul: multiplier magnitude (and the search's bit)
.lv_u    SKIP 3         \ lv_mul: |v|, shifted
.lv_a    SKIP 3         \ lv_mul: accumulator
.lv_k2   SKIP 2         \ MV40's K2
ENDIF

\ ------------------------------------------------------------------------------
\ L_REC (EE31, before the ship is recorded: GTYPE, GNF, XX2 as LL9's part 5
\ left it; A, X and Y are not kept)
\ ------------------------------------------------------------------------------

.LLT

 EQUB 24, 24, &E8       \ the light towards the sun, x, y, z (* 41.3): L_SUN
                        \ writes it, L_REC reads it; the fixed light until L_SUN
                        \ first runs, and always in the docked code

.GHAND

 EQUB %01000000         \ the ship's handedness (SHAND): %01000000 as ZINF's,
                        \ %01100000 as TIDY's (L_REC puts it in a face's level
                        \ when the face is culled by its winding, f_winding)

.l7_off EQUB 26, 20, 14 \ INWK offset of the z high byte: sidev, roofv, nosev
                        \ (NMOS: z, the loop runs z to x)

.L_REC
 LDA GNF
 BNE P%+3
 RTS
 LDX #2                 \ lr_b = LLT
.lr0
 LDA LLT,X
 STA lr_b,X
 DEX
 BPL lr0
 LDY #2                 \ axis: 2 nosev, 1 roofv, 0 sidev
.lr1
 STY l7_s
 LDX l7_off,Y
 LDY #2
.lr2
 LDA INWK,X             \ high byte (sign-magnitude, 96 = 1) / 2, signed
 BPL lr2a               \ (NMOS: m >> 1 for m >= 0, else (1 - m) >> 1 =
 EOR #&7F               \ -(m >> 1), arithmetic: -1 - m + 2, with SEC for
 SEC                    \ C = 1)
 ADC #1
.lr2a
 CMP #&80
 ROR A
 STA lr_a,Y
 DEX
 DEX
 DEY
 BPL lr2
 INY                    \ (Y = 0: l_dot)
 JSR l_dot              \ Ls = (h . LLT + 16) >> 5
 JSR l_r32
 LDY l7_s
 STA lr_c,Y
 DEY
 BPL lr1
 LDX #2                 \ lr_b = Ls
.lr3
 LDA lr_c,X
 STA lr_b,X
 DEX
 BPL lr3

 LDA GTYPE              \ the type's unit normals (FC_NORMTAB, the set's:
 ASL A                  \ three bytes a face), less one (the loop below reads
 TAX                    \ bytes 1 to 3)
 LDA FC_NORMTAB,X
 SEC
 SBC #1
 STA lrf+1
 LDA FC_NORMTAB+1,X
 SBC #0
 STA lrf+2
 LDX #0
.lf1
 STX lr_f
 LDA XX2,X              \ XX2: 0 hidden
 BEQ lf9
 STA lr_r
 LDY #3                 \ the face's unit normal
.lf2
.lrf
 LDA &FFFF,Y            \ (patched)
 STA lr_a-1,Y
 DEY
 BNE lf2
 JSR l_dot
 LDA #0
 BIT lr_sh
 BMI lf4                \ n . Ls < 0: level 0
 JSR l_r32              \ d
 STA lr_c
 LSR A                  \ d + d / 16 + 2 (<= 136)
 LSR A
 LSR A
 LSR A
 SEC
 ADC lr_c
 ADC #1                 \ (NMOS: C = 0)
 LSR A
 LSR A
 CMP #32
 BCC lf4
 LDA #31
.lf4
 ORA #&80               \ visible
 LDY lr_r
 INY
 BNE P%+5
 ORA GHAND              \ XX2 = 255: cull by winding (bit 6), and bit 5 if
                        \ the ship is mirrored (GHAND, set by S_SHIP)
 LDX lr_f
 STA XX2,X              \ the level, in place of the face's visibility
.lf9
 LDA lrf+1              \ (X = lr_f) the next face's normal: 3 bytes on
 CLC
 ADC #3
 STA lrf+1
 BCC P%+5
 INC lrf+2
 INX
 CPX GNF
 BCC lf1
 RTS

\ l_dot: (lr_sh lr_sl) = lr_a . lr_b (signed bytes, |a +/- b| < 128; NMOS:
\ Y = 0)

.l_dot
 STY lr_sl
 STY lr_sh
 LDX #2
.ld1
 LDA lr_a,X
 CLC
 ADC lr_b,X
 TAY                    \ (NMOS: Y = |a + b| by TAY, or by EOR, TAY, INY)
 BPL ld2
 EOR #&FF
 TAY
 INY
.ld2
 LDA lr_sl
 CLC
 ADC QSL,Y              \ bankcheck: ok
 STA lr_sl
 LDA lr_sh
 ADC QSH,Y              \ bankcheck: ok
 STA lr_sh
 LDA lr_a,X
 SEC
 SBC lr_b,X
 TAY                    \ (NMOS: as above)
 BPL ld3
 EOR #&FF
 TAY
 INY
.ld3
 LDA lr_sl
 SEC
 SBC QSL,Y              \ bankcheck: ok
 STA lr_sl
 LDA lr_sh
 SBC QSH,Y              \ bankcheck: ok
 STA lr_sh
 DEX
 BPL ld1
 RTS

\ l_r32: A = (lr_sh lr_sl + 16) >> 5 (the low byte of it; it fits a signed byte)

.l_r32
 LDA lr_sl
 CLC
 ADC #16
 STA lr_sl
 LDA lr_sh
 ADC #0
 ASL lr_sl
 ROL A
 ASL lr_sl
 ROL A
 ASL lr_sl
 ROL A
 RTS


\ L_REC's variables (renderer state, not game state)
.l7_s    SKIP 1
.lr_a    SKIP 3         \ l_dot's operands
.lr_b    SKIP 3
.lr_c    SKIP 3         \ L_REC: Ls, then d
.lr_sl   SKIP 1         \ l_dot's result
.lr_sh   SKIP 1
.lr_f    SKIP 1         \ L_REC: the face
.lr_r    SKIP 1         \ L_REC: its XX2
