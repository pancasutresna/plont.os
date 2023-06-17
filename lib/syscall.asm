section .text
global writeu

writeu:
    sub rsp, 16
    xor eax, eax

    mov [rsp], rdi
    mov [rsp+8], rsi

    mov rdi, 2 ; 2 arguments
    mov rsi, rsp ; pointer to arguments, 16 bytes long
    int 0x80

    add rsp, 16
    ret