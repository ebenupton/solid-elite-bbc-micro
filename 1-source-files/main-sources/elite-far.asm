\ ******************************************************************************
\
\ elite-far.asm - far calls between a program's home bank and its cold bank
\
\ Port (docs/memory-map.md): INCLUDEd in the loader's resident block A, in main
\ RAM at &0400, so that it is visible whatever is paged at &8000-&BFFF.
\
\ Each of the game's two programs (the flight code and the docked code) runs
\ with its home bank (ROMSEL = BANK4) paged in at &8000-&BFFF. Its cold code
\ lives in its cold bank (ROMSEL = BANK7), which is paged in only for a far
\ call. The bank numbers are the loader's (BANKS, below), as sideways RAM
\ boards differ. The source calls everything by the original's names, and
\ each side's emission of it (2-build-files/streams.py) holds, at the place
\ of each routine that lives on the other side and that this side calls,
\ jumps to or falls into, a 5-byte stub. In the home bank, under the cold
\ routine's own name (its body is name_C in the cold bank):
\
\   .TT22 JSR farC : EQUW TT22_C        call (A, X, Y, flags pass both ways)
\   .TT170 JSR farCj : EQUW TT170_C     jump (the target never returns)
\
\ and in the cold bank, under the name the cold code's calls and jumps are
\ renamed to:
\
\   .xh_TT26 JSR farH : EQUW TT26       call, then page the cold bank back in
\   .jh_BAY JSR farHj : EQUW BAY        jump (the target never returns here)
\
\ A routine that fell through into a routine now on the other side falls
\ into its stub: the stub calls the body, which returns to the falling
\ routine's caller with the caller's bank back, as the fall-through did.
\ The helpers read the EQUW while the caller's bank is still paged in, so a
\ stub works the same in either bank.
\
\ farC / farH page the target's bank in and call it, then page the caller's
\ bank (&F4 at the call) back in. farCj / farHj jump to the target (the
\ stub's return address is dropped). A, X, Y and all the flags reach the
\ target as they were at the stub, and come back from it unchanged. &F4
\ always matches ROMSEL (the MOS restores ROMSEL from &F4 after paged ROM
\ calls), and it is written first, so an interrupt between the two writes
\ leaves the right bank paged.
\
\ While a called target runs, the stack holds, from the top: the return
\ address into this code (farret - 1), the caller's ROMSEL, and the caller's
\ return address (three bytes more than a plain JSR), so no target may pull
\ its caller's return address or look at the stack above it. The harness
\ (6-harness/blib.mjs) sees through these frames by the label farret.
\
\ This is the BBC Master port's elite-far.asm, with the banks read from
\ BANKS rather than fixed.
\
\ ******************************************************************************

.BANKS                  \ The sideways RAM banks, as the loader found them:

.BANK7  EQUB 0          \ bank 7: the programs' cold passes, and the renderer's
                        \ window at its top
.BANK6  EQUB 0          \ bank 6: the frame layer (the filled renderer)
.BANK5  EQUB 0          \ bank 5: the rasteriser (the filled renderer)
.BANK4  EQUB 0          \ bank 4: the programs' hot passes (their home bank)

.fA     EQUB 0          \ A, X, the bank to page in (and flags on the way back)
.fX     EQUB 0
.fB     EQUB 0
.ft     EQUW 0          \ the target

.farC
 PHP
 STA fA
 LDA BANK7
 BNE farc               \ Jump to farc (BANK7 is never 0: it is the highest of
                        \ the four slots found, so at least 3)

.farH
 PHP
 STA fA
 LDA BANK4

.farc
 STA fB
 STX fX
 TSX                    \ &101,X = flags, &102,X / &103,X = the stub's return
 LDA &102,X             \ address (the JSR's last byte)
 STA fpc+1
 LDA &103,X
 STA fpc+2
 LDA &101,X             \ the flags and the caller's bank replace it:
 STA &102,X             \ the stack is (caller's return), bank, flags
 LDA &F4
 STA &103,X
 PLA
 LDX #2                 \ Copy the EQUW's two bytes, high byte first
.fpc
 LDA &FFFF,X            \ (patched) the EQUW after the JSR, read while the
 STA ft-1,X             \ caller's bank is still paged in
 DEX
 BNE fpc
 LDA fB
 STA &F4
 STA VIA+&30
 LDA fA
 LDX fX
 PLP
 JSR fjmp
.farret
 STA fA
 PHP
 PLA
 STA fB
 PLA                    \ the caller's bank
 STA &F4
 STA VIA+&30
 LDA fB
 PHA
 LDA fA
 PLP
 RTS

.fjmp
 JMP (ft)

.farCj
 PHP
 STA fA
 LDA BANK7
 BNE farj               \ Jump to farj (BANK7 is never 0, as in farC)

.farHj
 PHP
 STA fA
 LDA BANK4

.farj
 STA fB
 STX fX
 TSX
 LDA &102,X
 STA fpj+1
 LDA &103,X
 STA fpj+2
 LDA &101,X             \ drop the stub's return address
 STA &103,X
 PLA
 PLA
 LDX #2                 \ Copy the EQUW's two bytes, high byte first
.fpj
 LDA &FFFF,X
 STA ft-1,X
 DEX
 BNE fpj
 LDA fB
 STA &F4
 STA VIA+&30
 LDA fA
 LDX fX
 PLP
 JMP (ft)
