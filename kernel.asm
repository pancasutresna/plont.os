[BITS 64]
[ORG 0x200000]

start:
    mov rdi, Idt
    mov rax, handler0
    
    mov [rdi], ax
    shr rax, 16
    mov [rdi+6], ax
    shr rax, 16
    mov [rdi+8], eax

    ; load GDT
    ; Note that the address of GDT in GDT pointer is 8 bytes
    ; in 64-bit mode we load the pointer with 2-byte limit and 8-byte base address.
    lgdt [Gdt64Ptr]
    lidt [IdtPtr]

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

    xor rbx, rbx
    div rbx


End:
    hlt
    jmp End

handler0:
    mov byte[0xb8000],'D'
    mov byte[0xb8001],0xc

    jmp End

    iretq

Gdt64:
    dq 0
    dq 0x0020980000000000

Gdt64Len: equ $-Gdt64

Gdt64Ptr:
    dw Gdt64Len-1
    dq Gdt64   

Idt:
    %rep 256
    dw 0
    dw 0x8
    db 0
    db 0x8e
    dw 0
    dd 0
    dd 0
    %endrep

IdtLen: equ $-Idt
IdtPtr: dw IdtLen-1
        dq Idt
