; =============================================================================
;  test_map_rtc.asm  -  Goa'uld Doctor  -  memory mapper (I/O FC-FF) and
;                       RTC (RP5C01, I/O B4-B5) of the board
;
;  MAPPER: every slot whose page 2 holds RAM is a candidate.  With page 2
;  mapped to it (rlSelect, transparent):
;    1. markers: OUT (FE),s ; (8000)=s  for s = 255..0 (lowest alias wins)
;    2. count  : first s whose (8000) != s  (0 = 256).  1 = plain RAM.
;    3. fill segments 1..n-1 (n = min(count, 64)) with a pattern that depends
;       on segment and address, then verify them all: aliasing between
;       segments, stuck bits and address faults in the upper segments.
;    4. registers of the other pages: page 0 (FC) and 1 (FD) from RAM code
;       (rlMapperReg, reloc.asm), page 3 (FF) stackless (here).  Each one
;       selects another segment and reads it back through its own page.
;  Segment 0 is never filled: it is the page 3 the RAM test already covered
;  and, in an emulator, where THIS code's stack lives.  Ports FC-FF go back
;  to 3,2,1,0 (the Goa'uld's own mapper follows them as well).
;  Pattern: byte = 5*L + 11*(0x80 | (H & 0x3F)) + 13*seg + 0x3B
;
;  RTC: reads through the bus (CONTROL.rtc_ext): RAM banks 2 and 3 (26
;  nibbles, saved and restored) take 0x5/0xA, then the seconds must change
;  within 1.2 s with the timer enabled.  Mode register restored.
;  (sjasmplus: one instruction per line.)
; =============================================================================

MP_OK      equ 0
MP_PLAIN   equ 1        ; count = 1: RAM without mapper
MP_NORESP  equ 2        ; segment 0 does not even read back
MP_SEGFAIL equ 3
MP_REGFAIL equ 4

RTC_ADR    equ 0xB4
RTC_DAT    equ 0xB5

; ===========================================================================
;  MapperTest  -  every slot with RAM in page 2 -> mpRes (max 2 entries):
;                 [0]=slot id [1]=count (0 = 256) [2]=status [3]=segment
;                 [4..5]=addr [6]=exp [7]=got
; ===========================================================================
MapperTest:
    xor  a
    ld   (mpResN), a
    ld   (mmPri), a
mptSlot:
    xor  a
    ld   (mmSub), a
mptSub:
    ld   a, (mpResN)
    cp   2
    ret  nc
    call MakeSlotId
    ld   (mmSlotId), a
    ld   a, 2
    ld   (mmPage), a
    call MapCellPtr
    ld   a, (hl)
    cp   MMAP_RAM
    call z, MapperTestOne
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, mptNextSlot
    call SubSameSkip
    jr   z, mptNextSlot
    ld   a, (mmSub)
    inc  a
    ld   (mmSub), a
    cp   4
    jr   c, mptSub
mptNextSlot:
    ld   a, (mmPri)
    inc  a
    ld   (mmPri), a
    cp   4
    jr   c, mptSlot
    ret

; MapperTestOne - (mmSlotId): page 2 test, then the registers of the pages
;                 that hold RAM in that slot.  Appends to mpRes.
MapperTestOne:
    ld   a, (mpResN)
    add  a, a
    add  a, a
    add  a, a
    ld   c, a
    ld   b, 0
    ld   ix, mpRes
    add  ix, bc
    ld   a, (mmSlotId)
    call DisplaySlotId
    ld   (ix+0), a
    ld   (ix+2), MP_OK
    call MpTestPage2
    ld   a, (ix+2)
    or   a
    jr   nz, mtoDone
    ; ---- page 0 (FC) with segment 1, page 1 (FD) with segment n/2 ----
    xor  a
    ld   (mmPage), a
    ld   a, 1
    ld   (mpSeg), a
    call MpRegCheck01
    jr   nz, mtoDone
    ld   a, 1
    ld   (mmPage), a
    ld   a, (mpN)
    srl  a
    ld   (mpSeg), a
    call MpRegCheck01
    jr   nz, mtoDone
    ; ---- page 3 (FF) with segment n-1, stackless: never our own page 3 ----
    ld   a, 3
    ld   (mmPage), a
    call MapCellPtr
    ld   a, (hl)
    cp   MMAP_RAM
    jr   nz, mtoDone
    ld   a, (monPresent)
    or   a
    jr   nz, mtoP3
    ld   a, (mmSlotId)
    call OwnPage3
    jr   z, mtoDone
mtoP3:
    ld   a, (mpN)
    dec  a
    ld   (mpSeg), a
    push ix
    call MpTestPage3            ; clobbers IX/IY
    pop  ix
    call MpRegResult
mtoDone:
    ld   a, (mpResN)
    inc  a
    ld   (mpResN), a
    ret

; MpRegCheck01 - (mmPage) 0/1, (mpSeg): skip (Z) unless that page is RAM;
;                else rlMapperReg and Z = ok / NZ = entry filled with REGFAIL
MpRegCheck01:
    call MapCellPtr
    ld   a, (hl)
    cp   MMAP_RAM
    jr   z, mrcRun
    xor  a
    ret
mrcRun:
    push ix
    call rlMapperReg
    pop  ix
MpRegResult:
    ld   a, (rsSlotOK)
    or   a
    jr   z, mrrFail
    xor  a
    ret
mrrFail:
    ld   (ix+2), MP_REGFAIL
    ld   a, (mpSeg)
    ld   (ix+3), a
    ld   hl, (rsFailAddr)
    ld   (ix+4), l
    ld   (ix+5), h
    ld   a, (rsFailExp)
    ld   (ix+6), a
    ld   a, (rsFailGot)
    ld   (ix+7), a
    or   1
    ret

; ===========================================================================
;  MpTestPage2  -  IX = entry.  Page 2 -> (mmSlotId): markers, segment count,
;                  fill + verify of segments 1..n-1.  Leaves FE = 1.
; ===========================================================================
MpTestPage2:
    di
    call rlSelect
    ; ---- markers, 255 first so the lowest alias wins ----
    ld   b, 0
mp2Mark:
    dec  b
    ld   a, b
    out  (0xFE), a
    ld   (0x8000), a
    jr   nz, mp2Mark
    ; ---- count ----
    ld   b, 0
mp2Cnt:
    ld   a, b
    out  (0xFE), a
    ld   a, (0x8000)
    cp   b
    jr   nz, mp2CntMis
    inc  b
    jr   nz, mp2Cnt
    jr   mp2CntDone             ; 256 distinct segments (count byte = 0)
mp2CntMis:
    ld   a, b
    or   a
    jr   nz, mp2CntDone
    ld   (ix+2), MP_NORESP
    jr   mp2End
mp2CntDone:
    ld   (ix+1), b
    ld   a, b
    cp   1
    jr   nz, mp2Mapper
    ld   (ix+2), MP_PLAIN
    jr   mp2End
mp2Mapper:
    ; n = min(count, 64), count 0 = 256
    or   a
    jr   z, mp2Cap
    cp   65
    jr   c, mp2N
mp2Cap:
    ld   a, 64
mp2N:
    ld   (mpN), a
    ; ---- fill segments 1..n-1 ----
    ld   c, 1
mp2FillSeg:
    ld   a, c
    out  (0xFE), a
    call MpSegTerm
    ld   h, 0x80
mp2FillRow:
    ld   a, h
    call MpRowBase
    ld   e, a
    ld   l, 0
mp2FillB:
    ld   (hl), e
    ld   a, e
    add  a, 5
    ld   e, a
    inc  l
    jr   nz, mp2FillB
    inc  h
    ld   a, h
    cp   0xC0
    jr   nz, mp2FillRow
    inc  c
    ld   a, (mpN)
    cp   c
    jr   nz, mp2FillSeg
    ; ---- verify ----
    ld   c, 1
mp2VerSeg:
    ld   a, c
    out  (0xFE), a
    call MpSegTerm
    ld   h, 0x80
mp2VerRow:
    ld   a, h
    call MpRowBase
    ld   e, a
    ld   l, 0
mp2VerB:
    ld   a, (hl)
    cp   e
    jr   nz, mp2SegFail
    ld   a, e
    add  a, 5
    ld   e, a
    inc  l
    jr   nz, mp2VerB
    inc  h
    ld   a, h
    cp   0xC0
    jr   nz, mp2VerRow
    inc  c
    ld   a, (mpN)
    cp   c
    jr   nz, mp2VerSeg
    jr   mp2End
mp2SegFail:
    ld   (ix+2), MP_SEGFAIL
    ld   (ix+3), c
    ld   (ix+4), l
    ld   (ix+5), h
    ld   (ix+6), e
    ld   (ix+7), a
mp2End:
    ld   a, 1
    out  (0xFE), a
    call rlDeselect
    ei
    ret

