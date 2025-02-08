ca65 battleship.asm -o battleship.o --debug-info
ld65 battleship.o -o battleship.nes -C nes_cc65.cfg --dbgfile battleship.dbg
