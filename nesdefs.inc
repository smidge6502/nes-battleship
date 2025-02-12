; PPU Registers
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
OAMDATA   = $2004
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014

; Other addresses
JOYPAD1 = $4016
JOYPAD2 = $4017

; APU
APU_FRAME_COUNTER = $4017

; Universal constants
NAMETABLE_TILES_PER_LINE = 32
NAMETABLE_LINES          = 30

; These assume the tiles in CHAR are arranged in a 
; 16x16 grid with $00 at the top-left and $FF at the
; bottom-right.
CHAR_TILES_PER_ROW       = 16 
CHAR_ROWS                = 16