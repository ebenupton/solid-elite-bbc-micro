\ ******************************************************************************
\
\ BBC MICRO DISC ELITE GAME LOADER SOURCE (PART 3 OF 3)
\
\ BBC Micro disc Elite was written by Ian Bell and David Braben and is copyright
\ Acornsoft 1984
\
\ The code in this file has been reconstructed from a disassembly of the version
\ released on Ian Bell's personal website at http://www.elitehomepage.org/
\
\ The commentary is copyright Mark Moxon, and any misunderstandings or mistakes
\ in the documentation are entirely my fault
\
\ The terminology and notations used in this commentary are explained at
\ https://elite.bbcelite.com/terminology
\
\ The deep dive articles referred to in this commentary can be found at
\ https://elite.bbcelite.com/deep_dives
\
\ ------------------------------------------------------------------------------
\
\ This source file contains the third of three game loaders for BBC Micro disc
\ Elite.
\
\ ------------------------------------------------------------------------------
\
\ This source file produces the following binary file:
\
\   * ELITE4.bin
\
\ after reading in the following files:
\
\   * P.DIALS.bin
\   * MISSILE.bin
\   * WORDS.bin
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-build-options.asm"

 INCLUDE "1-source-files/main-sources/elite-map.asm"    \ Port: the memory map

 _IB_DISC               = (_VARIANT = 1)
 _STH_DISC              = (_VARIANT = 2)
 _SRAM_DISC             = (_VARIANT = 3)

 GUARD &6000            \ Guard against assembling over screen memory

\ ******************************************************************************
\
\ Configuration variables
\
\ ******************************************************************************

 CODE% = &1900          \ The address where the code will be run

 LOAD% = &1900          \ The address where the code will be loaded

 Q% = _MAX_COMMANDER    \ Set Q% to TRUE to max out the default commander, FALSE
                        \ for the standard default commander

 N% = 67                \ N% is set to the number of bytes in the VDU table, so
                        \ we can loop through them below

 VSCAN = 57             \ Defines the split position in the split-screen mode

 POW = 15               \ Pulse laser power

 VEC = &7FFE            \ VEC is where we store the original value of the IRQ1
                        \ vector, matching the address in the elite-missile.asm
                        \ source

 BRKV = &0202           \ The break vector that we intercept to enable us to
                        \ handle and display system errors

 IRQ1V = &0204          \ The IRQ1V vector that we intercept to implement the
                        \ split-screen mode

 WRCHV = &020E          \ The WRCHV vector that we intercept with our custom
                        \ text printing routine

 NETV = &0224           \ The NETV vector that we intercept as part of the copy
                        \ protection

 LASCT = &0346          \ The laser pulse count for the current laser, matching
                        \ the address in the main game code

 HFX = &0348            \ A flag that toggles the hyperspace colour effect,
                        \ matching the address in the main game code

 ESCP = &0386           \ The flag that determines whether we have an escape pod
                        \ fitted, matching the address in the main game code

 S% = HOME%            \ The address of the main entry point workspace in the
                        \ main game code

 VIA = &FE00            \ Memory-mapped space for accessing internal hardware,
                        \ such as the video ULA, 6845 CRTC and 6522 VIAs (also
                        \ known as SHEILA)

 OSWRCH = &FFEE         \ The address for the OSWRCH routine

 OSBYTE = &FFF4         \ The address for the OSBYTE routine

 OSWORD = &FFF1         \ The address for the OSWORD routine

 OSCLI = &FFF7          \ The address for the OSCLI vector

\ ******************************************************************************
\
\       Name: ZP
\       Type: Workspace
\    Address: &0070 to &008B
\   Category: Workspaces
\    Summary: Important variables used by the loader
\
\ ******************************************************************************

IF _SRAM_DISC OR _STH_DISC

 ORG &0004              \ Set the assembly address to &0004

.TRTB%

 SKIP 2                 \ Contains the address of the keyboard translation
                        \ table, which is used to translate internal key
                        \ numbers to ASCII

ENDIF

 ORG &0070              \ Set the assembly address to &0070

.ZP

 SKIP 2                 \ Stores addresses used for moving content around

.P

 SKIP 1                 \ Temporary storage, used in a number of places

.Q

 SKIP 1                 \ Temporary storage, used in a number of places

.YY

 SKIP 1                 \ Temporary storage, used in a number of places

.T

 SKIP 1                 \ Temporary storage, used in a number of places

.SC

 SKIP 1                 \ Screen address (low byte)
                        \
                        \ Elite draws on-screen by poking bytes directly into
                        \ screen memory, and SC(1 0) is typically set to the
                        \ address of the character block containing the pixel
                        \ we want to draw

.SCH

 SKIP 1                 \ Screen address (high byte)

.CHKSM

 SKIP 2                 \ Used in the copy protection code

 ORG &008B              \ Set the assembly address to &008B

.DL

 SKIP 1                 \ Vertical sync flag
                        \
                        \ DL gets set to 30 every time we reach vertical sync on
                        \ the video system, which happens 50 times a second
                        \ (50Hz). The WSCAN routine uses this to pause until the
                        \ vertical sync, by setting DL to 0 and then monitoring
                        \ its value until it changes to 30

\ ******************************************************************************
\
\ ELITE LOADER
\
\ ******************************************************************************

 ORG CODE%              \ Set the assembly address to CODE%

\ ******************************************************************************
\
\       Name: B%
\       Type: Variable
\   Category: Drawing the screen
\    Summary: VDU commands for setting the square mode 4 screen
\  Deep dive: The split-screen mode in BBC Micro Elite
\             Drawing monochrome pixels on the BBC Micro
\
\ ------------------------------------------------------------------------------
\
\ This block contains the bytes that get written by OSWRCH to set up the screen
\ mode (this is equivalent to using the VDU statement in BASIC).
\
\ It defines the whole screen using a square, monochrome mode 4 configuration;
\ the mode 5 part for the dashboard is implemented in the IRQ1 routine.
\
\ The top part of Elite's screen mode is based on mode 4 but with the following
\ differences:
\
\   * 32 columns, 31 rows (256 x 248 pixels) rather than 40, 32
\
\   * The horizontal sync position is at character 45 rather than 49, which
\     pushes the screen to the right (which centres it as it's not as wide as
\     the normal screen modes)
\
\   * Screen memory goes from &6000 to &7EFF, which leaves another whole page
\     for code (i.e. 256 bytes) after the end of the screen. This is where the
\     Python ship blueprint slots in
\
\   * The text window is 1 row high and 13 columns wide, and is at (2, 16)
\
\   * The cursor is disabled
\
\ This almost-square mode 4 variant makes life a lot easier when drawing to the
\ screen, as there are 256 pixels on each row (or, to put it in screen memory
\ terms, there's one page of memory per row of pixels).
\
\ There is also an interrupt-driven routine that switches the bytes-per-pixel
\ setting from that of mode 4 to that of mode 5, when the raster reaches the
\ split between the space view and the dashboard.
\
\ ******************************************************************************

.B%

 EQUB 22, 4             \ Switch to screen mode 4

 EQUB 28                \ Define a text window as follows:
 EQUB 2, 17, 15, 16     \
                        \   * Left = 2
                        \   * Right = 15
                        \   * Top = 16
                        \   * Bottom = 17
                        \
                        \ i.e. 1 row high, 13 columns wide at (2, 16)

 EQUB 23, 0, 6, 31      \ Set 6845 register R6 = 31
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "vertical displayed" register, and sets
                        \ the number of displayed character rows to 31. For
                        \ comparison, this value is 32 for standard modes 4 and
                        \ 5, but we claw back the last row for storing code just
                        \ above the end of screen memory

 EQUB 23, 0, 12, &0C    \ Set 6845 register R12 = &0C and R13 = &00
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This sets 6845 registers (R12 R13) = &0C00 to point
 EQUB 23, 0, 13, &00    \ to the start of screen memory in terms of character
 EQUB 0, 0, 0           \ rows. There are 8 pixel lines in each character row,
 EQUB 0, 0, 0           \ so to get the actual address of the start of screen
                        \ memory, we multiply by 8:
                        \
                        \   &0C00 * 8 = &6000
                        \
                        \ So this sets the start of screen memory to &6000

 EQUB 23, 0, 1, 32      \ Set 6845 register R1 = 32
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "horizontal displayed" register, which
                        \ defines the number of character blocks per horizontal
                        \ character row. For comparison, this value is 40 for
                        \ modes 4 and 5, but our custom screen is not as wide at
                        \ only 32 character blocks across

 EQUB 23, 0, 2, 45      \ Set 6845 register R2 = 45
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "horizontal sync position" register, which
                        \ defines the position of the horizontal sync pulse on
                        \ the horizontal line in terms of character widths from
                        \ the left-hand side of the screen. For comparison this
                        \ is 49 for modes 4 and 5, but needs to be adjusted for
                        \ our custom screen's width

 EQUB 23, 0, 10, 32     \ Set 6845 register R10 = %00100000 = 32
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "cursor start" register, and bits 5 and 6
                        \ define the "cursor display mode", as follows:
                        \
                        \   * %00 = steady, non-blinking cursor
                        \
                        \   * %01 = do not display a cursor
                        \
                        \   * %10 = fast blinking cursor (blink at 1/16 of the
                        \           field rate)
                        \
                        \   * %11 = slow blinking cursor (blink at 1/32 of the
                        \           field rate)
                        \
                        \ We can therefore turn off the cursor completely by
                        \ setting cursor display mode %01, with bit 6 of R10
                        \ clear and bit 5 of R10 set

\ ******************************************************************************
\
\       Name: E%
\       Type: Variable
\   Category: Sound
\    Summary: Sound envelope definitions
\
\ ------------------------------------------------------------------------------
\
\ This table contains the sound envelope data, which is passed to OSWORD by the
\ FNE macro to create the four sound envelopes used in-game. Refer to chapter 30
\ of the "BBC Microcomputer User Guide" by John Coll for details of sound
\ envelopes and what all the parameters mean.
\
\ The envelopes are as follows:
\
\   * Envelope 1 is the sound of our own laser firing
\
\   * Envelope 2 is the sound of lasers hitting us, or hyperspace
\
\   * Envelope 3 is the first sound in the two-part sound of us dying, or the
\     second sound in the two-part sound of us hitting or killing an enemy ship
\
\   * Envelope 4 is the sound of E.C.M. firing
\
\ ******************************************************************************

.E%

 EQUB 1, 1, 0, 111, -8, 4, 1, 8, 8, -2, 0, -1, 126, 44
 EQUB 2, 1, 14, -18, -1, 44, 32, 50, 6, 1, 0, -2, 120, 126
 EQUB 3, 1, 1, -1, -3, 17, 32, 128, 1, 0, 0, -1, 1, 1
 EQUB 4, 1, 4, -8, 44, 4, 6, 8, 22, 0, 0, -127, 126, 0

\ ******************************************************************************
\
\       Name: FNE
\       Type: Macro
\   Category: Sound
\    Summary: Macro definition for defining a sound envelope
\
\ ------------------------------------------------------------------------------
\
\ The following macro is used to define the four sound envelopes used in the
\ game. It uses OSWORD 8 to create an envelope using the 14 parameters in the
\ I%-th block of 14 bytes at location E%. This OSWORD call is the same as BBC
\ BASIC's ENVELOPE command.
\
\ See variable E% for more details of the envelopes themselves.
\
\ ******************************************************************************

MACRO FNE I%

 LDX #LO(E%+I%*14)      \ Set (Y X) to point to the I%-th set of envelope data
 LDY #HI(E%+I%*14)      \ in E%

 LDA #8                 \ Call OSWORD with A = 8 to set up sound envelope I%
 JSR OSWORD

ENDMACRO

\ ******************************************************************************
\
\       Name: Elite loader (Part 1 of 3)
\       Type: Subroutine
\   Category: Loader
\    Summary: Set up the split screen mode, move code around, set up the sound
\             envelopes and configure the system
\
\ ******************************************************************************

.ENTRY

IF _STH_DISC OR _IB_DISC

                        \ Port: the copy protection's checksums (PROT1, PROT2,
                        \ PROT3, CHECK, OSBmod) are gone, and the port does the
                        \ setup that the first two loaders (ELITE2 and ELITE3,
                        \ which the port does not use) did for the game

 LDA #119               \ Call OSBYTE with A = 119 to close any *SPOOL or *EXEC
 JSR OSBYTE             \ files, as ELITE2 did

 LDA #172               \ Call OSBYTE 172 to read the address of the MOS
 LDX #0                 \ keyboard translation table into (Y X), and store it
 LDY #&FF               \ in TRTB%(1 0), as ELITE3 did
 JSR OSBYTE
 STX TRTB%
 STY TRTB%+1

