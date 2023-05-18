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

    ; disable interrpt when we are doing mode switch so that the processor will not respond 
    ; to the interrupt. After we switch to long mode, we will re-enable and process the interrupt
    cli
    ; load the GDT and IDT structure.
    ; GDT and IDT structure are stored in memory and we need to tell the processor where they are located
    ; by loading the GDTR and IDTR registers.
    ; There is a register called global descriptor table register which points to the location of the GDT in memory
    ; and we load the register with the address of the GDT structure and the size of the GDT structure.
    ; NOTE that the default operand size of lgdt instruction is 16 bits,in 16 bits mode,
    ; if the operand size is 16 bits, the address of gdt pointer is actually 24 bits.
    ; here we define the address to be 32bitt and assign the address of gdt to the lower24 bits.
    lgdt [Gdt32Ptr]

    ; The next thing we are goind to do is load interrupt descriptor table.
    ; Just like global descriptor table register, there also interrupt descriptor table register
    ; and we need to load the register with the address and size of idt structure.
    ; since we don't want to deal with interrupts until we jump to long mode, we load the register with valid 
    ; address and size of 0.
    ; NOTE that there is one type of intterupt called non-maskable interrupt which is not disabled by the 
    ; cli instruction. So when non-maskable interrupt occurs, the processor will find the idt in memory
    ; and still respond to it. The CPU exception will be generated because the address and size of idt are
    ; invalid. Eventually the system will reset.
    ; The reason is that non-maskable interrupts indicate that non revocerable hardware errors such as ram error.
    lidt [Idt32Ptr]

    ; After we load gdt and idt, then we enable protected mode by setting the protected mode enable bit 
    ; in cr0 register.
    ; The cr0 register is a control register which controls the processor's operating mode.
    mov eax, cr0
    or eax, 1 ; set the protected mode enable bit
    mov cr0, eax

    ; The last thing we will do is load the cs segment register with a new code segment descriptor we just
    ; defined in the GDT structure.
    ; Loading code segment descriptor to cs register is different from another segment registers.
    ; We cannot use mov instruction to load cs register, instead we use jump instruction to do it.
    ; The code segment descriptor is the second entry which is 8 bytes away from the beginning of the GDT structure.
    ; The index of the selector is 8
    ; |--------------------------------|
    ; | 0 | 0 | 0 | 0 | 1 | 0  | 0 | 0 | (binary)
    ; |--------------------------------|
    ; | index             | TI | RPL   |
    ; |--------------------------------|
    ; index = 8
    ; TI = 0, means that we use GDT
    ; RPL = 0, means that the privilege level is 0
    ; Therefore when CPU performs privilege check, the RPL is 0 and equal to the DPL of code segment then the
    ; check will pass.
    ; Then we also need to specify the offset, we want to jump to the protected mode entry which is label we will
    ; define later.
    jmp 8:PMEntry

ReadError:
NotSupport:
End:
	hlt
	jmp End

; Before we define the label, we use directive bits to indicate that the following code is running at 32-bit mode.
[BITS 32]
PMEntry:
    ; initialize other segment registers such as ds, and ss registers.
    mov ax, 0x10 ; the data segment descriptor is the third entry in the GDT structure
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x7c00 ; set stack pointer esp to 0x7c00

    ; Enable paging
    ; this block of code basically find a free memory area and initialize the paging structure
    ; which is used to translate the virtual address to physical address.
    ; The addresses (0x80000 - 0x90000) may be used for BIOS data. We can use memory area from 0x70000 to 0x80000 instead.
    cld
    mov edi, 0x80000
    xor eax, eax
    mov ecx, 0x10000/4
    rep stosd
    
    mov dword[0x80000], 0x81007
    mov dword[0x81000], 10000111b

    ; Then we load the GDT that we will use in 64-bit mode. The GDT is defined in the next section.
    lgdt [Gdt64Ptr]
    ; enable the 64-bit mode by setting the necessary bits.
    ; The first register is cr4. The bit 5 in cr4 is the physical address extension bit or PAE bit.
    ; we have to set it to 1 before activating 64-bit mode.
    mov eax, cr4
    or eax, (1 << 5)
    mov cr4, eax

    ; The next register is related to cr3 register, we copy the address of the page structure we just set up,
    ; 80000 in this case to cr3 register
    mov eax, 0x80000
    mov cr3, eax
    ; The address loaded to cr3 are physical address. So this is one of few cases we need to use physical address
    ; in our code

    ; enable long mode
    ; extended feature enable register or efer register is the last register we need to set.
    ; The bit 8 in efer register is the long mode enable bit. We set it to 1 to enable long mode.
    ; to read and write a model specific register, we move the index of the register to ecx.
    mov ecx, 0xc0000080
    rdmsr ; read the value of the register to eax and edx
    or eax, (1 << 8) ; The return value is in eax register. So we set the bit 8 in eax using or instruction
    ; Then we write the value back to the register using wmsr instruction
    wrmsr

    ; enable paging by setting the bit 31 in register cr0
    mov eax, cr0
    or eax, (1 << 31)
    mov cr0, eax

    jmp 8:LMEntry 
    ; Here we specify the segment selector 8, since each entry is 8 bytes and the code segment selector is 
    ; the second entry and then the offset long mode entry

