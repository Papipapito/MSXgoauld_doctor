; =============================================================================
;  test_ram.asm  -  Goa'uld Doctor  -  board memory map (any slot/subslot)
;                   and the stackless page-3 tests
;
;  Slot ids are in ENASLT format: bit7 = expanded (use the subslot), bits 3:2
;  subslot, bits 1:0 primary.  The board's expansion registers follow the
;  Goa'uld's writes to 0xFFFF (every memory write goes out on the bus), so
;  "select subslot" = park page 3 in that primary slot and write 0xFFFF.
;  That write is done by SubslotWrite, a stub that lives HERE (ROM, page 1,
;  always visible) because page 3 - RAM, stack, variables - is away meanwhile.
;
;  Page 3 of the BOARD is where our stack lives (Goa'uld: internal mapper 3-0;
;  emulator: the machine's RAM), so page-3 tests are STACKLESS: P3_SWITCH_ON /
;  P3_SWITCH_OFF bracket code that uses only registers + LDIR.
;     IX  = base (IXH), IXL = saved subslot image (expanded ids)
;     IYL = saved PPI A8, IYH = phase
;     B'/C' (alternate set) = slot id / CONTROL2 value (kept across)
;  0xFFFF is never touched as data (it is the expansion register), so page 3
;  is tested 0xC000-0xFFFE.
;  (sjasmplus: one instruction per line.)
; =============================================================================

MMAP_EMPTY  equ 0
MMAP_RAM    equ 1
MMAP_ROM    equ 2
MMAP_DOC    equ 3       ; the Doctor's own ROM window (0-3 page 1)
MMAP_OWN    equ 4       ; page 3 that holds our stack (emulator only)
MMAP_NA     equ 5

; ===========================================================================
;  ROM stubs for the expansion register of a primary slot (DI assumed).
;  They park page 3 in the target primary, touch 0xFFFF and restore A8 -
;  no stack, no RAM inside the parked window.
; ===========================================================================

; SubslotWrite - B = primary, C = new register value.  Updates subImg[B].
SubslotWrite:
    ld   hl, subImg
    ld   d, 0
    ld   e, b
    add  hl, de
    ld   (hl), c
    in   a, (0xA8)
    ld   e, a                   ; E = A8 to restore
    and  0x3F
    ld   d, a
    ld   a, b
    rrca
    rrca                        ; primary << 6
    or   d
    out  (0xA8), a              ; page 3 -> primary   (no stack from here)
    ld   a, c
    ld   (0xFFFF), a
    ld   a, e
    out  (0xA8), a              ; page 3 back
    ret

; SubslotWriteP2 - same, but running from RAM in PAGE 2 (0x8000): needed
; when the subslot of PAGE 1 is changed, because this ROM lives in page 1.
; Installed by RelocInstall; page 2 is the Goa'uld's own mapper RAM.
SubslotP2Src:
    DISP 0x8000
SubslotWriteP2:
    ld   hl, subImg
    ld   d, 0
    ld   e, b
    add  hl, de
    ld   (hl), c
    in   a, (0xA8)
    ld   e, a
    and  0x3F
    ld   d, a
    ld   a, b
    rrca
    rrca
    or   d
    out  (0xA8), a
    ld   a, c
    ld   (0xFFFF), a
    ld   a, e
    out  (0xA8), a
    ret
    ENT
SubslotP2End:

; SubslotRead - B = primary -> A = register image (complement of 0xFFFF)
SubslotRead:
    in   a, (0xA8)
    ld   e, a
    and  0x3F
    ld   d, a
    ld   a, b
    rrca
    rrca
    or   d
    out  (0xA8), a
    ld   a, (0xFFFF)
    cpl
    ld   c, a
    ld   a, e
    out  (0xA8), a
    ld   a, c
    ret

; SubslotProbe - B = primary -> A = 1 if that slot has an expansion register
;                (0xFFFF reads back complemented), else 0.  Flips only the
;                page-3 bits during the probe and restores the original.
SubslotProbe:
    in   a, (0xA8)
    ld   e, a
    and  0x3F
    ld   d, a
    ld   a, b
    rrca
    rrca
    or   d
    out  (0xA8), a
    ld   a, (0xFFFF)
    ld   c, a                   ; C = raw
    cpl
    xor  0xC0
    ld   d, a                   ; D = test image
    ld   (0xFFFF), a
    ld   a, (0xFFFF)
    cpl
    cp   d
    jr   nz, spNotExp
    ld   a, c
    cpl
    ld   (0xFFFF), a            ; expanded: restore the image
    ld   a, e
    out  (0xA8), a
    ld   a, 1
    ret
spNotExp:
    ld   a, c
    ld   (0xFFFF), a            ; plain memory: put the byte back
    ld   a, e
    out  (0xA8), a
    xor  a
    ret

; ===========================================================================
;  MapCellPtr  -  HL = &memMap[(mmSlotId & 3)*16 + sub*4 + mmPage]
;                 (sub = 0 for non-expanded ids)
; ===========================================================================
MapCellPtr:
    ld   a, (mmSlotId)
    ld   c, a
    and  0x03
    rlca
    rlca
    rlca
    rlca
    ld   b, a                   ; primary*16
    ld   a, c
    bit  7, a
    jr   z, mcpNoSub
    and  0x0C                   ; subslot*4
    or   b
    ld   b, a
mcpNoSub:
    ld   a, (mmPage)
    or   b
    ld   c, a
    ld   b, 0
    ld   hl, memMap
    add  hl, bc
    ret

; ===========================================================================
;  Stackless bracket macros (page 3 of the board), see header.
;  P3Prepare computes, with the stack still valid:
;    D = new A8, E = new 0xFFFF image, B'/C' = id / CONTROL2, IX, IYL
; ===========================================================================
    MACRO P3_SWITCH_ON
    ld   a, MON_CTRL2
    out  (MON_IDX), a
    exx
    ld   a, c
    exx
    out  (MON_DAT), a           ; transparency (+p3_release): page 3 may vanish
    ld   a, d
    out  (0xA8), a              ; page -> primary
    exx
    ld   a, b
    exx
    bit  7, a
    jr   z, $+12                ; not expanded: skip the 10 bytes below
    ld   a, (0xFFFF)
    cpl
    ld   ixl, a                 ; saved image
    ld   a, e
    ld   (0xFFFF), a            ; new image
    ENDM

    MACRO P3_SWITCH_OFF
    exx
    ld   a, b
    exx
    bit  7, a
    jr   z, $+7                 ; not expanded: skip the 5 bytes below
    ld   a, ixl
    ld   (0xFFFF), a
    ld   a, iyl
    out  (0xA8), a
    ld   a, MON_CTRL2
    out  (MON_IDX), a
    xor  a
    out  (MON_DAT), a
    ENDM

; --- P3_ASC / P3_DESC: HL = base / base+count-1, BC = count (from IX) ---
    MACRO P3_ASC
    ld   a, ixh
    ld   h, a
    ld   l, 0
    ld   bc, 0x4000
    ld   a, ixh
    cp   0xC0
    jr   nz, $+3                ; skip the 1-byte dec bc
    dec  bc
    ENDM

    MACRO P3_DESC
    P3_ASC
    add  hl, bc
    dec  hl
    ENDM

; ===========================================================================
;  P3Prepare  -  from (p3SlotId), (p3Page) = 2 or 3
; ===========================================================================
P3Prepare:
    ld   a, (p3Page)
    rrca
    rrca
    and  0xC0
    ld   ixh, a
    ld   ixl, 0
    in   a, (0xA8)
    ld   iyl, a
    ld   c, a
    ; --- D = new A8 ---
    ld   a, (p3Page)
    cp   3
    ld   a, c
    jr   nz, p3pPage2
    and  0x3F
    ld   b, a
    ld   a, (p3SlotId)
    rrca
    rrca
    and  0xC0
    or   b
    ld   d, a
    jr   p3pSub
p3pPage2:
    and  0xCF
    ld   b, a
    ld   a, (p3SlotId)
    rlca
    rlca
    rlca
    rlca
    and  0x30
    or   b
    ld   d, a
p3pSub:
    ; --- E = new register image: subImg[primary] with the page bits replaced ---
    ld   a, (p3SlotId)
    and  0x03
    ld   c, a
    ld   b, 0
    ld   hl, subImg
    add  hl, bc
    ld   a, (hl)
    ld   e, a
    ld   a, (p3SlotId)
    rrca
    rrca
    and  0x03                   ; subslot
    ld   c, a
    ld   a, (p3Page)
    cp   3
    jr   nz, p3pSubP2
    ld   a, e
    and  0x3F
    ld   e, a
    ld   a, c
    rrca
    rrca
    or   e
    ld   e, a
    jr   p3pAlt
p3pSubP2:
    ld   a, e
    and  0xCF
    ld   e, a
    ld   a, c
    rlca
    rlca
    rlca
    rlca
    or   e
    ld   e, a
p3pAlt:
    ; --- B' = id, C' = CONTROL2 = (1 << primary) | p3_release if 3-0 page 3 ---
    ld   a, (p3SlotId)
    ld   b, a
    and  0x03
    inc  a
    ld   c, a
    ld   a, 1
p3pMask:
    dec  c
    jr   z, p3pMaskDone
    add  a, a
    jr   p3pMask
p3pMaskDone:
    ld   c, a
    ld   a, (p3Page)
    cp   3
    jr   nz, p3pStore
    ld   a, b
    and  0x8F
    cp   0x83                   ; expanded, primary 3, subslot 0
    jr   nz, p3pStore
    ld   a, c
    or   0x10
    ld   c, a
p3pStore:
    push bc
    exx
    pop  bc
    exx
    ret

; ===========================================================================
;  RamTestStackless  -  A = slot id, (p3Page) = 2 or 3
;    p3Found=0 -> no RAM there.  Else p3Phase (0 = pass, n = failed phase),
;    p3FailAddr / p3FailExp / p3FailGot, p3Count = bytes tested.
; ===========================================================================
RamTestStackless:
    ld   (p3SlotId), a
    di
    ld   a, CTL_IGNINT
    call MonSetCtrl
    xor  a
    ld   (p3Found), a
    call P3Prepare
    ld   iyh, 0
    P3_SWITCH_ON
    ; ================= no stack / no page-3 variables from here =================
    ; ---- presence probe: base+0x0010 and base+0x2345 ----
    ld   a, ixh
    ld   h, a
    ld   l, 0x10
    ld   d, (hl)
    ld   a, d
    cpl
    ld   (hl), a
    cp   (hl)
    jp   nz, rtsNoRam
    ld   (hl), d
    ld   a, ixh
    or   0x23
    ld   h, a
    ld   l, 0x45
    ld   d, (hl)
    ld   a, d
    cpl
    ld   (hl), a
    cp   (hl)
    jp   nz, rtsNoRam
    ld   (hl), d
    ; ---- March C- ----
    ld   iyh, 1
    P3_ASC
rtsM0:
    ld   (hl), 0x00
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsM0
    ld   iyh, 2
    P3_ASC
    ld   e, 0x00
rtsM1:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    ld   (hl), 0xFF
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsM1
    ld   iyh, 3
    P3_ASC
    ld   e, 0xFF
rtsM2:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    ld   (hl), 0x00
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsM2
    ld   iyh, 4
    P3_DESC
    ld   e, 0x00
rtsM3:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    ld   (hl), 0xFF
    dec  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsM3
    ld   iyh, 5
    P3_DESC
    ld   e, 0xFF
rtsM4:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    ld   (hl), 0x00
    dec  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsM4
    ld   iyh, 6
    P3_ASC
    ld   e, 0x00
rtsM5:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsM5
    ; ---- walking 1/0 on the first 16 cells ----
    ld   iyh, 7
    ld   d, 8
    ld   e, 0x01
rtsWalk:
    ld   a, ixh
    ld   h, a
    ld   l, 0
    ld   b, 16
rtsW1w:
    ld   (hl), e
    inc  hl
    djnz rtsW1w
    ld   a, ixh
    ld   h, a
    ld   l, 0
    ld   b, 16
rtsW1r:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    inc  hl
    djnz rtsW1r
    ld   a, e
    cpl
    ld   e, a
    ld   a, ixh
    ld   h, a
    ld   l, 0
    ld   b, 16
rtsW0w:
    ld   (hl), e
    inc  hl
    djnz rtsW0w
    ld   a, ixh
    ld   h, a
    ld   l, 0
    ld   b, 16
rtsW0r:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    inc  hl
    djnz rtsW0r
    ld   a, e
    cpl
    rlca
    ld   e, a
    dec  d
    jr   nz, rtsWalk
    ; ---- address uniqueness: cell = H xor L ----
    ld   iyh, 8
    P3_ASC
rtsAUw:
    ld   a, h
    xor  l
    ld   (hl), a
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsAUw
    P3_ASC
rtsAUr:
    ld   a, h
    xor  l
    ld   e, a
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsAUr
    ; ---- retention: 0xC3, ~0.35 s, verify ----
    ld   iyh, 9
    P3_ASC
rtsRetW:
    ld   (hl), 0xC3
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsRetW
    ld   de, 0xC000
rtsRetD:
    dec  de
    ld   a, d
    or   e
    jr   nz, rtsRetD
    P3_ASC
    ld   e, 0xC3
rtsRetR:
    ld   a, (hl)
    cp   e
    jp   nz, rtsFail
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, rtsRetR
    ; ---- pass ----
    ld   iyh, 0
    P3_SWITCH_OFF
    ; ================= page restored: stack and variables back =================
    ld   a, 1
    ld   (p3Found), a
    xor  a
    ld   (p3Phase), a
    jr   rtsDone

rtsFail:
    ; HL = address, E = expected, A = got, IYH = phase
    ld   d, a
    P3_SWITCH_OFF
    ld   (p3FailAddr), hl
    ld   a, e
    ld   (p3FailExp), a
    ld   a, d
    ld   (p3FailGot), a
    ld   a, iyh
    ld   (p3Phase), a
    ld   a, 1
    ld   (p3Found), a
    jr   rtsDone

rtsNoRam:
    P3_SWITCH_OFF
    xor  a
    ld   (p3Found), a

rtsDone:
    ld   hl, 0x4000
    ld   a, (p3Page)
    cp   3
    jr   nz, rtsCnt
    dec  hl
rtsCnt:
    ld   (p3Count), hl
    xor  a
    call MonSetCtrl
    ei
    ret

; ===========================================================================
;  ProbeP3  -  A = slot id: classify page 3 into memMap (EMPTY/RAM/ROM)
; ===========================================================================
ProbeP3:
    ld   (p3SlotId), a
    ld   (mmSlotId), a
    ld   a, 3
    ld   (p3Page), a
    ld   (mmPage), a
    di
    ld   a, CTL_IGNINT
    call MonSetCtrl
    call P3Prepare
    P3_SWITCH_ON
    ld   e, MMAP_RAM
    ld   hl, 0xC010
    ld   d, (hl)
    ld   a, d
    cpl
    ld   (hl), a
    cp   (hl)
    jr   nz, pp3NotRam
    ld   (hl), d
    ld   hl, 0xE345
    ld   d, (hl)
    ld   a, d
    cpl
    ld   (hl), a
    cp   (hl)
    jr   nz, pp3NotRam
    ld   (hl), d
    jr   pp3Restore
pp3NotRam:
    ld   e, MMAP_ROM
    ld   hl, 0xC000
    ld   b, 64
pp3FF1:
    ld   a, (hl)
    inc  a
    jr   nz, pp3Restore
    inc  hl
    djnz pp3FF1
    ld   hl, 0xE000
    ld   b, 64
pp3FF2:
    ld   a, (hl)
    inc  a
    jr   nz, pp3Restore
    inc  hl
    djnz pp3FF2
    ld   e, MMAP_EMPTY
pp3Restore:
    ld   d, e                   ; keep the verdict in D (P3_SWITCH_OFF uses A)
    P3_SWITCH_OFF
    ; ---- stack back ----
    call MapCellPtr
    ld   (hl), d
    xor  a
    call MonSetCtrl
    ei
    ret

; ===========================================================================
;  OwnPage3  -  A = slot id: Z if that id is where page 3 currently lives
;               (our stack/variables in a real MSX).  On the Goa'uld page 3
;               is its internal mapper (3-0) and the board's 3-0 page 3 IS
;               testable (p3_release), so the caller ignores this when the
;               monitor is present.
; ===========================================================================
OwnPage3:
    ld   c, a
    in   a, (0xA8)
    rlca
    rlca
    and  0x03
    ld   b, a                   ; current primary of page 3
    ld   a, c
    and  0x03
    cp   b
    ret  nz
    ld   a, c
    bit  7, a
    ret  z                      ; not expanded: same primary = own
    ld   hl, subImg
    ld   d, 0
    ld   e, b
    add  hl, de
    ld   a, (hl)
    rlca
    rlca
    and  0x03                   ; current subslot of page 3
    ld   b, a
    ld   a, c
    rrca
    rrca
    and  0x03
    cp   b
    ret

; ===========================================================================
;  DoMemMap  -  expFlags/subImg for the 4 primaries, then every cell:
;               primary 0-3 x subslot (0-3 if expanded) x page 0-3
; ===========================================================================
DoMemMap:
    ld   hl, memMap
    ld   b, 64
    ld   a, MMAP_NA
dmmFill:
    ld   (hl), a
    inc  hl
    djnz dmmFill
    call SlotsInit
    ; --- cells ---
    xor  a
    ld   (mmPri), a
dmmSlot:
    xor  a
    ld   (mmSub), a
dmmSub:
    call MakeSlotId             ; A = id from mmPri/mmSub/expFlags
    ld   (mmSlotId), a
    xor  a
    ld   (mmPage), a
dmmPage:
    ; the Doctor's own window: 0-3 page 1 on the Goa'uld
    ld   a, (monPresent)
    or   a
    jr   z, dmmProbe
    ld   a, (mmSlotId)
    cp   0x8C
    jr   nz, dmmProbe
    ld   a, (mmPage)
    cp   1
    jr   nz, dmmProbe
    call MapCellPtr
    ld   (hl), MMAP_DOC
    jr   dmmNextPage
dmmProbe:
    call RelocProbe
dmmNextPage:
    ld   a, (mmPage)
    inc  a
    ld   (mmPage), a
    cp   3
    jr   c, dmmPage
    ; page 3
    ld   a, (mmSlotId)
    ld   c, a
    ld   a, (monPresent)
    or   a
    jr   nz, dmmP3Probe
    ld   a, c
    call OwnPage3
    jr   nz, dmmP3Probe
    ld   a, 3
    ld   (mmPage), a
    call MapCellPtr
    ld   (hl), MMAP_OWN
    jr   dmmNextSub
dmmP3Probe:
    ld   a, (mmSlotId)
    call ProbeP3
dmmNextSub:
    ld   a, (mmPri)
    ld   hl, expFlags
    ld   c, a
    ld   b, 0
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, dmmNextSlot         ; not expanded: only subslot 0
    ld   a, (mmSub)
    inc  a
    ld   (mmSub), a
    cp   4
    jr   c, dmmSub
dmmNextSlot:
    ld   a, (mmPri)
    inc  a
    ld   (mmPri), a
    cp   4
    jr   c, dmmSlot
    ; subSame[p]: an expanded primary whose subslot rows are all identical
    ; is the board's plain slot behind the Goa'uld's own expansion register
    xor  a
    ld   (mmPri), a
dmmSame:
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, dmmSameStore        ; not expanded: 0
    call SubRowsAllSame         ; clobbers mmSub/mmPage/mmSlotId, keeps mmPri
    ld   a, 0
    jr   nz, dmmSameStore
    inc  a
dmmSameStore:
    ld   hl, subSame
    ld   c, a
    ld   a, (mmPri)
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   (hl), c
    inc  a
    ld   (mmPri), a
    cp   4
    jr   c, dmmSame
    ret

; SubSameSkip - Z if (mmPri) is expanded but its subslot rows are identical
;               (only subslot 0 is worth testing)
SubSameSkip:
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, subSame
    add  hl, bc
    ld   a, (hl)
    dec  a                      ; Z when subSame = 1
    ret

; DisplaySlotId - A = id -> plain "Sn" id when its primary is subSame
DisplaySlotId:
    bit  7, a
    ret  z
    ld   c, a
    and  0x03
    ld   e, a
    ld   d, 0
    ld   hl, subSame
    add  hl, de
    ld   a, (hl)
    or   a
    ld   a, c
    ret  z
    and  0x03
    ret

; ===========================================================================
;  SlotsInit  -  expFlags[p] / subImg[p] for the 4 primary slots.  MUST run
;                before anything selects a subslot (RomInit calls it; the
;                map calls it again in case a BIOS ENASLT changed things).
; ===========================================================================
SlotsInit:
    di
    ld   b, 0
siLoop:
    push bc
    call SubslotProbe
    pop  bc
    ld   hl, expFlags
    ld   d, 0
    ld   e, b
    add  hl, de
    ld   (hl), a
    or   a
    jr   z, siNext
    push bc
    call SubslotRead
    pop  bc
    ld   hl, subImg
    ld   d, 0
    ld   e, b
    add  hl, de
    ld   (hl), a
siNext:
    inc  b
    ld   a, b
    cp   4
    jr   c, siLoop
    ei
    ret

; MakeSlotId - A = id for (mmPri, mmSub): expanded -> 0x80 | sub<<2 | pri
MakeSlotId:
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    ld   a, c
    ret  z
    ld   a, (mmSub)
    rlca
    rlca
    or   c
    or   0x80
    ret

; ===========================================================================
;  PrintMemMap  -  header + one row per primary slot, or per non-empty
;                  subslot of an expanded one ("S3-2").
; ===========================================================================
PrintMemMap:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sMapHdr
    call PrintAt
    xor  a
    ld   (mmPri), a
pmmSlot:
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   nz, pmmExpanded
    xor  a
    ld   (mmSub), a
    ld   (tmpA), a
    call PrintMapRow
    jr   pmmNextSlot
pmmExpanded:
    ; all subslot rows identical to subslot 0 (a 'doc' cell matches anything)
    ; -> the board does not really expand this slot: print one plain row
    call SubRowsAllSame
    jr   nz, pmmPerSub
    xor  a
    ld   (mmSub), a
    ld   a, 1
    ld   (tmpA), a              ; 1 = print the row without "-n"
    call PrintMapRow
    jr   pmmNextSlot
pmmPerSub:
    xor  a
    ld   (tmpA), a
    ld   (mmSub), a
    ld   (tmpB), a              ; rows printed for this slot
pmmSubLoop:
    call SubRowEmpty
    jr   z, pmmSubNext
    call PrintMapRow
    ld   a, (tmpB)
    inc  a
    ld   (tmpB), a
pmmSubNext:
    ld   a, (mmSub)
    inc  a
    ld   (mmSub), a
    cp   4
    jr   c, pmmSubLoop
    ld   a, (tmpB)
    or   a
    jr   nz, pmmNextSlot
    xor  a
    ld   (mmSub), a
    ld   a, 1
    ld   (tmpA), a
    call PrintMapRow            ; all empty: one plain row
pmmNextSlot:
    ld   a, (mmPri)
    inc  a
    ld   (mmPri), a
    cp   4
    jr   c, pmmSlot
    ret

; SubRowsAllSame - Z if subslot rows 1..3 of (mmPri) equal row 0 cell by
;                  cell, where a DOC cell on either side counts as equal
SubRowsAllSame:
    ld   a, 1
    ld   (mmSub), a
srsSub:
    xor  a
    ld   (mmPage), a
srsPage:
    ; HL = &cell(sub 0, page), DE = &cell(sub n, page)
    ld   a, (mmSub)
    push af
    xor  a
    ld   (mmSub), a
    call MakeSlotId
    ld   (mmSlotId), a
    call MapCellPtr
    push hl
    pop  de
    pop  af
    ld   (mmSub), a
    call MakeSlotId
    ld   (mmSlotId), a
    call MapCellPtr
    ld   a, (de)
    ld   b, a
    ld   a, (hl)
    cp   b
    jr   z, srsSame
    cp   MMAP_DOC
    jr   z, srsSame
    ld   a, b
    cp   MMAP_DOC
    jr   z, srsSame
    or   1                      ; NZ: rows differ
    ret
srsSame:
    ld   a, (mmPage)
    inc  a
    ld   (mmPage), a
    cp   4
    jr   c, srsPage
    ld   a, (mmSub)
    inc  a
    ld   (mmSub), a
    cp   4
    jr   c, srsSub
    xor  a                      ; Z: all the same
    ret

; SubRowEmpty - Z if the 4 cells of (mmPri, mmSub) are all EMPTY
SubRowEmpty:
    call MakeSlotId
    ld   (mmSlotId), a
    xor  a
    ld   (mmPage), a
    call MapCellPtr
    ld   a, (hl)
    inc  hl
    or   (hl)
    inc  hl
    or   (hl)
    inc  hl
    or   (hl)
    ret

; PrintMapRow - row for (mmPri, mmSub) at (row)+1
PrintMapRow:
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 1
    call SetPos
    ld   hl, sMapSlot
    call PrintStr
    ld   a, (mmPri)
    add  a, '0'
    call CHPUT
    ld   a, (tmpA)
    or   a
    jr   nz, pmrNoSub           ; collapsed / plain row: "S0   "
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, pmrNoSub
    ld   a, '-'
    call CHPUT
    ld   a, (mmSub)
    add  a, '0'
    call CHPUT
    ld   a, ' '
    call CHPUT
    jr   pmrCells
pmrNoSub:
    ld   hl, sMapSep
    call PrintStr
pmrCells:
    call MakeSlotId
    ld   (mmSlotId), a
    xor  a
    ld   (mmPage), a
pmrPage:
    call MapCellPtr
    ld   a, (hl)
    call PrintMapCell
    ld   a, (mmPage)
    inc  a
    ld   (mmPage), a
    cp   4
    jr   c, pmrPage
    ret

; PrintMapCell - A = MMAP_* -> 5-char cell
PrintMapCell:
    add  a, a
    ld   c, a
    ld   b, 0
    ld   hl, mapNames
    add  hl, bc
    ld   a, (hl)
    inc  hl
    ld   h, (hl)
    ld   l, a
    call PrintStr
    ret
mapNames:  dw sMapEmpty, sMapRam, sMapRom, sMapDoc, sMapOwn, sMapNA
sMapHdr:   db "MAPA    pag0 pag1 pag2 pag3", 0
sMapSlot:  db " S", 0
sMapSep:   db "   ", 0
sMapEmpty: db "---  ", 0
sMapRam:   db "RAM  ", 0
sMapRom:   db "ROM  ", 0
sMapDoc:   db "doc  ", 0
sMapOwn:   db "own  ", 0
sMapNA:    db "n/a  ", 0

; ===========================================================================
;  RawP3Screen  -  key X: page 3 of the first slot whose page 3 answers
;    (RAM/ROM in the map, else slot 0) in the raw: read 16 bytes twice,
;    write 00 11 22 .. FF, read again, for C000 and E000.  Buffers live in
;    PAGE 2 (Goa'uld mapper RAM at 0x8000, untouched by the page-3 switch).
; ===========================================================================
RAW_BUF  equ 0x8100      ; (0x8000-0x80FF = SubslotWriteP2 stub)

    MACRO RAW_BLOCK base, buf
    ld   hl, base
    ld   de, buf
    ld   bc, 16
    ldir
    ld   hl, base
    ld   de, buf + 16
    ld   bc, 16
    ldir
    ld   hl, base
    ld   b, 16
    xor  a
    ld   (hl), a
    inc  hl
    add  a, 0x11
    djnz $ - 4
    ld   hl, base
    ld   de, buf + 32
    ld   bc, 16
    ldir
    ENDM

RawP3Screen:
    call INITXT
    ld   b, 1
    ld   c, 1
    ld   hl, sRawTitle
    call PrintAt
    call RawPickSlot            ; A = slot id
    ld   (p3SlotId), a
    call PrintSlotId
    ld   a, 3
    ld   (p3Page), a
    di
    ld   a, CTL_IGNINT
    call MonSetCtrl
    call P3Prepare
    P3_SWITCH_ON
    RAW_BLOCK 0xC000, RAW_BUF
    RAW_BLOCK 0xE000, RAW_BUF + 48
    P3_SWITCH_OFF
    xor  a
    call MonSetCtrl
    ei
    ld   hl, RAW_BUF
    ld   (tmpHL), hl
    ld   a, 3
    ld   (row), a
    ld   hl, sRawC000
    call RawPrintBlock
    ld   hl, sRawE000
    call RawPrintBlock
    ld   b, 22
    ld   c, 1
    ld   hl, sRawNote
    call PrintAt
    ld   b, 24
    ld   c, 1
    ld   hl, sRSPressKey
    call PrintAt
    call WaitKeyEdge
    ret

; RawPickSlot - A = first slot id with RAM/ROM in page 3 (map order), else 0
RawPickSlot:
    xor  a
    ld   (mmPri), a
rpsSlot:
    xor  a
    ld   (mmSub), a
rpsSub:
    call MakeSlotId
    ld   (mmSlotId), a
    ld   a, 3
    ld   (mmPage), a
    call MapCellPtr
    ld   a, (hl)
    cp   MMAP_RAM
    jr   z, rpsFound
    cp   MMAP_ROM
    jr   z, rpsFound
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, rpsNextSlot
    ld   a, (mmSub)
    inc  a
    ld   (mmSub), a
    cp   4
    jr   c, rpsSub
rpsNextSlot:
    ld   a, (mmPri)
    inc  a
    ld   (mmPri), a
    cp   4
    jr   c, rpsSlot
    xor  a
    ret
rpsFound:
    ld   a, (mmSlotId)
    ret

; PrintSlotId - A = slot id -> "S3-2" / "S0"
PrintSlotId:
    ld   c, a
    ld   a, 'S'
    call CHPUT
    ld   a, c
    and  0x03
    add  a, '0'
    call CHPUT
    bit  7, c
    ret  z
    ld   a, '-'
    call CHPUT
    ld   a, c
    rrca
    rrca
    and  0x03
    add  a, '0'
    call CHPUT
    ret

; RawPrintBlock - HL = title; prints "leido 1/leido 2/escrito+leido" rows
RawPrintBlock:
    push hl
    ld   a, (row)
    ld   b, a
    ld   c, 1
    call SetPos
    pop  hl
    call PrintStr
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   hl, sRawR1
    call RawPrint16
    ld   hl, sRawR2
    call RawPrint16
    ld   hl, sRawR3
    call RawPrint16
    ret

; RawPrint16 - HL = label; 16 bytes from (tmpHL) over two rows
RawPrint16:
    push hl
    ld   a, (row)
    ld   b, a
    ld   c, 1
    call SetPos
    pop  hl
    call PrintStr
    call RawPrint8
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 9
    call SetPos
    call RawPrint8
    ld   a, (row)
    inc  a
    ld   (row), a
    ret
RawPrint8:
    ld   hl, (tmpHL)
    ld   b, 8
rp8Loop:
    ld   a, (hl)
    inc  hl
    push bc
    push hl
    call PrintHexA
    call PrintSpace
    pop  hl
    pop  bc
    djnz rp8Loop
    ld   (tmpHL), hl
    ret

sRawTitle: db "RAM PAG3 EN CRUDO (C000 / E000) ", 0
sRawC000:  db "C000:", 0
sRawE000:  db "E000:", 0
sRawR1:    db "leo 1   ", 0
sRawR2:    db "leo 2   ", 0
sRawR3:    db "00..FF  ", 0
sRawNote:  db "leo1!=leo2: bus flota. 00..FF: escritura", 0
