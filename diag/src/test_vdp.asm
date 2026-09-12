; =============================================================================
;  test_vdp.asm  -  Goa'uld Doctor  -  the BOARD's VDP (TMS9918/9118/9929)
;
;  With CONTROL.vdp_ext the ports 0x98/0x99 reach the board's own VDP (the
;  Goa'uld's V9958 is deselected, so the HDMI dashboard survives).  Everything
;  here runs with DI and never calls the BIOS (its ISR would read 0x99).
;
;  Tests: status register alive (F flag), frames/s, /INT line (monitor),
;         16 KB VRAM (address, 4 patterns, retention) with bit attribution,
;         sprite engine (collision + 5th sprite flags = real rendering),
;         and finally a picture is left on the board's video output.
;
;  TMS timing: >= 2 us between VRAM accesses with the display blanked; every
;  loop here is >= 30 T (8 us) so no extra padding is needed.
;  (sjasmplus: one instruction per line.)
; =============================================================================

VDP_DATA equ 0x98
VDP_CTRL equ 0x99

VR_ADDR  equ 1      ; phase codes
VR_P00   equ 2
VR_PFF   equ 3
VR_PAA   equ 4
VR_P55   equ 5
VR_RET   equ 6

; ---------------------------------------------------------------------------
;  VdpReg  -  E = register 0..7, A = value
; ---------------------------------------------------------------------------
VdpReg:
    out  (VDP_CTRL), a
    ld   a, e
    or   0x80
    out  (VDP_CTRL), a
    ret

; ---------------------------------------------------------------------------
;  VdpSetWr / VdpSetRd  -  HL = VRAM address
; ---------------------------------------------------------------------------
VdpSetWr:
    ld   a, l
    out  (VDP_CTRL), a
    ld   a, h
    and  0x3F
    or   0x40
    out  (VDP_CTRL), a
    ret
VdpSetRd:
    ld   a, l
    out  (VDP_CTRL), a
    ld   a, h
    and  0x3F
    out  (VDP_CTRL), a
    ret

; ---------------------------------------------------------------------------
;  VdpFill  -  HL = VRAM address, BC = count, A = value
; ---------------------------------------------------------------------------
VdpFill:
    ld   (vdpTmp), a
    call VdpSetWr
    ld   a, (vdpTmp)
vfLoop:
    out  (VDP_DATA), a
    dec  bc
    ld   d, a
    ld   a, b
    or   c
    ld   a, d
    jr   nz, vfLoop
    ret

; ---------------------------------------------------------------------------
;  VdpWriteBlock  -  HL = source, DE = VRAM address, BC = count
; ---------------------------------------------------------------------------
VdpWriteBlock:
    push hl
    ex   de, hl
    call VdpSetWr
    pop  hl
vwbLoop:
    ld   a, (hl)
    out  (VDP_DATA), a
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, vwbLoop
    ret

; ---------------------------------------------------------------------------
;  VdpWriteStr  -  HL = NUL string, DE = VRAM address (name table)
; ---------------------------------------------------------------------------
VdpWriteStr:
    push hl
    ex   de, hl
    call VdpSetWr
    pop  hl
vwsLoop:
    ld   a, (hl)
    or   a
    ret  z
    out  (VDP_DATA), a
    inc  hl
    jr   vwsLoop

; ---------------------------------------------------------------------------
;  VdpWaitFrame  -  poll S#0 until F=1 (clears it).  C = timeout (~60 ms)
; ---------------------------------------------------------------------------
VdpWaitFrame:
    ld   bc, 7000
vwfLoop:
    in   a, (VDP_CTRL)
    rlca
    jr   c, vwfSeen
    dec  bc
    ld   a, b
    or   c
    jr   nz, vwfLoop
    scf
    ret
vwfSeen:
    or   a
    ret