; MpSegTerm - A = segment -> D = 13*seg + 0x3B      (clobbers A, B)
MpSegTerm:
    ld   b, a
    add  a, a
    add  a, a                   ; 4s
    ld   d, a
    add  a, a                   ; 8s
    add  a, d                   ; 12s
    add  a, b                   ; 13s
    add  a, 0x3B
    ld   d, a
    ret

; MpRowBase - A = H of the row, D = term -> A = 11*(0x80|(H&0x3F)) + D
;             (clobbers B)
MpRowBase:
    and  0x3F
    or   0x80
    ld   b, a
    add  a, a
    add  a, a                   ; 4H
    add  a, b                   ; 5H
    add  a, a                   ; 10H
    add  a, b                   ; 11H
    add  a, d
    ret

; ===========================================================================
;  MpTestPage3  -  (mmSlotId), (mpSeg): OUT (FF),seg, then rows C000 and
;                  E000 of the board's page 3 are read back against the
;                  pattern.  Stackless bracket: the Goa'uld's own page 3
;                  follows port FF too, so no RAM between the OUT and the
;                  restore.  rsSlotOK / rsFail*.  Clobbers IX/IY.
; ===========================================================================
MpTestPage3:
    ld   a, (mmSlotId)
    ld   (p3SlotId), a
    ld   a, 3
    ld   (p3Page), a
    di
    ld   a, CTL_IGNINT
    call MonSetCtrl
    call P3Prepare              ; D = A8', E = image', B'/C', IX, IYL
    ld   a, (mpSeg)
    push de
    call MpSegTerm
    ld   a, d
    pop  de
    ld   h, a                   ; term
    add  a, 0x80                ; row C000: H&3F|80 = 80, 11*80 = ..80
    ld   b, a
    ld   a, h
    add  a, 0xE0                ; row E000: A0, 11*A0 = ..E0
    ld   c, a
    ld   a, (mpSeg)
    out  (0xFF), a
    ; ================= no stack / no page-3 variables from here =================
    P3_SWITCH_ON
    ld   h, 0xC0
    ld   l, 0
    ld   e, b
mp3Row1:
    ld   a, (hl)
    cp   e
    jr   nz, mp3Fail
    ld   a, e
    add  a, 5
    ld   e, a
    inc  l
    jr   nz, mp3Row1
    ld   h, 0xE0
    ld   e, c
mp3Row2:
    ld   a, (hl)
    cp   e
    jr   nz, mp3Fail
    ld   a, e
    add  a, 5
    ld   e, a
    inc  l
    jr   nz, mp3Row2
    P3_SWITCH_OFF
    xor  a
    out  (0xFF), a
    ; ================= page restored: stack and variables back =================
    ld   a, 1
    ld   (rsSlotOK), a
    jr   mp3Done
mp3Fail:
    ld   d, a
    P3_SWITCH_OFF
    xor  a
    out  (0xFF), a
    ld   (rsFailAddr), hl
    ld   a, d
    ld   (rsFailGot), a
    ld   a, e
    ld   (rsFailExp), a
    xor  a
    ld   (rsSlotOK), a
mp3Done:
    xor  a
    call MonSetCtrl
    ei
    ret

; ===========================================================================
;  MapperPrint  -  one row per mpRes entry at (row), leaves row = next free
;    "MAPPER S3-2 8 seg 128K regs ok        OK"
;    "MAPPER S3-2 seg 5 @8123 e=5A g=00    MAL"
;    "MAPPER S3-2 FD s2 @4000 e=5A g=00    MAL"
; ===========================================================================
MapperPrint:
    ld   a, (mpResN)
    or   a
    jr   nz, mppLoopInit
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sMpNone
    call PrintAt
    call PrintNA
    ld   a, (row)
    inc  a
    ld   (row), a
    ret
mppLoopInit:
    ld   ix, mpRes
    ld   a, (mpResN)
    ld   (tmpB), a
mppLoop:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sMpHdr
    call PrintAt
    ld   a, (ix+0)
    push ix
    call PrintSlotId
    pop  ix
    call PrintSpace
    ld   a, (ix+2)
    or   a
    jr   z, mppOk
    cp   MP_PLAIN
    jr   z, mppPlain
    cp   MP_NORESP
    jr   z, mppNoResp
    cp   MP_SEGFAIL
    jr   z, mppSeg
    ; register failure: "FD s2 @4000 e=5A g=00"
    ld   a, 'F'
    call CHPUT
    ld   a, (ix+5)
    rlca
    rlca
    and  0x03
    add  a, 'C'
    call CHPUT
    ld   hl, sMpS
    call PrintStr
    ld   a, (ix+3)
    call PrintDec8
    jr   mppAddr
