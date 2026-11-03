\ ******************************************************************************
\
\ gfx-window7.asm - the renderer's window in the flight code's bank 7 (WIN7%,
\ after the cold pass and the overlays: elite-layout-flight.asm)
\
\ Port (Model B): the disc layer's painter (gfx-raster_disc.asm, with the
\ strips, gfx-raster_strips.asm), the second disc (gfx-raster_disc2.asm) and
\ their operands' patch for a buffer (gfx-raster_dpatch.asm), then each
\ buffer's disc state, in the last twelve pages below DFSSAVE% (which are
\ not saved: DP_BEGIN's PB_RESET sets them up once a buffer is blanked, as
\ every program load leaves both), page aligned so that each buffer's
\ arrays are the other's but for their high bytes (buffer 1's are buffer
\ 0's + &300):
\
\   * the layer's spans, R_DISCL and R_DISCR, and the second disc's, R_S2L
\     and R_S2R (192 each per buffer: L = 255, R = 0 for none);
\
\   * the layer's boundaries, R_BDN (the count, 0 to 3, or &40 for more:
\     unknown, and in bit 7 the colour at the span's left end, as R_NDN),
\     R_BDX0, R_BDX1 and R_BDX2.
\
\ The most read, R_DISCL, R_DISCR, R_BDN and R_BDX0, start at low bytes &00
\ and &40, so that reading them ,X never crosses a page.
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/gfx-raster_disc.asm"
 INCLUDE "1-source-files/main-sources/gfx-raster_disc2.asm"
 INCLUDE "1-source-files/main-sources/gfx-raster_dpatch.asm"

DPST% = DFSSAVE% - &C00 \ the disc state, to DFSSAVE%
 ASSERT LO(DPST%) = 0

R_DISCL0 = DPST%        \ buffer 0's spans (three pages)
R_S2L0   = DPST% + &0C0
R_S2R0   = DPST% + &180
R_DISCR0 = DPST% + &240
R_DISCL1 = DPST% + &300 \ buffer 1's
R_S2L1   = DPST% + &3C0
R_S2R1   = DPST% + &480
R_DISCR1 = DPST% + &540
R_BDN0   = DPST% + &600 \ buffer 0's boundaries (three pages)
R_BDX10  = DPST% + &6C0
R_BDX20  = DPST% + &780
R_BDX00  = DPST% + &840
R_BDN1   = DPST% + &900 \ buffer 1's
R_BDX11  = DPST% + &9C0
R_BDX21  = DPST% + &A80
R_BDX01  = DPST% + &B40
 ASSERT R_BDX01 + 192 = DFSSAVE%
