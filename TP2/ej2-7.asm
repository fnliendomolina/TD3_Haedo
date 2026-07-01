;*******************************************************
;Ej 2-7
;Tome el programa del Ejercicio 2.5 o del Ejercicio 2.6 (elija el que prefiera), y modifíquelo para que ambas tareas ejecuten, en un segmento de RPL = 11.
;Las tareas dejarán de presentar su tiempo de ejecución y mediante el acceso a dos servicios (Fecha y Hora) implementados en el segmento de código de RPL = 00, accediendo directamente al Real Time Clock de la PC. Las tareas presentarán:
;Tarea 1: Periódicamente, presenta la Hora del Sistema en la posición de pantalla Fila 8 Columna 35, en el formato hh:mm:ss.
;Tarea 2: Periódicamente, presenta Fecha y Hora del Sistema en la posición de pantalla Fila 16 Columna 35 en formato dd:mm:aaaaa y en Fila 17 Columna 35 en formato hh:mm:ss. Ídem Servicio Hora del Sistema.
;Tarea 3: Envía cada 1 segundo por puerto serie la hora del sistema.
;Las tareas, descriptas se seguirán ejecutando de acuerdo al esquema de manejo de prioridades establecido en el Ejercicio 2.5 o en el Ejercicio 2.6 según haya sido su elección.
;El programa finaliza cuando se pulsa la tecla F10, o cuando alguna de las dos tareas llega a los 3 minutos de operación efectiva.
;Recuerde que HLT es una instrucción privilegiada, por lo que este comando se debe ejecutar desde una rutina que corra en anillo 0.
;*******************************************************

use16 ;codigo 16 bits
org 8000h ;offset del codigo en 0x8000
jmp inicio ;voy a inicio (salteo variables)

tick50                 equ       5 ;config base ticks
MAX_TIME_EXEC_TASK     equ       180 ;180seg = 3min. Tiempo maximo de tarea.
TIME_EXEC_SERIAL_PORT  equ       1000 ;1000mSeg = 1seg. Tiempo para ejecutar tarea pto. serie.
COLOR_BG               equ       0x60
COLOR_BG_EXCEPTION     equ       0x11

;***********************************
;	variables
;***********************************
gdtr	                   resb	     6
idtr 	                   resb      6
keyPressState                 db        0
counterTicksTask1        db	       0 ; para almacenar contador de ticks de la tarea 1
counterTicksTask2        db        0 ; para almacenar contador de ticks de la tarea 2
timeSerialPort           dw        0 ; para almacenar contador de tiempo de la tarea de puerto serie (cada 1s)
ticksMaxTask1            db        tick50 ; para almacenar el porcentaje de tiempo que debe conmutar a Tarea 1, inicialmente arranca en 50%
ticksMaxTask2            db        tick50 ; para almacenar el porcentaje de tiempo que debe conmutar a Tarea 2, inicialmente arranca en 50%
timeMilsTask1            dw        0 ; para almacenar milesimas de segundo de tiempo tarea 1
timeMilsTask2            dw        0 ; para almacenar milesimas de segundo de tiempo tarea 2
timeMaxTask1             dw        0 ; para almacenar tiempo maximo en segundos de tarea 1 (180s)
timeMaxTask2             dw        0 ; para almacenar tiempo maximo en segundos de tarea 2 (180s)
msgException             db        'A fatal exception DE has occurred. The current application will be terminated.'
endOfString              db        0 ; Null, fin del string a imprimir

secondsRTC               db        0 ;
unitSeconds              db        0 ; 
tenSeconds               db        0 ; 

minutesRTC               db        0 ;
unitMinutes              db        0 ; 
tenMinutes               db        0 ; 

hourRTC                  db        0 ;
unitHour                 db        0 ; 
tenHour                  db        0 ;

dayRTC                   db        0 ; 
unitDay                  db        0 ; 
tenDays                  db        0 ; 

monthRTC                 db        0 ;
unitMonth                db        0 ; 
tenMonth                 db        0 ; 

yearRTC                  dw        0 ;
unitYear                 db        0 ; 
tenYear                  db        0 ;
hundredYear              db        0 ;
milsYear                 db        2 ; 

;***********************************
; Scan Codes de los Make de teclas
;***********************************
KEY_J_MakeCode         equ       0x24
KEY_W_MakeCode         equ       0x11 ;se cambiaron F2,F3 y F10 por problema con teclado de laptop
KEY_E_MakeCode         equ       0x12
KEY_Q_MakeCode         equ       0x10

;***********************************
; TSS
;***********************************
;tss de la tarea inicial
tssTaskInit_Lvl0  resb 68h ; reservo 68 hexabytes sin nada por ser la tarea inicial