ELIF _SRAM_DISC

 JSR PROT4              \ Fetch the address of the keyboard translation table
                        \ before calling PROT1 to calculate checksums into CHKSM

ENDIF

IF _INTERLACE_FIX

 LDA #144               \ Call OSBYTE with A = 144, X = 255 and Y set to the
 LDX #255               \ current interlace setting (which the MOS stores at
 LDY &0291              \ &0291), so this moves the screen down one line but
 JSR OSBYTE             \ without changing the interlace

ELSE

 LDA #144               \ Call OSBYTE with A = 144, X = 255 and Y = 0 to move
 LDX #255               \ the screen down one line and turn screen interlace on
 JSR OSB

ENDIF

 LDA #LO(B%)            \ Set the low byte of ZP(1 0) to point to the VDU code
 STA ZP                 \ table at B%

 LDA #HI(B%)            \ Set the high byte of ZP(1 0) to point to the VDU code
 STA ZP+1               \ table at B%

 LDY #0                 \ We are now going to send the N% VDU bytes in the table
                        \ at B% to OSWRCH to set up the special mode 4 screen
                        \ that forms the basis for the split-screen mode

.loop1

 LDA (ZP),Y             \ Pass the Y-th byte of the B% table to OSWRCH
 JSR OSWRCH

 INY                    \ Increment the loop counter

 CPY #N%                \ Loop back for the next byte until we have done them
 BNE loop1              \ all (the number of bytes was set in N% above)

 JSR PLL1               \ Call PLL1 to draw Saturn

 LDA #16                \ Call OSBYTE with A = 16 and X = 3 to set the ADC to
 LDX #3                 \ sample 3 channels from the joystick/Bitstik
 JSR OSBYTE

 LDA #&60               \ Store an RTS instruction in location &0232
 STA &0232

 LDA #&02               \ Point the NETV vector to &0232, which we just filled
 STA NETV+1             \ with an RTS
 LDA #&32
 STA NETV

 LDA #190               \ Call OSBYTE with A = 190, X = 8 and Y = 0 to set the
 LDX #8                 \ ADC conversion type to 8 bits, for the joystick
 JSR OSB

IF _STH_DISC OR _IB_DISC

 LDA #200               \ Call OSBYTE with A = 200, X = 0 and Y = 0 to enable
 LDX #0                 \ the ESCAPE key and disable memory clearing if the
 JSR OSB                \ BREAK key is pressed

ELIF _SRAM_DISC

 LDA #219               \ Store 219 in location &9F. This gets checked by the
 STA &9F                \ TITLE routine in the main docked code as part of the
                        \ copy protection (the game hangs if it doesn't match)
                        \
                        \ This is normally done in the OSBmod routine, but the
                        \ sideways RAM variant doesn't call OSBmod as that part
                        \ of the copy protection is disabled, so we set the
                        \ value of location &BF here instead

 NOP                    \ Pad out the code so it takes up the same amount of
 NOP                    \ space as in the original version
 NOP

ENDIF

 LDA #13                \ Call OSBYTE with A = 13, X = 0 and Y = 0 to disable
 LDX #0                 \ the "output buffer empty" event
 JSR OSB

 LDA #225               \ Call OSBYTE with A = 225, X = 128 and Y = 0 to set
 LDX #128               \ the function keys to return ASCII codes for SHIFT-fn
 JSR OSB                \ keys (i.e. add 128)

 LDA #12                \ Set A = 12 and X = 0 to pretend that this is an
 LDX #0                 \ innocent call to OSBYTE to reset the keyboard delay
                        \ and auto-repeat rate to the default, when in reality
                        \ the OSB address in the next instruction gets modified
                        \ to point to OSBmod

.OSBjsr

IF _STH_DISC OR _IB_DISC

 LDA #219               \ Port: store 219 in location &9F, which the TITLE
 STA &9F                \ routine in the main docked code checks as part of the
                        \ copy protection (the original's OSBmod, which this
                        \ JSR was modified to call, did this after a checksum)

ELIF _SRAM_DISC

 NOP                    \ The sideways RAM variant has this part of the copy
 NOP                    \ protection disabled, so pad out the code so it takes
 NOP                    \ up the same amount of space as in the original version

ENDIF

 LDA #13                \ Call OSBYTE with A = 13, X = 2 and Y = 0 to disable
 LDX #2                 \ the "character entering buffer" event
 JSR OSB

 LDA #4                 \ Call OSBYTE with A = 4, X = 1 and Y = 0 to disable
 LDX #1                 \ cursor editing, so the cursor keys return ASCII values
 JSR OSB                \ and can therefore be used in-game

 LDA #9                 \ Call OSBYTE with A = 9, X = 0 and Y = 0 to disable
 LDX #0                 \ flashing colours
 JSR OSB

 \ Port: no PROT3, as there is no copy protection

 LDA #&00               \ Set the following:
 STA ZP                 \
 LDA #&11               \   ZP(1 0) = &1100
 STA ZP+1               \   P(1 0) = TVT1code
 LDA #LO(TVT1code)
 STA P
 LDA #HI(TVT1code)
 STA P+1

 JSR MVPG               \ Call MVPG to move and decrypt a page of memory from
                        \ TVT1code to &1100-&11FF

 LDA #&00               \ Set the following:
 STA ZP                 \
 LDA #&78               \   ZP(1 0) = &7800
 STA ZP+1               \   P(1 0) = DIALS
 LDA #LO(DIALS)         \   X = 8
 STA P
 LDA #HI(DIALS)
 STA P+1
 LDX #8

 JSR MVBL               \ Call MVBL to move 8 pages of memory from DIALS to
                        \ &7800-&7FFF (Port: not encrypted)

IF _INTERLACE_FIX

 LDA &0291              \ If interlace is on then the MOS will have set &0291 to
 BEQ lace1              \ zero, so jump to lace1 to skip the following

                        \ If we get here then interlace is off, so we modify the
                        \ split-screen interrupt timer from (57 30) to (56 238)
                        \ to ensure a clean transition between the space view
                        \ and dashboard, using figures derived by Patrick Moore

 LDA #238               \ Modify the LDA #30 instruction in LINSCN to LDA #238
 STA LINSCN+1           \ to change the low-order T1 count to 238

 LDA #56                \ Modify the LDA #VSCAN instruction in LINSCN to LDA #56
 STA LINSCN+8           \ to change the high-order T1 count to 56

 STA lace2+1            \ Modify the LDA #VSCAN instruction at lace2 to LDA #56
                        \ to change the high-order T1 count to 56

.lace1

ENDIF

 SEI                    \ Disable interrupts while we set up our interrupt
                        \ handler to support the split-screen mode

 LDA VIA+&44            \ Read the 6522 System VIA T1C-L timer 1 low-order
 STA &0001              \ counter (SHEILA &44), which decrements one million
                        \ times a second and will therefore be pretty random,
                        \ and store it in location &0001, which is among the
                        \ main game code's random seeds (so this seeds the
                        \ random number generator for the main game)

 LDA #%00111001         \ Set 6522 System VIA interrupt enable register IER
 STA VIA+&4E            \ (SHEILA &4E) bits 0 and 3-5 (i.e. disable the Timer1,
                        \ CB1, CB2 and CA2 interrupts from the System VIA)

 LDA #%01111111         \ Set 6522 User VIA interrupt enable register IER
 STA VIA+&6E            \ (SHEILA &6E) bits 0-7 (i.e. disable all hardware
                        \ interrupts from the User VIA)

 LDA IRQ1V              \ Copy the current IRQ1V vector address into VEC(1 0)
 STA VEC
 LDA IRQ1V+1
 STA VEC+1

 LDA #LO(IRQ1)          \ Set the IRQ1V vector to IRQ1, so IRQ1 is now the
 STA IRQ1V              \ interrupt handler
 LDA #HI(IRQ1)
 STA IRQ1V+1

IF _INTERLACE_FIX

.lace2

