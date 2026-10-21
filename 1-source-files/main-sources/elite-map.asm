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
                        \ the screen, which the game clears after each load)

 QSL = &1200            \ The quarter squares, QS(n) = INT(n * n / 4) for n = 0
 QSH = &1400            \ to 511: their low bytes at QSL and high bytes at QSH,
                        \ two pages each, page aligned (their users index them
                        \ by an operand's low byte and pick the page by its
                        \ high bit), in main RAM where every bank's code can
                        \ read them; the loader puts them there, below the
                        \ screen and the staging area

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

 MBOX = &7E00           \ The rasteriser's mailbox (&7E00-&7EFF, between the
                        \ dashboard and the missile's blueprint): its callers'
                        \ inputs (gfx-rws.asm)

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
