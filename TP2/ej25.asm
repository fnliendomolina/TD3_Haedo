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

tick50                 equ       5

;***********************************
;	variables
;***********************************
gdtr	resb	6
idtr 	resb    6
count_ticks dd	0; cuento ticks en SCH por cada INT
key_state	db	0;keydown or keyup
msgException db 'A fatal exception DE has occurred. The current application will be terminated.'
counter_decenas db 0; contador decenas
counter_unidades db 0; contador unidades
keydown_counter db 0;
contadorTicksTarea1    db	       0 ; para almacenar contador de ticks de la tarea 1
contadorTicksTarea2    db        0 ; para almacenar contador de ticks de la tarea 2
contadorUnidadT1       db        0 ; Aca almacenare las unidades del contador de la tarea 1
contadorDecenaT1       db        0 ; Aca almacenare las decenas del contador de la tarea 1
contadorUnidadT2       db        0 ; Aca almacenare las unidades del contador de la tarea 2
contadorDecenaT2       db        0 ; Aca almacenare las decenas del contador de la tarea 2
tiempoTarea1           dw        0 ; para almacenar contador de tiempo de la tarea 1
tiempoTarea2           dw        0 ; para almacenar contador de tiempo de la tarea 2
tiempoPuertoSerie      dw        0 ; para almacenar contador de tiempo de la tarea de puerto serie (cada 1s)
ticksMaxTarea1         db        tick50 ; para almacenar el porcentaje de tiempo que debe conmutar a Tarea 1, inicialmente arranca en 50%
ticksMaxTarea2         db        tick50 ; para almacenar el porcentaje de tiempo que debe conmutar a Tarea 2, inicialmente arranca en 50%

;***********************************
;Scan Code de los make code
;***********************************
F2_Key_MakeCode equ 0x10 ;0x24 se reemplaza por 'q'
F3_Key_MakeCode equ 0x11 ;0x1e se reemplaza por 'w'
F10_Key_MakeCode equ 0x19 ;0x21 se reemplaza por 'p'
ESC_Key_MakeCode equ 0x01 

TICKS_SERIAL_PORT equ 1000 ;1000mS
TICKS_LIMIT_TASK1 equ 500 ;umbral para T1 (0-500)
TICKS_TASK2 equ 1000 ;limite para T2 (500-1000)

;***********************************
;TSS - 1 por cada tarea
;***********************************
;TSS inicial - Seria como el proceso padre por donde empieza el programa
tssTaskInit_Lvl0  resb 68h;

;TSS SCH - Corre en Anillo 0
tssScheduler_Lvl0 
    dd 0
    dd 0        ;esp0 
    dw 0        ;ss0
    dw 0
    dd 0        ;esp1 (dd: define double --> 32 bits) --> PILA ANILLO 1: No se usa
    dd 0        ;ss1 
    dd 0        ;esp2 --> PILA ANILLO 2: No se usa
    dd 0        ;ss2
    dd 0        ;cr3
    dd irq0Handler  ;eip --> Instruction Pointer --> Al llamar a la tarea se dirige al offset irq0Handler
    dd 0x202    ;eflags --> habilita Flag de interrupcion
    dd 0        ;eax
    dd 0        ;ecx
    dd 0        ;edx
    dd 0        ;ebx
    dd stackSch_Niv0+0xff ;esp  --> La pila se configura con ss:esp --> dataSel0:pilaSchNiv0+0xff (de 0 a 99 (ff) y luego al final reserva 100h)
    dd 0        ;ebp
    dd 0        ;esi
    dd 0        ;edi
    dw 0        ;es
    dw 0
    dw codeSel_Lvl0 ;cs
    dw 0
    dw dataSel_Lvl0 ;ss
    dw 0
    dw dataSel_Lvl0 ;ds --> segmento de datos para las variables
    dw 0 
    dd 0        ;fs
    dd 0        ;gs
    dd 0
    dd 0