ENDIF

 LDA #VSCAN             \ Set 6522 System VIA T1C-L timer 1 high-order counter
 STA VIA+&45            \ (SHEILA &45) to VSCAN (57) to start the T1 counter
                        \ counting down from 14622 at a rate of 1 MHz

 CLI                    \ Re-enable interrupts

 LDA #&00               \ Set the following:
 STA ZP                 \
 LDA #&61               \   ZP(1 0) = &6100
 STA ZP+1               \   P(1 0) = ASOFT
 LDA #LO(ASOFT)
 STA P
 LDA #HI(ASOFT)
 STA P+1

 JSR MVPG               \ Call MVPG to move and decrypt a page of memory from
                        \ ASOFT to &6100-&61FF

 LDA #&63               \ Set the following:
 STA ZP+1               \
 LDA #LO(ELITE)         \   ZP(1 0) = &6300
 STA P                  \   P(1 0) = ELITE
 LDA #HI(ELITE)
 STA P+1

 JSR MVPG               \ Call MVPG to move and decrypt a page of memory from
                        \ ELITE to &6300-&63FF

 LDA #&76               \ Set the following:
 STA ZP+1               \
 LDA #LO(CpASOFT)       \   ZP(1 0) = &7600
 STA P                  \   P(1 0) = CpASOFT
 LDA #HI(CpASOFT)
 STA P+1

 JSR MVPG               \ Call MVPG to move and decrypt a page of memory from
                        \ CpASOFT to &7600-&76FF

 LDA #&00               \ Set the following:
 STA ZP                 \
 LDA #&04               \   ZP(1 0) = &0400
 STA ZP+1               \   P(1 0) = RESAcode
 LDA #LO(RESAcode)      \   X = 4
 STA P
 LDA #HI(RESAcode)
 STA P+1
 LDX #4

 JSR MVBL               \ Call MVBL to move 4 pages of memory from RESAcode to
                        \ &0400-&07FF (Port: the resident block A, in the place
                        \ of the original's WORDS, docs/memory-map.md)

 JSR PROBE              \ Port: find four sideways RAM banks for the game

                        \ Port: make the quarter squares, QS(n) = INT(n * n / 4)
                        \ for n = 0 to 511, at the top of the home bank (QSL,
                        \ QSH: elite-map.asm), where they stay: each program's
                        \ home image ends below them. QS(n) = QS(n - 1) +
                        \ INT(n / 2), summed in ZP(1 0)

 LDA &F4                \ Page the home bank in, keeping the paged ROM on the
 PHA                    \ stack
 LDA BANK4
 STA &F4
 STA VIA+&30

 LDA #0                 \ ZP(1 0) = QS(0) = 0
 STA ZP
 STA ZP+1

FOR I%, 0, 1            \ n = 256 * I% + X

 TAX                    \ (A = 0 here: X = 0)

{
.qs1

 TXA                    \ A = INT(n / 2) = 128 * I% + INT(X / 2)
 LSR A
 ORA #128 * I%

 CLC                    \ ZP(1 0) = ZP(1 0) + INT(n / 2) = QS(n)
 ADC ZP
 STA ZP
 STA QSL + 256 * I%,X
 LDA ZP+1
 ADC #0
 STA ZP+1
 STA QSH + 256 * I%,X

 INX
 BNE qs1

 TXA                    \ (A = 0 for the next half)
}

NEXT

 PLA                    \ Page the ROM back in
 STA &F4
 STA VIA+&30

 LDX #35                \ We now want to copy the disc catalogue routine from
                        \ CATDcode to CATD, so set a counter in X for the 36
                        \ bytes to copy

.loop2

 LDA CATDcode,X         \ Copy the X-th byte of CATDcode to the X-th byte of
 STA CATD,X             \ CATD

 DEX                    \ Decrement the loop counter

 BPL loop2              \ Loop back to copy the next byte until they are all
                        \ done

 \ Port: the drive number in the CATD routine stays 0, the drive the game
                        \ boots from (ELITE3 set &76 to it, and the original copied
                        \ &76 into CATBLOCK here)

 FNE 0                  \ Set up sound envelopes 0-3 using the FNE macro
 FNE 1
 FNE 2
 FNE 3

 LDX #LO(MESS1)         \ Set (Y X) to point to MESS1 ("DIR E")
 LDY #HI(MESS1)

 JSR OSCLI              \ Call OSCLI to run the OS command in MESS1, which
                        \ changes the disc directory to E

 LDA #LO(LOAD)          \ Set the following:
 STA ZP                 \
 LDA #HI(LOAD)          \   ZP(1 0) = LOAD
 STA ZP+1               \   P(1 0) = LOADcode
 LDA #LO(LOADcode)
 STA P
 LDA #HI(LOADcode)
 STA P+1

 LDY #0                 \ We now want to move and decrypt one page of memory
                        \ from LOADcode to LOAD, so set Y as a byte counter

.loop3

 LDA (P),Y              \ Fetch the Y-th byte of the P(1 0) memory block (Port:
                        \ not encrypted)

 STA (ZP),Y             \ Store the result in the Y-th byte of the ZP(1 0)
                        \ memory block

 DEY                    \ Decrement the byte counter

 BNE loop3              \ Loop back to copy the next byte until we have done a
                        \ whole page of 256 bytes

 INC P+1                \ Port: and a second page (LOAD loads the renderer's
 INC ZP+1               \ banks too), to &0C00-&0CFF, which is free until the
 LDA ZP+1               \ game starts
 CMP #HI(LOAD) + 2
 BNE loop3

 JMP LOAD               \ Jump to the start of the routine we just decrypted

\ ******************************************************************************
\
\       Name: CHECK
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Calculate a checksum from two 256-byte portions of the loader code
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: LOADcode
\       Type: Subroutine
\   Category: Loader
\    Summary: Encrypted LOAD routine, bundled up in the loader so it can be
\             moved to &0B00 to be run
\
\ ------------------------------------------------------------------------------
\
\ This section is encrypted by EOR'ing with &18. The encryption is done by the
\ elite-checksum.py script, and decryption is done in part 1 above, at the same
\ time as it is moved to &0B00.
\
\ ******************************************************************************

.LOADcode

 ORG &0B00              \ Set the assembly address to &0B00

\ ******************************************************************************
\
\       Name: LOAD
\       Type: Subroutine
\   Category: Loader
\    Summary: Load the main docked code, set up various vectors, run a checksum
\             and start the game
\
\ ------------------------------------------------------------------------------
\
\ This routine also contains a hidden message from the authors for potential
\ crackers to enjoy:
\
\   Does your mother know you do this?
\
\ I bet this made quite a few people smile back in the day...
\
\ ******************************************************************************

.LOAD

 LDX #0                 \ Port: copy the rupture's code to RUPT% (its pages,
                        \ elite-rupture.asm), while the loader's image is still
.rpl                    \ in memory

FOR I%, 0, RUPTPG - 1
 LDA RUPTcode + I% * 256,X
 STA RUPT% + I% * 256,X
NEXT
 INX
 BNE rpl

 LDX #(RESH_END - RESH% - 1)  \ Port: copy the high resident block to RESH%
                        \ (elite-resident-high.asm), with the palette and the
.rhl                    \ rupture's registers, first, while the loader's image
                        \ is still in memory (the loads below go through
 LDA RESHcode,X         \ STAGE%, over it)
 STA RESH%,X
 DEX
 BPL rhl

                        \ Port: load the renderer's two banks, the rasteriser
                        \ R.BANK into bank 5 and the frame layer F.BANK into
                        \ bank 6, each to STAGE% and then into its bank, as
                        \ PCLI loads a program's images (before the first disc
                        \ command through PCLI, so that DFS's workspace at
                        \ &1000 is still DFS's own)

 LDX #(LRBK_END - LRBK - 1)  \ Put "R.BANK" in PCLI's command buffer, for pload

.lbk1

 LDA LRBK,X
 STA pcbuf,X
 DEX
 BPL lbk1

 JSR pload              \ Load R.BANK to STAGE% and copy it into bank 5
 LDA BANK5
 LDX #64
 LDY #&80
 JSR bcopy

 LDA #'F'               \ Load F.BANK to STAGE% and copy it into bank 6
 STA pcbuf+2
 JSR pload
 LDA BANK6
 LDX #64
 LDY #&80
 JSR bcopy

 LDX #FG_INIT           \ Start the frame layer: direct mode, buffer 1 (SCREEN%)
 JSR GCALL              \ on show, as the rupture shows it from the start

 LDX #LO(LTLI)          \ Set (Y X) to point to LTLI ("L.T.CODE")
 LDY #HI(LTLI)

 JSR PCLI               \ Call PCLI to run the OS command in LTLI, which loads
                        \ the main docked code (Port: its home and cold images,
                        \ T.CODEH and T.CODEC, into its two sideways RAM banks,
                        \ through the game's own OSCLI, in the resident block)

 LDX #LO(LTPN)          \ Port: load the dashboard's image, P.DIALS, into
 LDY #HI(LTPN)          \ PANEL% (through PCLI, which passes the command to the
 JSR PCLI               \ MOS)

                        \ Port: switch the screen to the game's (elite-map.asm,
                        \ docs/video-timing.md): the loading screen is the
                        \ original's split mode 4 and mode 5, at the 6845's 1
                        \ MHz clock, with its own interrupt handler (IRQ1 in
                        \ block B); the game's is a 2 MHz screen and the 1 MHz
                        \ dashboard, the rupture (RUPT), which takes over at
                        \ its switch S2, on the loading screen's line 311

 SEI                    \ Disable interrupts while we change the screen

 LDA VIA+&6B            \ Set the user VIA's timer 2 running free, as the
 AND #%11011111         \ rupture's clock: one-shot mode (which counts on
 STA VIA+&6B            \ through 0), its interrupt disabled, and started
 LDA #%00100000
 STA VIA+&6E
 LDA #&FF
 STA VIA+&68
 STA VIA+&69

 LDX #(rinit_end - rinit - 2)

.rnl

 LDA rinit,X            \ Set 6845 register rinit+X to rinit+X+1, for each
 STA VIA+&00            \ pair in rinit: the field as one 39-row frame, vsync
 LDA rinit+1,X          \ at its row 34 (line 272), with the game's screen as
 STA VIA+&01            \ the start address of the next frame (frame A)
 DEX
 DEX
 BPL rnl

 JSR rcal               \ Find the vertical sync in timer 2, and set the
                        \ switches' targets from it

 LDA #0                 \ No switch has been made late (rcal uses rslip to
 STA rslip              \ check its probes)

 STA rblank             \ The display is on (R8 = 0, rinit), for RUPT and rdin

 LDA #LO(35*RLINEUS-12) \ Start timer 1 to fire on line 310 (we are just after
 STA VIA+&44            \ line 272's start), a line before S2, and then RPA
 LDA #HI(35*RLINEUS-12) \ microseconds on (point 1, a line before S1)
 STA VIA+&45
 LDA #LO(RPA)
 STA VIA+&46
 LDA #HI(RPA)
 STA VIA+&47

 LDA #1                 \ The first point is point 2 (S2), from the loading
 STA rphase             \ screen's 1 MHz clock
 STA rstate

 LDA #ULAA              \ The MOS's copy of the ULA's control register, as the
 STA &0248              \ game's screen has it

 LDY #15                \ Write the four-colour palette, PALCMYK

