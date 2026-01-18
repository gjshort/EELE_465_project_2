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
            ; Stop the watchdog timer
            mov.w   #WDTPW+WDTHOLD,&WDTCTL

            ; Disable low-power mode
            bic.w   #LOCKLPM5,&PM5CTL0

main:

            nop
            jmp main
            nop



;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   RESET_VECTOR
            .short  RESET

            .end
