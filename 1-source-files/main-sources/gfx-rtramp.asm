\ ******************************************************************************
\
\ gfx-rtramp.asm - the trampolines into bank R, the rasteriser (main RAM)
\
\ Port (Model B): to be INCLUDEd in the resident block A (elite-resident.asm),
\ after gfx-rws.asm's constants. The frame layer, in bank F, calls T_INIT,
\ T_POLY and so on: each pages bank R in (BANKR, elite-far.asm), calls the
\ routine through bank R's jump table, RJT, and pages the caller's bank back
\ (whatever was in &F4: so any bank may call them). A, X and Y are passed
\ through to the routine; nothing is returned in them (results, if any, are
\ in the mailbox or the zero page). Not re-entrant: interrupt handlers must
\ not call them.
\
\ ******************************************************************************

.rtA    EQUB 0          \ A across the paging
.rtB    EQUB 0          \ the caller's bank

.rtin                   \ page bank R in, keeping A, X, Y
 STA rtA
 LDA &F4
 STA rtB
 LDA BANKR
 STA &F4
 STA &FE30
 LDA rtA
 RTS

.rtout                  \ page the caller's bank back in, keeping A, X, Y
 STA rtA
 LDA rtB
 STA &F4
 STA &FE30
 LDA rtA
 RTS

MACRO RTRAMP n
 JSR rtin
 JSR RJT + 3 * n
 JMP rtout
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
.rtramp_end
