BEEBASM?=beebasm
PYTHON?=python

# A make command with no arguments will build the Model B port (the
# Stairway to Hell variant, which the port starts from) with the standard
# commander, and report whether the game binaries still match the originals
# (crc32)
#
# The port (docs/README.md) is built without the copy protection's checksums,
# which are tied to the original's code and addresses (as with "encrypt=no"
# in the original's Makefile: the loader's and the docked code's checksum
# tests are disabled, and the docked code's checksum byte is not set). It is
# the Stairway to Hell variant only (the variants differ only in their
# loaders and copy protection)
#
# Optional arguments for the make command are:
#
#   commander=max       Start with a maxed-out commander
#
#   match=no            Do not attempt to match the original game binaries
#                       (i.e. omit workspace noise)
#
#   fix-interlace=yes   By default the game forces interlace to be on; this
#                       uses the interlace setting from when the game is run
#
#   verify=no           Do not compare the game binaries with the originals
#
# So, for example:
#
#   make commander=max match=no verify=no
#
# will build the port with a maxed-out commander, no workspace noise and no
# crc32 comparison
#
# The following variables are written into elite-build-options.asm depending on
# the above arguments, so they can be passed to BeebAsm:
#
# _VERSION
#   2 = BBC Micro disc
#
# _VARIANT
#   2 = Stairway to Hell
#
# _MAX_COMMANDER
#   TRUE  = Maxed-out commander
#   FALSE = Standard commander
#
# _REMOVE_CHECKSUMS
#   TRUE  = Disable checksum routines (always, in the port)
#
# _MATCH_ORIGINAL_BINARIES
#   TRUE  = Match binaries to released version (i.e. fill workspaces with noise)
#   FALSE = Zero-fill workspaces

ifeq ($(commander), max)
  max-commander=TRUE
else
  max-commander=FALSE
endif

unencrypt=-u
remove-checksums=TRUE

ifeq ($(match), no)
  match-original-binaries=FALSE
else
  match-original-binaries=TRUE
endif

ifeq ($(fix-interlace), yes)
  interlace=-i
  interlace-fix=TRUE
else
  interlace=
  interlace-fix=FALSE
endif

variant-number=2
folder=sth

.PHONY:all
all:
	echo _VERSION=2 > 1-source-files/main-sources/elite-build-options.asm
	echo _VARIANT=$(variant-number) >> 1-source-files/main-sources/elite-build-options.asm
	echo _REMOVE_CHECKSUMS=$(remove-checksums) >> 1-source-files/main-sources/elite-build-options.asm
	echo _MATCH_ORIGINAL_BINARIES=$(match-original-binaries) >> 1-source-files/main-sources/elite-build-options.asm
	echo _MAX_COMMANDER=$(max-commander) >> 1-source-files/main-sources/elite-build-options.asm
	echo _INTERLACE_FIX=$(interlace-fix) >> 1-source-files/main-sources/elite-build-options.asm
	$(PYTHON) 2-build-files/streams.py > 3-assembled-output/compile.txt
	$(PYTHON) 2-build-files/panel.py >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-missile.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-loader3.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-loader3.asm -d | grep "^\[{" > 3-assembled-output/loader-symbols.txt
	$(PYTHON) 2-build-files/layout-info.py
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout-flight.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout-flight.asm -d | grep "^\[{" > 3-assembled-output/flight-symbols.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout-docked.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-layout-docked.asm -d | grep "^\[{" > 3-assembled-output/docked-symbols.txt
	$(PYTHON) 2-build-files/bankcheck.py
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-a.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-b.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-c.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-d.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-e.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-f.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-g.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-h.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-i.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-j.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-k.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-l.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-m.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-n.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-o.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-ships-p.asm -v >> 3-assembled-output/compile.txt
	$(BEEBASM) -i 1-source-files/main-sources/elite-readme.asm -v >> 3-assembled-output/compile.txt
	$(PYTHON) 2-build-files/elite-checksum.py
	$(BEEBASM) -i 1-source-files/main-sources/elite-disc.asm -do 5-compiled-game-discs/elite-modelb.ssd -boot ELITE4 -title "E L I T E"
ifneq ($(verify), no)
	@$(PYTHON) 2-build-files/crc32.py 4-reference-binaries/$(folder) 3-assembled-output || true
endif

.PHONY:verify
verify:
	BEEBASM=$(BEEBASM) PYTHON=$(PYTHON) sh 6-harness/verify.sh

.PHONY:b2
b2:
	curl -G "http://localhost:48075/reset/b2"
	curl -H "Content-Type:application/binary" --upload-file "5-compiled-game-discs/elite-modelb.ssd" "http://localhost:48075/run/b2?name=elite-modelb.ssd"
