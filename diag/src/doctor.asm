; =============================================================================
;  doctor.asm  -  Goa'uld Doctor  -  the automatic summary screen
;
;  Funnel order (the first red line is usually the verdict):
;    RELOJ -> RESET -> /WAIT -> BIOS -> MAPA -> RAM -> VDP -> VRAM -> SPRITE
;    -> PPI -> PSG, then a couple of hints.
;  (sjasmplus: one instruction per line.)
; =============================================================================

; ===========================================================================
;  DoctorScreen  -  run every test first (progress words on row 1), then
;                   INITXT and paint the whole summary from the results.
;                   (In an emulator the VDP test trashes the real screen, so
;                   nothing is painted before all tests are done.)
; ===========================================================================
DoctorScreen:
    call INITXT
    ld   b, 1
    ld   c, 1
    ld   hl, sDocProbing
    call PrintAt
    ld   hl, sDocPBios
    call PrintStr
    call BiosTest
    ld   hl, sDocPMap
    call PrintStr
    call DoMemMap
    ld   hl, sDocPRam
    call PrintStr
    call RamTestsAll
    ld   hl, sDocPMapper
    call PrintStr
    call MapperTest
    ld   hl, sDocPVdp
    call PrintStr
    call VdpTest
    call PpiTest
    call PsgTest
    ld   hl, sDocPRtc
    call PrintStr
    call RtcTest
    ; ---------------- paint ----------------
    call INITXT
    ld   b, 1
    ld   c, 1
    ld   hl, sDocTitle
    call PrintAt
    ld   a, (monPresent)
    or   a
    jr   z, dsNoMon
    ld   hl, sDocMon
    call PrintStr
    jr   dsTitleDone
dsNoMon:
    ld   hl, sDocNoMon
    call PrintStr
dsTitleDone:
    ld   a, 2
    ld   (row), a
    call Stage0Print            ; row 2 (+1 detail row when bad)
    ld   a, (row)
    inc  a
    ld   (row), a
    call BiosPrint              ; 2 rows
    ld   a, (row)
    inc  a
    ld   (row), a
    call PrintMemMap            ; 4 rows
    ld   a, (row)
    inc  a
    ld   (row), a
    call RamRowsPrint           ; 1-4 rows (grouped per slot)
    call MapperPrint            ; 1-2 rows
    call VdpPrint               ; 3-4 rows
    ld   a, (row)
    inc  a
    ld   (row), a
    call PpiPrint
    ld   a, (row)
    inc  a
    ld   (row), a
    call PsgPrint
    ld   a, (row)
    inc  a
    ld   (row), a
    call RtcPrint
    ; hints: one blank row before them when the screen has room
    ld   a, (row)
    inc  a
    cp   22
    jr   nc, dsHintRow
    inc  a
dsHintRow:
    ld   (row), a
    call Hints
    ld   b, 24
    ld   c, 1
    ld   hl, sDocFooter
    call PrintAt
    ret

sDocProbing: db "GOAULD DOCTOR probando: ", 0
sDocPBios:   db "BIOS ", 0
sDocPMap:    db "MAPA ", 0
sDocPRam:    db "RAM ", 0
sDocPVdp:    db "VDP ", 0
sDocPMapper: db "MAPPER ", 0
sDocPRtc:    db "RTC ", 0

; ===========================================================================
;  Stage0Print  -  one row: "RELOJ 3579.6k placa RST H/1 WT H     OK"
;                  plus one detail row when something is wrong
; ===========================================================================
Stage0Print:
    ld   a, (monPresent)
    or   a
    jr   nz, s0Mon
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sS0NoMon
    call PrintAt
    ret
s0Mon:
    xor  a
    ld   (tmpB), a              ; failure flags: 1 clk 2 reset 4 wait
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sS0Clk
    call PrintAt
    ld   a, 0x16
    call MonReadReg
    ld   l, a
    in   a, (MON_DAT)           ; 0x17 (auto-increment)
    ld   h, a
    ld   (tmpHL), hl
    ld   a, h
    or   l
    jr   nz, s0ClkVal
    ld   hl, sS0None
    call PrintStr
    ld   a, 1
    ld   (tmpB), a
    jr   s0ClkSrc