; ===========================================================================
;  VdpTest  -  run everything; results in variables
; ===========================================================================
VdpTest:
    di
    ld   a, CTL_VDP | CTL_IGNINT
    call MonSetCtrl
    xor  a
    ld   (vdpAlive), a
    ld   (vdpTO), a
    ld   (vrBadBits), a
    ld   (vrPhase), a
    ld   (sprNoColl), a
    ld   (sprColl), a
    ld   (sprFifth), a
    ld   hl, 0
    ld   (vrFails), hl
    ld   (vrRetFails), hl
    ld   a, 0xFF
    ld   (vdpIntRate), a
    ; display off, 16 KB, IE=0
    ld   e, 1
    ld   a, 0x80
    call VdpReg
    ld   e, 0
    xor  a
    call VdpReg
    ; ---- 1. alive: raw S#0, then F must appear within ~60 ms ----
    in   a, (VDP_CTRL)
    ld   (vdpS0), a
    call VdpWaitFrame
    jp   c, vtDead
    call VdpWaitFrame
    jp   c, vtDead
    ld   a, 1
    ld   (vdpAlive), a
    ; ---- 1b. type + VRAM size (TMS / V9938 / V9958, 16/64/128 KB) ----
    call VdpProbeType
    ; V99x8: 50 Hz (R#9 NT bit) when the board BIOS says PAL (byte 002B bit 7)
    xor  a
    ld   (vdpR9), a
    ld   a, (vdpType)
    or   a
    jr   z, vtNoPal
    ld   a, (BIOS_HEAD + 0x2B)
    and  0x80
    ld   a, 0x00
    jr   z, vtR9
    ld   a, 0x02
vtR9:
    ld   (vdpR9), a
    ld   e, 9
    call VdpReg
vtNoPal:
    ; ---- 2. frames per second ----
    ; A real TMS9918 LOSES the F flag if the status register is read in the
    ; very cycle the flag is being set, so tight polling drops 1-2 frames/s
    ; (seen on a real HB-10: 58/s while /INT said 60).  Poll every ~2 ms.
    ld   a, (monPresent)
    or   a
    jr   z, vtFpsLoop
    ; monitor present: exact 1000 ms from the free-running ms counter
    ld   a, 0x19
    call MonReadReg
    ld   e, a
    in   a, (MON_DAT)           ; 0x1A latched high byte
    ld   d, a                   ; DE = start
    ld   b, 0                   ; frames
    ld   c, e
vtFpsMs:
    ld   a, 0x19
    out  (MON_IDX), a
    in   a, (MON_DAT)
    ld   l, a
    in   a, (MON_DAT)
    ld   h, a
    ld   a, l
    sub  c
    cp   2
    jr   c, vtFpsMs             ; < 2 ms since the last poll: wait
    ld   c, l
    in   a, (VDP_CTRL)
    and  0x80
    jr   z, vtFpsMsNo
    inc  b
vtFpsMsNo:
    or   a
    sbc  hl, de                 ; elapsed ms
    ld   a, h
    cp   0x03
    jr   c, vtFpsMs
    ld   a, l
    cp   0xE8                   ; 1000 = 0x03E8
    jr   c, vtFpsMs
    ld   a, b
    ld   (vdpFrames), a
    jr   vtFpsDone
vtFpsLoop:
    ; no monitor (emulator): 500 polls spaced ~2 ms (DelayMs is ~0.93 ms/unit
    ; + loop overhead), close enough for the 45-65 window
    ld   d, 0
    ld   hl, 500
vtFps:
    in   a, (VDP_CTRL)
    and  0x80
    jr   z, vtFpsNo
    inc  d
vtFpsNo:
    push hl
    ld   c, 2
    call DelayMs
    pop  hl
    dec  hl
    ld   a, h
    or   l
    jr   nz, vtFps
    ld   a, d
    ld   (vdpFrames), a
vtFpsDone:
    ; ---- 3. /INT line: IE=1, keep acknowledging for ~2.2 s, read INT_RATE ----
    ld   e, 1
    ld   a, 0xA0
    call VdpReg
    ld   bc, 0
    ld   d, 3
vtInt:
    in   a, (VDP_CTRL)
    dec  bc
    ld   a, b
    or   c
    jr   nz, vtInt
    dec  d
    jr   nz, vtInt              ; 3 x 65536 x ~36 T = 2.0 s
    ld   a, (monPresent)
    or   a
    jr   z, vtIntNoMon
    ld   a, 0x0E
    call MonReadReg
    ld   (vdpIntRate), a
vtIntNoMon:
    ld   e, 1
    ld   a, 0x80
    call VdpReg
    in   a, (VDP_CTRL)          ; release /INT
    ; ---- 4. VRAM (every bank) ----
    call VramTest
    ; ---- 4b. V99x8 command engine ----
    call CmdTest
    ; ---- 5. sprites ----
    call SpriteTest
    ; ---- 6. leave a picture on the board's video output ----
    call VdpPicture
    jr   vtEnd
vtDead:
    ld   a, 1
    ld   (vdpTO), a
vtEnd:
    xor  a
    call MonSetCtrl
    ei
    ret

; ===========================================================================
;  VramTest  -  16 KB, display blanked.  Failures accumulate (never abort).
; ===========================================================================
VramTest:
    ; --- phase 1: address uniqueness, cell = H xor L xor bank*0x33 ---
    ld   a, VR_ADDR
    ld   (vrPhase), a
    xor  a
    ld   (vrBank), a
vrAwBank:
    call VrSetBank
    ld   hl, 0
    call VdpSetWr
    ld   hl, 0
vrAw:
    ld   a, (vrBankPat)
    xor  h
    xor  l
    out  (VDP_DATA), a
    inc  hl
    ld   a, h
    cp   0x40
    jr   nz, vrAw
    call VrNextBank
    jr   nz, vrAwBank
    xor  a
    ld   (vrBank), a
vrArBank:
    call VrSetBank
    ld   hl, 0
    call VdpSetRd
    ld   hl, 0
vrAr:
    ld   a, (vrBankPat)
    xor  h
    xor  l
    ld   e, a
    in   a, (VDP_DATA)
    cp   e
    call nz, VrRecord
    inc  hl
    ld   a, h
    cp   0x40
    jr   nz, vrAr
    call VrNextBank
    jr   nz, vrArBank
    ; --- phases 2-5: fixed patterns ---
    ld   a, VR_P00
    ld   e, 0x00
    call VrPattern
    ld   a, VR_PFF
    ld   e, 0xFF
    call VrPattern
    ld   a, VR_PAA
    ld   e, 0xAA
    call VrPattern
    ld   a, VR_P55
    ld   e, 0x55
    call VrPattern
    ; --- phase 6: retention, ~1 s ---
    ld   a, VR_RET
    ld   (vrPhase), a
    ld   a, 0x5A
    call VrFillAll
    ld   c, 250
    call DelayMs
    ld   c, 250
    call DelayMs
    ld   c, 250
    call DelayMs
    ld   c, 250
    call DelayMs
    ld   hl, (vrFails)
    ld   (tmpHL), hl
    ld   e, 0x5A
    call VrVerifyAll
    ld   hl, (vrFails)
    ld   de, (tmpHL)
    or   a
    sbc  hl, de
    ld   (vrRetFails), hl
    xor  a
    ld   (vrPhase), a
    ld   (vrBank), a
    call VrSetBank              ; leave bank 0 for the sprite test / picture
    ret

; VrSetBank - R#14 = (vrBank) on a V99x8 (no-op on a TMS); vrBankPat = bank*0x33
VrSetBank:
    ld   a, (vrBank)
    ld   c, a
    add  a, a
    add  a, c
    ld   b, a                   ; bank*3
    add  a, a
    add  a, a
    add  a, a
    add  a, a                   ; bank*48
    add  a, b                   ; bank*0x33
    ld   (vrBankPat), a
    ld   a, (vdpType)
    or   a
    ret  z
    ld   a, c
    ld   e, 14
    call VdpReg
    ret

; VrNextBank - vrBank++; NZ while vrBank < vrBanks
VrNextBank:
    ld   a, (vrBank)
    inc  a
    ld   (vrBank), a
    ld   c, a
    ld   a, (vrBanks)
    cp   c
    ret

; VrPattern - A = phase code, E = pattern: fill all banks + verify all banks
VrPattern:
    ld   (vrPhase), a
    push de
    ld   a, e
    call VrFillAll
    pop  de
    call VrVerifyAll
    ret

; VrFillAll - A = value into every bank
VrFillAll:
    ld   (vrFillVal), a
    xor  a
    ld   (vrBank), a
vfaBank:
    call VrSetBank
    ld   hl, 0
    ld   bc, 0x4000
    ld   a, (vrFillVal)
    call VdpFill
    call VrNextBank
    jr   nz, vfaBank
    ret

; VrVerifyAll - E = expected everywhere, every bank
VrVerifyAll:
    xor  a
    ld   (vrBank), a
vvaBank:
    push de
    call VrSetBank
    pop  de
    ld   hl, 0
    call VdpSetRd
    ld   hl, 0
vrvLoop:
    in   a, (VDP_DATA)
    cp   e
    call nz, VrRecord
    inc  hl
    ld   a, h
    cp   0x40
    jr   nz, vrvLoop
    push de
    call VrNextBank
    pop  de
    jr   nz, vvaBank
    ret

; VrRecord - HL = addr, E = expected, A = got.  Preserves HL, DE, BC.
VrRecord:
    push hl
    push de
    push bc
    ld   c, a                   ; C = got
    xor  e
    ld   b, a                   ; B = expected ^ got
    ld   a, (vrBadBits)
    or   b
    ld   (vrBadBits), a
    push de
    ld   de, (vrFails)
    ld   a, d
    or   e
    pop  de
    jr   nz, vrrCount
    ; first failure: record it
    ld   (vrFailAddr), hl
    ld   a, (vrBank)
    ld   (vrFailBank), a
    ld   a, e
    ld   (vrFailExp), a
    ld   a, c
    ld   (vrFailGot), a
    ld   a, (vrPhase)
    ld   (vrFailPh), a
vrrCount:
    ld   hl, (vrFails)
    ld   a, h
    and  l
    inc  a
    jr   z, vrrDone             ; saturated at 0xFFFF
    inc  hl
    ld   (vrFails), hl
vrrDone:
    pop  bc
    pop  de
    pop  hl
    ret

; ===========================================================================
;  VdpProbeType  -  vdpType 0 = TMS9918/9118/9929 (16 KB), 1 = V9938,
;                   2 = V9958; vramKB 16/64/128; vrBanks = vramKB/16.
;  Safe on a TMS: "R#14" aliases to R#6 there (SpriteTest sets R#6 again)
;  and R#15 is only touched once R#14 proved to exist.
; ===========================================================================
VdpProbeType:
    xor  a
    ld   (vdpType), a
    ld   a, 16
    ld   (vramKB), a
    ld   e, 14
    xor  a
    call VdpReg                 ; bank 0 (TMS: R6=0)
    ld   hl, 0
    call VdpSetWr
    ld   a, 0x5A
    out  (VDP_DATA), a
    ld   e, 14
    ld   a, 1
    call VdpReg                 ; bank 1 = VRAM 0x4000 (TMS: still 0x0000)
    ld   hl, 0
    call VdpSetWr
    ld   a, 0xA5
    out  (VDP_DATA), a
    ld   e, 14
    xor  a
    call VdpReg
    ld   hl, 0
    call VdpSetRd
    in   a, (VDP_DATA)
    ld   (vdpProbe), a          ; 5A = V99x8, A5 = TMS, else VRAM holds nothing
    cp   0x5A
    jr   nz, vptTms             ; overwritten: 14-bit address space = TMS
    ; ---- V99x8: 64 or 128 KB?  bank 4 = VRAM 0x10000 ----
    ld   a, 64
    ld   (vramKB), a
    ld   e, 14
    ld   a, 4
    call VdpReg
    ld   hl, 0
    call VdpSetWr
    ld   a, 0x3C
    out  (VDP_DATA), a
    ld   e, 14
    xor  a
    call VdpReg
    ld   hl, 0
    call VdpSetRd
    in   a, (VDP_DATA)
    cp   0x5A
    jr   nz, vptType
    ld   a, 128
    ld   (vramKB), a
vptType:
    ; ---- V9938 or V9958: S#1 bits 5:1 = ID (0 / 2) ----
    ld   e, 15
    ld   a, 1
    call VdpReg
    in   a, (VDP_CTRL)
    and  0x3E
    ld   c, 1
    or   a
    jr   z, vptSet
    ld   c, 2
vptSet:
    ld   a, c
    ld   (vdpType), a
    ld   e, 15
    xor  a
    call VdpReg                 ; back to S#0
vptTms:
    ld   a, (vramKB)
    rrca
    rrca
    rrca
    rrca                        ; /16
    and  0x0F
    ld   (vrBanks), a
    ret

; ===========================================================================
;  CmdTest  -  V99x8 command engine: HMMV fills a 256x16 block at (0,0) in
;              SCREEN 5 (bytes 0000-07FF), HMMM copies it to (0,64) (bytes
;              2000-27FF); both blocks are read back through the CPU port.
;              cmdRes: 0 ok, 1 mismatch, 2 CE never dropped, 3 n/a (TMS).
; ===========================================================================
CmdTest:
    ld   a, 3
    ld   (cmdRes), a
    ld   a, (vdpType)
    or   a
    ret  z
    ld   e, 0
    ld   a, 0x06                ; R#0: M4=1 M3=1 -> GRAPHIC 4 (SCREEN 5)
    call VdpReg
    ld   e, 1
    ld   a, 0x80                ; display off, M1 = M2 = 0
    call VdpReg
    ld   e, 14
    xor  a
    call VdpReg
    call CmdWaitCE
    jp   c, cmdTimeout
    ; --- HMMV: DX=0 DY=0 NX=256 NY=16 CLR=0xA5 ---
    ld   e, 36
    call CmdReg0
    ld   e, 37
    call CmdReg0
    ld   e, 38
    call CmdReg0
    ld   e, 39
    call CmdReg0
    ld   e, 40
    call CmdReg0
    ld   e, 41
    ld   a, 1
    call VdpReg
    ld   e, 42
    ld   a, 16
    call VdpReg
    ld   e, 43
    call CmdReg0
    ld   e, 44
    ld   a, 0xA5
    call VdpReg
    ld   e, 45
    call CmdReg0
    ld   e, 46
    ld   a, 0xC0                ; HMMV
    call VdpReg
    call CmdWaitCE
    jr   c, cmdTimeout
    ; --- HMMM: SX=0 SY=0 -> DX=0 DY=64, NX=256 NY=16 ---
    ld   e, 32
    call CmdReg0
    ld   e, 33
    call CmdReg0
    ld   e, 34
    call CmdReg0
    ld   e, 35
    call CmdReg0
    ld   e, 36
    call CmdReg0
    ld   e, 37
    call CmdReg0
    ld   e, 38
    ld   a, 64
    call VdpReg
    ld   e, 39
    call CmdReg0
    ld   e, 40
    call CmdReg0
    ld   e, 41
    ld   a, 1
    call VdpReg
    ld   e, 42
    ld   a, 16
    call VdpReg
    ld   e, 43
    call CmdReg0
    ld   e, 46
    ld   a, 0xD0                ; HMMM
    call VdpReg
    call CmdWaitCE
    jr   c, cmdTimeout
    ; --- verify both blocks: 0000-07FF and 2000-27FF must be 0xA5 ---
    xor  a
    ld   (cmdRes), a
    ld   hl, 0x0000
    call CmdVerifyBlock
    ld   hl, 0x2000
    call CmdVerifyBlock
    jr   cmdDone
cmdTimeout:
    ld   a, 2
    ld   (cmdRes), a
cmdDone:
    ld   e, 15
    xor  a
    call VdpReg                 ; S#0 again
    ld   e, 0
    xor  a
    call VdpReg                 ; mode bits back to G1
    ret

; CmdReg0 - register E = 0
CmdReg0:
    xor  a
    call VdpReg
    ret

; CmdVerifyBlock - HL = VRAM start, 2048 bytes must read 0xA5; cmdRes=1 if not
CmdVerifyBlock:
    call VdpSetRd
    ld   bc, 0x0800
cvbLoop:
    in   a, (VDP_DATA)
    cp   0xA5
    jr   z, cvbOk
    ld   a, 1
    ld   (cmdRes), a
cvbOk:
    dec  bc
    ld   a, b
    or   c
    jr   nz, cvbLoop
    ret

; CmdWaitCE - S#2 bit 0 (CE) must drop within ~200 ms; C = timeout
CmdWaitCE:
    ld   e, 15
    ld   a, 2
    call VdpReg
    ld   bc, 20000
cwcLoop:
    in   a, (VDP_CTRL)
    and  0x01
    jr   z, cwcDone
    dec  bc
    ld   a, b
    or   c
    jr   nz, cwcLoop
    scf
    ret
cwcDone:
    or   a
    ret

; ===========================================================================
;  SpriteTest  -  Graphics 1, display on: collision and 5th-sprite flags
; ===========================================================================
SpriteTest:
    ; tables: NT 0x1800, CT 0x2000, PG 0x0000, SAT 0x1B00, SPG 0x3800
    ld   e, 2
    ld   a, 0x06
    call VdpReg
    ld   e, 3
    ld   a, 0x80
    call VdpReg
    ld   e, 4
    xor  a
    call VdpReg
    ld   e, 5
    ld   a, 0x36
    call VdpReg
    ld   e, 6
    ld   a, 0x07
    call VdpReg
    ld   e, 7
    ld   a, 0x04
    call VdpReg
    ; blank pattern 0, name table 0, colour table F4, sprite pattern 0 solid
    ld   hl, 0x0000
    ld   bc, 8
    xor  a
    call VdpFill
    ld   hl, 0x1800
    ld   bc, 768
    xor  a
    call VdpFill
    ld   hl, 0x2000
    ld   bc, 32
    ld   a, 0xF4
    call VdpFill
    ld   hl, 0x3800
    ld   bc, 8
    ld   a, 0xFF
    call VdpFill
    ; --- A: two sprites apart -> C must stay 0 ---
    ld   hl, satApart
    ld   de, 0x1B00
    ld   bc, 12
    call VdpWriteBlock
    ld   e, 1
    ld   a, 0xC0                ; display on, IE=0, 16K, 8x8 sprites
    call VdpReg
    call SprPoll
    ld   (sprNoColl), a
    ; --- B: overlapping -> C must be 1 ---
    ld   hl, satOverlap
    ld   de, 0x1B00
    ld   bc, 12
    call VdpWriteBlock
    call SprPoll
    ld   (sprColl), a
    ; --- C: five on one line -> 5S=1, number=4 ---
    ld   hl, satFive
    ld   de, 0x1B00
    ld   bc, 24
    call VdpWriteBlock
    call SprPoll
    ld   (sprFifth), a
    ret

; SprPoll - read S#0 continuously for ~5 frames (each read clears F, which
;           keeps 5th-sprite detection armed - it only runs while F=0):
;           A = OR of the flag bits (F/5S/C) | fifth-sprite number captured
;           while 5S was set (else the last number seen).
SprPoll:
    in   a, (VDP_CTRL)          ; discard stale flags
    ld   d, 0                   ; OR of flags
    ld   e, 0x1F                ; number
    ld   bc, 9000               ; ~9000 x 36 T = 90 ms
