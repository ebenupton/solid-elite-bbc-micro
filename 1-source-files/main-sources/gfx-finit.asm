\ ******************************************************************************
\
\ gfx-finit.asm - the frame layer's one-off initialisation, F_INIT
\
\ Port (Model B): the BBC Master port's gfx-finit.asm. The loader calls it
\ (LDX #FG_INIT : JSR GCALL) once, after loading banks 5 and 6, before the
\ first frame: the rasteriser's state (T_INIT), direct mode with buffer 1
\ (SCREEN%) on show, no records. Buffer 0 (BUF0) holds whatever the loader
\ left there, and DFS's workspace and the staging area are in it, so it is
\ marked as used by a disc command (GSTASH): the first space-mode frame
\ clears it (f_b0new). The text map, F_TCH and the notes are all zero, as
\ loaded: no text, none shown, none noted.
\
\ ******************************************************************************

.F_INIT
 STY f_ysav
 LDX #&21               \ R_INIT uses &06-&27: keep the game's values
.fin0
 LDA &06,X
 STA f_zsv,X
 DEX
 BPL fin0
 JSR T_INIT
 LDX #&21
.fin4
 LDA f_zsv,X
 STA &06,X
 DEX
 BPL fin4
 LDA #0
 STA GMODE
 STA GFLIP
 STA GSIGHT
 STA GLASV
 STA GFORCE
 STA GWARP
 STA GDL
 LDX #NDSTAR-1          \ no stars recorded
.fin1
 STA R_SS,X
 DEX
 BPL fin1
 LDA #1
 STA GFRONT
 LDA #&FF
 STA GSTASH
 JMP f_reset            \ (no docking slot, the lists empty; Y kept)
