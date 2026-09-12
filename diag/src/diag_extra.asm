; =============================================================================
;  diag_extra.asm  –  Slot scan and RAM pattern test sections
;  Included by diag.asm after helpers.asm.
;  (sjasmplus syntax: one instruction per line — no '\' separators.)
; =============================================================================

; ===========================================================================
;  DrawSlotScan  –  row 21: primary slots 0-3, read via BIOS RDSLT
;  RDSLT (0x000C): A = slot descriptor bits7:6=primary, HL = byte address
;  Descriptor: A = (slot_num << 6); subslot=0, expand-flag=0.
; ===========================================================================
DrawSlotScan:
    ld   b, 21
    ld   c, 1
    call SetPos
    ld   hl, sSlotHdr
    call PrintStr
    ld   d, 0               ; slot index 0..3
dsLoop:
    ; Slot descriptor for RDSLT: primary slot goes in bits 1:0 = d (0..3).
    ; (The old "d<<6" was wrong and only read slot 0 correctly.)
    ld   a, d
    push af                 ; save descriptor
    ; Print "Sn:"
    ld   a, 'S'
    call CHPUT_E
    ld   a, d
    add  a, '0'
    call CHPUT_E
    ld   a, ':'
    call CHPUT_E
    ; Read byte 0 at 0x4000
    pop  af
    ld   hl, 0x4000
    di
    call RDSLT
    ei
    ld   (slByte0), a
    ; Read byte 1 at 0x4001 (rebuild descriptor)
    ld   a, d
    ld   hl, 0x4001
    di
    call RDSLT
    ei
    ld   (slByte1), a
    ; Classify: check for ROM header 'A','B'
    ld   a, (slByte0)
    cp   0x41
    jr   nz, dsNotROM
    ld   a, (slByte1)
    cp   0x42
    jr   nz, dsNotROM
    ld   hl, sROM
    call PrintStr
    jr   dsNext
dsNotROM:
    ld   a, (slByte0)
    cp   0xFF
    jr   nz, dsUnkn
    ld   hl, sEmpty
    call PrintStr
    jr   dsNext
dsUnkn:
    ld   hl, sUnkn
    call PrintStr
    ld   a, (slByte0)
    call PrintHexA
    ld   a, ' '
    call CHPUT_E
dsNext:
    inc  d
    ld   a, d
    cp   4
    jr   c, dsLoop
    ret

sSlotHdr: db "SLOT:", 0
sROM:     db "ROM ", 0
sEmpty:   db "--- ", 0
sUnkn:    db "?", 0

; ===========================================================================
;  DrawRamTest  –  rows 22-23
; ===========================================================================
DrawRamTest:
    ld   b, 22
    ld   c, 1
    call SetPos
    ld   hl, sRamHdr
    call PrintStr
    call DoRamTest
    ld   b, 23
    ld   c, 1
    call SetPos
    ld   a, (ramOK)
    or   a
    jr   z, drtFail
    ld   hl, sRamOK
    call PrintStr
    ret
drtFail:
    ld   hl, sRamFail
    call PrintStr
    ld   hl, (ramFailAddr)
    call PrintHexHL
    ld   a, ' '
    call CHPUT_E
    ld   a, (ramFailBits)
    call PrintHexA
    ld   hl, sPad8
    call PrintStr
    ret

sRamHdr:  db "--- RAM INTERNA GOAULD C100+ ---", 0
sRamOK:   db "RAM OK                          ", 0
sRamFail: db "FAIL@", 0

; ===========================================================================
;  DoRamTest – run fixed + walking-1 patterns; update ramOK / ramFailAddr
; ===========================================================================
DoRamTest:
    ld   a, 1
    ld   (ramOK), a      ; assume OK
    ld   a, 0x00
    call WVPat
    ret  z
    ld   a, 0xFF
    call WVPat
    ret  z
    ld   a, 0xAA
    call WVPat
    ret  z
    ld   a, 0x55
    call WVPat
    ret  z
    ; Walking-1: 0x01..0x80
    ld   a, 1
    ld   (w1pat), a
    ld   a, 8
    ld   (w1cnt), a
drtW1:
    ld   a, (w1pat)
    call WVPat
    ret  z
    ld   a, (w1pat)
    rlca
    ld   (w1pat), a
    ld   a, (w1cnt)
    dec  a
    ld   (w1cnt), a
    jr   nz, drtW1
    ret

; ===========================================================================
;  WVPat – write pattern A to RAM_TEST_START..+LEN-1, read back, verify.
;          Pattern is held in E across the loops (A is clobbered by the
;          16-bit BC counter test, so it must NOT carry the pattern).
;          Returns NZ = OK, Z = error (sets ramOK=0, ramFailAddr, ramFailBits)
; ===========================================================================
WVPat:
    ld   (patCurr), a
    ld   e, a               ; E = pattern, preserved across both loops
    ld   hl, RAM_TEST_START
    ld   bc, RAM_TEST_LEN
wvpW:
    ld   (hl), e
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, wvpW
    ld   hl, RAM_TEST_START
    ld   bc, RAM_TEST_LEN
wvpV:
    ld   a, e
    cp   (hl)
    jr   nz, wvpFail
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, wvpV
    or   1                  ; force NZ = all OK
    ret
wvpFail:
    xor  a
    ld   (ramOK), a         ; 0 = failed
    ld   (ramFailAddr), hl
    ld   a, (hl)
    ld   d, a
    ld   a, e               ; expected pattern
    xor  d                  ; bits that differ
    ld   (ramFailBits), a
    xor  a                  ; force Z = error
    ret
