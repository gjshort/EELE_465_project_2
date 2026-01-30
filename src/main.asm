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

tx_byte:    .byte  0            ; Byte destined for i2c transmit is stored  
rx_byte:    .byte  0            ; Byte from an i2c receive
i2c_ack:    .byte  0            ; I2C ACK and NACK
rtc_reg:    .byte  0            ; Register pointer for RTC
rtc_tx_data:   .byte 0          ; Data to be sent to the RTC
rx_byte_count: .byte 0          ; Number of bytes to read from slave

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
RTC_WR  .equ 0DEh      ; RTC Addr 0x6F | WR (0)
RTC_RD  .equ 0DFh      ; RTC Addr 0x6F | RD (1)
RTC_OSC_EN  .equ 080h  ; RTC oscillator enable bit in seconds reg
RTC_SEC_REG .equ 00h   ; RTC seconds register
RTC_MIN_REG .equ 01h   ; RTC minutes register
RTC_HR_REG  .equ 02h   ; RTC hours register

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

            ; Init the RTC by setting the oscillator enable
            ; bit in the seconds register
            mov.b #RTC_SEC_REG, &rtc_reg
            mov.b #RTC_OSC_EN, &rtc_tx_data 
            call #rtc_write_register        

main:

            mov.b #RTC_SEC_REG, &rtc_reg    
            call #rtc_read_register

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
            
delay_50ms_loop

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

; -- rtc_write_register --
; Writes the data stored in 'rtc_tx_data' to the
; RTC register specified in 'rtc_reg'. These locations
; must be updated prior to calling this function.
rtc_write_register:

        call #i2c_start

        ; Send RTC Address with write bit
        mov.b #RTC_WR, &tx_byte
        call #i2c_tx_byte
        call #i2c_rx_ack   
        cmp.b #0, &i2c_ack              ; Check ACK/NACK
        jnz exit_rtc_write              ; Exit if NACK           

        ; Set RTC register pointer
        mov.b &rtc_reg, &tx_byte        ; Writing to seconds register
        call #i2c_tx_byte
        call #i2c_rx_ack   
        cmp.b #0, &i2c_ack              ; Check ACK/NACK
        jnz exit_rtc_write              ; Exit if NACK                

        ; Write to RTC seconds register
        mov.b &rtc_tx_data, &tx_byte    ; Pack Tx buffer with data
        call #i2c_tx_byte
        call #i2c_rx_ack
        
exit_rtc_write

        call #i2c_stp

        ret

; -- RTC Read Register --
; Reads the register specified in 'rtc_reg'.
; The user must write to that location before calling this.
rtc_read_register:

        call #i2c_start

        ; Send RTC Address with write bit
        mov.b #RTC_WR, &tx_byte
        call #i2c_tx_byte
        call #i2c_rx_ack   
        cmp.b #0, &i2c_ack              ; Check ACK/NACK
        jnz exit_rtc_read               ; Exit if NACK           

        ; Set RTC register pointer
        mov.b &rtc_reg, &tx_byte        ; Writing to seconds reg.
        call #i2c_tx_byte
        call #i2c_rx_ack   
        cmp.b #0, &i2c_ack              ; Check ACK/NACK
        jnz exit_rtc_read               ; Exit if NACK                

        ; Start & stop before switching to reading
        call #i2c_repeated_start        ; Switch from WR to RD

        ; Tx Address and specify a read
        mov.b #RTC_RD, &tx_byte                 
        call #i2c_tx_byte                       
        call #i2c_rx_ack                        
        cmp.b #0, &i2c_ack              ; Check ACK/NACK
        jnz exit_rtc_read               ; Exit if NACK

        ; Read from RTC and end transmission
        call #i2c_rx_byte               ; Receive byte (stored in rx_byte)
        call #i2c_tx_nack               ; Stop asking for data
      
exit_rtc_read

        call #i2c_stp

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

    bis.b   #SDA_PIN, &I2C_DIR           ; Set SDA to output

msb_tst

        bit.b   #MSB_MASK, R4           ; tst MSB of R4
        jnz     sda_high                ; if MSB in R4 is not 0 go to sda_high

sda_low

        bic.b   #SDA_PIN, &P3OUT        ; set SDA to LOW
        jmp     tx_scl                  

sda_high

        bis.b   #SDA_PIN, &P3OUT        ; Set SDA to HIGH