spLoop:
    in   a, (VDP_CTRL)
    ld   h, a
    and  0xE0
    or   d
    ld   d, a
    ld   a, h
    and  0x40
    jr   z, spNo5
    ld   a, h
    and  0x1F
    ld   e, a
spNo5:
    dec  bc
    ld   a, b
    or   c
    jr   nz, spLoop
    ld   a, d
    or   e
    ret

satApart:   db 80, 20, 0, 15,  80, 120, 0, 6,  0xD0, 0, 0, 0
satOverlap: db 80, 20, 0, 15,  80,  20, 0, 6,  0xD0, 0, 0, 0
satFive:    db 80, 0, 0, 15,  80, 20, 0, 6,  80, 40, 0, 10
            db 80, 60, 0, 12,  80, 80, 0, 14,  0xD0, 0, 0, 0

; ===========================================================================
;  VdpPicture  -  font + text + colour bars on the board's VDP (G1), and the
;                 two apart sprites; display left ON with IE=0.
; ===========================================================================
VdpPicture:
    ld   e, 1
    ld   a, 0x80                ; blank while loading
    call VdpReg
    ; font: 2 KB from the (internal) BIOS CGTABL pointer at 0x0004
    ld   hl, (0x0004)
    ld   de, 0x0000
    ld   bc, 0x0800
    call VdpWriteBlock
    ; patterns 0x80-0xFF solid
    ld   hl, 0x0400
    ld   bc, 0x0400
    ld   a, 0xFF
    call VdpFill
    ; colour table: chars <0x80 white on blue; groups 16..31 = colour n on blue
    ld   hl, 0x2000
    ld   bc, 16
    ld   a, 0xF4
    call VdpFill
    ld   hl, 0x2010
    call VdpSetWr
    ld   b, 16
    xor  a
