; =============================================================================
;  reloc.asm  -  Goa'uld Doctor  -  code that must run from RAM (page 3)
;
;  Everything between RelocStart/RelocEnd is assembled for RELOC_BASE (0xC800)
;  with DISP and copied there once at boot (RelocInstall).  These routines
;  switch pages 0/1/2 of the Z80 map to other slots, and make the board's
;  physical slot 0 transparent (CONTROL.slot0_ext), so while they run:
;
;    * NO calls into this ROM (page 1 may be gone)
;    * NO BIOS calls while slot0_ext=1 (page 0 is then the BOARD's BIOS)
;    * interrupts disabled
;
;  ENASLT (BIOS, page 0) IS used, but only with slot0_ext=0.
;  (sjasmplus: one instruction per line.)
; =============================================================================

; ===========================================================================
;  RelocInstall  -  copy the block to RELOC_BASE (call once at boot, EI ok)
; ===========================================================================
RelocInstall:
    ld   hl, RelocStart
    ld   de, RELOC_BASE
    ld   bc, RelocEnd - RelocStart
    ldir
    ld   hl, SubslotP2Src
    ld   de, 0x8000
    ld   bc, SubslotP2End - SubslotP2Src
    ldir
    ret

RelocStart:
    DISP RELOC_BASE

; ---------------------------------------------------------------------------
;  rlSetCtrl  -  A = CONTROL value (inline monitor access, no ROM helpers)
; ---------------------------------------------------------------------------
rlSetCtrl:
    push af
    ld   a, MON_CTRL
    out  (MON_IDX), a
    pop  af
    out  (MON_DAT), a
    ret

; ---------------------------------------------------------------------------
;  rlSetCtrl2  -  A = CONTROL2 value (transparency mask bits 3:0, bit4 = p3)
; ---------------------------------------------------------------------------
rlSetCtrl2:
    push af
    ld   a, MON_CTRL2
    out  (MON_IDX), a
    pop  af
    out  (MON_DAT), a
    ret

; ---------------------------------------------------------------------------
;  rlSelect  -  map page (mmPage: 0/1/2) to slot id (mmSlotId, ENASLT format:
;               bit7 expanded, 3:2 subslot, 1:0 primary) and make that
;               primary slot transparent.  Order matters:
;                 1. transparency OFF (page 2 / ROM must be ours)
;                 2. subslot register of the primary (via the ROM stub, which
;                    parks page 3 in that slot for the write) - page 1 is
;                    still our ROM at this point
;                 3. PPI A8: page -> primary
;                 4. CONTROL2 = 1 << primary (+ CONTROL ign_int)
;               Saves A8 in rtSlotSaved and the subslot image in rtSubSaved.
; ---------------------------------------------------------------------------
rlSelect:
    xor  a
    call rlSetCtrl2
    in   a, (0xA8)
    ld   (rtSlotSaved), a
    ld   a, (mmSlotId)
    bit  7, a
    jr   z, rlSelPrimary
    ; ---- expanded: new subslot image for this page ----
    and  0x03
    ld   c, a                   ; C = primary
    ld   b, 0
    ld   hl, subImg
    add  hl, bc
    ld   a, (hl)
    ld   (rtSubSaved), a
    ld   d, a                   ; D = current image
    ld   a, (mmPage)
    add  a, a                   ; page*2 = shift
    ld   b, a
    ld   a, 0x03
    ld   e, a                   ; E = mask 3<<shift
    ld   a, (mmSlotId)
    rrca
    rrca
    and  0x03                   ; A = subslot
rlSelShift:
    ld   c, a
    ld   a, b
    or   a
    jr   z, rlSelShifted
    ld   a, e
    add  a, a
    ld   e, a
    ld   a, c
    add  a, a
    dec  b
    jr   rlSelShift
rlSelShifted:
    ld   a, e
    cpl
    and  d                      ; image with the page bits cleared
    or   c                      ; | subslot<<shift
    ld   c, a                   ; C = new image
    ld   a, (mmSlotId)
    and  0x03
    ld   b, a                   ; B = primary
    call rlSubInstall           ; page 1: fresh page-2 copy (ROM still here)
    call rlSubWrite             ; stub: page 3 -> primary, (FFFF) = C
rlSelPrimary:
    ; ---- A8: page -> primary ----
    ld   a, (mmPage)
    add  a, a
    ld   b, a                   ; shift = page*2
    ld   a, 0x03
    ld   e, a
    ld   a, (mmSlotId)
    and  0x03
rlSelA8Shift:
    ld   c, a
    ld   a, b
    or   a
    jr   z, rlSelA8Shifted
    ld   a, e
    add  a, a
    ld   e, a
    ld   a, c
    add  a, a
    dec  b
    jr   rlSelA8Shift
rlSelA8Shifted:
    ld   a, e
    cpl
    ld   e, a
    ld   a, (rtSlotSaved)
    and  e
    or   c
    ld   (tmpA), a
    ; ---- transparency for that primary, external /INT masked ----
    ld   a, CTL_IGNINT
    call rlSetCtrl
    ld   a, (mmSlotId)
    and  0x03
    ld   b, a
    ld   a, 1
    inc  b
rlSelMask:
    dec  b
    jr   z, rlSelMaskDone
    add  a, a
    jr   rlSelMask
rlSelMaskDone:
    call rlSetCtrl2
    ld   a, (tmpA)
    out  (0xA8), a
    ret

; ---------------------------------------------------------------------------
;  rlDeselect  -  undo rlSelect: transparency off, A8 back, subslot back
; ---------------------------------------------------------------------------
rlDeselect:
    xor  a
    call rlSetCtrl2
    xor  a
    call rlSetCtrl
    ld   a, (rtSlotSaved)
    out  (0xA8), a
    ld   a, (mmSlotId)
    bit  7, a
    ret  z
    and  0x03
    ld   b, a
    ld   a, (rtSubSaved)
    ld   c, a
    call rlSubWrite
    ret

; rlSubWrite - B = primary, C = value: the ROM stub, or its page-2 copy when
;              the change affects page 1 (the ROM itself would vanish).
;              rlSubInstall re-copies the page-2 stub: ONLY valid while this
;              ROM is in page 1, i.e. at select time - never at deselect, when
;              page 1 is still the other slot (a page-2 RAM test may have
;              overwritten the stub, hence the copy on every select).
rlSubWrite:
    ld   a, (mmPage)
    cp   1
    jp   nz, SubslotWrite
    jp   SubslotWriteP2
rlSubInstall:
    ld   a, (mmPage)
    cp   1
    ret  nz
    push bc
    ld   hl, SubslotP2Src
    ld   de, 0x8000
    ld   bc, SubslotP2End - SubslotP2Src
    ldir
    pop  bc
    ret

; ===========================================================================
;  RelocProbe  -  classify page (mmPage 0..2) of slot id (mmSlotId) into
;                 memMap[primary*16 + sub*4 + page] = EMPTY / RAM / ROM
; ===========================================================================
RelocProbe:
    di
    call rlSelect
    ; base = page * 0x4000
    ld   a, (mmPage)
    rrca
    rrca                        ; page -> bits 7:6
    and  0xC0
    ld   h, a
    ld   l, 0x10
    ; --- RAM probe at base+0x0010 and base+0x2345 ---
    call rlCellIsRam
    jr   nz, rlProbeNotRam
    ld   a, (mmPage)
    rrca
    rrca
    and  0xC0
    or   0x23
    ld   h, a
    ld   l, 0x45
    call rlCellIsRam
    jr   nz, rlProbeNotRam
    ld   a, MMAP_RAM
    jr   rlProbeStore
rlProbeNotRam:
    ; --- ROM vs empty: any byte != 0xFF in base+0x0000..0x003F or +0x2000..+0x203F ---
    ld   a, (mmPage)
    rrca
    rrca
    and  0xC0
    ld   h, a
    ld   l, 0
    ld   b, 64
rlProbeFF1:
    ld   a, (hl)
    inc  a
    jr   nz, rlProbeRom
    inc  hl
    djnz rlProbeFF1
    ld   a, (mmPage)
    rrca
    rrca
    and  0xC0
    or   0x20
    ld   h, a
    ld   l, 0
    ld   b, 64
rlProbeFF2:
    ld   a, (hl)
    inc  a
    jr   nz, rlProbeRom
    inc  hl
    djnz rlProbeFF2
    ld   a, MMAP_EMPTY
    jr   rlProbeStore
rlProbeRom:
    ld   a, MMAP_ROM
rlProbeStore:
    ld   (tmpB), a
    call rlDeselect
    call MapCellPtr             ; HL = &memMap[slotId, page]  (ROM helper)
    ld   a, (tmpB)
    ld   (hl), a
    ei
    ret

; rlCellIsRam - HL = cell. Z = RAM (complement written and read back, then
;               restored), NZ = not RAM.  Clobbers AF, D.
rlCellIsRam:
    ld   d, (hl)
    ld   a, d
    cpl
    ld   (hl), a
    cp   (hl)
    jr   nz, rlCirNo
    ld   (hl), d
    ld   a, d
    cp   (hl)
    ret                         ; Z if restore also read back
rlCirNo:
    ld   (hl), d
    or   1                      ; NZ
    ret

; ===========================================================================
;  RelocTestPage  -  full RAM suite on page (mmPage 0..2) of slot (mmSlotId)
;                    Results in rsSlotOK / rsFailAddr / rsFailExp / rsFailGot.
; ===========================================================================
RelocTestPage:
    di
    call rlSelect
    ld   a, (mmPage)
    rrca
    rrca
    and  0xC0
    ld   h, a
    ld   l, 0
    ld   (rtBase), hl
    call RamSuite
    call rlDeselect
    ei
    ret

; ===========================================================================
;  RamSuite  -  generic 16 KB RAM test on (rtBase)..(rtBase)+0x3FFF
;               March C- (6 phases), walking 1/0 on 16 cells, address
;               uniqueness, 0.2 s retention.  Stops at the first failure:
;               rsSlotOK=0, rsFailAddr/Exp/Got/XOR.  Stack in page 3 (ok:
;               the page under test is never page 3 here).
;  Register convention inside the phases:
;     HL = pointer, E = expected/pattern, C = end high byte (base+0x40),
;     B = base high byte - 1 (descending stop)
; ===========================================================================
RamSuite:
    ld   a, 1
    ld   (rsSlotOK), a
    call rsBounds
    ; ---- March C- ----
    ; phase 0: ascending write 0x00
    ld   hl, (rtBase)
rsM0:
    ld   (hl), 0x00
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsM0
    ; phase 1: ascending read 0, write FF
    ld   hl, (rtBase)
    ld   e, 0x00
rsM1:
    ld   a, (hl)
    cp   e
    jp   nz, rsFail
    ld   (hl), 0xFF
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsM1
    ; phase 2: ascending read FF, write 0
    ld   hl, (rtBase)
    ld   e, 0xFF
rsM2:
    ld   a, (hl)
    cp   e
    jp   nz, rsFail
    ld   (hl), 0x00
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsM2
    ; phase 3: descending read 0, write FF
    ld   hl, (rtBase)
    ld   a, h
    add  a, 0x3F
    ld   h, a
    ld   l, 0xFF
    ld   e, 0x00
rsM3:
    ld   a, (hl)
    cp   e
    jp   nz, rsFail
    ld   (hl), 0xFF
    dec  hl
    ld   a, h
    cp   b
    jr   nz, rsM3
    ; phase 4: descending read FF, write 0
    ld   hl, (rtBase)
    ld   a, h
    add  a, 0x3F
    ld   h, a
    ld   l, 0xFF
    ld   e, 0xFF
rsM4:
    ld   a, (hl)
    cp   e
    jp   nz, rsFail
    ld   (hl), 0x00
    dec  hl
    ld   a, h
    cp   b
    jr   nz, rsM4
    ; phase 5: ascending read 0
    ld   hl, (rtBase)
    ld   e, 0x00
rsM5:
    ld   a, (hl)
    cp   e
    jp   nz, rsFail
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsM5
    ; ---- walking 1 / walking 0 on the first 16 cells ----
    ld   d, 8
    ld   e, 0x01
rsWalk:
    ld   hl, (rtBase)
    push bc
    ld   b, 16
rsW1w:
    ld   (hl), e
    inc  hl
    djnz rsW1w
    ld   hl, (rtBase)
    ld   b, 16
rsW1r:
    ld   a, (hl)
    cp   e
    jp   nz, rsWalkFail
    inc  hl
    djnz rsW1r
    ld   a, e
    cpl
    ld   e, a                   ; walking 0
    ld   hl, (rtBase)
    ld   b, 16
rsW0w:
    ld   (hl), e
    inc  hl
    djnz rsW0w
    ld   hl, (rtBase)
    ld   b, 16
rsW0r:
    ld   a, (hl)
    cp   e
    jp   nz, rsWalkFail
    inc  hl
    djnz rsW0r
    pop  bc
    ld   a, e
    cpl
    rlca
    ld   e, a                   ; next bit
    dec  d
    jr   nz, rsWalk
    ; ---- address uniqueness: cell = L xor H ----
    ld   hl, (rtBase)
rsAUw:
    ld   a, h
    xor  l
    ld   (hl), a
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsAUw
    ld   hl, (rtBase)
rsAUr:
    ld   a, h
    xor  l
    ld   e, a
    ld   a, (hl)
    cp   e
    jp   nz, rsFail
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsAUr
    ; ---- retention: fill 0xC3, wait ~0.2 s, verify ----
    ld   hl, (rtBase)
rsRetW:
    ld   (hl), 0xC3
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsRetW
    ld   de, 0xC000
rsRetD:
    dec  de
    ld   a, d
    or   e
    jr   nz, rsRetD
    ld   hl, (rtBase)
    ld   e, 0xC3
rsRetR:
    ld   a, (hl)
    cp   e
    jp   nz, rsFail
    inc  hl
    ld   a, h
    cp   c
    jr   nz, rsRetR
    ret

rsWalkFail:
    pop  bc
rsFail:
    ; HL = address, E = expected, A = got
    ld   (rsFailAddr), hl
    ld   (rsFailGot), a
    xor  e
    ld   (rsFailXOR), a
    ld   a, e
    ld   (rsFailExp), a
    xor  a
    ld   (rsSlotOK), a
    ret

; rsBounds: C = end high byte, B = base high byte - 1
rsBounds:
    ld   a, (rtBase + 1)
    ld   b, a
    dec  b
    add  a, 0x40
    ld   c, a
    ret

; ===========================================================================
;  RelocBiosRead  -  read the BOARD's BIOS 0x0000-0x7FFF through the bus:
;                    CRC32 -> biosCRC, non-FF count -> biosNonFF,
;                    first 128 bytes -> BIOS_HEAD, D_DEAD -> biosDead.
;                    Needs the CRC table at CRC_TABLE (BuildCrcTable).
; ===========================================================================
RelocBiosRead:
    di
    ld   a, (expFlags + 0)      ; slot 0 (subslot 0 if expanded), page 1 ->
    or   a                      ; board BIOS 4000-7FFF
    ld   a, 0x00
    jr   z, rlBrId
    ld   a, 0x80
rlBrId:
    ld   (mmSlotId), a
    ld   a, 1
    ld   (mmPage), a
    call rlSelect               ; slot 0 transparent: 0000-7FFF = board ROM
    xor  a                      ; re-arm monitor accumulators (idx 0 != 0x20)
    out  (MON_IDX), a
    out  (MON_DAT), a
    ; head copy
    ld   hl, 0x0000
    ld   de, BIOS_HEAD
    ld   bc, 128
    ldir
    ; CRC32 over 0000-7FFF: crc = D:E:B:C (D = msb)
    ld   bc, 0xFFFF
    ld   de, 0xFFFF
    ld   iy, 0                  ; non-FF counter
    ld   hl, 0x0000
rlCrcLoop:
    ld   a, (hl)
    cp   0xFF
    jr   z, rlCrcFF
    inc  iy
rlCrcFF:
    xor  c
    ld   ixl, a
    ld   ixh, 0xC4
    ld   a, (ix+0)
    xor  b
    ld   c, a
    ld   ixh, 0xC5
    ld   a, (ix+0)
    xor  e
    ld   b, a
    ld   ixh, 0xC6
    ld   a, (ix+0)
    xor  d
    ld   e, a
    ld   ixh, 0xC7
    ld   d, (ix+0)
    inc  hl
    ld   a, h
    cp   0x80
    jr   nz, rlCrcLoop
    ; final complement, store little-endian
    ld   a, c
    cpl
    ld   (biosCRC + 0), a
    ld   a, b
    cpl
    ld   (biosCRC + 1), a
    ld   a, e
    cpl
    ld   (biosCRC + 2), a
    ld   a, d
    cpl
    ld   (biosCRC + 3), a
    ld   (biosNonFF), iy
    ; data lines that never toggled while the board ROM drove the bus
    ld   a, 0x02
    out  (MON_IDX), a
    in   a, (MON_DAT)
    ld   (biosDead + 0), a
    in   a, (MON_DAT)
    ld   (biosDead + 1), a
    call rlDeselect
    ei
    ret

; ---------------------------------------------------------------------------
;  rlMapperReg  -  mapper register of page (mmPage 0/1): map the page to
;                  (mmSlotId), OUT (FC+page),(mpSeg), verify the first row
;                  of the page and the one at +0x2000 against the pattern
;                  MpTestPage2 wrote, put the register back (3 - page).
;                  rsSlotOK / rsFailAddr / rsFailExp / rsFailGot.
; ---------------------------------------------------------------------------
rlMapperReg:
    di
    call rlSelect
    ld   a, (mmPage)
    add  a, 0xFC
    ld   c, a
    ld   a, (mpSeg)
    out  (c), a
    ; D = 13*seg + 0x3B
    ld   b, a
    add  a, a
    add  a, a
    ld   d, a
    add  a, a
    add  a, d
    add  a, b
    add  a, 0x3B
    ld   d, a
    ld   a, (mmPage)
    rrca
    rrca
    and  0xC0
    ld   h, a
    call rlMpRow
    jr   nz, rlMrFail
    ld   a, (mmPage)
    rrca
    rrca
    and  0xC0
    or   0x20
    ld   h, a
    call rlMpRow
    jr   nz, rlMrFail
    ld   a, 1
    ld   (rsSlotOK), a
    jr   rlMrDone
rlMrFail:
    ld   (rsFailAddr), hl
    ld   (rsFailGot), a
    ld   a, e
    ld   (rsFailExp), a
    xor  a
    ld   (rsSlotOK), a
rlMrDone:
    ld   a, (mmPage)
    ld   b, a
    add  a, 0xFC
    ld   c, a
    ld   a, 3
    sub  b
    out  (c), a
    call rlDeselect
    ei
    ret

; rlMpRow - H = row, D = term: 256 bytes against 5*L + 11*(80|H&3F) + D.
;           Z = ok, else HL / E / A = address / expected / got
rlMpRow:
    ld   a, h
    and  0x3F
    or   0x80
    ld   b, a
    add  a, a
    add  a, a
    add  a, b
    add  a, a
    add  a, b
    add  a, d
    ld   e, a
    ld   l, 0
rlMpRowB:
    ld   a, (hl)
    cp   e
    ret  nz
    ld   a, e
    add  a, 5
    ld   e, a
    inc  l
    jr   nz, rlMpRowB
    ret

    ENT
RelocEnd:

    IF RelocEnd - RelocStart > 0x0800
        ERROR "relocated block exceeds 2 KB"
    ENDIF

; ===========================================================================
;  BuildCrcTable  -  CRC32 (IEEE, reflected, poly 0xEDB88320) lookup table
;                    as 4 byte-planes at CRC_TABLE.  Runs from ROM.
; ===========================================================================
BuildCrcTable:
    ld   l, 0                   ; i
bctOuter:
    ld   c, l                   ; crc = i (D:E:B:C)
    ld   b, 0
    ld   de, 0
    ld   h, 8
bctBit:
    srl  d
    rr   e
    rr   b
    rr   c
    jr   nc, bctNoX
    ld   a, c
    xor  0x20
    ld   c, a
    ld   a, b
    xor  0x83
    ld   b, a
    ld   a, e
    xor  0xB8
    ld   e, a
    ld   a, d
    xor  0xED
    ld   d, a
bctNoX:
    dec  h
    jr   nz, bctBit
    ld   h, 0xC4
    ld   (hl), c
    inc  h
    ld   (hl), b
    inc  h
    ld   (hl), e
    inc  h
    ld   (hl), d
    inc  l
    jr   nz, bctOuter
    ret
