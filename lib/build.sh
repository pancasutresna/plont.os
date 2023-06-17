nasm -f elf64 -o syscall.o syscall.asm
gcc -std=c99 -mcmodel=large -ffreestanding -fno-stack-protector -mno-red-zone -c print.c
ar rcs lib.a print.o syscall.o
cp lib.a ../lib.a
cp lib.a ../user1/lib.a
cp lib.a ../user2/lib.a
cp lib.a ../user3/lib.a