vpCt:
    ld   d, a
    rlca
    rlca
    rlca
    rlca
    or   0x04
    out  (VDP_DATA), a
    ld   a, d
    inc  a
    djnz vpCt
    ; name table: spaces
    ld   hl, 0x1800
    ld   bc, 768
    ld   a, 0x20
    call VdpFill
    ld   hl, sPic1
    ld   de, 0x1800 + 2*32 + 2
    call VdpWriteStr
    ld   hl, sPic2
    ld   de, 0x1800 + 4*32 + 2
    call VdpWriteStr
    ld   hl, sPic3
    ld   de, 0x1800 + 5*32 + 2
    call VdpWriteStr
    ld   hl, sPic4
    ld   de, 0x1800 + 7*32 + 2
    call VdpWriteStr
    ; colour bar rows 13-15: 16 blocks of 2 chars, char = 0x80 + n*8
    ld   d, 3
    ld   hl, 0x1800 + 13*32
vpBarRow:
    push hl
    call VdpSetWr
    pop  hl
    ld   b, 16
    ld   a, 0x80
vpBar:
    out  (VDP_DATA), a
    ld   c, a
    out  (VDP_DATA), a
    ld   a, c
    add  a, 8
    djnz vpBar
    ld   bc, 32
    add  hl, bc
    dec  d
    jr   nz, vpBarRow
    ; sprites apart again, display on
    ld   hl, satApart
    ld   de, 0x1B00
    ld   bc, 12
    call VdpWriteBlock
    ld   e, 1
    ld   a, 0xC0
    call VdpReg
    ret

