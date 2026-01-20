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

            ; Stop the watchdog timer
            mov.w   #WDTPW+WDTHOLD,&WDTCTL
            ; Disable low-power mode
            bic.w   #LOCKLPM5,&PM5CTL0
            bis.w #GIE, SR              ; Enable global interrupts

main:

            nop
            jmp main
            nop



;-------------------------------------------------------------------------------
; Subroutines
;-------------------------------------------------------------------------------

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