.palt

 LDA PALCMYK,Y
 STA VIA+&21
 DEY
 BPL palt

 LDA VEC                \ Copy the MOS's IRQ1V handler from VEC to IRQMOS, for
 STA IRQMOS             \ IRQG
 LDA VEC+1
 STA IRQMOS+1

 LDA #LO(IRQG)          \ Point IRQ1V at the game's interrupt handler, IRQG
 STA IRQ1V              \ (in the resident block), which handles the vertical
 LDA #HI(IRQG)          \ sync and the rupture, and passes everything else to
 STA IRQ1V+1            \ the MOS (at VEC)

 CLI                    \ Re-enable interrupts

 LDA #LO(BRKR)          \ Point BRKV to BRKR, which pages in the home bank and
 STA BRKV               \ goes on to the fifth entry in the main docked code's
 LDA #HI(BRKR)          \ S% workspace, which contains JMP BRBR1 (Port: the
 STA BRKV+1             \ original pointed BRKV straight at S%+11)

 LDA #LO(WRCHR)         \ Point WRCHV to WRCHR, which pages in the home bank and
 STA WRCHV              \ calls the third entry in the main docked code's S%
 LDA #HI(WRCHR)         \ workspace, which contains JMP CHPR (Port: the
 STA WRCHV+1            \ original pointed WRCHV straight at S%+6)

                        \ Port: the original's checksum of the docked code is
                        \ gone, with the copy protection

 LDA BANK4              \ Port: page in the docked code's home bank
 STA &F4
 STA VIA+&30

 JMP S%+3               \ Jump to the second entry in the main docked code's S%
                        \ workspace to start a new game

.LTLI

 EQUS "L.T.CODE"        \ This is short for "*LOAD T.CODE"
 EQUB 13

.LRBK

 EQUS "L.R.BANK"        \ Port: the rasteriser's bank (pload loads the file
 EQUB 13                \ named from the third character on)

.LRBK_END

.LTPN

 EQUS "L.P.DIALS"       \ Port: "*LOAD P.DIALS", the dashboard's image (to its
 EQUB 13                \ own load address, PANEL%)

.rcal

                        \ Port: find the vertical sync's start (line 272) in
                        \ timer 2's count, to the microsecond, and set the
                        \ switches' targets from it (docs/video-timing.md,
                        \ "Calibration"): a coarse wait for the sync's flag,
                        \ then a probe a field later at each microsecond from
                        \ just before it, until the flag is seen (a field is
                        \ &4E00 microseconds, so each probe's target is one
                        \ field and one microsecond on from the last's)

 LDA #%00000010         \ Clear the vertical sync's flag and wait for it
 STA VIA+&4D

.rc1

 BIT VIA+&4D
 BEQ rc1

 JSR rt2rd              \ (rcvh rcvl) = timer 2, just after the sync's flag set

 LDA rcvl               \ (rch rcl) = the first probe, 94 microseconds earlier
 CLC                    \ in the field (a probe reads the flag 45
 ADC #94                \ microseconds after its time, at rwait's return, so
                        \ the probes read it from about 47 microseconds before
                        \ the moment it sets to 49 after)
 STA rcl
 LDA rcvh
 ADC #0
 STA rch

 LDA #96                \ At most 96 probes (rcn: rwait uses Y)
 STA rcn

.rc2

 LDA rcl                \ (rch rcl) = the next probe: a field and a microsecond
 SEC                    \ on, &4E01 counts lower (a microsecond here, the field
 SBC #&01               \ at rc5)
 STA rcl
 LDA rch
 SBC #0
 STA rch

.rc5

 LDA rch                \ A field on, &4E00 counts lower (rc5: the same probe in
 SEC                    \ the next field, after a late one)
 SBC #&4E
 STA rch

 LDA #0                 \ rwait counts a late wait in rslip (the probe's read
 STA rslip              \ is then a whole number of lines after its time)

.rc3

 JSR rt2rd2             \ Wait until timer 2 is RCW or fewer counts above the
 LDA rcdl               \ probe (rt2rd2 sets (rcdh rcdl) = timer 2 less the
 SEC                    \ probe): a pass of this loop is 49 microseconds (65
 SBC #RCW+1             \ when rt2rd reads twice), and rwait reads timer 2 50
 LDA rcdh               \ after this loop's read, so that rwait's wait is 8 to
 SBC #0                 \ 72 microseconds: on time (at most RWMAX), and the
 BPL rc3                \ flag is read at the probe's time

 LDA #%00000010         \ Clear the sync's flag, then read it at the probe's
 STA VIA+&4D            \ exact time (rwait, with the probe as target 4)
 LDA rcl
 STA rtgt+4
 LDX #4
 JSR rwait
 LDA VIA+&4D

 LDX rslip              \ If rwait's wait was late, the read was not at the
 BNE rc6                \ probe's time: make the probe again a field later

 AND #%00000010         \ If the flag is set, the sync has started: this probe
 BNE rc4                \ is the calibration

 DEC rcn                \ Otherwise try the next microsecond
 BNE rc2
 BEQ rc4

.rc6

 DEC rcn                \ (a late probe counts as one of the 96)
 BNE rc5

.rc4

 LDA rcl                \ The targets, RD1 and RD2 microseconds after the
 SEC                    \ probe (docs/video-timing.md)
 SBC #LO(RD1)
 STA rtgt
 LDA rcl
 SEC
 SBC #LO(RD2)
 STA rtgt+2

 RTS

.rt2rd2

 JSR rt2rd              \ Read timer 2, and set (rcdh rcdl) = it less the probe
 LDA rcvl
 SEC
 SBC rcl
 STA rcdl
 LDA rcvh
 SBC rch
 STA rcdh
 RTS

.rt2rd

 LDA VIA+&69            \ (rcvh rcvl) = timer 2, read until both bytes agree
 STA rcvh
 LDA VIA+&68
 STA rcvl
 LDA VIA+&69
 CMP rcvh
 BNE rt2rd
 RTS

.rcn

 EQUB 0                 \ The probes left

.rcl

 EQUB 0                 \ The probe (low byte, then high byte)

.rch

 EQUB 0

.rcvl

 EQUB 0                 \ Timer 2 as read (low byte, then high byte)

.rcvh

 EQUB 0

.rcdl

 EQUB 0                 \ Timer 2 less the probe (low byte, then high byte)

.rcdh

 EQUB 0

.rinit

                        \ Port: the 6845 registers for the rupture's start
                        \ (register and value pairs)
 EQUB 4, 38             \ R4 = 38, a 39-row frame
 EQUB 5, 0              \ R5 = 0, no vertical adjust
 EQUB 7, 34             \ R7 = 34, vsync at row 34
 EQUB 8, 0              \ R8 = 0, no interlace
 EQUB 12, HI(SCREEN% DIV 8)
 EQUB 13, LO(SCREEN% DIV 8)  \ R12 R13 = SCREEN% / 8, the next frame's start

.rinit_end

 EQUS "Does your mother know you do this?"

 PRINT "LOAD: ", ~LOAD, "-", ~P%-1, ", free ", LOAD+&200-P%
 ASSERT P% <= LOAD + &200       \ (the loader moves two pages to LOAD)

 COPYBLOCK LOAD, P%, LOADcode

 ORG LOADcode + P% - LOAD

\ ******************************************************************************
\
\       Name: CATDcode
\       Type: Subroutine
\   Category: Save and load
\    Summary: The CATD routine, bundled up in the loader so it can be moved to
\             &0D7A to be run
\
\ ******************************************************************************

.CATDcode

 ORG &0D7A              \ Set the assembly address to &0D7A

\ ******************************************************************************
\
\       Name: CATD
\       Type: Subroutine
\   Category: Save and load
\    Summary: Load disc sectors 0 and 1 to &0E00 and &0F00 respectively
\  Deep dive: Swapping between the docked and flight code
\
\ ------------------------------------------------------------------------------
\
\ This routine is copied to &0D7A in part 1 above. It is called by both the main
\ docked code and the main flight code, just before the docked code, flight code
\ or ship blueprint files are loaded.
\
\ ******************************************************************************

.CATD

 DEC CATBLOCK+8         \ Decrement sector number from 1 to 0
 DEC CATBLOCK+2         \ Decrement load address from &0F00 to &0E00

 JSR CATL               \ Call CATL to load disc sector 1 to &0E00

 INC CATBLOCK+8         \ Increment sector number back to 1
 INC CATBLOCK+2         \ Increment load address back to &0F00

.CATL

 LDA #127               \ Call OSWORD with A = 127 and (Y X) = CATBLOCK to
 LDX #LO(CATBLOCK)      \ load disc sector 1 to &0F00
 LDY #HI(CATBLOCK)
 JMP OSWORD

\ ******************************************************************************
\
\       Name: CATBLOCK
\       Type: Subroutine
\   Category: Save and load
\    Summary: OSWORD block for loading  disc sectors 0 and 1
\  Deep dive: Swapping between the docked and flight code
\
\ ******************************************************************************

.CATBLOCK

 EQUB 0                 \ 0 = Drive = 0
 EQUD &00000F00         \ 1 = Data address = &0F00
 EQUB 3                 \ 5 = Number of parameters = 3
 EQUB &53               \ 6 = Command = &53 (read data)
 EQUB 0                 \ 7 = Track = 0
 EQUB 1                 \ 8 = Sector = 1
 EQUB %00100001         \ 9 = Load 1 sector of 256 bytes
 EQUB 0                 \ 10 = The result of the OSWORD call is returned here

 COPYBLOCK CATD, P%, CATDcode

 ORG CATDcode + P% - CATD

\ ******************************************************************************
\
\       Name: PROT1
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Part of the CHKSM copy protection checksum calculation
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: PLL1 (Part 1 of 3)
\       Type: Subroutine
\   Category: Drawing planets
\    Summary: Draw Saturn on the loading screen (draw the planet)
\  Deep dive: Drawing Saturn on the loading screen
\
\ ******************************************************************************

.PLL1

                        \ The following loop iterates CNT(1 0) times, i.e. &300
                        \ or 768 times, and draws the planet part of the
                        \ loading screen's Saturn

 LDA VIA+&44            \ Read the 6522 System VIA T1C-L timer 1 low-order
 STA RAND+1             \ counter (SHEILA &44), which decrements one million
                        \ times a second and will therefore be pretty random,
                        \ and store it in location RAND+1, which is among the
                        \ main game code's random seeds in RAND (so this seeds
                        \ the random number generator)

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r1

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r1^2

 STA ZP+1               \ Set ZP(1 0) = (A P)
 LDA P                  \             = r1^2
 STA ZP

 \ Port: the copy protection modified OSBjsr's JSR here (low byte)

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r2

 STA YY                 \ Set YY = A
                        \        = r2

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r2^2

 TAX                    \ Set (X P) = (A P)
                        \           = r2^2

 LDA P                  \ Set (A ZP) = (X P) + ZP(1 0)
 ADC ZP                 \
 STA ZP                 \ first adding the low bytes

 TXA                    \ And then adding the high bytes
 ADC ZP+1

 BCS PLC1               \ If the addition overflowed, jump down to PLC1 to skip
                        \ to the next pixel

 STA ZP+1               \ Set ZP(1 0) = (A ZP)
                        \             = r1^2 + r2^2

 LDA #1                 \ Set ZP(1 0) = &4001 - ZP(1 0) - (1 - C)
 SBC ZP                 \             = 128^2 - ZP(1 0)
 STA ZP                 \
                        \ (as the C flag is clear), first subtracting the low
                        \ bytes

 LDA #&40               \ And then subtracting the high bytes
 SBC ZP+1
 STA ZP+1

 BCC PLC1               \ If the subtraction underflowed, jump down to PLC1 to
                        \ skip to the next pixel

                        \ If we get here, then both calculations fitted into
                        \ 16 bits, and we have:
                        \
                        \   ZP(1 0) = 128^2 - (r1^2 + r2^2)
                        \
                        \ where ZP(1 0) >= 0

 JSR ROOT               \ Set ZP = SQRT(ZP(1 0))

 LDA ZP                 \ Set X = ZP >> 1
 LSR A                  \       = SQRT(128^2 - (a^2 + b^2)) / 2
 TAX

 LDA YY                 \ Set A = YY
                        \       = r2

 CMP #128               \ If YY >= 128, set the C flag (so the C flag is now set
                        \ to bit 7 of A)

 ROR A                  \ Rotate A and set the sign bit to the C flag, so A is
                        \ halved while retaining its sign
                        \
                        \ A is still a signed number from -128 to 127

 JSR PIX                \ Draw a pixel at screen coordinate (X + 128, A + 128),
                        \ where:
                        \
                        \   X = ZP / 2
                        \   A = r2 / 2
                        \   ZP = SQRT(128^2 - (r1^2 + r2^2))
                        \
                        \ So this is the same as plotting at (x, y) where:
                        \
                        \   r1 = random number from -128 to 127
                        \   r2 = random number from -128 to 127
                        \
                        \   (r1^2 + r2^2) < 128^2
                        \
                        \   x = (SQRT(128^2 - (r1^2 + r2^2)) / 2) + 128
                        \   y = (r2 / 2) + 128
                        \
                        \ which is what we want

