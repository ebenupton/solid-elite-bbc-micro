\ ******************************************************************************
\
\ gfx-dlayer.asm - the disc layer (Model B: in the flight code's cold bank)
\
\ The sun or the planet (the bigger, the sun if not smaller, as the BBC
\ Master port's disc layer chooses) stays on each screen buffer from frame
\ to frame, and each frame only what changed is drawn: the disc is not
\ marked dirty, so the repair leaves it alone except where something else
\ was drawn over it. A crater planet's crater is a band of a second colour
\ (the Master port's dark crater) across the disc's rows, as the Master
\ draws a planet without meridians; a planet with meridians and an equator
\ keeps them as lines over a plain disc (bank F's), as before. The other
\ disc, if both are on the screen, is bank F's, drawn whole over this one.
\
\ Where things are: this code, the frame's disc records and each buffer's
\ rows (what the disc left on each row of the buffer: its span, and its
\ band if it had one) are in the cold bank, which has the room. The flight
\ code's hooks record the disc (DL_PLAN, from CIRCLE's and SUN's record
\ paths, beside bank F's F_PLANET) and a crater's points (DL_CURVE and
\ DL_POINT, from PLS22 and BLINE, for a planet whose TYPE is not 128). The
\ frame layer (bank F) calls DL_FRAME by a far call after the repair. It
\ asks bank R for the repair's extents (R_WL, R_WR: what the repair blacked
\ on each row) twenty rows at a time (T_GETW, into the mailbox), works out
\ each row's changes and writes them into the back buffer itself, which is
\ main RAM (up to DL_DIR bytes a span, the middle bytes through an unrolled
\ run); a longer span would be queued in the mailbox for bank R's row runs
\ (T_DRAINQ, nine at a time), so bank R is paged in only a few times a
\ frame.
\
\ A row's changes: the old disc's pixels that the new one does not cover go
\ black; the new disc's pixels that the old one did not cover, or that the
\ band moved over, or that the repair blacked, are filled. When the disc on
\ the buffer was the other one (the sun, the planet), or none is known (a
\ blanked buffer: GDL), all of the new disc is filled. When the disc is
\ where it was two frames ago on this buffer, with no band, only what the
\ repair blacked is filled (dl_srow).
\
\ A small disc (radius below DL_MINR, which is most often a moving one)
\ costs less drawn whole each frame than kept: after this buffer's kept
\ disc (if any) is taken off, it is written row by row and marked dirty
\ (T_GETW with A = &80 + n: R_MARKDIRTY for each span queued), for the
\ repair to take off next time, as bank F's discs are.
\
\ ******************************************************************************

DLZ = &D2               \ the zero page (F_FRAME saves &D2-&E1 and gives them
dl_sp = DLZ             \ back): a screen pointer
dl_t = DLZ + 2          \ temporaries
dl_u = DLZ + 3
dl_a = DLZ + 4          \ the span being drawn, its colour byte
dl_b = DLZ + 5
dl_c = DLZ + 6
dl_y = DLZ + 7          \ the row
dl_nl = DLZ + 8         \ the row's new span
dl_nr = DLZ + 9
dl_ol = DLZ + 10        \ and its old one
dl_or = DLZ + 11
dl_wl = DLZ + 12        \ the repair's extent on the row
dl_wr = DLZ + 13
dl_rbl = DLZ + 14       \ the row's screen address (its byte in column 0)
dl_rbh = DLZ + 15

DL_WQ = MBOX            \ the repair's extents, (WL, WR) for 20 rows
DL_Q = MBOX + &28       \ the queue: (row, left, right, colour byte), 9
DL_QN = 9               \ (to MBOX + &4B: R_SCOL, at &4C, is kept)
 ASSERT DL_Q + 4 * DL_QN <= MBOX + &4C   \ (R_SCOL, gfx-rws.asm)

\ ------------------------------------------------------------------------------
\ The records, from the flight code's hooks (between frames)
\ ------------------------------------------------------------------------------

\ DL_PLAN: CIRCLE or SUN is recording a disc: centre (K3, K4), radius K,
\ TYPE odd for the sun. Keeps A, X, Y.

.DL_PLAN
 PHA
 TXA
 PHA
 LDX #0                 \ X = 0: the planet's record, 7: the sun's
 LDA TYPE
 LSR A
 BCC dlp1
 LDX #7
.dlp1
 LDA K3
 STA dl_px,X
 LDA K3+1
 STA dl_px+1,X
 LDA K4
 STA dl_py,X
 LDA K4+1
 STA dl_py+1,X
 LDA K
 STA dl_pr,X
 LDA TYPE
 STA dl_pt,X
 CPX #0                 \ the planet: its crater's points are to come
 BNE dlpl2
 STX dl_np
 STX dl_con
.dlpl2
 PLA
 TAX
 PLA
 RTS

\ DL_CURVE: PLS22 starts a crater's ellipse. DL_POINT: BLINE's next point
\ (K6, K5+2). Keep A, X, Y.

.DL_CURVE
 PHA
 LDA dl_np
 STA dl_cvs             \ (one crater a planet: its first point)
 LDA #&FF
 STA dl_con
 PLA
 RTS

.DL_POINT
 PHA
 TXA
 PHA
 LDX dl_np
 CPX #DL_NPT
 BCS dlpt9
 LDA K6
 STA dl_ptxl,X
 LDA K6+1
 STA dl_ptxh,X
 LDA K5+2
 STA dl_ptyl,X
 LDA K5+3
 STA dl_ptyh,X
 INC dl_np
.dlpt9
 PLA
 TAX
 PLA
 RTS

\ ------------------------------------------------------------------------------
\ The frame
\ ------------------------------------------------------------------------------

\ DL_FRAME: the disc layer on buffer DL_BACK (after the repair, before the
\ frame layer's other drawing). Returns A = the disc drawn (0 none, 1 the sun,
\ 2 the planet), which the frame layer then leaves out. Clobbers X, Y.

.DL_FRAME
 STA DL_BACK            \ the buffer
 STX dl_on              \ the discs recorded (bit 0 the sun, bit 1 the planet)
 TAX                    \ the buffer blanked since its last disc (GDL's bit
 INX                    \ for it clear): no old disc on it
 TXA
 AND GDL
 BNE dlf0
 LDX DL_BACK
 STA dl_kind,X          \ (A = 0)
 STA dl_ob,X
 LDA #&FF
 STA dl_ot,X
.dlf0
 LDX #0                 \ the layer: the planet, or the sun if it is the only
 LDA dl_on              \ disc or not smaller (X = the record, dl_lay = 2 or
 AND #2                 \ 1, 0 none)
 BEQ dlf1
 LDA dl_on
 LSR A
 BCC dlf2
 LDA dl_sr
 CMP dl_pr
 BCC dlf2
.dlf1
 LDX #7
 LDA dl_on
 LSR A
 BCC dlf3
 LDA #1
 BNE dlf4
.dlf2
 LDA #2
 BNE dlf4
.dlf3
 LDA #0
.dlf4
 STA dl_lay
 BNE dlf4a
 JMP dlf5
.dlf4a
 LDA dl_px,X            \ the layer's centre, radius and colours
 STA dl_cx
 LDA dl_px+1,X
 STA dl_cx+1
 LDA dl_py,X
 STA dl_cy
 LDA dl_py+1,X
 STA dl_cy+1
 LDA dl_pr,X
 STA dl_r
 LDY dl_lay
 LDA dl_cae-1,Y
 STA dl_ae
 LDA dl_cao-1,Y
 STA dl_ao
 JSR dl_hw              \ its half-widths
 LDA #0                 \ dl_inx: &FF if cx - r >= 2 and cx + r <= 253
 STA dl_inx
 LDA dl_cx+1
 BNE dlf4x
 LDA dl_cx
 SEC
 SBC dl_r
 BCC dlf4x
 CMP #2
 BCC dlf4x
 LDA dl_cx
 CLC
 ADC dl_r
 BCS dlf4x
 CMP #254
 BCS dlf4x
 DEC dl_inx
.dlf4x
 JSR dl_rows            \ its rows, dl_nt..dl_nb (none: dl_nt > dl_nb)
 LDA #0                 \ its band: a crater planet's crater
 STA dl_band
 LDA dl_lay
 CMP #2
 BNE dlf6
 LDA dl_con
 BEQ dlf5b
 JSR dl_crater
.dlf5b
 LDA #0                 \ a small disc (radius below DL_MINR) is not kept: it
 STA dl_bmode           \ is drawn whole and marked dirty, for the repair to
 LDA dl_r               \ take off (dl_bmode &FF, after this buffer's layer
 CMP #DL_MINR           \ disc, if any, is taken off as for no disc)
 BCS dlf6
 DEC dl_bmode
 LDA dl_lay
 STA dl_blay
 LDA dl_band
 STA dl_bband
 LDA dl_nt
 STA dl_bnt
 LDA dl_nb
 STA dl_bnb
 LDA #0
 STA dl_lay
.dlf5
 LDA #&FF               \ no disc: no rows, no band
 STA dl_nt
 LDA #0
 STA dl_nb
 STA dl_band
.dlf6
 LDX DL_BACK            \ this buffer's rows: the tables' pages, and whether
 LDA dl_hl,X            \ its old disc was this one
 STA dlo_l1+2
 STA dlo_l2+2
 LDA dl_hr,X
 STA dlo_r1+2
 STA dlo_r2+2
 LDA dl_h0,X
 STA dlo_a1+2
 STA dlo_a2+2
 LDA dl_h1,X
 STA dlo_b1+2
 STA dlo_b2+2
 LDA dl_base,X           \ (the buffer's base, for dl_row)
 STA dl_bb
 LDA dl_ot,X
 STA dl_oot
 LDA dl_ob,X
 STA dl_oob
 LDA #0
 STA dl_same
 LDA dl_kind,X
 BEQ dlf7
 CMP dl_lay
 BNE dlf7
 DEC dl_same            \ (&FF: the old rows are this disc's)
.dlf7
 LDA dl_lay
 STA dl_kind,X
 LDA #0                 \ dl_stat: &FF if the disc is where it was on this
 STA dl_stat            \ buffer, the same size and with no band then or now:
 BIT dl_same            \ then only what the repair blacked needs filling
 BPL dlf7n
 LDA dl_band
 ORA dl_sbd,X
 BNE dlf7n
 LDA dl_cx
 CMP dl_scx,X
 BNE dlf7n
 LDA dl_cx+1
 CMP dl_scx+2,X
 BNE dlf7n
 LDA dl_cy
 CMP dl_scy,X
 BNE dlf7n
 LDA dl_cy+1
 CMP dl_scy+2,X
 BNE dlf7n
 LDA dl_r
 CMP dl_srr,X
 BNE dlf7n
 DEC dl_stat
.dlf7n
 LDA dl_cx              \ (for next time)
 STA dl_scx,X
 LDA dl_cx+1
 STA dl_scx+2,X
 LDA dl_cy
 STA dl_scy,X
 LDA dl_cy+1
 STA dl_scy+2,X
 LDA dl_r
 STA dl_srr,X
 LDA dl_sbd,X           \ (dl_obd: whether the last frame on it had a band)
 STA dl_obd
 LDA dl_band
 STA dl_sbd,X
 LDA dl_hl,X            \ (dl_srow's tables)
 STA dls_l+2
 LDA dl_hr,X
 STA dls_r+2
 LDA dl_nt              \ the rows to visit: lo = min(new top, old top) ..
 CMP dl_oot
 BCC P%+5
 LDA dl_oot
 STA dl_lo
 LDA dl_nb              \ .. hi = max(new bottom, old bottom)
 CMP dl_oob
 BCS P%+5
 LDA dl_oob
 STA dl_hi
 LDA #0
 STA dl_qn
 LDY dl_lo
 CPY #192
 BCS dlf9
 CPY dl_hi
 BEQ dlf8
 BCS dlf9
.dlf8
 JSR dl_batch           \ twenty rows at a time from Y
 CPY dl_hi
 BEQ dlf8
 BCC dlf8
.dlf9
 JSR dl_drain           \ what is left in the queue
 LDX DL_BACK            \ the new rows are the old ones next time
 LDA dl_nt
 STA dl_ot,X
 LDA dl_nb
 STA dl_ob,X
 INX                    \ GDL: whether the buffer has a disc now
 TXA
 ORA GDL
 LDY dl_lay
 BNE P%+5
 EOR dl_bit-1,X
 STA GDL
 BIT dl_bmode           \ a small disc: draw it now
 BPL dlf9b
 JSR dl_small
.dlf9b
 LDA #0                 \ the crater's points are used
 STA dl_np
 STA dl_con
 LDA dl_lay
 RTS

\ dl_small: the small disc, whole: each row's span (with the band) painted
\ and marked dirty (in batches, T_GETW with A = &80 + the count)

.dl_small
 LDA dl_blay
 STA dl_lay
 LDA dl_bband
 STA dl_band
 LDA dl_bnt
 STA dl_nt
 LDA dl_bnb
 STA dl_nb
 LDA #0
 STA dl_qn
 LDY dl_nt
 CPY #192
 BCS dlsm9
 CPY dl_nb
 BEQ dlsm1
 BCS dlsm9
.dlsm1
 STY dl_y
 TYA                    \ the row's screen address
 AND #7
 STA dl_rbl
 TYA
 LSR A
 LSR A
 AND #&FE
 CLC
 ADC dl_bb
 STA dl_rbh
 LDA #0
 STA dl_n0
 STA dl_n1
 JSR dl_span
 LDA dl_nr
 CMP dl_nl
 BCC dlsm2
 STA dl_b
 LDA dl_nl
 STA dl_a
 JSR dl_fill
 LDX dl_qn              \ mark it (the queue: row, left, right)
 CPX #DL_QN * 4
 BCC dlsm3
 JSR dl_mflush
 LDX #0
.dlsm3
 LDA dl_y
 STA DL_Q,X
 LDA dl_nl
 STA DL_Q+1,X
 LDA dl_nr
 STA DL_Q+2,X
 TXA
 CLC
 ADC #4
 STA dl_qn
.dlsm2
 LDY dl_y
 CPY dl_nb
 INY
 BCC dlsm1
 JSR dl_mflush
.dlsm9
 RTS

.dl_mflush              \ bank R marks the queue's spans dirty
 LDA dl_qn
 BEQ dlmf9
 LSR A
 LSR A
 ORA #&80
 JSR T_GETW
 LDA #0
 STA dl_qn
.dlmf9
 RTS

\ dl_batch: rows Y .. min(Y + 19, dl_hi): the repair's extents from bank R,
\ then each row; Y = the row after

.dl_batch
 STY dl_y
 LDA dl_hi
 SEC
 SBC dl_y
 CMP #20
 BCC P%+4
 LDA #19
 STA dl_n               \ rows - 1
 CLC
 ADC #1
 LDY dl_y
 JSR T_GETW             \ (A rows from row Y into DL_WQ)
 LDX #0
.dlb1
 STX dl_wi
 LDA DL_WQ,X            \ the repair's extent on this row
 STA dl_wl
 LDA DL_WQ+1,X
 STA dl_wr
 BIT dl_stat
 BMI dlb2
 JSR dl_row
 JMP dlb3
.dlb2
 JSR dl_srow
.dlb3
 LDX dl_wi
 INX
 INX
 INC dl_y
 DEC dl_n
 BPL dlb1
 LDY dl_y
 RTS

\ ------------------------------------------------------------------------------
\ A row
\ ------------------------------------------------------------------------------

\ dl_row: row dl_y. New: dl_nl..dl_nr (none: dl_nl > dl_nr), band dl_n0 ..
\ dl_n1 - 1 (none: dl_n0 >= dl_n1); old: the buffer's tables (if the row is in
\ the old rows), dl_ol..dl_or, dl_o0..dl_o1; the repair's extent dl_wl..dl_wr
\ (dl_wr = 0: none)

.dl_row
 LDY dl_y
 TYA                    \ the row's screen address (dl_rbl, dl_rbh: its byte in
 AND #7                 \ column 0)
 STA dl_rbl
 TYA
 LSR A
 LSR A
 AND #&FE
 CLC
 ADC dl_bb
 STA dl_rbh
 LDA #255               \ the new span
 STA dl_nl
 LDA #0
 STA dl_nr
 STA dl_n0
 STA dl_n1
 CPY dl_nt
 BCC dlr1
 CPY dl_nb
 BEQ P%+4
 BCS dlr1
 JSR dl_span            \ (into dl_nl, dl_nr; dl_n0, dl_n1)
.dlr1
 LDA #255               \ the old one
 STA dl_ol
 LDA #0
 STA dl_or
 STA dl_o0
 STA dl_o1
 CPY dl_oot
 BCC dlr2
 CPY dl_oob
 BEQ P%+4
 BCS dlr2
.dlo_l1
 LDA &FF00,Y            \ (patched: this buffer's tables)
 STA dl_ol
.dlo_r1
 LDA &FF00,Y
 STA dl_or
 BIT dl_obd             \ (the band's tables only if the last frame on this
 BPL dlr2               \ buffer had a band)
.dlo_a1
 LDA &FF00,Y
 STA dl_o0
.dlo_b1
 LDA &FF00,Y
 STA dl_o1
.dlr2
 LDA dl_nl              \ keep the new row for next time
.dlo_l2
 STA &FF00,Y
 LDA dl_nr
.dlo_r2
 STA &FF00,Y
 LDA dl_band            \ (and the band, if there is one)
 BEQ dlr2b
 LDA dl_n0
.dlo_a2
 STA &FF00,Y
 LDA dl_n1
.dlo_b2
 STA &FF00,Y
.dlr2b
 BIT dl_same            \ the old disc another (or none known): fill all of
 BMI dlr3               \ the new, black all of the old outside it
 JSR dl_oldout
 LDA dl_nl
 STA dl_a
 LDA dl_nr
 STA dl_b
 JMP dl_fill
.dlr3
 LDA dl_wr              \ not repaired and no band now or before: just the
 ORA dl_n1              \ edges' moves (the usual row), if both spans are
 ORA dl_o1              \ there and overlap
 BNE dlr3g
 LDA dl_nr
 CMP dl_nl
 BCC dlr3g
 LDA dl_or
 CMP dl_ol
 BCC dlr3g
 CMP dl_nl              \ (OR >= NL)
 BCC dlr3g
 LDA dl_nr              \ (NR >= OL)
 CMP dl_ol
 BCC dlr3g
 LDA dl_nl              \ the left edge: NL < OL: NL .. OL - 1 filled; NL >
 CMP dl_ol              \ OL: OL .. NL - 1 black
 BEQ dlr3r
 BCS dlr3a
 STA dl_a
 LDX dl_ol
 DEX
 STX dl_b
 JSR dlfa
 JMP dlr3r
.dlr3a
 TAX
 DEX
 STX dl_b
 LDA dl_ol
 STA dl_a
 JSR dl_black
.dlr3r
 LDA dl_nr              \ the right edge: NR > OR: OR + 1 .. NR filled; NR <
 CMP dl_or              \ OR: NR + 1 .. OR black
 BEQ dlr3x
 BCC dlr3b
 STA dl_b
 LDX dl_or
 INX
 STX dl_a
 JMP dlfa
.dlr3b
 TAX
 INX
 STX dl_a
 LDA dl_or
 STA dl_b
 JMP dl_black
.dlr3x
 RTS
.dlr3g
 LDA dl_wr              \ unchanged and not repaired: nothing to do
 BNE dlr4
 LDA dl_nl
 CMP dl_ol
 BNE dlr4
 LDA dl_nr
 CMP dl_or
 BNE dlr4
 LDA dl_n0
 CMP dl_o0
 BNE dlr4
 LDA dl_n1
 CMP dl_o1
 BNE dlr4
 RTS
.dlr4
 JSR dl_oldout          \ the old span's pixels outside the new one: black
 LDA dl_nr              \ no new span: done
 CMP dl_nl
 BCS dlr4a
 RTS
.dlr4a
 LDA dl_ol              \ no old span: fill all of the new
 CMP dl_or
 BEQ dlr5
 BCC dlr5
 LDA dl_nl
 STA dl_a
 LDA dl_nr
 STA dl_b
 JMP dl_fill
.dlr5
 LDA dl_nl              \ left of the old span: NL .. min(NR, OL - 1)
 CMP dl_ol
 BCS dlr6
 STA dl_a
 LDX dl_ol
 DEX
 CPX dl_nr
 BCC P%+4
 LDX dl_nr
 STX dl_b
 JSR dl_fill
.dlr6
 LDA dl_or              \ right of it: max(NL, OR + 1) .. NR
 CMP dl_nr
 BCS dlr7
 ADC #1                 \ (C = 0)
 CMP dl_nl
 BCS P%+4
 LDA dl_nl
 STA dl_a
 LDA dl_nr
 STA dl_b
 JSR dl_fill
.dlr7
 LDA dl_o0              \ the band's changes: none before: all of the new
 CMP dl_o1              \ band; none now: all of the old (in the new span);
 BCC dlr7a              \ else where its edges moved, min(N0, O0) ..
 LDA dl_n0              \ max(N0, O0) - 1, and the same for N1, O1
 CMP dl_n1
 BCS dlr8
 STA dl_a
 LDX dl_n1
 DEX
 STX dl_b
 JSR dl_cfill
 JMP dlr8
.dlr7a
 LDA dl_n0
 CMP dl_n1
 BCC dlr7b
 LDA dl_o0
 STA dl_a
 LDX dl_o1
 DEX
 STX dl_b
 JSR dl_cfill
 JMP dlr8
.dlr7b
 LDA dl_n0
 LDX dl_o0
 JSR dl_moved
 LDA dl_n1
 LDX dl_o1
 JSR dl_moved
.dlr8
 LDA dl_wr              \ and what the repair blacked: max(NL, WL) ..
 BEQ dlr9               \ min(NR, WR)
 CMP dl_nr
 BCC P%+4
 LDA dl_nr
 STA dl_b
 LDA dl_wl
 CMP dl_nl
 BCS P%+4
 LDA dl_nl
 STA dl_a
 JMP dl_fill            \ (which checks a <= b)
.dlr9
 RTS

\ dl_srow: row dl_y of a disc that has not changed on this buffer (dl_stat):
\ just fill what the repair blacked in its span

.dl_srow
 LDA dl_wr
 BEQ dlsr9
 LDY dl_y
 CPY dl_nt
 BCC dlsr9
 CPY dl_nb
 BEQ P%+4
 BCS dlsr9
 TYA                    \ the row's screen address
 AND #7
 STA dl_rbl
 TYA
 LSR A
 LSR A
 AND #&FE
 CLC
 ADC dl_bb
 STA dl_rbh
.dls_r
 LDA &FF00,Y            \ (patched: the buffer's span right)
 CMP dl_wr              \ b = min(OR, WR)
 BCC P%+4
 LDA dl_wr
 STA dl_b
.dls_l
 LDA &FF00,Y            \ a = max(OL, WL)
 CMP dl_wl
 BCS P%+4
 LDA dl_wl
 STA dl_a
 LDA dl_b
 CMP dl_a
 BCC dlsr9
 JMP dlfa
.dlsr9
 RTS

\ dl_moved: A = a new band edge, X = the old one: if they differ, fill the
\ new pixels between them (as far as the new span reaches)

.dl_moved
 STX dl_t
 CMP dl_t
 BEQ dlm9
 BCC dlm1
 STA dl_b               \ new > old: old .. new - 1
 STX dl_a
 DEC dl_b
 JMP dl_cfill
.dlm1
 STA dl_a               \ new < old: new .. old - 1
 DEX
 STX dl_b

\ dl_cfill: dl_fill, clipped to the new span

.dl_cfill
 LDA dl_a               \ clipped to the new span
 CMP dl_nl
 BCS P%+6
 LDA dl_nl
 STA dl_a
 LDA dl_b
 CMP dl_nr
 BCC P%+6
 LDA dl_nr
 STA dl_b
 JMP dl_fill            \ (which checks a <= b)
.dlm9
 RTS

\ dl_oldout: black the old span's pixels outside the new span (or all of it,
\ with no new span): OL .. min(OR, NL - 1) and max(OL, NR + 1) .. OR

.dl_oldout
 LDA dl_ol
 CMP dl_or
 BEQ P%+4
 BCS dlx9               \ no old span
 LDA dl_nl
 CMP dl_nr
 BEQ dlx1
 BCC dlx1
 LDA dl_ol              \ no new span: all of it
 STA dl_a
 LDA dl_or
 STA dl_b
 JMP dl_black
.dlx1
 LDA dl_ol
 CMP dl_nl
 BCS dlx2
 STA dl_a
 LDX dl_nl
 DEX
 CPX dl_or
 BCC P%+4
 LDX dl_or
 STX dl_b
 JSR dl_black
.dlx2
 LDA dl_nr
 CMP dl_or
 BCS dlx9
 ADC #1                 \ (C = 0)
 CMP dl_ol
 BCS P%+4
 LDA dl_ol
 STA dl_a
 LDA dl_or
 STA dl_b
 JMP dl_black
.dlx9
 RTS

\ dl_fill: pixels dl_a .. dl_b of the row (within the new span) in the new
\ disc's colours: colour A, but colour B in the band dl_n0 .. dl_n1 - 1. In up
\ to three pieces.

.dl_fill
 LDA dl_b               \ nothing if b < a
 CMP dl_a
 BCC dlf_9
 LDA dl_n0              \ no band: all colour A
 CMP dl_n1
 BCS dlfa
 LDA dl_a               \ left of the band: a .. min(b, N0 - 1)
 CMP dl_n0
 BCS dlf_2
 LDA dl_b
 PHA
 LDX dl_n0
 DEX
 CPX dl_b
 BCS P%+4
 STX dl_b
 JSR dlfa
 PLA
 STA dl_b
 LDA dl_n0              \ (on from N0)
 CMP dl_b
 BEQ P%+4
 BCS dlf_9
 STA dl_a
.dlf_2
 LDA dl_a               \ in the band: a .. min(b, N1 - 1), colour B
 CMP dl_n1
 BCS dlfa
 LDA dl_b
 PHA
 LDX dl_n1
 DEX
 CPX dl_b
 BCS P%+4
 STX dl_b
 LDA dl_y
 LSR A
 LDA dl_be
 BCC P%+5
 LDA dl_bo
 JSR dl_paint
 PLA
 STA dl_b
 LDA dl_n1              \ on from N1, colour A
 CMP dl_b
 BEQ P%+4
 BCS dlf_9
 STA dl_a
.dlfa                   \ dl_a .. dl_b in colour A
 LDA dl_y
 LSR A
 LDA dl_ae
 BCC dl_paint
 LDA dl_ao
 BCS dl_paint
.dlf_9
 RTS

.dl_black
 LDA #0

\ dl_paint: pixels dl_a .. dl_b (dl_a <= dl_b) of row dl_y in the colour byte
\ A: up to DL_DIR bytes written here (the ends masked), longer queued for
\ bank R's row runs

DL_DIR = 32
DL_MINR = 40            \ (the smallest disc the layer keeps)
 ASSERT 2 * DL_MINR DIV 4 + 1 < DL_DIR   \ (a small disc's spans are all written
                                         \ here: the queue is for its marks)

.dl_paint
 STA dl_c
 LDA dl_a               \ one byte (the usual: an edge moved a little)?
 EOR dl_b
 CMP #4
 BCS dlpm
 LDA dl_a               \ the mask: pixels a AND 3 .. b AND 3
 AND #3
 TAX
 LDA dl_b
 AND #3
 TAY
 LDA dl_lm,X
 AND dl_rm,Y
 STA dl_u
 JSR dl_addr
 LDY #0
 LDA (dl_sp),Y
 EOR dl_c
 AND dl_u
 EOR (dl_sp),Y
 STA (dl_sp),Y
 RTS
.dlpm
 LDA dl_b               \ two bytes or more
 LSR A
 LSR A
 STA dl_t
 LDA dl_a
 LSR A
 LSR A
 EOR #&FF
 SEC
 ADC dl_t               \ bytes - 1
 CMP #DL_DIR
 BCC dlpd
 JMP dlq                \ long: queue
.dlpd
 TAX
 JSR dl_addr            \ dl_sp = the byte of (dl_a, dl_y)
 LDA dl_a               \ the first byte: pixels a AND 3 .. 3
 AND #3
 TAY
 LDA dl_lm,Y
 LDY #0
 JSR dl_wbyte
 STX dl_t               \ the whole bytes, 1 .. X - 1: through the unrolled
 DEX                    \ run dl_un, with an RTS planted at byte X's LDY (at
 BEQ dlp4               \ dl_un + 4 (X - 1))
 TXA
 ASL A
 ASL A
 TAX
 LDA #&60
 STA dl_un,X
 LDA dl_c
 JSR dl_un
 LDA #&A0
 STA dl_un,X
.dlp4
 LDA dl_t               \ the last byte, at 8 X: pixels 0 .. b AND 3
 ASL A
 ASL A
 ASL A
 TAY
 LDA dl_b
 AND #3
 TAX
 LDA dl_rm,X
 JMP dl_wbyte

.dl_un                  \ the unrolled run: byte k at (dl_sp) + 8 k, k = 1 to 31
FOR k, 1, 31
 LDY #8 * k
 STA (dl_sp),Y
NEXT
 RTS


\ dl_wbyte: the byte at (dl_sp),Y: the mask A's pixels in dl_c (keeps X, Y)

.dl_wbyte
 STA dl_u
 LDA (dl_sp),Y
 EOR dl_c
 AND dl_u
 EOR (dl_sp),Y
 STA (dl_sp),Y
 RTS

.dlq                    \ queue the span (row, left, right, colour)
 LDX dl_qn
 CPX #DL_QN * 4
 BCC dlq1
 JSR dl_drain
 LDX #0
.dlq1
 LDA dl_y
 STA DL_Q,X
 LDA dl_a
 STA DL_Q+1,X
 LDA dl_b
 STA DL_Q+2,X
 LDA dl_c
 STA DL_Q+3,X
 TXA
 CLC
 ADC #4
 STA dl_qn
 RTS

\ dl_drain: bank R draws the queue (T_DRAINQ: A spans at DL_Q)

.dl_drain
 LDA dl_qn
 BEQ dld9
 LSR A
 LSR A
 JSR T_DRAINQ
 LDA #0
 STA dl_qn
.dld9
 RTS

\ dl_addr: dl_sp = the address of the byte with pixel (dl_a, dl_y) in
\ buffer DL_BACK: base + (y DIV 8) * &200 + (y MOD 8) + 8 * (x DIV 4) (the
\ row's part from dl_row)

.dl_addr
 LDA dl_a
 AND #&FC
 ASL A                  \ (C: x >= 128, the row's second page)
 ORA dl_rbl
 STA dl_sp
 LDA dl_rbh
 ADC #0
 STA dl_sp+1
 RTS

\ ------------------------------------------------------------------------------
\ The disc's geometry
\ ------------------------------------------------------------------------------

\ dl_hw: dl_hwt[d] = floor(sqrt(r * r - d * d)) for d = 0 to r (r = dl_r),
\ unless the table is for this radius already (the frame layer's f_hwbuild)

.dl_hw
 LDA dl_r
 CMP dl_hwr
 BNE dlh0
 RTS
.dlh0
 STA dl_hwr
 LDX dl_r               \ x = r
 LDA #0
 STA dl_e               \ e = 0 (d = 0, x = r)
 STA dl_e+1
 LDY #0                 \ d
.dlh1
 TXA
 STA dl_hwt,Y
 CPY dl_r
 BEQ dlh9
 TYA                    \ e -= 2d + 1 ; d++
 ASL A
 STA dl_t
 LDA #0
 ROL A
 STA dl_u
 LDA dl_e
 CLC                    \ (C = 0: SBC takes the + 1 too)
 SBC dl_t
 STA dl_e
 LDA dl_e+1
 SBC dl_u
 STA dl_e+1
 INY
.dlh2
 LDA dl_e+1             \ while e < 0: e += 2x - 1 ; x--
 BPL dlh1
 TXA
 ASL A
 STA dl_t
 LDA #0
 ROL A
 STA dl_u
 LDA dl_t
 SEC
 SBC #1
 STA dl_t
 BCS P%+4
 DEC dl_u
 LDA dl_e
 CLC
 ADC dl_t
 STA dl_e
 LDA dl_e+1
 ADC dl_u
 STA dl_e+1
 DEX
 JMP dlh2
.dlh9
 RTS

\ dl_rows: dl_nt = the disc's top row, cy - r, dl_nb its bottom, cy + r,
\ clipped to the window's rows 1 to 191 (none: dl_nt > dl_nb)

.dl_rows
 LDA dl_cy
 SEC
 SBC dl_r
 STA dl_nt
 LDA dl_cy+1
 SBC #0
 BMI dlw1               \ above the screen: row 1
 BNE dlw8               \ below row 255: none
 LDA dl_nt
 BNE dlw2
.dlw1
 LDA #1
 STA dl_nt
.dlw2
 LDA dl_cy
 CLC
 ADC dl_r
 STA dl_nb
 LDA dl_cy+1
 ADC #0
 BMI dlw8               \ above the screen: none
 BNE dlw3               \ below row 255: row 191
 LDA dl_nb
 CMP #192
 BCC dlw4
.dlw3
 LDA #191
 STA dl_nb
.dlw4
 LDA dl_nb
 CMP dl_nt
 BCS dlw9
.dlw8
 LDA #&FF
 STA dl_nt
 LDA #0
 STA dl_nb
.dlw9
 RTS

\ dl_span: row Y (in dl_nt..dl_nb): the disc's span on it, clipped to the
\ window's columns 2 to 253, in dl_nl..dl_nr (none: left > right), and the
\ crater's band on it (dl_n0..dl_n1 - 1, within the span). Keeps Y.

.dl_span
 TYA                    \ X = |row - cy| (<= r)
 SEC
 SBC dl_cy
 STA dl_t
 LDA #0
 SBC dl_cy+1
 BPL dls1
 LDA dl_t
 EOR #&FF
 CLC
 ADC #1
 STA dl_t
.dls1
 LDX dl_t
 LDA dl_hwt,X
 BIT dl_inx             \ the disc inside columns 2..253: no clipping
 BPL dls1c
 TAX
 CLC
 ADC dl_cx
 STA dl_nr
 TXA
 EOR #&FF
 SEC
 ADC dl_cx
 STA dl_nl
 JMP dls5
.dls1c
 STA dl_u
 CLC                    \ right = cx + n, clipped
 LDA dl_cx
 ADC dl_u
 STA dl_nr
 LDA dl_cx+1
 ADC #0
 BMI dls8               \ left of the screen: none
 BNE dls2               \ right of it: column 253
 LDA dl_nr
 CMP #2
 BCC dls8
 CMP #254
 BCC dls3
.dls2
 LDA #253
 STA dl_nr
.dls3
 SEC                    \ left = cx - n, clipped
 LDA dl_cx
 SBC dl_u
 STA dl_nl
 LDA dl_cx+1
 SBC #0
 BMI dls4               \ left of the screen: column 2
 BNE dls8               \ right of it: none
 LDA dl_nl
 CMP #254
 BCS dls8
 CMP #2
 BCS dls5
.dls4
 LDA #2
 STA dl_nl
.dls5
 LDA dl_band            \ the crater's band on this row, within the span
 BEQ dls9
 LDA dl_crl,Y
 CMP dl_crr,Y
 BCS dls9               \ (none)
 CMP dl_nl
 BCS P%+4
 LDA dl_nl
 STA dl_n0
 LDX dl_nr              \ (nr + 1 <= 254)
 INX
 STX dl_t
 LDA dl_crr,Y
 CMP dl_t
 BCC P%+4
 LDA dl_t
 STA dl_n1
 LDA dl_n0
 CMP dl_n1
 BCC dls9
 LDA #0                 \ (empty after clipping)
 STA dl_n0
 STA dl_n1
.dls9
 RTS
.dls8
 LDA #255
 STA dl_nl
 LDA #0
 STA dl_nr
 RTS

\ dl_crater: the crater's points (the closed ellipse PLS22 made) into its
\ rows' extents dl_crl[y] .. dl_crr[y] - 1 (none: crl >= crr): each edge
\ stepped row by row, its x at each row (from its top end plus a half,
\ rounded down, clamped to 0..255) widening the row's extent. The crater is
\ convex, so its extent on a row is its span there.

.dl_crater
 LDY #191               \ no extents yet
.dlc0
 LDA #255
 STA dl_crl,Y
 LDA #0
 STA dl_crr,Y
 DEY
 BNE dlc0
 LDA dl_np              \ at least three points
 SEC
 SBC dl_cvs
 CMP #3
 BCC dlc9
 LDX dl_cvs
 STX dl_i
.dlc1
 LDX dl_i               \ the edge from point i to point i + 1 (the last to
 LDA dl_ptxl,X          \ the first)
 STA dl_ax
 LDA dl_ptxh,X
 STA dl_ax+1
 LDA dl_ptyl,X
 STA dl_ay
 LDA dl_ptyh,X
 STA dl_ay+1
 INX
 CPX dl_np
 BCC P%+5
 LDX dl_cvs
 LDA dl_ptxl,X
 STA dl_bx
 LDA dl_ptxh,X
 STA dl_bx+1
 LDA dl_ptyl,X
 STA dl_by
 LDA dl_ptyh,X
 STA dl_by+1
 JSR dl_seg
 INC dl_i
 LDA dl_i
 CMP dl_np
 BCC dlc1
 LDA #&FF
 STA dl_band
.dlc9
 RTS

\ dl_seg: the edge (dl_ax, dl_ay) - (dl_bx, dl_by) (signed 16-bit): if its dx
\ or dy is outside -255..255, its halves (recursively), else dl_edge

.dl_seg
 LDA dl_bx
 SEC
 SBC dl_ax
 TAX
 LDA dl_bx+1
 SBC dl_ax+1
 BEQ dls_1
 CMP #&FF
 BNE dls_s
 TXA
 BEQ dls_s              \ (dx = -256)
.dls_1
 LDA dl_by
 SEC
 SBC dl_ay
 TAX
 LDA dl_by+1
 SBC dl_ay+1
 BEQ dls_2
 CMP #&FF
 BNE dls_s
 TXA
 BNE dls_2
.dls_s                  \ split at the midpoint: keep b
 LDA dl_bx+1
 PHA
 LDA dl_bx
 PHA
 LDA dl_by+1
 PHA
 LDA dl_by
 PHA
 LDX #0                 \ b = (a + b) / 2, x then y (17-bit sums: the true
 JSR dl_mid             \ sign is N EOR V)
 LDX #2
 JSR dl_mid
 LDA dl_bx+1            \ keep the midpoint
 PHA
 LDA dl_bx
 PHA
 LDA dl_by+1
 PHA
 LDA dl_by
 PHA
 JSR dl_seg             \ a to the midpoint
 PLA                    \ then the midpoint to b
 STA dl_ay
 PLA
 STA dl_ay+1
 PLA
 STA dl_ax
 PLA
 STA dl_ax+1
 PLA
 STA dl_by
 PLA
 STA dl_by+1
 PLA
 STA dl_bx
 PLA
 STA dl_bx+1
 JMP dl_seg
.dls_2
 JMP dl_edge

.dl_mid                 \ dl_b(x or y, X = 0 or 2) = (dl_a + dl_b) / 2
 LDA dl_ax,X
 CLC
 ADC dl_bx,X
 STA dl_bx,X
 LDA dl_ax+1,X
 ADC dl_bx+1,X
 STA dl_bx+1,X
 BVC P%+4
 EOR #&80
 ASL A
 ROR dl_bx+1,X
 ROR dl_bx,X
 RTS

\ dl_edge: the edge a - b (dx and dy within -255..255): for each row y from
\ its top end to its bottom end that is on the screen (0..191), x = x0 + 0.5
\ + (y - y0) |dx| / dy (8.8 steps, added or taken away), widening dl_crl[y]
\ .. dl_crr[y]

.dle_x
 RTS

.dl_edge
 LDA dl_by              \ from the top end down: swap the ends if b is above
 CMP dl_ay
 LDA dl_by+1
 SBC dl_ay+1
 BVC P%+4
 EOR #&80
 BPL dle1
 LDX #3
.dle0
 LDA dl_ax,X
 LDY dl_bx,X
 STA dl_bx,X
 TYA
 STA dl_ax,X
 DEX
 BPL dle0
.dle1
 LDA dl_by+1            \ all above the screen, or all below it: nothing
 BMI dle_x
 LDA dl_ay+1
 BMI dle2
 BNE dle_x
 LDA dl_ay
 CMP #192
 BCS dle_x
.dle2
 LDA dl_by              \ dy
 SEC
 SBC dl_ay
 TAX
 LDA #0                 \ |dx| and its sign
 STA dl_neg
 LDA dl_bx
 SEC
 SBC dl_ax
 TAY
 LDA dl_bx+1            \ (the high byte: 0 or &FF, as dx is within -255..255)
 SBC dl_ax+1
 BPL dle3a
 TYA
 EOR #&FF
 CLC
 ADC #1
 DEC dl_neg
 JMP dle3
.dle3a
 TYA
.dle3
 LDY #0                 \ the step: |dx| * 256 / dy (0 for a flat edge)
 STY dl_stp
 STY dl_stp+1
 CPX #0
 BEQ dle4
 JSR dl_div
.dle4
 LDA #&80               \ x = x0 + 0.5 (16.8), y = y0
 STA dl_xf
 LDA dl_ax
 STA dl_xi
 LDA dl_ax+1
 STA dl_xh
 LDA dl_ay
 STA dl_yl
 LDA dl_ay+1
 STA dl_yh
.dle5
 LDA dl_yh              \ row y on the screen: widen its extent
 BNE dle7
 LDY dl_yl
 CPY #192
 BCS dle9               \ (below the screen: done)
 LDA dl_xh              \ x clamped to 0..255
 BMI dle6a
 BEQ dle6b
 LDA #255
 BNE dle6c
.dle6a
 LDA #0
 BEQ dle6c
.dle6b
 LDA dl_xi
.dle6c
 CMP dl_crl,Y           \ crl = min(crl, x)
 BCS P%+5
 STA dl_crl,Y
 CMP #255               \ crr = max(crr, x + 1), at most 255
 BCS P%+4
 ADC #1
 CMP dl_crr,Y
 BCC dle7
 STA dl_crr,Y
.dle7
 LDA dl_yl              \ the bottom end: done
 CMP dl_by
 BNE dle8
 LDA dl_yh
 CMP dl_by+1
 BEQ dle9
.dle8
 INC dl_yl              \ y + 1, x +/- the step
 BNE P%+5
 INC dl_yh
 BIT dl_neg
 BMI dle8n
 LDA dl_xf
 CLC
 ADC dl_stp
 STA dl_xf
 LDA dl_xi
 ADC dl_stp+1
 STA dl_xi
 BCC dle5
 INC dl_xh
 JMP dle5
.dle8n
 LDA dl_xf
 SEC
 SBC dl_stp
 STA dl_xf
 LDA dl_xi
 SBC dl_stp+1
 STA dl_xi
 BCS dle8j
 DEC dl_xh
.dle8j
 JMP dle5
.dle9
 RTS

\ dl_div: dl_stp(1 0) = A * 256 / X (X >= 1), by restoring division

.dl_div
 STX dl_t
 STA dl_stp+1           \ the dividend: A * 256
 LDA #0
 STA dl_stp
 LDX #16
.dlv1
 ASL dl_stp
 ROL dl_stp+1
 ROL A
 BCS dlv2
 CMP dl_t
 BCC dlv3
.dlv2
 SBC dl_t
 INC dl_stp
.dlv3
 DEX
 BNE dlv1
 RTS

\ ------------------------------------------------------------------------------
\ Tables and state
\ ------------------------------------------------------------------------------

.dl_lm EQUB &FF, &77, &33, &11    \ pixels x AND 3..3 of a byte
.dl_rm EQUB &88, &CC, &EE, &FF    \ pixels 0..x AND 3
.dl_base EQUB HI(BUF0), HI(SCREEN%)
.dl_cae EQUB &FF, &05   \ colour A's even and odd rows' bytes: the sun's, the
.dl_cao EQUB &FA, &5A   \ planet's (the frame layer's FC_SUNE.. FC_PLANO)
.dl_be EQUB &50         \ colour B, a crater: dark (the Master port's)
.dl_bo EQUB &A0
.dl_hl EQUB HI(dl_l0), HI(dl_l1)
.dl_hr EQUB HI(dl_r0), HI(dl_r1)
.dl_h0 EQUB HI(dl_a0), HI(dl_a1)
.dl_h1 EQUB HI(dl_b0), HI(dl_b1)

DL_NPT = 48             \ crater points a frame

.dl_pon EQUB 0          \ the planet's record: on, centre x, y, radius, TYPE
.dl_px EQUW 0
.dl_py EQUW 0
.dl_pr EQUB 0
.dl_pt EQUB 0
.dl_son EQUB 0          \ the sun's (7 on)
.dl_sux EQUW 0
.dl_suy EQUW 0
.dl_sr EQUB 0
.dl_st EQUB 0
.dl_np EQUB 0           \ the crater's points: count, first, on
.dl_cvs EQUB 0
.dl_con EQUB 0
.dl_ptxl SKIP DL_NPT
.dl_ptxh SKIP DL_NPT
.dl_ptyl SKIP DL_NPT
.dl_ptyh SKIP DL_NPT

.dl_lay EQUB 0          \ this frame's disc: 0 none, 1 the sun, 2 the planet
.dl_kind EQUB 0, 0      \ the disc each buffer holds (0 none known)
.dl_ot EQUB &FF, &FF    \ each buffer's disc rows (none: top > bottom)
.dl_ob EQUB 0, 0
.dl_oot EQUB 0          \ (this buffer's)
.dl_oob EQUB 0
.dl_same EQUB 0         \ &FF: the buffer's old rows are this disc's
.dl_cx EQUW 0           \ the disc: centre, radius, colour A's bytes
.dl_cy EQUW 0
.dl_r EQUB 0
.dl_ae EQUB 0
.dl_ao EQUB 0
.dl_hwr EQUB 0          \ the radius dl_hwt is for (0 at first: all 0)
.dl_e EQUW 0
.dl_nt EQUB 0           \ its rows
.dl_nb EQUB 0
.dl_band EQUB 0         \ non-zero: a crater's band
.dl_lo EQUB 0           \ the rows to visit
.dl_hi EQUB 0
.dl_n EQUB 0
.dl_wi EQUB 0
.dl_n0 EQUB 0
.dl_n1 EQUB 0
.dl_o0 EQUB 0
.dl_o1 EQUB 0
.dl_qn EQUB 0           \ the queue's length (x 4)
.dl_i EQUB 0            \ the crater: the edge, its ends, its step, x, y
.dl_ax EQUW 0           \ (a: x, y; b: x, y, at +2 from each)
.dl_ay EQUW 0
.dl_bx EQUW 0
.dl_by EQUW 0
.dl_neg EQUB 0
.dl_stp EQUW 0
.dl_xf EQUB 0
.dl_xi EQUB 0
.dl_xh EQUB 0
.dl_yl EQUB 0
.dl_yh EQUB 0
.dl_on EQUB 0           \ the discs recorded this frame (DL_FRAME's X)
.dl_bit EQUB 1, 2       \ GDL's bits
.dl_obd EQUB 0          \ &FF: the last frame on this buffer had a band
.dl_bmode EQUB 0        \ &FF: a small disc, drawn whole (dl_small): its
.dl_blay EQUB 0         \ kind, band and rows
.dl_bband EQUB 0
.dl_bnt EQUB 0
.dl_bnb EQUB 0
.dl_stat EQUB 0         \ &FF: the disc as it was on this buffer
.dl_scx EQUW 0, 0       \ each buffer's disc: centre x (lo, lo, hi, hi), y,
.dl_scy EQUW 0, 0       \ radius, band
.dl_srr EQUB 0, 0
.dl_sbd EQUB 0, 0
.dl_inx EQUB 0          \ &FF: the disc is inside the window's columns
.dl_bb EQUB 0           \ the buffer's base (high byte)
.DL_BACK EQUB 0         \ the buffer DL_FRAME draws (0 or 1)

 ALIGN &100             \ the page-aligned tables
.dl_hwt SKIP 256        \ the half-widths
.dl_crl SKIP 192        \ the crater's extents by row
 ALIGN &100
.dl_crr SKIP 192
 ALIGN &100
.dl_l0 SKIP 192         \ buffer 0's rows: span left, right, band start, end
 ALIGN &100
.dl_r0 SKIP 192
 ALIGN &100
.dl_a0 SKIP 192
 ALIGN &100
.dl_b0 SKIP 192
 ALIGN &100
.dl_l1 SKIP 192         \ buffer 1's
 ALIGN &100
.dl_r1 SKIP 192
 ALIGN &100
.dl_a1 SKIP 192
 ALIGN &100
.dl_b1 SKIP 192
