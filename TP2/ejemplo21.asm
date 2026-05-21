;*******************************************************
;Ejemplo3
;-Carga gdt (2 segmentos de datos y 1 segmento de codigo)
;-Entra a modo protegido
;-Carga en cs el segmento de codigo
;-Carga en ds el segmento de datos de video
;-cambio el color de la pantalla
;-Sale de modo protegido
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

;***********************************
;	GDT
;***********************************
gdt:
  ;descriptor nulo
  resb 8

  ; descriptor de datos (Base 0, size 64k, nivel 0)
dataSel0 equ $-gdt

  dw 0xffff
  dw 0x0000
  db 0x00
  db 10010010b
  db 0x00
  db 0x00

; descriptor de video (Base: 0xb8000, size 4k, nivel 0)
videoSel0 equ $-gdt

  dw 0x1000
  dw 0x8000
  db 0x0b
  db 10010010b
  db 0x00
  db 0x00

; descriptor de codigo (Base: 0x0000, size 64k, nivel 0)
codeSel0 equ $-gdt
  dw 0xffff		; Limite en parte baja: 0xffff
  dw 0x0000		; Base baja: 0x0000
  db 0x00		; Base media: 0x00
  db 10011010b     	; Attr: P=1 (presencia), DPL=00, S=1 (no es de Sist), E=1 (exec, segmento de cod), C=0, R=0 (read),A=0(acc)
  db 0x00
  db 0x00		; Base alta: 0x0000

;tamaño de la gdt
gdtSize equ $-gdt

;***********************************
;	Codigo
;***********************************
;comienzo del codigo
inicio: 
;deshabilito interruciones
cli
;***************
;Breakpoint
;***************
xor eax, eax
debug:
 cmp al, 1
 jne debug

;cargo gdtr
mov ax, gdtSize - 1	;longitud de gdt - 1
mov [gdtr + 0], ax		

xor eax, eax
mov ax, gdt
mov [gdtr + 2], eax	;ubicacion de la gdt en memoria	

; cargo en el registro gdtr
lgdt [gdtr]

;paso a modo protegido
mov eax, cr0
or al,1
mov cr0, eax
jmp short $+2

;CS no lo puedo cambiar haciendo: 
;mov ax, codeSel0
;mov cs, ax

; PROCESADOR EJECUTA EL CODIGO APUNTADO POR CS:EIP
; modo real CS:0X0000	EIP: 0X8000
; jmp pepe	se modifica solamente EIP = pepe / CS no cambio
; jmp cs2:pepe	se modifica CS=cs2 y EIP = pepe


;cargo en cs el selector de codigo codeSel0, hago salto largo (mod CS:EIP), corto (solo EIP)
jmp codeSel0:modo_protegido

modo_protegido:
;cargo ds con el selector de video
mov ax, videoSel0
mov ds, ax
;cargo cantidad de puntos en pantalla a pintar
mov cx, 80*25
;cargo valor del atributo
mov al, 0x78 ;01111000 (0x78) para pantalla normal 0x70
;cargo edi = 1
mov edi, 1
bucle_pantalla:
  ;guardo en ds:edi el valor 0x70
  mov [edi], al
  ;incremento edi en dos 
  inc edi
  inc edi
  ;ciclo hasta terminar de recorrer el buffer de video
  loop bucle_pantalla


;loop infinito
jmp $





 
