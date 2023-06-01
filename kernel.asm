[BITS 64]
[ORG 0x200000]

start:
    mov rdi, Idt
    mov rax, Handler0
    call SetHandler

    mov rax, Timer
    mov rdi, Idt+32*16
    call SetHandler

    mov rdi, Idt+32*16+7*16
    mov rax, SIRQ
    call SetHandler

    ; load GDT
    ; Note that the address of GDT in GDT pointer is 8 bytes
    ; in 64-bit mode we load the pointer with 2-byte limit and 8-byte base address.
    lgdt [Gdt64Ptr]
    lidt [IdtPtr]

; Load TSS Descriptor
SetTss:
    mov rax, Tss
    mov [TssDesc+2], ax
    shr rax, 16
    mov [TssDesc+4], al
    shr rax, 8
    mov [TssDesc+7], al
    shr rax, 8
    mov [TssDesc+8], eax

    mov ax, 0x20
    ltr ax

    push 8
    push KernelEntry

    db 0x48

    ; load the code segment descriptor into CS register
    ; instead of using jump instruction, we load the descriptor using another instruction
    ; return instruction.
    retf 
    ; indicating that is a far return instruction. 
    ; far return instruction loads the code segment descriptor into CS register
    ; and the instruction pointer from the stack.
    ; normal return will not load the descriptor into CS register.

KernelEntry:
    mov byte[0xb8000],'K'
    mov byte[0xb8001],0xa

    ; initialize the PIT and PIC which require several steps. 
    ; First we look at the PIT. 
    ; There are three channels in PIT, through channel 0 to channel 2. Channel 1 and 2 may
    ; not exist and we don't use them.
    ; The PIT has four registes, one mode command register and three data registers for
    ; channel 0, 1 and 2.
    ; We set command  and data registers to make the PIT works as we expect, that is
    ; to fire an interrupt periodically.

    ; The mode command register has four parts in it.
    ; |-------------------------------|
    ; | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
    ; |-------------------------------|
    ; the Bit 0 indicates that the value PIT uses is in binary or BCD.
    ; we set it to 0 to indicate that the value is in binary.
    ; bit 1 through 3 is the operating mode of the PIT.
    ; we set it to 010 which is mode 2 rate generator used for recurring interupt.
    ; bit 4 t0 5 is the access mode of the PIT. The data register are 8 bits.
    ; If we want to write a 16-bit value to the PIT, we need to write two bytes in a row.
    ; Access mode specifies in which order the data will be written to the data register
    ; such as low byte only, high byte only, etc
    ; we set the access mode to 11 which mean we want to write the low byte first
    ; and then the high byte.
    ; The last part is for selecting the channel with 0 being channel 0, 1 being channel 1
    ; and so on.

InitPIT:
    mov al,(1<<2)|(3<<4)

    ; The address of mode command register is 43. we use out instruction to write
    ; the value in al to the register.
    out 0x43,al

    ; Write the settings to data register to make the PIT fire the interrupt as we
    ; expect.
    ; The value we want to write to the PIT is an interval value which specifies
    ; when the interrupt is fired.
    ; The PIT works by decrement the loaded counter value at a rate of 1.193182 MHZ
    ; Which means it will decrement the value roughly 1.193182 million times per second.
    ; In this system, we want the interrupt fired at 100 HZ which means 100 times per second.
    mov ax,11931 ; 1193182/100
    out 0x40,al ; the address of data register of channel 0 is 40.
    mov al,ah ; now al holds the high byte of the value
    out 0x40,al