;tss del Scheduler --> Es de Nivel 0 
tssScheduler_Lvl0 dd 0
    dd 0                 ;esp0 
    dw 0                 ;ss0
    dw 0
    dd 0                 ;esp1 (dd: define double --> 32 bits) --> no necesito pila de anillo 1, pues estoy en anillo 0
    dd 0                 ;ss1 
    dd 0                 ;esp2 --> no necesito pila de anillo 2, pues estoy en anillo 0
    dd 0                 ;ss2
    dd 0                 ;cr3
    dd irq0Handler       ;eip --> Instruction Pointer --> debera arrancar en irq0Handler al conmutar
    dd 0x202             ;eflags --> habilita Flag de interrupcion
    dd 0                 ;eax
    dd 0                 ;ecx
    dd 0                 ;edx
    dd 0                 ;ebx
    dd stackSch_Lvl0+0xff ;esp  --> La pila se configura con ss:esp --> dataSel0:pilaSchNiv0+0xff (de 0 a 99 (ff) y luego al final reserva 100h)
    dd 0                 ;ebp
    dd 0                 ;esi
    dd 0                 ;edi
    dw 0                 ;es --> no pongo videoSel pues el Scheduler no pintara la pantalla, lo hara el codigo de la call gate
    dw 0
    dw codeSel_Lvl0      ;cs
    dw 0
    dw dataSel_Lvl0      ;ss
    dw 0
    dw dataSel_Lvl0      ;ds --> lo usare para las variables 
    dw 0 
    dd 0                 ;fs
    dd 0                 ;gs
    dd 0
    dd 0

;tss de la tara que envia al puerto serie --> Es de Nivel 0 
tssTaskSerialPort_Lvl0 dd 0
    dd 0        ;esp0 
    dw 0        ;ss0
    dw 0
    dd 0        ;esp1 (dd: define double --> 32 bits) --> no necesito pila de anillo 1, pues estoy en anillo 0
    dd 0        ;ss1 
    dd 0        ;esp2 --> no necesito pila de anillo 2, pues estoy en anillo 0
    dd 0        ;ss2
    dd 0        ;cr3
    dd serialPortHandler  ;eip --> Instruction Pointer --> debera arrancar en irq0Handler al conmutar
    dd 0x202    ;eflags --> habilita Flag de interrupcion
    dd 0        ;eax
    dd 0        ;ecx
    dd 0        ;edx
    dd 0        ;ebx
    dd stackSerialPort_Lvl0+0xff ;esp  --> 
    dd 0        ;ebp
    dd 0        ;esi
    dd 0        ;edi
    dw 0        ;es 
    dw 0
    dw codeSel_Lvl0 ;cs
    dw 0
    dw dataSel_Lvl0 ;ss
    dw 0
    dw dataSel_Lvl0 ;ds --> lo usare para las variables 
    dw 0 
    dd 0        ;fs
    dd 0        ;gs
    dd 0
    dd 0

;tss de la tarea 1 (anillo 3) --> Debo configurar pilas de nivel 0 y 3. Por medio de CG va a anillo 0.
tssTask1_Lvl3 dd 0
    dd stackTask1_Lvl0+0xff     ;esp0 --> aca pongo la pila de nivel 0
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
    dd 0xff    ;esp --> aca pongo la pila de nivel 3 propia de esta tarea: SS:ESP --> pilaSel_Niv3:0xff
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

;tss de la tarea 2 (anillo 3) --> Debo configurar pilas de nivel 0 y 3. Por medio de CG va a anillo 0.
tssTask2_Lvl3 dd 0
    dd stackTask2_Lvl0+0xff   ;esp0 --> aca pongo la pila de nivel 0
    dw dataSel_Lvl0           ;ss0
    dw 0
    dd 0                      ;esp1
    dd 0                      ;ss1
    dd 0                      ;esp2
    dd 0                      ;ss2
    dd 0                      ;cr3
    dd Task2_Lvl3            ;eip
    dd 0x202                  ;eflags
    dd 0                      ;eax
    dd 0                      ;ecx
    dd 0                      ;edx
    dd 0                      ;ebx
    dd 0xff                   ;esp --> aca pongo la pila de nivel 3 propia de esta tarea: SS:ESP --> pilaSel_Niv3:0xff
    dd 0                      ;ebp
    dd 0                      ;esi
    dd 0                      ;edi
    dw 0                      ;es
    dw 0
    dw codeSel_Lvl3           ;cs
    dw 0
    dw stackSelT2_Lvl3         ;ss --> Selector del descriptor de datos de la pila de la tarea 2
    dw 0
    dw dataSel_Lvl3           ;ds --> no uso DS en la tarea de anillo 3 pues solo llama a la call gate de anillo 0, por lo tanto no usa datos niv3
    dw 0 
    dd 0                      ;fs
    dd 0                      ;gs
    dd 0
    dd 0 

;***********************************
;	GDT
;***********************************
gdt: ; direccion base de la gdt
  resb 8 ;descriptor nulo

