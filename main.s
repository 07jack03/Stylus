#include <xc.inc>

; ==========================================================
; SPI2 on PORTD:
;   RD4 = SDO2 (output from PIC)
;   RD5 = SDI2 (input to PIC)
;   RD6 = SCK2 (clock output in master mode)
;   RD7 = SS2* (we will drive as GPIO chip-select)
; ==========================================================

global  SPI2_Setup, SPI2_TransferByte

psect   code

; --------------------------
; SPI2_Setup
; --------------------------
SPI2_Setup:
    ; 1) Make sure PORTD pins are digital (on this chip PORTD is typically digital-only,
    ; but leaving this comment here as a "checklist" item: analog pins must be disabled.)

    ; 2) TRIS directions:
    ;    RD4 (SDO2) output, RD6 (SCK2) output, RD7 (CS) output
    ;    RD5 (SDI2) input
    bcf     TRISD, 4, A      ; RD4 output (SDO2)
    bsf     TRISD, 5, A      ; RD5 input  (SDI2)
    bcf     TRISD, 6, A      ; RD6 output (SCK2)
    bcf     TRISD, 7, A      ; RD7 output (manual CS)

    ; 3) Set safe idle levels using LAT (not PORT) so outputs are stable
    bsf     LATD, 7, A       ; CS high (inactive)
    bcf     LATD, 6, A       ; SCK idle low (CKP=0 mode)

    ; 4) Configure SPI2 as Master
    ; SPI mode bits live in SSP2STAT and SSP2CON1 (MSSP2 module)
    ;
    ; SSP2STAT:
    ;   CKE = 1 means data changes on active-to-idle edge, sampled on idle-to-active edge (depends on CKP)
    ; We'll start with a common "Mode 0" style: CKP=0, CKE=1.
    ;
    ; SSP2CON1:
    ;   SSPEN = 1 enables SPI pins / module
    ;   CKP   = 0 clock idle low
    ;   SSPM  = 0000 -> SPI Master, clock = Fosc/4 (fastest, good for first tests if wiring is short)
    ;
    bsf     SSP2STAT, CKE, A     ; transmit on active edge setting (common start point)

    movlw   b'00100000'          ; SSPEN=1 (bit5), CKP=0, SSPM=0000 (Fosc/4)
    movwf   SSP2CON1, A

    return

; --------------------------
; SPI2_TransferByte
; IN:  WREG = byte to send
; OUT: WREG = byte received during transfer
; --------------------------
SPI2_TransferByte:
    ; Pull CS low to start transaction (your device may need this)
    bcf     LATD, 7, A

    ; Writing SSP2BUF starts the 8 clock pulses in hardware
    movwf   SSP2BUF, A

wait_bf:
    btfss   SSP2STAT, BF, A      ; BF=1 when receive is complete (8 bits shifted)
    bra     wait_bf

    ; Read received byte (also clears BF condition by reading buffer)
    movf    SSP2BUF, W, A

    ; End transaction
    bsf     LATD, 7, A
    return