s0ClkVal:
    push hl
    call Div10
    push af
    call PrintDec16
    ld   a, '.'
    call CHPUT
    pop  af
    add  a, '0'
    call CHPUT
    pop  hl
    ld   a, 'k'
    call CHPUT
    ; 3500.0 .. 3650.0 kHz -> 35000..36500
    ld   hl, (tmpHL)
    ld   de, 35000
    or   a
    sbc  hl, de
    jr   c, s0ClkBad
    ld   de, 1500
    or   a
    sbc  hl, de
    jr   c, s0ClkSrc
s0ClkBad:
    ld   a, 1
    ld   (tmpB), a
s0ClkSrc:
    ld   a, 0x15
    call MonReadReg
    ld   (tmpA), a
    and  0x02
    ld   hl, sS0Ext
    jr   z, s0ClkSrcP
    ld   hl, sS0Int
    ld   a, 1
    ld   (tmpB), a
s0ClkSrcP:
    call PrintStr
    ; --- RST level / edges ---
    ld   hl, sS0Rst
    call PrintStr
    ld   a, (tmpA)
    and  0x04
    ld   a, 'H'
    jr   nz, s0RstLvl
    ld   a, 'L'
    push af
    ld   a, (tmpB)
    or   2
    ld   (tmpB), a
    pop  af
s0RstLvl:
    call CHPUT
    ld   a, '/'
    call CHPUT
    ld   a, 0x18
    call MonReadReg
    call PrintDec8
    ; --- WAIT level ---
    ld   hl, sS0Wait
    call PrintStr
    ld   a, (tmpA)
    and  0x10
    ld   a, 'H'
    jr   nz, s0WaitLvl
    ld   a, 'L'
s0WaitLvl:
    call CHPUT
    ld   a, (tmpA)
    and  0x08
    jr   z, s0Verdict
    ld   a, (tmpB)
    or   4
    ld   (tmpB), a
s0Verdict:
    ld   a, (tmpB)
    or   a
    jr   nz, s0Bad
    call PrintOK
    ret
s0Bad:
    call PrintFAIL
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   b, a
    ld   c, 8
    call SetPos
    ld   a, (tmpB)
    and  1
    jr   z, s0BadRst
    ld   hl, sS0NoClk
    call PrintStr
s0BadRst:
    ld   a, (tmpB)
    and  2
    jr   z, s0BadWait
    ld   hl, sS0RstLow
    call PrintStr
s0BadWait:
    ld   a, (tmpB)
    and  4
    ret  z
    ld   hl, sS0WaitStuck
    call PrintStr
    ret

sDocTitle:   db "GOAULD DOCTOR v1.0  ", 0
sDocMon:     db "monitor v2", 0
sDocNoMon:   db "SIN MONITOR (emul.)", 0
sS0NoMon:    db "RELOJ/RESET/WAIT: n/d sin monitor", 0
sS0Clk:      db "RELOJ  ", 0
sS0None:     db "0.0k", 0
sS0Ext:      db " placa", 0
sS0Int:      db " INT!", 0
sS0NoClk:    db "sin reloj: VDP/cristal ", 0
sS0Rst:      db " RST ", 0
sS0RstLow:   db "RESET a 0 ", 0
sS0Wait:     db " WT ", 0
sS0WaitStuck: db "/WAIT pegado", 0
sDocFooter:  db "SPC V X=ram3 W=mart B=bios K=tec M=bus", 0

; ===========================================================================
;  RamTestsAll  -  every map cell marked RAM (primary 0-3 x subslot x page):
;                  test it and store the result in ramRes (max 4 entries):
;                  [0]=slot id [1]=page [2]=status 0 ok/1 fail/2 vanished/3 own
;                  [3..4]=addr [5]=exp [6]=got [7]=phase
; ===========================================================================
RamTestsAll:
    xor  a
    ld   (ramResN), a
    ld   (mmPri), a
rtaSlot:
    xor  a
    ld   (mmSub), a
