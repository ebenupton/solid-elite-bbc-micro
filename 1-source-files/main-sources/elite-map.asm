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

 BPSLOT% = &B600        \ The blueprint set in each home bank (2.5K, up to the
                        \ end of the bank)

 STAGE% = &1600         \ Where files are loaded before they are copied into
                        \ their bank (main RAM &1600 to &55FF, over the top of
                        \ the screens, which the game clears after each load)

 QSL = &B200            \ The quarter squares, QS(n) = INT(n * n / 4) for n = 0
 QSH = &B400            \ to 511: their low bytes at QSL and high bytes at QSH,
                        \ two pages each, page aligned (their users index them
                        \ by an operand's low byte and pick the page by its
                        \ high bit), in the flight code's home bank, just
                        \ below its blueprint slot (elite-layout-flight.asm
                        \ assembles them there): only the flight code's home
                        \ code uses them, and main RAM below the screen is
                        \ the renderer's second buffer (BUF0)

 SCREEN% = &4000        \ The screen: 256 x 192 pixels in four colours (MODE 1's
                        \ format, 64-byte rows), then the dashboard's 256 x 56
                        \ at PANEL%, shown as one 31-row frame by the 6845, as
                        \ BBC Master Elite's screen
 PANEL% = &7000

 DFSSAVE% = &BF00       \ DFS's workspace, &1000-&10FF, between disc commands:
                        \ the last page of each program's cold bank, which no
                        \ cold image reaches (elite-layout-*.asm)

 PANELROWS = 7          \ The dashboard's character rows

 RLINEUS = 64           \ The screen's line, in microseconds
 RPA = 188 * RLINEUS - 2  \ Timer 1's periods for the rupture (resident's IRQG):
 RPB = 124 * RLINEUS - 2  \ point 2 (line 8) to point 1 (line 196), and point 1 to
                        \ point 2 (the latch counts N + 2 microseconds)

 BUF0 = &1000           \ The filled renderer's second screen buffer, buffer 0
                        \ (&1000-&3FFF; buffer 1 is SCREEN%), which the
                        \ rasteriser (bank R, gfx-rws.asm) draws into; not
                        \ yet shown or used by the game; it covers DFS's
                        \ static workspace at &1000-&10FF, which PCLI keeps in
                        \ DFSSAVE% between disc commands

 MBOX = &7E00           \ The rasteriser's mailbox (&7E00-&7E9F, between the
                        \ dashboard and the missile's blueprint): its callers'
                        \ inputs (gfx-rws.asm)

 GVARS = &7EA0          \ The filled renderer's shared variables (&7EA0-&7EFF,
                        \ after the mailbox), which the game's hooks, the
                        \ vertical sync interrupt and the frame layer (bank
                        \ F, gfx-frame.asm) all read or write; none of them
                        \ is game state (docs/renderer.md, "The frame layer's
                        \ bank F"):

 GMODE = GVARS          \ Bit 7 set: space mode (double buffered: the drawing
                        \ hooks record, F_FRAME draws); clear: direct mode
                        \ (the game draws on buffer 1, SCREEN%, as it is)
 GFRONT = GVARS + 1     \ The buffer on show (0 or 1; 1 in direct mode)
 GFLIP = GVARS + 2      \ Non-zero: show buffer GPEND at the next vertical
 GPEND = GVARS + 3      \ sync (the interrupt sets GFRONT = GPEND and GFLIP =
                        \ 0); F_FRAME sets them, and waits for GFLIP = 0
                        \ before drawing into a buffer
 GDRAWON = GVARS + 4    \ For the hooks: 0 while the game is erasing (an
                        \ erasing call is not recorded)
 GFORCE = GVARS + 5     \ For the hooks: non-zero to draw directly even in a
                        \ space view
 GSIGHT = GVARS + 6     \ Non-zero: F_FRAME draws the laser sights
 GLASV = GVARS + 7      \ Non-zero: F_FRAME draws our laser beams (from LASX,
                        \ LASY; cleared after each frame)
 GLCOL = GVARS + 8      \ F_LINE's colour (a fixed colour index, FC_*)
 GDCOL = GVARS + 9      \ F_DOT's colour (a fixed colour index, FC_*)
 GNF = GVARS + 10       \ F_SHIP's inputs: the ship's number of faces and
 GNV = GVARS + 11       \ vertices, and its type (TYPE, or 32 for the
 GTYPE = GVARS + 12     \ dodecahedron station: a type 2 with 24 vertices)
 GSTASH = GVARS + 13    \ Bit 7 set: something else used the screen buffers
                        \ (a disc load): F_FRAME blanks both before drawing
 GA = GVARS + 14        \ GCALL's A across the paging (gfx-glue.asm)

                        \ The frame layer's entries, as the game calls them
                        \ (LDX #FG_xxx : JSR GCALL, gfx-glue.asm), in the order
                        \ of bank F's dispatcher (gfx-bankf.asm)

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
 FG_HANG0    = 14
 FG_HANGAR   = 15
 FG_N        = 16

                        \ The fixed colours of the frame layer's lines and dots
                        \ (GLCOL and GDCOL hold these indices, gfx-frame.asm)

 FC_BLACK = 0
 FC_LASER = 1            \ our laser beams
 FC_ELASER = 2           \ enemy laser beams
 FC_PLINE = 3            \ planet meridians, equator and craters
 FC_PART = 4             \ explosion particles
 FC_SIGHT = 5            \ laser sights
 FC_STAR = 6             \ stardust

 MB_SX = MBOX + &50     \ The stars' x, y and size (1 to 3, 0 for none) in the
 MB_SY = MBOX + &68     \ rasteriser's mailbox (R_SX, R_SY and R_SS in
 MB_SS = MBOX + &80     \ gfx-rws.asm), which the game's star hooks write

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
                        \ the trampolines into bank R (gfx-glue.asm): at a
                        \ fixed address at the end of the resident block A
                        \ (&0724-&07BC), which includes it there, so that bank F
                        \ can be built against it

 DTMP = &07BD          \ Workspace for the dashboard's drawing routines, at
 DTMP2 = &07BE          \ the end of the resident block A (elite-resident.asm)
 DSTK = &07BF           \ The scanner stick's pixels (CPIX2 sets it for SCAN)

 LCOL = &A8             \ The colour of the next lines, pixels and characters
                        \ that the drawing routines draw on the space view: a
                        \ byte of four pixels of the colour (&0F cyan, &F0
                        \ magenta, &FF yellow), which they AND with their
                        \ pixels; in zero page at &A8, in the MOS's OSCLI
                        \ workspace (each drawing sets it first, and nothing
                        \ draws in a disc command)
