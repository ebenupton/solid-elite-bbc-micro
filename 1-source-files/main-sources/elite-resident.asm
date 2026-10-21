\ ******************************************************************************
\
\ elite-resident.asm - the loader's resident block A, main RAM &0400-&07FF
\
\ Port (docs/memory-map.md): the original's loader put the recursive text
\ tokens (WORDS: QQ18, then SNE and ACT) at &0400-&07FF. The port puts QQ18 in
\ each program's cold bank, and this block in its place: the code that must
\ be visible whatever is paged at &8000-&BFFF, because it pages the banks
\ itself or because the MOS enters it with any ROM paged in:
\
\   * the far calls between a program's home and cold banks, and the bank
\     numbers that the loader found (elite-far.asm);
\
\   * PCLI, the game's OSCLI, which loads the programs and the blueprint
\     files into sideways RAM;
\
\   * WRCHR and BRKR, the WRCHV and BRKV handlers, which page the program's
\     home bank in and go on through its S% table, as the original's vectors
\     went through S% at &11E3;
\
\ then, at &07C0, the sine and arctan tables SNE and ACT, as in the original
\ (elite-text-tokens.asm's blocks tagged resident).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-far.asm"

\ ******************************************************************************
\
\       Name: PCLI
\       Type: Subroutine
\   Category: Loader
\    Summary: The game's OSCLI: load a program or a blueprint file into
\             sideways RAM, or pass a command to the MOS
\
\ ------------------------------------------------------------------------------
\
\ Port: both programs call OSCLI through here (OSCLI = PCLI in their
\ sources). The original's commands that load the programs ("L.T.CODE",
\ "R.T.CODE", "R.D.CODE") and the ship blueprints ("L.D.MOx") now load the
\ port's images instead, which DFS cannot load into sideways RAM itself (it
\ is paged in at &8000 while it loads): each is loaded into main RAM at
\ STAGE% and copied into its bank:
\
\   * "L.x.CODE" loads program x's home image (x.CODEH) into the home bank
\     and its cold image (x.CODEC) into the cold bank, and returns to the
\     caller's address, now in the new program's home bank (the flight
\     code's INBAY, which loads the docked code after a death, returns into
\     the docked code's INBAY, as in the original);
\
\   * "R.x.CODE" does the same and then runs the program at S%, as *RUN
\     did;
\
\   * "L.D.MOx" loads blueprint file D.MOx into the home bank's blueprint
\     slot, BPSLOT%.
\
\ Any other command (*CAT, *DELETE, *DIR) goes to the MOS. The command is
\ copied into main RAM first in every case, as the filing system reads it
\ with its own ROM paged in at &8000.
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   (Y X)               The command, terminated by a carriage return, in main
\                       RAM or in the caller's bank
\
\ ******************************************************************************

.PCLI

 STX pcs+1              \ Set the address in the LDA below to the command
 STY pcs+2

 LDA &F4                \ Note the caller's bank
 STA pbank

 LDX #0                 \ Copy the command into pcbuf, up to and including its
                        \ carriage return
.pcl1

.pcs

 LDA &FFFF,X            \ (the address is set above)
 STA pcbuf,X
 INX
 CMP #13
 BNE pcl1

 LDA pcbuf+1            \ A load or run of a file in a directory is "L.d.name"
 CMP #'.'               \ or "R.d.name": anything else goes to the MOS
 BNE pmos
 LDA pcbuf+3
 CMP #'.'
 BNE pmos

 LDA pcbuf+4            \ "x.CODE" is a program, "D.MOx" a blueprint file
 CMP #'C'
 BEQ pprog
 CMP #'M'
 BEQ pbp

.pmos

 LDX #LO(pcbuf)         \ Pass the command to the MOS's OSCLI, from main RAM
 LDY #HI(pcbuf)         \ (which pages the caller's bank back in from &F4 when
 JMP &FFF7              \ it has finished)

.pbp

 JSR pload              \ Load the blueprint file to STAGE%

 LDA BANKH              \ Copy its ten pages to the home bank's blueprint slot
 LDX #10
 LDY #HI(BPSLOT%)
 JSR bcopy

 JMP prest              \ Page the caller's bank back in and return