; descriptor de datos de nivel 0 (Base: 0, size 64k, nivel 0)
dataSel_Lvl0 equ $-gdt ; selector del descriptor de segmento de datos de nivel 0 --> index = 1, TI = 0, RPL = 00 (Niv 0)
  dw 0xffff     ; limite parte baja = 65536 = 64k
  dw 0x0000     ; primeros 2 bytes base = 0
  db 0x00       ; 3er byte base = 0
  db 10010010b  ; atributos: P=1 DPL=00 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0 
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; descriptor de datos de nivel 3 (Base: 0, size 100h, nivel 0)
dataSel_Lvl3 equ $-gdt ; selector del descriptor de segmento de datos de nivel 3 --> index = 2, TI = 0, RPL = 11 (Niv 3)
  dw 0x00ff     ; limite parte baja = 255 = 0xff --> limite + 1 = 256 = 0x100 = 100h
  dw data_anillo3 ; otra forma de definir la base, con una etiqueta
  db 0x00       ; 3er byte base = 0
  db 11110010b  ; atributos: P=1 DPL=11 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0 
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; descriptor de video (Base: 0xb8000, size 4k, nivel 0)
videoSel_Lvl0 equ $-gdt ; selector del descriptor de segmento de datos de video de nivel 0 --> index = 3, TI = 0, RPL = 00
  dw 0x1000     ; limite parte baja = 4096 = 4k
  dw 0x8000     ; base = 0xb8000, en los primeros 2 bytes pongo 8000
  db 0x0b       ; en el 3er byte pongo b
  db 10010010b  ; atributos: P=1 DPL=00 S=1 TIṔO=001 (E=0 por lo tanto es segmento de datos, ED=0, W=1 por lo tanto puedo escribir) A=0
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

; descriptor de codigo de nivel 0 (Base: 0x0000, size 64k, nivel 0) para el handler de IRQ0
codeSel_Lvl0 equ $-gdt ; selector del descriptor de segmento de codigo --> index = 4, TI = 0, RPL = 00
  dw 0xffff     ; limite parte baja = 65536 = 64k
  dw 0x0000     ; primeros 2 bytes base = 0
  db 0x00       ; 3er byte base = 0
  db 10011010b  ; atributos: P=1 DPL=00 S=1 TIPO=101 (E=1 por lo tanto es segmento de codigo, C=0, R=1 por lo tanto puedo leer y ejecutar) A=0
  db 0x00       ; parte alta atributos = 0
  db 0x00       ; 4to byte base = 0

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
; Todos los selectores van con RPL=0 !! --> TSS siempre en anillo 0

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

;-------- Reconfiguro Timer para que interrumpa cada 1ms ------------
  ; Para reprogramar el timer tick para que interrumpa cada 1 ms
  ; debo dividir los 1,193180Mhz por la cuenta a cargar en el 8253/4
  ; Por ejemplo: 1mseg1.19e6 / 04a6h (1190) = 1000 ints/s 
  mov ax,04a6h
  out 40h,al ; Parte Baja
  mov al,ah
  out 40h,al ; Parte Alta

;-------- Habilito binario en el RTC (bit 2 del registro B) --------
  ; Paso 1: Selecciono el registro B
  mov al, 0x0B
  out 70h, al
  in al, 71h          ; Leo el valor actual del registro B
  mov bl, al          ; Lo guardo en BL
  ; Paso 2: Seteo el bit 2 (DM = 1) para binario
  or bl, 00000100b    ; BL = BL | 0x04
  ; Paso 3: Vuelvo a escribir el registro B con el bit 2 activado
  mov al, 0x0B
  out 70h, al
  mov al, bl
  out 71h, al

;-------------------------------------------------------------------

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
  mov ax, dataSel_Lvl0
  mov ss, ax
  mov ds, ax
  mov ax, videoSel_Lvl0
  mov es, ax

  ;cargo en cs el selector de codigo codeSel0_Niv0
  jmp codeSel_Lvl0:modo_protegido

