#include <xc.inc>

; ==========================================================
; Adafruit LSM9DS1 over I2C using MSSP1 (RC3=SCL1, RC4=SDA1)
; Display bytes on PORTJ LEDs (LATJ)
; ==========================================================

; ---- LSM9DS1 (Accel/Gyro block) registers ----
WHO_AM_I_AG      equ 0x0F
CTRL_REG1_G      equ 0x10
OUT_X_L_G        equ 0x18          ; X low @0x18, X high @0x19

; ---- Possible I2C 7-bit addresses for A/G ----
; SDOAG selects between these two. We'll probe both.
AG_ADDR_A        equ 0x6A
AG_ADDR_B        equ 0x6B

; ---- Access RAM ----
psect udata_acs
devaddr      ds 1                  ; chosen 7-bit device address
regaddr      ds 1                  ; register address to access
tmp          ds 1                  ; temp storage

psect code
global main

; ==========================================================
; Delay (very rough, for human-visible LED update)
; Adjust N for your clock if needed.
; ==========================================================
Delay_ms:
    ; crude delay ~ a few ms depending on Fosc
    movlw   0xFF
    movwf   tmp, A
d1: decfsz  tmp, F, A
    bra     d1
    return

Delay_visible:
    ; repeat Delay_ms many times to slow LED updates
    movlw   80
    movwf   tmp, A
d2: call    Delay_ms
    decfsz  tmp, F, A
    bra     d2
    return

; ==========================================================
; I2C1 init: Master 100 kHz (example) at Fosc = 16 MHz
; SSP1ADD = (Fosc/(4*Fscl)) - 1 = (16MHz/(4*100k))-1 = 39 (0x27)
; ==========================================================
I2C1_Init:
    ; I2C pins as inputs (MSSP controls them open-drain)
    bsf     TRISC, 3, A            ; RC3/SCL1 input
    bsf     TRISC, 4, A            ; RC4/SDA1 input

    ; Standard speed: disable slew rate control? (PICs vary)
    ; Many labs set SMP=1 for Standard Mode.
    bsf     SSP1STAT, SMP, A

    ; I2C Master mode, SSPEN=1, SSPM=1000
    movlw   b'00101000'            ; SSPEN=1(bit5), SSPM=1000
    movwf   SSP1CON1, A

    movlw   0x27                   ; ~100kHz @16MHz
    movwf   SSP1ADD, A
    return

; ==========================================================
; Wait until MSSP1 is idle (no Start/Stop/Ack/Receive)
; ==========================================================
I2C1_WaitIdle:
wi:
    movf    SSP1CON2, W, A
    andlw   b'00011111'            ; SEN RSEN PEN RCEN ACKEN
    bnz     wi
    btfsc   SSP1STAT, R_W, A       ; transmit in progress
    bra     wi
    return

; ==========================================================
; Start / Stop / Restart
; ==========================================================
I2C1_Start:
    call    I2C1_WaitIdle
    bsf     SSP1CON2, SEN, A
    return

I2C1_Restart:
    call    I2C1_WaitIdle
    bsf     SSP1CON2, RSEN, A
    return

I2C1_Stop:
    call    I2C1_WaitIdle
    bsf     SSP1CON2, PEN, A
    return

; ==========================================================
; Write one byte on I2C
; IN:  WREG = byte
; OUT: ACKSTAT in SSP1CON2 tells if slave ACKed (0=ACK, 1=NACK)
; ==========================================================
I2C1_WriteByte:
    call    I2C1_WaitIdle
    movwf   SSP1BUF, A             ; begin transmission
wb:
    btfsc   SSP1STAT, BF, A        ; wait BF clear (buffer/shift emptied)
    bra     wb
    call    I2C1_WaitIdle
    return

; ==========================================================
; Read one byte from I2C
; IN:  WREG = 0 to ACK next, 1 to NACK next (ACKDT)
; OUT: WREG = received byte
; ==========================================================
I2C1_ReadByte:
    movwf   tmp, A                 ; save ACKDT setting (0=ACK,1=NACK)

    call    I2C1_WaitIdle
    bsf     SSP1CON2, RCEN, A      ; enable receive
