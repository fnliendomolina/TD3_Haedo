;*******************************************************

;Ejercicio 2-5
;Tome el programa del Ejercicio 2.4, y agregue el código necesario para administrar dos tareas encargadas de la presentación de información en forma simultánea en las mitades superior e inferior de la pantalla respectivamente, utilizando al timer tick de la PC como base de tiempos.
;La información a presentar en cada mitad de la pantalla, consiste en el tiempo acumulado (expresado en décimas de segundos) que lleva escribiendo en cada mitad. Para simplificar los cálculos en su código, reprograme el Timer Tick para generar una interrupción por mseg. Tenga en cuenta que el Timer 0 de la PC tiene una señal de clock externa establecida por un cristal de 1.19 MHz.
;En su condición de arranque (default), el programa dedicará el 50% de los ciclos de timer para cada tarea (de modo que en esta condición el número presentado en cada mitad será el mismo).
;Para alterar la prioridad de cada tarea (y por ende desbalancear los valores presentados en cada una) se desea utilizar la tecla F2, y la tecla F3 para aumentar en pasos del 10% la prioridad de la mitad superior e inferior respectivamente. Cada mitad aumenta su prioridad en desmedro de la otra. Cuando se llega al extremo de tener una tarea al 0% no se la debe invocar hasta que su prioridad aumente al menos al 10%
;Se finaliza el programa limpiando la pantalla cuando se pulsa la tecla F10 y luego un HLT.
;Adicionalmente, cada 1 segundo el sistema deberá llamar a una tarea que envía por puerto serie 0x3f8 (COM1) los tiempos acumulados de las dos tareas antes mencionadas. Configure el bochs para que la salida del puerto serie 0x3f8 se almacene en un archivo de texto.
;En una máquina virtual, el timer es virtual, y puede que no cuente más rápido que 1 mseg, no se preocupe si ve que el tiempo avanza más rápido…
;Utilizar una puerta de tarea para IRQ0, y una puerta de interrupción para IRQ1.
;*******************************************************
;codigo 16 bits
use16

;offset del codigo en 0x8000
org 8000h

;voy a inicio (salteo variables)
jmp inicio

;**************************************************************************************
; Valores de Ticks a darle a cada tarea por el Scheduler --> Tomando como base 10 ticks
;**************************************************************************************
tick50                 equ       5

;***********************************
;	variables
;***********************************
gdtr	                 resb	     6
idtr 	                 resb      6
estado_tecla           db        0
flagNoEjecutar         db        0
contadorTicksTarea1    db	       0 ; para almacenar contador de ticks de la tarea 1
contadorTicksTarea2    db        0 ; para almacenar contador de ticks de la tarea 2
tiempoCentesimasTarea1 dw        0 ; para almacenar contador de tiempo de la tarea 1
tiempoCentesimasTarea2 dw        0 ; para almacenar contador de tiempo de la tarea 2
tiempoTarea1           dw        0 ; para almacenar contador de tiempo de la tarea 1
tiempoTarea2           dw        0 ; para almacenar contador de tiempo de la tarea 2
tiempoPuertoSerie      dw        0 ; para almacenar contador de tiempo de la tarea de puerto serie (cada 1s)
ticksMaxTarea1         db        tick50 ; para almacenar el porcentaje de tiempo que debe conmutar a Tarea 1, inicialmente arranca en 50%
ticksMaxTarea2         db        tick50 ; para almacenar el porcentaje de tiempo que debe conmutar a Tarea 2, inicialmente arranca en 50%
estadoF2               db        0 ; para que solo detecte el pulsado de F2 y no el soltado 
estadoF3               db        0 ; para que solo detecte el pulsado de F3 y no el soltado
estadoConmutacion      db        0 ; para que el Scheduler sepa a que tarea conmutar, si es 0 estoy en tarea 1, si es 1 estoy en tarea 2
msgException           db        'A fatal exception DE has occurred. The current application will be terminated.'
endOfString            db        0 ; Null, fin del string a imprimir
contadorUnidadT1       db        0 ; Aca almacenare las unidades del contador de la tarea 1
contadorDecenaT1       db        0 ; Aca almacenare las decenas del contador de la tarea 1
contadorUnidadT2       db        0 ; Aca almacenare las unidades del contador de la tarea 2
contadorDecenaT2       db        0 ; Aca almacenare las decenas del contador de la tarea 2

;***********************************
; Scan Codes de los Make de teclas
;***********************************
Tecla_J_MakeCode       equ       0x10 ;excepcion
Tecla_A_MakeCode       equ       0x11 ;F2 Inc Priority Task1
Tecla_F_MakeCode       equ       0x12 ;F3 Inc Priority Task2
KEY_Q_MakeCode         equ       0x10

;***********************************
; TSS
;***********************************
;tss de la tarea inicial
tssTareaInicial_Niv0  resb 68h ; reservo 68 hexabytes sin nada por ser la tarea inicial

;tss del Scheduler --> Es de Nivel 0 
tssScheduler_Niv0 dd 0
    dd 0        ;esp0 
    dw 0        ;ss0
    dw 0
    dd 0        ;esp1 (dd: define double --> 32 bits) --> no necesito pila de anillo 1, pues estoy en anillo 0
    dd 0        ;ss1 
    dd 0        ;esp2 --> no necesito pila de anillo 2, pues estoy en anillo 0
    dd 0        ;ss2
    dd 0        ;cr3
    dd irq0Handler  ;eip --> Instruction Pointer --> debera arrancar en irq0Handler al conmutar
    dd 0x202    ;eflags --> habilita Flag de interrupcion
    dd 0        ;eax
    dd 0        ;ecx
    dd 0        ;edx
    dd 0        ;ebx
    dd pilaSch_Niv0+0xff ;esp  --> La pila se configura con ss:esp --> dataSel0:pilaSchNiv0+0xff (de 0 a 99 (ff) y luego al final reserva 100h)
    dd 0        ;ebp
    dd 0        ;esi
    dd 0        ;edi
    dw 0        ;es --> no pongo videoSel pues el Scheduler no pintara la pantalla, lo hara el codigo de la call gate
    dw 0
    dw codeSel_Lvl0 ;cs
    dw 0
    dw dataSel_Niv0 ;ss
    dw 0
    dw dataSel_Niv0 ;ds --> lo usare para las variables 
    dw 0 
    dd 0        ;fs
    dd 0        ;gs
    dd 0
    dd 0

