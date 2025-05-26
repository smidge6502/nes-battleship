.include "nesdefs.inc"

; RAM addresses
STACK     = $100
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

; Game states
GAMESTATE_TITLE = 0
GAMESTATE_PLACE_SHIPS = 1
GAMESTATE_BOARD = 2

NAMETABLE_TL = $2000 ; top-left
NAMETABLE_TR = $2400 ; top-right
NAMETABLE_BL = $2800 ; bottom-left
NAMETABLE_BR = $2C00 ; bottom-right

NAMETABLE_ATTRIBUTE_OFFSET = $3C0
NAMETABLE_ATTRIBUTE_TL = NAMETABLE_TL + NAMETABLE_ATTRIBUTE_OFFSET
NAMETABLE_ATTRIBUTE_TR = NAMETABLE_TR + NAMETABLE_ATTRIBUTE_OFFSET
NAMETABLE_ATTRIBUTE_BL = NAMETABLE_BL + NAMETABLE_ATTRIBUTE_OFFSET
NAMETABLE_ATTRIBUTE_BR = NAMETABLE_BR + NAMETABLE_ATTRIBUTE_OFFSET

; Ship tiles
; Each ship part is 2x2 tiles. The value here
; is the upper-left tile.
SHIP_BOW_HORIZ_TILE   = $E8
SHIP_MID_HORIZ_TILE   = $EA
SHIP_STERN_HORIZ_TILE = $EC
SHIP_BOW_VERT_TILE    = $AE
SHIP_MID_VERT_TILE    = $CE
SHIP_STERN_VERT_TILE  = $EE

EMPTY_SQUARE_TILE     = $CC
HIT_SQUARE_TILE       = $C8
MISS_SQUARE_TILE      = $CA

; Ship types
NUM_SHIPS        = $05
SHIP_PATROL_BOAT = $00
SHIP_DESTROYER   = $01
SHIP_SUBMARINE   = $02
SHIP_BATTLESHIP  = $03
SHIP_CARRIER     = $04

; Orientations
ORIENTATION_HORIZONTAL = $00
ORIENTATION_VERTICAL   = $01

; Board (top-left corner)
BOARD_OFFSET_X   = $02
BOARD_OFFSET_Y   = $08

BOARD_SQUARES_PER_LINE = 10
BOARD_NUM_ROWS         = 10
BOARD_NUM_COLS         = 10
BOARD_NUM_SQUARES      = BOARD_NUM_ROWS * BOARD_NUM_COLS

CURSOR_BLINK_CHECK_MASK = %00010000 ; show cursor if this AND globalTimer = 0

; Pointer to nametable attribute byte for (X,Y) = (0,0)
BOARD_ATTRIBUTE_PTR = NAMETABLE_ATTRIBUTE_BL + 2*NAMETABLE_ATTRIBUTE_BYTES_PER_LINE

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

.segment "ZEROPAGE"
args:             .res 16 ; reserve $00-$0F for general use
nmiArgs:          .res 8  ; reserve 8 bytes just for use during NMI

nmiFlags:         .res 1  ; bit 7 set = call LoadPalette

; Global variables - zero page
;------------------------------
globalTimer:      .res 1
frameState:       .res 1
FRAMESTATE_NMI          = 1 << 7 ; 1 means NMI has occurred and we can do game logic
FRAMESTATE_UPDATE_BOARD = 1 << 6 ; set if board nametable needs updating

gameState:        .res 1
nextGameState:    .res 1

; Random number generator variables
rng:              .res 1

; Controller state variables
prevButtons1:     .res 1 ; buttons read the previous frame
prevButtons2:     .res 1
buttons1:         .res 1 ; buttons read this frame
buttons2:         .res 1
heldButtons1:     .res 1
heldButtons2:     .res 1
pressedButtons1:  .res 1
pressedButtons2:  .res 1
releasedButtons1: .res 1
releasedButtons2: .res 1

; PPU variables
ppuScrollX:       .res 1
ppuScrollY:       .res 1
ppuControl:       .res 1
currentPalette:   .res 2
nextTile:         .res 1 ; for testing updates to specific nametable tiles

; Cursor for placing ships
cursorX:          .res 1
cursorY:          .res 1
shipBeingPlaced:  .res 1
shipOrientation:  .res 1 ; 1 = vertical, 0 = horizontal
newCursorX:       .res 1
newCursorY:       .res 1
newShip:          .res 1
newOrientation:   .res 1

; Nametable write queues
;   * Status:   d7-d1 ignored; d0 = orientation
;   * Address:  Nametable address where to start writing
;   * Tiles:    Tiles to write.
;   * Next:     Index of next available queue
NUM_NAMETABLE_QUEUES   = 4
NAMETABLE_QUEUE_LENGTH = 16
NAMETABLE_QUEUE_STATUS_HORIZONTAL = %00000000  ; PPUCTRL d2 for write increment
NAMETABLE_QUEUE_STATUS_VERTICAL   = %00000100
nametableQueueStatus:       .res NUM_NAMETABLE_QUEUES
nametableQueueAddressLo:    .res NUM_NAMETABLE_QUEUES
nametableQueueAddressHi:    .res NUM_NAMETABLE_QUEUES
nametableQueueTiles:        ;.res NUM_NAMETABLE_QUEUES * NAMETABLE_QUEUE_LENGTH
NQUEUE0:                    .res NAMETABLE_QUEUE_LENGTH
NQUEUE1:                    .res NAMETABLE_QUEUE_LENGTH
NQUEUE2:                    .res NAMETABLE_QUEUE_LENGTH
NQUEUE3:                    .res NAMETABLE_QUEUE_LENGTH

; Attributes start at: $23C0, $27C0, $2BC0, or $2FC0
NUM_ATTRIBUTE_QUEUES                 = 2
ATTRIBUTE_QUEUE_LENGTH               = 4
ATTRIBUTE_QUEUE_INCREMENT_HORIZONTAL = 1
ATTRIBUTE_QUEUE_INCREMENT_VERTICAL   = 8
ATTRIBUTE_QUEUE_TERMINATOR           = $FF  ; can't be 0 because that's a valid byte (but so is FF...)
attributeQueueLo:           .res NUM_ATTRIBUTE_QUEUES
attributeQueueHi:           .res NUM_ATTRIBUTE_QUEUES
attributeQueueIncrement:    .res NUM_ATTRIBUTE_QUEUES
attributeQueue0:            .res ATTRIBUTE_QUEUE_LENGTH
attributeQueue1:            .res ATTRIBUTE_QUEUE_LENGTH

.segment "BSS" ; RAM start from $300
stringWriteQueueCount:       .res 1 ; entries on queue
stringWriteQueueStringLo:    .res 4 ; low byte of string pointer
stringWriteQueueStringHi:    .res 4 ; high byte of string pointer
stringWriteQueueStringLen:   .res 4 ; length of string
stringWriteQueueNametableLo: .res 4 ; low byte of starting nametable pointer
stringWriteQueueNametableHi: .res 4 ; high byte of starting nametable pointer

; TODO: align to page
playerBoard:           .res 100
cpuBoard:              .res 100
; Structure of a board byte:
;
;  7 6 543 21 0
;  | | |   |  - orientation (0 = horizontal, 1 = vertical)
;  | | |   - ship section (0 = bow, 1 = middle, 2 = stern)
;  | | - ship ID
;  | - has been fired upon flag (1=yes)
;  - has ship flag (1 = yes)

playerShipsRemainingHits:   .res NUM_SHIPS
cpuShipsRemainingHits:      .res NUM_SHIPS

ATTRIBUTE_CACHE_NUM_ROWS      = 5
ATTRIBUTE_CACHE_BYTES_PER_ROW = 6
ATTRIBUTE_CACHE_NUM_BYTES     = ATTRIBUTE_CACHE_NUM_ROWS * ATTRIBUTE_CACHE_BYTES_PER_ROW
playerBoardAttributeCache:  .res ATTRIBUTE_CACHE_NUM_BYTES
cpuBoardAttributeCache:     .res ATTRIBUTE_CACHE_NUM_BYTES

placedShipsX:          .res NUM_SHIPS
placedShipsY:          .res NUM_SHIPS
allShipsPlaced:        .res 1
stringWriteCount:      .res 1

isMainBoardPlayer:     .res 1 ; d7 = 1 means the large board on the play screen
                              ; is showing the player's board. 0 shows the
                              ; CPU's board. 

.segment "STARTUP"
.proc Reset
    SEI ; Disables all interrupts
    CLD ; disable decimal mode

    ; Disable APU frame counter IRQ
    LDX #$40
    STX APU_FRAME_COUNTER

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

; Init game state
    LDA #<TitlePalette
    LDX #>TitlePalette
    STA currentPalette
    STX currentPalette+1
    JSR LoadPalette

    ; Load title screen
    LDA #<TitleMap
    LDX #>TitleMap
    LDY #>NAMETABLE_TL
    JSR LoadNametable

    ; Load ship placement screen in off-screen nametable
    LDA #<PlaceShipsMap
    LDX #>PlaceShipsMap
    LDY #>NAMETABLE_BL
    JSR LoadNametable

    LDA #GAMESTATE_TITLE
    STA gameState
    STA nextGameState

    ; Set RNG seed
    LDA #1
    STA rng

; Enable interrupts
    ;CLI

    LDA #%10001000 ; (7)enable NMI, (4)background = 2nd char table ($1000); (3)sprites = $1000
    STA ppuControl
    STA PPUCTRL

    LDA #0
    STA ppuScrollX
    STA ppuScrollY

    ; Enabling sprites and background for left-most 8 pixels
    ; Enable sprites and background
    LDA #%00011110
    STA PPUMASK

    JMP MainLoop
.endproc

;#######################################
; NMI
;#######################################

.proc NMI
    PHP ; does NMI do PHP for you?
    PHA
    TXA
    PHA
    TYA
    PHA

    LDA #>OAMBUFFER ; copy sprite data from $0200 => PPU memory for display
    STA OAMDMA

    ; Load palette if bit 7 of nmiFlags is set
    LDA nmiFlags
    BPL Queues
    AND #%01111111         ; clear the flag
    STA nmiFlags
    LDA currentPalette
    LDX currentPalette+1
    JSR LoadPalette

    ; Process update queues
Queues:
    JSR NMI_ProcessNametableQueue_Fast
    LDA ppuControl
    STA PPUCTRL
    JSR NMI_ProcessAttributeQueue
    JSR NMI_ProcessStringWriteQueue

SetScroll:
    ; Set scroll
    LDA ppuControl
    STA PPUCTRL
    BIT PPUSTATUS ; clear w flag
    LDA ppuScrollX
    STA PPUSCROLL
    LDA ppuScrollY
    STA PPUSCROLL

    ; Indicate that an NMI has occurred by setting bit 7 of frameState
    ; Also clears other bits
    LDA #FRAMESTATE_NMI
    STA frameState

    PLA
    TAY
    PLA
    TAX
    PLA
    PLP
    RTI
.endproc

.proc NMI_ProcessStringWriteQueue
ASCII_SPACE = $20
stringPointer = nmiArgs ; 2 bytes
stringLength  = nmiArgs + 2
reachedEnd    = nmiArgs + 3 ; set bit 7 = 1 when the string terminator is reached
    LDX stringWriteQueueCount
    BNE :+
    RTS
:

    LDX #0
@queueLoop:
    LDA stringWriteQueueStringLo,X
    STA stringPointer
    LDA stringWriteQueueStringHi,X
    STA stringPointer + 1
    LDA stringWriteQueueStringLen,X
    STA stringLength
    BIT PPUSTATUS
    LDA stringWriteQueueNametableHi,X
    STA PPUADDR
    LDA stringWriteQueueNametableLo,X
    STA PPUADDR

    LDY #0
    STY reachedEnd
@stringLoop:
    CPY stringLength
    BEQ @queueLoop_next

    BIT reachedEnd
    BPL :+
    LDA #ASCII_SPACE ; padding for the rest of the string
    BPL @stringLoop_write
:
    LDA (stringPointer),Y
    BNE @stringLoop_write
    SEC             ; hit string terminator; set bit 7 of reachedEnd
    ROR reachedEnd
    LDA #ASCII_SPACE
@stringLoop_write:
    STA PPUDATA
    INY
    BPL @stringLoop

@queueLoop_next:
    INX
    CPX stringWriteQueueCount
    BNE @queueLoop


End:
    LDX #0
    STX stringWriteQueueCount
    RTS
.endproc

.proc NMI_ProcessAttributeQueue
;ProcessQueue0
    LDA attributeQueue0
    BMI ProcessQueue1
    LDX #0

@loop:
    LDY attributeQueue0,X
    BMI ProcessQueue1

    BIT PPUSTATUS
    LDA attributeQueueHi
    STA PPUADDR
    LDA attributeQueueLo
    STA PPUADDR
    STY PPUDATA

    CLC
    ADC attributeQueueIncrement
    STA attributeQueueLo

    INX
    BNE @loop

ProcessQueue1:
    LDA attributeQueue1
    BMI End
    LDX #0

@loop:
    LDY attributeQueue1,X
    BMI End

    BIT PPUSTATUS
    LDA attributeQueueHi + 1
    STA PPUADDR
    LDA attributeQueueLo + 1
    STA PPUADDR
    STY PPUDATA

    CLC
    ADC attributeQueueIncrement + 1
    STA attributeQueueLo + 1

    INX
    BNE @loop


End:
    RTS
.endproc

