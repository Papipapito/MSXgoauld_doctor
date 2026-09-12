# Goa'uld Doctor — MSX board diagnostic ROM

A 16 KB cartridge ROM embedded in the Goa'uld FPGA (slot 0-3, page 1) that
tests the **host MSX board** from the Z80 socket — a Fluke-9010A-style
in-circuit tester: the Goa'uld's own BIOS/VDP/HDMI show the results, so the
board's video, BIOS and RAM may all be dead and you still get a screen.

Validated first on the **Sony HB-10 (JP)** (TMS9118 + 2×4416 VRAM, 16 KB RAM
in slot 0 page 3), then extended to any MSX1/MSX2 board: every slot and
subslot is mapped, V9938/V9958 with 64/128 KB VRAM, memory mapper and RTC.

## The summary screen (automatic at boot, SPACE repeats)

| Row | What is tested | How |
|-----|----------------|-----|
| RELOJ | Z80 clock from the board (VDP CPUCLK) | `bus_monitor` counts edges: kHz, and whether the core fell back to its internal clock |
| RESET | external /RESET level + falling edges since power-up | a stuck-low /RESET no longer freezes the core (edge → 10 ms pulse) |
| /WAIT | external /WAIT level, stuck detection | a /WAIT held > 1.2 ms is auto-released and reported |
| BIOS | board ROM 0000-7FFF read through the bus | `F3 C3` header, id bytes 002B-2D, CRC32 vs. a table of 95 MSX1/MSX2 main ROMs (generated from openMSX dumps by `tools/gen_bios_table.py`), data lines that never moved |
| MAPA | primary slots 0-3, subslots 0-3 of expanded ones, pages 0-3 | RAM / ROM / --- probe per cell; the board's expansion registers follow the Goa'uld's writes to 0xFFFF |
| RAM | every cell found as RAM (max 4 rows, pages of a slot grouped: `p0-p2 48 KB`) | March C-, walking 1/0, address uniqueness, retention. Page 3 uses a **stackless** routine (that page holds our own stack) |
| MAPPER | every slot with RAM in page 2 | segment count through port FE (markers 255..0 then read back: `8 seg 128K`), fill+verify of segments 1..n-1 (n ≤ 64) with a segment/address pattern, then ports FC/FD/FF checked from pages 0/1/3 (page 3 stackless — the Goa'uld's own page 3 follows FF as well). `sin mapper (RAM plana)` on plain RAM |
| VDP | board VDP | type (TMS / V9938 / V9958 by the R#14 probe and S#1), F flag toggles, frames/s (exact via the monitor ms counter), /INT line rate with IE=1; R#9 = 50 Hz when the board BIOS is PAL |
| VRAM | 16 / 64 / 128 KB through ports 98/99, per 16 KB bank | address, 00/FF/AA/55, retention; first failure with bank and address, bad-bit mask → which nibble / which 64K half |
| CMD | V99x8 command engine | HMMV fills 256×16 in SCREEN 5, HMMM copies it, both read back by CPU; "motor colgado" if CE never drops |
| SPRITE | rendering path | collision flag with overlapping sprites, 5th-sprite flag + number (real rendering, no monitor needed) |
| PPI | board 8255 | port A latch read back through the bus, port C toggle/readback, port B |
| PSG | board AY-3-8910 | R0-R13 written with 55/AA and read back |
| RTC | board RP5C01 (ports B4/B5, read through the bus) | RAM banks 2 and 3 (26 nibbles, saved and restored) take 5/A, then the seconds must move within 1.2 s. `no hay (placa MSX1)` when the BIOS says MSX1 |

At the end the board's VDP is left showing a text + colour-bar + sprite
picture: connect the board's own video output to check the whole video chain
(`V` shows test patterns for it).

Keys: `B` BIOS hex dump, `K` live keyboard matrix of the board, `M` the
original bus monitor dashboard, `T` self-test of the stackless routine on
page 2, `X` raw dump of page 3 (what the bus returns), `V` video patterns on
the board's VDP.

Hints at the bottom: no clock, mute BIOS + dead VDP, stuck data lines (from
the BIOS read), VRAM nibble/half, "page 3 reads but does not write"
(starved 4416), RAM + VRAM both failing (DRAM supply).

## How it reaches the board (FPGA hooks, all under `DIAG_AUTOBOOT`)

`bus_monitor.v` v2 exposes a CONTROL register (index 0x20 via ports
0x2C/0x2D): `slot0_ext` makes the physical slot 0 transparent, `vdp_ext`
routes ports 98-9B to the board's VDP (the internal V9958 is deselected so
the HDMI screen survives), `ppi_ext`, `rtc_ext` (port B5 from the board's
RTC), `ign_int`, `ign_wait`; and CONTROL2 (0x21): a transparency mask per
primary slot (memory reads of that slot come from the bus, except the Doctor
ROM and the internal mapper's page 3) plus `p3_release` to hand that page 3
to the board too.  While slot 3 is transparent the internal mapper ignores
the cycle as well, so a page-2 fill with port FE = 0 cannot land in our own
page 3.  Status registers 0x15-0x1A give clock/reset/wait health and a ms
counter.  Without the monitor (e.g. openMSX) the control writes are no-ops
and the ROM still runs against whatever it sees — that is how it was
validated.

The build is `DIAG_SLIM`: only what the diagnostic needs stays in the FPGA
(T80, V9958+HDMI, SDRAM, flash loader, BIOS/subrom/mapper decode, internal
PPI/RTC, wait FSM, bus monitor, Doctor ROM).  Out: OPLL/SCC/megaram, SD
card/Nextor, settings ports and flash writer, WiFi UART, USB keyboard and
joystick link, kanji, version guard (no red border), debug UART.  Logic 44 %,
and the half-cycle T80 paths close timing with margin.

Keys are read by scanning the PPI matrix directly and reacting only to a key
that goes from released to pressed after 0.5 s of quiet: a stuck or
intermittent membrane cannot drive the Doctor, and is reported as a hint
(`> Teclado placa: pegada f/b 8/0` / `26 cambios/s, ignorado`).

## Build

```bash
cd diag
sjasmplus --lst=diag.lst --sym=diag.sym src/diag.asm      # -> DIAG.ROM
python tools/split_rom_hex.py                          # -> ../fpga/msx_debug/diag_rom_0..7.hex
cd ../fpga && gw_sh build_diag.tcl                        # -> impl/pnr/project.fs
```

The FPGA build needs the BIOS pack in flash at 0x200000 as usual (the diag
uses the Goa'uld's own BIOS for text output).

## Emulator check

```bash
openmsx -machine Sony_HB-10 -carta DIAG.ROM -script test.tcl
```

Expected on the emulated HB-10: BIOS `EE229390 HB-10 OK`, map
`S0 ROM ROM --- own`, `MAPPER ninguno`, VDP TMS 61/s, VRAM 16K, `RTC no hay
(placa MSX1)`.  On a Philips NMS 8250: `S3-2 RAM RAM RAM own`, `MAPPER S3-2
8 seg 128K regs ok`, VDP 9938 51/s (R#9 PAL), VRAM 128K, CMD OK, RTC OK.
Page-3 RAM shows "own" because in a real MSX that page holds the stack; a
machine reproducing the Goa'uld's slot layout (`Goauld_doctor_test`, Doctor
in 0-3, mapper in 3-0) exercises the same paths the hardware uses.
