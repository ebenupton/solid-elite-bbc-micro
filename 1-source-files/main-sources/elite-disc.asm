\ ******************************************************************************
\
\ BBC MICRO DISC ELITE DISC IMAGE SCRIPT
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
\ This source file produces an SSD disc image for BBC Micro disc Elite.
\
\ ------------------------------------------------------------------------------
\
\ This source file produces one of the following SSD disc images, depending on
\ which release is being built:
\
\   * elite-disc-sth.ssd
\   * elite-disc-ib-disc.ssd
\   * elite-disc-sideways-ram.ssd
\
\ This can be loaded into an emulator or a real BBC Micro.
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-build-options.asm"

 _IB_DISC               = (_VARIANT = 1)
 _STH_DISC              = (_VARIANT = 2)
 _SRAM_DISC             = (_VARIANT = 3)

 \ Port: the loader (the original's third loader, ELITE4, which the disc's
 \ !Boot runs: the copy protection's first two loaders are gone), the two
 \ programs' images (each program's home and cold banks, which the loader's
 \ PCLI loads into sideways RAM, docs/memory-map.md), and the ship blueprint
 \ files (which PCLI loads into the flight code's home bank)

 PUTFILE "3-assembled-output/ELITE4.bin", "ELITE4", &FF1900, &FF197B

 PUTFILE "3-assembled-output/D.CODEH.bin", "D.CODEH", &008000, &008000
 PUTFILE "3-assembled-output/D.CODEC.bin", "D.CODEC", &008000, &008000
 PUTFILE "3-assembled-output/T.CODEH.bin", "T.CODEH", &008000, &008000
 PUTFILE "3-assembled-output/T.CODEC.bin", "T.CODEC", &008000, &008000

 PUTFILE "3-assembled-output/D.MOA.bin", "D.MOA", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOB.bin", "D.MOB", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOC.bin", "D.MOC", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOD.bin", "D.MOD", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOE.bin", "D.MOE", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOF.bin", "D.MOF", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOG.bin", "D.MOG", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOH.bin", "D.MOH", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOI.bin", "D.MOI", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOJ.bin", "D.MOJ", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOK.bin", "D.MOK", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOL.bin", "D.MOL", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOM.bin", "D.MOM", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MON.bin", "D.MON", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOO.bin", "D.MOO", &00B600, &00B600
 PUTFILE "3-assembled-output/D.MOP.bin", "D.MOP", &00B600, &00B600

 PUTFILE "3-assembled-output/README.txt", "README", &FFFFFF, &FFFFFF