.proc NMI_ProcessNametableQueue_Fast
; DESCRIPTION: NMI routine for writing queued updates to the nametable.
;-------------------------------------------------------------------------------
;ProcessQueue0
    LDA NQUEUE0
    BEQ ProcessQueue1

    BIT PPUSTATUS
    LDA nametableQueueAddressHi
    STA PPUADDR
    LDA nametableQueueAddressLo
    STA PPUADDR
    LDA nametableQueueStatus
    STA PPUCTRL

    LDX #0
@loop:
    LDA NQUEUE0,X
    BEQ ProcessQueue1
    STA PPUDATA
    INX
    BPL @loop

ProcessQueue1:
    LDA NQUEUE1
    BEQ ProcessQueue2

    BIT PPUSTATUS
    LDA nametableQueueAddressHi + 1
    STA PPUADDR
    LDA nametableQueueAddressLo + 1
    STA PPUADDR
    LDA nametableQueueStatus + 1
    STA PPUCTRL

    LDX #0
@loop:
    LDA NQUEUE1,X
    BEQ ProcessQueue2
    STA PPUDATA
    INX
    BPL @loop

ProcessQueue2:
    LDA NQUEUE2
    BEQ ProcessQueue3

    BIT PPUSTATUS
    LDA nametableQueueAddressHi + 2
    STA PPUADDR
    LDA nametableQueueAddressLo + 2
    STA PPUADDR
    LDA nametableQueueStatus + 2
    STA PPUCTRL

    LDX #0
@loop:
    LDA NQUEUE2,X
    BEQ ProcessQueue3
    STA PPUDATA
    INX
    BPL @loop

ProcessQueue3:
    LDA NQUEUE3
    BEQ End

    BIT PPUSTATUS
    LDA nametableQueueAddressHi + 3
    STA PPUADDR
    LDA nametableQueueAddressLo + 3
    STA PPUADDR
    LDA nametableQueueStatus + 3
    STA PPUCTRL

    LDX #0
@loop:
    LDA NQUEUE3,X
    BEQ End
    STA PPUDATA
    INX
    BPL @loop

End:
    RTS
.endproc

.proc MainLoop
    ; Check if NMI has occurred
    BIT frameState
    BPL MainLoop

    LDA #0
    STA frameState
    INC globalTimer

    ; Reset the nametable queues
    LDA #0
    STA NQUEUE0
    STA NQUEUE1
    STA NQUEUE2
    STA NQUEUE3
    LDA #ATTRIBUTE_QUEUE_TERMINATOR
    STA attributeQueue0
    STA attributeQueue1

    ; Iterate RNG
    JSR GetNextRng

    ; Read the joypads and disable the APU frame counter
    ; IRQ again since reading the second joypad re-enables it
    JSR ReadJoypads
    LDA #$40
    STA APU_FRAME_COUNTER

    ; Check if game state is changing
    LDA gameState
    EOR nextGameState
    TAY ; Y will be non-zero if the state changed
    LDA nextGameState
    STA gameState

    ; Check game state
    LDA gameState
    CMP #GAMESTATE_TITLE
    BNE :+
    JMP ProcessTitle
:
    CMP #GAMESTATE_PLACE_SHIPS
    BNE :+
    JMP ProcessPlaceShips
:
    CMP #GAMESTATE_BOARD
    BNE :+
    JMP ProcessPlayBoard
:

    JMP MainLoop
.endproc

.proc ProcessTitle
; DESCRIPTION: Main routine for the title screen.
;------------------------------------------------------------------------------
    ; Check if the start putton was pressed
    LDA buttons1
    AND #BUTTON_START
    BEQ :+

    LDA #GAMESTATE_PLACE_SHIPS
    STA nextGameState

:
    JMP MainLoop
.endproc

.proc ProcessPlaceShips
; DESCRIPTION: Main routine for the screen where the player places their ships.
;------------------------------------------------------------------------------
iShipSquare    = $00
dBoardArray    = $01

iQueue           = $02
currentSquare    = $03
arrayId          = $04
dTileWithinQueue = $05
dTileNextQueue   = $06
shipTilePtr      = $07 ; 2 bytes
shipNumTiles     = $09

X_MAX                         = $09
Y_MAX                         = $09
BOARD_WIDTH                   = $0A
ALL_SHIPS_PLACED_STRING_COUNT = 3
    ; Check if we need to initialize the screen
    TYA
    BEQ InitEnd

Init:
    ; Disable rendering and NMI
    LDA #0
    STA PPUMASK

    ; Switch to BL nametable
    LDA ppuControl
    AND #%01111100 ; clear nametable and NMI bits
    ORA #%00000010 ; set nametable bits
    STA ppuControl
    STA PPUCTRL

    ; Load nametable
    LDA #<PlaceShipsMap
    LDX #>PlaceShipsMap
    LDY #>NAMETABLE_BL
    JSR LoadNametable

    ; Load palette
    LDA #<PlaceShipsPalette
    STA currentPalette
    LDX #>PlaceShipsPalette
    STX currentPalette+1
    ;JSR SetNmiFlagLoadPalette
    JSR LoadPalette

    ; Write "PLACE YOUR" text
    LDA #<StringPlaceYour
    STA $00
    LDA #>StringPlaceYour
    STA $01
    LDA #11
    STA $02
    LDY #>NAMETABLE_BL
    LDX #$48
    JSR EnqueueStringWrite

    ; Initialize cursor to A-1
    LDA #0
    STA cursorX
    STA cursorY
    STA shipBeingPlaced ; patrol boat
    STA shipOrientation ; horizontal
    TAY
    JSR UpdatePlaceYourShipString

    ; Initialize placed ships
    LDA #$FF ; $FF = ship has not been placed
    LDX #NUM_SHIPS - 1
:
    STA placedShipsX,X
    STA placedShipsY,X
    DEX
    BPL :-

    LDA #0
    STA allShipsPlaced
    LDA #ALL_SHIPS_PLACED_STRING_COUNT
    STA stringWriteCount

    ; Clear the board and set player board as main board
    LDA #0
    LDX #BOARD_NUM_SQUARES - 1
:
    STA playerBoard,X
    DEX
    BPL :-
    LDA #%10000000
    STA isMainBoardPlayer

    ; Enable rendering and NMI
    LDA #%00011110
    STA PPUMASK
    LDA ppuControl
    ORA #%10000000 ; set NMI bit
    STA ppuControl
    STA PPUCTRL

    JMP EndProcessPlaceShips ; skip button checks
InitEnd:

    ; Check if all ships have been placed
    LDA allShipsPlaced
    BEQ CheckJoypad

    ; Reset the board if select is pressed
    LDA pressedButtons1
    AND #BUTTON_SELECT
    BEQ :+
    JMP Init

:
    ; Advance to playing the game if start is pressed
    LDA pressedButtons1
    AND #BUTTON_START
    BEQ :+

    LDA #GAMESTATE_BOARD
    STA nextGameState
    JMP MainLoop

:
    JSR WriteAllShipsPlacedText
    JMP EndProcessPlaceShips

CheckJoypad:
    ; Initialize variables
    LDX cursorX
    STX newCursorX
    LDY cursorY
    STY newCursorY
    LDA shipOrientation
    STA newOrientation
    LDA shipBeingPlaced
    STA newShip

@checkA:
    LDA pressedButtons1
    AND #BUTTON_A
    BEQ @checkSelect

    ; Call PlaceShipOnBoard for the player
    LDA $00
    PHA
    LDA $01
    PHA
    LDA shipOrientation
    STA $00
    LDA shipBeingPlaced
    STA $01
    LDX cursorX
    LDY cursorY
    SEC
    JSR PlaceShipOnBoard
    PLA
    STA $01
    PLA
    STA $00

    JSR PlaceShipOnCpuBoard

    BCS @updateNextShip

    JMP DrawBoard

@checkSelect:
    LDA pressedButtons1
    AND #BUTTON_SELECT
    BEQ @checkB

@updateNextShip:
    ; Find the next unplaced ship
    LDY newShip
    JSR GetNextShipToPlace
    BMI @setAllShipsPlaced
    
    STA newShip
    JMP CheckNewCursorWithinBounds

@setAllShipsPlaced:
    LDA #1
    STA allShipsPlaced
    ;JSR WriteAllShipsPlacedText
    JMP DrawBoard

@checkB:
    LDA pressedButtons1
    AND #BUTTON_B
    BEQ @checkRight

    LDA shipOrientation
    EOR #%00000001
    STA newOrientation
    JMP CheckNewCursorWithinBounds

@checkRight:
    LDA pressedButtons1
    AND #BUTTON_RIGHT
    BEQ @checkLeft
    INX
    STX newCursorX
    JMP @checkDown

@checkLeft:
    LDA pressedButtons1
    AND #BUTTON_LEFT
    BEQ @checkDown

    DEX
    STX newCursorX

@checkDown:
    LDA pressedButtons1
    AND #BUTTON_DOWN
    BEQ @checkUp
    INY
    STY newCursorY
    JMP CheckNewCursorWithinBounds

@checkUp:
    LDA pressedButtons1
    AND #BUTTON_UP
    BEQ CheckNewCursorWithinBounds
    DEY
    STY newCursorY

CheckNewCursorWithinBounds:
    ; Find the maximum X or Y (depending on orientation) based on ship length.
    ; The X and Y registers will hold their respective maximums.
    LDY newShip
    LDA #BOARD_WIDTH
    SEC
    SBC ShipLengths,Y

    LDY newOrientation
    BNE @maxBoundsVertical
@maxBoundsHorizontal:
    TAX
    LDY #Y_MAX
    BNE @checkLeft
@maxBoundsVertical:
    LDX #X_MAX
    TAY

@checkLeft:
    LDA newCursorX
    BPL @checkRight ; non-negative means in bounds
    LDA #0
    STA newCursorX
    BEQ @checkTop
@checkRight:
    CPX newCursorX
    BCS @checkTop   ; branch if max >= new
    STX newCursorX

@checkTop:
    LDA newCursorY
    BPL @checkBottom
    LDA #0
    STA newCursorY
    BEQ DrawShipText
@checkBottom:
    CPY newCursorY
    BCS DrawShipText
    STY newCursorY

DrawShipText:
    LDA newShip
    CMP shipBeingPlaced
    BEQ DrawBoard ; skip string update if same ship
    TAY

    ; Update "PLACE YOUR {SHIP}"
    ; Save off $00-$02
    LDA $00
    PHA
    LDA $01
    PHA
    LDA $02
    PHA
    JSR UpdatePlaceYourShipString
    PLA
    STA $02
    PLA
    STA $01
    PLA
    STA $00   

DrawBoard:
@drawBoardAtCurrentPosition:
    ; Overwrite the current ship's tiles with what's on the board
    ;
    ; Horizontal:
    ;   * NQUEUE0 - top row
    ;   * NQUEUE1 - bottom row
    ; Vertical:
    ;   * NQUEUE0 - left row
    ;   * NQUEUE1  - right row

    ; First we need to set the nametable pointers in the queues.
    LDX cursorX
    LDY cursorY
    JSR GetSquareNametablePtrFromXY ; A and X hold the hi and lo pointers

    ; The NQUEUE0 address is the same for both orientations.
    STA nametableQueueAddressHi
    STX nametableQueueAddressLo

    ; NQUEUE1 address
    STA nametableQueueAddressHi + 1  ; same hi byte for both sections

    LDA shipOrientation
    BNE :+
    ; horizontal
    TXA
    CLC
    ADC #NAMETABLE_TILES_PER_LINE
    STA nametableQueueAddressLo + 1
    LDY #NAMETABLE_QUEUE_STATUS_HORIZONTAL
    JMP @setStatus
:
    ; vertical
    INX
    STX nametableQueueAddressLo + 1
    LDY #NAMETABLE_QUEUE_STATUS_VERTICAL

@setStatus:
    STY nametableQueueStatus
    LDA ppuControl
    AND #%11111011
    ORA nametableQueueStatus
    STA nametableQueueStatus
    STA nametableQueueStatus + 1

@tileQueues:
    ; We need to loop over the board squares according to the orientation.
    ;
    ; Get the number of squares to loop over
    LDY shipBeingPlaced
    LDA ShipLengths,Y
    STA iShipSquare

    ; Initialize queue index
    LDA #0
    STA iQueue

    ; Figure out how much to add to get to the next board square and
    ; to get the next char tile within a square.
    ;   * dTileWithinQueue = increment to next tile for the next index
    ;                        of a single queue (ex. top to top + 1)
    ;   * dTileNextQueue   = increment to next queue at the same index
    ;                        (ex. top 0 to bottom 0)
    LDA shipOrientation
    BNE :+
    ; horizontal
    LDA #1
    STA dBoardArray
    STA dTileWithinQueue
    LDA #CHAR_TILES_PER_ROW
    STA dTileNextQueue
    BNE :++
:
    ; vertical
    LDA #BOARD_WIDTH
    STA dBoardArray
    LDA #CHAR_TILES_PER_ROW
    STA dTileWithinQueue
    LDA #1
    STA dTileNextQueue
:

    ; Get the starting square and board array ID
    LDX cursorX
    LDY cursorY
    JSR GetBoardArrayIdFromXY
    STA arrayId

