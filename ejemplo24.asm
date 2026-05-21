;*******************************************************
;Ejercicio 2-4
;Tome el programa del Ejercicio 2.3 e inserte un handler para cada una de las
;excepciones del procesador. Se busca proveer un mínimo manejo de excepciones
;de modo de evitar que el sistema se estrelle ante fallas de protección. Para ello
;cada excepción deberá tener un handler que llame a la porción de código que
;imprima un mensaje en memoria de video y luego ejecute “jmp $”.
;A los fines de probar el funcionamiento de las excepciones, se pide que en el
;caso en que se pulse la tecla ‘J’ (mayúscula o minúscula indistintamente), se
;ejecute cualquier operación no válida que genere una excepción. Cualquier otra
;tecla, continúa la lógica planteada en el Ejercicio 2.3 (actualiza el contador en
;pantalla). 
;*******************************************************
;codigo 16 bits
use16

;offset del codigo en 0x8000
org 8000h

;voy a inicio (salteo variables)
jmp inicio

;***********************************
;	variables
;***********************************
gdtr	resb	6
idtr 	resb    6
keydown_counter dd	0;init keydown count (32 bits) - dw (16 bits)
key_state	db	0;keydown or keyup
msgException db 'A fatal exception DE has occurred. The current application will be terminated.'

;***********************************
;	GDT
;***********************************
gdt:
  ;descriptor nulo
  resb 8

 ; descriptor de datos (base 0, size 64k, nivel 0)
dataSel0 equ $-gdt ; selector descr segment data --> index = 1, TI = 0, RPL = 00

  dw 0xffff     ; limit low part = 65536 = 64k
  dw 0x0000     ; first 2 bytes set = 0
  db 0x00       ; 3er byte base = 0
  db 10010010b  ; attr:P=1 DPL=00 S=1 TIPO=001 (E=0 data segment, ED=0, W=1 write) A=0 
  db 0x00       ; attr high part = 0
  db 0x00       ; 4to byte base = 0

; video descriptor (offset: 0xb8000, size 4k, nivel 0)
videoSel0 equ $-gdt ; selector descr video segment data --> index = 3, TI = 0, RPL = 00

 dw 0x1000     ; limit low part = 4096 = 4k
 dw 0x8000     ; base = 0xb8000, first 2 bytes set 8000
 db 0x0b       ; 3 byte set b
 db 10010010b  ; attr: P=1 DPL=00 S=1 TIPO=001 (E=0 data segment, ED=0, W=1 write) A=0
 db 0x00       ; attr high part = 0
 db 0x00       ; 4to byte base = 0

; code descriptor (base 0x0000, size 64k, nivel 0) for handler
codeSel0 equ $-gdt ; selector descr segment code --> index = 2, TI = 0, RPL = 00
  dw 0xffff	; limit low part = 65536 = 64k
  dw 0x0000	; first 2 bytes base = 0
  db 0x00	; 3er byte base = 0
  db 10011010b	; Attr: P=1 DPL=00 S=1 TIPO=101 (E=1 code segment, C=0, R=1 read and execute) A=0
  db 0x00	; attr high part = 0
  db 0x00	; 4to byte base = 0

;tamaño de la gdt
gdtSize equ $-gdt


;***********************************
;	IDT
;***********************************
idt:
  ;Excepciones predefinidas en el uP --> 
  ;Uso mismo handler, mismo selector con campo TIPO: 16 bits trap gate (TIPO=0111)
  
  ;Excepcion 0: Divide Error
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
  ;Excepcion 1: Debug
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

    resb 8 ; Aca dejo espacio libre pues es la Interrupcion 2
    
  ;Excepcion 3: Breakpoint
    dw excHandler  ; OHandler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 4: Overflow
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 5: Bound Range Exceed
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 6: Invalid Opcode
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
  ;Excepcion 7: Device not available
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 8: Double Fault
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 9: Coproccesor segment overrun
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 10: Invalid TSS
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 11: Segment Not Present
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 12: Stack Segment
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 13: General Protection
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 14: Page Fault
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
    resb 8         ; la 15 esta reservada

  ;Excepcion 16: Floating Point Error
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 17: Alignment Check
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 18: Machine Check
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 19: SIMD Floating Point Exception
    dw excHandler  ; Handler que atiende la excep
    dw codeSel0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
  
  resb 8*13 ; de la 20 a la 31 son reservadas y la 32 es el TimerTick. Son 13 lugares en total.

  ;PUERTA de interrupcion (int 0x21, irq1, teclado)
  dw irq1Handler	;2 bytes offset donde estara el handler a partir de la base del code segment
  dw codeSel0	;low part
  db 0		;bits from 32 to 39 set 0
  db 0x86	;byte attr: P=1 DPL=00 S=0 (system) TIPO=0110 (Gate int. 16 bits) 
  dw 0x00	;last 2 bytes offset set 0

idtSize equ $-idt	;para sacar el tamano de la IDT
;***********************************
;	Codigo
;***********************************
;comienzo del codigo
inicio: 
;deshabilito interruciones
    cli

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

;cargo gdtr
mov ax, gdtSize - 1	;longitud de gdt - 1
mov [gdtr + 0], ax		

xor eax, eax
mov ax, gdt
mov [gdtr + 2], eax	;ubicacion de la gdt en memoria	

;cargo idtr
mov ax, idtSize - 1	;longitud de idt - 1
mov [idtr + 0], ax		

xor eax, eax	;clear bits eax
mov eax, idt
mov [idtr + 2], eax	;ubicacion de la idt en memoria	

; cargo en el registro gdtr (tabla global de desc)
lgdt [gdtr]

; cargo en el registro idtr load idt (tabla de INT)
lidt [idtr]

