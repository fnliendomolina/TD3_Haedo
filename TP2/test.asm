use16

org 8000h

jmp inicio

gdtr resb 6
idtr resb 6
msgException db 'Fatal error exception'

;GDT
gdt:
    ;desc nulo
    resb 8

;descriptores
dataSel0 equ $-gdt

  dw 0xffff
  dw 0x0000
  db 0x00
  db 10010010b 
  db 0x00
  db 0x00
;desc de video
videoSel0 equ $-gdt

  dw 0x1000
  dw 0x8000
  db 0x0b
  db 10010010b
  db 0x00
  db 0x00
;desc de codigo
codeSel0 equ $-gdt
  dw 0xffff
  dw 0x0000
  db 0x00
  db 10011010b ; Attr: P=1 (presencia), DPL=00, S=1 (no es de Sist), E=1 (exec, segmento de cod), C=0, R=0 (read),A=0(acc)
  db 0x00
  db 0x00

;en gdt defino todos los descriptores
;luego tamano de gdt
gdtSize equ $-gdt

;idt

idt:
  ;Excepciones predefinidas en el uP --> 
  ;Uso mismo handler, mismo selector con campo TIPO: 16 bits trap gate (TIPO=0111)
  ;excep 0
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 1
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  resb 8

  ;excep 3
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 4
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 5
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 6
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 7
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 8
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 9
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 10
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 11
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 12
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 13
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 14
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  resb 8

  ;excep 16
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 17
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 18
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;excep 19
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  resb 8*13;

  ;excep 0
  dw excHandler
  dw codeSel0
  db 0
  db 0x87 ;1000 0111 -: P=1; DPL=00; S=0; TIPO=0111
  db 0x00

  ;Pta INT 0x21 teclado

  dw irq1Handler
  dw codeSel0
  db 0
  db 0x86 ;byte attr: P=1 DPL=00 S=0 (system) TIPO=0110 (Gate int. 16 bits) 
  dw 0x00

idtSize equ $-idt

;codigo
inicio:
;deshabilito INT porque estoy en modo real
cli

;reprogramo el PIC antes de entrar modo protegido
;Inicializacion PIC 1
    mov al, 0x11 ; icw1: IRQs activas por flanco, modo cascada
    out 0x20, al
    mov al, 0x20 ; icw2: INT base para el PIC N#1 tipo 20H (IRQ0 sera el tipo de interrupcion 20h)
    out 0x21, al ; el PIC1 comienza en 0x20
    mov al, 0x04 ; icw3: PIC N#1 Master tiene un slave conectado a IRQ2 (0000 0100b)
    out 0x21, al
    mov al, 0x01 ; icw4: Modo No Buffered, Fin de interrupcion normal, procesador 8086
    out 0x21, al

;Inicializacion PIC 2
    mov al, 0x11 ; icw1: IRQs activas por flanco, modo cascada
    out 0xa0, al
    mov al, 0x28 ; icw2: INT base para el PIC N#1 tipo 28h
    out 0xa1, al ; el PIC2 comienza en 0x28
    mov al, 0x02 ; icw3: PIC N#2 Slave, IRQ2 es la linea que envia al Master (010b)
    out 0xa1, al
    mov al, 0x01 ; icw4: Modo No Buffered, Fin de interrupcion normal, procesador 8086
    out 0xa1, al


;break
xor eax, eax
debug:
  cmp al, 1
  jne debug

;cargo gdtr
mov ax, gdtSize-1
mov [gdtr+0], ax

xor eax, eax
mov ax, gdt
mov [gdtr+2], eax

;cargo idtr
mov ax, idtSize-1
mov [idtr+0], ax

xor eax, eax
mov eax, idt
mov [idtr+2], eax

;cargo reg gdtr
lgdt [gdtr]
;cargo reg idtr
lidt [idtr]

;paso a modo protegido
mov eax, cr0
or al, 1
mov cr0, eax
jmp short $+2

jmp codeSel0:modo_protegido

modo_protegido:
  mov ax, dataSel0
  mov ss, ax ;config pila
  mov ds, ax ;cargo selector de video en ds

  mov eax, fin+0x100
  mov esp, eax

  mov al, 0xfd 
  out 0x21, al

  mov al, 0xff
  out 0xa1, al

  mov ax, videoSel0
  mov es, ax
  ;cargo pixeles en contador cx
  mov cx, 80*25
  mov edi, 0x00

  ;attr para pantalla
  mov al, 0x78 ;0111 1000
  mov edi, 1
  bucle_pantalla:
    mov al, 0x00
    mov [es:edi], al
    inc edi
    mov al, 0x77
    mov [es:edi], al
    inc edi
    loop bucle_pantalla

sti


irq1Handler:
  cli
  mov al, 0x20
  out 0x20, al
  in al, 0x20
  cmp al, 0x24
  jne no_jota
  xor eax, eax
  mov edx, 1
  mov ecx, 0
  div ecx ;excepcion div por cero

excHandler:
  cli
  mov cx, 80*25
  mov edi, 0x00
  mov edx, 0x00
  ;pintar pantalla
  bucle_pantalla_excep:
    mov al, 0x00
    mov [es:edi], al
    inc edi
    mov al, 0x11
    mov [es:edi], al
    inc edi
    loop bucle_pantalla_excep
  ;mostrar msg
  xor edi, edi
  xor eax, eax

  printMessage:
    mov al, BYTE[ds:msgException]
    cmp al, 0 ;busco /0
    je finString
    inc edx
    mov [es:edi], al
    inc edi
    mov al, 0x17
    mov [es:edi], al
    inc edi
    jmp printMessage

  finString:
    jmp $
    sti
    

no_jota:
  sti
  iret
  

fin: