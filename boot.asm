[BITS 16]                   ; 16 bit mode for 8086 processor (16 bit registers)
[ORG 0x7c00]                ; BIOS loads the boot sector into 0x7c00 and jumps to it (0x7c00 is the entry point)

start:                      ; entry point
    xor ax, ax              ; clear ax register
    mov ds, ax              ; set ds register to 0
    mov es, ax              ; set es register to 0
    mov ss, ax              ; set ss register to 0
    mov sp, 0x7c00          ; set stack pointer to 0x7c00

TestDiskExtension:
    mov [DriveId], dl
    mov ah, 0x41            ; set ax register to 0x41 (BIOS service 0x41 is to check if the disk has extensions)
    mov bx, 0x55aa          ; set bx register to 0x55aa (BIOS service 0x41 will set bx to 0xaa55 if the disk has extensions)
    ; also n ote that dl holds the drive id when BIOS transfer control to our boot code.

    ; since we call disk service more than once later in the boot process, 
    ; and we need to pass the drive id to dl register before we call the disk service.
    int 0x13                ; call BIOS service 0x41

    ; if the service is not supported, the carry flag isset. So we just use jc function
    jc NotSupport   ; if carry flag is set, it means the disk does not have extensions, so we try again
    cmp bx, 0xaa55          ; compare bx register with 0xaa55
    jne NotSupport
    


; this part print the message on the screen, so that we can see our system is running
; print character is done by calling BIOS service using interrupt 0x10
; before calling BIOS service, we need to set the parameters in the registers
printMessage:               ; print message
    mov ah, 0x13            ; set ah register to 0x13 (BIOS service 0x13 is to print character)
    mov al, 1               ; register al specifies the write mode, we set it to 1 so that the cursor will be placed 
                            ; at the end of the string
    mov bx, 0xa             ; set bx register to 0xa. 
                            ; bh (the higher part of bx register represent page number)
                            ; bl (the lower part of bx holds the attribute of the character)
                            ; 0xa means the character is printed in bright green color
    xor dx, dx              ; zero the dx register
                            ; dh (the higher part of dx register represent row number)
                            ; dl (the lower part of dx register represent column number)
                            ; we set dx to 0 so that the character will be printed at the top left corner of the screen
    mov bp, Message         ; set bp register to the address of the message
    mov cx, MessageLen      ; set cx register to the length of the message
    int 0x10                ; call BIOS service 0x13 to print the message

NotSupport:
End:
    hlt                     ; Hat instruction places the processor in a HALT state until an interrupt occurs
    jmp End                 ; create an infinite loop so that the processor will not execute random code after hlt

DriveId: db 0               ; define a byte to hold the drive id

Message: db "Disk extension is supported!"  ; message to be printed, db means define byte, so each character is 1 byte, 
                            ; so the length of the message is 12 bytes.
MessageLen: equ $ - Message ; calculate the length of the message, $ means the current address, 
                            ; so $ - Message means the current address minus the address of the message

; There the expression specifies how many times db is repeated, the $$ sign is the start address of the current section
; We only have one section, so $$ is the start address of the boot sector
; The $ - $$ expression represents the size from the start of the code to the end of the message, then we subtract it from 0x1be
times (0x1be - ($-$$)) db 0 ; fill the rest of the boot sector with 0, 
                            ; 0x1be is the address of the partition table, 
                            ; so we fill the rest of the boot sector with 0 until the partition table

    db 80h                  ; boot signature (indicator), 0x80 means the bootable partition is the first partition
    db 0, 2, 0              ; starting CHS (Cylinder, Head, Sector) 
                            ; first bytes -> Head = 0
                            ; second bytes divided into 2 parts. 
                            ;   bits 0 - 5 -> Sector = 2, 
                            ;   bits 6 - 7 -> Higher bits of Cylinder value = 0
                            ; third bytes -> lower 8 bits of Cylinder value = 0
    db 0f0h                 ; partition type, 0x0f means extended partition
    db 0ffh, 0ffh, 0ffh     ; ending CHS
    dd 1                    ; starting LBA (Logical Block Address) of starting sector of the partition
                            ; in the boot proces we will load our file using LBA, instead of CHS value
    dd (20 * 16 * 63 - 1)   ; size of the partition in sectors, 20 * 16 * 63 is the total number of sectors in the disk
                            ; we subtract 1 because the first sector is sector 0
                            ; The reason we define this entry is that some BIOS will try to find the valid looking partition entries
                            ; and if it finds one, it will try to boot from it, so we need to make it look valid
                            ; it its not valid, the BIOS will not boot from it, and it will boot from the next bootable device

    times (16 * 3) db 0     ; fill the rest of the partition table with 0

    ; this part is the boot signature, 55aa is the boot signature, it is used to tell the BIOS that this is a bootable disk
    ; the size of the boot file is 512 bytes, so the size of the boot sector is 512 bytes
    db 0x55
    db 0xaa