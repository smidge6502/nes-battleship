ca65 battleship.asm -o battleship.o --debug-info
ld65 battleship.o -o battleship.nes -t nes --dbgfile battleship.dbg