PEnd:
    hlt
    jmp PEnd    

[BITS 64]
LMEntry:
    mov rsp, 0x7c00

    mov byte[0xb8000], 'L'
    mov byte[0xb8001], 0xa

LEnd:
    hlt
    jmp LEnd


DriveId: db 0
ReadPacket: times 16 db 0

; define a variable to store the GDT structure
Gdt32:
    ; the first entry in the GDT is reserved for null descriptor or 0
    dq 0 ; each entry is 8 bytes long, we use directive dq to define a quad word (8 bytes)

; This is the code segment descriptor we will use in protected mode.
Code32:
    ; the second entry is the code segment descriptor
    ; the first 2 bytes are the lower 16 bits of segment size
    dw 0xffff ; set to max size
    ; the next three bytes are the lower 24 bits of the base address which we set to 0
    ; meaning that the code segment starts at address 0
    dw 0
    db 0
    
    ; The fourth byte specified the segment attributes
    ; |--------------------|
    ; | P | DPL | S | TYPE |
    ; |--------------------|
    ; | 1 | 00  | 1 | 1010 | -> 0x9A in hex
    ; |--------------------|
    ; the S means the segment descriptor is system descriptor or not
    ; here we set it to 1, means that it is a code or data segment descriptor.
    ; the TYPE field specifies the type of the segment. it is assigned to 1010, means that it is a 
    ; non conforming code segment
    ; The different between conforming and a non-conforming code segment is that the cpl is not changed
    ; when the control is transferred to higher privilege conforming code segment from the lower one.
    ; the DPL field specifies the privilege level of the segment. Here we set it to 00, means that the
    ; code segment can be accessed by any privilege level.
    ; Because we want to be running at ring0 when we jump to protected mode. So we set the DPL to 00
    ; and when we load the descriptor to cs register, the cpl will be set to 0 indicating that we are at ring0.
    ; P is the present bit. We need to set it to 1 when we want to load the descriptor otherwise the cpu exception
    ; will be generated.
    db 0x9a

    ; the next bytes is a combination of segment size and attributes
    ; |-----------------------|
    ; | G | D | 0 | A | LIMIT |
    ; |-----------------------|
    ; | 1 | 1 | 0 | 0 | 1111  | -> 0xcf in hex
    ; |-----------------------|
    ; the lower half is the upper 4 bits of segment size. We set it to to max size, the available bit can be used by the system software.
    ; The D bit is the default operand size. We set it to 1, means that the default operand is 32 bits.
    ; otherwise it is 16 bits. We set it to 1 in the protected mode.
    ; G is the granularity bit. We set it to 1, means that the size field is scaled by 4KB units.
    ; Which gives us the max size of 4GB of segment size.
    db 0xcf
    ; the last is the upper 8 bits of the base address. We set it to 0
    db 0

; Since we will access data in memory, we need to define a data segment descriptor.
; The structure of code segment and data segment descriptor is very similar.
Data32:
    dw 0xffff ; set to max size
    dw 0
    db 0

    ; The only change we need to make in this case is the type field. We set it to 0010 in binary, means that
    ; it is a readable and writable data segment.
    ; |-----------------------|
    ; | G | D | 0 | A | LIMIT |
    ; |-----------------------|
    ; | 1 | 1 | 0 | 0 | 0010  | -> 0x92 in hex
    ; |-----------------------|
    db 0x92
    db 0xcf
    ; set the writeable bit to 1 to make the segment writeable, currently it is set to 0
    db 0 

Gdt32Len: equ $-Gdt32
Gdt32Ptr: dw Gdt32Len-1
          dd Gdt32 ; we define the address to be 32 bits.

Idt32Ptr: dw 0
          dd 0

Gdt64:
    dq 0

    ; |------------|------------|------------|-----------------|------------|------------|------------|
    ; | D (bit 54) | L (bit 53) | P (bit 47) | DPL (bit 46-45) | 1 (bit 44) | 1 (bit 43) | C (bit 42) |
    ; |------------|------------|------------|-----------------|------------|------------|------------|
    ; | 0          | 1          | 1          | 0 0             | 1          | 1          | 0          | -> 0x0020980000000000 in hex
    ; |------------|------------|------------|-----------------|------------|------------|------------|
     
    ; The Conforming bit is set to 0, since we only use con-conforming code segment in our system.
    ; The next 1s means that the descriptor is code segment descriptor.
    ; The DPL indicates privilege level of the code segment, we set DPL to 0, when we load the descriptor
    ; to cs register and jump to 64-bit mode the CPL will be 0 indicating that we are at ring0.
    ; Present bit (P) is set to 1, otherwise the CPU exception is generated of we trey to load the descriptor.
    ; The Long bit (L) is set to 1 indicating that the code segment runs in 64-bit mode. If it is set to 0, then
    ; it will runs in compatibility mode.
    ; The D bit can only be set to 0 if the long bit is set. It indicates the default operand size. We set it to 0
    dq 0x0020980000000000 
    ; 64-bit code segment descriptor, we dont need to load the data segment because we runing in ring0

Gdt64Len: equ $-Gdt64

Gdt64Ptr: dw Gdt64Len-1
          dd Gdt64