;tss de la tara que envia al puerto serie --> Es de Nivel 0 
tssTareaPuertoSerie_Niv0 dd 0
    dd 0        ;esp0 
    dw 0        ;ss0
    dw 0
    dd 0        ;esp1 (dd: define double --> 32 bits) --> no necesito pila de anillo 1, pues estoy en anillo 0
    dd 0        ;ss1 
    dd 0        ;esp2 --> no necesito pila de anillo 2, pues estoy en anillo 0
    dd 0        ;ss2
    dd 0        ;cr3
    dd puertoSerieHandler  ;eip --> Instruction Pointer --> debera arrancar en irq0Handler al conmutar
    dd 0x202    ;eflags --> habilita Flag de interrupcion
    dd 0        ;eax
    dd 0        ;ecx
    dd 0        ;edx
    dd 0        ;ebx
    dd pilaPuertoSerie_Niv0+0xff ;esp  --> 
    dd 0        ;ebp
    dd 0        ;esi
    dd 0        ;edi
    dw 0        ;es 
    dw 0
    dw codeSel_Lvl0 ;cs
    dw 0
    dw dataSel_Niv0 ;ss
    dw 0
    dw dataSel_Niv0 ;ds --> lo usare para las variables 
    dw 0 
    dd 0        ;fs
    dd 0        ;gs
    dd 0
    dd 0

;tss de la tarea 1 --> Va a ejecutar codigo de nivel 0 para pintar la pantalla con una call gate, por eso tambien configuro la pila de nivel 0, pero es de Nivel 3
tssTarea1_Niv3 dd 0
    dd pilaTarea1_Niv0+0xff     ;esp0 --> aca pongo la pila de nivel 0
    dw dataSel_Niv0             ;ss0
    dw 0
    dd 0       ;esp1
    dd 0       ;ss1
    dd 0       ;esp2
    dd 0       ;ss2
    dd 0       ;cr3
    dd Tarea1_Niv3  ;eip
    dd 0x202   ;eflags
    dd 0       ;eax
    dd 0       ;ecx
    dd 0       ;edx
    dd 0       ;ebx
    dd 0xff    ;esp --> aca pongo la pila de nivel 3 propia de esta tarea: SS:ESP --> pilaSel_Niv3:0xff
    dd 0       ;ebp
    dd 0       ;esi
    dd 0       ;edi
    dw 0       ;es
    dw 0
    dw codeSel_Niv3    ;cs
    dw 0
    dw pilaSelT1_Niv3 ;ss --> Selector del descriptor de datos de la pila de la tarea 1
    dw 0
    dw 0       ;ds --> no uso DS en la tarea de anillo 3 pues solo llama a la call gate de anillo 0, por lo tanto no usa datos niv3
    dw 0 
    dd 0       ;fs
    dd 0       ;gs
    dd 0
    dd 0  

;tss de la tarea 2 --> Va a ejecutar codigo de nivel 0 para pintar la pantalla con una call gate, por eso tambien configuro la pila de nivel 0, pero es de Nivel 3
tssTarea2_Niv3 dd 0
    dd pilaTarea2_Niv0+0xff     ;esp0 --> aca pongo la pila de nivel 0
    dw dataSel_Niv0             ;ss0
    dw 0
    dd 0       ;esp1
    dd 0       ;ss1
    dd 0       ;esp2
    dd 0       ;ss2
    dd 0       ;cr3
    dd Tarea2_Niv3  ;eip
    dd 0x202   ;eflags
    dd 0       ;eax
    dd 0       ;ecx
    dd 0       ;edx
    dd 0       ;ebx
    dd 0xff    ;esp --> aca pongo la pila de nivel 3 propia de esta tarea: SS:ESP --> pilaSel_Niv3:0xff
    dd 0       ;ebp
    dd 0       ;esi
    dd 0       ;edi
    dw 0       ;es
    dw 0
    dw codeSel_Niv3 ;cs
    dw 0
    dw pilaSelT2_Niv3 ;ss --> Selector del descriptor de datos de la pila de la tarea 2
    dw 0
    dw 0       ;ds --> no uso DS en la tarea de anillo 3 pues solo llama a la call gate de anillo 0, por lo tanto no usa datos niv3
    dw 0 
    dd 0       ;fs
    dd 0       ;gs
    dd 0
    dd 0 

;***********************************
;	GDT
;***********************************
gdt: ; direccion base de la gdt
  ;descriptor nulo
  resb 8

; descriptor de datos de nivel 0 (Base: 0, size 64k, nivel 0)
dataSel_Niv0 equ $-gdt ; selector del descriptor de segmento de datos de nivel 0 --> index = 1, TI = 0, RPL = 00 (Niv 0)
  dw 0xffff     ; limite parte baja = 65536 = 64k
  dw 0x0000     ; primeros 2 bytes base = 0
  db 0x00       ; 3er byte base = 0
  db 10010010b  ; atributos: P=1 DPL=00 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0 
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; descriptor de datos de nivel 3 (Base: 0, size 100h, nivel 0)
dataSel_Niv3 equ $-gdt ; selector del descriptor de segmento de datos de nivel 3 --> index = 1, TI = 0, RPL = 11 (Niv 3)
  dw 0x00ff     ; limite parte baja = 255 = 0xff --> limite + 1 = 256 = 0x100 = 100h
  dw datos_anillo3 ; otra forma de definir la base, con una etiqueta
  db 0x00       ; 3er byte base = 0
  db 11110010b  ; atributos: P=1 DPL=11 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0 
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; descriptor de video (Base: 0xb8000, size 4k, nivel 0)
videoSel_Niv0 equ $-gdt ; selector del descriptor de segmento de datos de video de nivel 0 --> index = 3, TI = 0, RPL = 00
  dw 0x1000     ; limite parte baja = 4096 = 4k
  dw 0x8000     ; base = 0xb8000, en los primeros 2 bytes pongo 8000
  db 0x0b       ; en el 3er byte pongo b
  db 10010010b  ; atributos: P=1 DPL=00 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; descriptor de codigo de nivel 0 (Base: 0x0000, size 64k, nivel 0) para el handler de IRQ0
