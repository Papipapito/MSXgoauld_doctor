#!/usr/bin/env python3
"""make_screens.py - the docs/img/*.png screens (exact transcriptions of the
Goa'uld Doctor screens, see README).  Needs an MSX BIOS ROM for the font:
    python make_screens.py path/to/msx_bios.rom
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from render_screen import load_font, render

OUT = os.path.join(os.path.dirname(__file__), "..", "img")

def v(text, verdict):            # verdict column 36 (1-based)
    return text.ljust(35) + verdict

FOOTER = "SPC V X=ram3 W=mart B=bios K=tec M=bus"

hb10_ok = [
    "GOAULD DOCTOR v1.0  monitor v2",
    v("RELOJ  3579.5k placa RST H/0 WT H", "OK"),
    "BIOS   F3C3 id:00 00 00 CRC EE229390",
    v("       HB-10+", "OK"),
    "MAPA    pag0 pag1 pag2 pag3",
    " S0   ROM  ROM  ---  RAM",
    " S1   ---  ---  ---  ---",
    " S2   ---  ---  ---  ---",
    " S3   ---  ---  ---  ---",
    v("RAM  S0 p3 16383 b", "OK"),
    v("MAPPER ninguno (sin RAM en pag2)", "n/d"),
    v("VDP    TMS  S0=D1 F:59/s /INT:60Hz", "OK"),
    v("VRAM   16K sin fallos", "OK"),
    v("SPRITE colis:OK   5o=4", "OK"),
    v("PPI    A8 F0=F0 AA 7A=7A A9=FF", "OK"),
    v("PSG    R0-R13 releen bien", "OK"),
    v("RTC    no hay (placa MSX1)", "n/d"),
    "", "", "", "", "", "",
    FOOTER,
]

hb10_ram = [
    "GOAULD DOCTOR v1.0  monitor v2",
    v("RELOJ  3579.5k placa RST H/0 WT H", "OK"),
    "BIOS   F3C3 id:00 00 00 CRC EE229390",
    v("       HB-10+", "OK"),
    "MAPA    pag0 pag1 pag2 pag3",
    " S0   ROM  ROM  ---  ROM",
    " S1   ---  ---  ---  ---",
    " S2   ---  ---  ---  ---",
    " S3   ---  ---  ---  ---",
    v("RAM    ninguna encontrada", "MAL"),
    v("MAPPER ninguno (sin RAM en pag2)", "n/d"),
    v("VDP    TMS  S0=D1 F:59/s /INT:60Hz", "OK"),
    v("VRAM   16K sin fallos", "OK"),
    v("SPRITE colis:OK   5o=4", "OK"),
    v("PPI    A8 F0=F0 AA 3A=3A A9=6B", "OK"),
    v("PSG    R0-R13 releen bien", "OK"),
    v("RTC    no hay (placa MSX1)", "n/d"),
    "",
    "> pag3 lee y no escribe: VCC/GND RAM, /W",
    "", "", "", "",
    FOOTER,
]

nms8250 = [
    "GOAULD DOCTOR v1.0  SIN MONITOR (emul.)",
    "RELOJ/RESET/WAIT: n/d sin monitor",
    "BIOS   F3C3 id:91 11 01 CRC 6CDAF3A5",
    v("       NMS8220+", "OK"),
    "MAPA    pag0 pag1 pag2 pag3",
    " S0   ROM  ROM  ---  ---",
    " S1   ROM  ROM  ROM  ROM",
    " S2   ---  ---  ---  ---",
    " S3-0 ROM  ROM  ROM  ROM",
    " S3-2 RAM  RAM  RAM  own",
    " S3-3 ---  ROM  ---  ---",
    v("RAM  S3-2 p0-p2 48 KB", "OK"),
    v("MAPPER S3-2 8 seg 128K regs ok", "OK"),
    v("VDP    9938 S0=1F F:51/s /INT:n/d", "OK"),
    v("VRAM   128K sin fallos", "OK"),
    v("CMD    HMMV+HMMM verificados", "OK"),
    v("SPRITE colis:OK   5o=4", "OK"),
    v("PPI    A8 F4=F4 AA 1A=1A A9=FF", "OK"),
    v("PSG    R0-R13 releen bien", "OK"),
    v("RTC    RP5C01 seg 32>34 RAM26 ok", "OK"),
    "", "", "",
    FOOTER,
]

boot = [
    "GOAULD DOCTOR probando: BIOS MAPA RAM MA",
    "PPER VDP",
]

kbd = ["MATRIZ TECLADO DE LA PLACA (sin USB)", "", "     b7 b6 b5 b4 b3 b2 b1 b0"]
for r in range(11):
    cells = ["."] * 8
    if r == 8:
        cells[7] = "X"           # SPC = row 8 bit 0 (bit 0 is the rightmost column)
    kbd.append(("R%d" % r).ljust(5) + " ".join(cells))
kbd += ["", "X = tecla pulsada. LED CAPS parpadea.", "ESC para volver."]

raw = [
    "RAM PAG3 EN CRUDO (C000 / E000) S0",
    "",
    "C000:",
    "leo 1   C3 C3 C3 C3 C3 C3 C3 C3",
    "        C3 C3 C3 C3 C3 C3 C3 C3",
    "leo 2   C3 C3 C3 C3 C3 C3 C3 C3",
    "        C3 C3 C3 C3 C3 C3 C3 C3",
    "00..FF  00 11 22 33 44 55 66 77",
    "        88 99 AA BB CC DD EE FF",
    "E000:",
    "leo 1   C3 C3 C3 C3 C3 C3 C3 C3",
    "        C3 C3 C3 C3 C3 C3 C3 C3",
    "leo 2   C3 C3 C3 C3 C3 C3 C3 C3",
    "        C3 C3 C3 C3 C3 C3 C3 C3",
    "00..FF  00 11 22 33 44 55 66 77",
    "        88 99 AA BB CC DD EE FF",
    "", "", "", "", "", "",
    "leo1!=leo2: bus flota. 00..FF: escritura",
    "Pulsa una tecla para volver.",
]

monitor = [
    "GOAULD DIAG  SIG:42 VER:02",
    "",
    "--- DATA BUS D7..D0 ---",
    "D7  D6  D5  D4  D3  D2  D1  D0",
    " OK  OK  OK  OK  OK  OK  OK  OK",
    "D_LAST=D8",
    "",
    "--- ADDR BUS A15..A0 ---",
    "NeverHI:OK",
    "NeverLO:OK",
    "",
    "--- INT/WAIT/CTRL ---",
    "/INT=0Hz ALERT",
    "/WAIT=255 max=17tk",
    "CTRL:RF=H M1=H WT=H IN=H RS=H MR=H IO=L",
    "RD=L",
    "--- ACTIVITY ---",
    "IORQ=15857 MREQ=61127",
    "IO:2D=FF A:2D2D",
    "",
    "SLOT:S0:?41",
    "--- RAM INTERNA GOAULD C100+ ---",
    "RAM OK",
    "SPACE=re-arm  ESC=volver al Doctor",
]

bios = [
    "== BIOS DE LA PLACA (slot 0, 32K) ==",
    "BIOS   F3C3 id:00 00 00 CRC EE229390",
    v("       HB-10+", "OK"),
    "", "",
    "00:F3C3D702BF1B9898C3832600C3B60100",
    "10:C3862600C3D10100C3451B00C3170200",
    "20:C36A1400C35E0200C389260000000000",
    "30:C305020000000000C33C0CC39D04C39D",
    "", "", "", "", "", "", "", "", "", "", "",
    "0000 debe ser F3 C3 (DI;JP). 002B-2D = i",
    "d.",
    "",
    "Pulsa una tecla para volver.",
]

hammer = [
    "MARTILLO DE ESCRITURAS EN PAG3, slot S0",
    "",
    "Escribiendo C000-FFFE sin parar.",
    "Cada byte = un pulso de /WR del Z80.",
    "",
    "OSCILOSCOPIO en /W del 4416 (pin 4):",
    " tren de pulsos 5V->0V, ~0.3us cada",
    " ~1.5us. Masa en pin 18 (VSS).",
    "",
    "MULTIMETRO (DC) en pin 4: unos 4V.",
    " 5.0V fijo = /W no llega. 0V = pegado.",
    "",
    "Compara con el pin 4 del otro 4416.",
    "", "", "", "", "", "", "", "", "", "",
    "Pulsa una tecla para volver.",
]

SCREENS = {
    "pantalla_w_martillo.png": hammer,
    "resumen_hb10_ok.png": hb10_ok,
    "resumen_hb10_ram.png": hb10_ram,
    "resumen_nms8250.png": nms8250,
    "arranque_probando.png": boot,
    "pantalla_k_teclado.png": kbd,
    "pantalla_x_pag3.png": raw,
    "pantalla_m_monitor.png": monitor,
    "pantalla_b_bios.png": bios,
}

if __name__ == "__main__":
    font = load_font(sys.argv[1])
    os.makedirs(OUT, exist_ok=True)
    for name, lines in SCREENS.items():
        render(font, lines, os.path.join(OUT, name))
    print(len(SCREENS), "screens in", os.path.normpath(OUT))