rb:
    btfss   SSP1STAT, BF, A
    bra     rb
    movf    SSP1BUF, W, A          ; W = received byte

    ; send ACK/NACK
    call    I2C1_WaitIdle
    btfsc   tmp, 0, A
    bsf     SSP1CON2, ACKDT, A     ; NACK
    btfss   tmp, 0, A
    bcf     SSP1CON2, ACKDT, A     ; ACK
    bsf     SSP1CON2, ACKEN, A
    return

; ==========================================================
; Probe device address (does it ACK?)
; IN:  devaddr = 7-bit address
; OUT: Z flag set if ACK? We'll return W=0 if ACK, W=1 if NACK
; ==========================================================
I2C1_ProbeAddr:
    call    I2C1_Start
    movf    devaddr, W, A
    rlf     WREG, W, A             ; 7-bit -> put into bits7..1
    andlw   0xFE                   ; R/W=0 (write)
    call    I2C1_WriteByte

    ; ACKSTAT=0 means ACK received
    btfsc   SSP1CON2, ACKSTAT, A
    bra     nack
ack:
    call    I2C1_Stop
    clrw                          ; W=0
    return
nack:
    call    I2C1_Stop
    movlw   0x01                  ; W=1
    return

; ==========================================================
; Read one register from A/G over I2C
; IN:  devaddr = 7-bit address
;      regaddr = register address
; OUT: WREG = data byte
; ==========================================================
LSM_AG_ReadReg_I2C:
    ; Write phase: send register address
    call    I2C1_Start
    movf    devaddr, W, A
    rlf     WREG, W, A
    andlw   0xFE                   ; write
    call    I2C1_WriteByte

    movf    regaddr, W, A
    call    I2C1_WriteByte

    ; Read phase
    call    I2C1_Restart
    movf    devaddr, W, A
    rlf     WREG, W, A
    iorlw   0x01                   ; read
    call    I2C1_WriteByte

    movlw   0x01                   ; NACK after 1 byte
    call    I2C1_ReadByte          ; returns byte in W
    call    I2C1_Stop
    return

; ==========================================================
; Write one register to A/G over I2C
; IN: devaddr, regaddr, WREG=data
; ==========================================================
LSM_AG_WriteReg_I2C:
    movwf   tmp, A                 ; save data

    call    I2C1_Start
    movf    devaddr, W, A
    rlf     WREG, W, A
    andlw   0xFE                   ; write
    call    I2C1_WriteByte

    movf    regaddr, W, A
    call    I2C1_WriteByte

    movf    tmp, W, A
    call    I2C1_WriteByte

    call    I2C1_Stop
    return

; ==========================================================
; main
; ==========================================================
main:
    ; LEDs on Port J
    clrf    TRISJ, A
    clrf    LATJ, A

    call    I2C1_Init

    ; --------- Find which A/G address is present (0x6A or 0x6B) ---------
    movlw   AG_ADDR_A
    movwf   devaddr, A
    call    I2C1_ProbeAddr
    bz      got_addr              ; W=0 => ACK => good

    movlw   AG_ADDR_B
    movwf   devaddr, A
    call    I2C1_ProbeAddr
    bz      got_addr

    ; If neither ACKs, show error pattern (all LEDs on) and stop
    movlw   0xFF
    movwf   LATJ, A
hang:
    bra     hang

got_addr:
    ; --------- Read WHO_AM_I and show on LEDs ---------
    movlw   WHO_AM_I_AG
    movwf   regaddr, A
    call    LSM_AG_ReadReg_I2C
    movwf   LATJ, A               ; should be a stable ID byte
    call    Delay_visible

    ; --------- Turn gyro on: CTRL_REG1_G = 0x60 (119Hz, 245dps) ---------
    movlw   CTRL_REG1_G
    movwf   regaddr, A
    movlw   0x60
    call    LSM_AG_WriteReg_I2C

loop:
    ; Read OUT_X_H_G (0x19) and display (easier to see than low byte)
    movlw   (OUT_X_L_G + 1)       ; 0x19
    movwf   regaddr, A
    call    LSM_AG_ReadReg_I2C
    movwf   LATJ, A

    call    Delay_visible         ; slow down so LEDs are readable
    bra     loop
