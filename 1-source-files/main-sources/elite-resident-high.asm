\ ******************************************************************************
\
\ ELITE HIGH RESIDENT BLOCK (Port)
\
\ The Model B port's code and data at RESH% (&7EB0-&7EFF), after the
\ renderer's shared variables and below the missile's blueprint, in main RAM
\ that nothing else uses: the loader's LOAD routine copies it there from
\ RESHcode (elite-loader3.asm). It holds what the vertical sync's and the
\ rupture's interrupt handler (IRQG, in the resident block A) reads, so that
\ the resident block A has room for the renderer's glue.
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: PALCMYK
\       Type: Variable
\   Category: Drawing the screen
\    Summary: The screen's palette: logical colours 0 to 3 are black, cyan,
\             magenta and yellow
\
\ ------------------------------------------------------------------------------
\
\ Port: the sixteen palette register bytes of the four-colour screen, as the
\ BBC Master port's CMYK palette: in a four-colour mode a pixel's two bits
\ are bits 3 and 1 of the palette index, so logical colour L is indices
\ with those bits equal to L's; each byte is the index in bits 4-7 and the
\ physical colour EOR 7 in bits 0-3 (black 0, magenta 5, cyan 6, yellow 3).
\ The vertical sync's interrupt writes it to the video ULA every field.
\
\ ******************************************************************************

 ASSERT P% = PALCMYK

 FOR I%, 0, 15
  L% = ((I% DIV 8) AND 1) * 2 + ((I% DIV 2) AND 1)
  IF L% = 0
   EQUB I% * 16 + (0 EOR 7)
  ELIF L% = 1
   EQUB I% * 16 + (6 EOR 7)
  ELIF L% = 2
   EQUB I% * 16 + (5 EOR 7)
  ELSE
   EQUB I% * 16 + (3 EOR 7)
  ENDIF
 NEXT

 PRINT "High resident block: ", ~RESH%, "-", ~P%-1, ", free ", PFVH%-P%, " (then the circle engine's variables)"
 ASSERT P% <= PFVH%