@queueLoop:
    TAY
    JSR GetBoardSquareTileFromArrayId ; A = char tile of upper-left tile of square
    STA currentSquare

    LDX iQueue
    STA NQUEUE0,X ; top-left tile in both orientations
    CLC
    ADC dTileNextQueue
    STA NQUEUE1,X

    INX
    ADC dTileWithinQueue
    STA NQUEUE1,X
    SEC
    SBC dTileNextQueue ; go back to queue 0
    STA NQUEUE0,X

    INX
    STX iQueue

    ; Move to the next board square
    LDA arrayId
    CLC
    ADC dBoardArray
    STA arrayId
    DEC iShipSquare
    BNE @queueLoop

    ; Write the 0 terminator to the queues.
    LDA #0
    STA NQUEUE0,X
    STA NQUEUE1,X


    ; The selected ship blinks - check if we should draw
    ; the ship being moved around or the board behind it.
    LDA globalTimer
    AND #CURSOR_BLINK_CHECK_MASK
    BEQ DrawCursorShip
    JMP UpdateCursor


DrawCursorShip:
    LDX newCursorX
    LDY newCursorY

    ; Set up a byte with the ship ID in d5-d3 and the orientation in d0.
    LDA newShip
    ASL
    ASL
    ASL
    ORA newOrientation

    JSR DrawWholeShip
    
UpdateCursor:
    JSR SetAttributeQueues

    LDA newCursorX
    STA cursorX
    LDA newCursorY
    STA cursorY
    LDA newOrientation
    STA shipOrientation
    LDA newShip
    STA shipBeingPlaced

EndProcessPlaceShips:
    JMP MainLoop
.endproc

.proc UpdatePlaceYourShipString
; DESCRIPTION: Enqueues an update to the {SHIP} part of the
;              "PLACE YOUR {SHIP}" string. Sets {SHIP} to the
;              name of the current ship.
; PARAMETERS:
;   * Y - Ship ID
strPtrLo = $00
strPtrHi = $01
strLen   = $02
    ; Set the "PLACE YOUR {SHIP}" string
    LDA ShipLongNameLo,Y
    STA $00
    LDA ShipLongNameHi,Y
    STA $01
    LDA #11 ; length of longest string; the rest will be blanked out
    STA $02
    LDX #$53
    LDY #>NAMETABLE_BL
    JSR EnqueueStringWrite
    RTS
.endproc

.proc WriteAllShipsPlacedText
; DESCRIPTION: Writes text to display once the player has placed all ships.
;              To avoid overwhelming the NMI handler, the text has been split
;              into multiple strings. One string will be enqueued each time
;              this is called until all strings have been written.
; ALTERS: A, X, Y
;------------------------------------------------------------------------------
    ; Save off $00-$02
    LDA $00
    PHA
    LDA $01
    PHA
    LDA $02
    PHA

    LDA stringWriteCount
    CMP #3
    BEQ WriteAllShipsPlaced
    CMP #2
    BEQ WriteStartPlay
    CMP #1
    BEQ WriteSelectReset
    ;DEC stringWriteCount
    JMP End

    ; Set up arguments
WriteAllShipsPlaced:
    LDA #<StringAllShipsPlaced
    STA $00
    LDA #>StringAllShipsPlaced
    STA $01
    LDA #22 ; long enough to overwrite "place your patrol boat"
    STA $02
    LDY #>NAMETABLE_BL
    LDX #$48
    JSR EnqueueStringWrite
    DEC stringWriteCount
    JMP End
    
WriteStartPlay:
    LDA #<StringStartPlay
    STA $00
    LDA #>StringStartPlay
    STA $01
    LDA #12
    STA $02
    LDY #>NAMETABLE_BL
    LDX #$83
    JSR EnqueueStringWrite
    DEC stringWriteCount
    JMP End

WriteSelectReset:
    LDA #<StringSelectReset
    STA $00
    LDA #>StringSelectReset
    STA $01
    LDA #14
    STA $02
    LDY #>NAMETABLE_BL
    LDX #$91
    JSR EnqueueStringWrite
    DEC stringWriteCount

End:
    ; Restore $00-$02
    PLA
    STA $02
    PLA
    STA $01
    PLA
    STA $00
    RTS
.endproc

.proc EnqueueStringWrite
; DESCRIPTION: Write a string to a location in a nametable.
; PARAMETERS:
;   * X - Low byte of nametable start position
;   * Y - High byte of namestable start position
;   * 0 - Low byte of string pointer
;   * 1 - High byte of string pointer
;   * 2 - Length of padded string
strPtrLo = $00
strPtrHi = $01
strLen   = $02

    TYA
    LDY stringWriteQueueCount

    STA stringWriteQueueNametableHi,Y
    TXA
    STA stringWriteQueueNametableLo,Y
    LDA strPtrLo
    STA stringWriteQueueStringLo,Y
    LDA strPtrHi
    STA stringWriteQueueStringHi,Y
    LDA strLen
    STA stringWriteQueueStringLen,Y

    INC stringWriteQueueCount

    RTS
.endproc

.proc SetAttributeQueues
; DESCRIPTION:
;------------------------------------------------------------------------------
ATTRIBUTE_START_PTR      = $2BC0
BOARD_NORMAL_PALETTE_ID  = $00
BOARD_OVERLAP_PALETTE_ID = $01
TEXT_PALETTE_ID          = $03
MAX_BYTES_PER_QUEUE      = 3
ATTRIBUTE_BOARD_NORMAL_X0 = (BOARD_NORMAL_PALETTE_ID << 6) | (TEXT_PALETTE_ID << 4) | (BOARD_NORMAL_PALETTE_ID << 2) | TEXT_PALETTE_ID
ATTRIBUTE_BOARD_NORMAL_X_NOT_0 = (BOARD_NORMAL_PALETTE_ID << 6) | (BOARD_NORMAL_PALETTE_ID << 4) | (BOARD_NORMAL_PALETTE_ID << 2) | BOARD_NORMAL_PALETTE_ID

shipNumSquares = $00
iAttByte       = $01
attX           = $02
attY           = $03

    LDA $00
    PHA
    LDA $01
    PHA
    LDA $02
    PHA
    LDA $03
    PHA

    LDA #>ATTRIBUTE_START_PTR
    STA attributeQueueHi

    LDX cursorX
    LDY cursorY
    LDA OffsetLoY,Y
    CLC
    ADC OffsetLoX,X
    STA attributeQueueLo

    LDA shipOrientation
    BNE :+
    ; horizontal
    LDA #ATTRIBUTE_QUEUE_INCREMENT_HORIZONTAL
    STA attributeQueueIncrement
    BNE WriteBoardQueue
:
    ; vertical
    LDA #ATTRIBUTE_QUEUE_INCREMENT_VERTICAL
    STA attributeQueueIncrement

    ; All board squares are aligned with attribute quadrants.
    ; Square (0,0) is in the UR quadrant of its attribute byte ($27D0).
    ; From there, we see that:
    ;   * X even -> right side of attribute byte
    ;   * X odd  -> left side of attribute byte
    ;   * Y even -> top side of attribute byte
    ;   * Y odd  -> bottom side of attribute byte
    ;
    ;  10 | 32
    ; ----|----
    ;  54 | 76
    ;
    ; There are two queues to set up:
    ;   * attributeQueue0: This is for drawing the board and ships placed on it
    ;                      and not the cursor. The palette is always the same.
    ;   * attributeQueue1: This is for drawing the cursor (the ship being moved
    ;                      by the player). We want to change the palette of a
    ;                      square of the cursor ship if the board square
    ;                      underneath it already contains a ship.
    ;
    ; Some squares will occupy the same attribute byte.
    ;
    ; Because we need to build up each attribute byte, the loop needs to
    ; be over those.

WriteBoardQueue:
    ; Figure out how many attribute bytes we need to write.
    ; This depends on the length of the ship and whether it starts on an even
    ; or odd square.
    ;    1A = 1 (1 + 0 + 1) / 2 = 1
    ;    1U = 1 (1 + 1 + 1) / 2 = 1
    ; 0  2A = 1 (2 + 0 + 1) / 2 = 1
    ; 1  2U = 2 (2 + 1 + 1) / 2 = 2
    ; 2  3A = 2 (3 + 0 + 1) / 2 = 2
    ; 3  3U = 2 (3 + 1 + 1) / 2 = 2
    ; 4  4A = 2 (4 + 0 + 1) / 2 = 2
    ; 5  4U = 3 (4 + 1 + 1) / 2 = 3
    ; 6  5A = 3
    ; 7  5U = 3
    ;    6A = 3
    ;    6U = 4
    ;---------------------------------
    ; N = (L + A + 1) / 2 ; A = 0 if aligned to attribute; 1 if not
    ; 
    ;   * A = (X or Y) d0
    ;------------------------------------
    ; We need to write at most 3 attributes, so just always write 3.

    LDY shipBeingPlaced
    LDA ShipLengths,Y
    STA shipNumSquares

    LDY #0
    LDA shipOrientation
    BEQ WriteBoardQueueHorizontal
    BNE WriteBoardQueueVertical

WriteBoardQueueHorizontal:
    LDX cursorX
    BNE :+
    LDA #ATTRIBUTE_BOARD_NORMAL_X0 ; special value for X=0
    BNE @writeToQueue
:
    LDA #ATTRIBUTE_BOARD_NORMAL_X_NOT_0
@writeToQueue:
    STA attributeQueue0
    LDA #ATTRIBUTE_BOARD_NORMAL_X_NOT_0 ; this is the only difference between orientations
    STA attributeQueue0 + 1 ; second and third entries always the same
    STA attributeQueue0 + 2
    LDA #ATTRIBUTE_QUEUE_TERMINATOR
    STA attributeQueue0 + 3 ; terminator
    BMI WriteCursorQueue
    

WriteBoardQueueVertical:
    LDX cursorX
    BNE :+
    LDA #ATTRIBUTE_BOARD_NORMAL_X0 ; special value for X=0
    BNE @writeToQueue
:
    LDA #ATTRIBUTE_BOARD_NORMAL_X_NOT_0
@writeToQueue:
    STA attributeQueue0
    STA attributeQueue0 + 1 ; second and third entries always the same
    STA attributeQueue0 + 2
    LDA #ATTRIBUTE_QUEUE_TERMINATOR
    STA attributeQueue0 + 3 ; terminator

WriteCursorQueue:
    ; Skip this if the cursor is not visible
    LDA globalTimer
    AND #CURSOR_BLINK_CHECK_MASK
    BEQ :+
    JMP End
:
    LDA #>ATTRIBUTE_START_PTR
    STA attributeQueueHi + 1

    LDX newCursorX
    LDY newCursorY
    LDA OffsetLoY,Y
    CLC
    ADC OffsetLoX,X
    STA attributeQueueLo + 1

    LDA newOrientation
    BNE :+
    ; horizontal
    LDA #ATTRIBUTE_QUEUE_INCREMENT_HORIZONTAL
    STA attributeQueueIncrement + 1
    BNE @initAttByteLoop
:
    ; vertical
    LDA #ATTRIBUTE_QUEUE_INCREMENT_VERTICAL
    STA attributeQueueIncrement + 1

@initAttByteLoop:
    ; First of all, look at this:
    ;
    ;  10 | 32
    ; ----|----
    ;  54 | 76
    ;
    ; We need to figure out the (X,Y) coordinate of the upper-left quadrant
    ; of the attribute byte where the cursor is located.
    LDA #0
    STA iAttByte
    LDX newCursorX
    LDY newCursorY
    LDA AttributeUpperLeftX,X
    STA attX
    LDA AttributeUpperLeftY,Y
    STA attY

AttByteLoop:
    ; quadrant UL
    JSR GetPaletteForAttributeQuadrantXY
    LDX iAttByte
    STA attributeQueue1,X

    ; quadrant UR
    INC attX
    JSR GetPaletteForAttributeQuadrantXY
    ; shift to bytes 3,2
    ASL
    ASL
    LDX iAttByte
    ORA attributeQueue1,X
    STA attributeQueue1,X

    ; quadrant BR
    INC attY
    JSR GetPaletteForAttributeQuadrantXY
    ; shift to bytes 7,6
    CLC
    ROR
    ROR
    ROR
    LDX iAttByte
    ORA attributeQueue1,X
    STA attributeQueue1,X

    ; quadrant BL
    DEC attX
    JSR GetPaletteForAttributeQuadrantXY
    ; shift to bytes 5,4
    ASL
    ASL
    ASL
    ASL
    LDX iAttByte
    ORA attributeQueue1,X
    STA attributeQueue1,X

    ; iterate
    INX
    STX iAttByte
    CPX #MAX_BYTES_PER_QUEUE
    BEQ @writeTerminator

    ; Change attX, attY to the UL-quadrant of the next byte
    ; Currently they are in the BL-quadrant of the current byte.
    LDA newOrientation
    BNE :+
    ; horizontal - move two right and one up
    DEC attY
    INC attX
    INC attX
    LDA #BOARD_SQUARES_PER_LINE
    CMP attX
    BCC @writeTerminator ; quit if attX is off the board
    JMP AttByteLoop
:
    ; vertical - move one down
    INC attY
    LDA #BOARD_SQUARES_PER_LINE
    CMP attY
    BCC @writeTerminator
    JMP AttByteLoop

@writeTerminator:
    LDX iAttByte
    LDA #ATTRIBUTE_QUEUE_TERMINATOR
    STA attributeQueue1,X

End:
    PLA
    STA $03
    PLA
    STA $02
    PLA
    STA $01
    PLA
    STA $00
    RTS

; Add these to get the starting pointer of the attribute table
OffsetLoY:
  .byte $D0,$D0,$D8,$D8,$E0,$E0,$E8,$E8,$F0,$F0
OffsetLoX:
  .byte $00,$01,$01,$02,$02,$03,$03,$04,$04,$05 ; could also do (X + 1) / 2

