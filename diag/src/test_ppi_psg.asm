; =============================================================================
;  test_ppi_psg.asm  -  Goa'uld Doctor  -  board PPI (8255), PSG (AY-3-8910)
;                        and a live keyboard-matrix screen
;
;  PPI: with CONTROL.ppi_ext an IN 0xA8 returns the board's real 8255 latch
;       (normally the Goa'uld answers with its own copy); it must equal what
;       the core last wrote.  Port C (0xAA) is read back after toggling the
;       CAPS-LED bit.  Port B (0xA9) is the keyboard row.
;  PSG: reads already come from the board (the Goa'uld only mirrors writes),
;       so R0-R13 are written with two patterns and read back through 0xA2.
;  (sjasmplus: one instruction per line.)
; =============================================================================

; ===========================================================================
;  PpiTest
; ===========================================================================
PpiTest:
    di
    in   a, (0xA8)
    ld   (ppiA8exp), a
    ld   a, CTL_PPI
    call MonSetCtrl
    in   a, (0xA8)
    ld   (ppiA8got), a
    xor  a
    call MonSetCtrl
    in   a, (0xAA)
    ld   c, a
    xor  0x40                   ; toggle CAPS LED bit
    out  (0xAA), a
    ld   (ppiAAexp), a
    in   a, (0xAA)
    ld   (ppiAAgot), a
    ld   a, c
    out  (0xAA), a
    in   a, (0xA9)
    ld   (ppiA9), a
    ei
    ret

; ===========================================================================
;  PpiPrint  -  "PPI    A8 xx=xx AA xx=xx A9=xx      OK"
; ===========================================================================
PpiPrint:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sPpiHdr
    call PrintAt
    ld   a, (ppiA8exp)
    call PrintHexA
    ld   a, '='
    call CHPUT
    ld   a, (ppiA8got)
    call PrintHexA
    ld   hl, sPpiAA
    call PrintStr
    ld   a, (ppiAAexp)
    call PrintHexA
    ld   a, '='
    call CHPUT
    ld   a, (ppiAAgot)
    call PrintHexA
    ld   hl, sPpiA9
    call PrintStr
    ld   a, (ppiA9)
    call PrintHexA
    ld   a, (ppiA8exp)
    ld   c, a
    ld   a, (ppiA8got)
    cp   c
    jr   nz, ppFail
    ld   a, (ppiAAexp)
    ld   c, a
    ld   a, (ppiAAgot)
    cp   c
    jr   nz, ppFail
    call PrintOK
    ret
ppFail:
    call PrintFAIL
    ret
sPpiHdr: db "PPI    A8 ", 0
sPpiAA:  db " AA ", 0
sPpiA9:  db " A9=", 0

; ===========================================================================
;  PsgTest  -  psgFail bit n = register n did not read back
; ===========================================================================
PsgTest:
    di
    ld   hl, 0
    ld   (psgFail), hl
    ld   a, 0x55
    ld   (psgPass), a
    call PsgPassRun
    ld   a, 0xAA
    ld   (psgPass), a
    call PsgPassRun
    ; silence: R7 = 1011 1111 (port B out, port A in, all channels off)
    ld   e, 7
    ld   a, 0xBF
    call PsgWrite
    ld   e, 8
    xor  a
    call PsgWrite
    ld   e, 9
    xor  a
    call PsgWrite
    ld   e, 10
    xor  a
    call PsgWrite
    ei
    ret

PsgPassRun:
    ld   e, 0
pprLoop:
    ld   hl, psgMasks
    ld   c, e
    ld   b, 0
    add  hl, bc
    ld   a, (psgPass)
    and  (hl)
    ld   c, a                   ; C = expected
    ld   a, e
    cp   7
    jr   nz, pprW
    ld   a, c
    or   0x80                   ; R7: port B output, port A input
    ld   c, a
pprW:
    ld   a, c
    call PsgWrite
    call PsgRead
    cp   c
    jr   z, pprNext
    ; set bit E of psgFail
    ld   a, e
    ld   hl, psgFail
    cp   8
    jr   c, pprBit
    inc  hl
    sub  8
pprBit:
    ld   b, a
    ld   a, 1
    inc  b
pprSh:
    dec  b
    jr   z, pprSet
    rlca
    jr   pprSh
pprSet:
    or   (hl)
    ld   (hl), a
pprNext:
    inc  e
    ld   a, e
    cp   14
    jr   c, pprLoop
    ret

; R0 R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12 R13
psgMasks: db 0xFF, 0x0F, 0xFF, 0x0F, 0xFF, 0x0F, 0x1F, 0x3F, 0x1F, 0x1F, 0x1F, 0xFF, 0xFF, 0x0F

; PsgWrite: E = reg, A = value.  PsgRead: E = reg -> A
PsgWrite:
    ld   d, a
    ld   a, e
    out  (0xA0), a
    ld   a, d
    out  (0xA1), a
    ret
PsgRead:
    ld   a, e
    out  (0xA0), a
    in   a, (0xA2)
    ret

; ===========================================================================
;  PsgPrint  -  "PSG    R0-R13 releen OK / fallan: 0 1 5"
; ===========================================================================
PsgPrint:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sPsgHdr
    call PrintAt
    ld   hl, (psgFail)
    ld   a, h
    or   l
    jr   nz, psgBad
    ld   hl, sPsgOK
    call PrintStr
    call PrintOK
    ret
psgBad:
    ld   b, 14
    ld   c, 0
psgCnt:
    srl  h
    rr   l
    jr   nc, psgCnt1
    inc  c
psgCnt1:
    djnz psgCnt
    ld   a, c
    cp   14
    jr   nz, psgSome
    ld   hl, sPsgNone
    call PrintStr
    call PrintFAIL
    ret
psgSome:
    ld   hl, sPsgBad
    call PrintStr
    ld   a, c
    cp   6
    jr   c, psgListAll
    call PrintDec8              ; too many for one row: "9 de 14"
    ld   hl, sPsgOf
    call PrintStr
    call PrintFAIL
    ret
psgListAll:
    ld   de, (psgFail)
    ld   b, 0
psgList:
    srl  d
    rr   e
    jr   nc, psgNextBit
    ld   a, 'R'
    call CHPUT
    push bc
    push de
    ld   a, b
    call PrintDec8              ; clobbers B, C, D, E
    pop  de
    pop  bc
    call PrintSpace
psgNextBit:
    inc  b
    ld   a, b
    cp   14
    jr   c, psgList
    call PrintFAIL
    ret
sPsgHdr: db "PSG    ", 0
sPsgOK:  db "R0-R13 releen bien", 0
sPsgBad: db "fallan: ", 0
sPsgOf:  db " de 14", 0
sPsgNone: db "ninguno relee (R0-R13)", 0

; ===========================================================================
;  KbdScreen  -  live keyboard matrix (11 rows x 8 bits), CAPS LED blinks.
;                ESC (row 7 bit 2) exits.  Physical and USB keys both show.
; ===========================================================================
KbdScreen:
    call INITXT
    ld   b, 1
    ld   c, 1
    ld   hl, sKbdTitle
    call PrintAt
    ld   b, 3
    ld   c, 1
    ld   hl, sKbdCols
    call PrintAt
    ld   b, 16
    ld   c, 1
    ld   hl, sKbdHelp1
    call PrintAt
    ld   b, 17
    ld   c, 1
    ld   hl, sKbdHelp2
    call PrintAt
    xor  a
    ld   (kbdTick), a
    ld   a, (kbdCtl)
    push af
    ld   a, CTL_USBOFF          ; the board's keyboard alone
    ld   (kbdCtl), a
ksLoop:
    call ScanMatrix             ; 11 rows into KBD_MATRIX
    di
    ; CAPS LED blink every 16 passes
    ld   a, (kbdTick)
    inc  a
    ld   (kbdTick), a
    and  0x0F
    jr   nz, ksNoBlink
    in   a, (0xAA)
    xor  0x40
    out  (0xAA), a
ksNoBlink:
    ei
    ; draw
    ld   hl, KBD_MATRIX
    ld   d, 0                   ; row index
ksDraw:
    push hl
    ld   a, d
    add  a, 4
    ld   b, a
    ld   c, 1
    call SetPos
    ld   a, 'R'
    call CHPUT
    push de
    ld   a, d
    call PrintDec8              ; clobbers D
    pop  de
    ld   a, d
    cp   10
    jr   nc, ksDrawSp
    call PrintSpace
ksDrawSp:
    call PrintSpace
    pop  hl
    ld   e, (hl)
    inc  hl
    ld   b, 8
ksBits:
    rl   e                      ; bit 7 first
    ld   a, '.'
    jr   c, ksBitOff
    ld   a, 'X'
ksBitOff:
    push bc
    call CHPUT
    call PrintSpace
    pop  bc
    djnz ksBits
    inc  d
    ld   a, d
    cp   11
    jr   c, ksDraw
    ; ESC = row 7 bit 2
    ld   a, (KBD_MATRIX + 7)
    and  0x04
    jr   z, ksExit
    ld   c, 40
    call DelayMs
    jr   ksLoop
ksExit:
    ; CAPS LED off (bit 6 = 1)
    in   a, (0xAA)
    or   0x40
    out  (0xAA), a
    pop  af
    ld   (kbdCtl), a
    ret

sKbdTitle: db "MATRIZ TECLADO DE LA PLACA (sin USB)", 0
sKbdCols:  db "     b7 b6 b5 b4 b3 b2 b1 b0", 0
sKbdHelp1: db "X = tecla pulsada. LED CAPS parpadea.", 0
sKbdHelp2: db "ESC para volver.", 0