.pprog

 LDA #'H'               \ Load x.CODEH, the program's home image, to STAGE%
 STA pcbuf+8
 LDA #13
 STA pcbuf+9
 JSR pload

 LDA BANKH              \ Copy it into the home bank (64 pages: the whole bank,
 LDX #64                \ as STAGE% has room for it)
 LDY #HI(HOME%)
 JSR bcopy

 LDA #'C'               \ Load x.CODEC, the program's cold image, to STAGE%
 STA pcbuf+8
 JSR pload

 LDA BANKC              \ Copy it into the cold bank
 LDX #64
 LDY #&80
 JSR bcopy

 LDA pcbuf              \ If this is "L.", return to the caller (in the bank
 CMP #'R'               \ that was paged, which now holds the new program)
 BNE prest

 LDA BANKH              \ Otherwise run the program at S% in its home bank
 STA &F4
 STA VIA+&30
 JMP HOME%

.prest

 LDA pbank              \ Page the caller's bank back in and return
 STA &F4
 STA VIA+&30
 RTS

\ ******************************************************************************
\
\       Name: pload
\       Type: Subroutine
\   Category: Loader
\    Summary: Load the file named at pcbuf+2 to STAGE%
\
\ ******************************************************************************

.pload

 LDX #6                 \ Set up the OSFILE block (the filing system writes the
.pld1                   \ file's details into it, so it is set each time)
 LDA pblk0,X
 STA pblk,X
 DEX
 BPL pld1

 LDA #&FF               \ Call OSFILE with A = &FF to load the file to the
 LDX #LO(pblk)          \ address in the block, STAGE%
 LDY #HI(pblk)
 JMP &FFDD

.pblk0

 EQUW pcbuf+2           \ The file name
 EQUD STAGE%            \ The load address
 EQUB 0                 \ 0: load to the address in the block

\ ******************************************************************************
\
\       Name: bcopy
\       Type: Subroutine
\   Category: Loader
\    Summary: Copy pages from STAGE% into a sideways RAM bank
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   A                   The bank (ROMSEL)
\
\   X                   The number of pages to copy
\
\   Y                   The page in the bank to copy to
\
\ ******************************************************************************

.bcopy

 STY bc2+2              \ Set the destination page in the STA below

 LDY #HI(STAGE%)        \ Set the source page in the LDA below
 STY bc1+2

 STA &F4                \ Page the bank in
 STA VIA+&30

 LDY #0

.bc1

 LDA &FF00,Y            \ (the source page is set above)

.bc2

 STA &FF00,Y            \ (the destination page is set above)

 INY
 BNE bc1
 INC bc1+2
 INC bc2+2
 DEX
 BNE bc1

 RTS

\ ******************************************************************************
\
\       Name: WRCHR
\       Type: Subroutine
\   Category: Text
\    Summary: The WRCHV handler: print a character through the program's S%
\
\ ------------------------------------------------------------------------------
\
\ Port: WRCHV points here, and the MOS may call it with any ROM paged in (as
\ when DFS prints a catalogue). It pages the program's home bank in, calls
\ S%+6 (JMP TT26 in the flight code, JMP CHPR in the docked code), where the
\ original's WRCHV pointed, and pages the caller's ROM back in.
\
\ ******************************************************************************

.WRCHR

 PHA                    \ Store the character on the stack

 LDA &F4                \ Store the caller's ROM on the stack
 PHA

 LDA BANKH              \ Page the program's home bank in
 STA &F4
 STA VIA+&30

 TSX                    \ Fetch the character from the stack
 LDA &102,X

 JSR HOME%+6            \ Print it through S%+6

 PLA                    \ Page the caller's ROM back in
 STA &F4
 STA VIA+&30

 PLA                    \ Restore the character into A and return
 RTS

\ ******************************************************************************
\
\       Name: BRKR
\       Type: Subroutine
\   Category: Utility routines
\    Summary: The BRKV handler: go on to the program's handler through its S%
\
\ ------------------------------------------------------------------------------
\
\ Port: BRKV points here, and the MOS enters it with its language ROM paged
\ in. It pages the program's home bank in and jumps to S%+11, where the
\ original's BRKV pointed: JMP BRBR1, or (in the docked code, which changes
\ that JMP's address, BRKV = S%+12) JMP BRBR or JMP MEBRK.
\
\ ******************************************************************************

.BRKR

 LDA BANKH              \ Page the program's home bank in
 STA &F4
 STA VIA+&30

 JMP HOME%+11           \ Go on to the program's handler

.pbank

 EQUB 0                 \ PCLI: the caller's bank

.pblk

 SKIP 18                \ PCLI: the OSFILE block

.pcbuf

 SKIP 40                \ PCLI: the command

\ ******************************************************************************
\
\ The sine and arctan tables, SNE and ACT, at &07C0 and &07E0 as in the
\ original (elite-text-tokens.asm's blocks tagged resident)
\
\ ******************************************************************************

 PRINT "Resident block A: &0400-", ~P%-1, ", free ", &07C0-P%, " (then SNE and ACT)"
 ASSERT P% <= &07C0

 ORG &07C0

 INCLUDE "3-assembled-output/elite-tokens-resident.asm"

 ASSERT SNE = &07C0 AND ACT = &07E0 AND P% = &0800
