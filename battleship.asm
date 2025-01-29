.include "nesdefs.inc"

; RAM addresses
OAMBUFFER = $200

; Controller button bits
BUTTON_A      = 1 << 7
BUTTON_B      = 1 << 6
BUTTON_SELECT = 1 << 5
BUTTON_START  = 1 << 4
BUTTON_UP     = 1 << 3
BUTTON_DOWN   = 1 << 2
BUTTON_LEFT   = 1 << 1
BUTTON_RIGHT  = 1 << 0

NUM_BUTTONS   = 8

.segment "HEADER"
.byte "NES"
.byte $1a
.byte $02 ; 2 * 16KB PRG ROM
.byte $01 ; 1 * 8KB CHR ROM
.byte %00000000 ; mapper and mirroring
.byte $00
.byte $00
.byte $00
.byte $00
.byte $00, $00, $00, $00, $00 ; filler bytes

.segment "ZEROPAGE" ; starts at $02!
.res 14 ; reserve $00-$0F for general use
framestate: .res 1 ; Bit 7 = 1 means NMI has occurred and we can do game logic
buttons1: .res 1
buttons2: .res 1
hey: .res 1
sexy: .res 1

.segment "STARTUP"
.proc Reset
    SEI ; Disables all interrupts
    CLD ; disable decimal mode

    ; Disable sound IRQ
    LDX #$40
    STX $4017 ; APU frame counter

    ; Initialize the stack register
    LDX #$FF
    TXS

    ; Zero out the PPU registers
    INX
    STX PPUCTRL
    STX PPUMASK

    STX $4010

:   ; first vblank wait
    BIT PPUSTATUS
    BPL :-

    TXA

ClearMem:
    STA $0000, X ; $0000 => $00FF
    STA $0100, X ; $0100 => $01FF
    STA $0300, X
    STA $0400, X
    STA $0500, X
    STA $0600, X
    STA $0700, X
    ; 200-2FF is for the OAM buffer; init to off-screen
    LDA #$FF
    STA $0200, X ; $0200 => $02FF
    LDA #$00
    INX
    BNE ClearMem    
; wait for vblank
:
    BIT PPUSTATUS
    BPL :-

    LDA #>OAMBUFFER
    STA OAMDMA
    NOP ; why is this here?

    ; $3F00 - $3F1F (palette RAM)
    LDA #$3F
    STA PPUADDR
    LDA #$00
    STA PPUADDR

    LDX #$55
    STX hey
    INX
    STX sexy
.endproc

    LDA #<PaletteData
    LDX #>PaletteData
    JSR LoadPalette

    LDA #<WorldData
    LDX #>WorldData
    JSR LoadNametable

.proc LoadSprites
    LDX #$00
    LDY #$00    
:
    LDA SpriteData, X
    STA $0200, X
    INX
    CPX #$20
    BNE :-
.endproc

; Enable interrupts
    CLI

    LDA #%10011000 ; enable NMI, background = 2nd char table ($1000); sprites = $1000
    STA PPUCTRL
    ; Enabling sprites and background for left-most 8 pixels
    ; Enable sprites and background
    LDA #%00011110
    STA PPUMASK

MainLoop:
    ; Check if NMI has occurred
    BIT framestate
    BPL MainLoop
    LDA #0
    STA framestate

    JSR ReadJoypads
    JSR UpdateButtonPressedSprites

    JMP MainLoop


.proc UpdateButtonPressedSprites
; DESCRIPTION: Updates the OAM buffer with the sprites for pressed buttons
;              in the controller test.
; ALTERS: A, X, Y, $00
BUTTON_SPRITE_BYTES = NUM_BUTTONS << 2 ; 4 bytes per button
buttonState = $E0
    LDA buttons1
    LDX #0 ; X = OAM buffer byte being written
    LDY #NUM_BUTTONS ; Y = buttons remaining
    LDA buttons1
    STA buttonState ; copy button input

Loop:
    ROR buttonState
    BCC :+ 
    ; If the button is pressed, copy its sprite's data to the buffer.
    LDA SpriteData,X
    STA OAMBUFFER,X
    INX
    LDA SpriteData,X
    STA OAMBUFFER,X
    INX
    LDA SpriteData,X
    STA OAMBUFFER,X
    INX
    LDA SpriteData,X
    STA OAMBUFFER,X
    INX
    JMP LoopEnd
:
    ; If not pressed, copy in $FF for the sprite.
    LDA #$FF
    STA OAMBUFFER,X
    INX
    STA OAMBUFFER,X
    INX
    STA OAMBUFFER,X
    INX
    STA OAMBUFFER,X
    INX
LoopEnd:
    DEY
    BEQ :+
    JMP Loop
:
    RTS
.endproc