tx_scl

        call    #delay_12us             ; ensure SDA in LOW state

        bis.b   #SCL_PIN, &P3OUT        ; Set SCL to HIGH
        call    #delay_12us             ; Ensure SCL is HIGH

        bic.b   #SCL_PIN, &P3OUT        ; Set SCL to LOW
        call    #delay_12us             ; SCL hold delay

next_bit

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

    bis.b   #SDA_PIN, &I2C_DIR           ; Set SDA to output

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

    bis.b   #SDA_PIN, &I2C_DIR      ; Set SDA to output

    bis.b   #SDA_PIN, &P3OUT        ; Send SDA HIGH
    call    #delay_12us             ; give it time, son

    bis.b   #SCL_PIN, &P3OUT        ; Send SCL HIGH
    call    #delay_12us
    bic.b   #SCL_PIN, &P3OUT        ; Take SCL LOW

    ret

; -- i2c_rx_ack -- 
; Releases SDA and pulses SCL so that the target can pull it high or low
; to indicate ACK/NACK. Saves the SR zero flag in R14.
i2c_rx_ack:

        bis.b #SDA_PIN, &P3OUT          ; Input pull-up resister
        bis.b #SDA_PIN, &P3REN          ; Enable resistor
        bic.b #SDA_PIN, &I2C_DIR        ; Set SDA to input
        call #delay_12us                ; Let slave set up ACK/NACK

        bis.b #SCL_PIN, &P3OUT          ; Send SCL HIGH
        call #delay_12us                ; SCL hold
        
        bit.b #SDA_PIN, &P3IN           ; Check for ACK/NACK                  
        jz store_ack

store_nack

        mov.b #1, &i2c_ack              ; A 1 indicates a NACK
        jmp end_rx_ack

store_ack

        mov.b #0, &i2c_ack              ; A 0 indicates an ACK

end_rx_ack

        call #delay_12us                ; SCL hold
        bic.b #SCL_PIN, &P3OUT          ; Send SCL LOW

        bis.b #SDA_PIN, &I2C_DIR        ; Set SDA to output           

        ret

; -- i2c_repeated_start --
; Sends a repeated start condition
i2c_repeated_start:

        bis.b #SDA_PIN, &I2C_DIR        ; Set SDA to output

        bis.b #SDA_PIN, &P3OUT          ; Send SDA high
        call #delay_12us

        bis.b #SCL_PIN, &P3OUT          ; Send SCL high
        call #delay_12us      

        bic.b #SDA_PIN, &P3OUT          ; Send SDA low
        call #delay_12us

        bic.b #SCL_PIN, &P3OUT          ; Send SCL low
        ret

;-- i2c_tx_Nbytes --
; This subroutine will send multiple bytes and receive an ACK after each. 
i2c_tx_Nbytes:

    ; Generate START
    call #i2c_start

    ; Transmits 1st byte, send ack, then send repeated start
    mov.b   #68h, &tx_byte
    call    #i2c_tx_byte
    call    #i2c_rx_ack               ; Okay so we did need NACK, maybe? My thought was to froce a nack so it can send a repeat start condition for next byte.

    ; Transmits 2nd byte, ..^
    mov.b   #67h, &tx_byte
    call    #i2c_tx_byte
    call    #i2c_rx_ack

    ; Transmits 3rd byte, ..^
    mov.b   #70h, &tx_byte
    call    #i2c_tx_byte
    call    #i2c_rx_ack

    ; End of bytes, generate STOP
    call    #i2c_stp

    ret

;-- i2c_tx_count --
; R6 counts from 0 thru 9 and the value is transmitted
; over I2C to the address entered below.
i2c_tx_count:

        push R6                 ; Preserve R6
        mov.w #0, R6            ; Init counter
        call #i2c_start

        ; Send address
        mov.b #68h, &tx_byte     ; Addr 0x34 | Read
        call #i2c_tx_byte
        call #i2c_rx_ack

send_count
        
        mov.w R6, &tx_byte      ; Copy counter val to i2c Tx buffer
        call #i2c_tx_byte       ; Tx i2c buffer
        call #i2c_rx_ack        ; Receive ACK from target

        inc.w R6                ; Increment counter
        cmp.w #10, R6           ; Count 0 thru 9
        jne send_count          ; Send next counter val