.PLC1

 DEC CNT                \ Decrement the counter in CNT (the low byte)

 BNE PLL1               \ Loop back to PLL1 until CNT = 0

 DEC CNT+1              \ Decrement the counter in CNT+1 (the high byte)

 BNE PLL1               \ Loop back to PLL1 until CNT+1 = 0

\ ******************************************************************************
\
\       Name: PLL1 (Part 2 of 3)
\       Type: Subroutine
\   Category: Drawing planets
\    Summary: Draw Saturn on the loading screen (draw the stars)
\  Deep dive: Drawing Saturn on the loading screen
\
\ ******************************************************************************

                        \ The following loop iterates CNT2(1 0) times, i.e. &1DD
                        \ or 477 times, and draws the background stars on the
                        \ loading screen

.PLL2

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r3

 TAX                    \ Set X = A
                        \       = r3

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r3^2

 STA ZP+1               \ Set ZP+1 = A
                        \          = r3^2 / 256

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r4

 STA YY                 \ Set YY = r4

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r4^2

 ADC ZP+1               \ Set A = A + r3^2 / 256
                        \       = r4^2 / 256 + r3^2 / 256
                        \       = (r3^2 + r4^2) / 256

 CMP #&11               \ If A < 17, jump down to PLC2 to skip to the next pixel
 BCC PLC2

 LDA YY                 \ Set A = r4

 JSR PIX                \ Draw a pixel at screen coordinate (X + 128, A + 128),
                        \ where:
                        \
                        \   X = r3
                        \   A = r4
                        \
                        \ So this is the same as plotting at (x, y) where:
                        \
                        \   r3 = random number from -128 to 127
                        \   r4 = random number from -128 to 127
                        \
                        \   (r3^2 + r4^2) / 256 >= 17
                        \
                        \   x = r3
                        \   y = r4
                        \
                        \ which is what we want

.PLC2

 DEC CNT2               \ Decrement the counter in CNT2 (the low byte)

 BNE PLL2               \ Loop back to PLL2 until CNT2 = 0

 DEC CNT2+1             \ Decrement the counter in CNT2+1 (the high byte)

 BNE PLL2               \ Loop back to PLL2 until CNT2+1 = 0

\ ******************************************************************************
\
\       Name: PLL1 (Part 3 of 3)
\       Type: Subroutine
\   Category: Drawing planets
\    Summary: Draw Saturn on the loading screen (draw the rings)
\  Deep dive: Drawing Saturn on the loading screen
\
\ ******************************************************************************

                        \ The following loop iterates CNT3(1 0) times, i.e. &333
                        \ or 819 times, and draws the rings around the loading
                        \ screen's Saturn

.PLL3

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r5

 STA ZP                 \ Set ZP = r5

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r5^2

 STA ZP+1               \ Set ZP+1 = A
                        \          = r5^2 / 256

 \ Port: the copy protection modified OSBjsr's JSR here (high byte)

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r6

 STA YY                 \ Set YY = r6

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r6^2

 STA T                  \ Set T = A
                        \       = r6^2 / 256

 ADC ZP+1               \ Set ZP+1 = A + r5^2 / 256
 STA ZP+1               \          = r6^2 / 256 + r5^2 / 256
                        \          = (r5^2 + r6^2) / 256

 LDA ZP                 \ Set A = ZP
                        \       = r5

 CMP #128               \ If A >= 128, set the C flag (so the C flag is now set
                        \ to bit 7 of ZP, i.e. bit 7 of A)

 ROR A                  \ Rotate A and set the sign bit to the C flag, so bits
                        \ 6 and 7 are now the same

 CMP #128               \ If A >= 128, set the C flag (so again, the C flag is
                        \ set to bit 7 of A)

 ROR A                  \ Rotate A and set the sign bit to the C flag, so bits
                        \ 5-7 are now the same, i.e. A is a random number in one
                        \ of these ranges:
                        \
                        \   %00000000 - %00011111  = 0-31
                        \   %11100000 - %11111111  = 224-255
                        \
                        \ In terms of signed 8-bit integers, this is a random
                        \ number from -32 to 31. Let's call it r7

 ADC YY                 \ Set A = A + YY
                        \       = r7 + r6

 TAX                    \ Set X = A
                        \       = r6 + r7

 JSR SQUA2              \ Set (A P) = A * A
                        \           = (r6 + r7)^2

 TAY                    \ Set Y = A
                        \       = (r6 + r7)^2 / 256

 ADC ZP+1               \ Set A = A + ZP+1
                        \       = (r6 + r7)^2 / 256 + (r5^2 + r6^2) / 256
                        \       = ((r6 + r7)^2 + r5^2 + r6^2) / 256

 BCS PLC3               \ If the addition overflowed, jump down to PLC3 to skip
                        \ to the next pixel

 CMP #80                \ If A >= 80, jump down to PLC3 to skip to the next
 BCS PLC3               \ pixel

 CMP #32                \ If A < 32, jump down to PLC3 to skip to the next pixel
 BCC PLC3

 TYA                    \ Set A = Y + T
 ADC T                  \       = (r6 + r7)^2 / 256 + r6^2 / 256
                        \       = ((r6 + r7)^2 + r6^2) / 256

 CMP #16                \ If A >= 16, skip to PL1 to plot the pixel
 BCS PL1

 LDA ZP                 \ If ZP is positive (i.e. r5 < 128), jump down to PLC3
 BPL PLC3               \ to skip to the next pixel

.PL1

                        \ If we get here then the following is true:
                        \
                        \   32 <= ((r6 + r7)^2 + r5^2 + r6^2) / 256 < 80
                        \
                        \ and either this is true:
                        \
                        \   ((r6 + r7)^2 + r6^2) / 256 >= 16
                        \
                        \ or both these are true:
                        \
                        \   ((r6 + r7)^2 + r6^2) / 256 < 16
                        \   r5 >= 128

 LDA YY                 \ Set A = YY
                        \       = r6

 JSR PIX                \ Draw a pixel at screen coordinate (X + 128, A + 128),
                        \ where:
                        \
                        \   X = (random -32 to 31) + r6
                        \   A = r6
                        \
                        \ So this is the same as plotting at (x, y) where:
                        \
                        \   r5 = random number from -128 to 127
                        \   r6 = random number from -128 to 127
                        \   r7 = r5, squashed into -32 to 31
                        \
                        \   32 <= ((r6 + r7)^2 + r5^2 + r6^2) / 256 < 80
                        \
                        \   Either: ((r6 + r7)^2 + r6^2) / 256 >= 16
                        \
                        \   Or:     ((r6 + r7)^2 + r6^2) / 256 <  16
                        \           r5 >= 128
                        \
                        \   x = r6 + r7 + 128
                        \   y = r6 + 128
                        \
                        \ which is what we want

.PLC3

 DEC CNT3               \ Decrement the counter in CNT3 (the low byte)

 BNE PLL3               \ Loop back to PLL3 until CNT3 = 0

 DEC CNT3+1             \ Decrement the counter in CNT3+1 (the high byte)

 BNE PLL3               \ Loop back to PLL3 until CNT3+1 = 0

                        \ The following code is not required, as we copy the
                        \ title images to their correct places on-screen when
                        \ we return from the subroutine, overwriting the copy
                        \ that we do here

 LDA #&00               \ Set ZP(1 0) = &6300
 STA ZP
 LDA #&63
 STA ZP+1

 LDA #LO(ELITE)         \ Set P(1 0) = ELITE
 STA P
 LDA #HI(ELITE)
 STA P+1

 LDX #8                 \ Call MVPG with X = 8 to copy 8 pages of memory from
 JSR MVPG               \ ELITE to &6300

