\ ******************************************************************************
\
\ ELITE RUPTURE BLOCK (Port)
\
\ The Model B port's code at RUPT% (elite-map.asm), in the main RAM that the
\ original's mode 5 dashboard leaves after PANEL%: the loader's LOAD routine
\ copies it there from RUPTcode (elite-loader3.asm). It is the rupture's
\ interrupt work, which changes the 6845's character clock twice a field, in
\ mid-line, without a single horizontal sync interval other than 64
\ microseconds: docs/video-timing.md has the timing, the arithmetic and the
\ proof, and every cycle count below refers to it.
\
\ ******************************************************************************

UVIA = VIA + &60        \ The user VIA, whose timer 2 runs free as the rupture's
UT2L = UVIA + &08       \ clock (1 microsecond a count, phase-locked to the
UT2H = UVIA + &09       \ lines; its interrupt disabled)

\ ******************************************************************************
\
\       Name: RUPT
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: The rupture's interrupt: switch the 6845's character clock on a
\             line's cycle 75 or 76, then set up the next CRTC frame
\
\ ------------------------------------------------------------------------------
\
\ Port: IRQG (the resident block A) comes here on the system VIA's timer 1,
\ which fires about a line before each switch, with interrupts disabled (and
\ A in &FC, as the MOS's handler leaves it). Point 1 (rphase = 0) is switch
\ S1 on line 191, from the screen's 2 MHz clock to the dashboard's 1 MHz;
\ point 2 (rphase = 1) is switch S2 on line 311, back again. Each switch is
\ made on the cycle that its target in timer 2 gives (rwait), or a whole
\ line later if the interrupt came too late for it, and the registers that
\ belong to the switch are written relative to the line it is made on. Then
\ the next CRTC frame's vertical registers and start address, timer 1's next
\ period, and the interrupt is passed on to the MOS (its 100 Hz work), after
\ the switch.
\
\ While the disc is in use (rdisc, set by dfsin), S1 is not made: frame B
\ stays at 2 MHz, with no rows shown, so that a disc NMI cannot fall inside a
\ switch.
\
\ ******************************************************************************

.RUPT

 TXA                    \ Store X and Y on the stack
 PHA
 TYA
 PHA

 LDA rphase             \ Point 2 is S2
 BEQ P%+5
 JMP rpt2

                        \ Point 1: S1, the switch to the dashboard (frame B)

 LDA rdisc              \ If the disc is in use, leave the field at 2 MHz
 BEQ P%+5
 JMP rpt1d

 LDY #0                 \ rpo = the dashboard's palette: 0 for the original's
 LDA ESCPA              \ standard colours, 12 for its escape pod colours
 BEQ P%+4
 LDY #12
 STY rpo

 LDX #0                 \ Wait for S1's cycle (rwait), from target 0
 JSR rwait

                        \ Line 191 (or the line the switch slipped to), at 2
                        \ MHz: the switch line's R3, R2' and R0'

 LDX #3                 \ R3 = &24: line 191's sync counts at 1 MHz
 STX CRTC
 LDX #&24
 STX CRTC+1

 LDX #2                 \ R2' = 83: its sync on cycle 90
 STX CRTC
 LDX #83
 STX CRTC+1

 LDX #0                 \ R0' = 101: its last tick on cycle 126
 STX CRTC
 LDX #101
 STX CRTC+1

 LDA #ULAB              \ The switch, on cycle 75 or 76: mode 5's 1 MHz clock
 RTRIMI RH1             \ and four colours (with its odd half microsecond)
 STA VIA+&20

 LDY rpo                \ Colour 2's four palette entries, in the line's
 LDA rpal,Y             \ border: the dashboard's first row is all colour 2
 STA VIA+&21
 LDA rpal+1,Y
 STA VIA+&21
 LDA rpal+2,Y
 STA VIA+&21
 LDA rpal+3,Y
 STA VIA+&21

 LDX #1                 \ R1 = 32 (line 192, frame B's first, shows 32 bytes)
 STX CRTC
 LDX #32
 STX CRTC+1

 LDX #2                 \ R2 = 45, after line 191's sync
 STX CRTC
 LDX #45
 STX CRTC+1

 RWAITX 10              \ (until line 191 has ended)

 LDX #0                 \ R0 = 63, now that line 191 has ended (C0 is below 63
 STX CRTC               \ again)
 LDX #63
 STX CRTC+1

 LDA rpal+4,Y           \ Colours 1 and 3's eight palette entries, which line
 STA VIA+&21            \ 192 does not show
 LDA rpal+5,Y
 STA VIA+&21
 LDA rpal+6,Y
 STA VIA+&21
 LDA rpal+7,Y
 STA VIA+&21
 LDA rpal+8,Y
 STA VIA+&21
 LDA rpal+9,Y
 STA VIA+&21
 LDA rpal+10,Y
 STA VIA+&21
 LDA rpal+11,Y
 STA VIA+&21

 INC rstate             \ Frame B is at 1 MHz

 JMP rpt1

