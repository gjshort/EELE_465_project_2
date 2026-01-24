;-------------------------------------------------------------------------------
; Include files
            .cdecls C,LIST,"msp430.h"
;-------------------------------------------------------------------------------

            ; RESET will be our program's entry point; we must define it to
            ; so the linker knows about it. The project configuration (.cproject)
            ; sets RESET as the entry point. Alternatively, we could have defined
            ; -e RESET in lnk_msp430fr2355.cmd instead of in the proejct settings.
            .def    RESET

            ; Make stack linker segment known
            .global __STACK_END
            .sect   .stack


            ; Assemble to flash memory
            .text

;--------------------------------------------------------------------------------
; Data Allocation
;--------------------------------------------------------------------------------

            .data                         ; go to data memory (2000h)
            .retain                       ; keep this section, even if not used

tx_byte:    .byte  0            ; Memory location where a byte destined for
                                ; i2c transmit is stored  

            ; Ensure current section gets linked
            .retain
            .retainrefs



            ; Initialize the stack pointer to the bottom of the stack
RESET       mov.w   #__STACK_END,SP

;-------------------------------------------------------------------------------
; Macros
;-------------------------------------------------------------------------------

SDA_PIN .equ BIT0
SCL_PIN .equ BIT2
I2C_DIR .equ P3DIR

MSB_MASK .equ 0x80


init:

            ; -- Register Init --
            mov.w   #8d, R15        ; Counter register for Tx/Rx

            ; -- P1.0 (LED1 Heartbeat) --
            bic.b #BIT0, &P1SEL0    ; Set to Digital I/O
            bic.b #BIT0, &P1SEL1    ; "..."
            bis.b #BIT0, &P1DIR     ; Set dir to out
            bic.b #BIT0, &P1OUT     ; Clear output

            ; -- TB0 (LED1 PWM) --
            ; 0.5 second timer for 50% duty cycle and 1 sec. period
            ; 0.5 sec = 1 us * 4 * 5 * 25,000
            bic.w #TBCLR, &TB0CTL			; Clear timers/dividers
            bis.w #TBSSEL__SMCLK, &TB0CTL	; 1 MHz ref clock
            bis.w #MC__UP, &TB0CTL			; Up mode
            bis.w #CNTL_0, &TB0CTL			; 16 bit counter
            bis.w #ID__4, &TB0CTL			; Divide by 4
            bis.w #TBIDEX__5, &TB0EX0		; Dicide by 5
            bis.w #25000d, &TB0CCR0	   ; Set compare value
            bic.w #CCIFG, &TB0CCTL0			; Clear interrupt flag
	        bis.w #CCIE, &TB0CCTL0			; Enable interrupt

            ; -- P3.2 (I2C SCL) --
            ; SCL here will be listening until it takes over
            bic.b #SCL_PIN, &P3SEL0    ; Set to Digital I/O
            bic.b #SCL_PIN, &P3SEL1    ; "...""
            bic.b #SCL_PIN, &I2C_DIR     ; Set dir to input
            bis.b #SCL_PIN, &P3REN     ; Enable resistor
            bis.b #SCL_PIN, &P3OUT     ; Pull-up

            ; -- P3.0 (I2C SDA) --
            ; SDA here will be listening until it takes over
            bic.b #SDA_PIN, &P3SEL0    ; Set to Digital I/O
            bic.b #SDA_PIN, &P3SEL1    ; "..."
            bic.b #SDA_PIN, &I2C_DIR   ; Set dir to input
            bis.b #SDA_PIN, &P3REN     ; Enable resistor
            bis.b #SDA_PIN, &P3OUT     ; Pull-up

            ; -- Final Init --
            mov.w   #WDTPW+WDTHOLD,&WDTCTL  ; Stop the watchdog timer
            bic.w   #LOCKLPM5,&PM5CTL0      ; Disable low-power mode
            nop
            bis.w #GIE, SR                  ; Enable global interrupts
            nop

main:
            ; this call will go through the program flow to transmit 3 bytes
            call #i2c_Nbytes
            
            call #delay_50ms
            
            nop
            jmp main
            nop



;-------------------------------------------------------------------------------
; Subroutines
;-------------------------------------------------------------------------------

; --- Delay 50 ms ---
delay_50ms:
            push R4
	    mov.w #04440h, R4	    ; Set delay counter (started at 30D1)
delay_50ms_loop:
            dec.w R4				; 
            jnz delay_50ms_loop	    ; Repeat loop until R4 is 0 
            pop R4
	        ret

; -- 12 us Delay --
; When measuring on a scope, the time it takes
; this function to execute between toggling
; GPIO pins is roughly 12 us.
delay_12us:
            ret

; -- I2C Start --
; Generates the start condition for I2C
i2c_start:

            bis.b #SCL_PIN, &I2C_DIR     ; Set SCL to output
            bis.b #SDA_PIN, &I2C_DIR     ; Set SDA to output

            bic.b #SDA_PIN, &P3OUT     ; Send SDA low for start
            call #delay_12us        ; Delay between SDA and SCL low

            bic.b #SCL_PIN, &P3OUT     ; Send SCL low
            call #delay_12us
            ret