;tss tarea puerto serie - Para accederlo necesito Anillo 0
tssTaskSerialPort_Lvl0 
    dd 0
    dd 0        ;esp0 
    dw 0        ;ss0
    dw 0
    dd 0        ;esp1 (dd: define double --> 32 bits) --> no necesito pila de anillo 1, pues estoy en anillo 0
    dd 0        ;ss1 
    dd 0        ;esp2 --> no necesito pila de anillo 2, pues estoy en anillo 0
    dd 0        ;ss2
    dd 0        ;cr3
    dd serialPortHandler  ;eip --> Instruction Pointer --> Al llamar a la tarea se dirige al offset puertoSerieHandler
    dd 0x202    ;eflags --> habilita Flag de interrupcion
    dd 0        ;eax
    dd 0        ;ecx
    dd 0        ;edx
    dd 0        ;ebx
    dd stackSerialPort_Niv0+0xff ;esp  --> 
    dd 0        ;ebp
    dd 0        ;esi
    dd 0        ;edi
    dw 0        ;es 
    dw 0
    dw codeSel_Lvl0 ;cs
    dw 0
    dw dataSel_Lvl0 ;ss
    dw 0
    dw dataSel_Lvl0 ;ds --> segmento de datos para las variables
    dw 0 
    dd 0        ;fs
    dd 0        ;gs
    dd 0
    dd 0

;tss tarea 1 --> Va a ejecutar codigo de nivel 0 para pintar la pantalla con una call gate, 
;por eso tambien configuro la pila de nivel 0, pero es de Nivel 3
tssTask1_Lvl3 
    dd 0
    dd stackTask1_Niv0+0xff     ;esp0 --> PILA ANILLO 0 de esta tarea
    dw dataSel_Lvl0             ;ss0
    dw 0
    dd 0       ;esp1
    dd 0       ;ss1
    dd 0       ;esp2
    dd 0       ;ss2
    dd 0       ;cr3
    dd Task1_Lvl3  ;eip
    dd 0x202   ;eflags
    dd 0       ;eax
    dd 0       ;ecx
    dd 0       ;edx
    dd 0       ;ebx
    dd 0xff    ;esp --> PILA ANILLO 3 de esta tarea: SS:ESP --> pilaSel_Niv3:0xff
    dd 0       ;ebp
    dd 0       ;esi
    dd 0       ;edi
    dw 0       ;es
    dw 0
    dw codeSel_Lvl3    ;cs
    dw 0
    dw stackSelT1_Lvl3 ;ss --> Selector del descriptor de datos de la pila de la tarea 1
    dw 0
    dw 0       ;ds --> no uso DS en la tarea de anillo 3 pues solo llama a la call gate de anillo 0, por lo tanto no usa datos niv3
    dw 0 
    dd 0       ;fs
    dd 0       ;gs
    dd 0
    dd 0  

;tss de la tarea 2 --> Va a ejecutar codigo de nivel 0 para pintar la pantalla con una call gate, 
;por eso tambien configuro la pila de nivel 0, pero es de Nivel 3
tssTask2_Lvl3 
    dd 0
    dd stackTask2_Niv0+0xff     ;esp0 ---> PILA ANILLO 0 de esta tarea
    dw dataSel_Lvl0             ;ss0
    dw 0
    dd 0       ;esp1
    dd 0       ;ss1
    dd 0       ;esp2
    dd 0       ;ss2
    dd 0       ;cr3
    dd Task2_Lvl3  ;eip
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
    dw codeSel_Lvl3 ;cs
    dw 0
    dw stackSelT2_Lvl3 ;ss --> Selector del descriptor de datos de la pila de la tarea 2
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
gdt:
  ;descriptor nulo
  resb 8

 ; descriptor de datos (base 0, size 64k, nivel 0)