; These are for obtaining the (X,Y) coordinate of the upper-left square of
; an attribute byte. Use the cursor location as an offset.
AttributeUpperLeftY:
  .byte 0,0,2,2,4,4,6,6,8,8
AttributeUpperLeftX:
  .byte $FF,1,1,3,3,5,5,7,7,9
.endproc

.proc GetPaletteForAttributeQuadrantXY
BOARD_NORMAL_PALETTE_ID  = $00
BOARD_OVERLAP_PALETTE_ID = $01
TEXT_PALETTE_ID          = $03

attX = SetAttributeQueues::attX
attY = SetAttributeQueues::attY

    LDX attX
    BPL :+ ; skip if negative (can only happen with X)
    LDA #TEXT_PALETTE_ID
    RTS
:

    ; If all ships have been placed, force the use of the
    ; normal palette. Without this, then the last ship
    ; placed will have the overlap palette if it's placed
    ; on a frame when the ship is visible.
    LDA allShipsPlaced
    BEQ :+
    LDA #BOARD_NORMAL_PALETTE_ID
    RTS

:
    ; Check if there is a ship placed at (X,Y)
    LDY attY
    JSR GetBoardArrayIdFromXY
    TAY
    LDA playerBoard,Y
    BPL @useNormal
    ; there is a ship on the board. Check if the cursor overlaps
    LDY attY ; X is still attX
    JSR IsNewCursorShipOnSquareXY
    BNE @useNormal
    ; overlap
    LDA #BOARD_OVERLAP_PALETTE_ID
    RTS
@useNormal:
    LDA #BOARD_NORMAL_PALETTE_ID
    RTS
.endproc

.proc PlaceShipOnBoard
; DESCRIPTION: Place a ship on the board
; PARAMETERS:
;  * X - X coordinate
;  * Y - Y coordinate
;  * C - set if player's board; clear if CPU's board
;  * $00 - ship orientation
;  * $01 - ship to place
; RETURNS: C flag set if ship placed; cleared if it could not be placed
;------------------------------------------------------------------------------
orientation    = $00 ; input parameters
shipType       = $01

currentArrayId = $02
deltaArrayId   = $03 ; amount to add to get the next array ID
shipByte       = $04
boardPtr       = $05 ; 2 bytes
startArrayId   = $07 ; not used?
isPlayerBoard  = $08
boardX         = $09
boardY         = $0A

    LDA $02
    PHA
    LDA $03
    PHA
    LDA $04
    PHA
    LDA $05
    PHA
    LDA $06
    PHA
    LDA $07
    PHA
    LDA $08
    PHA
    LDA $09
    PHA
    LDA $0A
    PHA

    STX boardX
    STY boardY

    ; Set up the board pointer
    BCS :+
    LDA #<cpuBoard
    STA boardPtr
    LDA #>cpuBoard
    STA boardPtr + 1
    LDA #0
    STA isPlayerBoard
    JMP InitArrayVars

:
    LDA #<playerBoard
    STA boardPtr
    LDA #>playerBoard
    STA boardPtr + 1
    LDA #1
    STA isPlayerBoard

InitArrayVars:
    JSR GetBoardArrayIdFromXY
    STA startArrayId
    STA currentArrayId

    LDA orientation
    BNE :+
    LDA #1 ; horizontal
    STA deltaArrayId
    BNE CheckIfEmpty
:
    LDA #10
    STA deltaArrayId

CheckIfEmpty:
    ; Check if there is already a ship at (X,Y)
    LDY shipType
    LDX ShipLengths,Y
@loop:
    LDY currentArrayId
    LDA (boardPtr),Y
    AND #%10000000
    BEQ @iterate

    CLC ; ship not placed
    JMP End

@iterate:
    LDA deltaArrayId
    CLC
    ADC currentArrayId
    STA currentArrayId
    DEX
    BNE @loop

PlaceShip:
    ; The bytes placed in the byte array will all be the same
    ; except for bits 2 and 1 (ship part). First build the
    ; common bits of the byte:
    ; d7 = 1 (has ship); d6 = 0 (not fired upon);
    ; d5-d3 = ship ID; d0 = orientation
    LDA shipType
    ASL
    ASL
    ASL
    ORA orientation
    ORA #%10000000
    STA shipByte

    LDA startArrayId
    STA currentArrayId

@placeBow:
    ; The ship part is already correctly set to 0.
    TAY
    LDA shipByte
    STA (boardPtr),Y

    TYA
    CLC
    ADC deltaArrayId
    STA currentArrayId

    ; Place middle
    LDY shipType
    LDX ShipLengths,Y
    DEX
    DEX ; subtract 2 for middle length
    BEQ @placeStern

    LDA shipByte
    ORA #%00000010 ; middle section
@middeLoop:
    LDY currentArrayId
    STA (boardPtr),Y
    PHA
    TYA
    CLC
    ADC deltaArrayId
    STA currentArrayId
    PLA
    DEX
    BNE @middeLoop

@placeStern:
    LDA shipByte
    ORA #%00000100 ; stern
    LDY currentArrayId
    STA (boardPtr),Y

    SEC   ; ship was placed

MarkShipAsPlaced:
    LDA isPlayerBoard ; skip this for the CPU's board
    BEQ End

    LDY shipType
    LDA boardX
    STA placedShipsX,Y
    LDA boardY
    STA placedShipsY,Y

End:
    PLA
    STA $0A
    PLA
    STA $09
    PLA
    STA $08
    PLA
    STA $07
    PLA
    STA $06
    PLA
    STA $05
    PLA
    STA $04
    PLA
    STA $03
    PLA
    STA $02

    RTS

.endproc

.proc PlaceShipOnCpuBoard
; DESCRIPTION: Place a ship on the CPU's board.
;              This is meant to be called at the same time the player places
;              a ship on the board. It will place the same type of ship but
;              at a random location and orientation.
; ALTERS: A
;------------------------------------------------------------------------------

; We need to use RNG to get three values: the X position, the Y position, and
; the orientation. For this we'll use two random numbers:
;   * Random num 1: YYYY XXXX - Y position in hi nibble, X in lo.
;                               Both values must be between 0 and 9 inclusive.
;   * Random num 2: xxxx xxxO - Orientation in d0.
;
; If the ship cannot be placed with the chosen orientation, the other will be
; tried. If neither works, then new coordinates will be chosen.
orientation = $00         ; Important: orientation and shipType line up with
shipType    = $01         ; the same args for PlaceShipOnBoard
positionX   = $02
positionY   = $03

    LDA $00
    PHA
    LDA $01
    PHA
    LDA $02
    PHA
    LDA $03
    PHA

    LDA shipBeingPlaced
    STA shipType

RngLoop:
    JSR GetNextRng        ; Value for coordinates
    CMP #$9A              ; Quick check - must be <= $99
    BCS RngLoop

    TAY                   ; X-coordinate
    AND #$0F
    CMP #$0A
    BCS RngLoop

    STA positionX

    TYA                   ; Y-coordinate
    LSR
    LSR
    LSR
    LSR
    CMP #$0A
    BCS RngLoop

    STA positionY

    JSR GetNextRng        ; Get the value to use for the orientation
    AND #$01
    STA orientation

    LDX positionX         ; First attempt to place with at this position
    LDY positionY
    CLC
    JSR PlaceShipOnBoard
    BCS End

    LDA orientation       ; Try again with the other orientation
    EOR #$01
    STA orientation
    LDX positionX
    LDY positionY
    CLC
    JSR PlaceShipOnBoard
    BCS End

    JMP RngLoop           ; Oh well. Start from the beginning.

End:
    PLA
    STA $03
    PLA
    STA $02
    PLA
    STA $01
    PLA
    STA $00

    RTS
.endproc

.proc ProcessPlayBoard
; DESCRIPTION: Main routine for the play board.
;------------------------------------------------------------------------------

boardSquare = $00
bowX        = $01
bowY        = $02

    ; Check if we need to initialize the screen
    TYA
    BEQ InitEnd

Init:
    ; Disable rendering and NMI
    LDA #0
    STA PPUMASK

    ; Switch to BL nametable
    LDA ppuControl
    AND #%01111100 ; clear nametable and NMI bits
    ORA #%00000010 ; set nametable bits
    STA ppuControl
    STA PPUCTRL

    ; Load nametable
    LDA #<PlaceShipsMap
    LDX #>PlaceShipsMap
    LDY #>NAMETABLE_BL
    JSR LoadNametable

    ; Load palette
    LDA #<PlaceShipsPalette
    STA currentPalette
    LDX #>PlaceShipsPalette
    STX currentPalette + 1
    JSR LoadPalette

    JSR DrawEmptyMiniMap
    JSR InitAttributeCaches

    ; Enable rendering and NMI
    LDA #%00011110
    STA PPUMASK
    LDA ppuControl
    ORA #%10000000 ; set NMI bit
    STA ppuControl
    STA PPUCTRL

    ; Initialize remaining hits on ships before they sink
    LDX #NUM_SHIPS - 1
:
    LDA ShipLengths,X
    STA playerShipsRemainingHits,X
    STA cpuShipsRemainingHits,X
    DEX
    BPL :-

    LDA #0
    STA cursorX
    STA cursorY
    STA newCursorX
    STA newCursorY
    STA isMainBoardPlayer

@copyPlayerBoardToCpuBoard:
    ; TODO - Remove this section.
    ; This copies the player's board to the CPU's board. Its purpose is to
    ; put something on the CPU board before that is properly implemented.
    LDY #BOARD_NUM_SQUARES - 1
:
    LDA playerBoard,Y
    AND #%10111111 ; clear "has missile" flag
    STA cpuBoard,Y
    DEY
    BPL :-
    JMP DrawCursor

    JMP End ; skip button checks
InitEnd:

    JSR DrawMiniMapOverlay

CheckJoypad:
    LDX cursorX
    STX newCursorX
    LDY cursorY
    STY newCursorY

@checkSelect:
    LDA pressedButtons1
    AND #BUTTON_SELECT
    BEQ @checkDirections

    LDA isMainBoardPlayer
    EOR #%10000000
    STA isMainBoardPlayer
    JSR DrawPlayBoardObjects

@checkDirections:
    ; Do not move or draw the cursor if the main board is displaying the
    ; player's board.
    BIT isMainBoardPlayer
    BPL @checkRight
    JMP DrawCursor

@checkRight:
    LDA pressedButtons1
    AND #BUTTON_RIGHT
    BEQ @checkLeft
    INX
    CPX #BOARD_NUM_COLS
    BCC :+
    LDX #0  ; wrap back to left side
:
    STX cursorX
    JMP @checkDown

@checkLeft:
    LDA pressedButtons1
    AND #BUTTON_LEFT
    BEQ @checkDown
    DEX
    BPL :+
    LDX #BOARD_NUM_COLS - 1 ; wrap back to right side
:
    STX cursorX

@checkDown:
    LDA pressedButtons1
    AND #BUTTON_DOWN
    BEQ @checkUp
    INY
    CPY #BOARD_NUM_ROWS
    BCC :+
    LDY #0  ; wrap back to top row
:
    STY cursorY
    JMP @checkA

@checkUp:
    LDA pressedButtons1
    AND #BUTTON_UP
    BEQ @checkA
    DEY
    BPL :+
    LDY #BOARD_NUM_ROWS - 1 ; wrap back to bottom row
:
    STY cursorY
    JMP DrawCursor

@checkA:
    LDA pressedButtons1
    AND #BUTTON_A
    BNE EnqueueHitOrMissTiles
    
    JMP DrawCursor

EnqueueHitOrMissTiles:
    LDX cursorX
    LDY cursorY
    JSR GetBoardArrayIdFromXY
    JSR FireMissileOnSquare
    BCS :+
    JMP DrawCursor

:
    ; Place the hit or miss tile on the board.
    ; First, determine the correct tile (hit or miss).
    BNE :+
    LDA #MISS_SQUARE_TILE
    BCS @storeTiles
:
    ; If this hit sinks a ship, reveal the ship. Otherwise, place a hit tile.
    LDX cursorX
    LDY cursorY
    JSR GetBoardArrayIdFromXY
    TAY
    LDA cpuBoard,Y
    JSR GetShipIdFromBoardByte
    TAY
    LDA cpuShipsRemainingHits,Y
    BEQ @revealShip

    LDA #HIT_SQUARE_TILE
    JMP @storeTiles

@revealShip:
    LDX cursorX
    LDY cursorY
    CLC
    JSR FindBowOfShip

    STX bowX
    STY bowY

    JSR GetBoardArrayIdFromXY
    TAY
    LDA cpuBoard,Y
    LDX bowX
    LDY bowY
    JSR DrawWholeShip
    JMP @updateSquareAttribute

@storeTiles:
    ; Write the tile data to the queues.
    ; Use queues 2 and 3 because that's what DrawWholeShip uses.
    STA NQUEUE2
    CLC
    ADC #1
    STA NQUEUE2 + 1
    ADC #CHAR_TILES_PER_ROW - 1
    STA NQUEUE3
    ADC #1
    STA NQUEUE3 + 1
    
    ; Terminators
    LDA #0
    STA NQUEUE2 + 2
    STA NQUEUE3 + 2

    ; Nametable pointers
    LDX cursorX
    LDY cursorY
    JSR GetSquareNametablePtrFromXY  ; preserves Y register
    STA nametableQueueAddressHi + 2      ; NQUEUE0
    STX nametableQueueAddressLo + 2
    STA nametableQueueAddressHi + 3  ; NQUEUE1
    TXA
    CLC
    ADC #NAMETABLE_TILES_PER_LINE
    STA nametableQueueAddressLo + 3

    ; Nametable write direction
    LDA ppuControl
    AND #%11111011
    ORA #NAMETABLE_QUEUE_STATUS_HORIZONTAL
    STA nametableQueueStatus + 2
    STA nametableQueueStatus + 3