;paso a modo protegido
mov eax, cr0
or al,1
mov cr0, eax
jmp short $+2

;cargo en cs el selector de codigo codeSel0
jmp codeSel0:modo_protegido	;salto largo, guardo en CS el selector de codigo para modo protegido

modo_protegido:
;load ss, ds, and es with data select (used for print screen)
mov ax, dataSel0
mov ss, ax	;como trabajo con INT debo config la PILA. SS:ESP (debo definir un area de pila)
mov ds, ax

;guardo los datos para la pila en la direccion fin+100h. El ESP va decrementado a medida que guardo en la PILA.
;si la pila ocupa mas de 100h va a comerse parte del codigo (ojo)

;apunto esp al final del codigo + 0x100 (100 bytes)... ahi empieza la PILA
mov eax, fin + 0x100
mov esp, eax

;enmascaro todas las interrupciones menos la irq1 (Teclado) enable -   int 9h solo dejo las que quiero usar
;                                            irq0 (timer tick) disable int 8h

mov al, 0xfd            ; Mascara PIC Master (0x21)   0xfd   1111 1101 (IRQ9) estos 8 bits es el IMR, en 0 la INT que habilito
out 0x21, al

mov al, 0xff            ; Mascara PIC Slave (0xff)
out 0xa1, al

;cargo ds con el selector de video
;Pantalla en modo inverso
mov ax, videoSel0
mov es, ax
mov cx, 80*25	;set count pixels
mov edi, 0x00	;set index = 0 

bucle_pantalla:
  mov al, 0x00	;clear character
  mov [es:edi], al	;clear
  inc edi	;change attr
  mov al, 0x77	;set attr char white and background white --> 0 111 | 0 111
  mov [es:edi], al
  inc edi
  ;ciclo hasta terminar de recorrer el buffer de video
  loop bucle_pantalla	;cx-- and loop while cx>0

;***************
;Breakpoint
;***************
xor eax, eax
debug:
	cmp al, 1
	jne debug
	
xor edi, edi	;set offset=0, first character
sti	;habilito interrupciones

wait_keypress:
	xor eax, eax
	mov al, [keydown_counter]
	add al, 0x30		;convert number 1 digit to ASCII 
	mov [es:edi], al	;print counter
	inc edi		;attr char
	mov al, 0x70		;black char 0111 0000
	mov [es:edi], al
	dec edi
	
	jmp wait_keypress

excHandler:
;Handler que atiende la excepcion cuando se divide por cero por ej.
    cli
    ; Primero pinto toda la pantalla de azul: usare el selector de video, pero recordar que ya lo habia cargado de antes en es
    mov cx, 80*25 ;cargo cantidad de puntos en pantalla a pintar
    mov edi, 0x00 ;cargo edi en 0 porque ahora tambien borrare los caracteres, por lo tanto me movere por todos los bytes de la pantalla
    mov edx, 0x00
    
    bucle_pantalla_2: ; pinta toda la pantalla de azul
    mov al, 0x00     ;poniendo el byte de caracter todo en 0 borra el caracter
    mov [es:edi], al ;borro caracter 
    inc edi          ;incremento edi para pasar al atributo
    mov al, 0x11     ;cargo valor del atributo para poner cada caracter en azul y fondo en azul --> 0x11 = 0 001 | 0 001 (R=0, G=0, B=1)
    mov [es:edi], al 
    inc edi          ;incremento edi para pasar al otro caracter
    ;ciclo hasta terminar de recorrer el buffer de video
    loop bucle_pantalla_2 ; loop usa al registro cx: decrementa cx. Si cx vale mas que 0, salta a la etiqueta indicada
    
    xor edi, edi ; vuelvo a poner el offset en 0, para escribir en el primer caracter
    xor eax, eax ; vuelvo a poner en 0 eax
    
    ;Ahora muestro mensaje de "error"
    printMessage:
    mov al, BYTE [ds:msgException+edx] ; Leo un char del string
    cmp al, 0                    ; Si es NULL fin del string
    je endMessage
    inc edx                      ; Muevo el indice al char siguiente
    mov [es:edi], al             ; Print char
    inc edi                      ; Inc indice (Attr char)
    mov al, 0x17                 ; Attr char en azul y background en azul --> 0x11 = 0 001 | 0 001 (R=0, G=0, B=1)
    mov [es:edi], al
    inc edi                      ; Next char
    jmp printMessage; vuelvo a el inicio de la etiqueta loop
    endMessage:   
    jmp $
    sti
  

irq1Handler:
;se pulse la tecla ‘J’ (mayúscula o minúscula indistintamente), se
;ejecute cualquier operación no válida que genere una excepción. Cualquier otra
;tecla, continúa la lógica planteada en el Ejercicio 2.3 (actualiza el contador en
;pantalla).
;analizar si la tecla presionada es 'J' -- 0x24 es el scan code de la 'j'
  cli	;disable interrupts
  mov al, 0x20
  out 0x20, al
  in al, 0x60
  cmp al, 0x24
  jne no_jota ;si se pulso tecla distinta a jota.
  ;aca genero excepcion, por ej, divido por cero
  xor eax, eax
  mov edx, 1
  mov ecx, 0
  div ecx     ;provoca excepcion 

no_jota:
;incremento contador de teclas
  xor eax, eax
  mov al, [key_state]
  cmp al, 0	;zero set variable 1
  jne set_key_state
  
  mov al, 1
  mov [key_state], al
  
  xor eax, eax
  mov eax, [keydown_counter]
  inc eax
  mov [keydown_counter], eax
  
  jmp fin_handler
  
set_key_state:
	mov al, 0
	mov [key_state], al

fin_handler:
    sti
    iret                       ; fin de la interrupcion. interrupt return


fin:            

; 100h mas adelante configuro el ESP de la pila. 
 