dataSel_Lvl0 equ $-gdt ; selector descr segment data --> index = 1, TI = 0, RPL = 00

  dw 0xffff     ; limit low part = 65536 = 64k
  dw 0x0000     ; first 2 bytes set = 0
  db 0x00       ; 3er byte base = 0
  db 10010010b  ; attr:P=1 DPL=00 S=1 TIPO=001 (E=0 data segment, ED=0, W=1 write) A=0 
  db 0x00       ; attr high part = 0
  db 0x00       ; 4to byte base = 0

; descriptor de datos de nivel 3 (Base: 0, size 100h, nivel 0)
dataSel_Lvl3 equ $-gdt ; selector del descriptor de segmento de datos de nivel 3 --> index = 1, TI = 0, RPL = 11 (Niv 3)
  dw 0x00ff     ; limite parte baja = 255 = 0xff --> limite + 1 = 256 = 0x100 = 100h
  dw datos_anillo3 ; otra forma de definir la base, con una etiqueta
  db 0x00       ; 3er byte base = 0
  db 11110010b  ; atributos: P=1 DPL=11 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0 
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; video descriptor (offset: 0xb8000, size 4k, nivel 0)
videoSel_Lvl0 equ $-gdt ; selector descr video segment data --> index = 3, TI = 0, RPL = 00

 dw 0x1000     ; limit low part = 4096 = 4k
 dw 0x8000     ; base = 0xb8000, first 2 bytes set 8000
 db 0x0b       ; 3 byte set b
 db 10010010b  ; attr: P=1 DPL=00 S=1 TIPO=001 (E=0 data segment, ED=0, W=1 write) A=0
 db 0x00       ; attr high part = 0
 db 0x00       ; 4to byte base = 0

; code descriptor (base 0x0000, size 64k, nivel 0) for handler
codeSel_Lvl0 equ $-gdt ; selector descr segment code --> index = 2, TI = 0, RPL = 00
  dw 0xffff	; limit low part = 65536 = 64k
  dw 0x0000	; first 2 bytes base = 0
  db 0x00	; 3er byte base = 0
  db 10011010b	; Attr: P=1 DPL=00 S=1 TIPO=101 (E=1 code segment, C=0, R=1 read and execute) A=0
  db 0x00	; attr high part = 0
  db 0x00	; 4to byte base = 0

; descriptor de codigo de nivel 3 (Base: 0x0000, size 64k, nivel 3), para el codigo de las tareas
codeSel_Lvl3 equ $-gdt + 3  ; Selector con RPL=3 
  dw 0xffff     ; limite parte baja = 65536 = 64k
  dw 0x0000     ; primeros 2 bytes base = 0
  db 0x00       ; 3er byte base = 0
  db 11111010b  ; atributos: P=1 DPL=11 S=1 TIPO=101 (E=1 por lo tanto es segmento de codigo, C=0, R=1 por lo tanto puedo leer y ejecutar) A=0
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; callgate para escribir contador de tarea 1 en parte superior --> El codigo de anillo 3 de la tarea 1 usara estara call gate para ejecutar codigo de niv 0
cgPrintScreenUp equ $-gdt +3 ; Selector con RPL=3  (lo pongo con ese +3)
  dw printScreenUp ; offset
  dw codeSel_Lvl0          ; selector del codigo de nivel 0 al que accede esta call gate
  db 0             
  db 11100100b             ; P=1 ; DPL = 11 ; S = 0 ; TIPO = 0100 (Call Gate 16 bits)
  dw 0

; callgate para limpiar la pantalla (DPL = 3)  --> El codigo de anillo 3 de la tarea 2 usara estara call gate para ejecutar codigo de la tarea de niv 0
cgPrintScreenDown equ $-gdt +3 ; Selector con RPL=3  (lo pongo con ese +3)
  dw printScreenDown ; offset
  dw codeSel_Lvl0          ; selector del codigo de nivel 0 al que accede esta call gate
  db 0             
  db 11100100b             ; P=1 ; DPL = 11 ; S = 0 ; TIPO = 0100 (Call Gate 16 bits)
  dw 0

