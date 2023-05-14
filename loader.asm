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
    

	mov ah, 0x13
	mov al, 1
	mov bx, 0xa
	xor dx, dx
	mov bp, Message
	mov cx, MessageLen
	int 0x10

ReadError:
NotSupport:
End:
	hlt
	jmp End

DriveId: db 0
Message: db "Kernel is loaded successfully!"
MessageLen: equ $-Message
ReadPacket: times 16 db 0