#define __SFR_OFFSET 0
#include <avr/io.h>

#define SS_PIN   2
#define MOSI_PIN 3
#define MISO_PIN 4
#define SCK_PIN  5
#define IND_PIN  0  // Pin 8 (Indikator LED Status)
#define PWM_PIN  1  // Pin 9 (Servo)

#define ST_LOCKED 0
#define ST_STOP   1
#define ST_DRIVE  2
#define ST_BRAKE  3

#define sys_state r18
#define speed_val r19


.global main
.global __vector_1

__vector_1:             
    push r16
    in r16, SREG
    push r16

    rcall delay_debounce

wait_tombol_lepas:
    in r16, PIND
    sbrs r16, 2
    rjmp wait_tombol_lepas

    rcall delay_debounce

    ldi r16, (1<<INTF0)
    out EIFR, r16       

    cpi sys_state, ST_STOP
    breq turn_on_engine
    cpi sys_state, ST_DRIVE
    breq turn_off_engine
    rjmp end_isr

turn_on_engine:
    ldi sys_state, ST_DRIVE
    rjmp end_isr
turn_off_engine:
    cpi speed_val, 0
    brne end_isr
    ldi sys_state, ST_STOP

end_isr:
    pop r16
    out SREG, r16
    pop r16
    reti

main:
// Initialization
    ldi r16, lo8(RAMEND)
    out SPL, r16
    ldi r16, hi8(RAMEND)
    out SPH, r16

    ldi r16, (1<<MOSI_PIN)|(1<<SCK_PIN)|(1<<SS_PIN)|(1<<IND_PIN)|(1<<PWM_PIN)
    out DDRB, r16
    sbi PORTB, SS_PIN
    cbi DDRD, DDD2
    sbi PORTD, PORTD2

    ldi r16, (1<<SPE)|(1<<MSTR)|(1<<SPR0)
    out SPCR, r16
    ldi r24, 0x14
    rcall rc522_read_reg
    ori r24, 0x03
    mov r22, r24
    ldi r24, 0x14
    rcall rc522_write_reg

    ldi r16, (1<<REFS0)|(1<<ADLAR) 
    sts ADMUX, r16        
    ldi r16, (1<<ADEN)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0) 
    sts ADCSRA, r16       

    ldi r16, (1<<COM1A1)|(1<<WGM11)
    sts TCCR1A, r16       
    ldi r16, (1<<WGM13)|(1<<WGM12)|(1<<CS11)|(1<<CS10)
    sts TCCR1B, r16       
    ldi r16, hi8(4999)      
    sts ICR1H, r16        
    ldi r16, lo8(4999)
    sts ICR1L, r16        

    ldi r16, 103
    sts UBRR0L, r16
    ldi r16, (1<<TXEN0)
    sts UCSR0B, r16

    ldi r16, 72
    sts TWBR, r16

    ldi r16, (1<<ISC01)
    sts EICRA, r16
    ldi r16, (1<<INT0)
    out EIMSK, r16

    ldi sys_state, ST_LOCKED
    sei

fsm_loop:
    cpi sys_state, ST_LOCKED
    breq handle_locked

    cpi sys_state, ST_STOP
    breq handle_stop

    cpi sys_state, ST_DRIVE
    breq handle_drive

    cpi sys_state, ST_BRAKE
    breq handle_brake

    rjmp fsm_loop

// STATE 0: Terkunci (Cek RFID)
handle_locked:
    cbi PORTB, IND_PIN 
    rcall set_servo_zero
    rcall check_card_present
    cpi r24, 0
    breq fsm_loop
    
    // Simulasi FIFO 4 Byte
    ldi r16, 0x01
    mov r2, r16
    ldi r16, 0x02
    mov r3, r16
    ldi r16, 0x03
    mov r4, r16
    ldi r16, 0x04
    mov r5, r16

    rcall authenticate_uid

wait_lepas_1:
    rcall check_card_present
    cpi r24, 0
    brne wait_lepas_1

    rcall delay_1sec
    rjmp fsm_loop

// STATE 1: Mesin Mati (Bisa jalan jika ditekan tombol, atau kunci lagi)
handle_stop:
    sbi PORTB, IND_PIN
    rcall set_servo_zero
    
    rcall check_card_present
    cpi r24, 0
    breq fsm_loop
    ldi sys_state, ST_LOCKED