rtaSub:
    call MakeSlotId
    ld   (mmSlotId), a
    xor  a
    ld   (mmPage), a
rtaPage:
    ld   a, (ramResN)
    cp   4
    ret  nc
    call MapCellPtr
    ld   a, (hl)
    cp   MMAP_RAM
    jr   nz, rtaNext
    call RamTestOne
rtaNext:
    ld   a, (mmPage)
    inc  a
    ld   (mmPage), a
    cp   4
    jr   c, rtaPage
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, rtaNextSlot
    call SubSameSkip
    jr   z, rtaNextSlot         ; identical subslots: sub 0 was enough
    ld   a, (mmSub)
    inc  a
    ld   (mmSub), a
    cp   4
    jr   c, rtaSub
rtaNextSlot:
    ld   a, (mmPri)
    inc  a
    ld   (mmPri), a
    cp   4
    jr   c, rtaSlot
    ret

; RamTestOne - mmSlotId/mmPage -> run and append to ramRes
RamTestOne:
    ; IX = &ramRes[n]
    ld   a, (ramResN)
    add  a, a
    add  a, a
    add  a, a
    ld   c, a
    ld   b, 0
    ld   ix, ramRes
    add  ix, bc
    ld   a, (mmSlotId)
    call DisplaySlotId
    ld   (ix+0), a
    ld   a, (mmPage)
    ld   (ix+1), a
    cp   3
    jr   z, rtoP3
    call RelocTestPage
    ld   a, (rsSlotOK)
    or   a
    jr   nz, rtoOK
    ld   (ix+2), 1
    ld   hl, (rsFailAddr)
    ld   (ix+3), l
    ld   (ix+4), h
    ld   a, (rsFailExp)
    ld   (ix+5), a
    ld   a, (rsFailGot)
    ld   (ix+6), a
    ld   (ix+7), 0
    jr   rtoStore
rtoOK:
    ld   (ix+2), 0
    jr   rtoStore