; ===========================================================================
;  Video pattern screen (key V) - patterns for the board's AV/RF output.
;  The board's VDP keeps whatever it was last told, so each pattern is set
;  with vdp_ext on (DI) and then the Goa'uld goes back to its own VDP to wait
;  for the next key.  1 = Doctor picture, 2 = full-screen colour bars,
;  3 = all white (backdrop 15, display off = max video level),
;  4 = all black (backdrop 1, sync only).
; ===========================================================================
VideoScreen:
    call INITXT
    ld   b, 1
    ld   c, 1
    ld   hl, sVidTitle
    call PrintAt
    ld   b, 3
    ld   c, 1
    ld   hl, sVid1
    call PrintAt
    ld   b, 4
    ld   c, 1
    ld   hl, sVid2
    call PrintAt
    ld   b, 5
    ld   c, 1
    ld   hl, sVid3
    call PrintAt
    ld   b, 6
    ld   c, 1
    ld   hl, sVid4
    call PrintAt
    ld   b, 8
    ld   c, 1
    ld   hl, sVidNote1
    call PrintAt
    ld   b, 9
    ld   c, 1
    ld   hl, sVidNote2
    call PrintAt
    ld   b, 24
    ld   c, 1
    ld   hl, sVidEsc
    call PrintAt
    call VidPattern1