codeSel_Lvl0 equ $-gdt ; selector del descriptor de segmento de codigo --> index = 2, TI = 0, RPL = 00
  dw 0xffff     ; limite parte baja = 65536 = 64k
  dw 0x0000     ; primeros 2 bytes base = 0
  db 0x00       ; 3er byte base = 0
  db 10011010b  ; atributos: P=1 DPL=00 S=1 TIPO=101 (E=1 por lo tanto es segmento de codigo, C=0, R=1 por lo tanto puedo leer y ejecutar) A=0
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; descriptor de codigo de nivel 3 (Base: 0x0000, size 64k, nivel 3), para el codigo de las tareas
codeSel_Niv3 equ $-gdt + 3  ; Selector con RPL=3 
  dw 0xffff     ; limite parte baja = 65536 = 64k
  dw 0x0000     ; primeros 2 bytes base = 0
  db 0x00       ; 3er byte base = 0
  db 11111010b  ; atributos: P=1 DPL=11 S=1 TIPO=101 (E=1 por lo tanto es segmento de codigo, C=0, R=1 por lo tanto puedo leer y ejecutar) A=0
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; callgate para escribir contador de tarea 1 en parte superior --> El codigo de anillo 3 de la tarea 1 usara estara call gate para ejecutar codigo de niv 0
cgPrintPantallaSuperior equ $-gdt +3 ; Selector con RPL=3  (lo pongo con ese +3)
  dw printPantallaSuperior ; offset
  dw codeSel_Lvl0          ; selector del codigo de nivel 0 al que accede esta call gate
  db 0             
  db 11100100b             ; P=1 ; DPL = 11 ; S = 0 ; TIPO = 0100 (Call Gate 16 bits)
  dw 0

; callgate para limpiar la pantalla (DPL = 3)  --> El codigo de anillo 3 de la tarea 2 usara estara call gate para ejecutar codigo de la tarea de niv 0
cgPrintPantallaInferior equ $-gdt +3 ; Selector con RPL=3  (lo pongo con ese +3)
  dw printPantallaInferior ; offset
  dw codeSel_Lvl0          ; selector del codigo de nivel 0 al que accede esta call gate
  db 0             
  db 11100100b             ; P=1 ; DPL = 11 ; S = 0 ; TIPO = 0100 (Call Gate 16 bits)
  dw 0

; descriptor de datos para la pila de nivel 3 de Tarea 1 (Base: pilaTarea1_Niv3, size 100h, nivel 3) 
pilaSelT1_Niv3 equ $-gdt + 3 ; Selector INDEX-TI-RPL con RPL=3 
  dw 0x00ff          ; tamano 100h bytes
  dw pilaTarea1_Niv3 ; base de esta pila
  db 0x00
  db 11110010b       ;atributos: P=1 DPL=11 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0
  db 0x00
  db 0x00

; descriptor de datos para la pila de nivel 3 de Tarea 2 (Base: pilaTarea2_Niv3, size 100h, nivel 3) 
pilaSelT2_Niv3 equ $-gdt + 3 ; Selector INDEX-TI-RPL con RPL=3 
  dw 0x00ff          ; tamano 100h bytes
  dw pilaTarea2_Niv3 ; base de esta pila
  db 0x00
  db 11110010b       ;atributos: P=1 DPL=11 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0
  db 0x00
  db 0x00

;------ Descriptores de TSS --------
; Todos los selectores van con RPL=0 !! --> todas las TSS van en anillo 0 por mas que ejecuten codigo de otro nivel

tssTareaInicial_Niv0_Sel equ $ -gdt ; selector que se cargara en el registro TR que es el selector del descriptor de TSS de la tarea actual
  dw 67h                  ; Limite o tamaño del descriptor
  dw tssTareaInicial_Niv0 ; Base del descriptor 
  db 0 
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssScheduler_Niv0_Sel equ $ -gdt
  dw 67h
  dw tssScheduler_Niv0
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssTareaPuertoSerie_Niv0_Sel equ $ -gdt
  dw 67h
  dw tssTareaPuertoSerie_Niv0
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssTarea1_Niv3_Sel equ $ -gdt
  dw 67h
  dw tssTarea1_Niv3
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssTarea2_Niv3_Sel equ $ -gdt   
  dw 67h
  dw tssTarea2_Niv3
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0


;tamaño de la gdt
gdtSize equ $-gdt


