#!/usr/bin/env python3
"""split_rom_hex.py - DIAG.ROM (16 KB) -> fpga/msx_debug/diag_rom_0.hex ..
diag_rom_7.hex, 2048 lines each (one byte per line), one file per BSRAM
primitive of diag_rom.v.  Run from anywhere:  python diag/tools/split_rom_hex.py
"""
import os, sys

here = os.path.dirname(os.path.abspath(__file__))
rom = os.path.join(here, "..", "DIAG.ROM")
out = os.path.join(here, "..", "..", "fpga", "msx_debug")
data = open(rom, "rb").read()
if len(data) != 16384:
    sys.exit("DIAG.ROM must be exactly 16384 bytes (%d)" % len(data))
for b in range(8):
    with open(os.path.join(out, "diag_rom_%d.hex" % b), "w", newline="\n") as f:
        f.writelines("%02x\n" % x for x in data[b * 2048:(b + 1) * 2048])
with open(os.path.join(out, "diag_rom.hex"), "w", newline="\n") as f:
    f.writelines("%02x\n" % x for x in data)
print("8 banks of 2048 lines written to", os.path.normpath(out))
