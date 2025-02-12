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

; Game states
GAMESTATE_TITLE = 0
GAMESTATE_PLACE_SHIPS = 1
GAMESTATE_BOARD = 2

NAMETABLE_TL = $2000 ; top-left
NAMETABLE_TR = $2400 ; top-right
NAMETABLE_BL = $2800 ; bottom-left
NAMETABLE_BR = $2C00 ; bottom-right

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
BOARD_NUM_SQUARES      = 100

CURSOR_BLINK_CHECK_MASK = %00010000 ; show cursor if this AND globalTimer = 0

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

placedShipsX:          .res NUM_SHIPS
placedShipsY:          .res NUM_SHIPS
allShipsPlaced:        .res 1

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

    ; Read the joypads and disable the APU frame counter
    ; IRQ again since reading the second joypad re-enables it
    JSR ReadJoypads
    LDA #$40
    STA APU_FRAME_COUNTER
    ;JSR UpdateButtonPressedSprites `

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
    JMP ProcessBoard
:

    JMP MainLoop
.endproc

.proc ProcessTitle
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
iShipSquare    = $00
dBoardArray    = $01

iQueue           = $02
currentSquare    = $03
arrayId          = $04
dTileWithinQueue = $05
dTileNextQueue   = $06
shipTilePtr      = $07 ; 2 bytes
shipNumTiles     = $09

X_MAX = $09
Y_MAX = $09
BOARD_WIDTH = $0A
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

    ; Clear the board
    LDX #BOARD_NUM_SQUARES - 1
:
    STA playerBoard,X
    DEX
    BPL :-

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

    JSR PlaceShipOnBoard
    BEQ @updateNextShip

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
    JSR WriteAllShipsPlacedText
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
    JSR GetBoardSquareFromArrayId ; A = char tile of upper-left tile of square
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
; This uses NQUEUE2 and NQUEUE3 to draw the ship.
    LDX newCursorX
    LDY newCursorY
    JSR GetSquareNametablePtrFromXY
    
    ; The NQUEUE2 address is the same for both orientations.
    STA nametableQueueAddressHi + 2
    STX nametableQueueAddressLo + 2
    STA nametableQueueAddressHi + 3  ; same hi byte for NQUEUE3

    LDA newOrientation
    BNE :+
    ; horizontal
    TXA
    CLC
    ADC #NAMETABLE_TILES_PER_LINE
    STA nametableQueueAddressLo + 3
    LDY #NAMETABLE_QUEUE_STATUS_HORIZONTAL
    JMP @setStatus
:
    ; vertical
    INX
    STX nametableQueueAddressLo + 3
    LDY #NAMETABLE_QUEUE_STATUS_VERTICAL

@setStatus:
    STY nametableQueueStatus + 2
    LDA ppuControl
    AND #%11111011
    ORA nametableQueueStatus + 2
    STA nametableQueueStatus + 2
    STA nametableQueueStatus + 3

@initTileQueueLoop:
    LDX newShip
    LDA ShipLengths,X
    ASL                ; double to get length in tiles
    STA shipNumTiles
    LDY #0 ; Y = ship tile index (and queue index for NQUEUE2)

    ; Choose the tile array to load into the queues based
    ; on the ship's orientation
    LDA newOrientation
    BNE :+
    ; horizontal
    LDA ShipTilesHorizontalLo,X
    STA shipTilePtr
    LDA ShipTilesHorizontalHi,X
    STA shipTilePtr + 1
    BNE @nQueue2Loop
:
    ; vertical
    LDA ShipTilesVerticalLo,X
    STA shipTilePtr
    LDA ShipTilesVerticalHi,X
    STA shipTilePtr + 1

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
; DESCRIPTION: Overwrites the "PLACE YOUR {SHIP}" text with instructions on
;              how the player can proceed.
; ALTERS: A, X, Y
;------------------------------------------------------------------------------
    ; Save off $00-$02
    LDA $00
    PHA
    LDA $01
    PHA
    LDA $02
    PHA

    ; Set up arguments
    LDA #<StringAllShipsPlaced
    STA $00
    LDA #>StringAllShipsPlaced
    STA $01
    LDA #22 ; long enough to overwrite "place your patrol boat"
    STA $02
    LDY #>NAMETABLE_BL
    LDX #$48
    JSR EnqueueStringWrite

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
ATTRIBUTE_START_PTR      = $2BC0
BOARD_NORMAL_PALETTE_ID  = $00
BOARD_OVERLAP_PALETTE_ID = $01
TEXT_PALETTE_ID          = $03
MAX_BYTES_PER_QUEUE      = 3

; Read/write
iShipSquare    = ProcessPlaceShips::iShipSquare
dBoardArray    = ProcessPlaceShips::dBoardArray
arrayId        = ProcessPlaceShips::arrayId
shipNumSquares = ProcessPlaceShips::shipNumTiles

iAttByte = $0D
attX     = $0E
attY     = $0F

ATTRIBUTE_BOARD_NORMAL_X0 = (BOARD_NORMAL_PALETTE_ID << 6) | (TEXT_PALETTE_ID << 4) | (BOARD_NORMAL_PALETTE_ID << 2) | TEXT_PALETTE_ID
ATTRIBUTE_BOARD_NORMAL_X_NOT_0 = (BOARD_NORMAL_PALETTE_ID << 6) | (BOARD_NORMAL_PALETTE_ID << 4) | (BOARD_NORMAL_PALETTE_ID << 2) | BOARD_NORMAL_PALETTE_ID

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
; RETURNS: Z flag set if ship placed; cleared if it could not be placed
;------------------------------------------------------------------------------
startArrayId   = $00
currentArrayId = $01
deltaArrayId   = $02 ; amount to add to get the next array ID
shipByte       = $03
    LDX cursorX
    LDY cursorY
    JSR GetBoardArrayIdFromXY
    STA startArrayId
    STA currentArrayId

    LDA shipOrientation
    BNE :+
    LDA #1 ; horizontal
    STA deltaArrayId
    BNE CheckIfEmpty
:
    LDA #10
    STA deltaArrayId

CheckIfEmpty:
    ; Check if there is already a ship at (X,Y)
    LDY shipBeingPlaced
    LDX ShipLengths,Y
@loop:
    LDY currentArrayId
    LDA playerBoard,Y
    AND #%10000000
    BEQ @iterate
    RTS  ; Z flag is cleared for return value

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
    LDA shipBeingPlaced
    ASL
    ASL
    ASL
    ORA shipOrientation
    ORA #%10000000
    STA shipByte

    LDA startArrayId
    STA currentArrayId

@placeBow:
    ; The ship part is already correctly set to 0.
    TAY
    LDA shipByte
    STA playerBoard,Y

    TYA
    CLC
    ADC deltaArrayId
    STA currentArrayId

    ; Place middle
    LDY shipBeingPlaced
    LDX ShipLengths,Y
    DEX
    DEX ; subtract 2 for middle length
    BEQ @placeStern

    LDA shipByte
    ORA #%00000010 ; middle section
@middeLoop:
    LDY currentArrayId
    STA playerBoard,Y
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
    STA playerBoard,Y

MarkShipAsPlaced:
    LDY shipBeingPlaced
    LDA cursorX
    STA placedShipsX,Y
    LDA cursorY
    STA placedShipsY,Y

    LDA #0 ; Set Z flag to indicate the ship was placed
    RTS

.endproc

.proc ProcessBoard
    ; Check if we need to initialize the board
    TYA
    BEQ InitEnd

    ; Board init
    ; Switch to BL nametable
    LDA ppuControl
    AND #%11111100 ; clear nametable bits
    ORA #%00000010 ; set nametable bits
    STA ppuControl

    ; Set palette
    LDA #<BoardPalette
    STA currentPalette
    LDA #>BoardPalette
    STA currentPalette+1
    JSR SetNmiFlagLoadPalette

    ; Init test tile
    LDA #$41
    STA nextTile
InitEnd:

CheckLeftRight:
    LDA pressedButtons1
    AND #BUTTON_RIGHT
    BEQ :+
    INC nextTile
    JMP CheckLeftRight_SetUpdateBoardFlag
:
    LDA pressedButtons1
    AND #BUTTON_LEFT
    BEQ CheckLeftRight_End
    DEC nextTile

CheckLeftRight_SetUpdateBoardFlag:
    LDA frameState
    ORA #FRAMESTATE_UPDATE_BOARD
    STA frameState

CheckLeftRight_End:

    JMP MainLoop
.endproc

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


;##############################################
; GAME LOGIC SUBROUTINES
;##############################################

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
    JSR GetBoardSquareFromArrayId
    RTS
.endproc

.proc GetBoardSquareFromArrayId
; DESCRIPTION: Get a char tile of a board from an array ID
; PARAMETERS:
;  * Y - array ID
; RETURNS:
;  * A - char tile of square at the array ID
; TODO: support both boards
;-------------------------------------------------------------------------------
    ; Check if there is a ship (bit 7)
    LDA playerBoard,Y
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

.proc hey
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
StringEmpty:      .asciiz ""
StringAllShipsPlaced: .asciiz "ALL SHIPS PLACED"


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

BoardMap:
  ;.incbin "assets/board/board.map"
  .incbin "assets/board_large/board.map"
BoardPalette:
  ;.incbin "assets/board/board.pal"
  .incbin "assets/board_large/board.pal"

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
    ; .incbin "hellomario.chr"
    .incbin "assets/tiles.chr"