.proc ReadJoypads
; Copied from https://www.nesdev.org/wiki/Controller_reading_code
; At the same time that we strobe bit 0, we initialize the ring counter
; so we're hitting two birds with one stone here
    lda #$01
    ; While the strobe bit is set, buttons will be continuously reloaded.
    ; This means that reading from JOYPAD1 will only return the state of the
    ; first button: button A.
    sta JOYPAD1
    sta buttons1 ; set to 1 for bcc
    lsr a        ; now A is 0
    ; By storing 0 into JOYPAD1, the strobe bit is cleared and the reloading stops.
    ; This allows all 8 buttons (newly reloaded) to be read from JOYPAD1.
    sta JOYPAD1
:
    lda JOYPAD1
    lsr a	       ; bit 0 -> Carry
    rol buttons1  ; Carry -> bit 0; bit 7 -> Carry
    bcc :-

    ; Read controller 2
    lda #$01
    ; While the strobe bit is set, buttons will be continuously reloaded.
    ; This means that reading from JOYPAD1 will only return the state of the
    ; first button: button A.
    sta JOYPAD2
    sta buttons2 ; set to 1 for bcc
    lsr a        ; now A is 0
    ; By storing 0 into JOYPAD1, the strobe bit is cleared and the reloading stops.
    ; This allows all 8 buttons (newly reloaded) to be read from JOYPAD1.
    sta JOYPAD2
:
    lda JOYPAD2
    lsr a	       ; bit 0 -> Carry
    rol buttons2  ; Carry -> bit 0; bit 7 -> Carry
    bcc :-
    rts
.endproc

.proc NMI
    ; Push state to stack
    PHP ; does NMI do PHP for you?
    PHA
    TXA
    PHA
    TYA
    PHA

    LDA #>OAMBUFFER ; copy sprite data from $0200 => PPU memory for display
    STA OAMDMA

    ; Indicate that an NMI has occurred by setting bit 7 of framestate
    LDA #%10000000
    STA framestate

    ; Restore state from stack
    PLA
    TAY
    PLA
    TAX
    PLA
    PLP
    RTI
.endproc

;##############################################
; GRAPHICS SUBROUTINES
;##############################################

.proc LoadNametable
; DESCRIPTION: Load a nametable
; PARAMETERS:
;  * A - lo byte of data address
;  * X - hi byte of data address
sourceData = $00

    STA sourceData
    STX sourceData + 1

    ; setup address in PPU for nametable data
    BIT PPUSTATUS ; why?
    LDA #$20
    STA PPUADDR
    LDA #$00
    STA PPUADDR

    ; Load 1024/$400 bytes 
    LDX #$00 ; high byte
    LDY #$00 ; low byte
:
    LDA (sourceData), Y
    STA PPUDATA
    INY
    BNE :-
    INX
    INC sourceData + 1
    CPX #$04
    BNE :-
    RTS
.endproc

.proc LoadPalette
; DESCRIPTION: Load a nametable
; PARAMETERS:
;  * A - lo byte of data address
;  * X - hi byte of data address
sourceData = $00

    STA sourceData
    STX sourceData + 1

    LDY #$00
:
    LDA (sourceData), Y
    STA PPUDATA ; $3F00, $3F01, $3F02 => $3F1F
    INY
    CPY #$20
    BNE :-
    RTS
.endproc

;##############################################
; DATA
;##############################################

PaletteData:
  .incbin "assets/palette.pal"

WorldData:
  ;.incbin "world.bin"
  ;.incbin "assets/controller_map_nametable.map"
  .incbin "assets/test.map"

TitleMap:
  .incbin "assets/title/title.map"
TitlePalette:
  .incbin "assets/title/title.pal" ; background
  .incbin "assets/title/title.pal" ; sprites

SpriteData:
  ; Attribute bits:
  ;  * 7 = Flip vertically
  ;  * 6 = Flip horizontally
  ;  * 5 = Priority (1 = behind background)
  ;  * 1-0 = palette
  ;
  ; y pos, tile index, attributes, x pos
  ; Button sprites ordered from low bit to high bit
  .byte $53, $7B, $02, $3A ; P1 right
  .byte $53, $7B, $02, $33 ; P1 left
  .byte $57, $7C, $02, $36 ; P1 down
  .byte $50, $7C, $02, $36 ; P1 up
  .byte $55, $7D, $02, $48 ; P1 start
  .byte $55, $7D, $02, $40 ; P1 select
  .byte $55, $7E, $02, $50 ; P1 B
  .byte $55, $7E, $02, $58 ; P1 A

; BUTTON_A      = 1 << 7
; BUTTON_B      = 1 << 6
; BUTTON_SELECT = 1 << 5
; BUTTON_START  = 1 << 4
; BUTTON_UP     = 1 << 3
; BUTTON_DOWN   = 1 << 2
; BUTTON_LEFT   = 1 << 1
; BUTTON_RIGHT  = 1 << 0

.segment "VECTORS"
    .word NMI
    .word Reset
    ; 
.segment "CHARS"
    ; .incbin "hellomario.chr"
    .incbin "assets/tiles.chr"