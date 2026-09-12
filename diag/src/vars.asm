; =============================================================================
;  vars.asm  -  Goa'uld Doctor  -  RAM layout (page 3 of the Goa'uld's own
;               mapper RAM, 0xC000-0xF1FF; BIOS work area starts at 0xF380)
;  Included LAST by diag.asm: only the location counter moves, nothing is
;  emitted into the ROM image.
;
;  0xC000-0xC0FF  variables (this file)
;  0xC100-0xC17F  internal RAM pattern test region (diag_extra.asm)
;  0xC400-0xC7FF  CRC32 table, 4 planes of 256 bytes (test_bios.asm)
;  0xC800-0xCFFF  relocated code (reloc.asm, runs from RAM)
;  0xD000-0xD07F  first 128 bytes of the board BIOS (captured)
;  0xD100-0xD1FF  keyboard matrix / scratch (RTC RAM backup at 0xD180)
;  0xF200         stack top (grows down)
; =============================================================================

CRC_TABLE     equ 0xC400      ; 4 x 256 bytes: T0 @C400 T1 @C500 T2 @C600 T3 @C700
RELOC_BASE    equ 0xC800      ; relocated code lands here
BIOS_HEAD     equ 0xD000      ; board BIOS bytes 0x0000-0x007F
KBD_MATRIX    equ 0xD100      ; 11 rows of the keyboard matrix
SCRATCH       equ 0xD180
physStuck     equ 0xD1C0      ; 11 bytes: board keyboard matrix at boot (0 = stuck)
usbStuck      equ 0xD1D0      ; 11 bytes: USB keyboard matrix at boot
memMap        equ 0xD200      ; 64 cells: primary*16 + subslot*4 + page

    ORG RAM_BASE

; ---- diag.asm dashboard ----
mon_buf:      ds  0x21, 0   ; monitor register snapshot (regs 0x00-0x20)
dbDeadLo:     ds  1, 0
dbDeadHi:     ds  1, 0
dbS0:         ds  1, 0
dbS1:         ds  1, 0
ctrlByte:     ds  1, 0
slByte0:      ds  1, 0
slByte1:      ds  1, 0
ramOK:        ds  1, 0
ramFailAddr:  dw  0
ramFailBits:  ds  1, 0
patCurr:      ds  1, 0
w1pat:        ds  1, 0
w1cnt:        ds  1, 0

; ---- diag_ramscan.asm (page-2 slot scan) ----
rsOrigSlot:  ds  1, 0
rsCurSlot:   ds  1, 0
rsRow:       ds  1, 0
rsSlotOK:    ds  1, 0
rsFailAddr:  dw  0
rsFailExp:   ds  1, 0
rsFailGot:   ds  1, 0
rsFailXOR:   ds  1, 0
rsBitLo:     ds  1, 0
rsBitHi:     ds  1, 0
rsB0:        ds  1, 0
rsB1:        ds  1, 0

; ---- common ----
monPresent:  ds  1, 0       ; 1 = bus_monitor v2 answered (SIG 0x42, VER>=2)
mySlot:      ds  1, 0       ; slot id of THIS ROM (page 1), ENASLT format
tmpA:        ds  1, 0
tmpB:        ds  1, 0
tmpHL:       dw  0
row:         ds  1, 0       ; current print row for the summary

; ---- BIOS test ----
biosCRC:     ds  4, 0       ; CRC32 little-endian (b0 b1 b2 b3)
biosNonFF:   dw  0          ; count of bytes != 0xFF (saturating)
biosDead:    ds  2, 0       ; D_DEAD_LO / D_DEAD_HI captured during the read
biosName:    dw  0          ; pointer to name string or 0

; ---- memory map / RAM tests ----
mmSlotId:    ds  1, 0       ; slot id under probe/test (ENASLT format)
mmPri:       ds  1, 0       ; loop: primary
mmSub:       ds  1, 0       ; loop: subslot
mmPage:      ds  1, 0
expFlags:    ds  4, 0       ; 1 = primary slot has an expansion register
subImg:      ds  4, 0       ; our image of each expansion register
subSame:     ds  4, 0       ; 1 = expanded but all subslot rows identical
rtSubSaved:  ds  1, 0
rtBase:      dw  0          ; base address of the page under test (pages 0-2)
rtSlotId:    ds  1, 0
rtSlotSaved: ds  1, 0
p3SlotId:    ds  1, 0       ; page-3 stackless test: slot id
p3Phase:     ds  1, 0       ; 0 = pass, else phase number of first failure
p3FailAddr:  dw  0
p3FailExp:   ds  1, 0
p3FailGot:   ds  1, 0
p3Found:     ds  1, 0       ; 1 = RAM present in page 3 of that slot
p3Count:     dw  0          ; bytes tested
p3Page:      ds  1, 0       ; 2 or 3
ramResN:     ds  1, 0       ; entries used in ramRes
ramRes:      ds  32, 0      ; 4 x {slot,page,status,addrL,addrH,exp,got,phase}

