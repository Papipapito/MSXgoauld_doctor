; =============================================================================
;  helpers.asm  –  Goa'uld MSX Diagnostic  –  utility subroutines
;  Included by diag.asm.  No duplicate labels; every routine is clean.
;
;  Port update (2025-06): monitor ports changed to 0x2C/0x2D (0x4C/0x4D
;  conflicted with OCM switched-I/O on the Goa'uld).
; =============================================================================

; ---------------------------------------------------------------------------
;  BIOS entry points  (MSX main-ROM, always mapped at page 0)
; ---------------------------------------------------------------------------
CHPUT   equ 0x00A2      ; output char in A
POSIT   equ 0x00C6      ; set cursor  H=col(1-based)  L=row(1-based)
CHSNS   equ 0x009C      ; Z=1 no key / Z=0 key waiting
CHGET   equ 0x009F      ; blocking key read -> A

; ---------------------------------------------------------------------------
;  Bus-monitor I/O ports
; ---------------------------------------------------------------------------
MON_IDX equ 0x2C        ; OUT: set register index
MON_DAT equ 0x2D        ; IN: read regs[idx] then idx++   |  OUT: re-arm

; ===========================================================================
;  PrintStr  –  print NUL-terminated string at HL
;  Clobbers: AF, HL
; ===========================================================================
PrintStr:
    ld   a, (hl)
    or   a
    ret  z
    call CHPUT
    inc  hl
    jr   PrintStr

; ===========================================================================
;  PrintHexA  –  print A as two uppercase hex digits
;  Clobbers: AF
; ===========================================================================
PrintHexA:
    push af
    rrca
    rrca
    rrca
    rrca
    call _HexNib
    pop  af
    call _HexNib
    ret

_HexNib:
    and  0x0F
    add  a, '0'
    cp   0x3A
    jr   c, _HexNibOut
    add  a, 7
_HexNibOut:
    call CHPUT
    ret

; ===========================================================================
;  PrintHexHL  –  print HL as four hex digits (H high, L low)
;  Clobbers: AF
; ===========================================================================
PrintHexHL:
    ld   a, h
    call PrintHexA
    ld   a, l
    call PrintHexA
    ret

; ===========================================================================
;  PrintDec8  –  print A (0..255) as decimal, no leading zeros, min 1 digit
;  Clobbers: AF, B, C, D, E
;  Algorithm: repeated subtraction; no extra RAM needed.
; ===========================================================================
PrintDec8:
    ld   e, a           ; E = value
    ld   d, 0           ; D = "have printed nonzero" flag
    ld   c, 100
    call _PD8Digit
    ld   c, 10
    call _PD8Digit
    ; units always printed
    ld   a, e
    add  a, '0'
    call CHPUT
    ret

_PD8Digit:
    ; Divide E by C via repeated subtraction.
    ; B = quotient digit; E = remainder afterward.
    ld   b, 0
_PD8SubL:
    ld   a, e
    sub  c
    jr   c, _PD8SubDone
    ld   e, a
    inc  b
    jr   _PD8SubL
_PD8SubDone:
    ; B = digit value.  Suppress leading zeros using D flag.
    ld   a, b
    or   a
    jr   nz, _PD8DoPrint    ; nonzero: always print
    ld   a, d
    or   a
    ret  z                  ; leading zero: skip
    ld   a, 0               ; digit is zero but not leading: print it
_PD8DoPrint:
    ld   d, 1               ; mark that we printed a nonzero
    ld   a, b
    add  a, '0'
    call CHPUT
    ret

; ===========================================================================
;  PrintDec16  –  print HL (16-bit unsigned) as decimal, no leading zeros
;  Algorithm: push remainder-digits on the Z80 stack then pop+print.
;  Clobbers: AF, BC, DE, HL
; ===========================================================================
PrintDec16:
    ld   b, 0           ; digit count
_PD16Build:
    call Div10          ; HL = HL/10, A = HL mod 10
    push af             ; save remainder digit (0-9)
    inc  b
    ld   a, h
    or   l
    jr   nz, _PD16Build ; repeat while quotient != 0
_PD16Print:
    pop  af
    add  a, '0'
    call CHPUT
    djnz _PD16Print
    ret

; ===========================================================================
;  Div10  –  HL = HL / 10 (unsigned 16-bit),  A = remainder 0..9
;  Clobbers: AF, BC, DE
; ===========================================================================
Div10:
    push bc
    ld   bc, 10
    ld   de, 0          ; DE = quotient
_Div10Loop:
    ; Check HL < 10
    ld   a, h
    or   a
    jr   nz, _Div10Sub  ; H != 0 => HL >= 256 >= 10
    ld   a, l
    cp   10
    jr   c, _Div10Done  ; L < 10 and H = 0 => done
_Div10Sub:
    or   a              ; clear carry
    sbc  hl, bc         ; HL -= 10
    inc  de
    jr   _Div10Loop
_Div10Done:
    ld   a, l           ; remainder 0-9 (H guaranteed 0 here)
    ex   de, hl         ; HL = quotient
    pop  bc
    ret

; ===========================================================================
;  BitMask8  –  compute (1 << A) in A; A must be 0..7
;  Clobbers: AF, B
; ===========================================================================
BitMask8:
    ld   b, a
    ld   a, 1
    inc  b              ; B = shift count + 1 (because djnz pre-decrements)
    jr   _BM8Loop
_BM8Start:
    rlca
_BM8Loop:
    djnz _BM8Start
    ret
; Note: when b_initial=0, inc b makes B=1; djnz decrements to 0 and falls
; through without shifting -> returns 1. Correct for bit 0.
; When b_initial=7, B=8; 7 rlca's -> 0x80. Correct.

; ===========================================================================
;  SetPos  –  position cursor: B = row (1-based), C = col (1-based)
;  Clobbers: AF, HL
; ===========================================================================
SetPos:
    ld   a, b
    cp   25
    jr   c, $+4
    ld   b, 24
    ld   h, c
    ld   l, b
    call POSIT
    ret

; ===========================================================================
;  ReadMonRegs  –  block-read monitor regs 0x00..0x14 into mon_buf
;  Clobbers: AF, B, HL
; ===========================================================================
ReadMonRegs:
    xor  a
    out  (MON_IDX), a   ; index = 0
    ld   hl, mon_buf
    ld   b, 0x21        ; registers 0x00-0x20 (v2 map)
_RMRLoop:
    in   a, (MON_DAT)   ; read regs[idx]; idx auto-increments
    ld   (hl), a
    inc  hl
    djnz _RMRLoop
    ret

; ===========================================================================
;  RearmMonitor  –  OUT (MON_DAT), 0  =>  clear / re-arm all accumulators
; ===========================================================================
RearmMonitor:
    xor  a
    out  (MON_DAT), a
    ret

; ===========================================================================
;  PrintSpace / PrintNL  –  convenience
; ===========================================================================
PrintSpace:
    ld   a, ' '
    call CHPUT
    ret

PrintNL:
    ld   a, 0x0D
    call CHPUT
    ld   a, 0x0A
    call CHPUT
    ret

; ===========================================================================
;  ---- Goa'uld Doctor additions ----
; ===========================================================================
EXPTBL  equ 0xFCC1      ; BIOS: expanded-slot flags, 4 bytes
SLTTBL  equ 0xFCC5      ; BIOS: image of the secondary slot registers

MON_CTRL  equ 0x20      ; CONTROL register index
MON_CTRL2 equ 0x21      ; CONTROL2: transparency mask bits 3:0, bit4 p3_release
CTL_SLOT0 equ 0x01      ; physical slot 0 transparent
CTL_VDP   equ 0x02      ; VDP ports -> board VDP
CTL_IGNINT equ 0x04     ; mask external /INT
CTL_IGNWAIT equ 0x08    ; mask external /WAIT
CTL_PPI   equ 0x10      ; IN A8 from the board PPI
CTL_RTC   equ 0x20      ; IN B5 from the board RTC
CTL_USBOFF equ 0x40     ; IN A9 without the USB keyboard
CTL_PHYSOFF equ 0x80    ; IN A9 without the board keyboard

; ===========================================================================
;  MonSetCtrl  -  write the CONTROL register: A = value
;  Clobbers: AF
; ===========================================================================
MonSetCtrl:
    push af
    ld   a, MON_CTRL
    out  (MON_IDX), a
    pop  af
    out  (MON_DAT), a
    ret

; ===========================================================================
;  MonReadReg  -  A = index -> A = value
; ===========================================================================
MonReadReg:
    out  (MON_IDX), a
    in   a, (MON_DAT)
    ret

; ===========================================================================
;  MonDetect  -  monPresent = 1 if SIG=0x42 and VERSION>=2
; ===========================================================================
MonDetect:
    xor  a
    ld   (monPresent), a
    call MonReadReg
    cp   0x42
    ret  nz
    ld   a, 1
    call MonReadReg
    cp   2
    ret  c
    ld   a, 1
    ld   (monPresent), a
    ret

; ===========================================================================
;  PrintHex32  -  HL -> 4 bytes little-endian; prints b3 b2 b1 b0
;  Clobbers: AF, HL
; ===========================================================================
PrintHex32:
    inc  hl
    inc  hl
    inc  hl
    ld   a, (hl)
    call PrintHexA
    dec  hl
    ld   a, (hl)
    call PrintHexA
    dec  hl
    ld   a, (hl)
    call PrintHexA
    dec  hl
    ld   a, (hl)
    call PrintHexA
    ret

; ===========================================================================
;  PrintAt  -  B = row, C = col, HL = string
; ===========================================================================
PrintAt:
    push hl
    call SetPos
    pop  hl
    call PrintStr
    ret

; ===========================================================================
;  PrintOK / PrintFAIL / PrintNA  -  verdict at column 36 of the current row
; ===========================================================================
PrintOK:
    ld   a, (row)
    ld   b, a
    ld   c, 36
    call SetPos
    ld   hl, sVOK
    call PrintStr
    ret
PrintFAIL:
    ld   a, (row)
    ld   b, a
    ld   c, 36
    call SetPos
    ld   hl, sVFAIL
    call PrintStr
    ret
PrintNA:
    ld   a, (row)
    ld   b, a
    ld   c, 36
    call SetPos
    ld   hl, sVNA
    call PrintStr
    ret
sVOK:   db "OK  ", 0
sVFAIL: db "MAL ", 0
sVNA:   db "n/d ", 0

; ===========================================================================
;  DelayMs  -  C = milliseconds (1..255), ~3.58 MHz busy loop (no BIOS)
;  Clobbers: AF, BC
; ===========================================================================
DelayMs:
    ld   b, 0           ; 256 x 13 T = 3328 T + overhead ~= 0.93 ms
_DMinner:
    djnz _DMinner
    dec  c
    jr   nz, DelayMs
    ret

; ===========================================================================
;  Keyboard by edges  -  the board's keyboard may have stuck keys or an
;  intermittent membrane, and the FPGA merges the USB keyboard (RP2040 link,
;  which can carry garbage) into the same PPI read.  So the key loops scan
;  the matrix themselves (no ISR, no KEYBUF), react only to a key going from
;  released to pressed after a quiet window, and each source is checked
;  alone at boot: a noisy one is dropped from IN A9 (CONTROL bits 6/7).
; ===========================================================================
; ScanMatrix - 11 rows through the PPI -> KBD_MATRIX, with the keyboard
;              source mask (kbdCtl) on top of whatever CONTROL holds now
ScanMatrix:
    di
    ld   a, MON_CTRL
    call MonReadReg
    push af                     ; current CONTROL (tests may have bits set)
    ld   hl, kbdCtl
    or   (hl)
    call MonSetCtrl
    ld   hl, KBD_MATRIX
    ld   c, 0
smRow:
    in   a, (0xAA)
    and  0xF0
    or   c
    out  (0xAA), a
    in   a, (0xA9)
    ld   (hl), a
    inc  hl
    inc  c
    ld   a, c
    cp   11
    jr   c, smRow
    pop  af
    call MonSetCtrl
    ei
    ret

; StuckKeysInit - at boot, each keyboard source alone for 0.5 s (25 scans):
;   physStuck/usbStuck = keys down in EVERY scan (0 = stuck),
;   physNoise/usbNoise = scans where the matrix changed with nobody typing.
;   A noisy source is then dropped from IN A9 for good (kbdCtl): phantom
;   presses from a bad membrane or from garbage on the RP2040 link must not
;   drive the Doctor, and must not block the other keyboard either.
StuckKeysInit:
    ld   a, CTL_USBOFF          ; board keyboard alone
    ld   (kbdCtl), a
    ld   ix, physStuck
    ld   iy, physNoise
    call KbdSample
    ld   a, CTL_PHYSOFF         ; USB keyboard alone
    ld   (kbdCtl), a
    ld   ix, usbStuck
    ld   iy, usbNoise
    call KbdSample
    ld   b, 0
    ld   a, (physNoise)
    or   a
    jr   z, skiPhysOk
    ld   b, CTL_PHYSOFF
skiPhysOk:
    ld   a, (usbNoise)
    or   a
    jr   z, skiUsbOk
    ld   a, b
    or   CTL_USBOFF
    ld   b, a
skiUsbOk:
    ld   a, b
    ld   (kbdCtl), a
    call ScanMatrix
    ld   hl, KBD_MATRIX
    ld   de, keyPrev
    ld   bc, 11
    ldir
    xor  a
    ld   (kbdQuiet), a
    ret

; KbdSample - IX -> 11-byte stuck image, IY -> noise counter; 25 scans
KbdSample:
    call ScanMatrix
    ld   (iy+0), 0
    push ix
    pop  de
    ld   hl, KBD_MATRIX
    ld   bc, 11
    ldir
    ld   hl, KBD_MATRIX
    ld   de, keyPrev
    ld   bc, 11
    ldir
    ld   b, 25
ksmLoop:
    push bc
    ld   c, 20
    call DelayMs
    call ScanMatrix
    ld   hl, KBD_MATRIX
    ld   de, keyPrev
    push ix
    pop  bc                     ; BC -> stuck image
    ld   a, 11
    ld   (tmpA), a
    xor  a
    ld   (tmpB), a              ; changed flag
ksmRow:
    ld   a, (de)
    cp   (hl)
    jr   z, ksmSame
    ld   a, 1
    ld   (tmpB), a
ksmSame:
    ld   a, (hl)
    ld   (de), a                ; keyPrev = current
    push hl
    ld   h, b
    ld   l, c
    or   (hl)                   ; stuck |= current (released once = not stuck)
    ld   (hl), a
    pop  hl
    inc  hl
    inc  de
    inc  bc
    ld   a, (tmpA)
    dec  a
    ld   (tmpA), a
    jr   nz, ksmRow
    ld   a, (tmpB)
    or   a
    jr   z, ksmNoChg
    inc  (iy+0)
    jr   nz, ksmNoChg
    dec  (iy+0)                 ; saturate at 255
ksmNoChg:
    pop  bc
    djnz ksmLoop
    ret

; PollKeyEdge - non-blocking: A = char (keyTab) of a key that just went
;               down, 0xFF for an unlisted new press, 0 = nothing.  The
;               matrix must have been unchanged for KBD_QUIET polls before
;               the press: a noisy keyboard never earns a quiet window.
KBD_QUIET  equ 25               ; x 20 ms = 0.5 s
PollKeyEdge:
    call ScanMatrix
    xor  a
    ld   (keyChg), a
    ld   a, 0xFF
    ld   (keyRow), a            ; no new press yet
    ld   hl, KBD_MATRIX
    ld   de, keyPrev
    ld   b, 0
pkeRow:
    ld   a, (de)
    ld   c, a                   ; C = previous (1 = released)
    ld   a, (hl)
    cp   c
    jr   z, pkeSame
    ld   a, 1
    ld   (keyChg), a
    ld   a, (hl)
    cpl
    and  c                      ; 1 = down now, up before
    jr   z, pkeSame
    ld   c, a
    ld   a, (keyRow)
    inc  a
    jr   nz, pkeSame            ; keep the first press found
    ld   a, b
    ld   (keyRow), a
    ld   a, c
    ld   c, 0
pkeBit:
    rrca
    jr   c, pkeBitDone
    inc  c
    jr   pkeBit
pkeBitDone:
    ld   a, c
    ld   (keyBit), a
pkeSame:
    inc  hl
    inc  de
    inc  b
    ld   a, b
    cp   11
    jr   c, pkeRow
    ld   hl, KBD_MATRIX
    ld   de, keyPrev
    ld   bc, 11
    ldir
    ld   a, (keyChg)
    or   a
    jr   nz, pkeChanged
    ld   a, (kbdQuiet)
    inc  a
    jr   z, pkeNone             ; saturated
    ld   (kbdQuiet), a
pkeNone:
    xor  a
    ret
pkeChanged:
    ld   a, (kbdQuiet)
    cp   KBD_QUIET
    ld   a, 0
    ld   (kbdQuiet), a
    ret  c                      ; not quiet before the change: ignore
    ld   a, (keyRow)
    inc  a
    ret  z                      ; only releases changed
    dec  a
    ld   b, a
    ld   a, (keyBit)
    ld   c, a
    ld   hl, keyTab             ; B = row, C = bit
pkeTab:
    ld   a, (hl)
    cp   0xFF
    jr   z, pkeUnknown
    cp   b
    jr   nz, pkeSkip
    inc  hl
    ld   a, (hl)
    dec  hl
    cp   c
    jr   nz, pkeSkip
    inc  hl
    inc  hl
    ld   a, (hl)
    ret
pkeSkip:
    inc  hl
    inc  hl
    inc  hl
    jr   pkeTab
pkeUnknown:
    ld   a, 0xFF
    ret

; WaitKeyEdge - blocking PollKeyEdge (polls every 20 ms)
WaitKeyEdge:
    call PollKeyEdge
    or   a
    ret  nz
    ld   c, 20
    call DelayMs
    jr   WaitKeyEdge

keyTab:                         ; row, bit, char (MSX matrix)
    db 8, 0, ' '
    db 3, 1, 'D'
    db 2, 7, 'B'
    db 4, 0, 'K'
    db 4, 2, 'M'
    db 5, 1, 'T'
    db 5, 3, 'V'
    db 5, 5, 'X'
    db 7, 2, 0x1B               ; ESC
    db 7, 7, 0x0D               ; RETURN
    db 0, 1, '1'
    db 0, 2, '2'
    db 0, 3, '3'
    db 0, 4, '4'
    db 0xFF

sRSPressKey: db "Pulsa una tecla para volver.    ", 0

; ===========================================================================
;  GetMySlot  -  A = slot id (ENASLT format) of the slot mapped in page 1,
;                i.e. of THIS ROM.  Goa'uld: 0x8C (slot 0-3); a cartridge in
;                openMSX slot 1: 0x01.
; ===========================================================================
GetMySlot:
    in   a, (0xA8)
    rrca
    rrca
    and  0x03
    ld   c, a
    ld   b, 0
    ld   hl, EXPTBL
    add  hl, bc
    ld   a, (hl)
    and  0x80
    jr   z, _GMSdone            ; not expanded -> id = primary
    ld   hl, SLTTBL
    add  hl, bc
    ld   a, (hl)                ; secondary slot register image
    rrca
    rrca
    and  0x03                   ; subslot of page 1
    rlca
    rlca                        ; -> bits 3:2
    or   0x80
_GMSdone:
    or   c
    ld   (mySlot), a
    ret