@updateSquareAttribute:
    ; Use queue 0 since it's available.
    CLC
    LDX cursorX
    LDY cursorY
    LDA #PALETTE_HIT_OR_MISS
    JSR UpdateAttributeCacheForOneSquareXY

    STY nametableQueueAddressHi
    STX nametableQueueAddressLo
    STA NQUEUE0  ; hopefully never 0
    LDA #0
    STA NQUEUE0 + 1

DrawCursor:
    LDX cursorX
    LDY cursorY
    JSR DrawPlayBoardFireCursor

End:
    JMP MainLoop
.endproc

.proc DrawEmptyMiniMap
; DESCRIPTION: Draw the mini map, used to see the secondary grid, to the
;              nametable. The mini map is drawn with no ships placed.
;------------------------------------------------------------------------------
TILES_PER_ROW = 6
NUM_ROWS      = 6
START_OFFSET  = $58
DELTA_OFFSET  = $20

    BIT PPUSTATUS

    LDA #START_OFFSET
    PHA

    LDY #0 ; Y = row counter
@rowLoop:
    LDA #>NAMETABLE_BL
    STA PPUADDR
    PLA
    STA PPUADDR
    CLC
    ADC #DELTA_OFFSET
    PHA

    LDX #0 ; X = tile on row counter
@tileLoop:
    CPY #0
    BNE :+
    ; Top row
    LDA MiniMapTopRow,X
    JMP @tileLoop_iterate

:
    ; Everything but the top row
    LDA MiniMapGridRow,X

@tileLoop_iterate:
    STA PPUDATA
    INX
    CPX #TILES_PER_ROW
    BCC @tileLoop ; branch if X < TILES_PER_ROW

    INY
    CPY #NUM_ROWS
    BCC @rowLoop

End:
    PLA
    RTS

T = $A0 ; top edge tile
E = $00 ; empty tile
G = $C0 ; grid tile
R = $CC ; right edge tile
MiniMapTopRow:  .byte T, T, T, T, T, E
MiniMapGridRow: .byte G, G, G, G, G, R
.endproc