vsLoop:
    call WaitKeyEdge
    cp   0x1B
    ret  z
    cp   '1'
    jr   z, vsP1
    cp   '2'
    jr   z, vsP2
    cp   '3'
    jr   z, vsP3
    cp   '4'
    jr   z, vsP4
    jr   vsLoop
vsP1:
    call VidPattern1
    jr   vsLoop
vsP2:
    call VidPattern2
    jr   vsLoop
vsP3:
    ld   a, 15
    call VidFlat
    jr   vsLoop
vsP4:
    ld   a, 1
    call VidFlat
    jr   vsLoop

; VidEnter / VidLeave - route the ports to the board's VDP and back
VidEnter:
    di
    ld   a, CTL_VDP | CTL_IGNINT
    call MonSetCtrl
    ret
VidLeave:
    xor  a
    call MonSetCtrl
    ei
    ret

; VdpG1Regs - Graphics 1 register set + solid sprite pattern 0, display off
VdpG1Regs:
    ld   e, 1
    ld   a, 0x80
    call VdpReg
    ld   e, 0
    xor  a
    call VdpReg
    ld   e, 2
    ld   a, 0x06
    call VdpReg
    ld   e, 3
    ld   a, 0x80
    call VdpReg
    ld   e, 4
    xor  a
    call VdpReg
    ld   e, 5
    ld   a, 0x36
    call VdpReg
    ld   e, 6
    ld   a, 0x07
    call VdpReg
    ld   e, 7
    ld   a, 0x04
    call VdpReg
    ld   hl, 0x3800
    ld   bc, 8
    ld   a, 0xFF
    call VdpFill
    ret