;***********************************
;	IDT
;***********************************
idt: ;direccion base de la idt
  ;A continuacion defino todas las puertas de excepcion predefinidas en el uP --> todas usaran el mismo handler, mismo selector pero el bit TIPO de atributos ahora sera 0111: 16 bits trap gate
  
  ;Excepcion 0: Divide Error
    dw excHandler0  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
  ;Excepcion 1: Debug
    dw excHandler1  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

    resb 8 ; Aca dejo espacio libre pues es la Interrupcion 2
    
  ;Excepcion 3: Breakpoint
    dw excHandler3  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 4: Overflow
    dw excHandler4  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 5: Bound Range Exceed
    dw excHandler5  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 6: Invalid Opcode
    dw excHandler6  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
  ;Excepcion 7: Device not available
    dw excHandler7  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 8: Double Fault
    dw excHandler8  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 9: Coproccesor segment overrun
    dw excHandler9  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 10: Invalid TSS
    dw excHandler10  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 11: Segment Not Present
    dw excHandler11  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 12: Stack Segment
    dw excHandler12  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 13: General Protection
    dw excHandler13  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 14: Page Fault
    dw excHandler14  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
    resb 8         ; la 15 esta reservada

  ;Excepcion 16: Floating Point Error
    dw excHandler16  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 17: Alignment Check
    dw excHandler17  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 18: Machine Check
    dw excHandler18  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 19: SIMD Floating Point Exception
    dw excHandler19  ; Offset donde esta el Handler que atendera las excepciones
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
    resb 8*12      ; de la 20 a la 31 estan reservadas (son 12)

  ;descriptor de puerta de tarea en 0x20 (irq0, timer tick)
    dw 0
    dw tssScheduler_Niv0_Sel ; Selector a descriptor de TSS del Scheduler que conmutara con el timertick
    db 0
    db 10000101b    ; Puertas de tarea en este caso va en con DPL = 00
    dw 0x00

  ;PUERTA de interrupcion 0x21 = 33 (int 0x21, irq1, teclado)
    dw irq1Handler ; primeros 2 bytes de offset donde estara el handler a partir de la base del segmento de codigo
    dw codeSel_Lvl0; selector de descriptor de segmento de codigo para ir a la GDT
    db 0           ; bits del 32 al 39 en 0
    db 0x86        ; byte de atributos: P=1 DPL=00 (puede interrumpir cualquier tarea) S=0 (es de sistema) TIPO=0110 (Puerta de int. de 16 bits) 
    dw 0x00        ; ultimos 2 bytes de offset en 0

idtSize equ $-idt
;***********************************
;	Codigo
;***********************************
;comienzo del codigo
inicio: 
    ;deshabilito interruciones
    cli

;-------- Remapeo de las interrupciones de los PICs -----------------------------------------------------------
    ;Inicializacion PIC 1
    mov al, 0x11 ; icw1: IRQs activas por flanco, modo cascada
    out 0x20, al
    mov al, 0x20 ; icw2: INT base para el PIC N#1 tipo 20H (osea ahora IRQ0 sera el tipo de interrupcion 20h)
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
;--------------------------------------------------------------------------------------------------------------

;-------- Reconfiguro Timer para que interrumpa cada 1ms ------------
    ; Para reprogramar el timer tick para que interrumpa cada 1 ms
    ; debo dividir los 1,193180Mhz por la cuenta a cargar en el 8253/4
    ; Por ejemplo: 1mseg1.19e6 / 04a6h (1190) = 1000 ints/s 
    mov ax,04a6h
    out 40h,al ; Parte Baja
    mov al,ah
    out 40h,al ; Parte Alta
;--------------------------------------------------------------------

    ;cargo gdtr
    mov ax, gdtSize - 1	;cargo limite a la gdtr: longitud de gdt - 1
    mov [gdtr + 0], ax	;a partir de la primer posicion de los 6 bytes de gdtr, osea ocupo 2 bytes, que es el tamaño del limite, por eso uso ax

    xor eax, eax
    mov ax, gdt         ; cargo base de la gdt en ax
    mov [gdtr + 2], eax	; a partir del 3 byte, que es donde esta el campo base de la GDTR, son 4 bytes, por eso uso eax

    ;cargo idtr
    mov ax, idtSize - 1	;longitud de idt - 1
    mov [idtr + 0], ax		

    xor eax, eax
    mov eax, idt
    mov [idtr + 2], eax	;ubicacion de la idt en memoria	

    ;cargo en el registro gdtr
    lgdt [gdtr]

    ;cargo en el registro idtr      load idt
    lidt [idtr]

    ;paso a modo protegido
    mov eax, cr0
    or al,1
    mov cr0, eax
    jmp short $+2

    ;cargo ss, ds, y es con el selector del descriptor de datos de nivel 0 (es lo usare para escribir en pantalla)
    mov ax, dataSel_Niv0
    mov ss, ax
    mov ds, ax
    mov ax, videoSel_Niv0
    mov es, ax

    ;cargo en cs el selector de codigo codeSel0_Niv0
    jmp codeSel_Lvl0:modo_protegido

modo_protegido:
    ;apunto esp al final del codigo + 0x100
    mov eax, pilaTareaInicial_Niv0            ; Pila de la tarea inicial
    mov esp, eax

    ;enmascaro todas las interrupciones menos la irq1 (Teclado)int 21h y irq0 (timer tick) disable int 20h (Luego del remapeado quedo asi)                                           
    mov al, 0xfc   ; Mascara PIC Master   0xfc   1111 1100 --> osea la IRQ1 es el 2do bit, la IRQ0 el primer bit, poniendo en 0 la habilito
    out 0x21, al   ; 0x21 es la direccion del registro de enmascaramiento del PIC Master
    mov al, 0xff   ; Mascara PIC Slave, ponemos todo en 1, osea deshabilito todas sus interrupciones pues no las uso
    out 0xa1, al   ; 0xA1 es la direccion del registro de enmascaramiento del PIC Slave

    ;cargo tss inicial --> lo cargo en tr
    mov ax, tssTareaInicial_Niv0_Sel
    ltr ax

    ;Primero pinto toda la pantalla de blanco (video inverso):
    mov cx, 80*25     ;cargo cantidad de puntos en pantalla a pintar
    mov edi, 0x00     ;cargo edi en 0 porque ahora tambien borrare los caracteres, por lo tanto me movere por todos los bytes de la pantalla
    bucle_pantalla: ; pinta toda la pantalla de blanco
    mov al, 0x00     ;poniendo el byte de caracter todo en 0 borra el caracter
    mov [es:edi], al ;borro caracter 
    inc edi          ;incremento edi para pasar al atributo
    mov al, 0x77     ;cargo valor del atributo para poner cada caracter en blanco y fondo en blanco --> 0 111 | 0 111
    mov [es:edi], al 
    inc edi          ;incremento edi para pasar al otro caracter
    ;ciclo hasta terminar de recorrer el buffer de video
    loop bucle_pantalla ; loop usa al registro cx: decrementa cx. Si cx vale mas que 0, salta a la etiqueta indicada