\ ******************************************************************************
\
\       Name: DORND
\       Type: Subroutine
\   Category: Maths (Arithmetic)
\    Summary: Generate random numbers
\  Deep dive: Generating random numbers
\             Fixing ship positions
\
\ ------------------------------------------------------------------------------
\
\ Set A and X to random numbers (though note that X is set to the random number
\ that was returned in A the last time DORND was called).
\
\ The C and V flags are also set randomly.
\
\ This is a simplified version of the DORND routine in the main game code. It
\ swaps the two calculations around and omits the ROL A instruction, but is
\ otherwise very similar. See the DORND routine in the main game code for more
\ details.
\
\ ******************************************************************************

.DORND

 LDA RAND+1             \ r1Â´ = r1 + r3 + C
 TAX                    \ r3Â´ = r1
 ADC RAND+3
 STA RAND+1
 STX RAND+3

 LDA RAND               \ X = r2Â´ = r0
 TAX                    \ A = r0Â´ = r0 + r2
 ADC RAND+2
 STA RAND
 STX RAND+2

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: RAND
\       Type: Variable
\   Category: Drawing planets
\    Summary: The random number seed used for drawing Saturn
\
\ ******************************************************************************

.RAND

 EQUD &34785349

\ ******************************************************************************
\
\       Name: SQUA2
\       Type: Subroutine
\   Category: Maths (Arithmetic)
\    Summary: Calculate (A P) = A * A
\  Deep dive: Shift-and-add multiplication
\
\ ------------------------------------------------------------------------------
\
\ Do the following multiplication of signed 8-bit numbers:
\
\   (A P) = A * A
\
\ This uses a similar approach to routine SQUA2 in the main game code, which
\ itself uses the MU11 routine to do the multiplication. However, this version
\ first ensures that A is positive, so it can support signed numbers.
\
\ ******************************************************************************

.SQUA2

 BPL SQUA               \ If A > 0, jump to SQUA

 EOR #&FF               \ Otherwise we need to negate A for the SQUA algorithm
 CLC                    \ to work, so we do this using two's complement, by
 ADC #1                 \ setting A = ~A + 1

.SQUA

 STA Q                  \ Set Q = A and P = A

 STA P                  \ Set P = A

 LDA #0                 \ Set A = 0 so we can start building the answer in A

 LDY #8                 \ Set up a counter in Y to count the 8 bits in P

 LSR P                  \ Set P = P >> 1
                        \ and C flag = bit 0 of P

.SQL1

 BCC SQ1                \ If C (i.e. the next bit from P) is set, do the
 CLC                    \ addition for this bit of P:
 ADC Q                  \
                        \   A = A + Q

.SQ1

 ROR A                  \ Shift A right to catch the next digit of our result,
                        \ which the next ROR sticks into the left end of P while
                        \ also extracting the next bit of P

 ROR P                  \ Add the overspill from shifting A to the right onto
                        \ the start of P, and shift P right to fetch the next
                        \ bit for the calculation into the C flag

 DEY                    \ Decrement the loop counter

 BNE SQL1               \ Loop back for the next bit until P has been rotated
                        \ all the way

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: PIX
\       Type: Subroutine
\   Category: Drawing pixels
\    Summary: Draw a single pixel at a specific coordinate
\
\ ------------------------------------------------------------------------------
\
\ Draw a pixel at screen coordinate (X + 128, A + 128). The routine uses the
\ same approach as the PIXEL routine in the main game code, except it plots a
\ single pixel from TWOS instead of a two pixel dash from TWOS2. This applies
\ to the top part of the screen (the monochrome mode 4 space view).
\
\ See the PIXEL routine in the main game code for more details.
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   X                   The signed screen x-coordinate of the pixel to draw,
\                       from -128 to 127, to be plotted relative to the origin
\                       at (128, 128)
\
\   A                   The signed screen y-coordinate of the pixel to draw,
\                       from -128 to 127, to be plotted relative to the origin
\                       at (128, 128)
\
\ ------------------------------------------------------------------------------
\
\ Other entry points:
\
\   out                 Contains an RTS
\
\ ******************************************************************************

.PIX

 TAY                    \ Copy A into Y, for use later

 EOR #%10000000         \ Add 128 to A and treat this as an unsigned number from
                        \ now on

 LSR A                  \ Set A = A >> 3
 LSR A
 LSR A

 \ Port: the copy protection shifted CHKSM+1 here

 ORA #&60               \ Set ZP+1 = &60 + A >> 3
 STA ZP+1

 TXA                    \ Set ZP = (X >> 3) * 8
 EOR #%10000000
 AND #%11111000
 STA ZP

 TYA                    \ Set Y = Y mod 8, which is the pixel row within the
 AND #7                 \ character block at which we want to draw our pixel
 TAY                    \ (as each character block has 8 rows)

 TXA                    \ Set X = X mod 8, which is the horizontal pixel number
 AND #7                 \ within the character block where the pixel lies (as
 TAX                    \ each pixel line in the character block is 8 pixels
                        \ wide)

 LDA TWOS,X             \ Fetch a pixel from TWOS and poke it into ZP+Y
 STA (ZP),Y

.out

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: TWOS
\       Type: Variable
\   Category: Drawing pixels
\    Summary: Ready-made single-pixel character row bytes for mode 4
\
\ ------------------------------------------------------------------------------
\
\ Ready-made bytes for plotting one-pixel points in mode 4 (the top part of the
\ split screen). See the PIX routine for details.
\
\ ******************************************************************************

.TWOS

 EQUB %10000000
 EQUB %01000000
 EQUB %00100000
 EQUB %00010000
 EQUB %00001000
 EQUB %00000100
 EQUB %00000010
 EQUB %00000001

\ ******************************************************************************
\
\       Name: PROT2
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Part of the CHKSM copy protection checksum calculation
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: CNT
\       Type: Variable
\   Category: Drawing planets
\    Summary: A counter for use in drawing Saturn's planetary body
\
\ ------------------------------------------------------------------------------
\
\ Defines the number of iterations of the PLL1 loop, which draws the planet part
\ of the loading screen's Saturn.
\
\ ******************************************************************************

.CNT

 EQUW &0300             \ The number of iterations of the PLL1 loop (768)

\ ******************************************************************************
\
\       Name: CNT2
\       Type: Variable
\   Category: Drawing planets
\    Summary: A counter for use in drawing Saturn's background stars
\
\ ------------------------------------------------------------------------------
\
\ Defines the number of iterations of the PLL2 loop, which draws the background
\ stars on the loading screen.
\
\ ******************************************************************************

.CNT2

 EQUW &01DD             \ The number of iterations of the PLL2 loop (477)

\ ******************************************************************************
\
\       Name: CNT3
\       Type: Variable
\   Category: Drawing planets
\    Summary: A counter for use in drawing Saturn's rings
\
\ ------------------------------------------------------------------------------
\
\ Defines the number of iterations of the PLL3 loop, which draws the rings
\ around the loading screen's Saturn.
\
\ ******************************************************************************

.CNT3

 EQUW &0333             \ The number of iterations of the PLL3 loop (819)

\ ******************************************************************************
\
\       Name: PROT3
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Part of the CHKSM copy protection checksum calculation
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: ROOT
\       Type: Subroutine
\   Category: Maths (Arithmetic)
\    Summary: Calculate ZP = SQRT(ZP(1 0))
\
\ ------------------------------------------------------------------------------
\
\ Calculate the following square root:
\
\   ZP = SQRT(ZP(1 0))
\
\ This routine is identical to LL5 in the main game code - it even has the same
\ label names. The only difference is that LL5 calculates Q = SQRT(R Q), but
\ apart from the variables used, the instructions are identical, so see the LL5
\ routine in the main game code for more details on the algorithm used here.
\
\ ******************************************************************************

.ROOT

 LDY ZP+1               \ Set (Y Q) = ZP(1 0)
 LDA ZP
 STA Q

                        \ So now to calculate ZP = SQRT(Y Q)

 LDX #0                 \ Set X = 0, to hold the remainder

 STX ZP                 \ Set ZP = 0, to hold the result

 LDA #8                 \ Set P = 8, to use as a loop counter
 STA P

.LL6

 CPX ZP                 \ If X < ZP, jump to LL7
 BCC LL7

 BNE LL8                \ If X > ZP, jump to LL8

 CPY #64                \ If Y < 64, jump to LL7 with the C flag clear,
 BCC LL7                \ otherwise fall through into LL8 with the C flag set

.LL8

 TYA                    \ Set Y = Y - 64
 SBC #64                \
 TAY                    \ This subtraction will work as we know C is set from
                        \ the BCC above, and the result will not underflow as we
                        \ already checked that Y >= 64, so the C flag is also
                        \ set for the next subtraction

 TXA                    \ Set X = X - ZP
 SBC ZP
 TAX

.LL7

 ROL ZP                 \ Shift the result in Q to the left, shifting the C flag
                        \ into bit 0 and bit 7 into the C flag

 ASL Q                  \ Shift the dividend in (Y S) to the left, inserting
 TYA                    \ bit 7 from above into bit 0
 ROL A
 TAY

 TXA                    \ Shift the remainder in X to the left
 ROL A
 TAX

 ASL Q                  \ Shift the dividend in (Y S) to the left
 TYA
 ROL A
 TAY

 TXA                    \ Shift the remainder in X to the left
 ROL A
 TAX

 DEC P                  \ Decrement the loop counter

 BNE LL6                \ Loop back to LL6 until we have done 8 loops

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: OSB
\       Type: Subroutine
\   Category: Utility routines
\    Summary: A convenience routine for calling OSBYTE with Y = 0
\
\ ******************************************************************************

.OSB

 LDY #0                 \ Call OSBYTE with Y = 0, returning from the subroutine
 JMP OSBYTE             \ using a tail call (so we can call OSB to call OSBYTE
                        \ for when we know we want Y set to 0)

 EQUB &0E               \ This byte appears to be unused

\ ******************************************************************************
\
\       Name: MVPG
\       Type: Subroutine
\   Category: Utility routines
\    Summary: Decrypt and move a page of memory
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   P(1 0)              The source address of the page to move
\
\   ZP(1 0)             The destination address of the page to move
\
\ ******************************************************************************

.MVPG

 LDY #0                 \ We want to move one page of memory, so set Y as a byte
                        \ counter

.MPL

 LDA (P),Y              \ Fetch the Y-th byte of the P(1 0) memory block (Port:
                        \ the loader is not encrypted)

 STA (ZP),Y             \ Store the result in the Y-th byte of the ZP(1 0)
                        \ memory block

 DEY                    \ Decrement the byte counter

 BNE MPL                \ Loop back to copy the next byte until we have done a
                        \ whole page of 256 bytes

 RTS                    \ Return from the subroutine

 EQUB &0E               \ This byte appears to be unused

