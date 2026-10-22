\ ******************************************************************************
\
\ gfx-rtramp.asm - the trampolines into bank R, the rasteriser (main RAM)
\
\ Port (Model B): to be INCLUDEd in the resident block A (elite-resident.asm),
\ after gfx-rws.asm's constants. The frame layer, in bank F, calls T_INIT,
\ T_POLY and so on: each pages bank R in (BANKR, elite-far.asm), calls the
\ routine through bank R's jump table, RJT, and pages the caller's bank back
\ (whatever was in &F4: so any bank may call them). Port: each T_n is four
\ bytes, a JSR to the shared body, rtgo, and the low byte of RJT's entry. A, X and Y are passed
\ through to the routine; nothing is returned in them (results, if any, are
\ in the mailbox or the zero page). Not re-entrant: interrupt handlers must
\ not call them.
\
\ ******************************************************************************

.rtA    EQUB 0          \ A, X and Y across the paging
.rtX    EQUB 0
.rtY    EQUB 0

.rtgo                   \ the trampolines' body: entered by a JSR from T_n,
                        \ which is followed by RJT's offset for routine n
 STA rtA                \ keep A, X and Y
 STX rtX
 STY rtY
 PLA                    \ take T_n's return address (its JSR's last byte) off
 STA rtl+1              \ the stack, so that this returns to T_n's caller, and
 PLA                    \ read the offset after it
 STA rtl+2
 LDX #1
.rtl
 LDA &FFFF,X            \ (the address is set above)
 STA rtj+1              \ the JSR below calls RJT's entry (whose low byte this
                        \ is: RJT is in one page)
 LDA &F4                \ keep the caller's bank on the stack and page bank R
 PHA                    \ in
 LDA BANKR
 STA &F4
 STA &FE30
 LDA rtA                \ put A, X and Y back for the routine
 LDX rtX
 LDY rtY
.rtj
 JSR RJT                \ (the low byte is set above)
 STA rtA                \ page the caller's bank back in, keeping A
 PLA
 STA &F4
 STA &FE30
 LDA rtA
 RTS

 ASSERT HI(RJT) = HI(RJT + 3 * 13)

MACRO RTRAMP n
 JSR rtgo
 EQUB LO(RJT) + 3 * n   \ (the low byte of RJT's entry n)
ENDMACRO

.T_INIT       RTRAMP 0  \ (RJT's order, gfx-bankr.asm)
.T_SETBUF     RTRAMP 1
.T_RESETBUF   RTRAMP 2
.T_REPAIR     RTRAMP 3
.T_SPAN       RTRAMP 4
.T_MARKDIRTY  RTRAMP 5
.T_DOT        RTRAMP 6
.T_POLY       RTRAMP 7
.T_LINE       RTRAMP 8
.T_STARERASE  RTRAMP 9
.T_STARPLOT   RTRAMP 10
.T_MARKBOX    RTRAMP 11
.T_GETW       RTRAMP 12 \ (the disc layer's, gfx-dlayer.asm)
.T_DRAINQ     RTRAMP 13
.rtramp_end