modo_protegido:
  ;apunto esp al final del codigo + 0x100
  mov eax, stackTaskInit_Lvl0            ; Pila de la tarea inicial
  mov esp, eax

  ;enmascaro todas las interrupciones menos la irq1 (Teclado)int 21h y irq0 (timer tick) disable int 20h (Luego del remapeado quedo asi)                                           
  mov al, 0xfc   ; Mascara PIC Master   0xfc   1111 1100 --> osea la IRQ1 es el 2do bit, la IRQ0 el primer bit, poniendo en 0 la habilito
  out 0x21, al   ; 0x21 es la direccion del registro de enmascaramiento del PIC Master
  mov al, 0xff   ; Mascara PIC Slave, ponemos todo en 1, osea deshabilito todas sus interrupciones pues no las uso
  out 0xa1, al   ; 0xA1 es la direccion del registro de enmascaramiento del PIC Slave

  ;cargo tss inicial --> lo cargo en tr
  mov ax, tssTaskInit_Lvl0_Sel
  ltr ax

  ;Primero pinto toda la pantalla de blanco (video inverso):
  mov cx, 80*25     ;cargo cantidad de puntos en pantalla a pintar
  mov edi, 0x00     ;cargo edi en 0 porque ahora tambien borrare los caracteres, por lo tanto me movere por todos los bytes de la pantalla
  bucle_pantalla: ; pinta toda la pantalla de blanco
  mov al, 0x00     ;poniendo el byte de caracter todo en 0 borra el caracter
  mov [es:edi], al ;borro caracter 
  inc edi          ;incremento edi para pasar al atributo
  mov al, COLOR_BG     ;cargo valor del atributo para poner cada caracter en blanco y fondo en blanco --> 0 111 | 0 111
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

  ;Me fijo si alguna de las tareas llego a su tiempo maximo (180s) y cuelgo el programa con HLT
  mov al,[ds:timeMaxTask1]
  cmp al,MAX_TIME_EXEC_TASK ; 180s son 3 minutos, el maximo que pide la consigna
  jne continueProgram
  hlt 
  continueProgram:
  mov al,[ds:timeMaxTask2]
  cmp al,MAX_TIME_EXEC_TASK ; 180s son 3 minutos, el maximo que pide la consigna

  ;Aumento contador de tiempo para tarea de puerto serie
  xor eax,eax
  mov ax,[ds:timeSerialPort]
  inc ax
  mov [ds:timeSerialPort],ax
  cmp ax,TIME_EXEC_SERIAL_PORT ;Si paso 1s = 1000ms --> Conmuto a serialPortHandler
  jne continue
  mov WORD[ds:timeSerialPort], 0 ; Reseteo timeSerialPort
  ;bajo busy flag de la tarea de nivel 0 (a llamar)
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTaskSerialPort_Lvl0_Sel + 5], al
  sti
  jmp tssTaskSerialPort_Lvl0_Sel:0
  jmp irq0Handler

  continue:
  ;si ticksMaxTask1 = 0 --> solo ejecuto T2
  mov al,[ds:ticksMaxTask1]
  cmp al,0
  je execOnlyTask2
  ;si ticksMaxTask2 = 0 --> solo ejecuto T1
  mov al,[ds:ticksMaxTask2]
  cmp al,0
  je execOnlyTask1
  ;si counterTicksTask1 no llego al maximo, aumento su tiempo y aumento counterTicksTask1 y conmuto a tarea1
  mov al,[ds:counterTicksTask1]
  cmp al,BYTE[ds:ticksMaxTask1]
  jne execTask1 
  ;Si son iguales sigue por aca
  ;Si counterTicksTask2 no llego al maximo, aumento su tiempo y aumento counterTicksTask1 y conmuto a tarea2
  mov al,[ds:counterTicksTask2]
  cmp al,BYTE[ds:ticksMaxTask2]
  jne execTask2
  ;Si son iguales sigue por aca, reseteo counterTicksTask1 y counterTicksTask2
  mov BYTE[ds:counterTicksTask1], 0 ;reseteo counterTicksTask1
  mov BYTE[ds:counterTicksTask2], 0 ;reseteo counterTicksTask2
  ;Vuelvo al inicio
  jmp irq0Handler

execOnlyTask2:
  ;aumento contador de tiempo de milesimas acumulado de tarea2
  xor eax,eax
  mov ax, [ds:timeMilsTask2] 
  inc ax ;
  mov [ds:timeMilsTask2], ax
  cmp ax, 1000
  ;si el contador de centesimas llega a 1000 lo reseteo y aumento el contador de tiempo de tarea 2
  jne noLlegoA100_a
  mov WORD[ds:timeMilsTask2], 0 ; Reseteo timeMilsTask2
  xor eax,eax
  mov ax, [ds:timeMaxTask2] 
  inc ax ;
  mov [ds:timeMaxTask2],ax
noLlegoA100_a: ;Conmuto a Tarea 2
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTask2_Lvl3_Sel + 5], al ; Reseteo Bit Busy Tarea 1
  sti ;habilito las interrupciones
  jmp tssTask2_Lvl3_Sel:0
  jmp irq0Handler