mppSeg:
    ld   hl, sMpSeg
    call PrintStr
    ld   a, (ix+3)
    call PrintDec8
mppAddr:
    call PrintSpace
    ld   a, '@'
    call CHPUT
    ld   l, (ix+4)
    ld   h, (ix+5)
    call PrintHexHL
    ld   hl, sExpS
    call PrintStr
    ld   a, (ix+6)
    call PrintHexA
    ld   hl, sGotS
    call PrintStr
    ld   a, (ix+7)
    call PrintHexA
    call PrintFAIL
    jr   mppNext
mppNoResp:
    ld   hl, sMpNoResp
    call PrintStr
    call PrintFAIL
    jr   mppNext
mppPlain:
    ld   hl, sMpPlain
    call PrintStr
    call PrintNA
    jr   mppNext
mppOk:
    ld   a, (ix+1)
    ld   l, a
    ld   h, 0
    or   a
    jr   nz, mppCnt
    inc  h                      ; 0 = 256 segments
mppCnt:
    push hl
    call PrintDec16
    ld   hl, sMpSegs
    call PrintStr
    pop  hl
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, hl                 ; x 16 KB
    call PrintDec16
    ld   hl, sMpRegs
    call PrintStr
    call PrintOK
mppNext:
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   bc, 8
    add  ix, bc
    ld   a, (tmpB)
    dec  a
    ld   (tmpB), a
    jp   nz, mppLoop
    ret

sMpHdr:    db "MAPPER ", 0
sMpNone:   db "MAPPER ninguno (sin RAM en pag2)", 0
sMpPlain:  db "sin mapper (RAM plana)", 0
sMpNoResp: db "pag2 no responde", 0
sMpSeg:    db "seg ", 0
sMpS:      db " s", 0
sMpSegs:   db " seg ", 0
sMpRegs:   db "K regs ok", 0

; ===========================================================================
;  RtcTest  -  rtcStatus: 0 ok, 2 RAM nibble failed (rtcFailReg/Exp/Got),
;              3 clock stopped.  rtcSec0/rtcSec1 = BCD seconds before/after.
;              Skipped on an MSX1 board (BIOS byte 002D = 0).
; ===========================================================================
RtcTest:
    xor  a
    ld   (rtcStatus), a
    ld   a, (BIOS_HEAD + 0x2D)  ; MSX1 board: no RTC, and the writes would
    or   a                      ; reach the Goa'uld's own RTC with garbage
    ret  z
    di
    ld   a, CTL_RTC
    call MonSetCtrl
    ld   a, 13
    call RtcRead
    ld   (rtcMode), a
    ; ---- RAM banks 2 and 3: save, test, restore ----
    ld   hl, SCRATCH
    ld   c, 0x0A                ; timer on, bank 2
    call RtcBankSave
    ld   c, 0x0B
    call RtcBankSave
    ld   c, 0x0A
    call RtcBankTest
    ld   c, 0x0B
    call RtcBankTest
    ld   hl, SCRATCH
    ld   c, 0x0A
    call RtcBankRestore
    ld   c, 0x0B
    call RtcBankRestore
    ; ---- seconds must move: bank 0, timer on ----
    ld   a, 13
    ld   c, 0x08
    call RtcWrite
    call RtcReadSec
    ld   (rtcSec0), a
    ld   b, 6
rtcWait:
    push bc
    ld   c, 200
    call DelayMs
    pop  bc
    djnz rtcWait
    call RtcReadSec
    ld   (rtcSec1), a
    ld   hl, rtcSec0
    cp   (hl)
    jr   nz, rtcTickOk
    ld   a, (rtcStatus)
    or   a
    jr   nz, rtcTickOk
    ld   a, 3
    ld   (rtcStatus), a
rtcTickOk:
    ld   a, (rtcMode)
    ld   c, a
    ld   a, 13
    call RtcWrite
    xor  a
    call MonSetCtrl
    ei
    ret

; RtcRead - A = register -> A = nibble
RtcRead:
    out  (RTC_ADR), a
    in   a, (RTC_DAT)
    and  0x0F
    ret

; RtcWrite - A = register, C = nibble
RtcWrite:
    out  (RTC_ADR), a
    ld   a, c
    out  (RTC_DAT), a
    ret

