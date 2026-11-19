\ ******************************************************************************
\
\ gfx-planet7.asm - the planet's styles
\
\ Port (Model B): the BBC Master port's (its bank 7's meridian window, in the
\ hand-converted NMOS 6502 code of its Model B branch), at the end of the
\ flight code's bank 4 with the circle engine's pc_circ (gfx-merid.asm's
\ bank 4 pass) in a build with _CIRCLES (elite-layout-flight.asm): PF_HOOK
\ from H_CIRC, in game context; its pf_tilt in bank 5 (the room below the
\ rasteriser's per-x tables), and pf_tilt's variables in main RAM, which both
\ assemblies place alike (each block's "Area:" line, streams.py's passes). Its class goes to PF_CLS (GVARS) and its
\ records to the mailbox (PCB, PC_N, pc_inv: gfx-rws.asm), for the frame's
\ f_bounds (PC_ROWS, in bank 6).
\
\ PF_HOOK, in game context (G_PFHOOK, from H_CIRC): the planet's class
\ (PF_CLS) and its style as a few circles on its sphere, each a record made
\ by gfx-merid.asm's pc_circ (which describes the method), and a base colour
\ (pc_inv), made on every iteration of a close planet, and in deep space on
\ the iterations with MCNT even (the game turns the planet by a half step on
\ every iteration: MVS5); on the others in deep space the last ones are
\ kept, if the radius, TYPE and VIEW are the same and they are the last
\ iteration's, and the frame moves them with the disc (the frame layer
\ decides: gfx-frame.asm's F_PFHOLD and f_hrec):
\
\   * class 0, a meridian planet (TYPE 128): the beach ball, the great
\     circles normal to roofv and sidev, base 1 (colour B where the surface
\     is on the same side of both planes, as Elite's equator and meridian
\     divide it);
\
\   * class 1, a crater planet (TYPE 130): one to three craters, small caps
\     from the system's seed (pf_craters), base 0.
\
\ Elite's state is not touched: of Elite's zero page &10-&26 (the engine's
\ workspace), XX0 and INF are saved and restored (the rest are temporaries
\ that the game sets before it reads them after PL9: XX16's last eleven
\ bytes, P, V, XX and YY, which the original's PL9 parts 2 and 3 and CIRCLE2
\ overwrite, and which the port's H_CIRC, returning from PL9 without them,
\ leaves as they come), and A, X, Y and the flags are preserved. The frame layer makes
\ the rows with gfx-merid.asm's PC_ROWS (f_bounds, in bank 6).
\ 6-harness/planet_caps.py models it all bit for bit.
\
\ ******************************************************************************

\       Area: bank 4

pf_tilt = T_TILT        \ (bank 5's, through the glue's trampoline)

.PF_HOOK
 ASSERT INF = XX0 + 2 AND XX0 >= &10 AND INF + 1 <= &26
 PHP
 PHA
 LDA TYPE               \ the class: a crater planet (TYPE 130) 1, a meridian
 LSR A                  \ planet (128) 0
 AND #1
 STA PF_CLS
 LDA K+1                \ the detail only below a radius of 256, as PL9 has
 BNE pfh9               \ it, and from 6 up, as its meridians
 LDA K
 CMP #6
 BCC pfh9
 STA pcr                \ (NMOS: X and Y saved only here,
 TXA                    \ as they are kept before)
 PHA
 TYA
 PHA
 LDX #3                 \ (XX0 and INF, in the engine's workspace, Elite's
.pfh0                   \ &10-&26)
 LDA XX0,X
 STA pm_zsave,X
 DEX
 BPL pfh0
 LDA K3                 \ the centre
 STA pcbx
 LDA K3+1
 STA pcbx+1
 LDA K4
 STA pcby
 LDA K4+1
 STA pcby+1
 LDX #0
 STX pc_inv             \ (NMOS: X = 0; PC_N zeroed here, not on entry: the
 STX PC_N               \ frame reads it only with PF_CLS bit 7 set)
 LDA pcr                \ the last records kept (the frame moves them with
 LDX #FG_PFHOLD         \ the disc), or made (gfx-frame.asm's F_PFHOLD)
 JSR GCALL
 BCS pfh7
 LDA PF_CLS
 BNE pfh2
 INC pc_inv             \ (the beach ball: base 1)
 JSR pf_beach
 JMP pfh3
.pfh2
 JSR pf_craters
.pfh3
 LDA PC_N               \ (records, or a base colour)
 ORA pc_inv
 BEQ pfh7
 LDA PF_CLS
 ORA #&80
 STA PF_CLS
.pfh7
 LDX #3
.pfh1
 LDA pm_zsave,X
 STA XX0,X
 DEX
 BPL pfh1
 PLA
 TAY
 PLA
 TAX
.pfh9
 PLA
 PLP
 RTS

\ pf_beach: a meridian planet's two great circles, normal to roofv and sidev
\ pf_one: a circle of cosine A (positive) about vector X (INWK offset) alone

.pf_beach
 LDX #15
 JSR pf_gc
 LDX #21
.pf_gc
 LDA #0
.pf_one
 PHA
 LDY #0
 STY pcneg
 TYA
 JSR pf_tilt
 PLA
 STA pcc
 JMP pc_circ

\ pf_craters: a crater planet's caps, from the system's seed (QQ2): the
\ first on roofv, 30 degrees across (Elite's crater: at 222/256 of the radius
\ from the centre, half the radius across); then, as the seed has it, one on
\ nosev (either way) tilted towards sidev, and one on sidev tilted towards
\ roofv, each 15 to 30 degrees. No two axes are closer than 63 degrees, so
\ the craters never overlap.

.pf_craters
 LDX #15                \ roofv
 LDA #222
 JSR pf_one
 LDA QQ2+4              \ s2_lo bits 0-1: more caps (0, 1, 2, 1)
 AND #3
 BEQ pfc9
 PHA
 LDA QQ2+4              \ bits 2-4: the second's signs and tilt
 LSR A
 LSR A
 AND #7
 LDX #9                 \ nosev, tilted towards sidev
 LDY #21
 JSR pf_tilt
 LDA QQ2+5              \ s2_hi bits 0-1: its size
 JSR pf_size
 PLA
 CMP #2
 BNE pfc9
 LDA QQ2+4              \ bits 5-7: the third's
 LSR A
 LSR A
 LSR A
 LSR A
 LSR A
 LDX #21                \ sidev, tilted towards roofv
 LDY #15
 JSR pf_tilt
 LDA QQ2+5              \ s2_hi bits 2-3
 LSR A
 LSR A
.pf_size                \ a crater of A bits 0-1's size (15, 20, 25 or 30
 AND #3                 \ degrees) on pcv
 TAX
 LDA pfs_c,X
 STA pcc                \ (pcneg: 0, from pf_one; NMOS: not set again)
 JMP pc_circ
.pfc9
 RTS
.pfs_c EQUB 247, 241, 232, 222




\       Area: bank 5 gap

INWK = PF_INWK          \ (bank 5's part, gfx-bank5.asm: pf_tilt, which reads
                        \ only the game's INWK and writes the main RAM's pcv
                        \ and pcn, so that the home bank has the room)

\ pf_tilt: pcv = (+/- vector X) / 2 + (+/- vector Y) / 2^(k+1), as
\ sign-magnitude words (X, Y = 9 nosev, 15 roofv, 21 sidev; Y = 0: none), A
\ bits 0-2: bit 0 the first's sign, bit 1 the second's, bit 2 k = 2, else
\ k = 1 (a tilt of 14 or 27 degrees); each magnitude shifted before its sign
\ is applied (so a vector alone is exactly halved). Halved, as the sums must fit 15 bits (a circle depends on its
\ axis' direction only); pcn = 2^24 / the sum's nominal length (>> 3)

.pf_tilt
 STA pft_f
 STX pft_x
 STY pft_y
 LDX #0                 \ pcn: 1536 (a vector halved), 1536 sqrt(1 + 1/4) or
 CPY #0                 \ sqrt(1 + 1/16) (k = 1, 2)
 BEQ pft0
 INX
 AND #4
 BEQ pft0
 INX
.pft0
 LDA pfn_lo,X
 STA pcn
 LDA pfn_hi,X
 STA pcn+1
 LDA pfn_k,X            \ (the second's shift)
 STA pft_k2
 LDY #4                 \ each component, Y = 4, 2, 0
.pft1
 LDX pft_y              \ a vector alone (a crater on roofv, the beach ball's
 BNE pft2               \ circles): its magnitude halved, its sign kept
 TYA
 CLC
 ADC pft_x
 TAX
 LDA INWK+1,X
 CMP #&80               \ C = its sign
 ROR A                  \ sign kept, magnitude halved (bit 6, the sign again,
 AND #&BF               \ cleared; C = the magnitude's bit 0)
 STA pcv+1,Y
 LDA INWK,X
 ROR A
 STA pcv,Y
 JMP pft6
.pft2
 LDA #0                 \ (NMOS: pft_r = 0 here only: the vector alone does
 STA pft_r              \ not use it)
 STA pft_r+1
 LDX pft_x              \ the first, halved and signed
 LDA pft_f
 STA pft_n
 LDA #1
 JSR pft_add
 LDX pft_y              \ the second, shifted k + 1 times and signed
 LDA pft_f
 LSR A
 STA pft_n
 LDA pft_k2
 JSR pft_add
.pft4
 LDA pft_r+1            \ to sign-magnitude
 BPL pft4a
 LDA #0
 SEC
 SBC pft_r
 STA pft_r
 LDA #0
 SBC pft_r+1
 ORA #&80
.pft4a
 STA pcv+1,Y            \ A = the high byte on both ways in
 LDA pft_r
 STA pcv,Y
.pft6
 DEY
 DEY
 BPL pft1
 RTS

.pfn_lo EQUB LO(10923), LO(9770), LO(10596)
.pfn_hi EQUB HI(10923), HI(9770), HI(10596)
.pfn_k  EQUB 0, 2, 3

\ pft_add: pft_r += the INWK word at X + Y, its magnitude shifted right A
\ times, negated if its sign EOR pft_n bit 0 is set (Y kept)

.pft_add
 STA pft_k
 STX pft_s
 TYA
 CLC
 ADC pft_s
 TAX
 LDA pft_n
 LSR A
 LDA INWK+1,X
 BCC P%+4
 EOR #&80
 STA pft_n
 AND #&7F
 STA pft_s+1
 LDA INWK,X
 STA pft_s
 LDX pft_k
.pfa1
 LSR pft_s+1
 ROR pft_s
 DEX
 BNE pfa1
 BIT pft_n
 BMI pfa2
 CLC
 LDA pft_r
 ADC pft_s
 STA pft_r
 LDA pft_r+1
 ADC pft_s+1
 STA pft_r+1
 RTS
.pfa2
 SEC
 LDA pft_r
 SBC pft_s
 STA pft_r
 LDA pft_r+1
 SBC pft_s+1
 STA pft_r+1
 RTS



\       Area: main high

                        \ pf_tilt's, in main RAM at PFVH%, which bank 5's layout
                        \ and the flight code's place alike (gfx-merid.asm's
                        \ follow in the flight code)
.pcv    SKIP 6          \ the axis (three sign-magnitude words: pf_tilt)
.pcn    SKIP 2          \ 2^24 / the axis' nominal length (>> 3)
.pft_f  SKIP 1          \ pf_tilt's own
.pft_x  SKIP 1
.pft_y  SKIP 1
.pft_k  SKIP 1
.pft_k2 SKIP 1
.pft_n  SKIP 1
.pft_r  SKIP 2
.pft_s  SKIP 2
