ca65 battleship.asm -o battleship.o --debug-info
ld65 battleship.o -o battleship.nes -C nes_cc65.cfg -m memory_map.txt --dbgfile battleship.dbg
