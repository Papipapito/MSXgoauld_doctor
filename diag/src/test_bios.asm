; =============================================================================
;  test_bios.asm  -  Goa'uld Doctor  -  board BIOS ROM test (slot 0, 0000-7FFF)
;
;  RelocBiosRead (reloc.asm, runs from RAM) reads the board's ROM through the
;  bus with CONTROL.slot0_ext and leaves: biosCRC, biosNonFF, BIOS_HEAD[128],
;  biosDead.  Here we judge it:
;    * all 0xFF            -> ROM mute (dead ROM / chip select / decoder)
;    * bytes 0-1 != F3 C3  -> not an MSX BIOS start (DI ; JP)
;    * CRC32 in table      -> identified machine
;    * D_DEAD bits         -> data lines that never moved while the ROM drove
;  (sjasmplus: one instruction per line.)
; =============================================================================

; ===========================================================================
;  BiosTest  -  run the read; results in variables (no printing)
; ===========================================================================
BiosTest:
    call BuildCrcTable
    call RelocBiosRead
    call BiosLookup
    ret

; ===========================================================================
;  BiosLookup  -  biosName = pointer to the name string of a known CRC, or 0
; ===========================================================================
BiosLookup:
    ld   hl, 0
    ld   (biosName), hl
    ld   hl, biosTable
blLoop:
    ld   a, (hl)
    inc  hl
    ld   e, a
    ld   a, (hl)
    inc  hl
    ld   d, a                   ; DE = name pointer (0 = end)
    ld   a, d
    or   e
    ret  z
    ; compare 4 CRC bytes
    ld   b, 4
    ld   ix, biosCRC
blCmp:
    ld   a, (ix+0)
    cp   (hl)
    jr   nz, blNext
    inc  hl
    inc  ix
    djnz blCmp
    ld   (biosName), de
    ret
blNext:
    ; skip the remaining CRC bytes
    inc  hl
    djnz blNext
    jr   blLoop

    include "bios_table.asm"

; ===========================================================================
;  BiosVerdict  -  A = 0 ok / 1 mute / 2 bad header / 3 unknown CRC (warn)
;                 4 = the Goa'uld's own BIOS was read (slot0_ext ineffective)
; ===========================================================================
BiosVerdict:
    ld   hl, (biosNonFF)
    ld   a, h
    or   l
    ld   a, 1
    ret  z                      ; everything 0xFF
    ld   a, (BIOS_HEAD + 0)
    cp   0xF3
    ld   a, 2
    ret  nz
    ld   a, (BIOS_HEAD + 1)
    cp   0xC3
    ld   a, 2
    ret  nz
    ld   hl, (biosName)
    ld   a, h
    or   l
    ld   a, 3
    ret  z
    ; the Goa'uld's own internal ROM came back: slot0_ext did not work
    ld   de, sBiosGoauld
    or   a
    sbc  hl, de
    ld   a, 4
    ret  z
    xor  a
    ret

; ===========================================================================
;  BiosPrint  -  two rows starting at (row):
;    "BIOS   F3C3 id:00 00 00 CRC EE229390"
;    "       SONY HB-10 (JP)          OK"
; ===========================================================================
BiosPrint:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sBiosHdr
    call PrintAt
    ld   a, (BIOS_HEAD + 0)
    call PrintHexA
    ld   a, (BIOS_HEAD + 1)
    call PrintHexA
    ld   hl, sBiosId
    call PrintStr
    ld   a, (BIOS_HEAD + 0x2B)
    call PrintHexA
    call PrintSpace
    ld   a, (BIOS_HEAD + 0x2C)
    call PrintHexA
    call PrintSpace
    ld   a, (BIOS_HEAD + 0x2D)
    call PrintHexA
    ld   hl, sBiosCrc
    call PrintStr
    ld   hl, biosCRC
    call PrintHex32
    ; second row
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 8
    call SetPos
    call BiosVerdict
    ld   (tmpA), a
    or   a
    jr   z, bpKnown
    cp   1
    jr   z, bpMute
    cp   2
    jr   z, bpHdr
    cp   4
    jr   z, bpGoauld
    ld   hl, sBiosUnk
    call PrintStr
    call PrintNA
    jr   bpDead
bpGoauld:
    ld   hl, sBiosGoauld
    call PrintStr
    call PrintFAIL
    ret
bpKnown:
    ld   hl, (biosName)
    call PrintStr
    call PrintOK
    jr   bpDead
bpMute:
    ld   hl, sBiosMute
    call PrintStr
    call PrintFAIL
    ret
bpHdr:
    ld   hl, sBiosBadHdr
    call PrintStr
    call PrintFAIL
bpDead:
    ; data lines that never toggled while the ROM was read (monitor only)
    ld   a, (monPresent)
    or   a
    ret  z
    ld   a, (biosDead + 0)
    ld   c, a
    ld   a, (biosDead + 1)
    or   c
    ret  z
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 8
    ld   hl, sBiosDead
    call PrintAt
    ld   a, (biosDead + 0)
    call PrintHexA
    call PrintSpace
    ld   a, (biosDead + 1)
    call PrintHexA
    ret

sBiosHdr:    db "BIOS   ", 0
sBiosId:     db " id:", 0
sBiosCrc:    db " CRC ", 0
sBiosUnk:    db "CRC desconocida (ROM?)  ", 0
sBiosMute:   db "MUDA: todo FF (ROM/CS)  ", 0
sBiosBadHdr: db "cabecera no es DI;JP    ", 0
sBiosDead:   db "lineas D sin mover LO/HI: ", 0