;-------------------------------Codigo de la aplicacion -------------------------------------------------------------

    sti ;habilito interrupciones

    jmp $
;----------------------------------------------------------------------------------------------------------------------
;                                           Handlers y codigos de las Call Gates
;----------------------------------------------------------------------------------------------------------------------

irq0Handler: ; Este es el handler del Scheduler, se conmuta a el con cada interrupcion del timertick mediante una puerta de tarea 
  ;deshabilito interrupciones
  cli
  ;bajo flag de interrupcion
  mov al, 0x20
  out 0x20, al

  ;Aumento contador de tiempo para tarea de puerto serie
  xor eax,eax
  mov ax,[ds:tiempoPuertoSerie]
  inc ax
  mov [ds:tiempoPuertoSerie],ax
  cmp ax,1000 ;Si paso 1s = 1000ms --> Conmuto a puertoSerieHandler
  jne continuar
  mov WORD[ds:tiempoPuertoSerie], 0 ; Reseteo tiempoPuertoSerie
  ;bajo busy flag de la tarea de nivel 0 (a llamar)
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTareaPuertoSerie_Niv0_Sel + 5], al
  sti
  jmp tssTareaPuertoSerie_Niv0_Sel:0
  jmp irq0Handler


  continuar:
  ;Me fijo en que tarea estoy para saber a cual aumentarle los contadores de ticks --> estadoConmutacion = 0 --> Tarea 1 ; estadoConutacion = 1 --> Tarea 2
  mov al,[ds:estadoConmutacion] 
  cmp al,0
  jne incContadoresTarea2 ; Si es 1, debo incrementar contador de tarea 2

  ;aumento contador de tiempo de centesimas acumulado de tarea1
  xor eax,eax
  mov ax, [ds:tiempoCentesimasTarea1] 
  inc ax ;
  mov [ds:tiempoCentesimasTarea1], ax
  cmp ax, 100
  ;si el contador de centesimas llega a 100 lo reseteo y aumento el contador de tiempo
  jne incContadorTicksTarea1
  mov WORD[ds:tiempoCentesimasTarea1], 0 ; Reseteo tiempoCentesimasTarea1
  xor eax,eax
  mov ax, [ds:tiempoTarea1] 
  inc ax ;
  mov [ds:tiempoTarea1],ax
  ;Veo si la relacion es 100% T1 - 0% T2
  mov al,[ds:flagNoEjecutar]
  cmp al,1 ; si flagNoejecutar = 1 solo debo conmutar a la tarea 1
  je conmutarTarea1

  incContadorTicksTarea1:
  ;aumento contador de tick de tarea1 (Inicialmente arranca con la tarea 1 en un 50%)
  xor eax,eax
  mov al, [ds:contadorTicksTarea1] 
  inc al ;
  mov [ds:contadorTicksTarea1], al
  ;Si contador tarea 1 llego a la cantidad de ticks de su tiempo, reseteo el contador de Ticks de tarea 1 cambio el estado Conmutacion a 1 y conmuto a tarea 2
  cmp al, [ds:ticksMaxTarea1]
  jne conmutarTarea1 ;si no llegue sigo conmutando a tarea 1
  ; ticks alcanzados, buscar siguiente tarea válida
  mov BYTE[ds:contadorTicksTarea1], 0 ;reseteo contadorTicksTarea1
  cmp BYTE[ds:ticksMaxTarea2], 0      ;me fijo si justo quede en una condicion en que la prioridad de tarea 2 es 0%
  je seguirConmutandoT1               ;si lo es porque justo se dio asi, sigo conmutando a la tarea 1
  ;Sino, Tarea 2 tiene prioridad válida, se puede conmutar
  mov BYTE[ds:estadoConmutacion], 1
  jmp conmutarTarea2
  seguirConmutandoT1:
  mov BYTE[ds:estadoConmutacion], 0
  
  conmutarTarea1: ;Si el contador todavia no llego al maximo, sigo conmutando a tarea 1
  ;Si no son iguales, todavia sigo conmutando a tarea 1 --> bajo busy flag de la tarea de nivel 3 (a llamar)
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTarea1_Niv3_Sel + 5], al ; Reseteo Bit Busy Tarea 1
  sti ;habilito las interrupciones
  ;Antes de saltar a la tarea 1, me fijo si justo no se dio la casualidad de que la prioridad de tarea 1 era 0%, si lo era no salto a tarea 1
  cmp BYTE[ds:ticksMaxTarea1], 0
  je skipTarea1
  jmp tssTarea1_Niv3_Sel:0
  skipTarea1:
  jmp irq0Handler

  incContadoresTarea2:
  ;aumento contador de tiempo de centesimas acumulado de tarea2
  xor eax,eax
  mov ax, [ds:tiempoCentesimasTarea2] 
  inc ax ;
  mov [ds:tiempoCentesimasTarea2], ax
  cmp ax, 100
  ;si el contador de centesimas llega a 100 lo reseteo y aumento el contador de tiempo
  jne incContadorTicksTarea2
  mov WORD[ds:tiempoCentesimasTarea2], 0 ; Reseteo tiempoCentesimasTarea1
  xor eax,eax
  mov ax, [ds:tiempoTarea2] 
  inc ax ;
  mov [ds:tiempoTarea2],ax
  ;Veo si la relacion es 100% T2 - 0% T1
  mov al,[ds:flagNoEjecutar]
  cmp al,1 ; si flagNoejecutar = 1 solo debo conmutar a la tarea 2
  je conmutarTarea2

  incContadorTicksTarea2:
  ;aumento contadores de tick de tarea2 (Inicialmente arranca con la tarea 2 en un 50%)
  xor eax,eax
  mov al, [ds:contadorTicksTarea2] 
  inc al ;
  mov [ds:contadorTicksTarea2], al
  ;Si contador tarea 2 llego a la cantidad de ticks de su tiempo, reseteo el contador de Ticks de tarea 2 cambio el estado Conmutacion a 0 y conmuto a tarea 1
  cmp al, [ds:ticksMaxTarea2]
  jne conmutarTarea2 ;si no llegue sigo conmutando a tarea 2
  ;ticks alcanzados, buscar siguiente tarea válida
  mov BYTE[ds:contadorTicksTarea2], 0 ;reseteo contadorTicksTarea0
  cmp BYTE[ds:ticksMaxTarea1], 0      ;me fijo si justo quede en una condicion en que la prioridad de tarea 2 es 0%
  je seguirConmutandoT2
  ;Sino, Tarea 2 tiene prioridad válida, se puede conmutar
  mov BYTE[ds:estadoConmutacion], 0
  jmp conmutarTarea1
  seguirConmutandoT2:
  mov BYTE[ds:estadoConmutacion], 1

  conmutarTarea2:
  ;Si no son iguales, todavia sigo conmutando a tarea 2 --> bajo busy flag de la tarea de nivel 3 (a llamar)
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTarea2_Niv3_Sel + 5], al ; Reseteo Bit Busy Tarea 1
  sti ;habilito las interrupciones
  ;Antes de saltar a la tarea 1, me fijo si justo no se dio la casualidad de que la prioridad de tarea 1 era 0%, si lo era no salto a tarea 1
  cmp BYTE[ds:ticksMaxTarea2], 0
  je skipTarea2
  jmp tssTarea2_Niv3_Sel:0
  skipTarea2:
  jmp irq0Handler