.rpt1d

 LDX #0                 \ The disc is in use: no switch, but wait until frame
 JSR rwait              \ B has started (its vertical registers may only be
 LDA #80                \ written then), from S1's line
 JSR rdelay
 LDX #0                 \ (R6 = 0 below, as rstate = 0)

.rpt1

                        \ Frame B has started: its R4, R7 and R6, and the
                        \ screen buffer to show in the next frame A

 LDX #4                 \ R4 = 14
 STX CRTC
 LDX #14
 STX CRTC+1

 LDX #7                 \ R7 = 10
 STX CRTC
 LDX #10
 STX CRTC+1

 LDX #6                 \ R6 = PANR (7, or 0 to hide the dashboard), or 0 while
 STX CRTC               \ the disc is in use
 LDX PANR
 LDA rstate
 BNE P%+4
 LDX #0
 STX CRTC+1

 LDX #0                 \ If the frame layer has asked for a flip (GFLIP), show
 LDA GFLIP              \ buffer GPEND from the next frame A on, and note that
 BEQ rpt3               \ it is done: the buffer that was on show is no longer
 LDA rflip              \ read from here on, as frame B shows the dashboard
 BNE rpt3               \ (docs/renderer.md, "The buffers and the flip"); but
 LDA GPEND              \ not in the field after a flip (rflip), so that a
 STA GFRONT             \ frame is on show for two fields at least: 25 frames a
 STX GFLIP              \ second at most, as the BBC Master port's
 INX

.rpt3

 STX rflip              \ (rflip: 1 if this field flipped)

 LDA #12                \ R12 = the buffer on show, GFRONT (0 for BUF0, 1 for
 STA CRTC               \ SCREEN%), latched when frame B ends (R13 is 0)
 LDX GFRONT
 LDA rsah,X
 STA CRTC+1

 LDX #(RPA AND &FF)     \ Timer 1's latch for its next reload, at point 2: RPA
 LDY #(RPA DIV 256)     \ microseconds on, to point 1
 JMP rpt9

.rpt2

                        \ Point 2: S2, the switch back to the screen (frame A)

 LDA rstate             \ If frame B is at 2 MHz (the disc is in use), there is
 BNE P%+5               \ nothing to switch
 JMP rpt4d

 LDX #2                 \ Wait for S2's cycle (rwait), from target 2
 JSR rwait

                        \ Line 311 (or the line the switch slipped to), at 1
                        \ MHz: the switch line's R3, R2'' and R0''

 LDX #3                 \ R3 = &28: line 311's sync counts at 2 MHz
 STX CRTC
 LDX #&28
 STX CRTC+1

 LDX #2                 \ R2'' = 52: its sync on cycle 90
 STX CRTC
 LDX #52
 STX CRTC+1

 LDX #0                 \ R0'' = 89: its last tick on cycle 127
 STX CRTC
 LDX #89
 STX CRTC+1

 LDA #ULAA              \ The switch, on cycle 75 or 76: MODE 1's 2 MHz clock
 RTRIMI RH2             \ and four colours (with its odd half microsecond)
 STA VIA+&20

 LDX #1                 \ R1 = 64 (line 311 is in the vertical blank; line 0,
 STX CRTC               \ frame A's first, shows 64 bytes)
 LDX #64
 STX CRTC+1

 LDX #2                 \ R2 = 90: line 311's sync has started (cycle 90), and
 STX CRTC               \ its C0 stops at 89; line 0's reaches the old 52 on
 LDX #90                \ its cycle 52
 STX CRTC+1

 RWAITX 20              \ (until line 311 has ended, on cycle 128)

 LDX #0                 \ R0 = 127, now that line 311 has ended, and before
 STX CRTC               \ line 0's C0 reaches the old 89 (its cycle 89)
 LDX #127
 STX CRTC+1

 DEC rstate             \ Frame B is at 2 MHz again

 JMP rpt4