; descriptor de datos para la pila de nivel 3 de Tarea 1 (Base: pilaTarea1_Niv3, size 100h, nivel 3) 
stackSelT1_Lvl3 equ $-gdt + 3 ; Selector INDEX-TI-RPL con RPL=3 
  dw 0x00ff          ; tamano 100h bytes
  dw stackTask1_Lvl3 ; base de esta pila
  db 0x00
  db 11110010b       ;atributos: P=1 DPL=11 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0
  db 0x00
  db 0x00

; descriptor de datos para la pila de nivel 3 de Tarea 2 (Base: pilaTarea2_Niv3, size 100h, nivel 3) 
stackSelT2_Lvl3 equ $-gdt + 3 ; Selector INDEX-TI-RPL con RPL=3 
  dw 0x00ff          ; tamano 100h bytes
  dw stackTask2_Lvl3 ; base de esta pila
  db 0x00
  db 11110010b       ;atributos: P=1 DPL=11 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0
  db 0x00
  db 0x00

;------ Descriptores de TSS --------
; Todos los selectores van con RPL=0 !! --> todas las TSS van en anillo 0 por mas que ejecuten codigo de otro nivel

tssTaskInit_Lvl0_Sel equ $ -gdt ; selector que se cargara en el registro TR que es el selector del descriptor de TSS de la tarea actual
  dw 67h                  ; Limite o tamaño del descriptor
  dw tssTaskInit_Lvl0 ; Base del descriptor 
  db 0 
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssScheduler_Lvl0_Sel equ $ -gdt
  dw 67h
  dw tssScheduler_Lvl0
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssTaskSerialPort_Lvl0_Sel equ $ -gdt
  dw 67h
  dw tssTaskSerialPort_Lvl0
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssTask1_Lvl3_Sel equ $ -gdt
  dw 67h
  dw tssTask1_Lvl3
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0

tssTask2_Lvl3_Sel equ $ -gdt   
  dw 67h
  dw tssTask2_Lvl3
  db 0
  db 10001001b            ; SIEMPRE CON RPL = DPL = 00
  db 0
  db 0


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
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
  ;Excepcion 1: Debug
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

    resb 8 ; Aca dejo espacio libre pues es la Interrupcion 2
    
  ;Excepcion 3: Breakpoint
    dw excHandler  ; OHandler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 4: Overflow
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 5: Bound Range Exceed
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 6: Invalid Opcode
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
  ;Excepcion 7: Device not available
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 8: Double Fault
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 9: Coproccesor segment overrun
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 10: Invalid TSS
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 11: Segment Not Present
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 12: Stack Segment
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 13: General Protection
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 14: Page Fault
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
    
    resb 8         ; la 15 esta reservada

  ;Excepcion 16: Floating Point Error
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 17: Alignment Check
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 18: Machine Check
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00

  ;Excepcion 19: SIMD Floating Point Exception
    dw excHandler  ; Handler que atiende la excep
    dw codeSel_Lvl0
    db 0
    db 0x87        ; 0x87 = 1000 0111 --> P=1 ; DPL=00 ; S=0 ; TIPO=0111
    dw 0x00
  
  resb 8*13 ; de la 20 a la 31 son reservadas y la 32 es el TimerTick. Son 13 lugares en total.

  ;descriptor de puerta de tarea en 0x20 (irq0, timer tick)
    dw 0
    dw tssScheduler_Lvl0_Sel ; Selector a descriptor de TSS del Scheduler que conmutara con el timertick
    db 0
    db 10000101b    ; Puertas de tarea en este caso va en con DPL = 00
    dw 0x00

  ;PUERTA de interrupcion 0x21 = 33 (int 0x21, irq1, teclado)
    dw irq1Handler ; primeros 2 bytes de offset donde estara el handler a partir de la base del segmento de codigo
    dw codeSel_Lvl0; selector de descriptor de segmento de codigo para ir a la GDT
    db 0           ; bits del 32 al 39 en 0
    db 0x86        ; byte de atributos: P=1 DPL=00 (puede interrumpir cualquier tarea) S=0 (es de sistema) TIPO=0110 (Puerta de int. de 16 bits) 
    dw 0x00        ; ultimos 2 bytes de offset en 0

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