;---------------------------------------------------------------------------------------------------------------------------------------

puertoSerieHandler:
  wait1:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait1            ; Si no está vacío, esperar
  mov al, [ds:contadorDecenaT1]
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  wait2:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait2            ; Si no está vacío, esperar
  mov al, [ds:contadorUnidadT1]
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  wait3:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait3            ; Si no está vacío, esperar
  mov al, [ds:contadorDecenaT2]
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  wait4:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait4            ; Si no está vacío, esperar
  mov al, [ds:contadorUnidadT2]
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  jmp puertoSerieHandler

;---------------------------------------------------------------------------------------------------------------------------------------

Tarea1_Niv3:  
  ;llamo a la callgate de la tarea 1
  call cgPrintPantallaSuperior:0  ; con esto ejecuto codigo de nivel 0 --> cgPrintPantalla es el selector de la callgate, que es el descriptor que accede
                                  ; a la memoria donde esta el codigo printPantalla, que esto se hace en anillo 0 ya que pinta la pantalla y su memoria
                                  ; la pusimos en anillo 0
  jmp Tarea1_Niv3

;---------------------------------------------------------------------------------------------------------------------------------------

Tarea2_Niv3:  
  ;llamo a la callgate de la tarea 2
  call cgPrintPantallaInferior:0  ; con esto ejecuto codigo de nivel 0 --> cgPrintPantalla es el selector de la callgate, que es el descriptor que accede
                                  ; a la memoria donde esta el codigo printPantalla, que esto se hace en anillo 0 ya que pinta la pantalla y su memoria
                                  ; la pusimos en anillo 0
  jmp Tarea2_Niv3

;---------------------------------------------------------------------------------------------------------------------------------------

printPantallaSuperior:
  ;Cuando entro a código de nivel 0 mediante la call gate, lo primero que tengo que hacer es cargar los selectores de nivel 0 en DS, ES, 
  ;pues yo venia de nivel 3
  mov ax, dataSel_Niv0
  mov ds, ax
  mov ax, videoSel_Niv0
  mov es, ax

  ;Muevo contador de tiempo tarea 1 a ax
  mov ax, [ds:tiempoTarea1] 

  ;Logica para separar en decenas y unidades de decimas de segundos el contador de tiempo de la tarea 1
  xor dx, dx    ; limpio dx antes de cada div pues en 16 bits hace DX:AX / BX
  mov bx, 100
  div bx        ; AX = tiempo / 100 → resultado en AX
                ; ahora AX tiene el número que queremos mostrar
                ; vamos a separar ese número en decenas y unidades
  mov cx, ax    ; guardo el resultado del cociente para no perderlo
  ; Separar en decena y unidad
  mov ax, cx    ; recupero el valor
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:contadorDecenaT1], al
  mov [ds:contadorUnidadT1], dl

  ;Logica para imprimir el tiempo en la mitad superior de la pantalla
  xor eax, eax
  xor edi, edi           ;reseteo edi para que vaya superponiendo el contador a imprimir
  add edi, 80*13         ;llevo el puntero a la mitad superior de la pantalla
  ;Imprimo decena
  mov al, [ds:contadorDecenaT1]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena en el caracter de la mitad de la mitad superior de la pantalla 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad
  ;Imprimo unidad
  mov al, [ds:contadorUnidadT1]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi
  inc edi 
  inc edi
  ;Imprimo ticksMax por tarea1
  mov al, [ds:ticksMaxTarea1]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi
  inc edi 
  inc edi
  ;Imprimo contadorTicksTarea1 
  mov al, [ds:contadorTicksTarea1]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al  
  retf                   ;retorno de la callgate

;---------------------------------------------------------------------------------------------------------------------------------------