exit_i2c_tx_count

        call #i2c_stp
        pop R6                  ; Restore R6
        ret


;-- i2c_rx_byte --
; This subroutine will receive a byte from the AD2 after we 
; have A:READY sent a read request.
i2c_rx_byte:

        push    R7
        mov.w   #00h, R7                ; Use R7 for I2C Rx buffer

        bis.b #SDA_PIN, &P3OUT          ; Input pull-up resister
        bis.b #SDA_PIN, &P3REN          ; Enable resistor
        bic.b #SDA_PIN, &I2C_DIR        ; Set SDA to input
        call #delay_12us                ; Let slave set up ACK/NACK

receiving

        bis.b #SCL_PIN, &P3OUT          ; Send SCL HIGH
        call #delay_12us                ; SCL hold

        bit.b   #SDA_PIN, &P3IN         ; Test if SDA reeceived a 1 or 0
        jnz     store_1                 ; If it was a 1, store a 1 in the reg
                                        ; If it was a zero, continue to storing a 0
store_0
        or.w    #0d, R7                 ; Set the LSb to 0 (last received)
        jmp     end_store

store_1
        or.w    #1d, R7                 ; Set the LSb to 1 (last received)

end_store

        bic.b   #SCL_PIN, &P3OUT        ; Send SCL LOW
        call    #delay_12us

        dec     R15                     ; Rx 8 bits       
        jz      end_receive             ; Once counter is 0, stop receiving

        rla     R7                      ; Shift received bit to prepare for next one
        jmp     receiving               ; Receive next bit

end_receive

        mov.b R7, &rx_byte              ; Save receieved byte
        mov.w #8d, R15                ; Reset Tx/Rx counter
        pop   R7                      ; Restore R7
        ret


; -- i2c_rx_Nbytes --
; Reads the # of bytes specified in rx_byte_count from a slave
; The value is constantly overwritten in rx_byte for now.
i2c_rx_Nbytes:

        push R8
        mov.w #0, R8
        mov.b &rx_byte_count, R8                ; Number of sequential bytes to read

        call    #i2c_start                      ; Send START from master

        ; Tx Address and specify a write
        mov.b   #0DEh, &tx_byte                  ; Slave addr 0x34 | Write
        call    #i2c_tx_byte                    ; Transmit slave address
        call    #i2c_rx_ack                     ; Let slave send ack signal
        cmp.b #0, &i2c_ack                      ; Check ACK/NACK
        jnz exit_rx_Nbytes                      ; Exit if NACK

        ; Tx Slave register pointer
        mov.b   #0h, &tx_byte                   ; Set slave register pointer to 0
        call    #i2c_tx_byte                    ; Transmit register address
        call    #i2c_rx_ack                     ; Let slave send ack signal
        cmp.b #0, &i2c_ack                      ; Check ACK/NACK
        jnz exit_rx_Nbytes                      ; Exit if NACK

        ; Start & stop before switching to reading
        call    #i2c_repeated_start             ; Switch from WR to RD

        ; Tx Address and specify a read
        mov.b   #0DFh, &tx_byte                  ; Slave addr 0x34 | Read
        call    #i2c_tx_byte                    ; Transmit slave adress
        call    #i2c_rx_ack                     ; Let slave send ack signal
        cmp.b #0, &i2c_ack                      ; Check ACK/NACK
        jnz exit_rx_Nbytes                      ; Exit if NACK

rx_loop
        ; Receive data from slave
        call #i2c_rx_byte                       ; Receive byte (stored in rx_byte)
        dec.w R8                                ; Rx num of bytes specified in R8
        jz done_receiving_bytes                 ; Received all bytes

        call #i2c_tx_ack                        ; Tx ACK to request next byte from slave
        jmp rx_loop

done_receiving_bytes

        call    #i2c_tx_nack                    ; Tx NACK to stop slave from sending

exit_rx_Nbytes

        call    #i2c_stp                        ; End transmission
        pop R8
        ret

; --- Timer B0 ISR ---
; This creates a heartbeat LED
TB0_CCR0_ISR:

	        xor.b #BIT0, &P1OUT		; Toggle LED1
	        bic.w #CCIFG, &TB0CCTL0	        ; Clear interrupt flag
	        reti


;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   RESET_VECTOR
            .short  RESET

            .sect 	".int43"				; TB0CCR0 Vector
	        .short	TB0_CCR0_ISR

            .end