\ ******************************************************************************
\
\       Name: MVBL
\       Type: Subroutine
\   Category: Utility routines
\    Summary: Decrypt and move a multi-page block of memory
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   P(1 0)              The source address of the block to move
\
\   ZP(1 0)             The destination address of the block to move
\
\   X                   Number of pages of memory to move (1 page = 256 bytes)
\
\ ******************************************************************************

.MVBL

 JSR MVPG               \ Call MVPG above to copy one page of memory from the
                        \ address in P(1 0) to the address in ZP(1 0)

 INC ZP+1               \ Increment the high byte of the source address to point
                        \ to the next page

 INC P+1                \ Increment the high byte of the destination address to
                        \ point to the next page

 DEX                    \ Decrement the page counter

 BNE MVBL               \ Loop back to copy the next page until we have done X
                        \ pages

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: MESS1
\       Type: Variable
\   Category: Loader
\    Summary: The OS command string for changing the disc directory to E
\
\ ******************************************************************************

.MESS1

 EQUS "*DIR E"
 EQUB 13

\ ******************************************************************************
\
\       Name: Elite loader (Part 2 of 3)
\       Type: Subroutine
\   Category: Loader
\    Summary: Include binaries for recursive tokens, Missile blueprint and
\             images
\
\ ------------------------------------------------------------------------------
\
\ The loader bundles a number of binary files in with the loader code, and moves
\ them to their correct memory locations in part 1 above.
\
\ This section is encrypted by EOR'ing with &A5. The encryption is done by the
\ elite-checksum.py script, and decryption is done in part 1 above, at the same
\ time as each block is moved to its correct location.
\
\ There are two files containing code:
\
\   * WORDS.bin contains the recursive token table, which is moved to &0400
\     before the main game is loaded
\
\   * MISSILE.bin contains the missile ship blueprint, which gets moved to &7F00
\     before the main game is loaded
\
\ and one file containing an image, which is moved into screen memory by the
\ loader:
\
\   * P.DIALS.bin contains the dashboard, which gets moved to screen address
\     &7800, which is the starting point of the four-colour mode 5 portion at
\     the bottom of the split screen
\
\ There are three other image binaries bundled into the loader, which are
\ described in part 3 below.
\
\ ******************************************************************************

.DIALS

 INCBIN "1-source-files/images/P.DIALS.bin"

.SHIP_MISSILE

 INCBIN "3-assembled-output/MISSILE.bin"

                        \ Port: the recursive text tokens are in each program's
                        \ cold bank; the resident block A follows


\ ******************************************************************************
\
\       Name: RESAcode
\       Type: Subroutine
\   Category: Loader
\    Summary: The resident block A, bundled up in the loader so it can be moved
\             to &0400-&07FF
\
\ ------------------------------------------------------------------------------
\
\ Port: the far calls, the game's OSCLI and the WRCHV and BRKV handlers, then
\ the sine and arctan tables, in the place of the original's WORDS
\ (elite-resident.asm, docs/memory-map.md).
\
\ ******************************************************************************

.RESAcode

 ORG &0400              \ Set the assembly address to &0400

 INCLUDE "1-source-files/main-sources/elite-resident.asm"

 COPYBLOCK &0400, &0800, RESAcode

 ORG RESAcode + &0400

\ ******************************************************************************
\
\       Name: RESHcode
\       Type: Subroutine
\   Category: Loader
\    Summary: The high resident block, which the LOAD routine copies to RESH%
\
\ ******************************************************************************

.RESHcode

 ORG RESH%

 INCLUDE "1-source-files/main-sources/elite-resident-high.asm"

.RESH_END

 COPYBLOCK RESH%, RESH_END, RESHcode

 ORG RESHcode + RESH_END - RESH%

\ ******************************************************************************
\
\       Name: RUPTcode
\       Type: Subroutine
\   Category: Loader
\    Summary: The rupture's code, which the LOAD routine copies to RUPT%
\
\ ******************************************************************************

.RUPTcode

 ORG RUPT%

 INCLUDE "1-source-files/main-sources/elite-rupture.asm"

.RUPT_END

 PRINT "Rupture block: ", ~RUPT%, "-", ~RUPT_END-1, " (", RUPT_END-RUPT%, " bytes)"
 ASSERT RUPT_END <= RUPT% + RUPTPG * 256 AND RUPT_END <= PROGM%

 COPYBLOCK RUPT%, RUPT_END, RUPTcode

 ORG RUPTcode + RUPT_END - RUPT%

\ ******************************************************************************
\
\       Name: PROBE
\       Type: Subroutine
\   Category: Loader
\    Summary: Find four sideways RAM banks for the game, or stop
\
\ ------------------------------------------------------------------------------
\
\ Port: the game lives in four sideways RAM banks (docs/memory-map.md). This
\ tests each slot from 15 down to 0, passing over any that the MOS has a ROM
\ in (its entry in the ROM type table at &02A1 is non-zero), and takes the
\ first four that hold what is written to them, in BANKS: the programs' home
\ bank, their cold bank, then the renderer's two banks. Without four, it
\ prints a message and stops.
\
\ ******************************************************************************

.PROBE

 LDA &F4                \ Store the current ROM on the stack
 PHA

 LDY #0                 \ Set Y = 0 to count the banks found

 LDX #15                \ Set X = 15 to test the slots from 15 down

.prb1

 LDA &02A1,X            \ If the MOS has a ROM in slot X, skip it
 BNE prb2

 STX &F4                \ Page slot X in
 STX VIA+&30

 LDA #&AA               \ If the slot does not hold &AA and &55 when they are
 STA &BFFF              \ written to it, it is not RAM, so skip it
 CMP &BFFF
 BNE prb2
 LDA #&55
 STA &BFFF
 CMP &BFFF
 BNE prb2

 TXA                    \ Slot X is RAM, so store it in the Y-th byte of BANKS
 STA BANKS,Y

 INY                    \ Stop when we have four
 CPY #4
 BEQ prb4

.prb2

 DEX                    \ Loop back for the next slot
 BPL prb1

 PLA                    \ Fewer than four: page the original ROM back in
 STA &F4
 STA VIA+&30

 LDX #0                 \ Print the message in prbm and stop

.prb3

 LDA prbm,X
 BEQ P%
 JSR OSWRCH
 INX
 BNE prb3

.prb4

 PLA                    \ Page the original ROM back in and return
 STA &F4
 STA VIA+&30

 RTS

.prbm

 EQUB 22, 7
 EQUS "This version of Elite needs 64K of"
 EQUB 13, 10
 EQUS "sideways RAM (four banks)."
 EQUB 13, 10, 0


\ ******************************************************************************
\
\       Name: OSBmod
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Calculate a checksum on &0F00 to &0FFF (the test is disabled in
\             this version)
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: TVT1code
\       Type: Subroutine
\   Category: Loader
\    Summary: Code block at &1100-&11E2 that remains resident in both docked and
\             flight mode (palettes, screen mode routine and commander data)
\
\ ------------------------------------------------------------------------------
\
\ This section is encrypted by EOR'ing with &A5. The encryption is done by the
\ elite-checksum.py script, and decryption is done in part 1 above, at the same
\ time as it is moved to &1100.
\
\ ******************************************************************************

.TVT1code

 ORG &1100              \ Set the assembly address to &1100

\ ******************************************************************************
\
\       Name: TVT1
\       Type: Variable
\   Category: Drawing the screen
\    Summary: Palette data for space and the two dashboard colour schemes
\
\ ------------------------------------------------------------------------------
\
\ Palette bytes for use with the split-screen mode (see IRQ1 below for more
\ details).
\
\ Palette data is given as a set of bytes, with each byte mapping a logical
\ colour to a physical one. In each byte, the logical colour is given in bits
\ 4-7 and the physical colour in bits 0-3. See page 379 of the "Advanced User
\ Guide for the BBC Micro" by Bray, Dickens and Holmes for details of how
\ palette mapping works, as in modes 4 and 5 we have to do multiple palette
\ commands to change the colours correctly, and the physical colour value is
\ EOR'd with 7, just to make things even more confusing.
\
\ Similarly, the palette at TVT1+16 is for the monochrome space view, where
\ logical colour 1 is mapped to physical colour 0 EOR 7 = 7 (white), and
\ logical colour 0 is mapped to physical colour 7 EOR 7 = 0 (black). Each of
\ these mappings requires six calls to SHEILA &21 - see page 379 of the
\ "Advanced User Guide for the BBC Micro" by Bray, Dickens and Holmes for an
\ explanation.
\
\ The mode 5 palette table has two blocks which overlap. The block used depends
\ on whether or not we have an escape pod fitted. The block at TVT1 is used for
\ the standard dashboard colours, while TVT1+8 is used for the dashboard when an
\ escape pod is fitted. The colours are as follows:
\
\                 Normal (TVT1)     Escape pod (TVT1+8)
\
\   Colour 0      Black             Black
\   Colour 1      Red               Red
\   Colour 2      Yellow            White
\   Colour 3      Green             Cyan
\
\ ******************************************************************************

.TVT1

 EQUB &D4, &C4          \ This block of palette data is used to create two
 EQUB &94, &84          \ palettes used in three different places, all of them
 EQUB &F5, &E5          \ redefining four colours in mode 5:
 EQUB &B5, &A5          \
                        \ 12 bytes from TVT1 (i.e. the first 6 rows): applied
 EQUB &76, &66          \ when the T1 timer runs down at the switch from the
 EQUB &36, &26          \ space view to the dashboard, so this is the standard
                        \ dashboard palette
 EQUB &E1, &F1          \
 EQUB &B1, &A1          \ 8 bytes from TVT1+8 (i.e. the last 4 rows): applied
                        \ when the T1 timer runs down at the switch from the
                        \ space view to the dashboard, and we have an escape
                        \ pod fitted, so this is the escape pod dashboard
                        \ palette
                        \
                        \ 8 bytes from TVT1+8 (i.e. the last 4 rows): applied
                        \ at vertical sync in LINSCN when HFX is non-zero, to
                        \ create the hyperspace effect in LINSCN (where the
                        \ whole screen is switched to mode 5 at vertical sync)

 EQUB &F0, &E0          \ 12 bytes of palette data at TVT1+16, used to set the
 EQUB &B0, &A0          \ mode 4 palette in LINSCN when we hit vertical sync,
 EQUB &D0, &C0          \ so the palette is set to monochrome when we start to
 EQUB &90, &80          \ draw the first row of the screen
 EQUB &77, &67
 EQUB &37, &27

