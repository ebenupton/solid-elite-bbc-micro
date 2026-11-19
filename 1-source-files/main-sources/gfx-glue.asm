\ ******************************************************************************
\
\ gfx-glue.asm - the main RAM glue of the filled renderer (docs/renderer.md)
\
\ Port (Model B): assembled at GLUE% (elite-map.asm), at the end of the
\ resident block A, which INCLUDEs it, so that it is visible whatever bank is
\ paged: the trampolines into bank 5, the rasteriser (which the frame layer
\ calls), and GCALL, through which the game calls the frame
\ layer in bank 6. Bank 6 is built against these addresses (gfx-bank6.asm,
\ which writes GLUE.bin for 6-harness/test_frame.py).
\
\ GCALL: X = an entry's number (FG_*, elite-map.asm), A and Y its inputs (and
\ C, which reaches the entry): pages bank 6 in (BANK6), enters it through
\ its dispatcher at FJT (the top of bank 6), and pages the caller's bank
\ (whatever was in &F4) back in, returning A and Y as the entry left them
\ (every entry keeps Y, but F_GUN, which returns one). The flags and X are
\ not kept. It may be called again while an entry runs (the frame's runs of
\ game code reach F_PDOT through it), but not from an interrupt.
\
\       Area: main
\
\ ******************************************************************************

FJT = &BFC0             \ bank 6's dispatcher (gfx-bank6.asm)

 INCLUDE "3-assembled-output/bank5-entry.asm"   \ RJT, bank 5's jump table (bank5.py
                                                \ writes it from bank 5's symbols)

\ (the entries' numbers, FG_*, are in elite-map.asm, for the game's hooks)

\ ******************************************************************************
\
\ The trampolines into bank 5, the rasteriser: the frame layer, in bank 6,
\ calls T_INIT, T_POLY and so on: each pages bank 5 in (BANK5, elite-far.asm),
\ calls the routine through bank 5's jump table, RJT, and pages the caller's
\ bank back (whatever was in &F4: so any bank may call them). Each T_n pushes
\ A and puts the low byte of RJT's entry n in A, then branches to the shared
\ body, rtgo (the last falls into it), which patches it into its JSR: five
\ bytes a trampoline, and about 73 cycles a call besides the routine's own.
\ A, X and Y are passed through to the routine, and A, X, Y, C and V come
\ back as it left them (N and Z as A). Not re-entrant (the caller's bank is
\ kept in rtB): no routine they call calls them, and interrupt handlers must
\ not call them.
\
\ ******************************************************************************

.rtB    EQUB 0          \ the caller's bank across the call

MACRO RTRAMP n
 PHA                    \ keep A
 LDA #LO(RJT) + 3 * n   \ the low byte of RJT's entry n (never 0: RJT is at
 BNE rtgo               \ the top of bank 5), and to the body
ENDMACRO

.T_INIT       RTRAMP 0  \ (RJT's order, gfx-bank5.asm)
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
.T_GETW       RTRAMP 12 \ (the disc layer's and the text's, gfx-raster_dq.asm)
.T_TILT                 \ (the planet's surface's pf_tilt, gfx-planet7.asm: from
 PHA                    \ the game's PF_HOOK, in the home bank; RTRAMP 13,
 LDA #LO(RJT) + 3 * 13  \ falling into the body)

.rtgo                   \ the trampolines' body: A = the low byte of RJT's
 STA rtj+1              \ entry, the routine's A on the stack; the JSR below
                        \ calls the entry (RJT is in one page)
 LDA &F4                \ keep the caller's bank and page bank 5 in
 STA rtB
 LDA BANK5
 STA &F4
 STA &FE30
 PLA                    \ A back for the routine
.rtj
 JSR RJT                \ (the low byte is set above)
 PHA                    \ page the caller's bank back in, keeping A
 LDA rtB
 STA &F4
 STA &FE30
 PLA
 RTS

 ASSERT HI(RJT) = HI(RJT + 3 * 13) AND LO(RJT) <> 0
.rtramp_end

.GCALL
 STA GA                 \ keep A while the bank is paged
 LDA &F4                \ the caller's bank, to page back after
 PHA
 LDA BANK6              \ page bank 6 in (&F4 first, as elite-far.asm)
 STA &F4
 STA &FE30
 JSR FJT                \ the entry X, with A = GA, and Y as it was
 TAX                    \ keep A while the bank is paged (X is not kept)
 PLA                    \ page the caller's bank back in
 STA &F4
 STA &FE30
 TXA                    \ A as the entry left it
 RTS

.GLUE_END