VidPattern1:
    call VidEnter
    call VdpG1Regs
    call VdpPicture
    call VidLeave
    ret

; full-screen vertical colour bars: every row = the 16 two-char blocks
VidPattern2:
    call VidEnter
    call VdpG1Regs
    call VdpPicture             ; loads font, solid blocks, colour table
    ld   e, 1
    ld   a, 0x80
    call VdpReg
    ld   d, 24
    ld   hl, 0x1800
vp2Row:
    push hl
    call VdpSetWr
    pop  hl
    ld   b, 16
    ld   a, 0x80
vp2Bar:
    out  (VDP_DATA), a
    ld   c, a
    out  (VDP_DATA), a
    ld   a, c
    add  a, 8
    djnz vp2Bar
    ld   bc, 32
    add  hl, bc
    dec  d
    jr   nz, vp2Row
    ld   hl, satNone
    ld   de, 0x1B00
    ld   bc, 4
    call VdpWriteBlock
    ld   e, 1
    ld   a, 0xC0
    call VdpReg
    call VidLeave
    ret
satNone: db 0xD0, 0, 0, 0

; VidFlat - A = colour: display off, backdrop = colour -> whole raster flat
VidFlat:
    ld   (vdpTmp), a
    call VidEnter
    ld   e, 1
    ld   a, 0x80
    call VdpReg
    ld   e, 7
    ld   a, (vdpTmp)
    and  0x0F
    call VdpReg
    call VidLeave
    ret

sVidTitle: db "PATRONES DE VIDEO EN EL VDP DE LA PLACA", 0
sVid1:     db "1 = cuadro del Doctor (texto+barras)", 0
sVid2:     db "2 = barras de color a pantalla completa", 0
sVid3:     db "3 = blanco pleno (nivel maximo)", 0
sVid4:     db "4 = negro (solo sincronismo)", 0
sVidNote1: db "Mira la salida AV/RF de la placa o mide", 0
sVidNote2: db "COMVID del TMS (pin 36): ~1 Vpp.", 0
sVidEsc:   db "ESC=volver (el patron se queda puesto)", 0

sPic1: db "GOAULD DOCTOR - VDP PLACA OK", 0
sPic2: db "SI VES ESTO, LA SALIDA DE", 0
sPic3: db "VIDEO DE LA PLACA FUNCIONA", 0
sPic4: db "SPRITES + BARRAS DE COLOR:", 0

; ===========================================================================
;  VdpPrint  -  summary rows starting at (row):
;    "VDP    S0=xx F:60/s /INT:60Hz      OK"
;    "VRAM   16K  0 fallos               OK"
;    "SPRITE colis OK  5o=4              OK"
; ===========================================================================
VdpPrint:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sVdpHdr
    call PrintAt
    ld   a, (vdpAlive)
    or   a
    jr   nz, vpAlive
    ld   hl, sVdpDead
    call PrintStr
    ld   a, (vdpS0)
    call PrintHexA
    call PrintFAIL
    ret
vpAlive:
    ld   a, (vdpType)
    or   a
    jr   nz, vpName
    ld   a, (vdpProbe)
    cp   0xA5
    jr   z, vpName
    ld   hl, sVdpUnk            ; "TMS" only because the VRAM kept nothing
    jr   vpNamePr
vpName:
    ld   a, (vdpType)
    add  a, a
    ld   c, a
    ld   b, 0
    ld   hl, vdpTypeNames
    add  hl, bc
    ld   a, (hl)
    inc  hl
    ld   h, (hl)
    ld   l, a
vpNamePr:
    call PrintStr
    ld   hl, sVdpS0
    call PrintStr
    ld   a, (vdpS0)
    call PrintHexA
    ld   hl, sVdpF
    call PrintStr
    ld   a, (vdpFrames)
    call PrintDec8
    ld   hl, sVdpInt
    call PrintStr
    ld   a, (vdpIntRate)
    cp   0xFF
    jr   nz, vpIntVal
    ld   hl, sVdpNoMon
    call PrintStr
    jr   vpVerdict
vpIntVal:
    call PrintDec8
    ld   hl, sHz2
    call PrintStr
vpVerdict:
    ; window: TMS 45..65 (PAL or NTSC by silicon); V99x8 = R#9 choice +-6
    ld   b, 45
    ld   c, 66
    ld   a, (vdpType)
    or   a
    jr   z, vpWin
    ld   b, 54
    ld   c, 67
    ld   a, (vdpR9)
    or   a
    jr   z, vpWin
    ld   b, 44
    ld   c, 57
vpWin:
    ld   a, (vdpFrames)
    cp   b
    jr   c, vpBad
    cp   c
    jr   nc, vpBad
    ld   a, (vdpIntRate)
    cp   0xFF
    jr   z, vpGood
    cp   b
    jr   c, vpBad
    cp   c
    jr   nc, vpBad
