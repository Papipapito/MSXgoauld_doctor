; =============================================================================
;  diag_ramscan.asm  –  Motherboard RAM Scan, Goa'uld MSX2+ Diagnostic ROM
;  Included by diag.asm after diag_extra.asm.
;  (sjasmplus: ONE instruction per line; no '\' separators.)
;
;  BIOS entries used:
;    ENASLT  equ 0x0024  ; A=slot-id, HL=addr-in-page -> enable slot for page
;  System variable:
;    RAMAD2  equ 0xF345  ; slot id currently mapped to page 2 (0x8000-0xBFFF)
;
;  Slot ids (ENASLT format):
;    Primary slot 1      : 0x01
;    Primary slot 2      : 0x02
;    Slot 3 subslot 0    : 0x83  (bit7=expand,bits1:0=primary3,bits3:2=sub0)
;
;  Page 2 (0x8000-0xBFFF) is the ONLY page we swap:
;    Page 0 = BIOS (must stay), Page 1 = our ROM at 0x4000 (must stay),
;    Page 3 = stack + system vars at 0xC000+ (must stay).
;
;  After each slot test, and on exit, page 2 is restored via RAMAD2.
; =============================================================================

ENASLT       equ  0x0024   ; BIOS: map slot A to page containing HL
RAMAD2       equ  0xF345   ; system var: slot currently mapped to page 2

PAGE2_BASE   equ  0x8000
PAGE2_LEN    equ  0x4000   ; 16384 bytes

; ===========================================================================
;  RamScan  –  full-screen motherboard RAM scan
;  Called from MainLoop on key 'R' / 'r'.  Returns to caller after keypress.
; ===========================================================================
RamScan:
    call INITXT             ; clear screen, SCREEN 0 40 col
    ld   b, 1
    ld   c, 1
    call SetPos
    ld   hl, sRSTitle
    call PrintStr
    ld   b, 2
    ld   c, 1
    call SetPos
    ld   hl, sRSSep
    call PrintStr

    ; Re-arm bus monitor so stuck-bit counts start fresh
    xor  a
    out  (MON_DAT), a

    ; Save current page-2 slot id before we touch anything
    ld   a, (RAMAD2)
    ld   (rsOrigSlot), a

    ; --- Test slot 1 (id=0x01) at row 4 ---
    ld   a, 0x01
    ld   (rsCurSlot), a
    ld   a, 4
    ld   (rsRow), a
    call RamScanSlot
    ; Restore page 2
    ld   a, (rsOrigSlot)
    ld   hl, PAGE2_BASE
    di
    call ENASLT
    ei

    ; --- Test slot 2 (id=0x02) at row 7 ---
    ld   a, 0x02
    ld   (rsCurSlot), a
    ld   a, 7
    ld   (rsRow), a
    call RamScanSlot
    ; Restore page 2
    ld   a, (rsOrigSlot)
    ld   hl, PAGE2_BASE
    di
    call ENASLT
    ei

    ; --- Test slot 3 sub 0 (id=0x83) at row 10 ---
    ld   a, 0x83
    ld   (rsCurSlot), a
    ld   a, 10
    ld   (rsRow), a
    call RamScanSlot
    ; Restore page 2 (final, unconditional)
    ld   a, (rsOrigSlot)
    ld   hl, PAGE2_BASE
    di
    call ENASLT
    ei

    ; --- Read bus monitor stuck bits after all tests ---
    ld   b, 14
    ld   c, 1
    call SetPos
    ld   hl, sRSBits
    call PrintStr
    ld   a, 0x02
    out  (MON_IDX), a
    in   a, (MON_DAT)       ; reg 0x02 = D_DEAD_LO; auto-increments idx
    ld   (rsBitLo), a
    in   a, (MON_DAT)       ; reg 0x03 = D_DEAD_HI
    ld   (rsBitHi), a
    ld   a, (rsBitLo)
    call PrintHexA
    ld   a, ' '
    call CHPUT_E
    ld   a, (rsBitHi)
    call PrintHexA
    ld   a, (rsBitLo)
    ld   c, a
    ld   a, (rsBitHi)
    or   c
    jr   nz, rsShowAlrt
    ld   hl, sRSBitsOK
    call PrintStr
    jr   rsFooter
rsShowAlrt:
    ld   hl, sRSBitsAlrt
    call PrintStr

rsFooter:
    ld   b, 21
    ld   c, 1
    call SetPos
    ld   hl, sRSNote1
    call PrintStr
    ld   b, 22
    ld   c, 1
    call SetPos
    ld   hl, sRSNote2
    call PrintStr
    ld   b, 24
    ld   c, 1
    call SetPos
    ld   hl, sRSPressKey
    call PrintStr

    ; Wait for keypress
rsWaitKey:
    call WaitKeyEdge
    ret

; ---------------------------------------------------------------------------
;  Strings – RamScan main
; ---------------------------------------------------------------------------
sRSTitle:    db "== SCAN RAM PLACA MADRE ==      ", 0
sRSSep:      db "Mapeando pag2(8000-BFFF) / slot ", 0
sRSBits:     db "Bus D bits-pegados LO/HI: ", 0
sRSBitsOK:   db "ninguno      ", 0
sRSBitsAlrt: db " <-- ALERTA  ", 0
sRSNote1:    db "Slot1/2=externos. Slot3=mapper  ", 0
sRSNote2:    db "interno salvo reubicacion conf. ", 0
sRSPressKey: db "Pulsa una tecla para volver.    ", 0

; ===========================================================================
;  RamScanSlot  –  test one slot and print result
;  Entry: rsCurSlot = slot id, rsRow = display row
;  page 2 is mapped to the target slot by the caller (we do the ENASLT here
;  actually — we do it internally so the logic is contained).
; ===========================================================================
RamScanSlot:
    ; Position cursor at rsRow, col 1
    ld   a, (rsRow)
    ld   b, a
    ld   c, 1
    call SetPos

    ; Print "Slot xx: "
    ld   hl, sRSSl
    call PrintStr
    ld   a, (rsCurSlot)
    call PrintHexA
    ld   hl, sRSColon
    call PrintStr

    ; Identify what is in the slot (ROM 'AB' / data / empty) via RDSLT,
    ; which peeks another slot's page-1 without unmapping our own code.
    call RsIdentify

    ; Map page 2 to target slot
    ld   a, (rsCurSlot)
    ld   hl, PAGE2_BASE
    di
    call ENASLT
    ei

    ; --- Presence probe ---
    ; Write 0xAA to cell 0, 0x55 to cell 1; read back
    ld   hl, PAGE2_BASE
    ld   (hl), 0xAA
    ld   a, (hl)
    cp   0xAA
    jr   nz, rssNoRam
    inc  hl
    ld   (hl), 0x55
    ld   a, (hl)
    cp   0x55
    jr   nz, rssNoRam
    ; Complement check
    ld   hl, PAGE2_BASE
    ld   (hl), 0x55
    ld   a, (hl)
    cp   0x55
    jr   nz, rssNoRam
    inc  hl
    ld   (hl), 0xAA
    ld   a, (hl)
    cp   0xAA
    jr   nz, rssNoRam

    ; --- RAM present: run full suite ---
    call RsFullSuite
    ld   a, (rsSlotOK)
    or   a
    jr   z, rssFail

    ; OK
    ld   hl, sRSOK
    call PrintStr
    ret

rssFail:
    ld   hl, sRSFail
    call PrintStr
    ld   hl, (rsFailAddr)
    call PrintHexHL
    ld   hl, sRSExp
    call PrintStr
    ld   a, (rsFailExp)
    call PrintHexA
    ld   hl, sRSGot
    call PrintStr
    ld   a, (rsFailGot)
    call PrintHexA
    ld   hl, sRSBit
    call PrintStr
    ld   a, (rsFailXOR)
    call PrintHexA
    ret

rssNoRam:
    ld   hl, sRSNoRam
    call PrintStr
    ret

; ---------------------------------------------------------------------------
;  Strings – slot result
; ---------------------------------------------------------------------------
sRSSl:    db "Slot ", 0
sRSColon: db ": ", 0
sRSOK:    db "OK (16384 b)            ", 0
sRSFail:  db "FALLO @", 0
sRSExp:   db " esp=", 0
sRSGot:   db " got=", 0
sRSBit:   db " bits=", 0
sRSNoRam: db "sin RAM                 ", 0

; ===========================================================================
;  RsIdentify  –  peek slot rsCurSlot at 0x4000/0x4001 via BIOS RDSLT and print
;  "ROM " (AB cartridge header) / "dat " (non-FF data) / "--- " (empty / FF).
;  RDSLT (0x000C) reads from any slot without disturbing the current page-1
;  mapping (our diagnostic ROM stays put). A = slot id (same format as ENASLT).
; ===========================================================================
RsIdentify:
    ld   a, (rsCurSlot)
    ld   hl, 0x4000
    di
    call RDSLT
    ei
    ld   (rsB0), a
    ld   a, (rsCurSlot)
    ld   hl, 0x4001
    di
    call RDSLT
    ei
    ld   (rsB1), a
    ; AB cartridge header?
    ld   a, (rsB0)
    cp   0x41
    jr   nz, rsIdNotAB
    ld   a, (rsB1)
    cp   0x42
    jr   nz, rsIdNotAB
    ld   hl, sIdROM
    call PrintStr
    ret
rsIdNotAB:
    ld   a, (rsB0)
    inc  a                  ; 0xFF -> 0x00 => looks empty
    jr   nz, rsIdData
    ld   hl, sIdEmpty
    call PrintStr
    ret
rsIdData:
    ld   hl, sIdData
    call PrintStr
    ret

sIdROM:   db "ROM ", 0
sIdData:  db "dat ", 0
sIdEmpty: db "--- ", 0

; ===========================================================================
;  RsFullSuite  -  the generic suite lives in RAM (reloc.asm: RamSuite);
;                  page 2 is already mapped to the target slot by the caller.
; ===========================================================================
RsFullSuite:
    ld   hl, PAGE2_BASE
    ld   (rtBase), hl
    call RamSuite
    ret
