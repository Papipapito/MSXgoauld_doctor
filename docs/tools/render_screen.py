#!/usr/bin/env python3
"""render_screen.py - draw a 40x24 MSX SCREEN 0 text screen as a PNG, with the
real MSX BIOS font (CGTABL of any MSX BIOS ROM), white on blue, 3x pixels.
The screens in docs/img are exact transcriptions of what the Goa'uld's HDMI
shows; this keeps them crisp and reproducible.

Usage:  python render_screen.py bios.rom screen.txt out.png
"""
import sys
from PIL import Image

BLUE = (30, 30, 210)
WHITE = (255, 255, 255)
SCALE = 3
COLS, ROWS = 40, 24
MARGIN = 12          # text-mode pixels of border around the 240x192 area

def load_font(rom_path):
    rom = open(rom_path, "rb").read()
    cg = rom[4] | (rom[5] << 8)
    return rom[cg:cg + 256 * 8]

def render(font, lines, out):
    w = (COLS * 6 + 2 * MARGIN) * SCALE
    h = (ROWS * 8 + 2 * MARGIN) * SCALE
    img = Image.new("RGB", (w, h), BLUE)
    px = img.load()
    for r, line in enumerate(lines[:ROWS]):
        line = line.rstrip("\n")[:COLS]
        for c, ch in enumerate(line):
            code = ord(ch) if ord(ch) < 256 else ord("?")
            glyph = font[code * 8:code * 8 + 8]
            for y in range(8):
                bits = glyph[y]
                for x in range(6):
                    if bits & (0x80 >> x):
                        x0 = (MARGIN + c * 6 + x) * SCALE
                        y0 = (MARGIN + r * 8 + y) * SCALE
                        for dy in range(SCALE):
                            for dx in range(SCALE):
                                px[x0 + dx, y0 + dy] = WHITE
    img.save(out, optimize=True)

if __name__ == "__main__":
    font = load_font(sys.argv[1])
    lines = open(sys.argv[2], encoding="utf-8").read().split("\n")
    render(font, lines, sys.argv[3])
    print("wrote", sys.argv[3])
