\ ******************************************************************************
\
\ gfx-glue.asm - the main RAM glue of the filled renderer (docs/renderer.md)
\
\ Port (Model B): assembled at GLUE% (elite-map.asm), at the end of the
\ resident block A, which INCLUDEs it, so that it is visible whatever bank is
\ paged: the trampolines into bank 5, the rasteriser (gfx-rtramp.asm, which
\ the frame layer calls), and GCALL, through which the game calls the frame
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
\ ******************************************************************************

FJT = &BFC0             \ bank 6's dispatcher (gfx-bank6.asm)

\ (the entries' numbers, FG_*, are in elite-map.asm, for the game's hooks)

 INCLUDE "1-source-files/main-sources/gfx-rtramp.asm"

.GCALL
 STA GA                 \ keep A while the bank is paged
 LDA &F4                \ the caller's bank, to page back after
 PHA
 LDA BANK6              \ page bank 6 in (&F4 first, as elite-far.asm)
 STA &F4
 STA &FE30
 JSR FJT                \ the entry X, with A = GA, and Y as it was
 STA GA
 PLA                    \ page the caller's bank back in
 STA &F4
 STA &FE30
 LDA GA
 RTS

.GLUE_END
