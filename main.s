;========================
; main.s  (calls the SSP2-based IMU test)
;========================
#include <xc.inc>

extrn   IMU_Test_Init
extrn   IMU_Test_Step

psect   resetVec, abs
org     0x0000
        goto    start

psect   code, class=CODE
start:
        ; PORTJ LEDs output (EasyPIC LEDs)
        clrf    TRISJ, A
        clrf    LATJ,  A

        ; init SPI + CS + LEDs
        call    IMU_Test_Init

loop:
        call    IMU_Test_Step
        bra     loop

end