; ---- VDP test ----
vdpAlive:    ds  1, 0       ; 1 = status register answers (F flag toggles)
vdpS0:       ds  1, 0       ; first raw S#0 read
vdpFrames:   ds  1, 0       ; F-flag sets in ~1 s
vdpIntRate:  ds  1, 0       ; monitor INT_RATE while IE=1 (0xFF = no monitor)
vrFails:     dw  0          ; VRAM byte failures (saturating)
vrBadBits:   ds  1, 0       ; OR of all XOR (expected^got)
vrFailAddr:  dw  0          ; first failing VRAM address
vrFailExp:   ds  1, 0
vrFailGot:   ds  1, 0
vrPhase:     ds  1, 0       ; phase currently running
vrFailPh:    ds  1, 0       ; phase of the first failure (1=addr 2..5=patterns 6=ret)
vrRetFails:  dw  0          ; failures in the retention phase only
sprNoColl:   ds  1, 0       ; S#0 with sprites apart (C must be 0)
sprColl:     ds  1, 0       ; S#0 with sprites overlapping (C must be 1)
sprFifth:    ds  1, 0       ; S#0 with 5 sprites on a line (5S=1, num=4)
vdpTmp:      ds  1, 0
vdpType:     ds  1, 0       ; 0 TMS, 1 V9938, 2 V9958
vdpProbe:    ds  1, 0       ; type probe read-back: 5A V99x8, A5 TMS, else ?
vramKB:      ds  1, 0       ; 16 / 64 / 128
vrBanks:     ds  1, 0       ; vramKB / 16
vrBank:      ds  1, 0       ; bank under test
vrBankPat:   ds  1, 0       ; bank*0x33 for the address phase
vrFailBank:  ds  1, 0
vrFillVal:   ds  1, 0
vdpR9:       ds  1, 0       ; R#9 written on a V99x8 (0x02 = 50 Hz)
cmdRes:      ds  1, 0       ; 0 ok 1 mismatch 2 timeout 3 n/a
vdpTO:       ds  1, 0       ; 1 = a wait-for-frame timed out

; ---- PPI / PSG ----
ppiA8exp:    ds  1, 0
ppiA8got:    ds  1, 0
ppiAAexp:    ds  1, 0
ppiAAgot:    ds  1, 0
ppiA9:       ds  1, 0
psgFail:     dw  0          ; bit n = register n mismatched
psgExp:      ds  1, 0
psgGot:      ds  1, 0
psgReg:      ds  1, 0
psgPass:     ds  1, 0

; ---- mapper (test_map_rtc.asm) ----
mpResN:      ds  1, 0
mpRes:       ds  16, 0      ; 2 x {slot,count,status,seg,addrL,addrH,exp,got}
mpSeg:       ds  1, 0
mpN:         ds  1, 0       ; segments covered (min(count,64))

; ---- RTC ----
rtcStatus:   ds  1, 0       ; 0 ok / 2 RAM nibble / 3 stopped
rtcMode:     ds  1, 0
rtcSec0:     ds  1, 0
rtcSec1:     ds  1, 0
rtcFailReg:  ds  1, 0
rtcFailExp:  ds  1, 0
rtcFailGot:  ds  1, 0

; ---- RAM rows (grouping) ----
grpN:        ds  1, 0
grpEnd:      ds  1, 0

; ---- keyboard by edges ----
keyPrev:     ds  11, 0      ; last matrix seen by PollKeyEdge
keyChg:      ds  1, 0
keyRow:      ds  1, 0
keyBit:      ds  1, 0
kbdQuiet:    ds  1, 0       ; polls without any matrix change
physNoise:   ds  1, 0       ; boot: matrix changes by itself, board keyboard alone
usbNoise:    ds  1, 0       ; same, USB keyboard alone
kbdCtl:      ds  1, 0       ; CTL_USBOFF/CTL_PHYSOFF applied by ScanMatrix

; ---- keyboard screen ----
kbdRow:      ds  1, 0
kbdCol:      ds  1, 0
kbdTick:     ds  1, 0

varsEnd:
    IF varsEnd > 0xC100
        ERROR "variables overflow 0xC100"
    ENDIF