printPantallaInferior:
  ;Cuando entro a código de nivel 0 mediante la call gate, lo primero que tengo que hacer es cargar los selectores de nivel 0 en DS, ES, 
  ;pues yo venia de nivel 3 
  mov ax, dataSel_Niv0
  mov ds, ax
  mov ax, videoSel_Niv0
  mov es, ax

  ;Muevo contador de tiempo tarea 2 a ax
  mov ax, [ds:tiempoTarea2] 

  ;Logica para separar en decenas y unidades de decimas de segundos el contador de tiempo de la tarea 1
  xor dx, dx    ; limpio dx antes de cada div pues en 16 bits hace DX:AX / BX
  mov bx, 100
  div bx        ; AX = tiempo / 100 → resultado en AX
                ; ahora AX tiene el número que queremos mostrar (por ejemplo, 37)
                ; vamos a separar ese número en decenas y unidades
  mov cx, ax    ; guardo el resultado del cociente para no perderlo
  ; Separar en decena y unidad
  mov ax, cx    ; recupero el valor
  xor dx, dx
  mov bx, 10
  div bx        ; AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:contadorDecenaT2], al
  mov [ds:contadorUnidadT2], dl

  ;Logica para imprimir el tiempo en la mitad inferior de la pantalla
  xor eax, eax
  xor edi, edi           ;reseteo edi para que vaya superponiendo el contador a imprimir
  add edi,80*37          ;llevo el puntero a la mitad inferior de la pantalla
  ;Imprimo decena
  mov al, [ds:contadorDecenaT2]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al ;imprimo decena en el caracter de la mitad de la mitad inferior de la pantalla (40*25)
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad
  ;Imprimo unidad
  mov al, [ds:contadorUnidadT2]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi
  inc edi 
  inc edi
  ;Imprimo ticksMax por tarea2
  mov al, [ds:ticksMaxTarea2]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi
  inc edi 
  inc edi
  ;Imprimo contadorTicksTarea2 
  mov al, [ds:contadorTicksTarea2]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al  
  retf  

;---------------------------------------------------------------------------------------------------------------------------------------

irq1Handler: ;Entra cada vez que se pulsa una tecla
    cli ;deshabilito interrupciones
    ;bajo flag de interrupcion --   EOI End of Interrupt. mandatorio.
    mov al, 0x20   ; 0x20, comando para bajar flag de interrupcion
    out 0x20, al   ; 0x20 aca es la direccion del puerto de E/S del PIC Master
    
    ; aca leo el teclado para ver si se presiono la j, que es la que hara algo que haga saltar una excepcion
    in al, 0x60               ; IMPORTANTE! aunque no lo use, leer el scan code porque sino se llena el buffer del teclado!!
    cmp al, Tecla_J_MakeCode  ; Si se pulso la tecla J no salta 
    jne no_es_la_jota         ; Si no se pulso la j, al sera distinto a 0x24 por lo tanto salta a no_es_la_jota y sigue

    ;si se pulso la jota no salta, hago algo que genere una excepcion, como por ejemplo dividir por 0
    ;Cuando divido por un registro de 32 bits (EXC), el par de registros EAX:EDX (número de 64 bits) se divide por este registro (EXC). Por lo tanto, debo poner a  cero el registro EAX y colocar el dividendo en EDX
    xor eax, eax ; pongo en 0 eax
    mov edx, 1   ; pongo el dividendo (cualquiera) en edx, en este caso 1
    mov ecx, 0   ; pongo el divisor 0, en edx
    div ecx      ; hace eax:edx dividido exc, osea algo dividido 0, debe generar la excepcion de dividir por 0

    no_es_la_jota:
    xor ebx, ebx ; limpio registro ebx
    ;si estado_tecla es 1 es porque ya pulse, por lo tanto cuando vuelva a entrar aca es porque solte y no aumento contador
    mov bl, [ds:estado_tecla]
    cmp bl, 0
    jne resetear_estado_tecla ;si estado_tecla es 0, no es igual a 1, por lo tanto sigue
                             ;si estado_tecla es 1, es porque ya solte, por lo tanto salta y resetea estado tecla
                             
    ;pone en 1 estado_tecla y analiza si se presiona F2, F3 o F10
    mov bl, 1
    mov [estado_tecla], bl
    ;in al, 0x60                ; vuelvo a leer teclado
    cmp al, Tecla_A_MakeCode  ; Si se pulso la tecla A 
    je pulseA       
    cmp al, Tecla_F_MakeCode  ; Si se pulso la tecla F
    je pulseF  
    cmp al, Tecla_ESC_MakeCode ; Si se pulso la tecla ESC
    jne fin_handler   

    ;Logica si pulse ESC --> Pinto pantalla de blanco y hago HLT
    ;Primero pinto toda la pantalla de blanco (video inverso):
    mov cx, 80*25     ;cargo cantidad de puntos en pantalla a pintar
    mov edi, 0x00     ;cargo edi en 0 porque ahora tambien borrare los caracteres, por lo tanto me movere por todos los bytes de la pantalla
    bucle_pantalla2: ; pinta toda la pantalla de blanco
    mov al, 0x00     ;poniendo el byte de caracter todo en 0 borra el caracter
    mov [es:edi], al ;borro caracter 
    inc edi          ;incremento edi para pasar al atributo
    mov al, 0x77     ;cargo valor del atributo para poner cada caracter en blanco y fondo en blanco --> 0 111 | 0 111
    mov [es:edi], al 
    inc edi          ;incremento edi para pasar al otro caracter
    ;ciclo hasta terminar de recorrer el buffer de video
    loop bucle_pantalla2 ; loop usa al registro cx: decrementa cx. Si cx vale mas que 0, salta a la etiqueta indicada
    hlt 
    ;jmp fin_handler

    pulseA: ;logica si pulse A --> aumento 10% prioridad de tarea A y disminuyo 10% prioridad de tarea B
    ;si ticksMaxTarea2 = 0 no sigo decrementandolo
    mov BYTE[ds:contadorTicksTarea1], 0 ; Reseteo contadorTicksTarea1
    mov BYTE[ds:contadorTicksTarea2], 0 ; Reseteo contadorTicksTarea2
    mov al,[ds:ticksMaxTarea2]
    cmp al,0
    je noEjecutarTarea1o2
    ;si ticksMaxTarea2 todavia no es 0, aumento en 1 ticksMaxTarea1 y disminuyo en 1 ticksMaxTarea2
    mov BYTE[ds:flagNoEjecutar], 0 ; Reseteo flagNoEjecutar
    mov al,[ds:ticksMaxTarea1]
    inc al
    mov [ds:ticksMaxTarea1],al
    mov al,[ds:ticksMaxTarea2]
    dec al
    mov [ds:ticksMaxTarea2],al
    jmp fin_handler

    pulseF: ;logica si pulse F --> aumento 10% prioridad de tarea B y disminuyo 10% prioridad de tarea A
    ;si ticksMaxTarea1 = 0 no sigo decrementandolo
    mov BYTE[ds:contadorTicksTarea1], 0 ; Reseteo contadorTicksTarea1
    mov BYTE[ds:contadorTicksTarea2], 0 ; Reseteo contadorTicksTarea2
    mov al,[ds:ticksMaxTarea1]
    cmp al,0
    je noEjecutarTarea1o2
    ;si ticksMaxTarea1 todavia no es 0, aumento en 1 ticksMaxTarea2 y disminuyo en 1 ticksMaxTarea1
    mov BYTE[ds:flagNoEjecutar], 0 ; Reseteo flagNoEjecutar
    mov al,[ds:ticksMaxTarea2]
    inc al
    mov [ds:ticksMaxTarea2],al
    mov al,[ds:ticksMaxTarea1]
    dec al
    mov [ds:ticksMaxTarea1],al    
    jmp fin_handler

    resetear_estado_tecla:     ; reseteo estado tecla
    mov bl, 0
    mov [ds:estado_tecla], bl

    noEjecutarTarea1o2:
    mov al, 1
    mov [ds:flagNoEjecutar],al
    ; si tarea 1 o 2 ya no deben ejecutarse, me aseguro de que estadoConmutacion apunte a la que sí
    cmp BYTE[ds:ticksMaxTarea1], 0
    je setTarea2
    cmp BYTE[ds:ticksMaxTarea2], 0
    je setTarea1
    jmp fin_handler
    setTarea1:
    mov BYTE[ds:estadoConmutacion], 0
    jmp fin_handler
    setTarea2:
    mov BYTE[ds:estadoConmutacion], 1

    fin_handler:               ; Si no se pulso ninguna de las teclas indicadas salgo de la interrupcion sin hacer nada           
    sti
    iret                       ; fin de la interrupcion. interrupt return

