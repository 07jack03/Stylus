;========================
; imu_lsm9ds1.s  (SSP2 SPI WHO_AM_I test)
;========================
#include <xc.inc>

global  IMU_Test_Init
global  IMU_Test_Step

; CSAG -> RA4 (keep if working)
CSAG_PORT   equ LATA
CSAG_TRIS   equ TRISA
CSAG_BIT    equ 4

psect udata_acs
d0: ds 1
d1: ds 1
d2: ds 1
rx: ds 1

psect code, class=CODE

Delay:
        movlw   0x20
        movwf   d0, A
D0:     movlw   0xFF
        movwf   d1, A
D1:     movlw   0xFF
        movwf   d2, A
D2:     decfsz  d2, F, A
        bra     D2
        decfsz  d1, F, A
        bra     D1
        decfsz  d0, F, A
        bra     D0
        return

;---------------------------------------
; SSP2 SPI transfer:
; write W to SSP2BUF, wait SSP2IF, return W=SSP2BUF
;---------------------------------------
SPI2_Xfer:
        movwf   SSP2BUF, A
W2:     btfss   PIR2, 5, A        ; SSP2IF
        bra     W2
        bcf     PIR2, 5, A        ; clear flag
        movf    SSP2BUF, W, A
        return

IMU_Test_Init:
        ; LEDs
        clrf    TRISJ, A
        clrf    LATJ,  A

        ; CSAG output, idle HIGH
        bcf     CSAG_TRIS, CSAG_BIT, A
        bsf     CSAG_PORT, CSAG_BIT, A

        ; ========= SPI2 pin directions =========
        ; TODO: set the *actual* SSP2 pins:
        ; - SCK2 output
        ; - SDO2 output (MOSI)
        ; - SDI2 input  (MISO)
        ;
        ; Example placeholders (CHANGE THESE!):
        ; bcf TRISD, ?, A   ; SCK2 output
        ; bcf TRISD, ?, A   ; SDO2 output
        ; bsf TRISD, ?, A   ; SDI2 input

        ; ========= SPI2 config =========
        ; CKE=0 in SSP2STAT (like your old working code)
        bcf     CKE2, A

        ; SSP2CON1: enable + master + clock polarity
        ; This matches your known-good:
        movlw   (SSP2CON1_SSPEN_MASK) | (SSP2CON1_CKP_MASK) | (SSP2CON1_SSPM1_MASK)
        movwf   SSP2CON1, A

        ; Clear any pending flag by reading buffer
        movf    SSP2BUF, W, A
        bcf     PIR2, 5, A
        return

IMU_Test_Step:
        ; Phase marker A
        clrf    LATJ, A
        bcf     CSAG_PORT, CSAG_BIT, A
        bsf     LATJ, 0, A
        call    Delay

        ; Phase marker B
        clrf    LATJ, A
        bsf     LATJ, 1, A
        call    Delay

        ; Phase C: WHO_AM_I read
        clrf    LATJ, A
        bsf     LATJ, 3, A

        bcf     CSAG_PORT, CSAG_BIT, A
        nop
        nop

        movlw   0x8F              ; READ WHO_AM_I (0x0F)
        call    SPI2_Xfer         ; discard

        movlw   0x00
        call    SPI2_Xfer         ; read byte
        movwf   rx, A

        bsf     CSAG_PORT, CSAG_BIT, A

        movf    rx, W, A
        movwf   LATJ, A
        call    Delay
        return

end
