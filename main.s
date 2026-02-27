#include <xc.inc>

; -------- LSM9DS1 A/G registers --------
WHO_AM_I_AG   equ 0x0F
CTRL_REG1_G   equ 0x10
OUT_X_L_G     equ 0x18

; -------- RAM (access) --------
psect udata_acs
addr    ds 1
tmp     ds 1

psect code
global main

; ==========================================================
; SPI1 Setup: Mode 3 for LSM9DS1 (CKP=1, CKE=0)
; Pins (as you want):
;   RD3 = SCK1  -> SPC/SCLK on breakout
;   RD4 = SDO1  -> SDI on breakout (MOSI)
;   RD5 = SDI1  <- SDOAG on breakout (MISO)
;   RA4 = CSAG  -> CS_A/G (active low)
; LEDs: LATJ
; ==========================================================
SPI1_Setup:
    ; Directions
    bcf     TRISD, 3, A      ; RD3 SCK1 output
    bcf     TRISD, 4, A      ; RD4 SDO1 (MOSI) output
    bsf     TRISD, 5, A      ; RD5 SDI1 (MISO) input
    bcf     TRISA, 4, A      ; RA4 CSAG output

    ; Idle levels
    bsf     LATA, 4, A       ; CS high (inactive)
    bsf     LATD, 3, A       ; SCK idle high (CKP=1)

    ; SPI mode bits
    bcf     SSP1STAT, CKE, A ; CKE=0 for Mode 3 with CKP=1

    ; Enable SPI Master, CKP=1, choose slower clock first (Fosc/64)
    ; SSPM=0010 typically => Fosc/64
    movlw   b'00110010'      ; SSPEN=1(bit5), CKP=1(bit4), SSPM=0010
    movwf   SSP1CON1, A

    return

; ==========================================================
; SPI1 transfer 1 byte
; IN:  WREG = byte to send
; OUT: WREG = byte received
; ==========================================================
SPI1_Xfer:
    movwf   SSP1BUF, A
waitBF:
    btfss   SSP1STAT, BF, A
    bra     waitBF
    movf    SSP1BUF, W, A
    return

; ==========================================================
; LSM9DS1 A/G READ 1 register
; Command format (A/G): first byte = (addr<<1) | 1
; ==========================================================
LSM_AG_ReadReg:
    bcf     LATA, 4, A           ; CS low

    movf    addr, W, A
    rlf     WREG, W, A           ; addr << 1
    iorlw   0x01                 ; RW=1
    call    SPI1_Xfer            ; send command (ignore returned)

    movlw   0x00
    call    SPI1_Xfer            ; clock in data
    ; WREG now has data byte

    bsf     LATA, 4, A           ; CS high
    return

; ==========================================================
; LSM9DS1 A/G WRITE 1 register
; First byte = (addr<<1) | 0, then data byte
; IN: addr preset, WREG=data
; ==========================================================
LSM_AG_WriteReg:
    movwf   tmp, A

    bcf     LATA, 4, A           ; CS low

    movf    addr, W, A
    rlf     WREG, W, A           ; addr<<1 (RW=0)
    call    SPI1_Xfer

    movf    tmp, W, A
    call    SPI1_Xfer

    bsf     LATA, 4, A           ; CS high
    return

; ==========================================================
; main
; ==========================================================
main:
    ; LEDs on Port J
    clrf    TRISJ, A
    clrf    LATJ, A

    call    SPI1_Setup

    ; ---- WHO_AM_I proof ----
    movlw   WHO_AM_I_AG
    movwf   addr, A
    call    LSM_AG_ReadReg
    movwf   LATJ, A              ; should display 0x68

    ; ---- turn gyro on ----
    movlw   CTRL_REG1_G
    movwf   addr, A
    movlw   0x60                 ; ODR=119Hz, FS=245dps
    call    LSM_AG_WriteReg

loop:
    ; Read OUT_X_H_G and show on LEDs
    movlw   (OUT_X_L_G + 1)      ; 0x19 = X high byte
    movwf   addr, A
    call    LSM_AG_ReadReg
    movwf   LATJ, A

    bra     loop
