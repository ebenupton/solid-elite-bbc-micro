#!/usr/bin/env python
#
# ******************************************************************************
#
# DISC ELITE CHECKSUM SCRIPT
#
# Written by Mark Moxon
#
# Port (docs/README.md): the port's binaries are neither encrypted nor
# scrambled, as the copy protection is gone (its loader copies its images as
# they are, and the programs' DEEOR has nothing to decrypt). This script now
# only sets the default commander's checksum in the loader, which the docked
# code's DFAULT checks when it copies the commander from NA%. It reads
#
#   * 3-assembled-output/ELITE4.unprot.bin (the loader)
#   * 3-assembled-output/loader-symbols.txt (its symbols, from beebasm -d)
#
# and writes 3-assembled-output/ELITE4.bin
#
# ******************************************************************************

from __future__ import print_function
import re

sy = {}
for m in re.finditer(r"'([^']+)':(\d+)", open("3-assembled-output/loader-symbols.txt").read()):
    sy.setdefault(m.group(1), int(m.group(2)))

load_address = 0x1900
tvt1_code = sy["TVT1code"]
tvt1 = sy["TVT1"]
na_per_cent = sy["NA%"]
chk2 = sy["CHK2"]

data_block = bytearray(open("3-assembled-output/ELITE4.unprot.bin", "rb").read())

# Commander data checksum (as the original script, at the port's addresses)

na_per_cent_offset = na_per_cent - tvt1 + tvt1_code - load_address
checksum_offset = chk2 - tvt1 + tvt1_code - load_address
CH = 0x4B - 2
CY = 0
for i in range(CH, 0, -1):
    CH = CH + CY + data_block[na_per_cent_offset + i + 7]
    CY = (CH > 255) & 1
    CH = CH % 256
    CH = CH ^ data_block[na_per_cent_offset + i + 8]

print("Commander checksum = ", hex(CH))

data_block[checksum_offset] = CH ^ 0xA9
data_block[checksum_offset + 1] = CH

open("3-assembled-output/ELITE4.bin", "wb").write(data_block)
print("3-assembled-output/ELITE4.bin file saved")
