\ ============================================================================
\ raster_wq.asm -- bank 5's query for the frame layer (Model B): r_wq, which
\ R_GETW (gfx-raster_dq.asm) enters with A = &40, in the room below the per-x
\ tables (gfx-bank5.asm)
\ ============================================================================

\ r_wq (R_GETW with A = &40): for the frame layer's text and sights, what was
\ written on this buffer this frame (R_WL..R_WR: the repair's writes) and
\ what is to be repaired next time (its dirty extents: this frame's shapes).
\ Inputs: MBOX+&30..&32, a mask of text rows (bit r AND 7 of byte r DIV 8 for
\ row r = 0..23); MBOX+&33 non-zero to look at the sights. Outputs: for each
\ text row r in the mask, MBOX + 2r and + 2r + 1 = the leftmost and
\ rightmost pixel of the union of both extents over its lines 8r..8r+7 (the
\ rightmost 0: none); MBOX+&34 bit 7 set if the sights are covered: on row 96,
\ an extent meeting x = 108..148, or on rows 76..116 one containing x = 128

QSGX = 128
QSGY = 96
QSGIN = 20

.r_wq
{
  LDA #HI(R_DIRTYL0)      \ this buffer's dirty extents (buffer 1's are &300 on)
  LDX R_PRBUF
  BEQ P%+4
  LDA #HI(R_DIRTYL1)
  STA dl1+2
  STA dl2+2
  STA sl1+2
  CLC
  ADC #HI(R_DIRTYR0) - HI(R_DIRTYL0)
  STA dr1+2
  STA dr2+2
  STA sr1+2
  LDA #0
  STA MBOX+&34
  LDX #23                 \ the text rows, 23 down to 0
.row
  TXA
  LSR A
  LSR A
  LSR A
  TAY
  TXA
  AND #7
  STX RZ_T2
  TAX
  LDA MBOX+&30,Y
  AND bits,X
  BEQ next
  LDA #255                \ the union over the row's eight lines
  STA RZ_T0
  LDA #0
  STA RZ_T1
  LDA RZ_T2
  ASL A
  ASL A
  ASL A
  TAY
  ADC #8                  \ (C = 0: 8 * 23 + 8 < 256)
  STA RZ_T3
.line
  LDA R_WR,Y
  BEQ ln2
  CMP RZ_T1
  BCC P%+4
  STA RZ_T1
  LDA R_WL,Y
  CMP RZ_T0
  BCS ln2
  STA RZ_T0
.ln2
.dr1
  LDA R_DIRTYR0,Y         \ (patched: this buffer's)
  BEQ ln3
  CMP RZ_T1
  BCC P%+4
  STA RZ_T1
.dl1
  LDA R_DIRTYL0,Y         \ (patched)
  CMP RZ_T0
  BCS ln3
  STA RZ_T0
.ln3
  INY
  CPY RZ_T3
  BCC line
  LDA RZ_T2
  ASL A
  TAX
  LDA RZ_T0
  STA MBOX,X
  LDA RZ_T1
  STA MBOX+1,X
.next
  LDX RZ_T2
  DEX
  BPL row
  LDA MBOX+&33            \ the sights
  BEQ done
  LDY #QSGY               \ row 96: an extent meeting 108..148
  LDA R_WR,Y
  BEQ s2
  CMP #QSGX-QSGIN
  BCC s2
  LDA R_WL,Y
  CMP #QSGX+QSGIN+1
  BCC hit
.s2
.dr2
  LDA R_DIRTYR0,Y         \ (patched)
  BEQ s3
  CMP #QSGX-QSGIN
  BCC s3
.dl2
  LDA R_DIRTYL0,Y         \ (patched)
  CMP #QSGX+QSGIN+1
  BCC hit
.s3
  LDY #QSGY-QSGIN         \ rows 76..116: an extent containing 128
.col
  LDA R_WR,Y              \ (WR >= 128: bit 7; then WL <= 128)
  BPL c2
  LDA R_WL,Y
  CMP #QSGX+1
  BCC hit
.c2
.sr1
  LDA R_DIRTYR0,Y         \ (patched)
  BPL c3
.sl1
  LDA R_DIRTYL0,Y         \ (patched)
  CMP #QSGX+1
  BCC hit
.c3
  INY
  CPY #QSGY+QSGIN+1
  BCC col
.done
  RTS
.hit
  LDA #&80
  STA MBOX+&34
  RTS
.bits EQUB 1, 2, 4, 8, 16, 32, 64, 128
}