rtoP3:
    ; Emulator guard: page 3 of the slot our stack lives in cannot be tested
    ; from here (on the Goa'uld page 3 is its internal mapper: always ok).
    ld   a, (monPresent)
    or   a
    jr   nz, rtoP3Run
    ld   a, (mmSlotId)
    call OwnPage3
    jr   nz, rtoP3Run
    ld   (ix+2), 3
    jr   rtoStore
rtoP3Run:
    ld   a, 3
    ld   (p3Page), a
    ld   a, (mmSlotId)
    push ix
    call RamTestStackless       ; clobbers IX/IY
    pop  ix
    ld   a, (p3Found)
    or   a
    jr   nz, rtoP3Found
    ld   (ix+2), 2
    jr   rtoStore
rtoP3Found:
    ld   a, (p3Phase)
    or   a
    jr   z, rtoOK
    ld   (ix+2), 1
    ld   hl, (p3FailAddr)
    ld   (ix+3), l
    ld   (ix+4), h
    ld   a, (p3FailExp)
    ld   (ix+5), a
    ld   a, (p3FailGot)
    ld   (ix+6), a
    ld   a, (p3Phase)
    ld   (ix+7), a
rtoStore:
    ld   a, (ramResN)
    inc  a
    ld   (ramResN), a
    ret

; ===========================================================================
;  RamRowsPrint  -  one row per ramRes entry starting at (row):
;    "RAM  S3-2 p3 16383 b                 OK"
;    "RAM  S0 p3 FALLO @C123 e=00 g=01 f2"
; ===========================================================================
RamRowsPrint:
    ld   a, (ramResN)
    or   a
    jr   nz, rrpLoopInit
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sRamNone
    call PrintAt
    call PrintFAIL
    ld   a, (row)
    inc  a
    ld   (row), a
    ret
rrpLoopInit:
    ld   ix, ramRes
    ld   a, (ramResN)
    ld   (tmpB), a              ; entries left
rrpLoop:
    ; ---- group: following entries of the same slot with the same status
    ;      and consecutive pages share this row ("p0-p2") ----
    ld   a, 1
    ld   (grpN), a
    ld   a, (ix+1)
    ld   (grpEnd), a
    push ix
    pop  hl
    ld   de, 8
rrpGrp:
    ld   a, (tmpB)
    ld   b, a
    ld   a, (grpN)
    cp   b
    jr   nc, rrpGrpDone
    add  hl, de
    ld   a, (ix+0)
    cp   (hl)
    jr   nz, rrpGrpDone
    inc  hl
    inc  hl
    ld   a, (ix+2)
    cp   (hl)
    jr   nz, rrpGrpDone
    dec  hl
    ld   a, (grpEnd)
    inc  a
    cp   (hl)
    jr   nz, rrpGrpDone
    ld   (grpEnd), a
    dec  hl
    ld   a, (grpN)
    inc  a
    ld   (grpN), a
    jr   rrpGrp
rrpGrpDone:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    ld   hl, sRamHdr2
    call PrintAt
    ld   a, (ix+0)
    push ix
    call PrintSlotId
    pop  ix
    ld   hl, sRamPag
    call PrintStr
    ld   a, (ix+1)
    add  a, '0'
    call CHPUT
    ld   a, (grpN)
    cp   1
    jr   z, rrpOnePage
    ld   a, '-'
    call CHPUT
    ld   a, 'p'
    call CHPUT
    ld   a, (grpEnd)
    add  a, '0'
    call CHPUT
rrpOnePage:
    call PrintSpace
    ld   a, (ix+2)
    or   a
    jr   nz, rrpNotOK
    ld   a, (grpN)
    cp   1
    jr   z, rrpOneSize
    add  a, a
    add  a, a
    add  a, a
    add  a, a                   ; pages x 16 KB
    call PrintDec8
    ld   hl, sRamKB
    call PrintStr
    call PrintOK
    jr   rrpNext
rrpOneSize:
    ld   hl, sRam16384
    ld   a, (ix+1)
    cp   3
    jr   nz, rrpSize
    ld   hl, sRam16383
rrpSize:
    call PrintStr
    call PrintOK
    jr   rrpNext
rrpNotOK:
    cp   2
    jr   nz, rrpNot2
    ld   hl, sRamVanish
    call PrintStr
    call PrintFAIL
    jr   rrpNext
rrpNot2:
    cp   3
    jr   nz, rrpFail
    ld   hl, sRamOwn
    call PrintStr
    call PrintNA
    jr   rrpNext
rrpFail:
    ld   hl, sRamFail2
    call PrintStr
    ld   l, (ix+3)
    ld   h, (ix+4)
    call PrintHexHL
    ld   hl, sExpS
    call PrintStr
    ld   a, (ix+5)
    call PrintHexA
    ld   hl, sGotS
    call PrintStr
    ld   a, (ix+6)
    call PrintHexA
    ld   hl, sRamPh
    call PrintStr
    ld   a, (ix+7)
    call PrintDec8              ; "FALLO" is the verdict (row is full)
rrpNext:
    ld   a, (row)
    inc  a
    ld   (row), a
    ld   a, (grpN)
    ld   b, a
    add  a, a
    add  a, a
    add  a, a
    ld   c, a
    ld   a, (tmpB)
    sub  b
    ld   (tmpB), a
    ld   b, 0
    add  ix, bc
    or   a
    jp   nz, rrpLoop
    ret

sRamHdr2:   db "RAM  ", 0
sRamPag:    db " p", 0
sRam16384:  db "16384 b", 0
sRam16383:  db "16383 b", 0
sRamKB:     db " KB", 0
sRamFail2:   db "FALLO @", 0
sRamPh:     db " f", 0
sExpS:      db " e=", 0
sGotS:      db " g=", 0
sRamVanish: db "desaparecio al probar", 0
sRamOwn:    db "= RAM del sistema", 0
sRamNone:   db "RAM    ninguna encontrada", 0

; ===========================================================================
;  Hints  -  up to 2 rows of advice derived from the results
; ===========================================================================
Hints:
    ld   a, (row)
    ld   b, a
    ld   c, 1
    call SetPos
    ; 1. no clock
    ld   a, (monPresent)
    or   a
    jr   z, hNoClkSkip
    ld   hl, (tmpHL)            ; last clock reading (Stage0Print)
    ld   a, h
    or   l
    jr   nz, hNoClkSkip
    ld   hl, sHintClk
    call PrintStr
    ret
hNoClkSkip:
    ; 2. BIOS mute + no RAM + VDP dead -> slot 0 / power
    call BiosVerdict
    cp   1
    jr   nz, hBus
    ld   a, (vdpAlive)
    or   a
    jr   nz, hBus
    ld   hl, sHintDead
    call PrintStr
    ret
hBus:
    ; 2b. a data line that never moved while the board ROM drove the bus
    ;     (ROM not mute, 1-3 lines): everything else fails because of it.
    xor  a
    ld   (tmpB), a              ; stuck mask
    ld   a, (monPresent)
    or   a
    jr   z, hStuck
    call BiosVerdict
    cp   1
    jr   z, hStuck
    ld   a, (biosDead + 0)
    ld   c, a
    ld   a, (biosDead + 1)
    or   c
    jr   z, hStuck
    ld   (tmpB), a
    call AnyRamOk               ; some RAM block passed: the bus is fine,
    ld   hl, sHintBus           ; the line dies between the ROM and the bus
    jr   nz, hBusTxt
    xor  a
    ld   (tmpB), a
    ld   hl, sHintRomLn
hBusTxt:
    call PrintStr
    ld   a, (biosDead + 1)      ; never LOW -> stuck at 1
    ld   e, '1'
    call HintBusBits
    ld   a, (biosDead + 0)      ; never HIGH -> stuck at 0
    ld   e, '0'
    call HintBusBits
    call AnyRamOk
    jr   nz, hBusEnd
    ld   hl, sHintRomLn2
    call PrintStr
hBusEnd:
    call HintNext
hStuck:
    ; 2c. keyboards: each source alone at boot - noise (-> dropped) or stuck keys
    ld   hl, physStuck
    ld   a, (physNoise)
    ld   de, sHintKbdBoard
    call HintKbdSource
    ld   hl, usbStuck
    ld   a, (usbNoise)
    ld   de, sHintKbdUsb
    call HintKbdSource
hVram:
    ; 3. VRAM bits -> chip attribution (2 x 4416 on a TMS9118), unless the
    ;    bad bits are just the stuck bus lines
    ld   a, (tmpB)
    cpl
    ld   c, a
    ld   a, (vrBadBits)
    and  c
    jr   z, hRamVram
    ld   hl, sHintVramA
    call PrintStr
    ld   a, (vrBadBits)
    and  0x0F
    jr   z, hVramHi
    ld   hl, sHintD03
    call PrintStr
hVramHi:
    ld   a, (vrBadBits)
    and  0xF0
    jr   z, hVramDone
    ld   hl, sHintD47
    call PrintStr
hVramDone:
    ; 128K boards pair the chips per 64K half: say which half failed first
    ld   a, (vramKB)
    cp   128
    jr   nz, hVramDone2
    ld   hl, sHintHalfLo
    ld   a, (vrFailBank)
    cp   4
    jr   c, hVramHalf
    ld   hl, sHintHalfHi
hVramHalf:
    call PrintStr
hVramDone2:
    call HintNext
hRamVram:
    ; 3b. a page 3 that reads (not FF) but does not take writes: RAM with no
    ;     VCC/GND or /W - what a starved 4416 looks like (real HB-10 case:
    ;     2.6 V on pin 9).  ROMs at C000-FFFF are rare on MSX.
    call AnyRomPage3
    jr   nz, hRamVram2
    ld   hl, sHintRamRO
    call PrintStr
    call HintNext
hRamVram2:
    ; 4. RAM and VRAM both failing -> DRAM supply
    ld   a, (vrBadBits)
    or   a
    ret  z
    ld   a, (p3Found)
    or   a
    ret  z
    ld   a, (p3Phase)
    or   a
    ret  z
    ld   hl, sHintDram
    call PrintStr
    ret

; HintNext - next row for a hint; when row 24 (the footer) is reached the
;            remaining hints are dropped: returns to the caller of Hints
HintNext:
    ld   a, (row)
    inc  a
    ld   (row), a
    cp   24
    jr   c, hnRoom
    pop  hl
    ret
hnRoom:
    ld   b, a
    ld   c, 1
    jp   SetPos

sHintClk:   db "> Sin reloj Z80: VDP, cristal 10.7M o 5V", 0
sHintBus:   db "> BUS DATOS pegado:", 0
sHintRomLn: db "> Solo la ROM:", 0
sHintRomLn2: db " (chip o pista)", 0
sHintKbdBoard: db "> Teclado placa: ", 0
sHintKbdUsb:   db "> Teclado USB: ", 0
sHintKbdNoise: db " cambios/s, ignorado", 0
sHintKbdStuck: db "pegada f/b", 0

; HintKbdSource - HL = 11-byte stuck image, A = noise count, DE = name.
;   Prints "> Teclado X: 26 cambios/s, ignorado" or "> Teclado X: pegada
;   f/b 8/0 3/1" (up to 4 pairs) on its own row; nothing if all is quiet.
HintKbdSource:
    or   a
    jr   nz, hksNoise
    push hl
    ld   b, 11
hksAny:
    ld   a, (hl)
    inc  a
    jr   nz, hksStuck
    inc  hl
    djnz hksAny
    pop  hl
    ret
hksStuck:
    pop  hl
    push hl
    ex   de, hl
    call PrintStr
    ld   hl, sHintKbdStuck
    call PrintStr
    pop  hl
    call PrintStuckPairs
    jp   HintNext
hksNoise:
    push af
    ex   de, hl
    call PrintStr
    pop  af
    add  a, a                   ; 25 scans in 0.5 s -> per second
    jr   nc, hksPerSec
    ld   a, 255
hksPerSec:
    call PrintDec8
    ld   hl, sHintKbdNoise
    call PrintStr
    jp   HintNext

; PrintStuckPairs - HL = stuck image: " r/b" for every 0 bit, max 4
PrintStuckPairs:
    ld   d, 0                   ; row
    ld   e, 0                   ; pairs printed
pspRow:
    ld   a, (hl)
    cpl
    ld   b, a                   ; 1 = stuck
    ld   c, 0                   ; bit
pspBit:
    srl  b
    jr   nc, pspBitNext
    ld   a, e
    cp   4
    ret  nc
    inc  e
    push bc
    push de
    push hl
    ld   a, ' '
    call CHPUT
    ld   a, d
    call PrintDec8
    ld   a, '/'
    call CHPUT
    pop  hl
    pop  de
    pop  bc
    push bc
    push de
    push hl
    ld   a, c
    add  a, '0'
    call CHPUT
    pop  hl
    pop  de
    pop  bc
pspBitNext:
    inc  c
    ld   a, b
    or   a
    jr   nz, pspBit
    inc  hl
    inc  d
    ld   a, d
    cp   11
    jr   c, pspRow
    ret

; HintBusBits - A = mask, E = level char: prints " Dn=<E>" per set bit
HintBusBits:
    ld   d, 0
hbbLoop:
    rrca
    jr   nc, hbbNext
    push af
    push de
    ld   a, ' '
    call CHPUT
    ld   a, 'D'
    call CHPUT
    ld   a, d
    add  a, '0'
    call CHPUT
    ld   a, '='
    call CHPUT
    ld   a, e
    call CHPUT
    pop  de
    pop  af
hbbNext:
    inc  d
    ld   c, a
    ld   a, d
    cp   8
    ld   a, c
    jr   c, hbbLoop
    ret
sHintDead:  db "> BIOS muda y VDP mudo: 5V, reset, SLTSL", 0
sHintVramA: db "> VRAM: nibble ", 0
sHintD03:   db "D0-D3 ", 0
sHintD47:   db "D4-D7 ", 0
sHintHalfLo: db "0-64K", 0
sHintHalfHi: db "64-128K", 0
sHintDram:  db "> RAM y VRAM fallan: alimentacion DRAM?", 0
sHintRamRO: db "> pag3 lee y no escribe: VCC/GND RAM, /W", 0

; AnyRamOk - NZ if no RAM block passed, Z if at least one did (status 0)
AnyRamOk:
    ld   a, (ramResN)
    or   a
    jr   z, arkNone
    ld   b, a
    ld   hl, ramRes + 2
    ld   de, 8
arkLoop:
    ld   a, (hl)
    or   a
    ret  z
    add  hl, de
    djnz arkLoop
arkNone:
    or   1                      ; NZ
    ret

; AnyRomPage3 - Z if some probed slot has ROM in page 3 with page 2 empty
;               (a ROM living only at C000-FFFF does not exist on MSX)
AnyRomPage3:
    xor  a
    ld   (mmPri), a
arpSlot:
    xor  a
    ld   (mmSub), a
arpSub:
    call MakeSlotId
    ld   (mmSlotId), a
    ld   a, 3
    ld   (mmPage), a
    call MapCellPtr
    ld   a, (hl)
    cp   MMAP_ROM
    jr   nz, arpNotRom
    dec  hl                     ; page 2 of the same slot: a real ROM there
    ld   a, (hl)                ; means a mirrored/32K ROM, not starved RAM
    cp   MMAP_EMPTY
    ret  z
arpNotRom:
    ld   a, (mmPri)
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, arpNextSlot
    ld   a, (mmSub)
    inc  a
    ld   (mmSub), a
    cp   4
    jr   c, arpSub
arpNextSlot:
    ld   a, (mmPri)
    inc  a
    ld   (mmPri), a
    cp   4
    jr   c, arpSlot
    or   1                      ; NZ: none
    ret

; ===========================================================================
;  StacklessSelfTest  -  key T: run RamTestStackless on PAGE 2 of the slot
;                        currently mapped in page 3 (Goa'uld: its own mapper;
;                        emulator: the system RAM) - validates the stackless
;                        code path on known-good RAM.
; ===========================================================================
StacklessSelfTest:
    call INITXT
    ld   b, 1
    ld   c, 1
    ld   hl, sStTitle
    call PrintAt
    in   a, (0xA8)
    rlca
    rlca
    and  0x03
    ld   (mmPri), a
    ld   c, a
    ld   b, 0
    ld   hl, expFlags
    add  hl, bc
    ld   a, (hl)
    or   a
    jr   z, stNotExp
    ld   hl, subImg
    add  hl, bc
    ld   a, (hl)
    rlca
    rlca
    and  0x03
    ld   (mmSub), a
stNotExp:
    call MakeSlotId
    ld   (tmpA), a
    call PrintSlotId
    ld   a, 2
    ld   (p3Page), a
    ld   a, (tmpA)
    call RamTestStackless
    ld   a, 3
    ld   (row), a
    ld   b, 3
    ld   c, 1
    ld   hl, sStRes
    call PrintAt
    ld   a, (p3Found)
    or   a
    jr   nz, stFound
    ld   hl, sRamVanish
    call PrintStr
    call PrintFAIL
    jr   stKey
stFound:
    ld   a, (p3Phase)
    or   a
    jr   nz, stFail
    ld   hl, sRam16384
    call PrintStr
    call PrintOK
    jr   stKey
stFail:
    ld   hl, sRamFail2
    call PrintStr
    ld   hl, (p3FailAddr)
    call PrintHexHL
    ld   hl, sExpS
    call PrintStr
    ld   a, (p3FailExp)
    call PrintHexA
    ld   hl, sGotS
    call PrintStr
    ld   a, (p3FailGot)
    call PrintHexA
    ld   hl, sRamPh
    call PrintStr
    ld   a, (p3Phase)
    call PrintDec8
stKey:
    ld   b, 24
    ld   c, 1
    ld   hl, sRSPressKey
    call PrintAt
    call WaitKeyEdge
    ret
sStTitle: db "AUTOTEST rutina sin pila, pag2 de ", 0
sStRes:   db "8000-BFFF: ", 0
