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

 JSR dfsin              \ Put DFS's workspace back at &1000-&10FF, where the
                        \ renderer's second screen buffer may have drawn over
                        \ it since the last disc command (dfsin, below)

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
 JSR &FFF7              \ it has finished)

 JMP dfsout             \ Keep DFS's workspace (and return; a command that
                        \ fails ends at BRKV instead, leaving the last copy)

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

 JSR dfsout             \ Otherwise keep DFS's workspace and run the program at
 LDA BANKH              \ S% in its home bank
 STA &F4
 STA VIA+&30
 JMP HOME%

.prest

 JSR dfsout             \ Keep DFS's workspace

 LDA pbank              \ Page the caller's bank back in and return
 STA &F4
 STA VIA+&30
 RTS

\ ******************************************************************************
\
\       Name: dfsin
\       Type: Subroutine
\   Category: Loader
\    Summary: Put DFS's workspace back before a disc command, and keep it
\             after one (dfsout)
\
\ ------------------------------------------------------------------------------
\
\ Port: the renderer's second screen buffer (BUF0%, &1000-&3FFF) covers
\ DFS's static workspace at &1000-&10FF, so PCLI keeps that page in the last
\ page of the cold bank (DFSSAVE%) between disc commands: dfsin copies it
\ back before each command, and dfsout copies it out after (the command
\ may have loaded new images into the banks: dfsout then rewrites the copy
\ in the new cold image's last page, which no image reaches). Until the
\ first dfsout (dfsok = 0), DFS's workspace has not been taken, and dfsin
\ leaves it. Both leave the caller's bank paged in.
\
\ ******************************************************************************

.dfsin

 LDA dfsok              \ If DFS's workspace has not been kept yet, leave it
 BEQ dfs3

 LDX #HI(DFSSAVE%)      \ Copy DFSSAVE% to &1000
 LDY #&10
 BNE dfs1               \ (this BNE is effectively a JMP)

.dfsout

 LDA #&FF               \ Note that DFS's workspace is kept
 STA dfsok

 LDX #&10               \ Copy &1000 to DFSSAVE%
 LDY #HI(DFSSAVE%)

.dfs1

 STX dfsa+2             \ Set the source page (X) in the LDA and the
 STY dfsb+2             \ destination page (Y) in the STA below

 LDA &F4                \ Page the cold bank in, keeping the paged bank on the
 PHA                    \ stack
 LDA BANKC
 STA &F4
 STA VIA+&30

 LDY #0

.dfs2

.dfsa

 LDA &FF00,Y            \ (the pages are set above)

.dfsb

 STA &FF00,Y

 INY
 BNE dfs2

 PLA                    \ Page the bank back in
 STA &F4
 STA VIA+&30

.dfs3

 RTS

.dfsok

 EQUB 0                 \ Non-zero once DFS's workspace has been kept

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

\ ******************************************************************************
\
\       Name: S1%
\       Type: Variable
\   Category: Save and load
\    Summary: The drive and directory number used when saving or loading a
\             commander file
\  Deep dive: Commander save files
\
\ ------------------------------------------------------------------------------
\
\ The drive part of this string (the "0") is updated with the chosen drive in
\ the GTNMEW routine, but the directory part (the "E") is fixed. The variable
\ is followed directly by the commander file at NA%, which starts with the
\ commander name, so the full string at S1% is in the format ":0.E.JAMESON",
\ which gives the full filename of the commander file.
\
\ ******************************************************************************

.S1%

 EQUS ":0.E."

\ ******************************************************************************
\
\       Name: NA%
\       Type: Variable
\   Category: Save and load
\    Summary: The data block for the last saved commander
\  Deep dive: Commander save files
\             The competition code
\
\ ------------------------------------------------------------------------------
\
\ Contains the last saved commander data, with the name at NA% and the data at
\ NA%+8 onwards. The size of the data block is given in NT% (which also includes
\ the two checksum bytes that follow this block). This block is initially set up
\ with the default commander, which can be maxed out for testing purposes by
\ setting Q% to TRUE.
\
\ The commander's name is stored at NA%, and can be up to 7 characters long
\ (the DFS filename limit). It is terminated with a carriage return character,
\ ASCII 13.
\
\ The offset of each byte within a saved commander file is also shown as #0, #1
\ and so on, so the kill tally, for example, is in bytes #71 and #72 of the
\ saved file. The related variable name from the current commander block is
\ also shown.
\
\ ******************************************************************************

.NA%

 EQUS "JAMESON"         \ The current commander name, which defaults to JAMESON
 EQUB 13                \
                        \ The commander name can be up to seven characters (the
                        \ DFS limit for filenames), and is terminated by a
                        \ carriage return

                        \ NA%+8 is the start of the commander data block
                        \
                        \ This block contains the last saved commander data
                        \ block. As the game is played it uses an identical
                        \ block at location TP to store the current commander
                        \ state, and that block is copied here when the game is
                        \ saved. Conversely, when the game starts up, the block
                        \ here is copied to TP, which restores the last saved
                        \ commander when we die
                        \
                        \ The initial state of this block defines the default
                        \ commander. Q% can be set to TRUE to give the default
                        \ commander lots of credits and equipment

 EQUB 0                 \ TP = Mission status, #0

 EQUB 20                \ QQ0 = Current system X-coordinate (Lave), #1
 EQUB 173               \ QQ1 = Current system Y-coordinate (Lave), #2

 EQUW &5A4A             \ QQ21 = Seed s0 for system 0, galaxy 0 (Tibedied), #3-4
 EQUW &0248             \ QQ21 = Seed s1 for system 0, galaxy 0 (Tibedied), #5-6
 EQUW &B753             \ QQ21 = Seed s2 for system 0, galaxy 0 (Tibedied), #7-8

IF Q%
 EQUD &00CA9A3B         \ CASH = Amount of cash (100,000,000 Cr), #9-12
ELSE
 EQUD &E8030000         \ CASH = Amount of cash (100 Cr), #9-12
ENDIF

 EQUB 70                \ QQ14 = Fuel level, #13

 EQUB 0                 \ COK = Competition flags, #14

 EQUB 0                 \ GCNT = Galaxy number, 0-7, #15

 EQUB POW+(128 AND Q%)  \ LASER = Front laser, #16

 EQUB (POW+128) AND Q%  \ LASER+1 = Rear laser, #17

 EQUB 0                 \ LASER+2 = Left laser, #18

 EQUB 0                 \ LASER+3 = Right laser, #19

 EQUW 0                 \ These bytes appear to be unused (they were originally
                        \ used for up/down lasers, but they were dropped),
                        \ #20-21

 EQUB 22 + (15 AND Q%)  \ CRGO = Cargo capacity, #22

 EQUB 0                 \ QQ20+0  = Amount of food in cargo hold, #23
 EQUB 0                 \ QQ20+1  = Amount of textiles in cargo hold, #24
 EQUB 0                 \ QQ20+2  = Amount of radioactives in cargo hold, #25
 EQUB 0                 \ QQ20+3  = Amount of slaves in cargo hold, #26
 EQUB 0                 \ QQ20+4  = Amount of liquor/Wines in cargo hold, #27
 EQUB 0                 \ QQ20+5  = Amount of luxuries in cargo hold, #28
 EQUB 0                 \ QQ20+6  = Amount of narcotics in cargo hold, #29
 EQUB 0                 \ QQ20+7  = Amount of computers in cargo hold, #30
 EQUB 0                 \ QQ20+8  = Amount of machinery in cargo hold, #31
 EQUB 0                 \ QQ20+9  = Amount of alloys in cargo hold, #32
 EQUB 0                 \ QQ20+10 = Amount of firearms in cargo hold, #33
 EQUB 0                 \ QQ20+11 = Amount of furs in cargo hold, #34
 EQUB 0                 \ QQ20+12 = Amount of minerals in cargo hold, #35
 EQUB 0                 \ QQ20+13 = Amount of gold in cargo hold, #36
 EQUB 0                 \ QQ20+14 = Amount of platinum in cargo hold, #37
 EQUB 0                 \ QQ20+15 = Amount of gem-stones in cargo hold, #38
 EQUB 0                 \ QQ20+16 = Amount of alien items in cargo hold, #39

 EQUB Q%                \ ECM = E.C.M. system, #40

 EQUB Q%                \ BST = Fuel scoops ("barrel status"), #41

 EQUB Q% AND 127        \ BOMB = Energy bomb, #42

 EQUB Q% AND 1          \ ENGY = Energy/shield level, #43

 EQUB Q%                \ DKCMP = Docking computer, #44

 EQUB Q%                \ GHYP = Galactic hyperdrive, #45

 EQUB Q%                \ ESCP = Escape pod, #46

 EQUD 0                 \ These four bytes appear to be unused, #47-50

 EQUB 3 + (Q% AND 1)    \ NOMSL = Number of missiles, #51

 EQUB 0                 \ FIST = Legal status ("fugitive/innocent status"), #52

 EQUB 16                \ AVL+0  = Market availability of food, #53
 EQUB 15                \ AVL+1  = Market availability of textiles, #54
 EQUB 17                \ AVL+2  = Market availability of radioactives, #55
 EQUB 0                 \ AVL+3  = Market availability of slaves, #56
 EQUB 3                 \ AVL+4  = Market availability of liquor/Wines, #57
 EQUB 28                \ AVL+5  = Market availability of luxuries, #58
 EQUB 14                \ AVL+6  = Market availability of narcotics, #59
 EQUB 0                 \ AVL+7  = Market availability of computers, #60
 EQUB 0                 \ AVL+8  = Market availability of machinery, #61
 EQUB 10                \ AVL+9  = Market availability of alloys, #62
 EQUB 0                 \ AVL+10 = Market availability of firearms, #63
 EQUB 17                \ AVL+11 = Market availability of furs, #64
 EQUB 58                \ AVL+12 = Market availability of minerals, #65
 EQUB 7                 \ AVL+13 = Market availability of gold, #66
 EQUB 9                 \ AVL+14 = Market availability of platinum, #67
 EQUB 8                 \ AVL+15 = Market availability of gem-stones, #68
 EQUB 0                 \ AVL+16 = Market availability of alien items, #69

 EQUB 0                 \ QQ26 = Random byte that changes for each visit to a
                        \ system, for randomising market prices, #70

 EQUW 0                 \ TALLY = Number of kills, #71-72

 EQUB 128               \ SVC = Save count, #73

\ ******************************************************************************
\
\       Name: CHK2
\       Type: Variable
\   Category: Save and load
\    Summary: Second checksum byte for the saved commander data file
\  Deep dive: Commander save files
\             The competition code
\
\ ------------------------------------------------------------------------------
\
\ Second commander checksum byte. If the default commander is changed, a new
\ checksum will be calculated and inserted by the elite-checksum.py script.
\
\ The offset of this byte within a saved commander file is also shown (it's at
\ byte #74).
\
\ ******************************************************************************

.CHK2

 EQUB &03 EOR &A9       \ The checksum value for the default commander, EOR'd
                        \ with &A9 to make it harder to tamper with the checksum
                        \ byte, #74

\ ******************************************************************************
\
\       Name: CHK
\       Type: Variable
\   Category: Save and load
\    Summary: First checksum byte for the saved commander data file
\  Deep dive: Commander save files
\             The competition code
\
\ ------------------------------------------------------------------------------
\
\ Commander checksum byte. If the default commander is changed, a new checksum
\ will be calculated and inserted by the elite-checksum.py script.
\
\ The offset of this byte within a saved commander file is also shown (it's at
\ byte #75).
\
\ ******************************************************************************

.CHK

 EQUB &03               \ The checksum value for the default commander, #75

\ ******************************************************************************
\
\       Name: BRBR1
\       Type: Subroutine
\   Category: Loader
\    Summary: Loader break handler: print a newline and the error message, and
\             then hang the computer
\  Deep dive: Swapping between the docked and flight code
\
\ ------------------------------------------------------------------------------
\
\ This break handler is used during loading and during flight, and is resident
\ in memory throughout the game's lifecycle. The docked code loads its own
\ break handler and overrides this one until the flight code is run.
\
\ The main difference between the two handlers is that this one display the
\ error and then hangs, while the docked code displays the error and returns.
\ This is because the docked code has to cope gracefully with errors from the
\ disc access menu (such as "File not found"), which we obviously don't want to
\ terminate the game.
\
\ ******************************************************************************

.BRBR1

                        \ The following loop prints out the null-terminated
                        \ message pointed to by (&FD &FE), which is the MOS
                        \ error message pointer - so this prints the error
                        \ message on the next line

 LDY #0                 \ Set Y = 0 to act as a character counter

 LDA #13                \ Set A = 13 so the first character printed is a
                        \ carriage return

.BRBRLOOP

 JSR OSWRCH             \ Print the character in A (which contains a carriage
                        \ return on the first loop iteration), and then any
                        \ characters we fetch from the error message

 INY                    \ Increment the loop counter

 LDA (&FD),Y            \ Fetch the Y-th byte of the block pointed to by
                        \ (&FD &FE), so that's the Y-th character of the message
                        \ pointed to by the MOS error message pointer

 BNE BRBRLOOP           \ If the fetched character is non-zero, loop back to the
                        \ JSR OSWRCH above to print the it, and keep looping
                        \ until we fetch a zero (which marks the end of the
                        \ message)

 BEQ P%                 \ Hang the computer as something has gone wrong

\ ******************************************************************************
\
\       Name: IRQG
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: The game's interrupt handler: the vertical sync
\
\ ------------------------------------------------------------------------------
\
\ Port: the screen is one MODE 1 frame in four fixed colours (SCREEN% and
\ PANEL%, elite-map.asm), so there is no split to make: the original's IRQ1
\ switched to mode 5 and the dashboard's palette at timer 1 and back at the
\ vertical sync (LINSCN, in the loader's block B, which still runs the
\ loading screen). This handles the vertical sync as LINSCN did, without the
\ mode: it sets DL for WSCAN, writes the palette (which the energy bomb's
\ flash changes for a frame) and decrements LASCT; everything else, timer 1
\ included (the MOS's 100 Hz clock, which the game no longer takes), goes to
\ the MOS's handler. The loader's LOAD routine installs it.
\
\ ******************************************************************************

.IRQG

 LDA #%00000010         \ If this is not the vertical sync (CA1), pass it to the
 BIT VIA+&4D            \ MOS, through IRQMOS (the original's handler kept the
 BNE irqv               \ MOS's vector in VEC, at &7FFE, which the docked code
 JMP (IRQMOS)           \ overwrites: the original only rarely needed it)

.irqv

 TYA                    \ Store Y on the stack
 PHA

 LDA #30                \ Set the line scan counter to a non-zero value, as
 STA DL                 \ LINSCN did, so WSCAN can wait for it to change

 LDY #15                \ Write the palette, PALCMYK's sixteen bytes

.irqp

 LDA PALCMYK,Y
 STA VIA+&21
 DEY
 BPL irqp

 LDA LASCT              \ Decrement the value of LASCT, but if we go too far
 BEQ P%+5               \ and it becomes negative, bump it back up again (this
                        \ controls the pulsing of pulse lasers)

.LASDEC

 DEC LASCT

 PLA                    \ Restore Y from the stack
 TAY

 LDA VIA+&41            \ Read the System VIA's IRA to clear the CA1 interrupt

 LDA &FC                \ Restore A from the MOS's save register and return
 RTI                    \ (the vertical sync is not passed to the MOS, as in
                        \ the original, so the MOS never rewrites the ULA)

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
\
\ ******************************************************************************

.IRQMOS

 EQUW 0                 \ The MOS's IRQ1V handler, which IRQG passes interrupts
                        \ on to (the loader's LOAD routine sets it from VEC)

.PALCMYK

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

 PRINT "Resident block A: &0400-", ~P%-1, ", free ", DTMP-P%, " (then the dashboard's workspace, SNE and ACT)"
 ASSERT P% <= DTMP

 ORG &07C0

 INCLUDE "3-assembled-output/elite-tokens-resident.asm"

 ASSERT SNE = &07C0 AND ACT = &07E0 AND P% = &0800