execOnlyTask1:
  ;aumento contador de tiempo de milesimas acumulado de tarea1
  xor eax,eax
  mov ax, [ds:timeMilsTask1] 
  inc ax ;
  mov [ds:timeMilsTask1], ax
  cmp ax, 1000
  ;si el contador de centesimas llega a 1000 lo reseteo y aumento el contador de tiempo de tarea 1
  jne noLlegoA100_b
  mov WORD[ds:timeMilsTask1], 0 ; Reseteo timeMilsTask1
  xor eax,eax
  mov ax, [ds:timeMaxTask1] 
  inc ax ;
  mov [ds:timeMaxTask1],ax
  noLlegoA100_b: ;Conmuto a Tarea 1
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTask1_Lvl3_Sel + 5], al ; Reseteo Bit Busy Tarea 1
  sti ;habilito las interrupciones
  jmp tssTask1_Lvl3_Sel:0
  jmp irq0Handler

execTask1:
  ;aumento contador de tiempo de milesimas acumulado de tarea1
  xor eax,eax
  mov ax, [ds:timeMilsTask1] 
  inc ax ;
  mov [ds:timeMilsTask1], ax
  cmp ax, 1000
  ;si el contador de centesimas llega a 1000 lo reseteo y aumento el contador de tiempo de tarea 1
  jne noLlegoA100_c
  mov WORD[ds:timeMilsTask1], 0 ; Reseteo timeMilsTask1
  xor eax,eax
  mov ax, [ds:timeMaxTask1] 
  inc ax ;
  mov [ds:timeMaxTask1],ax
noLlegoA100_c: ;Aumento counterTicksTask1 y conmuto a Tarea 1
  mov al, [ds:counterTicksTask1] 
  inc al ;
  mov [ds:counterTicksTask1], al
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTask1_Lvl3_Sel + 5], al ; Reseteo Bit Busy Tarea 1
  sti ;habilito las interrupciones
  jmp tssTask1_Lvl3_Sel:0
  jmp irq0Handler

execTask2:
  ;aumento contador de tiempo de milesimas acumulado de tarea2
  xor eax,eax
  mov ax, [ds:timeMilsTask2] 
  inc ax ;
  mov [ds:timeMilsTask2], ax
  cmp ax, 1000
  ;si el contador de centesimas llega a 100 lo reseteo y aumento el contador de tiempo de tarea 1
  jne noLlegoA100_d
  mov WORD[ds:timeMilsTask2], 0 ; Reseteo tiempoCentesimasTarea1
  xor eax,eax
  mov ax, [ds:timeMaxTask2] 
  inc ax ;
  mov [ds:timeMaxTask2],ax
noLlegoA100_d: ;Aumento counterTicksTask1 y conmuto a Tarea 1
  mov al, [ds:counterTicksTask2] 
  inc al ;
  mov [ds:counterTicksTask2], al
  mov al, 0x89  ;   1000 1001
  mov [gdt + tssTask2_Lvl3_Sel + 5], al ; Reseteo Bit Busy Tarea 1
  sti ;habilito las interrupciones
  jmp tssTask2_Lvl3_Sel:0
  jmp irq0Handler
;---------------------------------------------------------------------------------------------------------------------------------------

serialPortHandler:
  wait1:
    mov dx, 0x3FD  
    in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
    test al, 0x20       ; ¿Está vacío el THR? (bit 5)
    jz wait1            ; Si no está vacío, esperar
    mov al, [ds:tenHour]
    add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
    mov dx, 0x3f8
    out dx, al
  wait2:
    mov dx, 0x3FD  
    in al, dx           ; Leo Line Status Register, para ver si el buffer del puerto serie esta libre
    test al, 0x20       ; ¿Está vacío el THR? (bit 5)
    jz wait2            ; Si no está vacío, esperar
    mov al, [ds:unitHour]
    add al, 0x30        ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
    mov dx, 0x3f8
    out dx, al
    jmp serialPortHandler

;---------------------------------------------------------------------------------------------------------------------------------------

Task1_Lvl3:  
  ;llamo a la callgate de la tarea 1
  call cgPrintScreenUp:0  ; con esto ejecuto codigo de nivel 0 --> cgPrintPantalla es el selector de la callgate, que es el descriptor que accede
                                  ; a la memoria donde esta el codigo printPantalla, que esto se hace en anillo 0 ya que pinta la pantalla y su memoria
                                  ; la pusimos en anillo 0
  jmp Task1_Lvl3

;---------------------------------------------------------------------------------------------------------------------------------------

Task2_Lvl3:  
  ;llamo a la callgate de la tarea 2
  call cgPrintScreenDown:0  ; con esto ejecuto codigo de nivel 0 --> cgPrintPantalla es el selector de la callgate, que es el descriptor que accede
                                  ; a la memoria donde esta el codigo printPantalla, que esto se hace en anillo 0 ya que pinta la pantalla y su memoria
                                  ; la pusimos en anillo 0
  jmp Task2_Lvl3

;---------------------------------------------------------------------------------------------------------------------------------------