wait_lepas_2:
    rcall check_card_present
    cpi r24, 0
    brne wait_lepas_2

    rcall delay_1sec
    rjmp fsm_loop

// STATE 2: Berkendara (Baca ADC, Hitung Arithmetic, Update PWM)
handle_drive:
    lds r16, ADCSRA
    ori r16, (1<<ADSC)
    sts ADCSRA, r16
wait_adc:
    lds r16, ADCSRA
    sbrc r16, ADSC
    rjmp wait_adc
    lds speed_val, ADCH

    mov r16, speed_val
    ldi r17, 250
    add r16, r17
    clr r17
    adc r17, r17
    sts OCR1AH, r17
    sts OCR1AL, r16

    cpi speed_val, 200      // Jika gas >= 200, nyalakan safety measure
    brsh trigger_brake

    rjmp fsm_loop

trigger_brake:
    ldi sys_state, ST_BRAKE
    rjmp fsm_loop

// STATE 3: Pengereman Darurat (Auto Override & I2C Warning)
handle_brake:
    rcall set_servo_zero
    
    ldi r24, 'W'
    rcall uart_send
    rcall i2c_send_warning
    
    rcall delay_1sec
    rcall delay_1sec
    
    ldi sys_state, ST_DRIVE
    rjmp fsm_loop

// Arithmetic & Actuator
set_servo_zero:
    ldi r16, 0x00
    sts OCR1AH, r16
    ldi r16, 250
    sts OCR1AL, r16
    ret

authenticate_uid:
    ldi r16, 0x01
    cp r2, r16
    brne auth_fail
    
    ldi r16, 0x02
    cp r3, r16
    brne auth_fail

    ldi r16, 0x03
    cp r4, r16
    brne auth_fail

    ldi r16, 0x04
    cp r5, r16
    brne auth_fail
    
    ldi sys_state, ST_STOP 
auth_fail:
    ret

// Driver Komunikasi
uart_send:
    lds r16, UCSR0A
    sbrs r16, UDRE0
    rjmp uart_send
    sts UDR0, r24
    ret

i2c_send_warning:
    ldi r16, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
    sts TWCR, r16
wait_i2c:
    lds r16, TWCR
    sbrs r16, TWINT
    rjmp wait_i2c
    ret

// Driver SPI & RFID

check_card_present:
    ldi r24, 0x0A
    ldi r22, 0x80
    rcall rc522_write_reg

    ldi r24, 0x09
    ldi r22, 0x26
    rcall rc522_write_reg

    ldi r24, 0x0D
    ldi r22, 0x07
    rcall rc522_write_reg

    ldi r24, 0x01
    ldi r22, 0x0C
    rcall rc522_write_reg

    ldi r24, 0x0D
    rcall rc522_read_reg
    ori r24, 0x80
    mov r22, r24
    ldi r24, 0x0D
    rcall rc522_write_reg

    ldi r16, 255
wait_response:
    dec r16
    brne wait_response

    ldi r24, 0x0A
    rcall rc522_read_reg
    ret
    
rc522_write_reg:
    cbi PORTB, SS_PIN
    lsl r24
    andi r24, 0x7E
    rcall spi_transfer
    mov r24, r22
    rcall spi_transfer
    sbi PORTB, SS_PIN
    ret

rc522_read_reg:
    cbi PORTB, SS_PIN
    lsl r24
    andi r24, 0x7E
    ori r24, 0x80
    rcall spi_transfer
    ldi r24, 0x00
    rcall spi_transfer
    sbi PORTB, SS_PIN
    ret

spi_transfer:
    out SPDR, r24
wait_spi:
    in r16, SPSR
    sbrs r16, SPIF
    rjmp wait_spi
    in r24, SPDR
    ret

// Delay 1s

delay_1sec:
    push r20
    push r21
    push r22
    ldi r20, 80
outer_loop:
    ldi r21, 255
middle_loop:
    ldi r22, 255
inner_loop:
    dec r22
    brne inner_loop
    dec r21
    brne middle_loop
    dec r20
    brne outer_loop
    pop r22
    pop r21
    pop r20
    ret

// Debounce 50ms

delay_debounce:
    push r20
    push r21
    push r22
    ldi r20, 4
db_out:
    ldi r21, 255
db_mid:
    ldi r22, 255
db_in:
    dec r22
    brne db_in
    dec r21
    brne db_mid
    dec r20
    brne db_out
    pop r22
    pop r21
    pop r20
    ret