.rpt4d

 LDX #2                 \ Frame B is at 2 MHz: no switch, but wait until frame
 JSR rwait              \ A has started (its vertical registers may only be
 LDA #80                \ written then), from S2's line
 JSR rdelay

.rpt4

                        \ Frame A has started: its R4, R7 and R6, and the
                        \ dashboard's address for frame B

 LDX #4                 \ R4 = 23
 STX CRTC
 LDX #23
 STX CRTC+1

 LDX #7                 \ R7 = 127 (no vertical sync)
 STX CRTC
 LDX #127
 STX CRTC+1

 LDX #6                 \ R6 = 24
 STX CRTC
 LDX #24
 STX CRTC+1

 LDA #12                \ R12 = the dashboard, latched when frame A ends (R13
 STA CRTC               \ is 0 for every start address: the screens and the
 LDA #HI(PANEL% DIV 8)  \ dashboard each start on a multiple of &800, so it is
 STA CRTC+1             \ written once, by the loader)

 LDX #(RPB AND &FF)     \ Timer 1's latch for its next reload, at point 1: RPB
 LDY #(RPB DIV 256)     \ microseconds on, to point 2

.rpt9

 STX rlat               \ Timer 1's next period, written to its latch after the
 STY rlat+1             \ MOS has handled this interrupt (rret), as writing the
                        \ latch clears the interrupt's flag, which the MOS reads

 LDA rphase             \ Flip the phase
 EOR #1
 STA rphase

 PLA                    \ Restore Y and X from the stack
 TAY
 PLA
 TAX

 LDA #HI(rret)          \ Pass the interrupt on to the MOS (its 100 Hz work),
 PHA                    \ with A restored, through a return frame that brings
 LDA #LO(rret)          \ its RTI back to rret, with interrupts disabled
 PHA
 LDA #%00000100
 PHA
 LDA &FC
 JMP (IRQMOS)

.rret

 PHA                    \ Write timer 1's latch for the next point, and return
 LDA rlat               \ from the interrupt
 STA VIA+&46
 LDA rlat+1
 STA VIA+&47
 PLA
 RTI

\ ******************************************************************************
\
\       Name: rwait
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: Wait until a switch's target in timer 2, or a whole number of
\             lines after it
\
\ ------------------------------------------------------------------------------
\
\ Port: the target, rtgt+X, is the value that timer 2's low byte reads here
\ when the switch that follows the return will land on cycle 75 or 76 of its
\ line with no wait (docs/video-timing.md). The difference from the value
\ read is the wait in microseconds: as the targets are a whole number of
\ lines apart (64 microseconds) and the low byte wraps every 256 (four
\ lines), the difference modulo 256 keeps the line's phase. A difference of at most
\ RWMAX is the wait to the target; more means the interrupt came after the
\ target (another interrupt, or a SEI section, held it off), so the wait is
\ the difference modulo 64: the switch is made on the first line after that
\ has its target's phase, a whole number of lines late (rslip counts these).
\ The time from the read of timer 2 to the return is the constant RWFIX
\ cycles plus two a microsecond of wait.
\
\ ******************************************************************************

.rwait

 LDA UT2L               \ Timer 2's low byte, less the target (the read is a
 SEC                    \ 1 MHz access, so the cycles from here are fixed)
 SBC rtgt,X

 CMP #RWMAX+1           \ If it is more than RWMAX, the switch is late: wait
 BCC rwt1               \ the difference modulo 64 instead, and count it in
 AND #63                \ rslip (modulo 256)
 INC rslip
 JMP rwt2

.rwt1

 NOP                    \ (the late path's length, 10 cycles more than the
 NOP                    \ taken BCC, in the on-time path)
 NOP
 NOP
 NOP

.rwt2

                        \ Fall through into rdelay to wait A microseconds

\ ******************************************************************************
\
\       Name: rdelay
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: Wait exactly A microseconds (plus a fixed number of cycles)
\
\ ------------------------------------------------------------------------------
\
\ Port: blocks of 8 microseconds (16 cycles each) in a loop, then the rest,
\ 0 to 7, as a jump into a run of NOPs (2 cycles each). The time from the
\ call to the return is 2A + RDFIX cycles for any A from 0 to 255.
\
\ ******************************************************************************

