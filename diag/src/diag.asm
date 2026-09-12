; =============================================================================
;  diag.asm  –  Goa'uld Doctor  –  MSX board diagnostic ROM (Z80-socket Goa'uld)
;  Assembler : sjasmplus (>=1.18); produces DIAG.ROM via SAVEBIN.
;  Output    : DIAG.ROM  –  16 384-byte MSX cartridge ROM at 0x4000.
;
;  ROM header at 0x4000: 'A','B', INIT word, standard MSX layout.
;  No DOS.  Main-ROM BIOS only.  IM1 interrupts kept running.
;
;  Bus monitor I/O ports (bus_monitor.v, free range on Goa'uld):
;    OUT (0x2C), idx  ->  select register index
;    IN  (0x2D)       ->  read regs[idx], idx auto-increments
;    OUT (0x2D), x    ->  clear / re-arm all accumulators
;
;  Register map 0x00-0x14: see bus_monitor.v header for full description.
;  Safe RAM 0xC000-0xF2FF; stack at 0xF200 growing down.
; =============================================================================

ROM_BASE        equ 0x4000
RAM_BASE        equ 0xC000
STACK_TOP       equ 0xF200
RAM_TEST_START  equ 0xC100  ; RAM pattern test region (well above variables)
RAM_TEST_LEN    equ 0x0080  ; 128 bytes

; BIOS entries
INITXT  equ 0x006C  ; SCREEN 0, 40-col, clear
RDSLT   equ 0x000C  ; safe slot read: A=descriptor, HL=address
CHPUT_E equ 0x00A2  ; output char in A

    DEVICE NOSLOT64K    ; sjasmplus: flat 64 KB image, no page mapping

; ===========================================================================
;  ROM at 0x4000
; ===========================================================================
    ORG ROM_BASE

; Cartridge header
    db  'A', 'B'
    dw  RomInit         ; INIT pointer (little-endian)
    dw  0, 0, 0         ; STATEMENT / DEVICE / TEXT
    ds  6, 0            ; reserved

; ---------------------------------------------------------------------------
;  RomInit – called by BIOS after slot detect; stack is valid on entry.
; ---------------------------------------------------------------------------
RomInit:
    di
    ld   sp, STACK_TOP
    ; clear the variable area (power-up RAM is random)
    ld   hl, RAM_BASE
    ld   de, RAM_BASE + 1
    ld   bc, 0x00FF
    ld   (hl), 0
    ldir
    ld   a, 40
    ld   (0xF3AE), a    ; LINL40: force 40 columns (an MSX2+ BIOS may default to 80)
    ei
    call INITXT         ; SCREEN 0, 40 col, clear
    call MonDetect      ; bus_monitor v2 present?
    call GetMySlot      ; slot id of this ROM (for the page-1 switches)
    call RelocInstall   ; RAM-resident routines -> 0xC800
    call SlotsInit      ; expansion registers: flags + images (before any select)
    call StuckKeysInit  ; keys already down = stuck: never an edge, reported
    call DoctorScreen   ; automatic board summary

; ---------------------------------------------------------------------------
;  Key loop after the summary
; ---------------------------------------------------------------------------
KeyLoop:
    call WaitKeyEdge
    cp   ' '
    jr   z, kDoctor
    cp   'D'
    jr   z, kDoctor
    cp   'B'
    jr   z, kBios
    cp   'K'
    jr   z, kKbd
    cp   'M'
    jr   z, kMon
    cp   'T'
    jr   z, kSelf
    cp   'V'
    jr   z, kVideo
    cp   'X'
    jr   z, kRaw
    jr   KeyLoop
kRaw:
    call RawP3Screen
    call DoctorScreen
    jr   KeyLoop
kVideo:
    call VideoScreen
    call DoctorScreen
    jr   KeyLoop
kSelf:
    call StacklessSelfTest
    call DoctorScreen
    jr   KeyLoop
kDoctor:
    call DoctorScreen
    jr   KeyLoop
kBios:
    call BiosScreen
    call DoctorScreen
    jr   KeyLoop
kKbd:
    call KbdScreen
    call DoctorScreen
    jr   KeyLoop
kMon:
    call MonitorScreen
    call DoctorScreen
    jr   KeyLoop

; ---------------------------------------------------------------------------
;  BiosScreen  -  hex dump of the first 64 bytes of the board BIOS + CRC
; ---------------------------------------------------------------------------
BiosScreen:
    call INITXT
    ld   b, 1
    ld   c, 1
    ld   hl, sBsTitle
    call PrintAt
    call BiosTest
    ld   a, 2
    ld   (row), a
    call BiosPrint
    ; dump 0000-003F, 16 bytes per row from row 6
    ld   hl, BIOS_HEAD
    ld   d, 6
    ld   e, 0                   ; offset
bsRow:
    push hl
    ld   b, d
    ld   c, 1
    call SetPos
    ld   a, e
    call PrintHexA
    ld   a, ':'
    call CHPUT
    pop  hl
    ld   b, 16
bsByte:
    ld   a, (hl)
    inc  hl
    push bc
    call PrintHexA
    pop  bc
    djnz bsByte
    ld   a, e
    add  a, 16
    ld   e, a
    inc  d
    ld   a, d
    cp   10
    jr   c, bsRow
    ld   b, 12
    ld   c, 1
    ld   hl, sBsNote
    call PrintAt
    ld   b, 24
    ld   c, 1
    ld   hl, sRSPressKey
    call PrintAt
    call WaitKeyEdge
    ret
sBsTitle: db "== BIOS DE LA PLACA (slot 0, 32K) ==", 0
sBsNote:  db "0000 debe ser F3 C3 (DI;JP). 002B-2D = id.", 0

; ---------------------------------------------------------------------------
;  MonitorScreen  -  the original live bus dashboard; ESC returns
; ---------------------------------------------------------------------------
MonitorScreen:
    call INITXT
MainLoop:
    call ReadMonRegs    ; fill mon_buf
    call PollKeyEdge    ; non-blocking, edges only
    cp   0x1B
    ret  z
    cp   ' '
    call z, RearmMonitor    ; SPACE = re-arm monitor window
    call DrawHeader         ; row  1
    call DrawDataBus        ; rows 3-6
    call DrawAddrBus        ; rows 8-10
    call DrawIntWait        ; rows 12-15
    call DrawActivity       ; rows 17-19
    call DrawSlotScan       ; row  21
    call DrawRamTest        ; rows 22-23
    call DrawFooter         ; row  24
    ; soft delay ~200 ms
    ld   bc, 0xA000
.delay:
    dec  bc
    ld   a, b
    or   c
    jr   nz, .delay
    jp   MainLoop

; ===========================================================================
;  Section 1 – Header: title and monitor signature
; ===========================================================================
DrawHeader:
    ld   b, 1
    ld   c, 1
    call SetPos
    ld   hl, sTitle
    call PrintStr
    ld   a, (mon_buf + 0)       ; SIGNATURE
    cp   0x42
    jr   nz, .noMon
    ld   hl, sSigOK
    call PrintStr
    ld   a, (mon_buf + 1)
    call PrintHexA
    ret
.noMon:
    ld   hl, sNoMon
    call PrintStr
    ret

sTitle:  db "GOAULD DIAG  SIG:", 0
sSigOK:  db "42 VER:", 0
sNoMon:  db "!! MONITOR NO PRESENTE !!      ", 0

; ===========================================================================
;  Section 2 – DATA BUS D7..D0
; ===========================================================================
DrawDataBus:
    ld   b, 3
    ld   c, 1
    call SetPos
    ld   hl, sDataHdr
    call PrintStr
    ld   b, 4
    ld   c, 1
    call SetPos
    ld   hl, sDataCols
    call PrintStr
    ld   b, 5
    ld   c, 1
    call SetPos
    ld   a, (mon_buf + 2)       ; D_DEAD_LO
    ld   (dbDeadLo), a
    ld   a, (mon_buf + 3)       ; D_DEAD_HI
    ld   (dbDeadHi), a
    ld   e, 7                   ; bit index 7..0
.loop:
    ld   a, e
    call BitMask8               ; A = 1<<e
    ld   c, a
    ld   a, (dbDeadLo)
    and  c
    ld   (dbS0), a
    ld   a, (dbDeadHi)
    and  c
    ld   (dbS1), a
    ld   a, (dbS0)
    or   a
    jr   nz, .stk0
    ld   a, (dbS1)
    or   a
    jr   nz, .stk1
    ld   hl, sOK
    call PrintStr
    jr   .next
.stk0:
    ld   hl, sStk0
    call PrintStr
    jr   .next
.stk1:
    ld   hl, sStk1
    call PrintStr
.next:
    ld   a, e
    or   a
    jr   z, .done
    dec  e
    ld   a, ' '
    call CHPUT_E
    jr   .loop
.done:
    ld   b, 6
    ld   c, 1
    call SetPos
    ld   hl, sDLast
    call PrintStr
    ld   a, (mon_buf + 4)
    call PrintHexA
    ld   hl, sPad8
    call PrintStr
    ret

sDataHdr:  db "--- DATA BUS D7..D0 ---         ", 0
sDataCols: db "D7  D6  D5  D4  D3  D2  D1  D0 ", 0
sOK:       db " OK ", 0
sStk0:     db "ST0 ", 0
sStk1:     db "ST1 ", 0
sDLast:    db "D_LAST=", 0
sPad8:     db "         ", 0

; ===========================================================================
;  Section 3 – ADDRESS BUS A15..A0
; ===========================================================================
DrawAddrBus:
    ld   b, 8
    ld   c, 1
    call SetPos
    ld   hl, sAddrHdr
    call PrintStr
    ; Never-went-HIGH (stuck-0) lines
    ld   b, 9
    ld   c, 1
    call SetPos
    ld   hl, sAdNvHi
    call PrintStr
    ld   a, (mon_buf + 5)
    ld   l, a
    ld   a, (mon_buf + 6)
    ld   h, a
    call PrintDeadA16
    ; Never-went-LOW (stuck-1) lines
    ld   b, 10
    ld   c, 1
    call SetPos
    ld   hl, sAdNvLo
    call PrintStr
    ld   a, (mon_buf + 7)
    ld   l, a
    ld   a, (mon_buf + 8)
    ld   h, a
    call PrintDeadA16
    ret

sAddrHdr: db "--- ADDR BUS A15..A0 ---        ", 0
sAdNvHi:  db "NeverHI:", 0
sAdNvLo:  db "NeverLO:", 0

; PrintDeadA16 – HL = 16-bit dead mask; print "OK" or list of dead line nums
PrintDeadA16:
    ld   a, h
    or   l
    jr   nz, .has
    ld   hl, sAOK
    call PrintStr
    ret
.has:
    ld   d, h               ; DE = mask (no 'ld de,hl' on Z80)
    ld   e, l
    ld   b, 0               ; bit index
.loop:
    ld   a, e
    and  1
    jr   z, .next
    ld   a, 'A'
    call CHPUT_E
    push bc
    push de
    ld   a, b
    call PrintDec8              ; clobbers B, C, D, E
    pop  de
    pop  bc
    ld   a, ' '
    call CHPUT_E
.next:
    srl  d
    rr   e
    inc  b
    ld   a, b
    cp   16
    jr   c, .loop
    ret
sAOK: db "OK              ", 0

; ===========================================================================
;  Section 4 – /INT rate, /WAIT, CTRL_LIVE
; ===========================================================================
DrawIntWait:
    ld   b, 12
    ld   c, 1
    call SetPos
    ld   hl, sIWHdr
    call PrintStr
    ; /INT rate
    ld   b, 13
    ld   c, 1
    call SetPos
    ld   hl, sIntRate
    call PrintStr
    ld   a, (mon_buf + 0x0E)
    call PrintDec8
    ld   hl, sHz
    call PrintStr
    ld   a, (mon_buf + 0x0E)
    cp   40
    jr   c, .alrt
    cp   71
    jr   nc, .alrt
    ld   hl, sIntOK
    call PrintStr
    jr   .idone
.alrt:
    ld   hl, sIntAlrt
    call PrintStr
.idone:
    ; /WAIT
    ld   b, 14
    ld   c, 1
    call SetPos
    ld   hl, sWait
    call PrintStr
    ld   a, (mon_buf + 0x0F)
    call PrintDec8
    ld   hl, sWMax
    call PrintStr
    ld   a, (mon_buf + 0x10)
    call PrintDec8
    ld   hl, sClks
    call PrintStr
    ; CTRL_LIVE
    ld   b, 15
    ld   c, 1
    call SetPos
    ld   hl, sCtrl
    call PrintStr
    ld   a, (mon_buf + 0x0D)
    call PrintCtrlLive
    ret

sIWHdr:   db "--- INT/WAIT/CTRL ---           ", 0
sIntRate: db "/INT=", 0
sHz:      db "Hz ", 0
sIntOK:   db "OK   ", 0
sIntAlrt: db "ALERT", 0
sWait:    db "/WAIT=", 0
sWMax:    db " max=", 0
sClks:    db "tk   ", 0
sCtrl:    db "CTRL:", 0

; PrintCtrlLive – A=CTRL_LIVE; decode bit7(RF)..bit0(RD) as H/L
; ctrlNames: 2-byte abbreviations for bits 7..0, NUL-terminated list
PrintCtrlLive:
    ld   (ctrlByte), a
    ld   hl, ctrlNames
    ld   d, 7               ; bit index 7..0
.loop:
    ld   a, (hl)
    or   a
    ret  z                  ; end of table
    call CHPUT_E
    inc  hl
    ld   a, (hl)
    call CHPUT_E
    inc  hl
    ld   a, '='
    call CHPUT_E
    ld   a, d
    call BitMask8
    ld   b, a               ; B = bit mask
    ld   a, (ctrlByte)
    and  b
    jr   nz, .hi
    ld   a, 'L'
    call CHPUT_E
    jr   .sep
.hi:
    ld   a, 'H'
    call CHPUT_E
.sep:
    ld   a, ' '
    call CHPUT_E
    dec  d
    jp   m, .done
    jr   .loop
.done:
    ret

; 2-char signal names bits 7..0: RF M1 WT IN RS MR IO RD
ctrlNames: db "RF", "M1", "WT", "IN", "RS", "MR", "IO", "RD", 0

; ===========================================================================
;  Section 5 – Activity counters
; ===========================================================================
DrawActivity:
    ld   b, 17
    ld   c, 1
    call SetPos
    ld   hl, sActHdr
    call PrintStr
    ld   b, 18
    ld   c, 1
    call SetPos
    ld   hl, sIorqCnt
    call PrintStr
    ld   a, (mon_buf + 0x11)
    ld   l, a
    ld   a, (mon_buf + 0x12)
    ld   h, a
    call PrintDec16
    ld   hl, sMreqCnt
    call PrintStr
    ld   a, (mon_buf + 0x13)
    ld   l, a
    ld   a, (mon_buf + 0x14)
    ld   h, a
    call PrintDec16
    ld   b, 19
    ld   c, 1
    call SetPos
    ld   hl, sLastIO
    call PrintStr
    ld   a, (mon_buf + 0x09)
    call PrintHexA
    ld   a, '='
    call CHPUT_E
    ld   a, (mon_buf + 0x0A)
    call PrintHexA
    ld   hl, sLastA
    call PrintStr
    ld   a, (mon_buf + 0x0C)
    call PrintHexA
    ld   a, (mon_buf + 0x0B)
    call PrintHexA
    ld   hl, sPad8
    call PrintStr
    ret

sActHdr:  db "--- ACTIVITY ---                ", 0
sIorqCnt: db "IORQ=", 0
sMreqCnt: db " MREQ=", 0
sLastIO:  db "IO:", 0
sLastA:   db " A:", 0

; ===========================================================================
;  Footer
; ===========================================================================
DrawFooter:
    ld   b, 24
    ld   c, 1
    call SetPos
    ld   hl, sFooter
    call PrintStr
    ret
sFooter: db "SPACE=re-arm  ESC=volver al Doctor", 0

; ===========================================================================
;  Include utilities and all test modules
; ===========================================================================
    include "helpers.asm"
    include "diag_extra.asm"
    include "reloc.asm"
    include "test_bios.asm"
    include "test_ram.asm"
    include "test_vdp.asm"
    include "test_ppi_psg.asm"
    include "test_map_rtc.asm"
    include "doctor.asm"

; ===========================================================================
;  Save 16 KB ROM image (0x4000-0x7FFF)
;  The byte at 0x7FFF anchors the range; unwritten space is 0x00 fill.
; ===========================================================================
RomEnd:
    IF RomEnd > 0x7FF0
        ERROR "ROM overflow"
    ENDIF
    ORG 0x7FFF
    db  0xFF
    SAVEBIN "DIAG.ROM", 0x4000, 0x4000

; ===========================================================================
;  RAM variables (location counter only; not written to ROM image)
; ===========================================================================
    include "vars.asm"
