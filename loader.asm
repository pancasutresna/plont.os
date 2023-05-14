[BITS 16]
[ORG 0x7e00]

start:
	; save DriveId for later use
	mov [DriveId], dl
	
	; check to see wether it supports 0x80000001 input value
	mov eax, 0x80000000
	cpuid

	; if the return value in eax is less than 0x80000001, means it does not support input value
	cmp eax, 0x80000001
	jb NotSupport

	; this will return the processor features
	; the information about long mode support is saved in edx
	mov eax, 0x80000001 
	cpuid ; returs the processor identification and feature information.

	; we test bit 29 in edx, if it's set means that long mode is supported.
	; otherwise long mode is not available and we jump to the label not support.
	test edx, (1 << 29)
	; is zero flag is set, means that the bit we checked is not set and we jump to not support
	jz NotSupport

	; check 1g page support at bit 26
	test edx, (1 << 26)
	; if zero flag is set, it means that this feature is not supported and we jump to not support.
	jz NotSupport

LoadKernel:
    mov si, ReadPacket
    mov word[si], 0x10
    mov word[si+2], 100
    mov word[si+4], 0
    mov word[si+6], 0x1000 ; offset segment 0x1000:0 = 0x1000 * 16 + 0 = 0x10000
    ; the boot  file resides in the first sector,
    ; the loader file occupies the next five sectors. so we write our kernel from the 7th sector
    ; offset 0x1000:6 = 0x1000 * 16 + 6 = 0x10006\
    mov dword[si+8], 6 ; sector value is 0-based value, so 6 means the 7th sector
    
    
    mov dword[si+0xc], 0 
    mov dl, [DriveId]
    mov ah, 0x42
    int 0x13
    ; check the carry flag. If carry flag is set after calling the read service, 
    ; we know that loading kernel failed and we jump to read error and stop here.
    jc ReadError
    
GetMemInfoStart:
    mov eax, 0xe820 ; get memory map, eax = 0xe820, ebx = 0, ecx = 24, edx = 0x534d4150
    mov edx, 0x534d4150 ; asci code for 'SMAP' to edx, this is the signature for the memory map
    mov ecx, 20 ; the size of the memory map entry, 20 bytes
    mov edi, 0x9000 ; the memory address where we want to save the memory map, 0x9000
    ; save the memory address in which we saved the memory block returned in register edi
    
    ; ebx should be 0 before we call the function. 
    ; clear ebx using xor instruction
    xor ebx, ebx
    int 0x15 ; call the function

    ; if the carry flag is set, means that the service e820 is not supported.
    jc NotSupport

    ; if it returns the memory info successfully, the carry flag will be cleared and we continue to 
    ; retrieve the memory info

GetMemInfo:
    ; Adjust edit to point to the next memory map entry
    add edi, 20 ; to receive the next memory block. each memory map entry is 20 bytes long
    mov eax, 0xe820 ; get memory map, eax = 0xe820, ebx = 0, ecx = 24, edx = 0x534d4150
    mov edx, 0x534d4150 ; asci code for 'SMAP' to edx, this is the signature for the memory map
    mov ecx, 20 ; the size of the memory map entry, 20 bytes
    ; ebx must be preserved for the nextr call of the function. So we don't change it.
    int 0x15 ; call the function
    jc GetMemDone ; if carry flag is set this time, means that we have reached the end of the memory map

    test ebx, ebx 
    ; if ebx is zero, means that we have reached the end of the memory map
    ; if ebx is not zero, means that we have not reached the end of the memory map
    jnz GetMemInfo

GetMemDone:


TestA20:
    mov ax, 0xffff
    mov es, ax
    mov word[ds:0x7c00], 0xa200 ; 0:0x7c00 = 0x16 + 0x7c00 = 0x7c00
    cmp word[es:0x7c10], 0xa200 ; 0xffff:0x7c10 = 0xffff0 x 16 + 0x7c10 = 0x107c00
    jne SetA20LineDone
    mov word[0x7c00], 0xb200
    cmp word[es:0x7c10], 0xb200
    je End

SetA20LineDone:
    xor ax, ax
    mov es, ax

SetVideoMode:
    ; the function code in ah register means we want to set video mode
    ; then we need to choose video mode, text mode in this case, by copy 3 to al register.
    mov ax, 3
    int 0x10 ; set video mode

    ; clear the screen
    ; the base address for text mode is b8000.
    ; The size of screen we can print on is 80 (characters) * 25 (lines)
    ; Every character takes 2 bytes, one for the character (ascii codes), one for the attribute
    ; The lower half are foreground color and the higher half are background color.
    ; The first position on the screen correspondends to the two bytes at b8000
    ; The second position on the screen correspondends to the two bytes at b8002, and so on.
    
    ; save the address of characters to register si and text mode address b8000 to di
    ; note that the value b8000 is too large to fit in a 16-bit register, so we save b800 to es register
    ; and zero the di register
    ; when we reference the memory address b8000, we use es:di which is the same as b800:0
    mov si, Message
    mov ax, 0xb800
    mov es, ax
    xor di, di
    ; we save the number of characters to cx register
    mov cx, MessageLen
    ; then we print characters one at a time

PrintMessage:
    ; We copy the data in memory porinted to by si which is the first character of message at this point.
    mov al, [si]
    ; then copy the data to the memory addressed by di which is b8000 at this point.
    mov [es:di], al

    ; specify attribute for the character
    mov byte[es:di+1], 0xa ; 0xa is light green on black background
    
    add di, 2
    add si, 1
    ; because the character takes 2 bytes, we need to add 2 to di and the character stored in message 
    ; takes 1 byte, we need to add 1 to si
    loop PrintMessage


ReadError:
NotSupport:
End:
	hlt
	jmp End

DriveId: db 0
Message: db "Text mode is set"
MessageLen: equ $-Message
ReadPacket: times 16 db 0