; -- I2C Stop --
i2c_stp:
; From user guide UM10204 3.1.4; a LOW to HIGH transition on the SDA line while SCL is HIGH defines a STOP condition
; The bus is considered to be free again a certain time (4.7 us) after the STOP condition.

    bis.b   #SCL_PIN, &I2C_DIR           ; Set SCL to output
    bis.b   #SDA_PIN, &I2C_DIR           ; Set SDA to output

    bic.b   #SDA_PIN, &P3OUT           ; Ensure SDA is in LOW state
    bis.b   #SCL_PIN, &P3OUT           ; Ensure SCL is in HIGH state
    call    #delay_12us             ; Ensure enough rise time for SCL, which is only 1us but twelve-fold will do the trick

    bis.b   #SDA_PIN, &P3OUT           ; Make the transition to HIGH

    call    #delay_12us             ; Ensure bus lines become free after condition generation

    ret

; -- I2C Tx Byte --
i2c_tx_byte:
; This subroutine along with the following nested routines will handle transmitting a byte.
; General workflow of this is to move whatever you want to be sent (stored in reserved space tx_byte) to R4, test MSB in R4
; and then based on Z flag after the test manipulate SDA and SCL lines to transmit the message one bit at a time. each bit 
; being sent is the MSB in R4, so we use a rotate operation in next_bit to shift the next bit that is to be sent into the MSB 
; position of R4, while a counter variable (R15) keeps track to send exactly a byte worth including (R/W) before exiting this subroutine back to main.

    push    R4                      ; Save previous state of R4 to stack

    mov.b   &tx_byte, R4            ; move whatever is in tx byte to R4

msb_tst:
        bit.b   #MSB_MASK, R4           ; tst MSB of R4
        jnz     sda_high                ; if MSB in R4 is not 0 go to sda_high

sda_low:
        bic.b   #SDA_PIN, &P3OUT        ; set SDA to LOW
        jmp     tx_scl                  

sda_high:
        bis.b   #SDA_PIN, &P3OUT        ; Set SDA to HIGH

tx_scl:
        call    #delay_12us             ; ensure SDA in LOW state

        bis.b   #SCL_PIN, &P3OUT        ; Set SCL to HIGH
        call    #delay_12us             ; Ensure SCL is HIGH

        bic.b   #SCL_PIN, &P3OUT        ; Set SCL to LOW
        call    #delay_12us             ; SCL hold delay

next_bit:
        rlc     R4                      ; Rotate to the next MSB to send
        dec.w   R15
        jnz     msb_tst                  

        mov.w   #8d, R15                ; Reset Tx/Rx counter variable
        pop     R4                      ; Restore R4 from stack
        ret

;-- i2c_tx_ack --
i2c_tx_ack:
; This subroutine will force an ACK signal to be sent, for I2C protocol, this should be sent during the 9th clock cycle on SCL.
; To achieve this we will simply send SDA to a low after it is released from the R/W bit and have it remain LOW during SCLs 
; HIGH period of this 9th clock pulse set-up and hold times.

    bic.b   #SDA_PIN, &P3OUT        ; Take SDA to a LOW state
    call    #delay_12us

    bis.b   #SCL_PIN, &P3OUT        ; Take SCL to a HIGH state (if not in a HIGH state already)
    call    #delay_12us             ; Delay to ensure SDA is in LOW state for SCLs setup and hold times in HIGH state. 12us should be more than enough time.
    bic.b   #SCL_PIN, &P3OUT        ; Take SCL LOW

    ret                             ; Go back to main program flow.

;-- i2c_tx_nack -- 
; Okay now this next one is just like the subroutine in direct predecession to this one, except instead we will send a NACK signal on SCLs 9th cycle.
; Now apparently theres actually 5 different situations where a NACK will be sent, this subroutine is the brute force approach.
; We keep SDA HIGH while the SCL enters its 9th cycle.
i2c_tx_nack:

    bis.b   #SDA_PIN, &P3OUT        ; Send SDA HIGH
    call    #delay_12us             ; give it time, son

    bis.b   #SCL_PIN, &P3OUT        ; Send SCL HIGH
    call    #delay_12us
    bic.b   #SCL_PIN, &P3OUT        ; Take SCL LOW

    ret

;-- i2c_Nbytes --
; This subroutine will send multiple bytes with an ACK after each address, we will be using previously made subroutines, 
;so look at those for the details of how it all works
i2c_Nbytes:

    ; Generate START
    call #i2c_start

    ; Transmits 1st byte, send ack, then send repeated start
    mov.b   #69h, &tx_byte
    call    #i2c_tx_byte
    call    #i2c_tx_ack               ; Okay so we did need NACK, maybe? My thought was to froce a nack so it can send a repeat start condition for next byte.

    ; Transmits 2nd byte, ..^
    mov.b   #67h, &tx_byte
    call    #i2c_tx_byte
    call    #i2c_tx_ack

    ; Transmits 3rd byte, ..^
    mov.b   #70h, &tx_byte
    call    #i2c_tx_byte
    call    #i2c_tx_nack

    ; End of bytes, generate STOP
    call    #i2c_stp

    ret

; --- Timer B0 ISR ---
TB0_CCR0_ISR:

	        xor.b #BIT0, &P1OUT		; Toggle LED1
	        bic.w #CCIFG, &TB0CCTL0	; Clear interrupt flag
	        reti


;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   RESET_VECTOR
            .short  RESET

            .sect 	".int43"				; TB0CCR0 Vector
	        .short	TB0_CCR0_ISR

            .end
