\ ******************************************************************************
\
\ elite-map.asm - the port's memory map (docs/memory-map.md)
\
\ Port: the addresses that the loader, both programs and the ship blueprint
\ files share. Each of the two programs (the flight code and the docked code)
\ lives in two sideways RAM banks, which the loader finds (BANKS, in
\ elite-far.asm): its home bank, paged whenever its code runs, and its cold
\ bank, paged only for far calls. Both programs lay their home banks out the
\ same way, so that the loader's resident code can enter either one:
\
\   &8000   S%, the program's entry table (as the original's at &11E3), then
\           the program's home code in the original's order
\   &B600   the blueprint set (XX21, as the original's at &5600): the flight
\           program's is loaded from a D.MOx file, the docked program's is its
\           own (its blocks tagged "Area: blueprints")
\
\ and their cold banks hold the cold code from &8000 in the original's order,
\ then the recursive text tokens (QQ18, the original's WORDS file at &0400).
\ The missile's blueprint stays in main RAM at &7F00, as in the original,
\ where both programs' blueprint tables point, just above the screen.
\
\ Loads from disc cannot go straight into sideways RAM (DFS is paged in at
\ &8000 while it loads), so each file is loaded into main RAM at STAGE% and
\ copied into its bank.
\
\ ******************************************************************************

 HOME% = &8000          \ The start of each program's home bank: S%, its entry
                        \ table (+0: the docking or launch entry, +3: the new
                        \ game entry, +6: JMP to the WRCHV handler, +9: IRQ1's
                        \ address, +11: JMP to the BRKV handler)

 INBAYJ% = HOME% + &1D  \ The docked code's JMP SCRAM, in its INBAY, where the
                        \ flight code's INBAY returns after loading the docked
                        \ code at a death, as the original's did (the docked
                        \ code's layout checks it is there)

 PROGM% = &7970         \ Each program's main RAM part (its low pass, then the
 PROGM_END% = &7E00     \ hot pass's main RAM container), after the rupture's
                        \ code and before the mailbox, in the room that the
                        \ original's mode 5 dashboard leaves: the program's
                        \ layout copies it into its bank 4 image at PROGI%
                        \ (S%+14 gives it, as staged), and PCLI copies it here
                        \ when it loads the program

 PROGX% = &7FA0         \ The rest of each program's main RAM part: the room
 PROGX_END% = &7FFE     \ between the missile's blueprint (which ends there
                        \ without its edges) and VEC, for the hot pass (its
                        \ image follows PROGM%'s, and PCLI copies it too)

 PROGIS% = PROGM_END% - PROGM% + PROGX_END% - PROGX%   \ The size of the main
                        \ RAM part's image in bank 4 (PROGI%)

 BPSLOT% = &B700        \ The blueprint set in each home bank, to BPSLOT_END%
 BPSLOT_END% = &BFA2    \ without their edge lists (the EDGE macro), then its
                        \ ships' unit normals for the lighting, and their table
                        \ FC_NORMTAB at NORMTAB, at the slot's end (gfx-setdata.asm,
                        \ elite-shipset.asm): the largest set fits (the ship
                        \ files and the docked code's layout check it)

 NORMTAB = BPSLOT_END% - 2 * 33   \ FC_NORMTAB, by ship type 0 to 32

 SETF% = &C000          \ Where a D.MOx file carries its ships' face lists:
                        \ after the slot's pages (elite-shipset.asm)
 FC_NORMTAB = NORMTAB

 OVSTASH = &3C00        \ Where the flight code's overlay loader keeps WP and
                        \ the filing system's zero page during a load (ovload:
                        \ in buffer 0, above what STAGE% holds of an overlay)

 STAGE% = &1600         \ Where files are loaded before they are copied into
                        \ their bank (main RAM &1600 to &55FF, over the top of
                        \ the screens, which the game clears after each load)

 QSL = BPSLOT% - &400   \ The quarter squares, QS(n) = INT(n * n / 4) for n = 0
 QSH = QSL + &200       \ to 511: their low bytes at QSL and high bytes at QSH,
                        \ two pages each, page aligned (their users index them
                        \ by an operand's low byte and pick the page by its
                        \ high bit), in each program's home bank, just below
                        \ its blueprint slot (elite-layout-*.asm assemble
                        \ them there): only home code uses them (the game's
                        \ multiplications, and the renderer's lighting,
                        \ gfx-light.asm, which the docked code has them for),
                        \ and main RAM below the screen is the renderer's
                        \ second buffer (BUF0)

 SCREEN% = &4000        \ The screen: 256 x 192 pixels in four colours (MODE 1's
                        \ format, 64-byte rows, at the 6845's 2 MHz clock)
 PANEL% = &7000         \ The dashboard: the original's, 128 x 56 pixels in
                        \ four colours (mode 5's format, 32-byte rows, at the
                        \ 1 MHz clock), seven rows of 256 bytes, P.DIALS
                        \ (docs/video-timing.md)

 RUPT% = &7700          \ The rupture's code (elite-rupture.asm), after the
 RUPTPG = 3             \ dashboard: RUPTPG pages, which the loader copies

 CRTC = &FE00           \ The 6845's address and data registers

 ULAA = &D8             \ The video ULA's control register for the screen (MODE
 ULAB = &C4             \ 1: 2 MHz clock, four colours) and the dashboard (mode
                        \ 5: 1 MHz clock, four colours)

 ESCPA = &0386          \ ESCP, the escape pod flag, in both programs (their
                        \ layouts check it), for the dashboard's palette

 RTRIM1 = 0             \ The switches' trims, in 2 MHz cycles (half
 RTRIM2 = 0             \ microseconds), added to the cycle of S1's (RTRIM1) and
                        \ S2's (RTRIM2) write to the ULA's control register: 0
                        \ in jsbeeb; on a real Model B, the values that the
                        \ timing check gives (docs/video-timing.md, "On a real
                        \ Model B")

                        \ The switches' targets: S1 (line 191 of the next field)
                        \ and S2 (line 311) as cycles from the loader's
                        \ calibration probe (the vertical sync's start, line
                        \ 272, as rwait's target), each split into whole
                        \ microseconds (RD1, RD2, modulo 256 in timer 2) and a
                        \ half (RH1, RH2: the odd cycle, an instruction of 3
                        \ cycles in place of 2 before the write); RS1 and RS2
                        \ place the writes on cycle 76 in jsbeeb with no trim
                        \ (docs/video-timing.md)
 RS1 = 2 * (14800 - 1 * 64) - 7 + RTRIM1
 RS2 = 2 * (2512 - 1 * 64) - 6 + RTRIM2
 RD1 = RS1 DIV 2
 RH1 = RS1 AND 1
 RD2 = RS2 DIV 2
 RH2 = RS2 AND 1

 RWMAX = 80             \ The longest wait (microseconds) that rwait takes as
                        \ on time; more means the interrupt came late

 MACRO RTRIMI h         \ A switch's odd half microsecond, before the write to
  IF h                  \ the ULA's control register: 3 cycles or 2
   BIT &70
  ELSE
   NOP
  ENDIF
 ENDMACRO

 MACRO RWAITX c         \ Exactly c cycles (c >= 2)
  IF c AND 1
   BIT &70
   FOR I%, 1, (c - 3) DIV 2
    NOP
   NEXT
  ELSE
   FOR I%, 1, c DIV 2
    NOP
   NEXT
  ENDIF
 ENDMACRO

 DFSSAVE% = &BF00       \ DFS's workspace, &1000-&10FF, between disc commands:
                        \ the last page of each program's cold bank, which no
                        \ cold image reaches (elite-layout-*.asm)


 PANELROWS = 7          \ The dashboard's character rows

 RLINEUS = 64           \ The screen's line, in microseconds
 RPA = 192 * RLINEUS - 2  \ Timer 1's periods for the rupture (RUPT): point 2
 RPB = 120 * RLINEUS - 2  \ (a line before S2 on line 311) to point 1 (a line
                        \ before S1 on line 191), and point 1 to point 2 (the
                        \ latch counts N + 2 microseconds)

 BUF0 = &1000           \ The filled renderer's second screen buffer, buffer 0
                        \ (&1000-&3FFF; buffer 1 is SCREEN%), which the
                        \ rasteriser (bank 5, gfx-rws.asm) draws into; it
                        \ covers DFS's
                        \ static workspace at &1000-&10FF, which PCLI keeps in
                        \ DFSSAVE% between disc commands

 MBOX = &7E00           \ The rasteriser's mailbox (&7E00-&7E9F, between the
                        \ dashboard and the missile's blueprint): its callers'
                        \ inputs (gfx-rws.asm)

 GVARS = &7EA0          \ The filled renderer's shared variables (&7EA0-&7EFF,
                        \ after the mailbox), which the game's hooks, the
                        \ vertical sync interrupt and the frame layer (bank
                        \ 6, gfx-frame.asm) all read or write; none of them
                        \ is game state (docs/renderer.md, "The frame layer's
                        \ bank 6"):

 GMODE = GVARS          \ Bit 7 set: space mode (double buffered: the drawing
                        \ hooks record, F_FRAME draws); clear: direct mode
                        \ (the game draws on buffer 1, SCREEN%, as it is)
 GFRONT = GVARS + 1     \ The buffer on show (0 or 1; 1 in direct mode)
 GFLIP = GVARS + 2      \ Non-zero: show buffer GPEND at the next vertical
 GPEND = GVARS + 3      \ sync (the interrupt sets GFRONT = GPEND and GFLIP =
                        \ 0); F_FRAME sets them, and waits for GFLIP = 0
                        \ before drawing into a buffer
 GWARP = GVARS + 4      \ Bit 7 set: TT66 is an in-system jump's (WARP sets it,
                        \ F_DIRECT clears it): in space mode the frames go on
 GFORCE = GVARS + 5     \ For the hooks: non-zero to draw directly even in a
                        \ space view
 GSIGHT = GVARS + 6     \ Non-zero: F_FRAME draws the laser sights
 GLASV = GVARS + 7      \ Non-zero: F_FRAME draws our laser beams (from LASX,
                        \ LASY; cleared after each frame)
 GNF = GVARS + 10       \ F_SHIP's and L_REC's inputs: the ship's number of
 GTYPE = GVARS + 12     \ faces and its type (TYPE, or 32 for the dodecahedron
                        \ station: a type 2 with 24 vertices); GVARS + 8, + 9
                        \ and + 11 are free
 GSTASH = GVARS + 13    \ Bit 7 set: a disc command has used buffer 0 (PCLI):
                        \ the next frame starts it afresh (f_b0new)
 GA = GVARS + 14        \ GCALL's A across the paging (gfx-glue.asm)
 PF_CLS = GVARS + 15    \ The planet's class, as PF_HOOK made it in this
                        \ iteration (gfx-planet7.asm: 0 a meridian planet, 1
                        \ craters; bit 7 set if it made the surface's circles,
                        \ which the frame's f_bounds draws, or with bit 6 if
                        \ it kept the last ones, which the frame moves with
                        \ the disc: F_PFHOLD, f_hrec)

                        \ The frame layer's entries, as the game calls them
                        \ (LDX #FG_xxx : JSR GCALL, gfx-glue.asm), in the order
                        \ of bank 6's dispatcher (gfx-bank6.asm)

 FG_INIT     = 0         \ the entries, in fjt_lo's order (gfx-bank6.asm)
 FG_DIRECT   = 1
 FG_FRAME    = 2
 FG_SHIP     = 3
 FG_LINE     = 4
 FG_PDOT     = 5
 FG_PLANET   = 6
 FG_SHPPT    = 7
 FG_CHAR     = 8
 FG_DELCHAR  = 9
 FG_CLRTEXT  = 10
 FG_GUN      = 11
 FG_HANG0    = 12
 FG_HANGAR   = 13
 FG_CLOUD    = 14
 FG_SETLD    = 15
 FG_PFHOLD   = 16
 FG_N        = 17

                        \ The fixed colours of the frame layer's lines and dots
                        \ (indices into its F_CPE, gfx-frame.asm)

 FC_BLACK = 0
 FC_LASER = 1            \ our laser beams
 FC_ELASER = 2           \ enemy laser beams
 FC_PLINE = 3            \ planet meridians, equator and craters
 FC_PART = 4             \ explosion particles
 FC_SIGHT = 5            \ laser sights
 FC_STAR = 6             \ stardust

 MB_SX = MBOX + &67     \ The stars' x, y and size (1 to 3, 0 for none) in the
 MB_SY = MBOX + &7A     \ rasteriser's mailbox (R_SX, R_SY and R_SS in
 MB_SS = MBOX + &8D     \ gfx-rws.asm), which the game's star hooks write: 19
                        \ each (stars 1 to NOST), at the mailbox's end, so that
                        \ the frame's disc layer has the rest

 PCBUF = MBOX           \ PCLI's command (32 bytes) and OSFILE block (18), in
 PBLK = MBOX + &20      \ the mailbox's polygon vertices (R_PXL to R_PYH),
                        \ which hold nothing between two calls of R_POLY, and
                        \ nothing draws during a disc command

 RESH% = &7EB0          \ The high resident block (&7EB0-&7EFF, after the
                        \ renderer's shared variables): the screen's palette
                        \ and the rupture's registers, which the loader's LOAD
                        \ routine copies there (elite-resident-high.asm)

 PALCMYK = RESH%        \ The screen's palette (16 bytes), which the vertical
                        \ sync's interrupt writes

 GLUE% = &0724          \ The glue the game calls the frame layer through, and
                        \ the trampolines into bank 5 (gfx-glue.asm): at a
                        \ fixed address at the end of the resident block A
                        \ (&0724-&07BC), which includes it there, so that bank 6
                        \ can be built against it

 DTMP = &07BD           \ Workspace for the hangar's lines (HAS2 and HAS3, in
 DTMP2 = &07BE          \ the docked code), at the end of the resident block A
                        \ (elite-resident.asm)

 PFVA% = &06E6          \ The circle engine's variables (gfx-merid.asm and
 PFVH% = &7EC0          \ gfx-planet7.asm, the flight code's planet surface in
 PFVS% = BPSLOT_END%    \ a build with _CIRCLES): 62 bytes at the end of the
                        \ resident block A, before the glue, and 64 after the
                        \ high resident block, in main RAM, and what one
                        \ PF_HOOK call makes and uses in the home bank's last
                        \ 94 bytes, after the blueprint slot, which a set's
                        \ file loads over (LOMOD) between iterations
 ASSERT PFVA% + 62 = GLUE%

 PF_INWK = &46          \ INWK, for bank 5's part of the planet's surface
                        \ (gfx-planet7.asm's pf_tilt), which is built before the
                        \ flight code (elite-layout-flight.asm checks it)

 LCOL = &A8             \ The colour of the next lines, pixels and characters
                        \ that the drawing routines draw on the space view: a
                        \ byte of four pixels of the colour (&0F cyan, &F0
                        \ magenta, &FF yellow), which they AND with their
                        \ pixels; in zero page at &A8, in the MOS's OSCLI
                        \ workspace (each drawing sets it first, and nothing
                        \ draws in a disc command)