printScreenUp:
  ;Cuando entro a código de nivel 0 mediante la call gate, lo primero que tengo que hacer es cargar los selectores de nivel 0 en DS, ES, 
  ;pues yo venia de nivel 3
  mov ax, dataSel_Lvl0
  mov ds, ax
  mov ax, videoSel_Lvl0
  mov es, ax

  ;Leo segundos del RTC
  mov al,0x00 ; 0x00 es el registro del MC146818 que tiene los segundos
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h los segundos
  in al,71h   ; Leo lo que hay en el 71h, osea los segundos, y lo guardo en al, luego los guardo en secondsRTC
  mov [ds:secondsRTC],al

  ;Leo minutos del RTC
  mov al,0x02 ; 0x02 es el registro del MC146818 que tiene los minutos
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h los minutos
  in al,71h   ; Leo lo que hay en el 71h, osea los minutos, y lo guardo en al, luego los guardo en minutesRTC
  mov [ds:minutesRTC],al

  ;Leo hora del RTC
  mov al,0x04 ; 0x04 es el registro del MC146818 que tiene la hora
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h la hora
  in al,71h   ; Leo lo que hay en el 71h, osea la hora, y lo guardo en al, luego los guardo en hourRTC
  mov [ds:hourRTC],al

  ;Logica para separar en decenas y unidades los segundos
  xor ax,ax
  mov al,[ds:secondsRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenSeconds], al
  mov [ds:unitSeconds], dl

  ;Logica para separar en decenas y unidades los minutos
  xor ax,ax
  mov al,[ds:minutesRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenMinutes], al
  mov [ds:unitMinutes], dl

  ;Logica para separar en decenas y unidades la hora
  xor ax,ax
  mov al,[ds:hourRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenHour], al
  mov [ds:unitHour], dl

  ;Logica para imprimir hh:mm:ss
  xor eax,eax
  xor edi,edi            ;reseteo edi para que vaya superponiendo el contador a imprimir
  add edi,70*17          ;llevo el puntero a la posicion pedida --> Fila 8, Columna 35
  ;Imprimo decena hora
  mov al, [ds:tenHour]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad hora
  ;Imprimo unidad hora
  mov al, [ds:unitHour]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de :

 ;Imprimo :
  mov al, 0x3A           ;0x3A es el ASCII de :
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de decena minutos

  ;Imprimo decena minutos
  mov al, [ds:tenMinutes]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad minutos
  ;Imprimo unidad minutos
  mov al, [ds:unitMinutes]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de :

 ;Imprimo :
  mov al, 0x3A           ;0x3A es el ASCII de :
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de decena segundos

  ;Imprimo decena segundos
  mov al, [ds:tenSeconds]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad segundos
  ;Imprimo unidad segundos
  mov al, [ds:unitSeconds]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
 
  inc edi
  inc edi 
  inc edi

  ;Imprimo ticksMax por tarea1, para ver que prioridad tiene
  mov al, [ds:ticksMaxTask1]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al

  retf

;---------------------------------------------------------------------------------------------------------------------------------------

