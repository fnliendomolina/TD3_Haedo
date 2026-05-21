;*******************************************************
;Ejemplo
;-Carga gdt (2 segmentos de datos y 1 segmento de codigo)
;-Entra a modo protegido
;-Carga en cs el segmento de codigo;
;-habilito interrupciones
;-espero presion de tecla
;-deshabilito interrupciones
;-Carga en ds el segmento de datos de video
;-cambio el color de la pantalla
;-al presionar tecla aumenta el contador mostrado en pantalla
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
  ;entradas no utilizadas. No uso int 0 a int 8, pero tengo que dejar el espacio para los descriptores. 
  resb 8*9	;desde 0 a 8 descriptores para las INT estan vacios en el 10 comienza la de teclado 

  ;PUERTA de interrupcion (int 9, irq1, teclado)
  dw irq1Handler	;9h INT keyboard. 2 bytes offset donde estara el handler a partir de la base del code segment
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
;base en la parte baja y limite en la parte alta

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

irq1Handler:
  cli	;disable interrupts
  mov al, 0x20
  out 0x20, al
  in al, 0x60
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
 
