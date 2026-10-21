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
\ where both programs' blueprint tables point.
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

 STAGE% = &1200         \ Where files are loaded before they are copied into
                        \ their bank (main RAM &1200 to &51FF, below the screen)

 QSL = &5C00            \ The quarter squares, QS(n) = INT(n * n / 4) for n = 0
 QSH = &5E00            \ to 511: their low bytes at QSL and high bytes at QSH,
                        \ two pages each, page aligned (their users index them
                        \ by an operand's low byte and pick the page by its
                        \ high bit), in main RAM where every bank's code can
                        \ read them; the loader puts them there (main RAM &5C00
                        \ to &5FFF is free below the original's screen)