excHandler0:
  push 0
  jmp excHandler

excHandler1:
  push 1
  jmp excHandler

excHandler3:
  push 3
  jmp excHandler

excHandler4:
  push 4
  jmp excHandler

excHandler5:
  push 5
  jmp excHandler

excHandler6:
  push 6
  jmp excHandler

excHandler7:
  push 7
  jmp excHandler

excHandler8:
  push 8
  jmp excHandler

excHandler9:
  push 9
  jmp excHandler

excHandler10:
  push 10
  jmp excHandler

excHandler11:
  push 11
  jmp excHandler

excHandler12:
  push 12
  jmp excHandler

excHandler13:
  push 13
  jmp excHandler

excHandler14:
  push 14
  jmp excHandler

excHandler16:
  push 16
  jmp excHandler

excHandler17:
  push 17
  jmp excHandler

excHandler18:
  push 18
  jmp excHandler

excHandler19:
  push 19
  jmp excHandler

excHandler: ; handler general de la excepcion --> aca pinto toda la pantalla de azul por ejemplo, muestro un mensaje de error y numero de excepcion
    cli

    pop eax         ; saco número excepción (vector) de la pila
    mov bl, al      ; guardo en bl
    
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
    printLoop:
    mov al, BYTE [ds:msgException+edx] ; Lee un caracter del string
    cmp al, 0                    ; Si es 0 (Null) termina (End Of String)
    je finMensaje
    inc edx                      ; Incremento puntero string
    mov [es:edi], al             ; Imprimo el caracter que esta almacenado en al
    inc edi                      ; Incremento el puntero (Color (atributo) del caracter)
    mov al, 0x17                 ; Cargo valor del atributo para poner cada caracter en azul y fondo en azul --> 0x11 = 0 001 | 0 001 (R=0, G=0, B=1)
    mov [es:edi], al
    inc edi                      ; Incremento el puntero (Siguiente caracter)
    jmp printLoop; vuelvo a el inicio de la etiqueta loop
    finMensaje: ;Imprimo numero de excepcion
    add bl, '0'     ; convierto a ASCII
    mov [es:edi], bl
    inc edi
    mov al, 0x17
    mov [es:edi], al
    inc edi
    jmp $
    sti
fin:            

; 100h mas adelante configuro el ESP de la pila. 
 
;------------------------------------------
; ESPACIOS PARA PILAS Y SEGMENTOS DE DATOS
;------------------------------------------
pilaTareaInicial_Niv0:   ; pila de tarea inicial
resb 100h

pilaSch_Niv0:            ; irq0
resb 100h

pilaPuertoSerie_Niv0:         ; Tarea Puerto Serie
resb 100h

pilaTarea1_Niv0:         ; Tarea Print Pantalla (Anillo 3 // call gate accede a Anillo 0)
resb 100h

pilaTarea2_Niv0:         ; Tarea Print Pantalla (Anillo 3 // call gate accede a Anillo 0)
resb 100h

;Segmento de datos Anillo 3
datos_anillo3:
resb 100h

;Pila Tarea 1 Anillo 3
pilaTarea1_Niv3:
resb 100h

;Pila Tarea 1 Anillo 3
pilaTarea2_Niv3:
resb 100h