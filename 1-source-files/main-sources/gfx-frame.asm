\ ******************************************************************************
\
\ gfx-frame.asm - the filled renderer's frame layer, in bank 6
\ (docs/renderer.md, "The frame layer's bank 6")
\
\ Port (Model B): the BBC Master port's frame layer (its gfx-frame.asm, in
\ the hand-converted NMOS 6502 code of its Model B branch), adapted to the
\ Model B's memory. The game's drawing routines, in a view that draws ships
\ (QQ11 = 0, GFORCE = 0: record mode), record what they would have drawn
\ through GCALL (gfx-glue.asm: LDX #FG_xxx : JSR GCALL), and once per main
\ loop iteration F_FRAME draws the records into the buffer not on show and
\ asks the interrupt to show it (GFLIP, GPEND). LL9 records each ship as its
\ part 6 starts (F_SHIP), and the frame runs part 6 on for it as it draws it
\ (f_proj), as it runs PTCLS for an explosion cloud (f_dots); the text is a
\ map of the characters wanted (F_TM), drawn incrementally per buffer.
\
\ What differs from the Master port's, for the Model B:
\
\   * The two buffers are both in main RAM, at BUF0 (&1000, buffer 0) and
\     SCREEN% (&4000, buffer 1, the direct-mode screen), so there is no ACCCON
\     paging: what this bank writes to the screen itself (the text, the
\     sights' vertical arms, the lens flare, the border at f_enter) takes the
\     back buffer's base, which f_bufpatch sets each frame (f_scr).
\
\   * The rasteriser (bank 5) keeps its state in its own bank, which this
\     bank cannot see: it is reached only through the trampolines in main
\     RAM (T_INIT to T_GETW, gfx-rtramp.asm), with the inputs in its
\     mailbox (MBOX) and zero page (&06-&27). So what the Master port's frame
\     layer read or wrote of the rasteriser's arrays goes through bank 5: a
\     cell f_mark erases is marked dirty at each buffer's next frame
\     (f_text1, R_MARKBOX), and what f_text2 and f_sight2 need of this
\     frame's written extents comes from one query (R_GETW with A = &40).
\
\   * The game's zero page overlaps the rasteriser's (XX16 is &09-&1A, XX0
\     &1E) and this layer's (XX2 is FZ): the frame's runs of game code (part
\     6 on, PTCLS) are made through f_game, which puts the clip window back
\     after them, and nothing of FZ is kept across them.
\
\   * The game's code that the frame runs is reached through the far call
\     farH (elite-far.asm), at fixed entries in each program's S% table:
\     S% + 16 (LL42F: LL9's part 6 on) and S% + 19 (PTCLR: PTCLS's drawing).
\
\   * The discs are the Master port's (f_dprep, f_ddraw, f_disc2), with the
\     disc layer's row code, the painter, in the flight code's bank 7
\     (gfx-raster_disc.asm, gfx-raster_disc2.asm), reached by far calls and
\     given its rows a batch at a time in the mailbox; the planet's surface
\     rows (PC_ROWS, gfx-merid.asm) and the sun near the planet (S_SUN,
\     gfx-ssun.asm, a build with _SSUN) are in this bank.
\
\   * The lighting (L_SUN, L_REC, gfx-light.asm) runs in the game's bank 4,
\     where the quarter squares are: F_SHIP is given the faces' levels in XX2.
\
\   * Every entry keeps Y (but F_GUN, which returns one), and takes its
\     inputs in A, Y and memory (GCALL carries the entry's number in X).
\
\ ******************************************************************************

FZ = &D2                \ &D2-&E1: the frame layer's zero page during F_FRAME
fz_p    = FZ            \ general pointer (2)
fz_q    = FZ+2          \ second pointer (2)
fz_dl   = FZ+4          \ ship's levels in F_SR (2)
fz_v3   = FZ+6          \ general pointer (2), used by the text overlay
fz_ft   = FZ+8          \ face list pointer (2)
fz_nm   = FZ+10         \ general pointer (2), used by the text overlay
fz_dt   = FZ+10         \ ship's fin / detail list pointer (2)
fz_i    = FZ+12
fz_n    = FZ+13
fz_t    = FZ+14
fz_u    = FZ+15
                        \ (the game's XX2, K3 and K4, dead between main loop
                        \ iterations: F_FRAME keeps them with &06-&27 in f_zsv,
                        \ and they hold nothing across f_game, as part 6 reads
                        \ the faces' levels as XX2)

R_COLE  = &06           \ the rasteriser's zero page inputs (gfx-raster.asm's
R_COLO  = &07           \ names, which bank 5 assembles): the colour pair,
R_XL    = &08           \ the span ends and the clip window
R_XR    = &09
R_CL    = &0A
R_CR    = &0B
R_CT    = &0C
R_CB    = &0D
R_DCE   = &0E           \ (the disc layer's colour pair, for the painter in
R_DCO   = &0F           \ bank 7: f_ddraw)
RZ_T0   = &20           \ (DP_BEGIN's colour B pair)
RZ_T1   = &21

MAXSH = NOSH            \ ships per frame: LL9 records a ship at most once an
                        \ iteration, and only the ships in the NOSH slots
                        \ (the planet and the sun are not recorded)
MAXLN = MAXSH           \ lines per frame: the enemy beams, one per ship
                        \ recorded (H_EE31)
MAXDT = MAXSH           \ dots per frame: a distant ship's (SHPPT) or an
                        \ explosion cloud (DOEXP), at most one per ship recorded

NDSTAR = NOST + 1       \ stars 1..NOST in the mailbox's R_SX, R_SY, R_SS

F_DODO = 32             \ GTYPE of the dodecahedron station (gfx-faces.asm)

SGPROJ = HOME% + 16     \ the game's entries the frame runs (each program's S%
SGCLOUD = HOME% + 19    \ table, elite-source-*.asm): LL42F, PTCLR

\ ------------------------------------------------------------------------------
\ State
\ ------------------------------------------------------------------------------

\ Shared with the interrupt and the game (GVARS, elite-map.asm): GMODE (bit 7
\ set = space mode, double buffered), GFRONT (the buffer shown), GFLIP (non-
\ zero = flip pending to GPEND), GPEND, GFORCE (non-zero = draw directly
\ even though QQ11 = 0), GSIGHT, GLASV, GWARP, GSTASH, GNF, GTYPE, PF_CLS.

.F_BACK     EQUB 1      \ the buffer being drawn (the one not displayed)
.F_TCH      SKIP 24     \ per text row: bit b set (P) = the row changed since
                        \ buffer b's text steps last ran on it (whole in a
                        \ page: f_text1 reads it every frame, by row)
ASSERT HI(F_TCH) = HI(F_TCH + 23)

.F_NSHIP    EQUB 0      \ ships recorded this frame
.F_STYP     SKIP MAXSH  \ ship type
.F_SNF      SKIP MAXSH  \ number of faces
.F_SPL      SKIP MAXSH  \ the ship's faces' levels in F_SR (F_SHIP)
.F_SPH      SKIP MAXSH
.F_ORD      SKIP MAXSH  \ draw order (indices, far to near)
.F_SX4      SKIP MAXSH  \ LL9's XX4 (vertex visibility cut-off)
.F_DLP      EQUW F_SR   \ next free byte in F_SR

.F_NLINE    EQUB 0      \ enemy laser beams recorded this frame
.F_LX0      SKIP MAXLN
.F_LY0      SKIP MAXLN
.F_LX1      SKIP MAXLN
.F_LY1      SKIP MAXLN

.F_NDOT     EQUB 0      \ dots recorded this frame: distant ships and
.F_DX       SKIP MAXDT  \ explosion clouds, at most one per ship slot
.F_DY       SKIP MAXDT  \ (F_SHPPT: x, y, &80 + the ship type; F_CLOUD:
.F_DC       SKIP MAXDT  \ INF, the slot)

.F_PLON     EQUB 0      \ planet disc recorded this frame
.F_PLX      EQUW 0      \ centre x (16-bit signed screen)
.F_PLY      EQUW 0      \ centre y
.F_PLR      EQUB 0      \ radius
.F_PLT      EQUB 0      \ planet type

.F_SUON     EQUB 0      \ sun disc recorded this frame (F_PLANET)
.F_SUX      EQUW 0      \ its centre x, y (16-bit signed screen)
.F_SUY      EQUW 0
.F_SUR      EQUB 0      \ its radius

\ ------------------------------------------------------------------------------
\ Fixed colours (even-row byte, odd-row byte), by index (FC_BLACK to FC_STAR:
\ elite-map.asm)
\ ------------------------------------------------------------------------------

FC_PARTB = &FF          \ (the particles' colour byte: F_PDOT)
.F_CPE
 EQUB &00, &FF, &F0, &0F, FC_PARTB, &0F, &FF
F_CPO = F_CPE           \ (the odd rows' bytes are the even rows')

\ ------------------------------------------------------------------------------
\ Text map: 24 rows x 32 columns of desired characters (F_TM). A cell holds
\ its character (&20-&7F), or 0, or, once cleared, &80 + the character it
\ had (empty, remembering it), or &80 (empty: f_drule's mark for a cell a
\ buffer may show anything in). F_TMR counts each row's non-empty cells.
\ F_TCH holds, per row, bit b (P) for buffer b: the row has changed since
\ buffer b's text steps last ran on it. Nothing else records what a buffer
\ shows; between frames, for each buffer b and row:
\
\   * P clear: b shows exactly the row's characters (nothing in an empty
\     cell);
\   * P set: a cell holding c or &80 + c shows c or nothing, one holding 0
\     nothing, one holding &80 anything.
\
\ A cell given a different character (not into an empty, never-shown cell,
\ not its remembered one: f_char1) is erased at once in both buffers' next
\ frames, through their dirty extents (f_mark). A buffer's text steps, in a
\ row with P set, erase each cell with bit 7 set (f_text1), draw every
\ character (f_text2) and clear P; elsewhere they redraw only the
\ characters something was drawn over this frame. So a cell cleared and
\ given its character back (TT66 and a view's title) is left alone in both
\ buffers, as with the original's shown maps. Once both buffers have erased
\ a cleared cell it holds 0 (f_text1). A buffer's screen cleared (TTX66,
\ f_b0new) shows nothing: right for any P, as everything in the map since
\ (the screen's text) set P.
\
\ Outside record and space mode TT26 draws into buffer 1 (SCREEN%) and
\ the map changes only so that buffer 0 (BUF0, the last space-mode
\ frame: f_enter) knows what of its text the screen's text has overprinted
\ (f_drule), with one exception: the first DLMAX characters after a screen
\ clear are noted (f_dlx/f_dly/f_dlk, f_dlog) and given to the map at the
\ first change in record or space mode (f_sync), as the screens that carry
\ on in record mode without a TT66 (DEATH's and TITLE's TT66 13, then QQ11
\ = 0; the briefing's LL9B) have drawn at most TTX66's hyperspace
\ countdown (ee3: three characters) directly, which then stays on the
\ screen (docs/renderer.md, "The text map").
\ ------------------------------------------------------------------------------

DLMAX = 3               \ (TTX66's ee3: TT11, three digits)

\ f_cell: X = column, Y = row -> the map accessors f_tmld/f_tmst patched to
\ its cell (row*32 + column)

.f_cell
 TYA
 LSR A
 LSR A
 LSR A
 STA f_tmld+2           \ row DIV 8 = high byte of row*32
 TYA
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A                  \ (row MOD 8) * 32
 STX f_tmld+1
 ORA f_tmld+1          \ (F_TM is page aligned: LO(F_TM) = 0)
 STA f_tmld+1
 STA f_tmst+1
 LDA f_tmld+2
 CLC
 ADC #HI(F_TM)
 STA f_tmld+2
 STA f_tmst+2
 RTS

.f_row  EQUB 0
.f_tbit EQUB 0          \ this frame's buffer's bit in F_TCH (1 or 2)
.f_obit EQUB 0          \ and the other buffer's

\ f_char1 (F_CHAR, frame_cold.asm; f_sync): character A into the cell at
\ column X, row Y. EOR semantics like the original: printing the same
\ character again removes it.

.f_char1
 CPY #24
 BCS fch9
 CPX #32
 BCS fch9
 STY f_row
 STX f_tcol
 STA f_tmp
 JSR f_cell
 JSR f_tmget            \ X = the cell
 BEQ fch1               \ empty, never shown: store the character
 TXA
 BMI fch3
 CMP f_tmp
 BEQ fch2               \ the same character: remove it
 JSR f_eor              \ the one this cell's character replaced since the
 BCS fch8               \ frame: EOR takes it out again, the cell is unchanged
 JSR f_mark             \ another: replace it (erased in both buffers)
 BNE fch4               \ (NMOS: f_mark returns with Z clear)
.fch3
 AND #&7F               \ cleared: the character it remembers is shown as it
 CMP f_tmp              \ was; another is drawn over an erased cell
 BEQ fch1
 JSR f_mark
.fch1
 LDX f_row
 INC F_TMR,X
.fch4
 LDA f_tmp
 JSR f_tmst
 BNE fch8               \ (NMOS: A = the character, not zero)
.fch2
 JSR f_tmclr
 LDX f_row
 DEC F_TMR,X
.fch8
 LDX f_row
 LDA #3
 STA F_TCH,X
.fch9
 RTS

\ f_eor: character f_tmp printed over the cell at f_tcol, f_row, which holds
\ another, A. CHPR draws by EOR, and TT107 prints the countdown's next
\ number over the current one and then the current one again, to take it
\ out: so when a cell was given its character over f_tmp since the last
\ frame, printing f_tmp again leaves the cell as it is (C set). Otherwise
\ (C clear) the replacement of A is noted in a ring of RPN cells (the
\ countdown replaces at most three at a time; f_text1 forgets them).

RPN = 4

.f_eor
 STA f_eok
 LDX f_rpn
 CPX #RPN+1
 BCC P%+4
 LDX #RPN
.feo1
 DEX
 BMI feo4
 LDA f_rpr,X
 CMP f_row
 BNE feo1
 LDA f_rpc,X
 CMP f_tcol
 BNE feo1
 LDA f_rpk,X
 CMP f_tmp
 BNE feo1
 LDA #&FF               \ (taken out: forgotten)
 STA f_rpr,X
 SEC
 RTS
.feo4
 LDA f_rpn
 INC f_rpn
 BNE P%+5
 DEC f_rpn              \ (saturates at 255)
 AND #RPN-1
 TAX
 LDA f_row
 STA f_rpr,X
 LDA f_tcol
 STA f_rpc,X
 LDA f_eok
 STA f_rpk,X
 CLC
 RTS

.f_rpn  EQUB 0          \ cells noted since the last frame (to 255)
.f_rpr  SKIP RPN        \ their rows (&FF: none), columns and replaced
.f_rpc  SKIP RPN        \ characters
.f_rpk  SKIP RPN
.f_eok  EQUB 0

.f_tmclr                \ the cell (not empty, X from f_tmget) cleared: it
 TXA                    \ remembers its character, which each buffer shows
                        \ or not as before
 ORA #&80
.f_tmst
 STA F_TM               \ patched
 RTS

.f_tmget
.f_tmld
 LDX F_TM               \ patched; sets Z and N on the content
 RTS

.f_ysav EQUB 0
.f_tmp  EQUB 0
\ f_mark: the cell at column f_tcol, row f_row is given a character where a
\ buffer may show another: erase it in both buffers' next frames (buffer 0's
\ only while f_mk0 is set, f_sync), as f_text1's erases do there. Port
\ (Model B): bank 5's dirty extents are out of reach here (F_CHAR runs
\ between frames, and any bank may be paged), so the cell's column is noted
\ per buffer and text row (f_mkl, f_mkr: the leftmost cell and the rightmost
\ plus one, 0 for none), and f_text1 marks the cells dirty (R_MARKBOX,
\ clipped to the space views' clip window, x 2..253, y 1..191) at the
\ buffer's next frame, before its repair: the same pixels, but where two
\ noted cells of a row are apart, the cells between them too, which that
\ frame's text steps redraw (f_char1 sets the row's F_TCH bits). Returns
\ with Z clear

.f_mark
 LDY f_row              \ the row's notes for buffer 0, then buffer 1 (24 on)
 LDX #0
.fmk0
 LDA f_mkr,Y            \ none noted in the row yet: this cell alone
 BEQ fmk1
 LDA f_tcol             \ else widen the noted cells to this one
 CMP f_mkl,Y
 BCS fmk2
 STA f_mkl,Y
.fmk2
 LDA f_tcol             \ (the rightmost plus one: column + 1 if it is the
 CMP f_mkr,Y            \ rightmost now)
 BCC fmk3
.fmk4
 ADC #0                 \ (C = 1: + 1)
 STA f_mkr,Y
 BNE fmk3               \ (always: column + 1 > 0)
.fmk1
 LDA f_tcol
 STA f_mkl,Y
 SEC
 BCS fmk4
.fmk3
 LDA #&FF               \ the buffer has notes
 STA f_mkn,X
 TYA
 CLC
 ADC #24
 TAY
 INX                    \ (CPX #1, so that both exits have Z clear, f_char1:
 CPX #1                 \ X = 2, done; X = 1, buffer 1 unless f_mk0)
 BNE fmk9
 LDA f_mk0
 BEQ fmk0
.fmk9
 RTS

.f_mkn  EQUB 0, 0       \ per buffer: non-zero if it has cells noted
.f_mkl  SKIP 48         \ per buffer, per text row: the leftmost cell noted
.f_mkr  SKIP 48         \ and the rightmost plus one (0: none)
.f_mk0  EQUB 0          \ non-zero: f_mark leaves buffer 1 alone


\ f_delchar0 (F_DELCHAR, frame_cold.asm): clear the text map cell at X =
\ column, Y = row

.f_delchar0
 STY f_ysav
 CPY #24
 BCS fdc9
 CPX #32
 BCS fdc9
 STY f_row
 JSR f_cell
 JSR f_tmget
 BEQ fdc9
 BMI fdc9
 JSR f_tmclr
 LDX f_row
 DEC F_TMR,X
 LDA #3
 STA F_TCH,X
.fdc9
 LDY f_ysav
 RTS

\ f_clrtext0 (F_CLRTEXT, frame_cold.asm; f_direct0): clear text map rows X
\ to Y inclusive (each cell remembers its character; a row with no
\ character is left as it is). Y is kept

.f_clrtext0
 STY f_tmp
.fct0                   \ (F_CLRTEXT, with f_tmp set)
 STY f_ysav
.fct1
 STX f_row
 LDA F_TMR,X            \ (an empty row is clear already)
 BEQ fct6
 LDY f_row
 LDX #0
 JSR f_cell             \ f_tmst -> start of row
 LDA f_tmst+1
 STA fct3+1
 STA fct4+1
 LDA f_tmst+2
 STA fct3+2
 STA fct4+2
 LDY #31
.fct3
 LDA F_TM,Y             \ patched
 BEQ fct5
 ORA #&80
.fct4
 STA F_TM,Y             \ patched
.fct5
 DEY
 BPL fct3
 LDX f_row
 LDA #0
 STA F_TMR,X
 LDA #3
 STA F_TCH,X
.fct6
 INX
 CPX #24
 BCS fct9
 CPX f_tmp
 BCC fct1
 BEQ fct1
.fct9
 LDY f_ysav
 RTS

\ ------------------------------------------------------------------------------
\ f_direct0 (F_DIRECT, frame_cold.asm): the screen is about to be cleared and
\ drawn directly (TTX66): cancel double buffering and show buffer 1
\ (SCREEN%), the direct-mode screen
\ ------------------------------------------------------------------------------

.f_direct0
 PHP                    \ (the interrupt reads GMODE, GFLIP and GFRONT)
 SEI
 LDA #0
 STA GMODE
 STA GFLIP
 STA GSIGHT
 STA GLASV
 LDA #1
 STA GFRONT
 PLP
 LDX #0                 \ the text map cleared (Y is kept)
 LDY #23
 JSR f_clrtext0
 LDA #0
 LDX #NDSTAR-1          \ the stars will be re-recorded too
.fdi1
 STA R_SS,X
 DEX
 BPL fdi1
 RTS                    \ (NMOS: A = 0, F_DIRECT's f_dlog)

\ ------------------------------------------------------------------------------
\ Recorders (called during the main loop; must only touch Elite variables they
\ are documented to read, and preserve Y)
\ ------------------------------------------------------------------------------

\ F_SHIP: record the ship LL9 is drawing, before it projects the vertices
\ (S_SHIP, as LL9's part 6 starts): its type (GTYPE: TYPE, or F_DODO for the
\ dodecahedron station, whose slot is SST's), faces (GNF) and vertex cut-off
\ (XX4), its faces' levels in F_SR (XX2, which the game's L_REC has lit:
\ gfx-light.asm), and in F_RP, a field to an array of MAXSH, its place
\ (INWK 0-8: the sort's z is INWK 6-7, F_SZL and F_SZH), its orientation as
\ part 3 scaled it (XX16) and its blueprint (XX0): all that part 6 (LL42 on)
\ reads, which the frame runs for it (f_proj). A ship slot is recorded at
\ most once a frame, and a ship has at most 15 faces: F_SR holds MAXSH sets
\ of levels.

.F_SHIP
 STY f_ysav
 LDX F_NSHIP
 CPX #MAXSH
 BCC P%+5
 JMP fsh9
 FOR k, 0, 8
  LDA INWK+k
  STA F_RP+k*MAXSH,X
 NEXT
 FOR k, 0, 17
  LDA XX16+k
  STA F_RP+(9+k)*MAXSH,X
 NEXT
 LDA XX0
 STA F_RP+27*MAXSH,X
 LDA XX0+1
 STA F_RP+28*MAXSH,X
 LDA F_DLP
 STA F_SPL,X
 STA fsh2+1
 LDA F_DLP+1
 STA F_SPH,X
 STA fsh2+2
 LDA GTYPE
 STA F_STYP,X
 LDA GNF
 STA F_SNF,X
 LDA XX4
 STA F_SX4,X
 LDY #0                 \ the faces' levels (XX2, lit: gfx-light.asm)
 LDX GNF
 BEQ fsh3
.fsh1
 LDA XX2,Y
.fsh2
 STA &FFFF,Y            \ patched
 INY
 DEX
 BNE fsh1
.fsh3
 TYA                    \ (Y = nf)
 CLC
 ADC fsh2+1
 STA F_DLP
 LDA fsh2+2
 ADC #0
 STA F_DLP+1
 INC F_NSHIP
.fsh9
 LDY f_ysav
 RTS

\ F_PDOT: a particle of the frame's PTCLS (f_dots, through f_game; the game's
\ H_DOT, at PIXEL's call in PTCLS), at x = A, y = Y1, its size from ZZ as
\ PIXEL's: one pixel for ZZ >= 144, a dash for ZZ >= 80, a double-height
\ dash below, in the particles' colour. PTCLS keeps Y (its particle count)
\ and K3 (FZ, which T_DOT does not touch) across it; the clip window is the
\ frame's (part 6 on, which overwrites it, runs only through f_game)

.F_PDOT
 STY f_pdy              \ (not f_ysav: F_FRAME's, which this runs within)
 TAX
 LDA #FC_PARTB
 STA R_COLE
 STA R_COLO
 LDY Y1
 LDA ZZ                 \ the size: 1 for ZZ >= 144, else 2 for ZZ >= 80 (C
 CMP #144               \ set), 3 below (C clear)
 LDA #1
 BCS fpd1
 LDA ZZ
 CMP #80
 LDA #0
 ROL A
 EOR #3
.fpd1
 JSR T_DOT
 LDY f_pdy
 RTS

.f_pdy EQUB 0

\ F_PLANET: record the planet (TYPE even) or the sun (odd): centre (K3, K4)
\ 16-bit, radius K; the planet's z (24-bit: a planet 65536 or more away is
\ held as z_hi = &FF, further than any ship drawn with faces, which is
\ nearer than 4096), for hiding ships behind it (f_behind)

.F_PLANET
 LDA TYPE
 LSR A
 BCS fpl1
 LDA K3
 STA F_PLX
 LDA K3+1
 STA F_PLX+1
 LDA K4
 STA F_PLY
 LDA K4+1
 STA F_PLY+1
 LDA K
 STA F_PLR
 LDA TYPE
 STA F_PLT
 LDA INWK+8             \ the planet's z is 24-bit, and a ship drawn with
 BEQ P%+4               \ faces is nearer than 4096: a planet 65536 or more
 LDA #&FF               \ away is held as z_hi = &FF, further than any such
 ORA INWK+7             \ ship
 STA F_PLZH
 LDA INWK+6
 STA F_PLZL
 LDA #&FF
 STA F_PLON
 RTS

.F_PLZH EQUB 0          \ the planet's z (hi, lo), for hiding ships behind it
.F_PLZL EQUB 0
.fpl1                   \ the sun
 LDA K3
 STA F_SUX
 LDA K3+1
 STA F_SUX+1
 LDA K4
 STA F_SUY
 LDA K4+1
 STA F_SUY+1
 LDA K
 STA F_SUR
 LDA #&FF
 STA F_SUON
 RTS

\ ------------------------------------------------------------------------------
\ F_FRAME: render this frame's display list into the back buffer and queue a
\ flip. Called once per main-loop iteration (after M%: MFRAME), and per
\ iteration of the escape pod's drift, the title screen and the briefings
\ (LL9F, LL9B), and for the hangar (F_HANGAR)
\ ------------------------------------------------------------------------------

.F_FRAME
 STY f_ysav
IF _SSUN
 BCC ff0s               \ the flight code's frame (C set: hframe): the sun near
 JSR S_SUN              \ the planet first, in every iteration (gfx-ssun.asm)
.ff0s
ENDIF
 LDA QQ11
 BEQ ff1
 JMP f_reset            \ not a space view: just forget what was recorded

.ff1                    \ (the game's MFRAME has run L_SUN, the light for the
                        \ next iteration's ships, in bank 4)

 \ keep the zero page the rasteriser uses (&06-&27) and the frame layer's
 \ (&D2-&E1), unrolled, in f_zsv, not on the stack: the frame's ship
 \ projection puts the vertices in XX3, page 1 from &0100, under the stack
 FOR z, &06, &27
  LDA z
  STA f_zsv + z - &06
 NEXT
 FOR z, 0, 15
  LDA FZ + z
  STA f_zsv + &22 + z
 NEXT

 BIT GMODE              \ the first space-mode frame since the screen was
 BPL ff0                \ cleared, or a disc command has used buffer 0 (the
 BIT GSTASH             \ staging area and DFS's workspace are in it: PCLI)
 BPL ff5
.ff0
 JSR f_enter2           \ (f_enter, with frame_cold.asm's fix-ups)

.ff5                    \ (what touches no screen memory goes before the wait)
 JSR f_bufpatch
 JSR f_clip             \ the clip window inside the border (the zero page
                        \ copy is the game's between frames)
 LDA F_BACK
 JSR T_SETBUF
 JSR f_dprep            \ the discs' rows (first: PC_ROWS reads the mailbox)
 JSR f_text1            \ text cells to be erased: background them (old dirty)
 JSR f_sight1           \ and the sights, if they have gone
 LDA F_NSHIP            \ the ships in their order, the first one projected
 BEQ P%+10              \ (f_sort, f_proj0)
 LDA #&FF
 STA f_pj
 JSR f_sort

.ff2
 LDA GFLIP              \ wait for the previous flip, so the back buffer is
 BNE ff2                \ no longer on screen

 JSR T_STARERASE        \ undo last time's stars in this buffer
 JSR f_ddraw            \ repair the rest of what was drawn on it, and draw
                        \ the sun and the planet (the disc layer and the
                        \ second disc, through the painter in bank 7)
.ff_lin                 \ (F_HANGAR points this call at f_hback for its frame)
 JSR f_lines            \ enemy lasers
 JSR f_ships            \ filled ships, far to near
 JSR f_dots             \ particles, distant ships
 JSR f_lasers           \ our laser beams
 JSR f_flt              \ the lens flare (gfx-flare6.asm), then the text on top
 JSR f_sight2           \ and the sights
.ff_stars
 LDA #NDSTAR            \ stardust, on black only (last: erasing it next
 STA R_SN               \ time restores black, so it needs no WL/WR): stars
 LDA F_SLV+16           \ 1..NOST, recorded by the hooks straight into the
 CMP #&80               \ mailbox's R_SX/R_SY/R_SS (R_SS = 0: none); with a
 BEQ ffs1               \ docking slot filled this frame, f_slot
 JSR f_slot             \ (gfx-frame_cold.asm) plots them
 BMI ff_stars9          \ (NMOS: f_slot returns with N set)
.ffs1
 JSR T_STARPLOT
.ff_stars9              \ (the frame's drawing done: the harness's frame end)

 BIT f_gz               \ the game's zero page back, if the frame ran game
 BPL P%+5               \ code (f_gkeep)
 JSR f_gback

 FOR z, 0, 15            \ restore the zero page (kept at ff1)
  LDA f_zsv + &22 + z
  STA FZ + z
 NEXT
 FOR z, &06, &27
  LDA f_zsv + z - &06
  STA z
 NEXT

 LDA F_BACK             \ show it at the next vertical sync (the interrupt
 STA GPEND              \ reads GPEND once GFLIP is set)
 EOR #1
 STA F_BACK
 LDA #&FF
 STA GFLIP

.f_reset
 LDA #&80               \ no docking slot (f_poly2 records one, f_slot uses it)
 STA F_SLV+16
.f_lists
 LDA #0                 \ empty the per-frame lists
 STA GLASV              \ (the beams show for one frame per LASLI)
 STA F_NSHIP
 STA F_NLINE
 STA F_NDOT
 STA F_PLON
 STA F_SUON
 LDA #LO(F_SR)
 STA F_DLP
 LDA #HI(F_SR)
 STA F_DLP+1
 LDY f_ysav
 RTS

\ f_clip: the clip window inside the border, x 2..253, y 1..191 (F_FRAME,
\ and again after any game code the frame runs: f_game)

.f_clip
 LDA #2
 STA R_CL
 LDA #253
 STA R_CR
 LDA #1
 STA R_CT
 LDA #191
 STA R_CB
 RTS

\ f_enter: switch from direct drawing to double buffering. Buffer 1
\ (SCREEN%), the direct-mode screen, has just been cleared by TTX66 and
\ given its border: forget its rasteriser state. Buffer 0 (BUF0) still
\ holds the last frame of the previous space-mode session, which its
\ rasteriser state, disc layer and text notes still describe (direct mode
\ never writes it), so it is left alone and repaired incrementally by its
\ next frame; only the border is copied across (buffer 0 has none after a
\ disc command: f_b0new). Called with GMODE bit 7 clear, or (GSTASH) when a
\ disc command has used buffer 0 in space mode, when only buffer 0 starts
\ afresh (f_b0new) and has the border copied.

.f_enter
 LDA #HI(SCREEN%)       \ copy byte columns 0 and 63 of every line, and the
 STA fen1+2             \ whole of line 0, from buffer 1 to buffer 0
 LDA #HI(BUF0)
 STA fen2+2
 LDA #HI(SCREEN%)+1
 STA fen5+2
 LDA #HI(BUF0)+1
 STA fen6+2
.fen0
 LDX #7
.fen1
 LDA SCREEN%,X          \ (patched) column 0, lines 0-7 of a character row
.fen2
 STA BUF0,X             \ (patched)
.fen5
 LDA SCREEN%+&1F8,X     \ (patched) column 63
.fen6
 STA BUF0+&1F8,X        \ (patched)
 DEX
 BPL fen1
 CLC                    \ the next character row, two pages on (no carry)
 LDA fen1+2
 ADC #2
 STA fen1+2
 LDA fen2+2
 ADC #2
 STA fen2+2
 LDA fen5+2
 ADC #2
 STA fen5+2
 LDA fen6+2
 ADC #2
 STA fen6+2
 CMP #HI(BUF0)+1+&30    \ (24 rows)
 BNE fen0
 LDX #0                 \ line 0: bytes 0, 8, 16, ... of the first two pages
.fen7
 LDA SCREEN%,X
 STA BUF0,X
 LDA SCREEN%+&100,X
 STA BUF0+&100,X
 TXA
 CLC
 ADC #8
 TAX
 BNE fen7
 BIT GMODE              \ (a disc command in space mode: buffer 1 is the
 BMI fen9               \ frames', as it was)
 LDA #1                 \ buffer 1's state: empty (TTX66 blacked it)
 STA F_BACK
 STX F_SGS+1            \ (NMOS: X = 0, fen7's end: no sights in it,
 STX f_mkn+1            \ and no cells to erase: its text shows nothing,
 JSR T_SETBUF           \ right for any F_TCH: the text map)
 JSR T_RESETBUF
 LDX #1                 \ (nor any disc: f_dforget)
 JSR f_dforget
 LDA #0
 STA F_BACK             \ buffer 1 is on show: draw into buffer 0 first
 STA GFLIP
 LDA #&80
 STA GMODE
.fen9
 RTS
 ASSERT (SCREEN% - BUF0) MOD &100 = 0 AND LO(BUF0) = 0

\ f_bufpatch: this frame's buffer's screen base (f_scr: the high byte of
\ BUF0 or SCREEN%) into the code that writes the screen itself: the text
\ (f_glyph), the sights' vertical arms (f_sight2) and the lens flare
\ (gfx-flare.asm)

.f_bufpatch
 LDX F_BACK
 LDA fbp_scr,X
 STA f_scr
 CLC                    \ the sights' arms' bytes: &5304, &5500, &5B03 and
 ADC #&13               \ &5D00 in buffer 1 (SCREEN%), &3000 lower in buffer
 STA fsg4a+2            \ 0 (no carries)
 STA fsg4b+2
 ADC #2
 STA fsg5a+2
 STA fsg5b+2
 ADC #6
 STA fsg6a+2
 STA fsg6b+2
 ADC #2
 STA fsg6c+2
 STA fsg6d+2
 RTS
.fbp_scr EQUB HI(BUF0), HI(SCREEN%)
.f_scr   EQUB HI(SCREEN%)       \ this frame's buffer's screen base, high byte

\ ------------------------------------------------------------------------------
\ The discs (Port: the BBC Master port's f_discs and f_disc2, with its disc
\ layer's row code, the painter, in the flight code's bank 7: gfx-raster_disc.asm
\ and gfx-raster_disc2.asm, reached by far calls, farC; docs/renderer.md, "The
\ discs"). The bigger of the sun and the planet (the sun if not smaller) is
\ the disc layer, kept on each buffer from frame to frame and drawn where it
\ changed: its spans (f_sunrows, f_plrows: R_NDISCL/R, R_NDT, R_NDB) and the
\ planet's surface as boundaries (f_bounds: R_NDN, R_NDX0-3, R_NDF, from the
\ circle engine's PC_ROWS, gfx-merid.asm), made before the wait (f_dprep);
\ the other, if both are on the screen, is the second disc, behind it,
\ incremental too (f_disc2). After the wait (f_ddraw) bank 5 repairs the
\ dirty rows outside the band of the layer's rows, old and new (T_REPAIR),
\ and the painter takes the band's rows a batch at a time in the mailbox
\ (gfx-rws.asm: DB_*), with their dirty extents from bank 5, whose row
\ extents then get what it wrote (T_GETW: f_dbat). Each buffer's rows of
\ the layer (f_dlt, f_dlb), its colour (F_DCOL), whether its rows had
\ boundaries (f_bmode) and the second disc's rows and colour (R_S2T, R_S2B,
\ R_S2C) are kept here; a blanked buffer's are forgotten (f_dforget), and
\ the painter's with them at its next frame (f_dpr: DP_BEGIN's PB_RESET).
\ ------------------------------------------------------------------------------

\ f_dprep: which disc is the layer (f_lay: 1 the sun, 2 the planet, 0 none)
\ and which the second (f_sec), and the layer's rows (F_FRAME, before the
\ wait, and before anything of the frame uses the mailbox: f_bounds' PC_ROWS
\ reads the planet's records there, PCB)

.f_dprep
 LDA #0
 STA f_lay
 STA f_sec
 LDA F_SUON             \ the sun this frame?
 BEQ fds2
 LDA F_PLON
 BEQ fds1               \ the sun only
 LDA F_SUR
 CMP F_PLR
 BCC fds3               \ the planet bigger: the planet the layer, the sun second
 LDA #2
 STA f_sec              \ the sun the layer, the planet second
.fds1
 LDA #1
 STA f_lay
 BNE f_sunrows          \ (always)
.fds2
 LDA F_PLON
 BEQ fds9               \ neither
 LDA #2
 STA f_lay
 BNE fds6               \ (always)
.fds3
 LDA #2
 STA f_lay
 LDA #1
 STA f_sec
.fds6
 JSR f_plrows           \ the planet's spans, and its surface as boundaries
 JMP f_bounds
.fds9
 LDA #1                 \ no disc: no rows (R_NDF: f_nobounds)
 STA R_NDT
 LSR A                  \ (A = 0)
 STA R_NDB
 JMP f_nobounds

\ f_sunrows / f_plrows: a disc's spans into R_NDISCL/R and R_NDT/R_NDB, from
\ its centre (16-bit screen coordinates) and radius (8-bit), using a cached
\ half-width table per disc (rebuilt only when the radius changes); the sun
\ a disc of one colour (R_NDF: f_nobounds)

.f_sunrows
 JSR f_nobounds
 LDA F_SUX
 STA f_cx
 LDA F_SUX+1
 STA f_cxh
 LDA F_SUY
 STA f_cy
 LDA F_SUY+1
 STA f_cy+1
 LDA F_SUR
 STA f_r
 CMP f_hw2r
 BEQ fsu1
 STA f_hw2r
 LDA #HI(F_HW2)
 STA fhw_st+2
 JSR f_hwbuild
.fsu1
 LDA #HI(F_HW2)
 STA fpr_ld+2
 STA fpr_ld2+2
 JMP f_discspans

.f_plrows
 LDA F_PLX
 STA f_cx
 LDA F_PLX+1
 STA f_cxh
 LDA F_PLY
 STA f_cy
 LDA F_PLY+1
 STA f_cy+1
 LDA F_PLR
 STA f_r
 CMP f_hwr
 BEQ fpr1
 STA f_hwr
 LDA #HI(F_HW)
 STA fhw_st+2
 JSR f_hwbuild
.fpr1
 LDA #HI(F_HW)
 STA fpr_ld+2
 STA fpr_ld2+2
 JMP f_discspans
 ASSERT LO(F_HW) = 0 AND LO(F_HW2) = 0   \ (page aligned: only the high bytes
                                         \ are patched)

.fds_none
 LDA #1
 STA R_NDT
 LSR A                  \ (NMOS: A = 0, and C set, as every exit of
 STA R_NDB              \ f_discspans leaves it: f_disc2)
 RTS

.f_discspans            \ rows of the disc (f_cx, f_cy, f_r) within the window
                        \ (every exit sets R_NDT and R_NDB)
 LDA f_cy               \ fz_p = top row = cy - r, fz_q = bottom row = cy + r
 SEC
 SBC f_r
 STA fz_p
 LDA f_cy+1
 SBC #0
 STA fz_p+1
 LDA f_cy
 CLC
 ADC f_r
 STA fz_q
 LDA f_cy+1
 ADC #0
 STA fz_q+1
 BMI fds_none           \ bottom above the screen
 BNE fdx1               \ bottom below row 255: clamp
 LDA fz_q
 CMP R_CB
 BCC fdx2
.fdx1
 LDA R_CB
 STA fz_q
.fdx2
 LDA fz_p+1             \ top
 BMI fdx3               \ above row 0: clamp
 BNE fds_none           \ below row 255
 LDA fz_p
 CMP R_CT
 BCS fdx4
.fdx3
 LDA R_CT
 STA fz_p
.fdx4
 LDA fz_q               \ empty if top > bottom
 CMP fz_p
 BCC fds_none
 STA R_NDB
 LDA fz_p
 STA R_NDT
 SEC                    \ d = top - cy (16-bit signed, |d| <= r)
 SBC f_cy
 STA fz_t
 LDA #0
 SBC f_cy+1
 STA fz_u
 LDA f_cxh              \ fast path if the whole disc is inside the window
 BEQ fds_z              \ horizontally: cx - r >= CL and cx + r <= CR
 LDA #&90               \ high byte of cx nonzero: fpr_b1 becomes BCC and
 BNE fds_pat            \ fpr_b2 BCS, both always taken (NMOS: for BRA)
.fds_z
 LDA f_cx
 SEC
 SBC f_r
 BCC fds_slow
 CMP R_CL
 BCC fds_slow
 LDA f_cx
 CLC
 ADC f_r
 BCS fds_slow
 SBC R_CR               \ (C = 0) borrow iff cx + r <= CR
 BCS fds_slow
 JMP fds_fast           \ (the fast path follows the slow one, out of
                        \ branch range)
.fds_slow               \ (the disc crosses the window's side, or the screen's)
 LDA #&B0               \ high byte of cx zero: fpr_b1 becomes BCS and fpr_b2
.fds_pat                \ BCC, never taken (no-ops: NMOS, for BIT #imm)
 STA fpr_b1
 EOR #&20               \ (BCC <-> BCS)
 STA fpr_b2
 CLC                    \ (C = 0 at fpr2, through the loop)
 LDY R_NDT
 LDX #&E8               \ X = |d| through the loop, stepped by fpr_id: INX
 LDA fz_u               \ (&E8) if d >= 0, else DEX (&CA) until d reaches 0
 BPL fpr4
 EOR fz_t               \ (d < 0: fz_u = &FF as |d| <= r <= 255, so A = NOT d)
 ADC #1                 \ (C = 0, and no carry: A <= 255)
 STA fz_t
 LDX #&CA
.fpr4
 STX fpr_id
 LDX fz_t               \ |d|
.fpr2                   \ (C = 0 here: NMOS, the CLC that was here is above)
.fpr_ld2
 LDA F_HW,X             \ patched: half-width
 STA fz_n
.fpr_b1
 BCS fpr10              \ patched: BCC (always: C = 0) if the high byte of cx
                        \ is nonzero (out of line), else BCS (never: a no-op)
.fpr_cx                 \ right = cx + n, clamped: < CL (or
 ADC #0                 \ patched: f_cx (the low byte of cx lives in this
                        \ operand); negative): empty; > CR (or > 255): CR
 BCS fpr5               \ high byte of cx + n = 1
.fpr11
 CMP R_CL
 BCC fpr8
 CMP R_CR
 BCC fpr6
.fpr5
 LDA R_CR
.fpr6
 STA R_NDISCR,Y
 LDA f_cx               \ left = cx - n: negative: CL; > 255 or > CR: empty;
 SEC                    \ < CL: CL
.fpr_b2
 BCC fpr13              \ patched: BCS (always: C = 1) if fpr_b1 is BCC,
 SBC fz_n               \ else BCC (never)
 BCC fpr3               \ high byte of cx - n = -1
.fpr14
 CMP R_CR
 BEQ fpr7
 BCS fpr8
 CMP R_CL
 BCS fpr7
.fpr3
 LDA R_CL
 BNE fpr7               \ (NMOS: R_CL = 2, F_FRAME)
.fpr10                  \ right, A = n, C = 0, high byte of cx nonzero (X =
 ADC f_cx               \ |d| kept; fz_t is free in the loop): A = low byte,
 STA fz_t               \ C = carry
 LDA f_cxh
 ADC #0                 \ high byte of cx + n
 BMI fpr8               \ minus: empty
 BNE fpr5               \ plus: CR
 LDA fz_t               \ zero
 BCS fpr11              \ (NMOS: C = 1, as high byte &FF + 1 = 0)
.fpr17
 LDA fz_t               \ (fpr13: high byte zero)
 BCS fpr14              \ (NMOS: C = 1, as high byte 1 - 1 = 0)
.fpr13                  \ left, A = cx's low byte, C = 1, high byte of cx
 SBC fz_n               \ nonzero: A = low byte, C = no borrow
 STA fz_t
 LDA f_cxh
 SBC #0                 \ high byte of cx - n
 BEQ fpr17
 BMI fpr3               \ (plus: empty)
.fpr8
 LDA #0                 \ empty row: R = 0, L = 255
 STA R_NDISCR,Y
 LDA #&FF
.fpr7
 STA R_NDISCL,Y
.fpr9
.fpr_id
 INX                    \ patched: DEX while d < 0; when |d| reaches 0
 BNE fpr16              \ step up from then on (fz_u is not kept)
 LDA #&E8
 STA fpr_id
.fpr16
 CPY fz_q               \ (= R_NDB: stored from fz_q at fdx4, unchanged here)
 INY
 BCC fpr2
 RTS

.fds_fast               \ here r <= 127 and |d| <= r, so d fits a signed byte
 LDA f_cx
 STA fsy_cr+1           \ patch cx and 2cx + 1 (mod 256) into both loops
 STA fdf_cr+1
 SEC
 ROL A
 STA fsy_cl+1
 STA fdf_cl+1
 LDA fz_q               \ A = B - T (B = R_NDB = fz_q, T = R_NDT = fz_p)
 SEC
 SBC fz_p               \ (C = 1 after: B >= T)
 LDY fz_t               \ Y = d = T - cy (|d| <= 127, so N = sign of d)
 BPL fdd                \ d >= 0: all rows at or below cy
 CLC
 ADC fz_t               \ A = b = B - cy, C = 1 iff b >= 0
 BCS fdsym              \ b >= 0: cy is in T..B
                        \ b < 0 (C = 0): rows T..B are cy - k for k = -b..a
 EOR #&FF               \ (a = -d), walked up from B
 TAY
 INY                    \ Y = -b
 LDX fz_q               \ X = B
 LDA #2
 SBC fz_t               \ (C = 0) A = a + 1 (C = 0 after)
 STA fdf_cp+1
 LDA #&CA               \ DEX
 BNE fdxs
.fdd                    \ d >= 0 (A = B - T, C = 1, Y = d): rows T..B are cy + k
 ADC fz_t               \ for k = d..b; A = B - T + d + 1 = b + 1 <= 128 (C = 0)
 STA fdf_cp+1
 LDX fz_p               \ X = T
 LDA #&E8               \ INX
.fdxs
 STA fdf_st
.fdf1                   \ X = row, Y = k = |row - cy|, C = 0 here
.fpr_ld
 LDA F_HW,Y             \ patched: half-width table
.fdf_cr
 ADC #0                 \ patched: cx (A = cx + n <= cx + r <= 255, so C = 0)
 STA R_NDISCR,X
 EOR #&FF
.fdf_cl
 ADC #0                 \ patched: 2cx + 1 (A = 2cx + 1 + ~(cx + n) = cx - n)
 STA R_NDISCL,X
.fdf_st
 INX                    \ patched: INX (rows below cy) or DEX (rows above cy)
 INY
.fdf_cp
 CPY #0                 \ patched: last k, plus 1 (C = 0 until then)
 BNE fdf1
 RTS

.fdsym                  \ (A = b, C = 1; a = cy - T = -d > 0)
 TAY                    \ Y = b
 CLC
 ADC fz_t               \ A = b - a, C = 1 iff b >= a
 BEQ fdse
 BCC fdsu
 INY                    \ b > a: rows cy - k and cy + k together for k = 0..a,
 STY fdf_cp+1           \ then rows cy + k for k = a + 1..b
 LDA #&E8               \ INX
 STA fdf_st
 LDA #1
 SBC fz_t               \ (C = 1) A = a + 1 (C = 0 after)
 STA fsy_cp+1
 ADC f_cy               \ A = cy + a + 1 <= B + 1 (C = 0 after)
 STA fsx_x+1
 LDA #&A2               \ LDX #
 BNE fds_c
.fdsu                   \ b < a (C = 0): rows cy - k and cy + k together for
 INY                    \ k = 0..b, then rows cy - k for k = b + 1..a
 STY fsy_cp+1           \ (C = 0 still)
 LDA #2
 SBC fz_t               \ (C = 0) A = a + 1
 STA fdf_cp+1
 LDA #&CA               \ DEX
 STA fdf_st
 LDA #&A9               \ LDA # (a no-op here: NMOS, for BIT #; X is
 BNE fds_c              \ already row cy - b - 1)
.fdse                   \ b = a (C = 1, Y = a): rows cy - k and cy + k for k = 0..a
 INY
 STY fsy_cp+1           \ a + 1
 LDA #&60               \ RTS
.fds_c
 STA fsx_x              \ what follows the symmetric loop
 LDA fpr_ld+2           \ the symmetric loop reads n(k) at table + k (page
 STA fsy_ld+2           \ aligned: no page crossing)
 LDA f_cy               \ X = row cy - k, Y = k, from k = 0; rows cy + k are
 TAX                    \ written at (table + cy) + k
 CLC
 ADC #LO(R_NDISCR)      \ (cy <= R_CB = 191: no carry, see the ASSERT)
 STA fsy_sr+1
 TXA
 ADC #LO(R_NDISCL)
 STA fsy_sl+1
 LDA #HI(R_NDISCL)
 ADC #0                 \ (C = 0 after)
 STA fsy_sl+2
 LDY #0
.fsyl                   \ C = 0 here
.fsy_ld
 LDA F_HW,Y             \ patched: half-width table (high byte)
.fsy_cr
 ADC #0                 \ patched: cx
 STA R_NDISCR,X
.fsy_sr
 STA R_NDISCR,Y         \ patched: R_NDISCR + cy (low byte)
 EOR #&FF
.fsy_cl
 ADC #0                 \ patched: 2cx + 1
 STA R_NDISCL,X
.fsy_sl
 STA R_NDISCL,Y         \ patched: R_NDISCL + cy
 DEX
 INY
.fsy_cp
 CPY #0                 \ patched: last k, plus 1 (C = 0 until then)
 BNE fsyl
.fsx_x
 LDX #0                 \ patched: LDX #first tail row, LDA # (no-op) or RTS
 CLC                    \ (Y = k of the first tail row already)
 JMP fdf1
 ASSERT LO(R_NDISCR) + 191 < 256

f_cx = fpr_cx + 1       \ (the operand of ADC # in the slow disc loop)
.f_cxh EQUB 0           \ high byte of cx
.f_cy  EQUW 0
.f_r   EQUB 0
.f_hwr EQUB 0           \ the radius F_HW was built for (0 = none)
.f_hw2r EQUB 0          \ the radius F_HW2 was built for

\ f_hwbuild: table[d] = floor(sqrt(r * r - d * d)) for d = 0 to r (r = f_r,
\ the table's page patched into fhw_st), by walking x down from r while
\ x * x + d * d > r * r (e = r * r - d * d - x * x, 16-bit signed)

.f_hwbuild
 LDX f_r                \ x = r
 LDA #0
 STA fz_p               \ e = 0 (d = 0, x = r)
 STA fz_p+1
 LDY #0                 \ d
.fhw1
 TXA
.fhw_st
 STA F_HW,Y             \ patched
 CPY f_r
 BEQ fhw9
 TYA                    \ e -= 2d + 1 ; d++
 ASL A
 STA fz_t
 LDA #0
 ROL A
 STA fz_u
 LDA fz_p
 CLC                    \ (C = 0: SBC takes the + 1 too)
 SBC fz_t
 STA fz_p
 LDA fz_p+1
 SBC fz_u
 STA fz_p+1
 INY
.fhw2
 LDA fz_p+1             \ while e < 0: e += 2x - 1 ; x--
 BPL fhw1
 TXA
 ASL A
 STA fz_t
 LDA #0
 ROL A
 STA fz_u
 LDA fz_t
 SEC
 SBC #1
 STA fz_t
 BCS fhw3
 DEC fz_u
.fhw3
 LDA fz_p
 CLC
 ADC fz_t
 STA fz_p
 LDA fz_p+1
 ADC fz_u
 STA fz_p+1
 DEX
 JMP fhw2
.fhw9
 RTS

\ f_nobounds: the layer has no boundaries (a plain disc)

.f_nobounds
 LSR R_NDF              \ (NMOS: R_NDF is 0 or 1)
 RTS

\ f_bounds: the planet's surface as boundaries, R_NDN and R_NDX0-3, for rows
\ R_NDT..R_NDB (which f_plrows has just set), between colour A, the disc's
\ (the beach ball's sea), and colour B (FC_PLLE, FC_PLLO: DP_BEGIN's): the
\ circles on its sphere that PF_HOOK made this iteration, if it made any
\ (PF_CLS bit 7: the beach ball, or craters), as the circle engine's rows
\ (PC_ROWS, gfx-merid.asm)

.f_bounds
 JSR f_nobounds
 LDA R_NDT
 CMP R_NDB
 BEQ P%+4
 BCS fnb9
 BIT PF_CLS
 BPL fnb9
 INC R_NDF
 JMP PC_ROWS
.fnb9
 RTS

\ The planet's colours, every style's the beach ball's (pairs of bytes, even
\ rows and odd rows): colour A, the disc, its sea (FC_PLANE, FC_PLANO), and
\ colour B, its detail (the beach ball's land, the craters), green

FC_PLLE = &5F : FC_PLLO = &AF

\ f_ddraw: (F_FRAME, after the wait, in place of the repair) the repair, the
\ disc layer and the second disc on this buffer

.f_ddraw
 LDA R_NDT              \ the layer's new rows, within the window (none:
 CMP R_CT               \ 255, 0), as R_DISCROWS' R_PRNT, R_PRNB
 BCS fdw1
 LDA R_CT
.fdw1
 STA f_nt
 LDA R_NDB
 CMP R_CB
 BCC fdw2
 LDA R_CB
.fdw2
 STA f_nb
 CMP f_nt
 BCS fdw3
 LDA #0
 STA f_nb
 LDA #&FF
 STA f_nt
.fdw3
 LDX F_BACK             \ the band: the layer's rows, old and new, on this
 LDA f_dlt,X            \ buffer (which bank 5 leaves to the painter)
 CMP f_nt
 BCC fdw4
 LDA f_nt
.fdw4
 STA f_dy
 LDA f_dlb,X
 CMP f_nb
 BCS fdw5
 LDA f_nb
.fdw5
 STA f_dhi
 LDA f_nt               \ (this frame's, for the next on this buffer)
 STA f_dlt,X
 LDA f_nb
 STA f_dlb,X
 LDA f_dy               \ the repair (T_REPAIR: rows A .. Y are the band)
 LDY f_dhi
 JSR T_REPAIR
 LDX F_BACK             \ the second disc: rows on this buffer, or to come?
 LDA f_sec
 BNE fdw6
 LDA R_S2B,X
 CMP R_S2T,X
 BCS fdw6
 LDA f_dhi              \ nor the layer's: nothing more
 CMP f_dy
 BCS fdw6
 RTS
.fdw6
 LDA f_bmode,X          \ DP_BEGIN's flags: boundaries kept on this buffer's
 BNE fdw7               \ rows (the layer's this frame, or last time:
 LDA R_NDF              \ PB_BON, as the Master port's R_PRBMODE), and none
 BEQ fdw8               \ there before (PB_BCLR)
 LDA #PB_BCLR + PB_BON
 BNE fdw9               \ (always)
.fdw7
 LDA #PB_BON
.fdw8
.fdw9
 STA f_dfl
 LDA R_NDF
 STA f_bmode,X
 LDA f_lay              \ another colour on this buffer: the old disc
 CMP F_DCOL,X           \ folded into the dirty extents (PB_FOLD, the Master
 BEQ fdw10              \ port's f_discdirty)
 STA F_DCOL,X
 LDA f_dfl
 ORA #PB_FOLD
 STA f_dfl
.fdw10
 LDA f_dpr              \ blanked since its last disc: the painter forgets
 AND f_bbit,X           \ what it kept of it (PB_RESET)
 BEQ fdw11
 EOR f_dpr
 STA f_dpr
 LDA f_dfl
 ORA #PB_RESET
 STA f_dfl
.fdw11
 LDA #FC_PLLE           \ colour B (DP_BEGIN takes it in RZ_T0, RZ_T1)
 STA RZ_T0
 LDA #FC_PLLO
 STA RZ_T1
 LDA #0                 \ nothing queued or put yet
 STA DB_QN
 STA f_dput
 TXA
 LDX f_dfl
 JSR f_dpbegin
 LDA f_dhi              \ the layer's rows, if any
 CMP f_dy
 BCC fdw20
 LDA #0                 \ the layer's colour: none, the sun or the planet
 TAY                    \ (colour A: the beach ball's sea)
 LDX f_lay
 BEQ fdw13
 LDA #FC_PLANE
 LDY #FC_PLANO
 DEX
 DEX
 BEQ fdw13
 LDA #FC_SUNE
 LDY #FC_SUNO
.fdw13
 STA R_DCE
 STY R_DCO
 LDX #16                \ the batches: 16 rows, or 8 with boundaries (their
 LDA f_dfl              \ counts and colours and their x in the slots too)
 AND #PB_BON
 BEQ fdw14
 LDA #&80               \ (bit 7: the slots', bit 6: this frame's)
 LDY R_NDF
 BEQ P%+4
 LDA #&C0
 LDX #8
.fdw14
 STA f_d2c
 STX f_dN
 LDX #0                 \ (the dirty extents in the slots: the layer's)
 JSR f_dbat
.fdw20
 JSR f_disc2            \ the second disc's rows
 LDA #0                 \ then what the last batch wrote put, and its spans
 LDX f_dput             \ drawn
 JMP T_GETW

.f_bbit EQUB 1, 2       \ (f_dpr's bit for each buffer)

\ f_dbat: rows f_dy .. f_dhi (f_dy <= f_dhi) through the painter, f_dN at a
\ time (X = 0: the layer's, DP_ROWS, with their dirty extents; X = &80: the
\ second disc's, DP_DISC2, with what was written on them, and A = its
\ colour change, &FF or 0), each batch's slots filled from R_NDISCL/R in
\ R_NDT .. R_NDB (empty outside), with f_d2c bit 7 R_NDN and R_NDX0-3 too
\ (R_NDN zero with bit 6 clear); with each batch bank 5 puts what the last
\ one wrote and draws what it queued (T_GETW)

.f_dbat
 STX f_dmd
 STA f_dc2
.fdb1
 LDA f_dhi              \ n = min(f_dhi - f_dy + 1, f_dN)
 SEC
 SBC f_dy               \ (f_dy <= f_dhi, so the carry is set)
 ADC #0                 \ + 1 by the carry
 CMP f_dN
 BCC fdb2
 LDA f_dN
.fdb2
 STA f_dn
 ORA f_dmd              \ (bit 7: the written extents, not the dirty ones)
 LDY f_dy
 LDX f_dput
 JSR T_GETW
 LDX #0                 \ the slots
 LDY f_dy
.fdb3
 CPY R_NDT
 BCC fdb6
 CPY R_NDB
 BEQ fdb4
 BCS fdb6
.fdb4
 LDA R_NDISCL,Y
 STA DB_NL,X
 LDA R_NDISCR,Y
 STA DB_NR,X
 BIT f_d2c
 BPL fdb8
 BVC fdb7
 LDA R_NDN,Y
 STA DB_NN,X
 LDA R_NDX0,Y
 STA DB_X0,X
 LDA R_NDX1,Y
 STA DB_X1,X
 LDA R_NDX2,Y
 STA DB_X2,X
 LDA R_NDX3,Y
 STA DB_X3,X
 JMP fdb8
.fdb6
 LDA #&FF               \ an empty span
 STA DB_NL,X
 LDA #0
 STA DB_NR,X
 BIT f_d2c
 BPL fdb8
.fdb7
 LDA #0                 \ no boundaries
 STA DB_NN,X
.fdb8
 INY
 INX
 CPX f_dn
 BNE fdb3
 LDY f_dy               \ the painter
 LDX f_dn
 BIT f_dmd
 BMI fdb9
 JSR f_dprows
 JMP fdb10
.fdb9
 LDA f_dc2
 JSR f_dpdisc2
.fdb10
 LDA f_dy               \ the next batch
 STA DB_PY              \ (whose writes the next T_GETW puts)
 CLC
 ADC f_dn
 STA f_dy
 LDA f_dn
 STA f_dput
 LDA f_dhi
 CMP f_dy
 BCC fdb11
 JMP fdb1
.fdb11
 RTS

.f_dpbegin              \ the painter's entries, in the flight code's bank 7
 JSR farC               \ (gfx-raster_disc.asm, gfx-raster_disc2.asm)
 EQUW DP_BEGIN
.f_dprows
 JSR farC
 EQUW DP_ROWS
.f_dpdisc2
 JSR farC
 EQUW DP_DISC2

\ f_disc2: the second disc (both the sun and the planet on screen: more
\ often since the sun near the planet is drawn too, S_SUN). It is the
\ smaller disc, and the sun and the planet are the same size (PLANET's radius
\ 24576 / z for both), so it is the further: R_DISC2 (DP_DISC2, the painter)
\ draws what the layer's span leaves of each of its rows, incrementally. With
\ no second disc it is called only to erase what this buffer still holds of
\ one (R_S2T .. R_S2B: its rows), with empty spans. A planet that is the
\ second disc is a plain disc

.f_disc2
 LDA f_sec
 BEQ fd29
 CMP #1
 BEQ fd21
 LDA #FC_PLANE          \ (the planet's colour A: the beach ball's sea)
 STA R_COLE
 LDA #FC_PLANO
 STA R_COLO
 JSR f_plrows
 JMP fd22
.fd21
 LDA #FC_SUNE
 STA R_COLE
 LDA #FC_SUNO
 STA R_COLO
 JSR f_sunrows
.fd22
 LDX F_BACK             \ its colour changed (or none before): every row's
 LDA R_COLE             \ old span black, then its new one whole (R_DISC2's
 CMP R_S2C,X            \ d_fl)
 BEQ fd23
 STA R_S2C,X
 LDA #&FF
 BNE fd24               \ (always)
.fd23
 LDA #0
.fd24
 STA f_dc2
 LDA R_NDB              \ its rows (none: 255, 0)
 CMP R_NDT
 BCS fd25
.fd29
 LDA #0
 STA f_dc2
 STA R_NDB
 LDA #&FF
 STA R_NDT
.fd25
 LDX F_BACK             \ the rows of the batches: old and new (lo .. hi)
 LDA R_S2T,X
 CMP R_NDT
 BCC P%+5
 LDA R_NDT
 STA f_dy
 LDA R_S2B,X
 CMP R_NDB
 BCS P%+5
 LDA R_NDB
 STA f_dhi
 LDA R_NDT              \ (this frame's, for the next on this buffer)
 STA R_S2T,X
 LDA R_NDB
 STA R_S2B,X
 LDA f_dhi
 CMP f_dy
 BCC fd28               \ none, old or new
 LDA #0                 \ one colour, 16 rows a batch, the written extents
 STA f_d2c
 LDA #16
 STA f_dN
 LDA f_dc2
 LDX #&80
 JMP f_dbat
.fd28
 RTS

\ f_dforget: buffer X (blanked) holds no disc: the layer's rows, its colour,
\ its boundaries and the second disc forgotten here, and in the painter at
\ its next frame on it (f_dpr)

.f_dforget
 LDA #&FF
 STA f_dlt,X
 STA R_S2T,X
 LDA #0
 STA f_dlb,X
 STA R_S2B,X
 STA R_S2C,X
 STA F_DCOL,X
 STA f_bmode,X
 LDA f_dpr
 ORA f_bbit,X
 STA f_dpr
 RTS

.f_lay   EQUB 0         \ the disc layer: 0 none, 1 the sun, 2 the planet
.f_sec   EQUB 0         \ the second disc
.f_nt    EQUB 0         \ the layer's rows this frame (none: 255, 0)
.f_nb    EQUB 0
.f_dy    EQUB 0         \ f_dbat: the next batch's first row, the last row,
.f_dhi   EQUB 0         \ the rows a batch, this batch's
.f_dN    EQUB 0
.f_dn    EQUB 0
.f_dput  EQUB 0         \ the last batch's rows (its first: DB_PY)
.f_dmd   EQUB 0         \ 0 the layer, &80 the second disc
.f_dc2   EQUB 0         \ the second disc's colour change (&FF)
.f_d2c   EQUB 0         \ bit 7: boundaries in the slots; bit 6: this frame's
.f_dfl   EQUB 0         \ DP_BEGIN's flags
.f_dpr   EQUB 3         \ bit b: buffer b blanked since the painter last drew it
.f_dlt   EQUB &FF, &FF  \ per buffer: the layer's rows on it (none: 255, 0)
.f_dlb   EQUB 0, 0
.F_DCOL  EQUB 0, 0      \ per buffer: the layer on it (f_lay)
.f_bmode EQUB 0, 0      \ per buffer: its rows may hold boundaries
.R_S2T   EQUB &FF, &FF  \ per buffer: the second disc's rows on it and its
.R_S2B   EQUB 0, 0      \ colour (0: none)
.R_S2C   EQUB 0, 0
.R_NDT   EQUB 1         \ the layer's or the second disc's rows this frame
.R_NDB   EQUB 0
.R_NDF   EQUB 0         \ 1: the layer has boundaries (R_NDN, R_NDX0-3)

PB_BON   = 1            \ DP_BEGIN's flags (gfx-raster_disc.asm)
PB_FOLD  = 2
PB_BCLR  = &40
PB_RESET = &80


\ ------------------------------------------------------------------------------
\ Lines, ships, dots, lasers, stars
\ ------------------------------------------------------------------------------

.f_setcol               \ A = fixed colour index -> R_COLE/R_COLO
 TAX
 LDA F_CPE,X
 STA R_COLE
 LDA F_CPO,X
 STA R_COLO
 RTS

.f_line8                \ line from (fz_t, fz_u) to (X, Y), 8-bit coordinates
 STX R_X1
 STY R_Y1
 LDA fz_t
 STA R_X0
 LDA fz_u
 STA R_Y0
 LDA #0
 STA R_X0+1
 STA R_Y0+1
 STA R_X1+1
 STA R_Y1+1
 JMP T_LINE

.f_lines                \ the enemy beams
 LDA F_NLINE
 BEQ fln9
 LDA #FC_ELASER
 JSR f_setcol
 LDA #0
 STA fz_i
.fln1
 LDX fz_i
 LDA F_LX0,X
 STA fz_t
 LDA F_LY0,X
 STA fz_u
 LDA F_LY1,X
 TAY
 LDA F_LX1,X
 TAX
 JSR f_line8
 INC fz_i
 LDX fz_i
 CPX F_NLINE
 BCC fln1
.fln9
 RTS

\ f_sort: insertion-sort the ships far to near (F_ORD), before the frame's
\ wait for the flip; then project the first to be drawn (f_proj0), which
\ needs no screen memory either. f_ships draws each one (f_ship) after it.

.f_sort
 LDX #0                 \ F_ORD = 0, 1, 2, ... sorted by z descending
.fss1
 TXA
 STA F_ORD,X
 INX
 CPX F_NSHIP
 BCC fss1
 LDX #1
.fss2
 CPX F_NSHIP
 BCS fss6
 LDA F_ORD,X            \ insert element X
 STA fz_t
 TXA
 TAY
.fss3
 DEY
 BMI fss5
 LDA F_ORD,Y            \ compare z(fz_t) > z(F_ORD,Y)? then shift
 STA fz_u
 STX fz_n
 LDX fz_t
 LDA F_SZL,X
 STA fz_i
 LDA F_SZH,X
 LDX fz_u
 CMP F_SZH,X
 BCC fss4               \ new is nearer: stop
 BNE fss7               \ new is further: shift
 LDA fz_i
 CMP F_SZL,X
 BCC fss4
 BEQ fss4
.fss7
 LDX fz_n
 LDA fz_u
 STA F_ORD+1,Y
 JMP fss3
.fss4
 LDX fz_n
.fss5
 INY                    \ the place after Y (Y = -1, &FF, when it goes first:
 LDA fz_t               \ F_ORD+1,Y is then a page on, not F_ORD)
 STA F_ORD,Y
 INX
 BNE fss2
.fss6
 JMP f_proj0

.f_ships
 LDA #0                 \ (Port: the counter not in FZ, which each ship's
 STA f_ii               \ projection, game code, overwrites)
.fss8
 LDX f_ii
 CPX F_NSHIP
 BCS fss9
 LDA F_ORD,X
 JSR f_ship
 INC f_ii
 BNE fss8
.fss9
 RTS

.f_ii  EQUB 0           \ (f_ships's counter)

\ f_sdot: ship X's distant dot, where SHPPT would draw it (128 + 256 * x / z,
\ 96 - 256 * y / z: on the screen if within 0-255 and 0-189), in its dot
\ colour, drawn under its faces. LL9 fills a ship from the dot's range (its
\ blueprint's byte #13) in, and the faces of one so far away project to
\ slivers less than a pixel wide, which the rasteriser does not draw: so from
\ z_hi = FC_DOTZ[type] out (gfx-faces.asm: nearer, the faces cover the dot)
\ the dot is drawn too; and a ship f_ship does not fill (FC_MINVIS) is drawn
\ as the dot alone. LL10 has left |x| and |y| less than z. The rasteriser's
\ scratch &20-&25 is free here

fsd_zl = &20 : fsd_zh = &21 : fsd_rl = &22 : fsd_q = &24 : fsd_x = &25

.f_sdot
 LDA F_SZL,X            \ (fsd_zh fsd_zl) = z
 STA fsd_zl
 LDA F_SZH,X
 STA fsd_zh
 LDA F_RP+0*MAXSH,X     \ x
 LDY F_RP+1*MAXSH,X
 JSR fsd_div
 LDY F_RP+2*MAXSH,X     \ x_sign
 BMI fsq1
 EOR #&80               \ 128 + q, q < 128
 BMI fsq2               \ (on the screen: N is set; else q >= 128, no dot)
 RTS
.fsq1
 EOR #&FF               \ 128 - q, q <= 128 (C set from fsd_div)
 ADC #128
 BCC fsq9
.fsq2
 STA fsd_x
 LDA F_RP+3*MAXSH,X     \ y
 LDY F_RP+4*MAXSH,X
 JSR fsd_div
 LDY F_RP+5*MAXSH,X     \ y_sign
 BMI fsq3
 EOR #&FF               \ 96 - q, q <= 96 (C set from fsd_div)
 ADC #96
 BCS fsq4               \ (no borrow: on the screen; else no dot)
 RTS
.fsq3
 ADC #95                \ 96 + q < 190 (C set from fsd_div)
 BCS fsq9
 CMP #2*96-2
 BCS fsq9
.fsq4
 STA fsd_q
 LDY F_STYP,X
 LDA FC_DOTE,Y
 STA R_COLE
 LDA FC_DOTO,Y
 STA R_COLO
 LDX fsd_x
 LDY fsd_q
 LDA #3
 JMP T_DOT
.fsq9
 RTS

\ fsd_div: A = 256 * (Y A) / z (fsd_zh fsd_zl), rounded down, for (Y A) < z; X kept.
\ The remainder's high byte is in A; fsd_q's first 1 marks the eighth step

.fsd_div
 STA fsd_rl
 TYA
 LDY #1
 STY fsd_q
.fqv1
 ASL fsd_rl
 ROL A
 BCS fqv2               \ (a 17-bit remainder: more than z)
 CMP fsd_zh
 BCC fqv3
 BNE fqv2
 LDY fsd_rl              \ (high bytes equal: the low bytes decide)
 CPY fsd_zl
 BCC fqv3
.fqv2
 TAY                    \ remainder - z (C set)
 LDA fsd_rl
 SBC fsd_zl
 STA fsd_rl
 TYA
 SBC fsd_zh
 SEC
.fqv3
 ROL fsd_q
 BCC fqv1
 LDA fsd_q
 RTS

.f_si   EQUB 0          \ ship index being drawn
.f_nf   EQUB 0
.f_f    EQUB 0          \ face number
.f_x4   EQUB 0
.f_cnt  EQUB 0          \ item counter (details, fins)
.f_k    EQUB 0          \ fin pass: number of its two faces visible

\ f_ship: draw one ship. Every face is flat-shaded (FC_FACETAB: n + 16 * hue
\ ramp, n XX3 offsets; the record's levels in F_SR hold the face's level,
\ gfx-light.asm, and f_col its ramp entry). The visible faces are drawn, then
\ the surface details over them and the fins (see gfx-faces.asm for the
\ order); not a fin with neither of its faces visible, behind the body, as LL9
\ has not projected its vertex on the body edge (the missile's list only those
\ two faces), and XX3 holds whatever was there before. Port (Model B): the
\ ship is projected first (f_proj), as part 6's zero page (XX2) is this
\ layer's FZ, which is set up after it.

.f_ship                 \ A = ship index
 TAX
 STX f_si
 LDY F_STYP,X
 LDA F_SX4,X            \ ships whose polygon vertices may be stale: the
 STA f_x4               \ dot alone
 CMP FC_MINVIS,Y
 BEQ P%+7
 BCC P%+5
 JMP f_sdot
 LDA F_SNF,X
 STA f_nf
 JSR f_proj             \ the vertices on the screen, into XX3
 LDX f_si
 LDA F_STYP,X
 ASL A
 TAY
 LDA FC_FACETAB,Y
 STA fz_ft
 LDA FC_FACETAB+1,Y
 STA fz_ft+1
 LDA FC_DETTAB,Y        \ fins, then details
 STA fz_dt
 LDA FC_DETTAB+1,Y
 STA fz_dt+1
 LDA F_SPL,X            \ the faces' levels
 STA fz_dl
 LDA F_SPH,X
 STA fz_dl+1

 JSR f_behind           \ hidden behind the planet?
 BCC P%+3
 RTS
.fsh_nf0                \ (past f_behind)

 LDX f_si               \ a small ship: its distant dot under its faces
 LDY F_STYP,X
 LDA F_SZH,X
 CMP FC_DOTZ,Y
 BCC P%+5
 JSR f_sdot

 LDA #0
 STA f_f
 BEQ fsh_face
.fsh_skip               \ hidden face: just step over its entry
 LDY #0
 LDA (fz_ft),Y
 AND #15
 STA fz_n
 JMP fsh_next
.fsh_face
 LDY f_f
 CPY f_nf
 BCC P%+5
 JMP fsh_done
 LDA (fz_dl),Y          \ visibility
 BEQ fsh_skip
 STA fz_t
 LDY #0
 LDA (fz_ft),Y          \ n + 16 * ramp
 AND #15
 STA fz_n
 CMP #3
 BCC fsh_next
 STA R_PN
 LDA fz_t               \ the face's level
 AND #31
 TAX
 LDA (fz_ft),Y          \ its hue ramp
 LSR A
 LSR A
 LSR A
 LSR A
 JSR f_col              \ lit: R_COLE, R_COLO, R_COL2, R_COL3
 CLC                    \ the face's vertex offsets at fz_ft + 1
 LDA fz_ft
 ADC #1
 STA fsh_o+1
 LDA fz_ft+1
 ADC #0
 STA fsh_o+2
 LDX #0                 \ gather the vertices
.fsh_v
.fsh_o
 LDY &FFFF,X            \ XX3 offset (patched)
 LDA XX3,Y
 STA R_PXL,X
 LDA XX3+1,Y
 STA R_PXH,X
 LDA XX3+2,Y
 STA R_PYL,X
 LDA XX3+3,Y
 STA R_PYH,X
 INX
 CPX fz_n
 BCC fsh_v
 BIT fz_t               \ far faces (XX2 = 255, bit 6 of the copy: Elite skipped
 BVC fsh_draw           \ the normal test) are culled by their winding on
                        \ screen, in the ship's handedness (bit 5)
 JSR f_winding
 BCC fsh_next
.fsh_draw
 JSR T_POLY
.fsh_next
 LDA fz_n               \ next face list entry: n + 1 bytes on
 SEC
 ADC fz_ft
 STA fz_ft
 BCC P%+4
 INC fz_ft+1
 INC f_f
 JMP fsh_face

.fsh_done               \ details: skip the fins (7 bytes each) to the count
 LDY #0
 LDA (fz_dt),Y
 STA f_cnt
 ASL A
 ASL A
 ASL A
 SEC
 SBC f_cnt              \ 7 * count (C = 1: no borrow)
 ADC fz_dt              \ + 1 via the C = 1 left by the SBC
 STA fz_q
 LDA fz_dt+1
 ADC #0
 STA fz_q+1
 LDA (fz_q),Y
 BEQ fdt8
 STA f_cnt
 INC fz_q
 BNE fdt1
 INC fz_q+1
.fdt1
 JSR f_item
 DEC f_cnt
 BNE fdt1
.fdt8
 LDY #0                 \ the other fins: one face visible, then both (the
 LDA (fz_dt),Y          \ fin nearest the viewer)
 BEQ fdt9
 LDA #1
 JSR f_fins
 LDA #2
 JMP f_fins
.fdt9
 RTS

\ f_item: draw the detail at (fz_q) if it is within its visibility distance
\ and face1 or face2 is visible: n = 2 a line, else a polygon (culled by its
\ winding if XX2 = 255). Then fz_q -> the next item.

.f_item
 LDY #0
 LDA (fz_q),Y           \ visibility distance
 CMP f_x4
 BCC fit8
 INY
 LDA (fz_q),Y           \ face1 + 16 * face2
 AND #15
 TAY
 LDA (fz_dl),Y
 BNE fit1
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 BEQ fit8
.fit1
 STA fz_t
 JSR f_itemv            \ colour and vertices
 LDA fz_n
 CMP #3
 BCC fit3
 STA R_PN
 BIT fz_t               \ (XX2 = 255: cull by winding)
 BVC fit2
 JSR f_winding
 BCC fit8
.fit2
 JSR f_poly2            \ (T_POLY, and the docking slot's outline)
 JMP fit8
.fit3
 LDA R_PXL              \ a line
 STA R_X0
 LDA R_PXH
 STA R_X0+1
 LDA R_PYL
 STA R_Y0
 LDA R_PYH
 STA R_Y0+1
 LDA R_PXL+1
 STA R_X1
 LDA R_PXH+1
 STA R_X1+1
 LDA R_PYL+1
 STA R_Y1
 LDA R_PYH+1
 STA R_Y1+1
 JSR T_LINE
.fit8
 LDY #3                 \ next item: 4 + n bytes on
 LDA (fz_q),Y
 CLC
 ADC #4
 ADC fz_q
 STA fz_q
 BCC P%+4
 INC fz_q+1
 RTS

\ f_itemv: the item at (fz_q): its colour (lit at the brighter of its two
\ faces' levels, or unlit), fz_n = n, R_PX/R_PY[0..n-1]

.f_itemv
 LDY #1                 \ face1 + 16 * face2: the brighter level (a hidden
 LDA (fz_q),Y           \ face's is 0)
 AND #15
 TAY
 LDA (fz_dl),Y
 AND #31
 STA fz_u
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 AND #31
 CMP fz_u
 BCS P%+4
 LDA fz_u
 TAX
 LDY #2
 LDA (fz_q),Y           \ colour byte: a hue ramp, or &80 + an unlit colour
 JSR f_col              \ R_COLE, R_COLO, R_COL2, R_COL3
 LDY #3
 LDA (fz_q),Y
 STA fz_n
 INY
 LDX #0
.fiv1
 STY fz_u
 LDA (fz_q),Y           \ XX3 offset
 TAY
 LDA XX3,Y
 STA R_PXL,X
 LDA XX3+1,Y
 STA R_PXH,X
 LDA XX3+2,Y
 STA R_PYL,X
 LDA XX3+3,Y
 STA R_PYH,X
 LDY fz_u
 INY
 INX
 CPX fz_n
 BCC fiv1
 RTS

\ f_fins: A = k (1 or 2): draw the fins (two-sided triangles standing on the
\ body edge between face1 and face2) with exactly k of those two faces
\ visible. A fin with one or both visible is in front of the body, and only
\ the fin on the corner facing the viewer (both visible) can hide another fin.
\ (One with neither visible is behind the body and is not drawn: f_ship.)

.f_fins
 STA f_k
 LDY #0
 LDA (fz_dt),Y
 STA f_cnt
 LDA fz_dt
 CLC
 ADC #1
 STA fz_q
 LDA fz_dt+1
 ADC #0
 STA fz_q+1
.ffi1
 LDY #0
 LDA (fz_q),Y           \ visibility distance
 CMP f_x4
 BCC ffi8
 LDX #0                 \ X = number of the two faces visible
 INY
 LDA (fz_q),Y
 AND #15
 TAY
 LDA (fz_dl),Y
 BEQ P%+3
 INX
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 BEQ P%+3
 INX
 CPX f_k
 BNE ffi8
 JSR f_itemv
 LDA #3
 STA R_PN
 JSR T_POLY
.ffi8
 LDA fz_q               \ next fin: 7 bytes on
 CLC
 ADC #7
 STA fz_q
 BCC P%+4
 INC fz_q+1
 DEC f_cnt
 BNE ffi1
 RTS

\ f_col: A = a face's or item's colour byte, X = the level (0..31): the
\ colour R_COLE, R_COLO, R_COL2, R_COL3 (rows y AND 3 = 0..3). A = 0..8: entry
\ X of that hue ramp (gfx-light6.asm), a 4x4 dither packed as w = a + 32 b +
\ 1024 c, whose rows are H[a] EOR H[c] EOR HL[b] (H = HL AND &F0); A = &80 +
\ k: the unlit colour k (black, cyan, magenta, yellow).

.fc_fix
 AND #3
 TAY
 LDA LT_FIX,Y
 STA R_COLE
 STA R_COLO
 STA R_COL2
 STA R_COL3
 RTS
.f_col
 TAY
 BMI fc_fix
 LDA LT_RL,Y
 STA fcl+1
 CLC
 ADC #32
 STA fch+1
 LDA LT_RH,Y
 STA fcl+2
 ADC #0
 STA fch+2
.fch
 LDA &FFFF,X            \ (patched) w's high byte: c = hi >> 2
 STA fc_hi
 LSR A
 LSR A
 TAY
.fcl
 LDA &FFFF,X            \ (patched) w's low byte: a = lo AND 31
 STA fc_lo
 AND #31
 TAX
 FOR r, 0, 3            \ H[a] EOR H[c]
  LDA LT_HL0+17*r,X
  EOR LT_HL0+17*r,Y
  AND #&F0
  STA fc_row+r
 NEXT
 LDA fc_hi              \ b = (hi AND 3) * 8 + lo DIV 32
 AND #3
 ASL fc_lo
 ROL A
 ASL fc_lo
 ROL A
 ASL fc_lo
 ROL A
 TAY
 LDA LT_HL0,Y           \ EOR HL[b]
 EOR fc_row
 STA R_COLE
 LDA LT_HL0+17,Y
 EOR fc_row+1
 STA R_COLO
 LDA LT_HL0+34,Y
 EOR fc_row+2
 STA R_COL2
 LDA LT_HL0+51,Y
 EOR fc_row+3
 STA R_COL3
 RTS
ASSERT LT_HL1 = LT_HL0 + 17 AND LT_HL2 = LT_HL0 + 34 AND LT_HL3 = LT_HL0 + 51

.fc_lo  EQUB 0
.fc_hi  EQUB 0
.fc_row SKIP 4

\ f_dots: the distant ships' dots and the explosion clouds, in the order
\ recorded. A cloud is drawn by PTCLS itself (f_gcloud: bank 4, through the
\ far call farH, entering at PTCLR, the game's S% + 19), from its ship's line
\ heap, with the game's zero page kept (f_gkeep); a slot no longer holding an
\ exploding ship (its data block's byte #31 bit 5) has nothing to draw

.f_dots
 LDA #0                 \ (Port: the counter not in FZ: PTCLS is game code)
 STA f_di
.fdo2
 LDX f_di
 CPX F_NDOT
 BCS fdo9
 LDA F_DC,X
 BPL fdo5
 AND #&7F               \ a ship type: its dot colour
 TAY
 LDA FC_DOTE,Y
 STA R_COLE
 LDA FC_DOTO,Y
 STA R_COLO
 LDY F_DY,X
 LDA F_DX,X
 TAX
 LDA #3
 JSR T_DOT
.fdo4
 INC f_di
 BNE fdo2
.fdo5                   \ a cloud: A = its slot
 TAY
 LDA FRIN,Y             \ (main RAM)
 BEQ fdo4
 LDA F_DX,X
 STA fz_p
 LDA F_DY,X
 STA fz_p+1
 LDY #31
 LDA (fz_p),Y
 AND #%00100000
 BEQ fdo4
 JSR f_gkeep
 LDY #33                \ XX19 = the heap, from the data block
 LDA (fz_p),Y
 STA XX19
 INY
 LDA (fz_p),Y
 STA XX19+1
 JSR f_gcloud           \ PTCLS's drawing, in the game's bank 4
 JSR f_clip             \ (the clip window back)
 JMP fdo4               \ (NMOS: for BRA)
.fdo9
 RTS

.f_di  EQUB 0           \ (f_dots's counter)

\ f_lasers: our laser beams (LASLI's four lines from LASX,LASY to the bottom
\ of the view) and the sights

.f_lasers
 LDA GLASV
 BEQ fla2
 LDA #FC_LASER
 JSR f_setcol
 LDA LASX
 STA fz_t
 LDA LASY
 STA fz_u
 LDX #32
 LDY #2*Y-1
 JSR f_line8
 LDX #224
 LDY #2*Y-1
 JSR f_line8
 LDX #48
 LDY #2*Y-1
 JSR f_line8
 LDX #208
 LDY #2*Y-1
 JSR f_line8
.fla2
.fla9
 RTS

\ ------------------------------------------------------------------------------
\ Text overlay
\ ------------------------------------------------------------------------------

F_TCOL = &FF            \ text ink: yellow (logical colour 3)

\ f_rowptr: X = text row -> fz_p = F_TM + 32*row (X kept)

.f_rowptr
 TXA
 LSR A
 LSR A
 LSR A
 STA fz_p+1
 TXA
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A
 CLC
 ADC #LO(F_TM)
 STA fz_p
 LDA fz_p+1
 ADC #HI(F_TM)
 STA fz_p+1
 RTS

\ f_text1: this buffer's text before the repair. The cells f_mark noted
\ since its last frame are marked dirty (f_tmark). Then in each row that
\ changed since its last text steps (F_TCH), the cleared cells are erased,
\ given back their background by marking them dirty (R_MARKBOX); one the
\ other buffer has erased already is forgotten (0). A row with no character
\ is then done.

.f_text1
 LDX F_BACK
 LDA f_mkn,X
 BEQ ft10
 JSR f_tmark
.ft10
 LDA #0
 STA f_rpn              \ (f_eor's replacements: a frame apart, not EOR's)
 SEC                    \ this buffer's bit in F_TCH, and the other's
 ADC F_BACK
 STA f_tbit
 EOR #3
 STA f_obit
 LDX #23                \ rows 23..0 (each row is independent)
.ft11
 LDA F_TCH,X
 AND f_tbit
 BEQ ft18x
 STX fz_i
 JSR f_rowptr
 LDY #31
.ft12
 LDA (fz_p),Y           \ cleared (bit 7): erase it
 BPL ft17
 STY fz_u
 TYA
 ASL A
 ASL A
 ASL A
 STA R_XL
 ORA #7
 STA R_XR
 JSR f_clipx
 BCC ft16
 LDA fz_i               \ lines 8r..8r+7 within the clip window (1..191)
 ASL A
 ASL A
 ASL A
 TAY
 BNE P%+3              \ (Z from the TAY: row 0 starts at 1)
 INY
 ORA #7
 STA R_BY1
 JSR T_MARKBOX          \ (R_MARKDIRTY for rows Y to R_BY1)
.ft16
 LDY fz_u
 LDX fz_i
 LDA F_TCH,X            \ the other buffer erased it at its last frame: no
 AND f_obit             \ buffer shows it now
 BNE ft17
 LDA #0
 STA (fz_p),Y
.ft17
 DEY
 BPL ft12
 LDX fz_i
 LDA F_TMR,X            \ no character to draw: the row is done (else
 BNE ft18x              \ f_text2 finishes it)
 LDA F_TCH,X
 EOR f_tbit
 STA F_TCH,X
.ft18x
 DEX
 BPL ft11
 RTS

\ f_tmark: buffer X's cells that f_mark noted, row by row, marked dirty
\ (R_MARKBOX, within the clip window: x 2..253, y 1..191), and forgotten

.f_tmark
 LDA #0
 STA f_mkn,X
 TXA                    \ (buffer 1's notes are 24 on)
 BEQ P%+4
 LDA #24
 STA f_tmo
 LDX #23
.ftm1
 TXA
 CLC
 ADC f_tmo
 TAY
 LDA f_mkr,Y
 BEQ ftm8
 ASL A                  \ R_XR = 8 * (the rightmost + 1) - 1, at most 253
 ASL A                  \ (32 cells: 256 - 1, as the shifts drop bit 8)
 ASL A
 SEC
 SBC #1
 CMP #254
 BCC P%+4
 LDA #253
 STA R_XR
 LDA f_mkl,Y            \ R_XL = 8 * the leftmost, at least 2
 ASL A
 ASL A
 ASL A
 CMP #2
 BCS P%+4
 LDA #2
 STA R_XL
 LDA #0
 STA f_mkr,Y
 STX f_tmx
 TXA                    \ rows 8r .. 8r + 7, from 1
 ASL A
 ASL A
 ASL A
 TAY
 ORA #7
 STA R_BY1
 TYA
 BNE P%+3
 INY
 JSR T_MARKBOX
 LDX f_tmx
.ftm8
 DEX
 BPL ftm1
 RTS

.f_tmo EQUB 0
.f_tmx EQUB 0

.f_clipx                \ clamp R_XL..R_XR to the clip window; C set if not
 LDA R_XL               \ empty
 CMP R_CL
 BCS P%+6
 LDA R_CL
 STA R_XL
 LDA R_XR
 CMP R_CR
 BCC P%+6
 LDA R_CR
 STA R_XR
 LDA R_XR
 CMP R_XL
 RTS

\ f_text2: draw the characters of each row that changed since this buffer's
\ last text steps (F_TCH, whose bit is then cleared), and elsewhere those
\ whose pixels something overwrote this frame: anything in this frame's
\ written or dirty extents over the row's eight lines (R_WL/R_WR and this
\ buffer's dirty extents, from bank 5 for all the rows at once: f_wq; the
\ disc layer's writes are in R_WL/R_WR, which f_ddraw has bank 5 put there)

.f_text2
 JSR f_wq               \ the written extents, and the sights' (f_sight2)
 LDX #23                \ rows 23..0 (each row is independent)
.ft21
 LDA F_TMR,X            \ skip empty rows in a tight loop
 BNE ft2r
.ft29
 DEX
 BPL ft21
 RTS
.ft2r
 STX fz_i
 JSR f_rowptr
 LDA F_TCH,X            \ changed for this buffer: the whole row (then it is
 AND f_tbit             \ unchanged)
 BEQ ft2w
 EOR F_TCH,X
 STA F_TCH,X
 LDY #0
 STY f_wl
 LDY #31
 BNE ft27
.ft2w
 TXA                    \ the cells over this frame's writes: R_GETW's
 ASL A                  \ extent for the row (f_wq: in the mailbox)
 TAY
 LDA MBOX+1,Y
 BEQ ft2x               \ (nothing written in the row: WR = 0)
 LSR A                  \ as cell columns: wl DIV 8 .. wr DIV 8
 LSR A
 LSR A
 STA fz_t
 LDA MBOX,Y
 LSR A
 LSR A
 LSR A
 STA f_wl
 LDY fz_t
.ft27                   \ columns Y down to f_wl
 LDA (fz_p),Y
 BEQ ft28
 BMI ft28
 STY fz_u
 JSR f_glyph
 LDY fz_u
.ft28
 CPY f_wl
 BEQ ft2x
 DEY
 BPL ft27               \ (NMOS: Y = 0..30)
.ft2x
 LDX fz_i
 JMP ft29

.f_wl EQUB 0

\ f_wq: this frame's written and dirty extents, for the text rows with a
\ character and no change for this buffer (whose cells f_text2 redraws only
\ where something was drawn over them), and the sights' rows (f_sight2), from
\ bank 5 in one call (R_GETW with A = &40: gfx-raster_dq.asm): the rows' mask
\ in MBOX+&30..&32 (bit r AND 7 of byte r DIV 8 for text row r), &FF in
\ MBOX+&33 for the sights; the rows' extents come back as (WL, WR) pairs at
\ MBOX + 2r (WR = 0: none), and bit 7 of MBOX+&34 set if anything was drawn
\ over the sights

.f_wq
 LDA #0                 \ the rows' mask
 STA MBOX+&30
 STA MBOX+&31
 STA MBOX+&32
 LDX #23
.fwq1
 LDA F_TMR,X            \ a row with characters and no change for this buffer
 BEQ fwq2
 LDA F_TCH,X
 AND f_tbit
 BNE fwq2
 TXA
 LSR A
 LSR A
 LSR A
 TAY
 TXA
 AND #7
 STX fz_t
 TAX
 LDA f_bits,X
 ORA MBOX+&30,Y
 STA MBOX+&30,Y
 LDX fz_t
.fwq2
 DEX
 BPL fwq1
 LDX F_BACK             \ the sights, if they are drawn in this buffer and to
 LDA GSIGHT             \ stay (f_sight2)
 BEQ P%+5
 LDA F_SGS,X
 STA MBOX+&33
 LDA #&40
 JMP T_GETW

.f_bits EQUB 1, 2, 4, 8, 16, 32, 64, 128

\ f_glyph: draw character A at column Y, text row fz_i, ink F_TCOL, only on
\ the glyph's pixels and only inside the clip window

.f_glyph
 SEC
 SBC #32                 \ glyph address = F_FONT + 8 * (char - 32)
 PHA
 ASL A
 ASL A
 ASL A
 ASSERT LO(F_FONT) = 0
 STA fgl1+1
 STA fglr+1             \ (the second load of the same row, for the low nibble)
 PLA
 LSR A
 LSR A
 LSR A
 LSR A
 LSR A
 CLC
 ADC #HI(F_FONT)
 STA fgl1+2
 STA fglr+2
 TYA                    \ screen: base + row*&200 + 16*col
 ASL A
 ASL A
 ASL A
 ASL A
 STA fz_nm               \ low byte (16*col, may carry)
 ORA #8                  \ fz_v3 = fz_nm + 8, the right byte of the cell (low
 STA fz_v3               \ nibble 0: no carry; ORA keeps C for the ROL)
 LDA fz_i                \ high byte = 2*row + carry + &40 (row <= 23, so
 ROL A                   \ ROL leaves C = 0 and the ADC cannot carry)
 ADC f_scr               \ (Port: the back buffer's base, f_bufpatch)
 STA fz_nm+1
 STA fz_v3+1
 LDA #&FF               \ masks for the border columns (patched into the loop)
 STA fglm+1
 STA fgrm+1
 CPY #0
 BNE P%+7
 LDA #&33               \ pixels 0-1 of column 0 are the border
 STA fglm+1
 CPY #31
 BNE P%+7
 LDA #&CC               \ pixels 254-255 are the border
 STA fgrm+1
 ASSERT F_TCOL = &FF    \ ink is all-ones: (m AND ink) OR (NOT m AND s) = m OR s
 LDA fz_i               \ first line y = 8*row
 ASL A
 ASL A
 ASL A
 STA f_gy               \ (C = 0: row <= 23)
 LDA R_CT               \ the lines inside the clip window vertically:
 SBC f_gy               \ Y from max(0, R_CT - 8*row) (minus 1 here: the
 BCS P%+4               \ loop is entered at its INY)
 LDA #&FF
 TAY
 LDA R_CB               \ to min(7, R_CB - 8*row), none if R_CB < 8*row
 SEC
 SBC f_gy
 CLV                    \ V = 0 on exit, as before
 BCC fgl9
 CMP #7
 BCC P%+4
 LDA #6                 \ (NMOS: 6 + 1 + C = 1)
 ADC #1                 \ (no overflow: V = 0 still)
 STA fgl4+1
 BNE fgl3
.fgl0
.fgl1
 LDA F_FONT,Y           \ patched
 BEQ fgl3
 LSR A
 LSR A
 LSR A
 LSR A
 TAX
 LDA f_nib,X
.fglm
 AND #&FF               \ patched (left border mask)
 ORA (fz_nm),Y
 STA (fz_nm),Y
.fglr
 LDA F_FONT,Y           \ patched (the same address as fgl1)
 AND #15
 TAX
 LDA f_nib,X
.fgrm
 AND #&FF               \ patched (right border mask)
 ORA (fz_v3),Y
 STA (fz_v3),Y
.fgl3
 INY
.fgl4
 CPY #8                 \ patched (last line + 1)
 BCC fgl0
.fgl9
 RTS

.f_gy EQUB 0

.f_nib                  \ 4 font bits (bit 3 = leftmost) -> MODE 1 pixel mask
FOR n, 0, 15
 EQUB n * &11
NEXT

F_FONT = &C000          \ Port (Model B): the MOS's font (characters 32 to 127,
                        \ eight bytes each), in the MOS ROM, which is always
                        \ paged at &C000

\ ------------------------------------------------------------------------------
\ Laser sights: four short arms about (128, 96), drawn after everything else
\ and only redrawn when something was written over them (like the text)
\ ------------------------------------------------------------------------------

SGX = 128
SGY = 96
SGIN = 11               \ arms run from SGIN to SGOUT pixels from the centre
SGOUT = 20

.F_SGS EQUB 0, 0        \ per buffer: the sights are drawn in it

\ f_sight1: sights shown in this buffer but no longer wanted: mark them dirty

.f_sight1
 LDX F_BACK
 LDA F_SGS,X
 BEQ fsg9
 LDA GSIGHT
 BNE fsg9
 STA F_SGS,X            \ (A = 0 as GSIGHT = 0)
 LDA #SGX-SGOUT         \ the horizontal arms
 STA R_XL
 LDA #SGX+SGOUT
 STA R_XR
 LDY #SGY
 JSR T_MARKDIRTY
 LDA #SGX               \ and the vertical arms (Port: in one call, R_MARKBOX)
 STA R_XL
 STA R_XR
 LDA #SGY+SGOUT
 STA R_BY1
 LDY #SGY-SGOUT
 JMP T_MARKBOX
.fsg9
 RTS

\ f_sight2: the sights, when wanted: drawn if this buffer does not show them,
\ or if anything was drawn over them this frame (f_wq's bit 7 of MBOX+&34:
\ this frame's written or dirty extents covering x = SGX on rows SGY-SGOUT to
\ SGY+SGOUT, or SGX-SGOUT to SGX+SGOUT on row SGY: the disc layer's writes
\ among them)

.f_sight2
 LDA GSIGHT
 BEQ fsg9
 LDX F_BACK
 LDA F_SGS,X
 BEQ fsg3               \ not drawn yet
 BIT MBOX+&34           \ overwritten?
 BPL fsg9
.fsg3
 LDX F_BACK
 LDA #&FF
 STA F_SGS,X
 LDA F_CPE+FC_SIGHT     \ horizontal arms (row SGY is even)
 STA R_COLE
 STA R_COLO
 LDA #SGX-SGOUT
 STA R_XL
 LDA #SGX-SGIN
 STA R_XR
 LDY #SGY
 JSR T_SPAN
 LDA #SGX+SGIN
 STA R_XL
 LDA #SGX+SGOUT
 STA R_XR
 LDY #SGY
 JSR T_SPAN
 LDA F_CPE+FC_SIGHT     \ vertical arms: pixel 0 of byte column 32
 AND #&88               \ (loop-invariant colour bits)
 STA fz_t
 ASSERT SGY-SGOUT = 76 AND SGY-SGIN = 85   \ byte = base + (y DIV 8)*&200 + &100 + (y MOD 8)
 ASSERT SGY+SGIN = 107 AND SGY+SGOUT = 116
 LDY #3                 \ rows 76..79: &5304..&5307 (in buffer 1: the high bytes
.fsg4                   \ are f_bufpatch's, for this frame's buffer)
.fsg4a
 LDA &5304,Y
 AND #&77
 ORA fz_t
.fsg4b
 STA &5304,Y
 DEY
 BPL fsg4
 LDY #5                 \ rows 80..85: &5500..&5505
.fsg5
.fsg5a
 LDA &5500,Y
 AND #&77
 ORA fz_t
.fsg5b
 STA &5500,Y
 DEY
 BPL fsg5
 LDY #4                 \ rows 107..111: &5B03..&5B07, rows 112..116: &5D00..&5D04
.fsg6
.fsg6a
 LDA &5B03,Y
 AND #&77
 ORA fz_t
.fsg6b
 STA &5B03,Y
.fsg6c
 LDA &5D00,Y
 AND #&77
 ORA fz_t
.fsg6d
 STA &5D00,Y
 DEY
 BPL fsg6
 SEC                    \ C = 1 on exit, as before
 RTS

\ ------------------------------------------------------------------------------
\ f_behind: is ship f_si behind the planet, with the first vertex of its first
\ visible face inside its disc? C set if so (don't draw it)
\ ------------------------------------------------------------------------------

.f_behind
 LDA F_PLON             \ the planet's disc, if any
 BEQ fbh0
 LDX #4
.fbhp
 LDA F_PLX,X            \ (F_PLX, F_PLY, F_PLR)
 STA fb_x,X
 DEX
 BPL fbhp
 LDA F_PLZH
 STA fb_zh
 LDA F_PLZL
 STA fb_zl
 LDA #LO(F_HW)
 LDX #HI(F_HW)
 JMP f_bdisc
.fbh0
 CLC
 RTS

\ f_bdisc: is ship f_si behind the disc fb_x, fb_y, fb_r (half-widths at
\ (A, X)), z fb_zh/fb_zl, with the first vertex of its first visible face
\ inside it? C set if so

.f_bdisc
 STA fbh_hw+1
 STX fbh_hw+2
 LDX f_si               \ further away than the disc?
 LDA fb_zl
 CMP F_SZL,X
 LDA fb_zh
 SBC F_SZH,X
 BCS fbh8               \ disc z >= ship z: in front
 LDY #0                 \ first visible face: its first vertex
 STY f_f
 LDA fz_ft
 STA fz_p
 LDA fz_ft+1
 STA fz_p+1
.fbh1
 LDY f_f
 CPY f_nf
 BCS fbh8
 LDA (fz_dl),Y
 BNE fbh2
 LDY #0                 \ skip this face's list entry (n + 16 * its hue ramp,
 LDA (fz_p),Y           \ n offsets: n + 1 bytes)
 AND #15
 SEC
 ADC fz_p
 STA fz_p
 BCC P%+4
 INC fz_p+1
 INC f_f
 JMP fbh1
.fbh2
 LDY #1                 \ XX3 offset of the vertex
 LDA (fz_p),Y
 TAY
 LDA XX3,Y              \ dx = x - the disc's x (16-bit)
 SEC
 SBC fb_x
 STA fz_t
 LDA XX3+1,Y
 SBC fb_x+1
 JSR f_abs16            \ -> A = |dx| if < 256, else C set (Y kept)
 BCS fbh8
 STA f_bdx
 LDA XX3+2,Y            \ dy = y - the disc's y
 SEC
 SBC fb_y
 STA fz_t
 LDA XX3+3,Y
 SBC fb_y+1
 JSR f_abs16
 BCS fbh8
 CMP fb_r               \ |dy| <= r and |dx| <= half-width(|dy|)?
 BEQ fbh3
 BCS fbh8
.fbh3
 TAX
.fbh_hw
 LDA F_HW,X             \ (patched: the half-width table)
 CMP f_bdx
 BCC fbh8
 SEC
 RTS
.fbh8
 CLC
 RTS

.fb_x  EQUW 0           \ the disc: centre, radius (as F_PLX, F_PLY, F_PLR)
.fb_y  EQUW 0
.fb_r  EQUB 0
.fb_zh EQUB 0
.fb_zl EQUB 0
.f_bdx EQUB 0

\ f_abs16: (A fz_t) 16-bit signed -> A = |value| and C clear if < 256, else
\ C set

.f_abs16
 BPL fab1
 STA fz_u               \ negate the 16-bit value: 0 - (A fz_t)
 SEC
 LDA #0
 SBC fz_t
 STA fz_t
 LDA #0
 SBC fz_u
.fab1
 BNE fab9
 LDA fz_t
 CLC
 RTS
.fab9
 SEC
 RTS

\ f_winding: the face just gathered into R_PXL/R_PYL (low bytes; a far ship is
\ small, so differences fit in 8 bits), whose byte in the record's XX2 copy
\ is fz_t: C set if it is front-facing, i.e. clockwise on screen, (x1 - x0) *
\ (y2 - y0) - (y1 - y0) * (x2 - x0) > 0, as the face lists' windings are for
\ a ship with ZINF's handedness; anticlockwise if bit 5 of fz_t is set (the
\ ship has TIDY's handedness, mirrored: GHAND, S_SHIP)

.f_winding
 LDA R_PXL+1
 SEC
 SBC R_PXL
 STA fw_a
 LDA R_PYL+2
 SEC
 SBC R_PYL
 JSR f_smul             \ (x1 - x0) * (y2 - y0)
 STA fw_h
 STX fw_l
 LDA R_PYL+1
 SEC
 SBC R_PYL
 STA fw_a
 LDA R_PXL+2
 SEC
 SBC R_PXL
 JSR f_smul             \ (y1 - y0) * (x2 - x0)
 STA fw_t
 STX fw_t+1
 LDA fw_l               \ first - second, 16-bit signed
 SEC
 SBC fw_t+1
 STA fw_l
 LDA fw_h
 SBC fw_t
 BVC P%+4
 EOR #&80
 STA fw_h               \ (bit 7: the sign)
 ORA fw_l
 BEQ fwn9               \ zero: edge-on
 LDA fz_t               \ bit 5 of the face's byte (bit 7 here): the ship is
 ASL A                  \ mirrored from the face lists' handedness (L_REC)
 ASL A
 EOR fw_h
 BMI fwn9               \ negative (positive if mirrored): back face
 SEC
 RTS
.fwn9
 CLC
 RTS

\ f_smul: A * fw_a, both signed 8-bit -> A (high), X (low), signed 16-bit

.f_smul
 STA fw_b
 STA fw_bo
 LDA #0
 STA fw_t2
 LDX #8
.fsm1                   \ unsigned (fw_a * fw_b), then correct for signs
 LSR fw_b
 BCC fsm2
 CLC
 ADC fw_a
.fsm2
 ROR A
 ROR fw_t2
 DEX
 BNE fsm1
 TAX                    \ A = high byte of the unsigned product
 LDA fw_a               \ if fw_a < 0, high -= original b; if b < 0, high -= a
 BPL fsm3
 TXA
 SEC
 SBC fw_bo
 TAX
.fsm3
 LDA fw_bo
 BPL fsm4
 TXA
 SEC
 SBC fw_a
 TAX
.fsm4
 TXA
 LDX fw_t2
 RTS

.fw_a  EQUB 0
.fw_b  EQUB 0
.fw_bo EQUB 0
.fw_t  EQUW 0
.fw_t2 EQUB 0
.fw_h  EQUB 0
.fw_l  EQUB 0
\ f_proj: LL9's part 6 on (LL42P: each vertex's visibility, and the visible
\ ones' screen coordinates into XX3), run for ship f_si as LL9 would have run
\ it, from its record (F_SHIP): XX2 non-zero for the faces shown (the levels;
\ face 15 always, as part 3 sets it), XX4, INWK 0-8, XX16 and XX0. INWK+31
\ is 0 (LL72: not exploding), and H_EE31 returns at once (GPRJ, which the
\ game's LL42F sets round its call of LL42P). The game's zero page is kept
\ round it (f_gkeep). Port (Model B): part 6 on runs in the game's bank 4,
\ through the far call farH (f_gproj: the program's S% + 16, LL42F), and
\ its zero page is the rasteriser's &09-&27 (XX16, XX0 ...) and this
\ layer's FZ (XX2): the clip window is put back after it (f_clip), and FZ
\ holds nothing across it

\ f_proj0: before the wait for the flip (f_sort), project the first ship
\ f_ships draws, unless f_ship would skip it (FC_MINVIS); f_pj notes it,
\ and f_proj leaves its vertices for f_ship (f_pj: &FF, none)

.f_pj   EQUB &FF
.f_proj0
 LDX F_ORD
 LDY F_STYP,X
 LDA F_SX4,X
 CMP FC_MINVIS,Y
 BEQ P%+4
 BCS fpz9
 STX f_si
 LDA F_SNF,X
 STA f_nf
 JSR f_proj
 LDA f_si
 STA f_pj
.fpz9
 RTS

.f_proj
 LDA f_si               \ already projected (f_proj0): the vertices are in
 CMP f_pj               \ XX3, and no other ship is
 BNE fpj0
 LDA #&FF
 STA f_pj
 RTS
.fpj0
 JSR f_gkeep
 LDX f_si
 FOR k, 0, 8
  LDA F_RP+k*MAXSH,X
  STA INWK+k
 NEXT
 FOR k, 0, 17
  LDA F_RP+(9+k)*MAXSH,X
  STA XX16+k
 NEXT
 LDA F_RP+27*MAXSH,X
 STA XX0
 LDA F_RP+28*MAXSH,X
 STA XX0+1
 LDA F_SX4,X
 STA XX4
 LDA F_SPL,X            \ the faces' levels as XX2 (an absolute read: XX2 is
 STA fpj1+1             \ FZ, this layer's pointers)
 LDA F_SPH,X
 STA fpj1+2
 LDY #0
 LDX f_nf
 BEQ fpj2
.fpj1
 LDA &FFFF,Y            \ (patched)
 STA XX2,Y
 INY
 DEX
 BNE fpj1
.fpj2
 LDA #255
 STA XX2+15
 STX INWK+31            \ (NMOS: X = 0, fpj1's end)
 JSR f_gproj            \ part 6 on, in the game's bank 4
 JMP f_clip             \ (the clip window back: XX16 is over it)

\ f_gproj, f_gcloud: the game code the frame runs, in the program's bank 4
\ (BANK4), through the far call farH, which pages this bank back after it:
\ the entries in each program's S% table (elite-source-*.asm)

.f_gproj
 JSR farH               \ LL42F: LL9's part 6 on, with H_EE31 returning at once
 EQUW SGPROJ
.f_gcloud
 JSR farH               \ PTCLR: PTCLS's drawing of the cloud at XX19 (its
 EQUW SGCLOUD           \ particles through H_DOT, F_PDOT)

\ f_gkeep: before the frame first runs game code (f_proj, f_dots' clouds),
\ keep the game's zero page that the game reads afterwards and that game
\ code changes, outside the rasteriser's &06-&27 and FZ (which F_FRAME
\ keeps): RAND, Q, TGT, INWK 0-8, INWK+31 and XX19; the frame puts it back
\ at its end (f_gback; f_gz bit 7: kept, until then). The rest it writes is
\ the drawing's temporaries, written again before they are read

FGZ = 4 + 1 + 1 + 9 + 1 + 2
.f_gzs SKIP FGZ
.f_gz   EQUB 0
.f_gkeep
 BIT f_gz
 BMI fgk9
 FOR k, 0, 3 : LDA RAND+k : STA f_gzs+k : NEXT
 LDA Q : STA f_gzs+4
 LDA TGT : STA f_gzs+5
 FOR k, 0, 8 : LDA INWK+k : STA f_gzs+6+k : NEXT
 LDA INWK+31 : STA f_gzs+15
 LDA XX19 : STA f_gzs+16
 LDA XX19+1 : STA f_gzs+17
 DEC f_gz
.fgk9
 RTS

.f_gback
 INC f_gz               \ (NMOS: &FF to 0)
 FOR k, 0, 3 : LDA f_gzs+k : STA RAND+k : NEXT
 LDA f_gzs+4 : STA Q
 LDA f_gzs+5 : STA TGT
 FOR k, 0, 8 : LDA f_gzs+6+k : STA INWK+k : NEXT
 LDA f_gzs+15 : STA INWK+31
 LDA f_gzs+16 : STA XX19
 LDA f_gzs+17 : STA XX19+1
 RTS

\ F_GUN: the set-up of LL9's part 6 (LL42P) for a ship firing at us, whose
\ gun vertex alone it projects in the game (H_LL42; the frame projects the
\ ship): A = blueprint byte #6, 4 * the vertex's number. XX16 as LL42P
\ leaves it (transposed: LL51's matrix), XX20 = the offset after the vertex
\ (the loop's end), V = the vertex data (XX0 + 20), CNT = A (its offset in
\ XX3) and Y = its offset in the vertex data, 6 * the number, for part 6's
\ loop at LL48

.F_GUN
 STA CNT
 LSR A
 CLC
 ADC CNT
 PHA                    \ (C clear: 6 * the number is a byte, as Y)
 ADC #6
 STA XX20
 LDA XX0
 ADC #20                \ (C still clear: XX20 is a byte)
 STA V
 LDA XX0+1
 ADC #0
 STA V+1
 \ the transpose, as LL42P: XX16 2-3 <-> 6-7, 4-5 <-> 12-13, 10-11 <-> 14-15
 LDY XX16+2
 LDX XX16+3
 LDA XX16+6
 STA XX16+2
 LDA XX16+7
 STA XX16+3
 STY XX16+6
 STX XX16+7
 LDY XX16+4
 LDX XX16+5
 LDA XX16+12
 STA XX16+4
 LDA XX16+13
 STA XX16+5
 STY XX16+12
 STX XX16+13
 LDY XX16+10
 LDX XX16+11
 LDA XX16+14
 STA XX16+10
 LDA XX16+15
 STA XX16+11
 STY XX16+14
 STX XX16+15
 PLA
 TAY
 RTS

\ F_LINE: record an enemy laser beam X1,Y1 -> X2,Y2 (8-bit screen coords;
\ at most one per ship recorded: MAXLN)

.F_LINE
 LDX F_NLINE
 CPX #MAXLN
 BCS fli9
 LDA X1
 STA F_LX0,X
 LDA Y1
 STA F_LY0,X
 LDA X2
 STA F_LX1,X
 LDA Y2
 STA F_LY1,X
 INC F_NLINE
.fli9
 RTS

\ F_CLOUD: PTCLS on the explosion cloud at XX19 in record mode, its draw pass
\ (DOEXP falling into it: H_PTCLS, C set) or its erase pass (H_PTCLSE, C
\ clear). The draw pass notes the cloud for the frame: the slot, XSAV, and
\ its data block, INF (f_dots runs PTCLS again on the ship line heap, plotting
\ each particle: f_gcloud, F_PDOT). The heap is the cloud's record (bytes 0-2
\ its size, counter and vertex count, 3-6 its seeds, then the vertices' screen
\ coordinates), and nothing writes it again before the frame. Then both
\ passes do what the game keeps of PTCLS: the random numbers, which depend
\ only on the last vertex's seeds and the particle count, as PTCLS calls
\ DORND2 three times a particle and keeps RAND+1, and RAND+3 = the planet's
\ z_lo; and Q, U, TGT and CNT as it leaves them. Port (Model B): disc
\ Elite's PTCLS, whose particles per vertex are U + 1 with U = (the counter,
\ or its complement past 127) / 8 OR 1

.F_CLOUD
 BCC fcd1
 LDY F_NDOT
 CPY #MAXDT
 BCS fcd1
 LDA INF                \ (zero page)
 STA F_DX,Y
 LDA INF+1
 STA F_DY,Y
 LDA XSAV
 STA F_DC,Y
 INC F_NDOT
.fcd1
 LDY #0                 \ Q = the cloud's size
 LDA (XX19),Y
 STA Q
 INY                    \ U = the particles per vertex, less one (as PTCLS)
 LDA (XX19),Y
 BPL P%+4
 EOR #&FF
 LSR A
 LSR A
 LSR A
 ORA #1
 STA U
 INY                    \ TGT = the vertex count, 4 * n + 6
 LDA (XX19),Y
 STA TGT
 LDA #10                \ CNT = the last vertex's end: 10, 14, ... up to TGT
.fcd2
 CMP TGT
 BCS fcd3
 ADC #4
 BCC fcd2
.fcd3
 STA CNT
 INY                    \ its seeds RAND and RAND+2 (the bytes after them
 LDA (XX19),Y           \ feed DORND2's RAND+1 and RAND+3, which PTCLS
 EOR CNT                \ puts back as it found them, and as K%+6)
 STA RAND
 LDY #5
 LDA (XX19),Y
 EOR CNT
 STA RAND+2
 LDA U                  \ X = 3 * (U + 1): DORND2's RAND and RAND+2
 ASL A                  \ (U <= 15, so the carry is clear)
 ADC U
 ADC #3
 TAX
.fcd4
 LDA RAND
 ASL A
 TAY
 ADC RAND+2
 STA RAND
 STY RAND+2
 DEX
 BNE fcd4
 LDA K%+6               \ (main RAM)
 STA RAND+3
 RTS

\ F_SHPPT: record a distant ship as a 2x2 dot at (K3, K4), in its hue

.F_SHPPT
 STY f_ysav
 LDY F_NDOT
 CPY #MAXDT
 BCS fsp9
 LDA K3
 STA F_DX,Y
 LDA K4
 STA F_DY,Y
 LDA TYPE
 ORA #&80               \ bit 7: ship type (bits 0-6), drawn in its dot colour
 STA F_DC,Y
 INC F_NDOT
.fsp9
 LDY f_ysav
 RTS