;-------- Reconfiguro Timer para que interrumpa cada 1ms ------------
    ; Para reprogramar el timer tick para que interrumpa cada 1 ms
    ; debo dividir los 1,193180Mhz por la cuenta a cargar en el 8253/4
    ; Por ejemplo: 1mseg1.19e6 / 04a6h (1190) = 1000 ints/s 
    mov ax,04a6h
    out 40h,al ; Parte Baja
    mov al,ah
    out 40h,al ; Parte Alta

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

;cargo en cs el selector de codigo codeSel_Lvl0
jmp codeSel_Lvl0:modo_protegido	;salto largo, guardo en CS el selector de codigo para modo protegido

modo_protegido:
;cargo pila de init task
mov eax, stackTaskInit_Niv0
mov esp, eax

;enmascaro todas las interrupciones 
;menos la irq1 (Teclado)int 21h y irq0 
;(timer tick) disable int 20h (Luego del remapeado quedo asi)   
mov al, 0xfd ; Mascara PIC Master (0x21)   0xfd   1111 1101 (IRQ9) estos 8 bits es el IMR, en 0 la INT que habilito
out 0x21, al
mov al, 0xff ; Mascara PIC Slave (0xff)
out 0xa1, al

;cargo tss init task en TR (current task)
;seria como el proceso padre
mov ax, tssTaskInit_Lvl0_Sel
ltr ax

;Pixeles de pantalla
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
	
;********** CODIGO DEL PROGRAMA**************
  sti	;habilito interrupciones
  jmp $
;********************************************

;Handler del timertick. Conmuto al handler por
;cada INT por una puerta de tarea
irq0Handler:
  ;disable INT
  cli
  ;clear flag INT
  mov al, 20h
  out 0x20, al
  
  xor eax, eax
  mov ax, [ds:count_ticks]
  inc ax
  mov [ds:count_ticks], ax
  cmp ax, TICKS_SERIAL_PORT; 1000mS = 1seg, paso a ptoSerie
  jne verifyTask ;analizar tiempos de tareas
  mov BYTE[ds:count_ticks], 0 ;si es 1000, reseteo count
  ;marco como busy la tarea del pto serie
  mov al, 0x89 ;1000 1001
  mov [gdt + tssTaskSerialPort_Lvl0_Sel + 5], al
  sti ;activo INT
  jmp tssTaskSerialPort_Lvl0_Sel:0
  jmp irq0Handler

verifyTask:
  cmp BYTE[ds:count_ticks], TICKS_LIMIT_TASK1
  jg execTask2 ;si ticks mayor a 500 exec a T2
  ;antes de conmutar a la tarea marco como busy la misma
  mov al, 0x89
  mov [gdt + tssTask1_Lvl3_Sel + 5], al
  jmp tssTask1_Lvl3_Sel:0
  jmp irq0Handler
  sti ;habilito INT

execTask2:
  mov al, 0x89
  mov [gdt + tssTask2_Lvl3_Sel + 5], al
  jmp tssTask2_Lvl3_Sel:0
  jmp irq0Handler
  sti; habilito INT