\ ******************************************************************************
\
\       Name: IRQ1
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: The main screen-mode interrupt handler (IRQ1V points here)
\  Deep dive: The split-screen mode in BBC Micro Elite
\
\ ------------------------------------------------------------------------------
\
\ The main interrupt handler, which implements Elite's split-screen mode.
\
\ IRQ1V is set to point to IRQ1 by the loading process.
\
\ ******************************************************************************

.LINSCN

                        \ This is called from the interrupt handler below, at
                        \ the start of each vertical sync (i.e. when the screen
                        \ refresh starts)

 LDA #30                \ Set the line scan counter to a non-zero value, so
 STA DL                 \ routines like WSCAN can set DL to 0 and then wait for
                        \ it to change to non-zero to catch the vertical sync

 STA VIA+&44            \ Set 6522 System VIA T1C-L timer 1 low-order counter
                        \ (SHEILA &44) to 30

 LDA #VSCAN             \ Set 6522 System VIA T1C-L timer 1 high-order counter
 STA VIA+&45            \ (SHEILA &45) to VSCAN (57) to start the T1 counter
                        \ counting down from 14622 at a rate of 1 MHz

 LDA HFX                \ If HFX is non-zero, jump to VNT1 to set the mode 5
 BNE VNT1               \ palette instead of switching to mode 4, which will
                        \ have the effect of blurring and colouring the top
                        \ screen. This is how the white hyperspace rings turn
                        \ to colour when we do a hyperspace jump, and is
                        \ triggered by setting HFX to 1 in routine LL164

 LDA #%00001000         \ Set the Video ULA control register (SHEILA &20) to
 STA VIA+&20            \ %00001000, which is the same as switching to mode 4
                        \ (i.e. the top part of the screen) but with no cursor

.VNT3

 LDA TVT1+16,Y          \ Copy the Y-th palette byte from TVT1+16 to SHEILA &21
 STA VIA+&21            \ to map logical to actual colours for the bottom part
                        \ of the screen (i.e. the dashboard)

 DEY                    \ Decrement the palette byte counter

 BPL VNT3               \ Loop back to VNT3 until we have copied all the
                        \ palette bytes

 LDA LASCT              \ Decrement the value of LASCT, but if we go too far
 BEQ P%+5               \ and it becomes negative, bump it back up again (this
 DEC LASCT              \ controls the pulsing of pulse lasers)

 PLA                    \ Otherwise restore Y from the stack
 TAY

 LDA VIA+&41            \ Read 6522 System VIA input register IRA (SHEILA &41)

 LDA &FC                \ Set A to the interrupt accumulator save register,
                        \ which restores A to the value it had on entering the
                        \ interrupt

 RTI                    \ Return from interrupts, so this interrupt is not
                        \ passed on to the next interrupt handler, but instead
                        \ the interrupt terminates here

.IRQ1

 TYA                    \ Store Y on the stack
 PHA

 LDY #11                \ Set Y as a counter for 12 bytes, to use when setting
                        \ the dashboard palette below

 LDA #%00000010         \ Read the 6522 System VIA status byte bit 1 (SHEILA
 BIT VIA+&4D            \ &4D), which is set if vertical sync has occurred on
                        \ the video system

 BNE LINSCN             \ If we are on the vertical sync pulse, jump to LINSCN
                        \ to set up the timers to enable us to switch the
                        \ screen mode between the space view and dashboard

 BVC jvec               \ Read the 6522 System VIA status byte bit 6, which is
                        \ set if timer 1 has timed out. We set the timer in
                        \ LINSCN above, so this means we only run the next bit
                        \ if the screen redraw has reached the boundary between
                        \ the space view and the dashboard. Otherwise bit 6 is
                        \ clear and we aren't at the boundary, so we jump to
                        \ jvec to pass control to the next interrupt handler

 ASL A                  \ Double the value in A to 4

 STA VIA+&20            \ Set the Video ULA control register (SHEILA &20) to
                        \ %00000100, which is the same as switching to mode 5,
                        \ (i.e. the bottom part of the screen) but with no
                        \ cursor

 LDA ESCP               \ If an escape pod is fitted, jump to VNT1 to set the
 BNE VNT1               \ mode 5 palette differently (so the dashboard is a
                        \ different colour if we have an escape pod)

 LDA TVT1,Y             \ Copy the Y-th palette byte from TVT1 to SHEILA &21
 STA VIA+&21            \ to map logical to actual colours for the bottom part
                        \ of the screen (i.e. the dashboard)

 DEY                    \ Decrement the palette byte counter

 BPL P%-7               \ Loop back to the LDA TVT1,Y instruction until we have
                        \ copied all the palette bytes

.jvec

 PLA                    \ Restore Y from the stack
 TAY

 JMP (VEC)              \ Jump to the address in VEC, which was set to the
                        \ original IRQ1V vector by the loading process, so this
                        \ instruction passes control to the next interrupt
                        \ handler

.VNT1

 LDY #7                 \ Set Y as a counter for 8 bytes

 LDA TVT1+8,Y           \ Copy the Y-th palette byte from TVT1+8 to SHEILA &21
 STA VIA+&21            \ to map logical to actual colours for the bottom part
                        \ of the screen (i.e. the dashboard)

 DEY                    \ Decrement the palette byte counter

 BPL VNT1+2             \ Loop back to the LDA TVT1+8,Y instruction until we
                        \ have copied all the palette bytes

 BMI jvec               \ Jump up to jvec to pass control to the next interrupt
                        \ handler (this BMI is effectively a JMP as we didn't
                        \ loop back with the BPL above, so BMI is always true)

                        \ Port: S1%, NA% (the last saved commander), CHK2, CHK
                        \ and BRBR1 are in the resident block A
                        \ (elite-resident.asm), so that the screen's second
                        \ buffer can use main RAM from &1000 up; block B now
                        \ holds only the loading screen's palettes and
                        \ interrupt handler

 COPYBLOCK TVT1, P%, TVT1code

 ORG TVT1code + P% - TVT1

\ ******************************************************************************
\
\       Name: Elite loader (Part 3 of 3)
\       Type: Subroutine
\   Category: Loader
\    Summary: Include binaries for the loading screen images
\
\ ------------------------------------------------------------------------------
\
\ The loader bundles a number of binary files in with the loader code, and moves
\ them to their correct memory locations in part 1 above.
\
\ This section is encrypted by EOR'ing with &A5. The encryption is done by the
\ elite-checksum.py script, and decryption is done in part 1 above, at the same
\ time as each block is moved to its correct location.
\
\ This part includes three files containing images, which are all moved into
\ screen memory by the loader:
\
\   * P.A-SOFT.bin contains the "ACORNSOFT" title across the top of the loading
\     screen, which gets moved to screen address &6100, on the second character
\     row of the monochrome mode 4 screen
\
\   * P.ELITE.bin contains the "ELITE" title across the top of the loading
\     screen, which gets moved to screen address &6300, on the fourth character
\     row of the monochrome mode 4 screen
\
\   * P.(C)ASFT.bin contains the "(C) Acornsoft 1984" title across the bottom
\     of the loading screen, which gets moved to screen address &7600, the
\     penultimate character row of the monochrome mode 4 screen, just above the
\     dashboard
\
\ There are three other binaries bundled into the loader, which are described in
\ part 2 above.
\
\ ******************************************************************************

.ELITE

 INCBIN "1-source-files/images/P.ELITE.bin"

.ASOFT

 INCBIN "1-source-files/images/P.A-SOFT.bin"

.CpASOFT

 INCBIN "1-source-files/images/P.(C)ASFT.bin"

IF _MATCH_ORIGINAL_BINARIES

 IF _STH_DISC

  EQUB &F0, &00, &00, &00, &00, &00, &00, &00   \ These bytes appear to be
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00   \ unused and just contain random
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00   \ workspace noise left over from
  EQUB &F0, &80, &80, &80, &80, &C0, &A4, &96   \ the BBC Micro assembly process
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &33, &22, &33, &22, &33, &00
  EQUB &F0, &00, &AA, &22, &22, &22, &BB, &00
  EQUB &F0, &00, &22, &22, &22, &22, &AA, &00
  EQUB &F0, &00, &EE, &44, &44, &44, &44, &00
  EQUB &F0, &00, &EE, &88, &CC, &88, &EE, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00

ELIF _SRAM_DISC

  EQUB &F0, &00, &00, &00, &00, &00, &00, &00   \ These bytes appear to be
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00   \ unused and just contain random
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00   \ workspace noise left over from
  EQUB &F0, &80, &80, &80, &80, &C0, &A4, &96   \ the BBC Micro assembly process
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &33, &22, &33, &22, &33, &00
  EQUB &F0, &00, &AA, &22, &22, &22, &BB, &00
  EQUB &F0, &00, &22, &22, &22, &22, &AA, &00
  EQUB &F0, &00, &EE, &44, &44, &44, &44, &00
  EQUB &F0, &00, &EE, &88, &CC, &88, &EE, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00, &00, &00
  EQUB &F0, &00, &00, &00, &00, &00

 ELIF _IB_DISC

  SKIP 158              \ These bytes appear to be unused

 ENDIF

ELSE

IF _STH_DISC OR _IB_DISC

 SKIP 158               \ These bytes appear to be unused

ELIF _SRAM_DISC

 SKIP 142               \ These bytes appear to be unused

ENDIF

ENDIF

\ ******************************************************************************
\
\       Name: PROT4
\       Type: Subroutine
\   Category: Loader
\    Summary: Fetch the address of the keyboard translation table before
\             carrying on with the copy protection
\
\ ******************************************************************************

IF _SRAM_DISC

.PROT4

 LDA #172               \ Call OSBYTE 172 to read the address of the MOS
 LDX #0                 \ keyboard translation table into (Y X)
 LDY #255
 JSR OSBYTE

 STX TRTB%              \ Store the address of the keyboard translation table in
 STY TRTB%+1            \ TRTB%(1 0)

 JMP PROT1              \ Call PROT1 to calculate checksums into CHKSM,
                        \ returning from the subroutine using a tail call

ENDIF

\ ******************************************************************************
\
\ Save ELITE4.unprot.bin
\
\ ******************************************************************************

 PRINT "S.ELITE4 ", ~CODE%, " ", ~P%, " ", ~LOAD%, " ", ~LOAD%
 SAVE "3-assembled-output/ELITE4.unprot.bin", CODE%, P%, LOAD%

 PRINT "Addresses for the commander checksum in elite-checksum.py"
 PRINT "Load address = ", ~CODE%
 PRINT "TVT1code = ", ~TVT1code
 PRINT "TVT1 = ", ~TVT1
 PRINT "NA% = ", ~NA%
 PRINT "CHK2 = ", ~CHK2