vpGood:
    call PrintOK
    jr   vpVram
vpBad:
    call PrintFAIL
vpVram:
    ; ---- VRAM row ----
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 1
    ld   hl, sVramHdr
    call PrintAt
    ld   a, (vramKB)
    call PrintDec8
    ld   a, 'K'
    call CHPUT
    call PrintSpace
    ld   hl, (vrFails)
    ld   a, h
    or   l
    jr   nz, vpVramBad
    ld   hl, sVramOK
    call PrintStr
    call PrintOK
    jr   vpCmd
vpVramBad:
    call PrintDec16
    ld   hl, sVramFails
    call PrintStr
    ld   a, (vrBadBits)
    call PrintHexA
    call PrintFAIL
    ; detail row: first failure
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 8
    ld   hl, sVramFirst
    call PrintAt
    ld   a, (vdpType)
    or   a
    jr   z, vpNoBank
    ld   a, 'b'
    call CHPUT
    ld   a, (vrFailBank)
    add  a, '0'
    call CHPUT
    ld   a, ':'
    call CHPUT
vpNoBank:
    ld   hl, (vrFailAddr)
    call PrintHexHL
    ld   hl, sExpS
    call PrintStr
    ld   a, (vrFailExp)
    call PrintHexA
    ld   hl, sGotS
    call PrintStr
    ld   a, (vrFailGot)
    call PrintHexA
    ld   hl, sVramPh
    call PrintStr
    ld   a, (vrFailPh)
    call PrintDec8
    ld   hl, (vrRetFails)
    ld   a, h
    or   l
    jr   z, vpCmd
    ld   hl, sVramRet
    call PrintStr
vpCmd:
    ; ---- CMD row (V99x8 only) ----
    ld   a, (cmdRes)
    cp   3
    jr   z, vpSpr
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 1
    ld   hl, sCmdHdr
    call PrintAt
    ld   a, (cmdRes)
    or   a
    jr   nz, vpCmdBad
    ld   hl, sCmdOK
    call PrintStr
    call PrintOK
    jr   vpSpr
vpCmdBad:
    cp   2
    ld   hl, sCmdMis
    jr   nz, vpCmdP
    ld   hl, sCmdHang
vpCmdP:
    call PrintStr
    call PrintFAIL
vpSpr:
    ; ---- SPRITE row ----
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 1
    ld   hl, sSprHdr
    call PrintAt
    xor  a
    ld   (tmpA), a              ; error flags
    ld   a, (sprNoColl)
    and  0x20
    jr   z, vpSprA
    ld   a, (tmpA)
    or   0x01
    ld   (tmpA), a
vpSprA:
    ld   a, (sprColl)
    and  0x20
    jr   nz, vpSprB
    ld   a, (tmpA)
    or   0x02
    ld   (tmpA), a
vpSprB:
    ld   a, (sprFifth)
    and  0x40
    jr   z, vpSprC1
    ld   a, (sprFifth)
    and  0x1F
    cp   4
    jr   z, vpSprC
vpSprC1:
    ld   a, (tmpA)
    or   0x04
    ld   (tmpA), a
vpSprC:
    ld   hl, sSprColl
    call PrintStr
    ld   a, (tmpA)
    and  0x03
    ld   hl, sVOK
    jr   z, vpSprP1
    ld   hl, sVFAIL
vpSprP1:
    call PrintStr
    ld   hl, sSprFifth
    call PrintStr
    ld   a, (sprFifth)
    and  0x1F
    call PrintDec8
    ld   a, (tmpA)
    or   a
    jr   nz, vpSprBad
    call PrintOK
    ret
vpSprBad:
    call PrintFAIL
    ret

sVdpHdr:   db "VDP    ", 0
vdpTypeNames: dw sVdpTms, sVdp9938, sVdp9958
sVdpTms:   db "TMS  ", 0
sVdpUnk:   db "?    ", 0
sVdp9938:  db "9938 ", 0
sVdp9958:  db "9958 ", 0
sCmdHdr:   db "CMD    ", 0
sCmdOK:    db "HMMV+HMMM verificados", 0
sCmdMis:   db "HMMV/HMMM datos erroneos", 0
sCmdHang:  db "motor colgado (CE no baja)", 0
sVdpDead:  db "NO RESPONDE (sin F) S0=", 0
sVdpS0:    db "S0=", 0
sVdpF:     db " F:", 0
sVdpInt:   db "/s /INT:", 0
sVdpNoMon: db "n/d", 0
sHz2:      db "Hz", 0
sVramHdr:  db "VRAM   ", 0
sVramOK:   db "sin fallos", 0
sVramFails: db " fallos bits:", 0
sVramFirst: db "1o @", 0
sVramPh:   db " f", 0
sVramRet:  db " (ret)", 0
sSprHdr:   db "SPRITE ", 0
sSprColl:  db "colis:", 0
sSprFifth: db " 5o=", 0
