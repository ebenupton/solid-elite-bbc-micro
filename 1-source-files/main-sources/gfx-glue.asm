\ ******************************************************************************
\
\ gfx-glue.asm - the main RAM glue of the filled renderer (docs/renderer.md)
\
\ Port (Model B): assembled at GLUE% (elite-map.asm), in the resident block
\ A's spare room, so that it is visible whatever bank is paged: the
\ trampolines into bank R, the rasteriser (gfx-rtramp.asm, which the frame
\ layer calls), and GCALL, through which the game calls the frame layer in
\ bank F. Bank F is built against these addresses (gfx-bankf.asm), and
\ writes GLUE.bin; the resident block is to INCLUDE this file at GLUE% when
\ the game starts calling the renderer (nothing does yet).
\
\ GCALL: X = an entry's number (FG_*, below), A and Y its inputs: pages bank
\ F in (BANKF), enters it through its dispatcher at FJT (the top of bank F),
\ and pages the caller's bank (whatever was in &F4) back in, returning A
\ and Y as the entry left them (every entry keeps Y). The flags and X are
\ not kept. Not re-entrant: interrupt handlers must not call it.
\
\ ******************************************************************************

FJT = &BFC0             \ bank F's dispatcher (gfx-bankf.asm)

FG_INIT     = 0         \ the entries, in fjt_lo's order (gfx-bankf.asm)
FG_DIRECT   = 1
FG_FRAME    = 2
FG_SHIP     = 3
FG_LINE     = 4
FG_DOT      = 5
FG_PLANET   = 6
FG_SHPPT    = 7
FG_PCURVE   = 8
FG_PPOINT   = 9
FG_CHAR     = 10
FG_DELCHAR  = 11
FG_CLRTEXT  = 12
FG_BOMB     = 13
FG_N        = 14

 INCLUDE "1-source-files/main-sources/gfx-rtramp.asm"

.GCALL
 STA GA                 \ keep A while the bank is paged
 LDA &F4                \ the caller's bank, to page back after
 PHA
 LDA BANKF              \ page bank F in (&F4 first, as elite-far.asm)
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