.proc DrawMiniMapOverlay
; DESCRIPTION: Draw ships, hits, and misses to the mini map.
;              The mini map is arranged as ten rows of five sprites (50 sprites
;              total). Each sprite covers two horizontally adjacent squares.
;              Each square has four visual states:
;                0 = no ship, no missile (empty)
;                1 = no ship, missile    (miss)
;                2 = ship, no missile    (ship if player's board; empty if cpu)
;                3 - ship, missile       (hit)
;
;              Tile addresses $00-$0F represent the 16 possibile states of two
;              squares: d3 d2 for the left square, d1 d0 for the right.
;              Bits d7 and d6 of bytes in the board arrays have the correct
;              value to use for the mini map board square sprite tiles.
; ALTERS: A, X, Y
;------------------------------------------------------------------------------
spriteTile     = $00
spriteX        = $01
spriteY        = $02
bufferIndex    = $03
columnCount    = $04
boardPtr       = $05 ; 2 bytes

SPRITE_ATTRIBUTES  = %00000010 ; no flipping, normal priority, palette 2
BUFFER_START_INDEX = $10
NUM_COLUMNS        = 5
START_X            = 192
START_Y            = 19

    LDA #START_Y
    STA spriteY
    LDX #BUFFER_START_INDEX
    STX bufferIndex
    LDY #0

    BIT isMainBoardPlayer
    BMI :+
    ; mini map is the player's board
    LDA #<playerBoard
    STA boardPtr
    LDA #>playerBoard
    STA boardPtr + 1
    JMP BoardSquareLoop
:
    ; mini map is the CPU's board
    LDA #<cpuBoard
    STA boardPtr
    LDA #>cpuBoard
    STA boardPtr + 1

BoardSquareLoop:
    LDA #NUM_COLUMNS
    STA columnCount
    LDA #START_X
    STA spriteX

@columnLoop:
    CLC
    LDA #0
    STA spriteTile

    LDA (boardPtr),Y
    ROL                         ; move "has ship" bit to carry
    ROL spriteTile
    ROL                         ; move "has missile" bit to carry
    ROL spriteTile
    INY                         ; repeat for the right square

    LDA (boardPtr),Y
    ROL
    ROL spriteTile
    ROL
    ROL spriteTile
    INY

    ; Write to OAMBUFFER
    LDX bufferIndex
    LDA spriteY
    STA OAMBUFFER,X
    INX
    LDA spriteTile
    STA OAMBUFFER,X
    INX
    LDA #SPRITE_ATTRIBUTES
    STA OAMBUFFER,X
    INX
    LDA spriteX
    STA OAMBUFFER,X
    CLC               ; iterate sprite X position
    ADC #8
    STA spriteX
    INX
    STX bufferIndex

    ; Repeat for next square pair in row
    DEC columnCount
    BNE @columnLoop

@iterate:
    CLC               ; iterate sprite Y position
    LDA spriteY
    ADC #4
    STA spriteY

    CPY #BOARD_NUM_SQUARES
    BCC BoardSquareLoop

End:
    RTS
.endproc

.proc DrawPlayBoardObjects
; DESCRIPTION: Draws hits, misses, and ships on the main board grid.
; ALTERS: A, X, Y
;------------------------------------------------------------------------------
currentRowStart    = $00
nextRowStart       = $01
nametablePtrLo     = $02
nametablePtrHi     = $03
isBottomRow        = $04 ; set d7 = 1 if on the bottom half of a row of squares
remainingTileRows  = $05
remainingTileCols  = $06
boardPtr           = $07 ; 2 bytes
;attributes         = $09 ; 6 bytes

BOARD_NAMETABLE_OFFSET = $102
BOARD_ATTRIBUTE_OFFSET = $3D0
EMPTY_TILE_UL = EMPTY_SQUARE_TILE
EMPTY_TILE_UR = EMPTY_SQUARE_TILE + 1
EMPTY_TILE_BL = EMPTY_SQUARE_TILE + $10
EMPTY_TILE_BR = EMPTY_SQUARE_TILE + $11

    LDA #0
    STA currentRowStart
    ;STA currentCol
    STA isBottomRow
    LDA #10
    STA nextRowStart
    LDA #BOARD_NUM_ROWS * 2   ; 2 tile rows per square row
    STA remainingTileRows

    CLC
    LDA #<NAMETABLE_BL
    ADC #<BOARD_NAMETABLE_OFFSET
    STA nametablePtrLo
    LDA #>NAMETABLE_BL
    ADC #>BOARD_NAMETABLE_OFFSET
    STA nametablePtrHi

    BIT isMainBoardPlayer
    BMI :+
    ; main board is CPU
    LDA #<cpuBoard
    STA boardPtr
    LDA #>cpuBoard
    STA boardPtr + 1
    JMP DisableRendering
:
    ; main board is player
    LDA #<playerBoard
    STA boardPtr
    LDA #>playerBoard
    STA boardPtr + 1

DisableRendering:
    ; Disable NMI and rendering
    LDA #0
    STA PPUMASK
    LDA ppuControl
    AND #%01111100 ; clear nametable and NMI bits
    ORA #%00000010 ; set nametable bits
    STA ppuControl
    STA PPUCTRL

    BIT PPUSTATUS  ; prepares PPUADDR
; End init

    ; The outer loop (RowLoop) is over tile rows from top to bottom. Because
    ; each board square covers two tile rows, we need to read the same section
    ; of the board array twice: first for the top set of tiles from left to
    ; right and second for the bottom set.
RowLoop:
    LDA #BOARD_NUM_COLS
    STA remainingTileCols

    LDA nametablePtrHi
    STA PPUADDR
    LDA nametablePtrLo
    STA PPUADDR

    LDY currentRowStart

ColumnLoop:
    ; Determine which 2x2-tile square to draw.
    ;
    ; Psuedocode:
    ;   if no ship:
    ;       if missile: MISS
    ;       else: EMPTY
    ;   else if no missile:
    ;       if playerBoard: SHIP
    ;       else: EMPTY
    ;   else:
    ;       if playerBoard: SHIP
    ;       else if ship sunk: SHIP
    ;       else: HIT
    ;
    LDA (boardPtr),Y
    BMI @ifShip

@ifNoShip:
    AND #%01000000
    BEQ @ifNoShipAndNoMissile
    LDA #MISS_SQUARE_TILE
    JMP @drawTile

@ifNoShipAndNoMissile:
    LDA #EMPTY_SQUARE_TILE
    JMP @drawTile

@ifShip:
    AND #%01000000
    BEQ @elseIfNoMissile

@elseIfMissile:
    BIT isMainBoardPlayer
    BMI @chooseShipTile
    ; TODO: draw ship tile on CPU's board if ship sunk
    LDA #HIT_SQUARE_TILE
    JMP @drawTile

@elseIfNoMissile:
    BIT isMainBoardPlayer
    BMI @chooseShipTile
    LDA #EMPTY_SQUARE_TILE
    JMP @drawTile

@chooseShipTile:
    LDA (boardPtr),Y
    AND #%00000111
    TAX
    LDA ShipTiles,X

@drawTile:
    BIT isBottomRow
    BPL :+
    CLC
    ADC #CHAR_TILES_PER_ROW
:
    STA PPUDATA
    CLC
    ADC #1
    STA PPUDATA
    JMP @iterate

@iterate:
    INY
    DEC remainingTileCols
    BNE ColumnLoop

    DEC remainingTileRows
    BEQ SetPalettes

    ; Prepare the next row
    CLC
    LDA nametablePtrLo
    ADC #32
    STA nametablePtrLo
    LDA nametablePtrHi
    ADC #0
    STA nametablePtrHi

    BIT isBottomRow
    BMI @prepTopTileRow  ; branch if currently bottom, switch to top

@prepBottomTileRow:
    LDA #%10000000
    STA isBottomRow
    JMP RowLoop

@prepTopTileRow:
    LDA #0
    STA isBottomRow
    LDA nextRowStart
    STA currentRowStart
    CLC
    ADC #BOARD_NUM_COLS
    STA nextRowStart
    JMP RowLoop

SetPalettes:
    BIT isMainBoardPlayer
    BMI :+
    ; main board is CPU
    LDA #<cpuBoardAttributeCache
    STA boardPtr
    LDA #>cpuBoardAttributeCache
    STA boardPtr + 1
    JMP @copyAttributeCache
:
    ; main board is player
    LDA #<playerBoardAttributeCache
    STA boardPtr
    LDA #>playerBoardAttributeCache
    STA boardPtr + 1

@copyAttributeCache:
    LDY #0                               ; attribute cache index
    LDA #>BOARD_ATTRIBUTE_PTR
    STA nametablePtrHi
    LDA #<BOARD_ATTRIBUTE_PTR
    STA nametablePtrLo

@cacheRowLoop:
    LDX #ATTRIBUTE_CACHE_BYTES_PER_ROW   ; remaining columns
    LDA nametablePtrHi
    STA PPUADDR
    LDA nametablePtrLo
    STA PPUADDR

@cacheColLoop:
    LDA (boardPtr),Y
    STA PPUDATA
    INY

    DEX
    BNE @cacheColLoop

    CPY #ATTRIBUTE_CACHE_NUM_BYTES
    BCS End

    LDA nametablePtrLo                        ; carry is clear
    ADC #NAMETABLE_ATTRIBUTE_BYTES_PER_LINE
    STA nametablePtrLo
    JMP @cacheRowLoop

; SetPalettes:
;     ; Loop through the board squares one more time to set the palettes in the
;     ; nametable attributes.
;     ;
;     ; The main board is positioned such that square (0,0) occupies the upper-
;     ; right quadrant of a 4-tile by 4-tile attribute region.
;     ;
;     ; ,---+---+---+---.
;     ; |   |   |   |   |
;     ; + D1-D0 + D3-D2 +
;     ; |   |   |   |   |
;     ; +---+---+---+---+
;     ; |   |   |   |   |
;     ; + D5-D4 + D7-D6 +
;     ; |   |   |   |   |
;     ; `---+---+---+---'
;     ;
;     ; The loop is actually over attribute bytes, left to right then top to
;     ; bottom.
;     ;
; topRowArrayId          = currentRowStart      ; reuse variables
; bottomRowArrayId       = nextRowStart
; attribute              = isBottomRow
; remainingAttributeRows = remainingTileRows

;     CLC
;     LDA #<NAMETABLE_BL
;     ADC #<BOARD_ATTRIBUTE_OFFSET
;     STA nametablePtrLo
;     LDA #>NAMETABLE_BL
;     ADC #>BOARD_ATTRIBUTE_OFFSET
;     STA nametablePtrHi

;     ; A single attribute byte covers two rows of the board array. We track
;     ; those array indexes separately to avoid having to constantly add
;     ; and subtract 10.
;     LDA #0
;     STA topRowArrayId
;     LDA #10
;     STA bottomRowArrayId
;     LDA #5
;     STA remainingAttributeRows

; @rowLoop:
;     ; Set up PPUADDR
;     LDA nametablePtrHi
;     STA PPUADDR
;     LDA nametablePtrLo
;     STA PPUADDR

;     ; The left-most column is special since it includes the text labels for the
;     ; rows, and text has its own palette.
;     LDY topRowArrayId   ; square in upper-right quadrant 
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     ASL  ; scooch over to d3d2
;     ASL
;     ORA #ATTRIBUTE_MASK_LEFT
;     STA attribute

;     LDY bottomRowArrayId ; square in bottom-right quadrant 
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     CLC ; scooch over to d7d6
;     ROR  
;     ROR
;     ROR
;     ORA attribute
;     STA PPUDATA

;     INC topRowArrayId
;     INC bottomRowArrayId

;     ; The next four attribute bytes only contain board squares and can be
;     ; handled in a loop.
;     LDX #4 ; X = remaining attribute bytes for loop
; @middleLoop:
;     LDY topRowArrayId   ; upper-left (d1d0)
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     STA attribute

;     INY                 ; upper-right (d3d2)
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     ASL
;     ASL
;     ORA attribute
;     STA attribute

;     INY
;     STY topRowArrayId

;     LDY bottomRowArrayId ; bottom-left (d5d4)
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     ASL
;     ASL
;     ASL
;     ASL
;     ORA attribute
;     STA attribute

;     INY                 ; bottom-right (d7d6)
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     CLC
;     ROR
;     ROR
;     ROR
;     ORA attribute
;     STA PPUDATA

;     INY
;     STY bottomRowArrayId
    
;     DEX
;     BEQ @lastColumn
;     JMP @middleLoop

; @lastColumn:
;     ; The last column, like the first, is special because the right-most
;     ; squares are not part of the board.

;     LDY topRowArrayId   ; upper-left (d1d0)
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     STA attribute
;     ; INY
;     ; STY topRowArrayId

;     LDY bottomRowArrayId ; bottom-left (d5d4)
;     LDA (boardPtr),Y
;     JSR GetPaletteFromBoardSquareValue
;     ASL
;     ASL
;     ASL
;     ASL
;     ORA attribute
;     ORA #ATTRIBUTE_MASK_RIGHT
;     STA PPUDATA

;     ; Row iteration logic
;     DEC remainingAttributeRows
;     BEQ End

;     CLC
;     LDA topRowArrayId 
;     ADC #BOARD_SQUARES_PER_LINE + 1 
;     STA topRowArrayId
;     LDA bottomRowArrayId
;     ADC #BOARD_SQUARES_PER_LINE + 1
;     STA bottomRowArrayId
;     JMP @rowLoop

End:
    ; Enable rendering and NMI
    LDA #%00011110
    STA PPUMASK
    LDA ppuControl
    ORA #%10000000 ; set NMI bit
    STA ppuControl
    STA PPUCTRL

    RTS

ShipTiles:
    .byte SHIP_BOW_HORIZ_TILE, SHIP_BOW_VERT_TILE
    .byte SHIP_MID_HORIZ_TILE, SHIP_MID_VERT_TILE
    .byte SHIP_STERN_HORIZ_TILE, SHIP_STERN_VERT_TILE

.endproc

.proc DrawPlayBoardFireCursor
; DESCRIPTION: Draws the cursor the player moves on the play board to fire upon
;              enemy ships. If the main board is the player's board, then the
;              cursor is cleared from the screen.
; PARAMETERS:
;  * X - X coordinate
;  * Y - Y coordinate
; ALTERS: A, X, Y
;------------------------------------------------------------------------------
spriteX = $00
spriteY = $01

BUFFER_START_INDEX = $00
SPRITE_TILE        = $10
ATTRIBUTES         = $01  ; palette 1
TILE_WIDTH         = $08

    BIT isMainBoardPlayer
    BPL DrawCursor

ClearCursor:
    LDY #16    ; number of bytes to write
    LDX #BUFFER_START_INDEX
    LDA #$FF
@loop:
    STA OAMBUFFER,X
    INX
    DEY
    BNE @loop
    JMP End

DrawCursor:
    LDA StartPixelX,X
    STA spriteX
    LDA StartPixelY,Y
    STA spriteY
    
    LDX #BUFFER_START_INDEX
    
    ; Upper-left sprite
    LDA spriteY
    STA OAMBUFFER,X
    INX
    LDA #SPRITE_TILE
    STA OAMBUFFER,X
    INX
    LDA #ATTRIBUTES
    STA OAMBUFFER,X
    INX
    LDA spriteX
    STA OAMBUFFER,X
    INX
    
    ; Upper-right sprite
    LDA spriteY
    STA OAMBUFFER,X
    INX
    LDA #SPRITE_TILE
    STA OAMBUFFER,X
    INX
    LDA #ATTRIBUTES
    ORA #%01000000     ; flip horizontally
    STA OAMBUFFER,X
    INX
    LDA spriteX
    CLC
    ADC #TILE_WIDTH + 1  ; +1 accounts for the tile not being centered
    STA OAMBUFFER,X
    INX
    
    ; Bottom-left sprite
    LDA spriteY
    CLC
    ADC #TILE_WIDTH - 1
    STA OAMBUFFER,X
    INX
    LDA #SPRITE_TILE
    STA OAMBUFFER,X
    INX
    LDA #ATTRIBUTES
    ORA #%10000000     ; flip vertically
    STA OAMBUFFER,X
    INX
    LDA spriteX
    STA OAMBUFFER,X
    INX

    ; Bottom-right sprite
    LDA spriteY
    CLC
    ADC #TILE_WIDTH - 1
    STA OAMBUFFER,X
    INX
    LDA #SPRITE_TILE
    STA OAMBUFFER,X
    INX
    LDA #ATTRIBUTES
    ORA #%11000000     ; flip vertically and horizontally
    STA OAMBUFFER,X
    INX
    LDA spriteX
    CLC
    ADC #TILE_WIDTH + 1
    STA OAMBUFFER,X

End:
    RTS

X0 = 16
Y0 = 63
StartPixelX:
  .byte X0, X0 + 16, X0 + 2*16, X0 + 3*16, X0 + 4*16
  .byte X0 + 5*16, X0 + 6*16, X0 + 7*16, X0 + 8*16, X0 + 9*16
StartPixelY:
  .byte Y0, Y0 + 16, Y0 + 2*16, Y0 + 3*16, Y0 + 4*16
  .byte Y0 + 5*16, Y0 + 6*16, Y0 + 7*16, Y0 + 8*16, Y0 + 9*16
.endproc

.proc FireMissileOnSquare
; DESCRIPTION: Fires a missile at a board square.
;              The main board is always the board fired upon.
;              Sets the "fired upon" flag on the square.
; PARAMETERS:
;  * A - Array ID of the board square to fire upon
; RETURNS:
;  * C - set if missile fired; clear if not (square already fired upon)
;  * Z - set if miss; clear if hit; check only if C set
; ALTERS: A, X, Y
;------------------------------------------------------------------------------
FIRED_UPON_BIT_MASK = %01000000
    TAY
    BIT isMainBoardPlayer
    BMI :+
    LDA cpuBoard,Y
    JMP CheckIfAlreadyFiredUpon
:
    LDA playerBoard,Y

CheckIfAlreadyFiredUpon:
    PHA               ; save the board byte for later
    AND #FIRED_UPON_BIT_MASK
    BEQ FireMissile

    ; Quit since the square has already been fired upon
    PLA
    CLC
    RTS

FireMissile:
    PLA                       ; set the fired-upon flag on the board square
    ORA #FIRED_UPON_BIT_MASK
    BIT isMainBoardPlayer
    BMI :+
    STA cpuBoard,Y
    JMP DecrementRemainingHits
:
    STA playerBoard,Y

DecrementRemainingHits:
    TAY
    JSR GetShipIdFromBoardByte
    TAX

    BIT isMainBoardPlayer
    BMI :+
    DEC cpuShipsRemainingHits,X
    JMP End
:
    DEC playerShipsRemainingHits,X

End:
    SEC
    TYA
    AND #%10000000   ; set/clear Z flag
    RTS
.endproc



.proc DrawWholeShip
; DESCRIPTION: Draw all parts of a ship. Uses NQUEUE2 and NQUEUE3.
; PARAMETERS:
;  * X - X coordinate of bow
;  * Y - Y coordinate of bow
;  * A - Byte containing the ship ID in d5-d3 and the orientation in d0.
;        This is the same structure as a board square byte.
; AFFECTS: X, Y
;------------------------------------------------------------------------------

; TODO: Allow choosing queues 0/1 or 2/3

boardSquare      = $00
shipNumTiles     = $01
shipTilePtr      = $02 ; 2 bytes

    PHA         ; Push the board square parameter to the stack. It can't be
                ; written to the local variable yet because those memory
                ; locations haven't been saved off yet.

    LDA $00
    PHA
    LDA $01
    PHA
    LDA $02
    PHA
    LDA $03
    PHA

    TXA         ; Save the X coordinate
    PHA

    TSX
    LDA STACK + 6,X  ; Retrieve the board square byte.
    STA boardSquare

    ; Set up the nametable pointers
    ; The NQUEUE2 address is the same for both orientations.
    ; NQUEUE3 and NQUEUE2 have the same hi byte.
    ; NQUEUE3's lo byte is determine later since it's orientation-dependent.
    PLA                             ; Restore the X-coordinate.
    TAX
    JSR GetSquareNametablePtrFromXY ; A and X hold the hi and lo pointers.
    STA nametableQueueAddressHi + 2
    STX nametableQueueAddressLo + 2
    STA nametableQueueAddressHi + 3

SetUpOrientationDependentVars:
    ; Set up variable which depend on the ship's orientation.

    LDA boardSquare
    LSR ; move orientation to carry
    BCS @vertical

@horizontal:
    ; Ship graphics pointer
    LDA boardSquare
    JSR GetShipIdFromBoardByte
    TAY
    LDA ShipTilesHorizontalLo,Y
    STA shipTilePtr
    LDA ShipTilesHorizontalHi,Y
    STA shipTilePtr + 1

    ; Nametable pointer
    TXA
    CLC
    ADC #NAMETABLE_TILES_PER_LINE
    STA nametableQueueAddressLo + 3
    LDY #NAMETABLE_QUEUE_STATUS_HORIZONTAL
    JMP SetNametableStatus

@vertical:
    ; Ship graphics pointer
    LDA boardSquare
    JSR GetShipIdFromBoardByte
    TAY
    LDA ShipTilesVerticalLo,Y
    STA shipTilePtr
    LDA ShipTilesVerticalHi,Y
    STA shipTilePtr + 1
    
    ; Nametable pointer
    INX
    STX nametableQueueAddressLo + 3
    LDY #NAMETABLE_QUEUE_STATUS_VERTICAL

SetNametableStatus:
    STY nametableQueueStatus + 2
    LDA ppuControl
    AND #%11111011
    ORA nametableQueueStatus + 2
    STA nametableQueueStatus + 2
    STA nametableQueueStatus + 3

InitTileQueueLoop:
    ; Get the number of squares to loop over
    LDA boardSquare
    JSR GetShipIdFromBoardByte
    TAY
    LDA ShipLengths,Y
    ASL                ; double to get length in tiles
    STA shipNumTiles
    LDY #0

@nQueue2Loop:
    ; The tile and queue indices are in sync for the NQUEUE2 loop, so we just
    ; use Y for NQUEUE2.
    LDA (shipTilePtr),Y
    STA NQUEUE2,Y

    INY
    CPY shipNumTiles
    BCC @nQueue2Loop

    ; Write the terminator
    LDA #0
    STA NQUEUE2,Y

    ; Double the end of the loop for the second half (bottom or right)
    LDA shipNumTiles
    ASL
    STA shipNumTiles

    LDX #0
@nQueue3Loop:
    LDA (shipTilePtr),Y
    STA NQUEUE3,X

    INX
    INY
    CPY shipNumTiles
    BCC @nQueue3Loop

    ; Write the terminator
    LDA #0
    STA NQUEUE3,X

End:
    PLA
    STA $03
    PLA
    STA $02
    PLA
    STA $01
    PLA
    STA $00

    PLA

    RTS
.endproc

;##############################################
; GAME LOGIC SUBROUTINES
;##############################################

.proc GetNextRng
; DESCRIPTION: Get the next RNG value.
;              The RNG is implemented as an 8-bit linear feedback shift
;              register (LFSR) with maximal length. The shift bit is:
;                  shift bit = d7 ^ d5 ^ d4 ^ d3 ^ d0
; RETURNS:
;  * A - New RNG value
;------------------------------------------------------------------------------
shiftedRng = $00
nextBit    = $01  ; d7 holds the result of the XOR

    LDA $00
    PHA
    LDA $01
    PHA

    LDA rng
    STA shiftedRng

    ; d7
    STA nextBit        

    ; d7 ^ d5
    ASL
    ASL
    STA shiftedRng
    EOR nextBit
    STA nextBit

    ; d7 ^ d5 ^ d4
    LDA shiftedRng
    ASL
    STA shiftedRng
    EOR nextBit
    STA nextBit

    ; d7 ^ d5 ^ d4 ^ d3
    LDA shiftedRng
    ASL
    STA shiftedRng
    EOR nextBit     ; final value of the XOR
    ASL             ; shift next bit to carry
    ROL rng

End:
    PLA
    STA $01
    PLA
    STA $00

    LDA rng
    RTS
.endproc

.proc GetSquareNametablePtrFromXY
; DESCRIPTION: Given a board square's position at (X,Y),
;              compute the nametable address of the top-left
;              corner of the square.
; PARAMETERS:
;  * X - X coordinate
;  * Y - Y coordinate
; RETURNS:
;  * X - Hi byte of nametable pointer
;  * A - Lo byte of nametable pointer
;-------------------------------------------------------------------------------
NAMETABLE_LEFT_MARGIN = 2         ; 2 empty tiles to the left of the board
    ; Lo byte = (nametable lo at line start) + (margin) + 2*X 
    TXA
    ASL                           ; 2*X
    CLC
    ADC OffsetLo,Y                ; nametable lo at line start
    ADC #NAMETABLE_LEFT_MARGIN    ; margin
    TAX                           ; X output
    LDA OffsetHi,Y                ; A output
    RTS

; Both of these are indexed by the Y coordinate
OffsetHi:
  .byte $29,$29,$29,$29,$2A,$2A,$2A,$2A,$2B,$2B
OffsetLo:
  .byte $00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40
.endproc


.proc GetBoardSquareFromXY
; DESCRIPTION: Get the tile at board coordinate (X,Y)
; PARAMETERS:
;  * X - X coordinate
;  * Y - Y coordinate
; RETURNS:
;  * A - char tile of square at (X,Y)
; TODO: support both boards
    JSR GetBoardArrayIdFromXY
    TAY
    JSR GetBoardSquareTileFromArrayId
    RTS
.endproc

.proc GetBoardSquareTileFromArrayId
; DESCRIPTION: Get a char tile of a board from an array ID
; PARAMETERS:
;  * Y - array ID
; RETURNS:
;  * A - char tile of square at the array ID
;-------------------------------------------------------------------------------
    ; Check if there is a ship (bit 7)
    BIT isMainBoardPlayer
    BMI :+
    LDA cpuBoard,Y
    JMP @checkForShip
:
    LDA playerBoard,Y

@checkForShip:
    TAX
    AND #%10000000
    BNE @getTile
    LDA #EMPTY_SQUARE_TILE
    RTS

@getTile:
    ; Return tile based on bits 2-0 (ship section and orientation)
    TXA
    AND #%00000111
    TAY
    LDA Tiles,Y
    RTS

Tiles:
  .byte SHIP_BOW_HORIZ_TILE,SHIP_BOW_VERT_TILE
  .byte SHIP_MID_HORIZ_TILE,SHIP_MID_VERT_TILE
  .byte SHIP_STERN_HORIZ_TILE,SHIP_STERN_VERT_TILE
.endproc

.proc GetBoardArrayIdFromXY
; DESCRIPTION: Convert a board coordinate given as (X,Y) to its position
;              in the board array.
; PARAMETERS:
;  * X - X coordinate
;  * Y - Y coordinate
; RETURNS:
;  * A - position in the array (A = 10*Y + X)
;-------------------------------------------------------------------------------
    TXA
    CLC
    ADC OffsetY,Y
    RTS
OffsetY:
  .byte 0,10,20,30,40,50,60,70,80,90
.endproc

.proc GetShipIdFromBoardByte
; DESCRIPTION: Isolate the ship ID part of a board byte.
; PARAMETERS:
;  * A - Board byte
; RETURNS:
;  * A - Ship ID
;------------------------------------------------------------------------------
    LSR
    LSR
    LSR
    AND #%00000111
    RTS
.endproc

.proc GetNextShipToPlace
; DESCRIPTION: Get the ID of the next unplaced ship.
; PARAMETERS:
;  * Y - ID of ship to start with. This routine will first check the ship
;        AFTER this one.
; RETURNS:
;  * A = ID of the next unplaced ship or $FF if all ships have been placed
;-------------------------------------------------------------------------------
    LDX #NUM_SHIPS ; X = count of remaining ships to check

Loop:
    INY            ; Y = ship to check
    CPY #NUM_SHIPS ; wrap around to patrol boat
    BCC :+
    LDY #0       

:
    LDA placedShipsX,Y  ; d7 = 1 means the ship has not already been placed
    BMI End

    DEX
    BNE Loop

    LDY #$FF  ; all ships have been placed
End:
    TYA
    RTS
.endproc

.proc FindBowOfShip
; DESCRIPTION: Given the (X,Y) coordinates of a part of a ship on a board, find
;              the (X,Y) coordinates of the bow of the ship.
; PARAMETERS:
;  * X - Starting X-coordinate
;  * Y - Starting Y-coordinate
;  * C - set if player's board; clear if CPU's board
; RETURNS:
;  * X - X-coordinate of the bow of the ship or $FF if no ship
;  * Y - Y-coordinate of the bow of the ship or $FF if no ship
;------------------------------------------------------------------------------

boardPtr = $00 ; 2 bytes
currentX = $02
currentY = $03

    LDA $00
    PHA
    LDA $01
    PHA
    LDA $02
    PHA
    LDA $03
    PHA

    STX currentX
    STY currentY

    ; Set up the board pointer
    BCS :+
    LDA #<cpuBoard
    STA boardPtr
    LDA #>cpuBoard
    STA boardPtr + 1
    JMP InitLoop

:
    LDA #<playerBoard
    STA boardPtr
    LDA #>playerBoard
    STA boardPtr + 1

InitLoop:
    LDX currentX
    LDY currentY
    JSR GetBoardArrayIdFromXY
    TAY
    LDA (boardPtr),Y

    ; Quit if there's no ship
    BMI @loop
    LDA #$FF
    STA currentX
    STA currentY
    BNE End

@loop:
    LDX currentX
    LDY currentY
    JSR GetBoardArrayIdFromXY
    TAY
    LDA (boardPtr),Y

    LSR                  ; put orientation in carry
    AND #%00000011       ; isolate ship section ($0 = bow)
    BEQ End

    ; Change X and Y to the next square closer to the bow.
    ; The bow is always the minimum (X,Y) of the ship.
    BCS :+
    DEC currentX
    BPL @loop    ; Will always branch

:
    DEC currentY
    BPL @loop

End:
    LDX currentX
    LDY currentY

    PLA
    STA $03
    PLA
    STA $02
    PLA
    STA $01
    PLA
    STA $00

    RTS
.endproc

.proc IsNewCursorShipOnSquareXY
; DESCRIPTION: Check if the new cursor ship occupies (X,Y).
; PARAMETERS:
;  * X - X coordinate
;  * Y - Y coordinate
; RETURNS:
;  * Sets Z flag if true
;-------------------------------------------------------------------------------
;cursorXOrYPlusLength = $00

    LDA newOrientation
    BNE @vertical
    ; horizontal - Y must match
    CPY newCursorY
    BNE End
    ; X must be between cursorX and cursorX + ( ship length - 1 ) (inclusive)
    CPX newCursorX
    BCC End  ; quit if X < cursorX (also clears Z)

    TXA
    LDY newShip
    SBC ShipLengths,Y ; C already set
    BMI End_SetZ      ; CMP is unsigned so check if negative first
    CMP newCursorX
    BCC End_SetZ
    BCS End_ClearZ

@vertical:
    ; vertical - X must match
    CPX newCursorX
    BNE End
    ; Y must be between cursorY and cursorY + ( ship length - 1 ) (inclusive)
    CPY newCursorY
    BCC End  ; quit if Y < cursorY (also clears Z)

    TYA
    LDX newShip
    SBC ShipLengths,X ; C already set
    BMI End_SetZ      ; CMP is unsigned so check if negative first
    CMP newCursorY
    BCC End_SetZ
    BCS End_ClearZ

End_ClearZ:
    LDA #1
    RTS
End_SetZ:
    LDA #0
End:
    RTS
.endproc

.proc GetPaletteFromBoardSquareValue
; DESCRIPTION: Compute the palette to use for a square on the main board from
;              the square's value.
; PARAMETERS:
;  * A - The square's value
; RETURNS:
;  * A - Palette ID
; ALTERS: A
;------------------------------------------------------------------------------
PALETTE_UNHIT_SHIP_OR_EMPTY  = $00 
PALETTE_HIT_OR_MISS          = $01

    AND #%01000000
    BEQ :+
    LDA #PALETTE_HIT_OR_MISS
    RTS
:
    LDA #PALETTE_UNHIT_SHIP_OR_EMPTY
    RTS
.endproc

;##############################################
; GRAPHICS AND I/O SUBROUTINES
;##############################################

.proc ReadJoypads
changed1 = $00
changed2 = $01
; Copied from https://www.nesdev.org/wiki/Controller_reading_code
; At the same time that we strobe bit 0, we initialize the ring counter
; so we're hitting two birds with one stone here

    ; I added the previous states
    LDA buttons1
    STA prevButtons1
    LDA buttons2
    STA prevButtons2


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
    ; WARNING - This enables the frame counter IRQ because JOYPAD2 = $4017!
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

EvaluateStateChange:
    ; Check held buttons (previous = current = 1)
    LDA buttons1
    AND prevButtons1
    STA heldButtons1
    LDA buttons2
    AND prevButtons2
    STA heldButtons2

    ; TODO: controller 2
    LDA buttons1
    EOR prevButtons1
    STA changed1
    AND prevButtons1 ; released
    STA releasedButtons1
    LDA changed1
    AND buttons1     ; pressed
    STA pressedButtons1


End:
    rts
.endproc

.proc LoadNametable
; DESCRIPTION: Load a nametable
; PARAMETERS:
;  * A - lo byte of data address
;  * X - hi byte of data address
;  * Y - hi byte of nametable address to write to ($YY00)
sourceData = $00

    STA sourceData
    STX sourceData + 1

    ; setup address in PPU for nametable data
    BIT PPUSTATUS ; clear w flag
    STY PPUADDR
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

.proc SetNmiFlagLoadPalette
; DESCRIPTION: Tells the NMI routine to load the palette with
;              pointer at currentPalette the next NMI.
;------------------------------------------------------------------------------
    LDA nmiFlags
    ORA #%10000000
    STA nmiFlags
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

    BIT PPUSTATUS
    LDA #$3F    ; $3F00 - $3F1F (palette RAM)
    STA PPUADDR
    LDA #$00
    STA PPUADDR

    TAY
:
    LDA (sourceData), Y
    STA PPUDATA ; $3F00, $3F01, $3F02 => $3F1F
    INY
    CPY #$20
    BNE :-
    RTS
.endproc

;##############################################
; ATTRIBUTE CACHE ROUTINES
;##############################################

PALETTE_UNHIT_SHIP_OR_EMPTY  = $00 
PALETTE_HIT_OR_MISS          = $01
PALETTE_TEXT                 = $03
ATTRIBUTE_MASK_LEFT          = (PALETTE_TEXT << 4) | (PALETTE_TEXT)
ATTRIBUTE_MASK_RIGHT         = (PALETTE_TEXT << 6) | (PALETTE_TEXT << 2)

.proc InitAttributeCaches
; DESCRIPTION: Initialize the nametable attribute byte caches for both the
;              player's and CPU's boards.
;------------------------------------------------------------------------------

    LDX #0

Loop:
    LDA #ATTRIBUTE_MASK_LEFT
    STA playerBoardAttributeCache,X
    STA cpuBoardAttributeCache,X
    INX

    LDA #0
    STA playerBoardAttributeCache,X
    STA cpuBoardAttributeCache,X
    INX
    STA playerBoardAttributeCache,X
    STA cpuBoardAttributeCache,X
    INX
    STA playerBoardAttributeCache,X
    STA cpuBoardAttributeCache,X
    INX
    STA playerBoardAttributeCache,X
    STA cpuBoardAttributeCache,X
    INX
    
    LDA #ATTRIBUTE_MASK_RIGHT
    STA playerBoardAttributeCache,X
    STA cpuBoardAttributeCache,X
    INX

    CPX #ATTRIBUTE_CACHE_NUM_BYTES
    BCC Loop

End:
    RTS
.endproc

.proc UpdateAttributeCacheForOneSquareXY
; DESCRIPTION: Update the palette for a single board square in the nametable
;              attribute byte cache.
; PARAMETERS:
;  * C - set if player's board; clear if CPU's board
;  * X - X position of board square
;  * Y - Y position of board square
;  * A - Palette ID to set
; RETURNS:
;  * X - Lo byte of nametable attribute address
;  * Y - Hi byte of nametable attribute address
;  * A - Updated attribute byte value
; ALTERS: A, X, Y
;------------------------------------------------------------------------------
cachePtr       = $00 ; 2 bytes
cacheIx        = $02
boardY         = $03
paletteId      = $04
nametablePtrLo = $05
mask           = $06

    ;PHA
    STA paletteId
    STY boardY

    ; Determine which board cache to update
    BCS :+
    LDA #<cpuBoardAttributeCache
    STA cachePtr
    LDA #>cpuBoardAttributeCache
    STA cachePtr + 1
    BCC CalculateNametablePtr

:
    LDA #<playerBoardAttributeCache
    STA cachePtr
    LDA #>playerBoardAttributeCache
    STA cachePtr + 1

CalculateNametablePtr:
    CLC
    LDA NametableOffsetLoX,X
    ADC NametableOffsetLoY,Y
    ADC #<ATTRIBUTE_PTR_OFFSET
    STA nametablePtrLo

CalculateIndex:
    ; Figure out the index of the byte in the cache
    ; ix = 6*(Y/2) + (X+1)/2
    LDA boardY ; save this off since we need to divide it by 2
    PHA

    CLC
    TXA
    ADC #1
    LSR
    LSR boardY
    CLC
    ADC boardY
    ADC boardY
    ADC boardY
    ADC boardY
    ADC boardY
    ADC boardY
    STA cacheIx

    PLA         ; restore boardY
    STA boardY

ShiftMaskAndPaletteBits:
    ; Shift the mask and palette bits to the position for the target quadrant.
    ;   X % 2 = 0 --> right
    ;   X % 2 = 1 --> left
    ;   Y % 2 = 0 --> upper
    ;   Y % 2 = 1 --> lower
    LDA #%00000011 ; starting mask for upper-left (d1d0)
    STA mask

    LDA boardY
    AND #1
    BNE @lowerQuadrants

@upperQuadrants:
    TXA
    AND #1
    BNE SetAttributeByte ; branch if upper-left quadrant (d1d0)

    ; upper-right quadrant
    ASL mask
    ASL mask
    ASL paletteId
    ASL paletteId
    JMP SetAttributeByte

@lowerQuadrants:
    ; Shift four bytes to the left for lower quadrants
    ASL mask
    ASL mask
    ASL mask
    ASL mask
    ASL paletteId
    ASL paletteId
    ASL paletteId
    ASL paletteId

    TXA
    AND #1
    BNE SetAttributeByte ; branch if lower-left quadrant (d5d4)

    ; lower-right quadrant
    ASL mask
    ASL mask
    ASL paletteId
    ASL paletteId

SetAttributeByte:
    LDY cacheIx
    LDA mask
    EOR #%11111111      ; Flip the mask bits
    AND (cachePtr),Y
    ORA paletteId
    STA (cachePtr),Y

End:
    LDX nametablePtrLo
    LDY #>ATTRIBUTE_PTR_OFFSET
    RTS

;ATTRIBUTE_PTR_OFFSET = NAMETABLE_BL + NAMETABLE_ATTRIBUTE_OFFSET + 2*NAMETABLE_ATTRIBUTE_BYTES_PER_LINE ; = $2BD0
ATTRIBUTE_PTR_OFFSET = NAMETABLE_ATTRIBUTE_BL + 2*NAMETABLE_ATTRIBUTE_BYTES_PER_LINE ; = $2BD0
N_DY = NAMETABLE_ATTRIBUTE_BYTES_PER_LINE
NametableOffsetLoY:
  .byte $00,$00,N_DY,N_DY,2*N_DY,2*N_DY,3*N_DY,3*N_DY,4*N_DY,4*N_DY
  ;.byte $00,N_DY,N_DY,2*N_DY,2*N_DY,3*N_DY,3*N_DY,4*N_DY,4*N_DY,5*N_DY
NametableOffsetLoX:
  .byte $00,$01,$01,$02,$02,$03,$03,$04,$04,$05  ; could also do (X + 1) / 2

; C_DY = ATTRIBUTE_CACHE_BYTES_PER_ROW
; CacheOffsetY:
;   .byte $00,C_DY,C_DY,2*C_DY,2*C_DY,3*C_DY,3*C_DY,4*C_DY,4*C_DY,5*C_DY
.endproc

.proc hey ; IRQ handler
    INC $700
    JMP hey
.endproc

;##############################################
; GAME DATA
;##############################################

ShipLengths:
  ; Patrol boat, destroyer, submarine, battleship, carrier
  .byte $02,$03,$03,$04,$05

; Ship name strings
ShipLongNameHi:  .byte >StringPatrolBoat, >StringDestroyer, >StringSubmarine,  >StringBattleship, >StringCarrier
ShipLongNameLo:  .byte <StringPatrolBoat, <StringDestroyer, <StringSubmarine,  <StringBattleship, <StringCarrier
StringPatrolBoat: .asciiz "PATROL BOAT"
StringDestroyer:  .asciiz "DESTROYER"
StringSubmarine:  .asciiz "SUBMARINE"
StringBattleship: .asciiz "BATTLESHIP"
StringCarrier:    .asciiz "CARRIER"

; Other strings
StringEmpty:          .asciiz ""
StringPlaceYour:      .asciiz "PLACE YOUR"
StringAllShipsPlaced: .asciiz "ALL SHIPS PLACED"
StringStartPlay:      .asciiz "START: PLAY"
StringSelectReset:    .asciiz "SELECT: RESET"


ShipTilesHorizontalHi:
  .byte >PatrolBoatTilesHorizontal
  .byte >DestroyerTilesHorizontal
  .byte >SubmarineTilesHorizontal
  .byte >BattleshipTilesHorizontal
  .byte >CarrierTilesHorizontal
ShipTilesHorizontalLo:
  .byte <PatrolBoatTilesHorizontal
  .byte <DestroyerTilesHorizontal
  .byte <SubmarineTilesHorizontal
  .byte <BattleshipTilesHorizontal
  .byte <CarrierTilesHorizontal

ShipTilesVerticalHi:
  .byte >PatrolBoatTilesVertical
  .byte >DestroyerTilesVertical
  .byte >SubmarineTilesVertical
  .byte >BattleshipTilesVertical
  .byte >CarrierTilesVertical
ShipTilesVerticalLo:
  .byte <PatrolBoatTilesVertical
  .byte <DestroyerTilesVertical
  .byte <SubmarineTilesVertical
  .byte <BattleshipTilesVertical
  .byte <CarrierTilesVertical

PatrolBoatTilesHorizontal:
  ; Top
  .byte SHIP_BOW_HORIZ_TILE, SHIP_BOW_HORIZ_TILE + $1    
  .byte SHIP_STERN_HORIZ_TILE, SHIP_STERN_HORIZ_TILE + $1
  ; Bottom
  .byte SHIP_BOW_HORIZ_TILE + $10, SHIP_BOW_HORIZ_TILE + $11
  .byte SHIP_STERN_HORIZ_TILE + $10, SHIP_STERN_HORIZ_TILE + $11

PatrolBoatTilesVertical:
  ; Left
  .byte SHIP_BOW_VERT_TILE, SHIP_BOW_VERT_TILE + $10
  .byte SHIP_STERN_VERT_TILE, SHIP_STERN_VERT_TILE + $10
  ; Right
  .byte SHIP_BOW_VERT_TILE + $1, SHIP_BOW_VERT_TILE + $11
  .byte SHIP_STERN_VERT_TILE + $1, SHIP_STERN_VERT_TILE + $11

DestroyerTilesHorizontal:
  ; Top
  .byte SHIP_BOW_HORIZ_TILE, SHIP_BOW_HORIZ_TILE + $1
  .byte SHIP_MID_HORIZ_TILE, SHIP_MID_HORIZ_TILE + $1
  .byte SHIP_STERN_HORIZ_TILE, SHIP_STERN_HORIZ_TILE + $1
  ; Bottom
  .byte SHIP_BOW_HORIZ_TILE + $10, SHIP_BOW_HORIZ_TILE + $11
  .byte SHIP_MID_HORIZ_TILE + $10, SHIP_MID_HORIZ_TILE + $11
  .byte SHIP_STERN_HORIZ_TILE + $10, SHIP_STERN_HORIZ_TILE + $11

DestroyerTilesVertical:
  ; Left
  .byte SHIP_BOW_VERT_TILE, SHIP_BOW_VERT_TILE + $10
  .byte SHIP_MID_VERT_TILE, SHIP_MID_VERT_TILE + $10
  .byte SHIP_STERN_VERT_TILE, SHIP_STERN_VERT_TILE + $10
  ; Right
  .byte SHIP_BOW_VERT_TILE + $1, SHIP_BOW_VERT_TILE + $11
  .byte SHIP_MID_VERT_TILE + $1, SHIP_MID_VERT_TILE + $11
  .byte SHIP_STERN_VERT_TILE + $1, SHIP_STERN_VERT_TILE + $11

SubmarineTilesHorizontal:
  ; Top
  .byte SHIP_BOW_HORIZ_TILE, SHIP_BOW_HORIZ_TILE + $1
  .byte SHIP_MID_HORIZ_TILE, SHIP_MID_HORIZ_TILE + $1
  .byte SHIP_STERN_HORIZ_TILE, SHIP_STERN_HORIZ_TILE + $1
  ; Bottom
  .byte SHIP_BOW_HORIZ_TILE + $10, SHIP_BOW_HORIZ_TILE + $11
  .byte SHIP_MID_HORIZ_TILE + $10, SHIP_MID_HORIZ_TILE + $11
  .byte SHIP_STERN_HORIZ_TILE + $10, SHIP_STERN_HORIZ_TILE + $11

SubmarineTilesVertical:
  ; Left
  .byte SHIP_BOW_VERT_TILE, SHIP_BOW_VERT_TILE + $10
  .byte SHIP_MID_VERT_TILE, SHIP_MID_VERT_TILE + $10
  .byte SHIP_STERN_VERT_TILE, SHIP_STERN_VERT_TILE + $10
  ; Right
  .byte SHIP_BOW_VERT_TILE + $1, SHIP_BOW_VERT_TILE + $11
  .byte SHIP_MID_VERT_TILE + $1, SHIP_MID_VERT_TILE + $11
  .byte SHIP_STERN_VERT_TILE + $1, SHIP_STERN_VERT_TILE + $11

BattleshipTilesHorizontal:
  ; Top
  .byte SHIP_BOW_HORIZ_TILE, SHIP_BOW_HORIZ_TILE + $1
  .byte SHIP_MID_HORIZ_TILE, SHIP_MID_HORIZ_TILE + $1
  .byte SHIP_MID_HORIZ_TILE, SHIP_MID_HORIZ_TILE + $1
  .byte SHIP_STERN_HORIZ_TILE, SHIP_STERN_HORIZ_TILE + $1
  ; Bottom
  .byte SHIP_BOW_HORIZ_TILE + $10, SHIP_BOW_HORIZ_TILE + $11
  .byte SHIP_MID_HORIZ_TILE + $10, SHIP_MID_HORIZ_TILE + $11
  .byte SHIP_MID_HORIZ_TILE + $10, SHIP_MID_HORIZ_TILE + $11
  .byte SHIP_STERN_HORIZ_TILE + $10, SHIP_STERN_HORIZ_TILE + $11

BattleshipTilesVertical:
  ; Left
  .byte SHIP_BOW_VERT_TILE, SHIP_BOW_VERT_TILE + $10
  .byte SHIP_MID_VERT_TILE, SHIP_MID_VERT_TILE + $10
  .byte SHIP_MID_VERT_TILE, SHIP_MID_VERT_TILE + $10
  .byte SHIP_STERN_VERT_TILE, SHIP_STERN_VERT_TILE + $10
  ; Right
  .byte SHIP_BOW_VERT_TILE + $1, SHIP_BOW_VERT_TILE + $11
  .byte SHIP_MID_VERT_TILE + $1, SHIP_MID_VERT_TILE + $11
  .byte SHIP_MID_VERT_TILE + $1, SHIP_MID_VERT_TILE + $11
  .byte SHIP_STERN_VERT_TILE + $1, SHIP_STERN_VERT_TILE + $11

CarrierTilesHorizontal:
  ; Top
  .byte SHIP_BOW_HORIZ_TILE, SHIP_BOW_HORIZ_TILE + $1
  .byte SHIP_MID_HORIZ_TILE, SHIP_MID_HORIZ_TILE + $1
  .byte SHIP_MID_HORIZ_TILE, SHIP_MID_HORIZ_TILE + $1
  .byte SHIP_MID_HORIZ_TILE, SHIP_MID_HORIZ_TILE + $1
  .byte SHIP_STERN_HORIZ_TILE, SHIP_STERN_HORIZ_TILE + $1
  ; Bottom
  .byte SHIP_BOW_HORIZ_TILE + $10, SHIP_BOW_HORIZ_TILE + $11
  .byte SHIP_MID_HORIZ_TILE + $10, SHIP_MID_HORIZ_TILE + $11
  .byte SHIP_MID_HORIZ_TILE + $10, SHIP_MID_HORIZ_TILE + $11
  .byte SHIP_MID_HORIZ_TILE + $10, SHIP_MID_HORIZ_TILE + $11
  .byte SHIP_STERN_HORIZ_TILE + $10, SHIP_STERN_HORIZ_TILE + $11

CarrierTilesVertical:
  ; Left
  .byte SHIP_BOW_VERT_TILE, SHIP_BOW_VERT_TILE + $10
  .byte SHIP_MID_VERT_TILE, SHIP_MID_VERT_TILE + $10
  .byte SHIP_MID_VERT_TILE, SHIP_MID_VERT_TILE + $10
  .byte SHIP_MID_VERT_TILE, SHIP_MID_VERT_TILE + $10
  .byte SHIP_STERN_VERT_TILE, SHIP_STERN_VERT_TILE + $10
  ; Right
  .byte SHIP_BOW_VERT_TILE + $1, SHIP_BOW_VERT_TILE + $11
  .byte SHIP_MID_VERT_TILE + $1, SHIP_MID_VERT_TILE + $11
  .byte SHIP_MID_VERT_TILE + $1, SHIP_MID_VERT_TILE + $11
  .byte SHIP_MID_VERT_TILE + $1, SHIP_MID_VERT_TILE + $11
  .byte SHIP_STERN_VERT_TILE + $1, SHIP_STERN_VERT_TILE + $11

;##############################################
; GRAPHICS DATA
;##############################################

TitleMap:
  .incbin "assets/title/title.map"
TitlePalette:
  .incbin "assets/title/title.pal" ; background
  .incbin "assets/title/title.pal" ; sprites

PlaceShipsMap:
  .incbin "assets/place_ships/place_ships.map"
PlaceShipsPalette:
  .incbin "assets/place_ships/place_ships.pal"


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
    .word hey
    ; 
.segment "CHARS"
    .incbin "assets/tiles.chr"