InitPIC:

    ; The PIC also has command register and data register.
    ; Each chip has its own register set.
    ; The address of the master chip is 20 and the address of the slave chip is 0xa0.
    ; The bit 0 and bit 4 is 1
    ; |-------------------------------|
    ; | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
    ; |-------------------------------|
    ; | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | = 0x11
    ; |-------------------------------|
    ; The bit 4 means that this is the initialization command followed by another three initialization command words
    ; we are about to write
    ; The bit 0 indicate that we use the last initialization command word

    mov al, 0x11
    out 0x20, al
    out 0xa0, al

    ; Write three command words.
    ; The first one specifies the starting vector number of the first IRQ.
    ; Remember the processor has defined the first 32 vectors for its own use.
    ; So we can define the vector number 32 to 255.
    mov al, 32 ; the starting vector number of the first IRQ is 32.
    ; instead of writing the data to command register, we write it to the data register
    out 0x21, al ; address of the master chip's data register is 21
    ; Each chip has 8 IRQs and the first vector number of the master is 32, the second vector is 33 and so on.
    mov al, 40 ; the starting vector number of the slave IRQ is 40.
    out 0xa1, al ; address of the slave chip's data register is a1


    ; Set the IRQ used for connecting the two PIC chips.
    ; On a regular system, the slave is attached to the master via IRQ2. If the bit 2 of the word is set, 
    ; it means that IRQ2 is used for connecting the two chips.
    ; |-------------------------------|
    ; | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
    ; |-------------------------------|
    ; | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | = 0x04
    ; |-------------------------------|
    mov al, 4   
    out 0x21, al
    mov al, 2
    out 0xa1, al

    ; |-------------------------------|
    ; | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
    ; |-------------------------------|
    ; | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | = 0x01
    ; |-------------------------------|
    ; Used for selecting mode. The bit 0 should be 1 meaning that x86 system is used.
    ; The bit 1 is automatic end of interrupt. We don't use it.
    ; The bit 2 to 3 are set to 0 which means buffered mode is not used.
    ; The bit 4 specify the fully nested mode. We set it to 0.
    mov al, 1
    out 0x21, al
    out 0xa1, al

    ; Since we have a total of 15 IRQs, we need to mask the IRQs we don't use.
    mov al, 11111110b
    out 0x21, al
    ; All the IRQ in the slave are not use so we mask them all.
    mov al, 11111111b
    out 0xa1, al

    sti

    ; Set the IDT entry for the timer.
    ; The vector number of the timer is 32 in the PIC, so the address of the entry is 32*16 = 0x200

    push 0x18|3
    push 0x7c00
    push 0x202
    push 0x10|3
    push UserEntry
    iretq

End:
    hlt
    jmp End

SetHandler:
    ; copy the lower 16 bits of the offset to the location that rdi points to that
    ; is two bytes of IDT entry.
    mov [rdi], ax 
    shr rax, 16 ; shift right the offset in rax by 16 bits.
    mov [rdi+6], ax
    shr rax, 16
    mov [rdi+8], eax ; copy the value in the eax to the third part of the offset
    ret

UserEntry:

    inc byte[0xb8010]
    mov byte[0xb8011],0xF

UEnd:
    jmp UserEntry



Handler0:

    ; save registers value on the stack
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov byte[0xb8000],'D'
    mov byte[0xb8001],0xc

    jmp End

    ; restore registers value from the stack
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    iretq 
    ; interrupt return instruction which will pop more dadta than the regular return 
    ; and can return to the different privilege level.


Timer:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    inc byte[0xb8020]
    mov byte[0xb8021],0xe

    mov al, 0x20
    out 0x20, al    

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    iretq ; interrupt return instruction which will pop more data than the regular return

; spurious interrupt
SIRQ:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov al, 11
    out 0x20, al
    in al, 0x20

    test al, (1 << 7)
    jz .end ; local label start with the . (dot) character

    mov al, 0x20
    out 0x20, al

.end:

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    iretq

Gdt64:
    dq 0
    dq 0x0020980000000000
    dq 0x0020f80000000000
    dq 0x0000f20000000000

TssDesc:
    dw TssLen-1
    dw 0
    db 0
    db 0x89
    db 0
    db 0
    dq 0

Gdt64Len: equ $-Gdt64

Gdt64Ptr:
    dw Gdt64Len-1
    dq Gdt64   

Idt:
    %rep 256
        dw 0
        dw 0x8
        db 0
        ; |-----------------|
        ; | P | DPL |  TYPE |
        ; |-----------------|
        ; | 1 | 00  | 01110 | -> 0x8e
        ; |-----------------|
        db 0x8e 
        dw 0
        dd 0
        dd 0
    %endrep

IdtLen: equ $-Idt
IdtPtr: dw IdtLen-1
        dq Idt
Tss:
    dd 0
    dq 0x150000
    times 88 db 0
    dd TssLen

TssLen: equ $-Tss
