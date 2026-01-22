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

            ; Ensure current section gets linked
            .retain
            .retainrefs

            ; Initialize the stack pointer to the bottom of the stack
RESET       mov.w   #__STACK_END,SP


init:

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
            bic.b #BIT2, &P3SEL0    ; Set to Digital I/O
            bic.b #BIT2, &P3SEL1    ; "...""
            bic.b #BIT2, &P3DIR     ; Set dir to input
            bis.b #BIT2, &P3REN     ; Enable resistor
            bis.b #BIT2, &P3OUT     ; Pull-up

            ; -- P3.0 (I2C SDA) --
            ; SDA here will be listening until it takes over
            bic.b #BIT0, &P3SEL0    ; Set to Digital I/O
            bic.b #BIT0, &P3SEL1    ; "..."
            bic.b #BIT0, &P3DIR     ; Set dir to input
            bis.b #BIT0, &P3REN     ; Enable resistor
            bis.b #BIT0, &P3OUT     ; Pull-up

            ; -- Final Init --
            mov.w   #WDTPW+WDTHOLD,&WDTCTL  ; Stop the watchdog timer
            bic.w   #LOCKLPM5,&PM5CTL0      ; Disable low-power mode
            nop
            bis.w #GIE, SR                  ; Enable global interrupts
            nop

main:

            call #i2c_start         ; Generate start condition on SDA/SCL

            ;call #i2c_stp           ; Generate stop condition *has not been tested*

            nop
            jmp main
            nop



;-------------------------------------------------------------------------------
; Subroutines
;-------------------------------------------------------------------------------

; -- 12 us Delay --
; When measuring on a scope, the time it takes
; this function to execute between toggling
; GPIO pins is roughly 12 us.
delay_12us:
            ret

; -- I2C Start --
; Generates the start condition for I2C
i2c_start:

            bis.b #BIT2, &P3DIR     ; Set SCL to output
            bis.b #BIT0, &P3DIR     ; Set SDA to output

            bic.b #BIT0, &P3OUT     ; Send SDA low for start
            call #delay_12us        ; Delay between SDA and SCL low

            bic.b #BIT2, &P3OUT     ; Send SCL low
            ret

; -- I2C Stop --
; Generates the stop condition for I2C
i2c_stp:

; From user guide UM10204 3.1.4; a LOW to HIGH transition on the SDA line while SCL is HIGH defines a STOP condition
; The bus is considered to be free again a certain time (4.7 us) after the STOP condition.

    bis.b   #BIT2, &P3DIR           ; Set SCL to output
    bis.b   #BIT0, &P3DIR           ; Set SDA to output

    bis.b   #BIT2, &P3OUT           ; Ensure SCL is in HIGH state
    ;call    #delay_12us             ; Ensure enough rise time for SCL, which is only 1us but twelve-fold will do the trick

    bic.b   #BIT0, &P3OUT           ; Ensure SDA is in LOW state
    bis.b   #BIT0, &P3OUT           ; Make the transition to HIGH

    call    #delay_12us             ; Ensure bus lines become free after condition generation

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