wait_keypress:
	xor eax, eax
  xor edi, edi ;set offset=0, first character

	mov al, [ds:counter_decenas]
	add al, 0x30		;convert number 1 digit to ASCII 
	mov [es:edi], al	;print decenas
	inc edi		;attr char
	mov al, 0x70		;black char 0111 0000
	mov [es:edi], al
	inc edi ;next char

  mov al, [ds:counter_unidades]
	add al, 0x30		;convert number 1 digit to ASCII 
	mov [es:edi], al	;print unidades
	inc edi		;attr char
	mov al, 0x70		;black char 0111 0000
	mov [es:edi], al

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
    
    ;Ahora muestro mensaje de error
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
  cmp al, 0x24 ;003C (00BD es breakcode) es F2 003D es F3
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

  ;separo en unidades y decenas, divido por 10
  mov bl, 10 ;divido contador por 10
  mov ah, 0
  div bl ;ax/bx
  mov [ds:counter_decenas], al ;cociente 
  mov [ds:counter_unidades], ah ;resto
  
  jmp fin_handler
  
set_key_state:
	mov al, 0
	mov [key_state], al

fin_handler:
    sti
    iret                       ; fin de la interrupcion. interrupt return

;-------------------TAREAS--------------------
Task1_Lvl3:
  ;debo llamar a la callgate porque estoy
  ;en anillo 3 y para pintar pantalla superior debo estar
  ;en anillo 0
  call cgPrintScreenUp:0
  jmp Task1_Lvl3

Task2_Lvl3:
  ;debo llamar a la callgate porque estoy
  ;en anillo 3 y para pintar pantalla inferior debo estar
  ;en anillo 0
  call cgPrintScreenDown:0
  jmp Task2_Lvl3

;------------------------------------------------

printScreenUp:
  ;Cuando entro a código de nivel 0 mediante la call gate, lo primero que tengo que hacer es cargar los selectores de nivel 0 en DS, ES, 
  ;pues yo venia de nivel 3
  mov ax, dataSel_Lvl0
  mov ds, ax
  mov ax, videoSel_Lvl0
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

printScreenDown:
  ;Cuando entro a código de nivel 0 mediante la call gate, lo primero que tengo que hacer es cargar los selectores de nivel 0 en DS, ES, 
  ;pues yo venia de nivel 3 
  mov ax, dataSel_Lvl0
  mov ds, ax
  mov ax, videoSel_Lvl0
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

;---------------------------------------------------------------------------------------------------------------------------------------

serialPortHandler:
  wait1:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait1            ; Si no está vacío, esperar
  ;mov al, [ds:contadorDecenaT1]
  mov al, 1
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  wait2:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait2            ; Si no está vacío, esperar
  ;mov al, [ds:contadorUnidadT1]
  mov al, 5
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  wait3:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait3            ; Si no está vacío, esperar
  mov al, 6
  ;mov al, [ds:contadorDecenaT2]
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  wait4:
  mov dx, 0x3FD  
  in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
  test al, 0x20       ; ¿Está vacío el THR? (bit 5)
  jz wait4            ; Si no está vacío, esperar
  mov al, 4
  ;mov al, [ds:contadorUnidadT2]
  add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov dx, 0x3f8
  out dx, al
  jmp serialPortHandler

;---------------------------------------------------------------------------------------------------------------------------------------

fin:            

; 100h mas adelante configuro el ESP de la pila. 
 
;------------------------------------------
; ESPACIOS PARA PILAS Y SEGMENTOS DE DATOS
;------------------------------------------
stackTaskInit_Niv0:   ; pila de tarea inicial
resb 100h

stackSch_Niv0:            ; PILA SCH
resb 100h

stackSerialPort_Niv0:         ;PILA PTO SERIE
resb 100h

stackTask1_Niv0:         ; Tarea Print Pantalla (Anillo 3 // call gate accede a Anillo 0)
resb 100h

stackTask2_Niv0:         ; Tarea Print Pantalla (Anillo 3 // call gate accede a Anillo 0)
resb 100h

;Segmento de datos Anillo 3
datos_anillo3:
resb 100h

;Pila Tarea 1 Anillo 3
stackTask1_Lvl3:
resb 100h

;Pila Tarea 2 Anillo 3
stackTask2_Lvl3:
resb 100h
 