.rdelay

 TAY                    \ Set the jump into the NOPs to run A AND 7 of them
 AND #7
 EOR #7
 CLC
 ADC #LO(rdn)
 STA rdj+1
 LDA #HI(rdn)
 ADC #0
 STA rdj+2

 TYA                    \ X = A DIV 8, the blocks of 8 microseconds
 LSR A
 LSR A
 LSR A
 TAX

 NOP                    \ (4 cycles, so that the constant part of the wait is
 NOP                    \ what the switches' targets were set for)

 BEQ rdj                \ If there are none, go to the NOPs (3 cycles)

.rdl

 NOP                    \ A block: 16 cycles a pass, the last one 15
 NOP
 NOP
 NOP
 BIT &70
 DEX
 BNE rdl

 NOP                    \ (2: the not-taken BEQ, 2, and the last pass's 15
                        \ make the blocks 16 cycles each and the path 3 cycles
                        \ longer, as the taken BEQ's)

.rdj

 JMP rdn                \ Jump into the run of NOPs (the address is set above)

.rdn

 FOR I%, 1, 7
  NOP
 NEXT

 RTS

\ ******************************************************************************
\
\       Name: rdin
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: Stop the rupture's switches for a disc command (dfsin), and
\             start them again after it (rdout, dfsout)
\
\ ------------------------------------------------------------------------------
\
\ Port: DFS transfers sectors on NMIs, which a switch cannot hold off, so
\ while the disc is in use the field stays at 2 MHz (frame B with no rows
\ shown). rdin sets rdisc, so that S1 is not made from then on, and waits
\ until frame B is back at 2 MHz (rstate = 0), if it is not already: at most
\ frame B's 120 lines. rdout clears rdisc. Both keep A, X and Y.
\
\ ******************************************************************************

.rdin

 PHA                    \ Store A on the stack

 LDA #&FF               \ Stop S1
 STA rdisc

.rdi1

 LDA rstate             \ Wait until frame B is at 2 MHz
 BNE rdi1

 PLA                    \ Restore A and return
 RTS

.rdout

 PHA                    \ Start S1 again
 LDA #0
 STA rdisc
 PLA
 RTS

\ ******************************************************************************
\
\       Name: rtgt
\       Type: Variable
\   Category: Drawing the screen
\    Summary: The rupture's state, and the switches' targets in timer 2
\
\ ******************************************************************************

.rtgt

 EQUB 0, 0              \ S1's target (timer 2's low byte), set by the loader
 EQUB 0, 0              \ S2's target (the high bytes are not used)
 EQUB 0, 0              \ The loader's calibration probe (rcal)

.rphase

 EQUB 0                 \ The next point: 0 for S1, 1 for S2

.rstate

 EQUB 0                 \ Frame B's clock: 0 for 2 MHz, 1 for 1 MHz

.rdisc

 EQUB 0                 \ Non-zero while the disc is in use (rdin, rdout)

.rflip

 EQUB 0                 \ 1 if the last field's point 1 flipped the buffers

.rslip

 EQUB 0                 \ The switches made a line or more late (modulo 256)

.rlat

 EQUW 0                 \ Timer 1's next period, for rret

.rtmp

 EQUB 0                 \ rwait's workspace

.rpo

 EQUB 0                 \ The dashboard's palette: 0 or 12 (rpal)

.rsah

 EQUB HI(BUF0 DIV 8), HI(SCREEN% DIV 8)

.rpal

                        \ The dashboard's palette (as the original's TVT1):
                        \ colour 2's four entries, then colour 1's and colour
                        \ 3's eight, each the index in bits 4-7 and the
                        \ physical colour EOR 7 in bits 0-3

 EQUB &D4, &C4, &94, &84    \ Standard: colour 2 yellow,
 EQUB &76, &66, &36, &26    \ colour 1 red,
 EQUB &F5, &E5, &B5, &A5    \ colour 3 green

 EQUB &D0, &C0, &90, &80    \ Escape pod: colour 2 white,
 EQUB &76, &66, &36, &26    \ colour 1 red,
 EQUB &F1, &E1, &B1, &A1    \ colour 3 cyan

 ASSERT HI(rpal) = HI(rpal + 23)   \ (no page crossing: the cycles are fixed)