; RtcReadSec - A = BCD seconds (reg 1 tens, reg 0 units), bank 0 selected
RtcReadSec:
    ld   a, 1
    call RtcRead
    rlca
    rlca
    rlca
    rlca
    ld   b, a
    xor  a
    call RtcRead
    or   b
    ret

; RtcBankSave - C = mode nibble (bank), HL -> 13 bytes (HL advances)
RtcBankSave:
    ld   a, 13
    call RtcWrite
    ld   d, 0
rbsLoop:
    ld   a, d
    call RtcRead
    ld   (hl), a
    inc  hl
    inc  d
    ld   a, d
    cp   13
    jr   nz, rbsLoop
    ret

; RtcBankRestore - C = mode nibble, HL -> 13 bytes (HL advances)
RtcBankRestore:
    ld   a, 13
    call RtcWrite
    ld   d, 0
rbrLoop:
    ld   c, (hl)
    ld   a, d
    call RtcWrite
    inc  hl
    inc  d
    ld   a, d
    cp   13
    jr   nz, rbrLoop
    ret

; RtcBankTest - C = mode nibble: registers 0-12 take 0x5, then 0xA.
;               First failure -> rtcStatus 2, rtcFailReg/Exp/Got.
RtcBankTest:
    ld   a, 13
    call RtcWrite
    ld   e, 0x05
rbtPat:
    ld   d, 0
rbtLoop:
    ld   a, d
    ld   c, e
    call RtcWrite
    ld   a, d
    call RtcRead
    cp   e
    jr   nz, rbtFail
    inc  d
    ld   a, d
    cp   13
    jr   nz, rbtLoop
    ld   a, e
    cp   0x0A
    ret  z
    ld   e, 0x0A
    jr   rbtPat
rbtFail:
    ld   b, a
    ld   a, (rtcStatus)
    or   a
    ret  nz
    ld   a, 2
    ld   (rtcStatus), a
    ld   a, d
    ld   (rtcFailReg), a
    ld   a, e
    ld   (rtcFailExp), a
    ld   a, b
    ld   (rtcFailGot), a
    ret

; ===========================================================================
;  RtcPrint  -  one row at (row):
;    "RTC    RP5C01 seg 23>24 RAM26 ok      OK"
;    "RTC    no hay (placa MSX1)            n/d"
;    "RTC    seg 23>23 PARADO: 32kHz/pila  MAL"
;    "RTC    B4/B5 RAM reg 12 e=05 g=0F    MAL"
; ===========================================================================
RtcPrint:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sRtcHdr
    call PrintAt
    ld   a, (BIOS_HEAD + 0x2D)  ; MSX version byte of the board BIOS
    or   a
    jr   nz, rpMsx2
    ld   hl, sRtcNone
    call PrintStr
    call PrintNA
    ret
rpMsx2:
    ld   a, (rtcStatus)
    or   a
    jr   z, rpOk
    cp   2
    jr   z, rpRam
    ld   hl, sRtcSec
    call PrintStr
    call rpSecs
    ld   hl, sRtcStop
    call PrintStr
    call PrintFAIL
    ret
rpRam:
    ld   a, (rtcFailReg)
    or   a
    jr   nz, rpRamReg
    ld   a, (rtcFailGot)
    cp   0x0F
    jr   nz, rpRamReg
    ld   hl, sRtcDead
    call PrintStr
    call PrintFAIL
    ret
rpRamReg:
    ld   hl, sRtcRam
    call PrintStr
    ld   a, (rtcFailReg)
    call PrintDec8
    ld   hl, sExpS
    call PrintStr
    ld   a, (rtcFailExp)
    call PrintHexA
    ld   hl, sGotS
    call PrintStr
    ld   a, (rtcFailGot)
    call PrintHexA
    call PrintFAIL
    ret
rpOk:
    ld   hl, sRtcOk
    call PrintStr
    call rpSecs
    ld   hl, sRtcRamOk
    call PrintStr
    call PrintOK
    ret
rpSecs:
    ld   a, (rtcSec0)
    call PrintHexA
    ld   a, '>'
    call CHPUT
    ld   a, (rtcSec1)
    call PrintHexA
    ret

sRtcHdr:   db "RTC    ", 0
sRtcNone:  db "no hay (placa MSX1)", 0
sRtcSec:   db "seg ", 0
sRtcStop:  db " PARADO: 32kHz/pila", 0
sRtcDead:  db "B4/B5 no responde: RP5C01/5V", 0
sRtcRam:   db "B4/B5 RAM reg ", 0
sRtcOk:    db "RP5C01 seg ", 0
sRtcRamOk: db " RAM26 ok", 0