printScreenDown:
  ;Cuando entro a código de nivel 0 mediante la call gate, lo primero que tengo que hacer es cargar los selectores de nivel 0 en DS, ES, 
  ;pues yo venia de nivel 3 
  mov ax, dataSel_Lvl0
  mov ds, ax
  mov ax, videoSel_Lvl0
  mov es, ax

  ;Leo segundos del RTC
  mov al,0x00 ; 0x00 es el registro del MC146818 que tiene los segundos
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h los segundos
  in al,71h   ; Leo lo que hay en el 71h, osea los segundos, y lo guardo en al, luego los guardo en segundosRTC
  mov [ds:secondsRTC],al

  ;Leo minutos del RTC
  mov al,0x02 ; 0x02 es el registro del MC146818 que tiene los minutos
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h los minutos
  in al,71h   ; Leo lo que hay en el 71h, osea los minutos, y lo guardo en al, luego los guardo en minutesRTC
  mov [ds:minutesRTC],al

  ;Leo hora del RTC
  mov al,0x04 ; 0x04 es el registro del MC146818 que tiene la hora
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h la hora
  in al,71h   ; Leo lo que hay en el 71h, osea la hora, y lo guardo en al, luego los guardo en hourRTC
  mov [ds:hourRTC],al

  ;Leo año del RTC --> el año esta en 2 digitos
  mov al,0x09 ; 0x09 es el registro del MC146818 que tiene el año
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h los el año
  in al,71h   ; Leo lo que hay en el 71h, osea el año, y lo guardo en al, luego los guardo en añoRTC
  mov [ds:yearRTC],al

  ;Leo mes del RTC
  mov al,0x08 ; 0x08 es el registro del MC146818 que tiene el mes
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h el mes
  in al,71h   ; Leo lo que hay en el 71h, osea el mes, y lo guardo en al, luego los guardo en monthRTC
  mov [ds:monthRTC],al

  ;Leo dia del RTC
  mov al,0x07 ; 0x07 es el registro del MC146818 que tiene el dia
  out 70h,al  ; Con esto va al puerto de E/S 70h y carga en el 71h el dia
  in al,71h   ; Leo lo que hay en el 71h, osea el dia, y lo guardo en al, luego los guardo en dayRTC
  mov [ds:dayRTC],al

  ;Logica para separar en decenas y unidades los segundos
  xor ax,ax
  mov al,[ds:secondsRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenSeconds], al
  mov [ds:unitSeconds], dl

  ;Logica para separar en decenas y unidades los minutos
  xor ax,ax
  mov al,[ds:minutesRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenMinutes], al
  mov [ds:unitMinutes], dl

  ;Logica para separar en decenas y unidades la hora
  xor ax,ax
  mov al,[ds:hourRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenHour], al
  mov [ds:unitHour], dl

  ;Logica para separar en decenas y unidades el dia
  xor ax,ax
  mov al,[ds:dayRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenDays], al
  mov [ds:unitDay], dl

  ;Logica para separar en decenas y unidades el mes
  xor ax,ax
  mov al,[ds:monthRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenMonth], al
  mov [ds:unitMonth], dl

  ;Logica para separar en decenas y unidades el año
  xor ax,ax
  mov al,[ds:yearRTC]    
  xor dx, dx
  mov bx, 10
  div bx        ; DX:AX / 10
                ; Ax = cociente (decena), DX = resto (unidad)
  mov [ds:tenYear], al
  mov [ds:unitYear], dl

  ;Logica para imprimir hh:mm:ss
  ;                     dd:mm:aaaa
  xor eax,eax
  xor edi,edi            ;reseteo edi para que vaya superponiendo el contador a imprimir
  add edi,70*33          ;llevo el puntero a la posicion pedida --> Fila 16, Columna 35
  ;Imprimo decena hora
  mov al, [ds:tenHour]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad hora
  ;Imprimo unidad hora
  mov al, [ds:unitHour]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter :

 ;Imprimo :
  mov al, 0x3A           ;0x3A es el ASCII de :
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de decena minutos

  ;Imprimo decena minutos
  mov al, [ds:tenMinutes]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad minutos
  ;Imprimo unidad minutos
  mov al, [ds:unitMinutes]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter :

 ;Imprimo :
  mov al, 0x3A           ;0x3A es el ASCII de :
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de decena segundos

  ;Imprimo decena segundos
  mov al, [ds:tenSeconds]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad segundos
  ;Imprimo unidad minutos
  mov al, [ds:unitSeconds]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
 
  inc edi
  inc edi 
  inc edi

  ;Imprimo ticksMax por tarea2, para ver que prioridad tiene
  mov al, [ds:ticksMaxTask2]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al

  ;Paso a la fila 17 columna 35
  xor eax,eax
  xor edi,edi            ;reseteo edi para que vaya superponiendo el contador a imprimir
  add edi,70*35          ;llevo el puntero a la posicion pedida --> Fila 17, Columna 35
  add edi,20

  ;Imprimo decena dia
  mov al, [ds:tenDays]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad dia
  ;Imprimo unidad dia
  mov al, [ds:unitDay]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter :

 ;Imprimo :
  mov al, 0x3A           ;0x3A es el ASCII de :
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de decena mes

  ;Imprimo decena mes
  mov al, [ds:tenMonth]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad mes
  ;Imprimo unidad mes
  mov al, [ds:unitMonth]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de :

 ;Imprimo :
  mov al, 0x3A           ;0x3A es el ASCII de :
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad de mil de años

  ;Imprimo unidad de mil del año
  mov al, [ds:milsYear]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo decena 
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de centena año
  ;Imprimo centena año
  mov al, [ds:hundredYear]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de decena año
  ;Imprimo decena año
  mov al, [ds:tenYear]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
  inc edi                ;paso al byte de atributos 
  mov al, 0x70           ;para que el caracter a mostrar se vea de color negro
  mov [es:edi], al
  inc edi                ;paso a caracter de unidad año
  ;Imprimo unidad año
  mov al, [ds:unitYear]
  add al, 0x30           ;al sumarle 0x30 = 48 a un numero en decimal, obtengo su valor en ascii
  mov [es:edi], al       ;imprimo unidad
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
    cmp al, KEY_J_MakeCode  ; Si se pulso la tecla J no salta 
    jne no_j         ; Si no se pulso la j, al sera distinto a 0x24 por lo tanto salta a no_es_la_jota y sigue

    ;si se pulso la jota no salta, hago algo que genere una excepcion, como por ejemplo dividir por 0
    ;Cuando divido por un registro de 32 bits (EXC), el par de registros EAX:EDX (número de 64 bits) se divide por este registro (EXC). Por lo tanto, debo poner a  cero el registro EAX y colocar el dividendo en EDX
    xor eax, eax ; pongo en 0 eax
    mov edx, 1   ; pongo el dividendo (cualquiera) en edx, en este caso 1
    mov ecx, 0   ; pongo el divisor 0, en edx
    div ecx      ; hace eax:edx dividido exc, osea algo dividido 0, debe generar la excepcion de dividir por 0

    no_j:
      xor ebx, ebx ; limpio registro ebx
      ;si keyPressState es 1 es porque ya pulse, por lo tanto cuando vuelva a entrar aca es porque solte y no aumento contador
      mov bl, [ds:keyPressState]
      cmp bl, 0
      jne reset_keyPressState ;si keyPressState es 0, por lo tanto sigue
                              ;si keyPressState es 1, es porque ya solte, por lo tanto salta y resetea estado tecla
                             
      ;pone en 1 keyPressState y analiza si se presiona W, E o Q
      mov bl, 1
      mov [keyPressState], bl
      cmp al, KEY_W_MakeCode  ; Si se pulso la tecla W 
      je pressW       
      cmp al, KEY_E_MakeCode  ; Si se pulso la tecla E
      je pressE  
      cmp al, KEY_Q_MakeCode ; Si se pulso la tecla Q
      jne fin_handler   

      ;Logica si pulse Q --> Pinto pantalla de blanco y hago HLT
      ;Primero pinto toda la pantalla de blanco (video inverso):
      mov cx, 80*25     ;cargo cantidad de puntos en pantalla a pintar
      mov edi, 0x00     ;cargo edi en 0 porque ahora tambien borrare los caracteres, por lo tanto me movere por todos los bytes de la pantalla
    bucle_pantalla2: ; pinta toda la pantalla de blanco
      mov al, 0x00     ;poniendo el byte de caracter todo en 0 borra el caracter
      mov [es:edi], al ;borro caracter 
      inc edi          ;incremento edi para pasar al atributo
      mov al, COLOR_BG     ;cargo valor del atributo para poner cada caracter en blanco y fondo en blanco --> 0 111 | 0 111
      mov [es:edi], al 
      inc edi          ;incremento edi para pasar al otro caracter
      ;ciclo hasta terminar de recorrer el buffer de video
    loop bucle_pantalla2 ; loop usa al registro cx: decrementa cx. Si cx vale mas que 0, salta a la etiqueta indicada
    
    hlt 

    pressW: ;logica si pulse W --> aumento 10% prioridad de tarea A y disminuyo 10% prioridad de tarea B
      ;si ticksMaxTask2 = 0 no sigo decrementandolo
      mov al,[ds:ticksMaxTask2]
      cmp al,0
      je fin_handler
      ;si ticksMaxTask2 todavia no es 0, aumento en 1 ticksMaxTarea1 y disminuyo en 1 ticksMaxTarea2
      mov al,[ds:ticksMaxTask1]
      inc al
      mov [ds:ticksMaxTask1],al
      mov al,[ds:ticksMaxTask2]
      dec al
      mov [ds:ticksMaxTask2],al
      jmp fin_handler

    pressE: ;logica si pulse E --> aumento 10% prioridad de tarea B y disminuyo 10% prioridad de tarea A
      ;si ticksMaxTask1 = 0 no sigo decrementandolo
      mov al,[ds:ticksMaxTask1]
      cmp al,0
      je fin_handler
      ;si ticksMaxTask1 todavia no es 0, aumento en 1 ticksMaxTask2 y disminuyo en 1 ticksMaxTask1
      mov al,[ds:ticksMaxTask2]
      inc al
      mov [ds:ticksMaxTask2],al
      mov al,[ds:ticksMaxTask1]
      dec al
      mov [ds:ticksMaxTask1],al    
      jmp fin_handler

    reset_keyPressState:     ;reset keyPressState
      mov bl, 0
      mov [ds:keyPressState], bl

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
      mov al, COLOR_BG_EXCEPTION     ;cargo valor del atributo para poner cada caracter en azul y fondo en azul --> 0x11 = 0 001 | 0 001 (R=0, G=0, B=1)
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
stackTaskInit_Lvl0:   ; pila de tarea inicial
resb 100h

stackSch_Lvl0:            ; irq0
resb 100h

stackSerialPort_Lvl0:         ; Tarea Puerto Serie
resb 100h

stackTask1_Lvl0:         ; Tarea Print Pantalla (Anillo 3 // call gate accede a Anillo 0)
resb 100h

stackTask2_Lvl0:         ; Tarea Print Pantalla (Anillo 3 // call gate accede a Anillo 0)
resb 100h

;Segmento de datos Anillo 3
data_anillo3:
resb 100h

;Pila Tarea 1 Anillo 3
stackTask1_Lvl3:
resb 100h

;Pila Tarea 1 Anillo 3
stackTask2_Lvl3:
resb 100h