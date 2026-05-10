#define __SFR_OFFSET 0
#include <avr/io.h>

#define SS_PIN   2
#define MOSI_PIN 3
#define MISO_PIN 4
#define SCK_PIN  5
#define IND_PIN  0      // Pin 8 (Indikator LED Status)
#define PWM_PIN  1      // Pin 9 (Servo)
#define BLINK_PIN 7     // Pin 7 (LED Mesin Mati)
#define BUZZ_PIN 6      // Pin 6 (Active Buzzer)

#define ST_LOCKED 0     // State Terkunci
#define ST_STOP   1     // State Berhenti (Unlocked)
#define ST_DRIVE  2     // State Mengemudi
#define ST_BRAKE  3     // State Mengerem

#define sys_state  r18
#define speed_val  r19
#define print_tmr  r23  // Timer agar print gas tidak terlalu nge-spam
#define prev_state r26  // FIX: Menggunakan r26 

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

    ldi r16, 0xFF
    mov prev_state, r16
    clr print_tmr

    ldi r16, (1<<MOSI_PIN)|(1<<SCK_PIN)|(1<<SS_PIN)|(1<<IND_PIN)|(1<<PWM_PIN)
    out DDRB, r16
    sbi PORTB, SS_PIN       
    cbi DDRD, DDD2          
    sbi PORTD, PORTD2
    sbi DDRD, DDD7
    cbi PORTD, BLINK_PIN
    sbi DDRD, DDD6
    cbi PORTD, BUZZ_PIN

    ldi r16, (1<<SPE)|(1<<MSTR)|(1<<SPR0)
    out SPCR, r16

    ldi r24, 0x01
    ldi r22, 0x0F
    rcall rc522_write_reg
    rcall delay_1sec

    ldi r24, 0x2A
    ldi r22, 0x8D
    rcall rc522_write_reg
    
    ldi r24, 0x2B
    ldi r22, 0x3E
    rcall rc522_write_reg
    
    ldi r24, 0x2C
    ldi r22, 0x00
    rcall rc522_write_reg
    
    ldi r24, 0x2D
    ldi r22, 0x1E
    rcall rc522_write_reg

    ldi r24, 0x15
    ldi r22, 0x40
    rcall rc522_write_reg

    ldi r24, 0x11
    ldi r22, 0x3D
    rcall rc522_write_reg

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

    // Inisialisasi LCD
    rcall lcd_init

    ldi sys_state, ST_LOCKED
    sei                     

fsm_loop:
    cpi sys_state, ST_LOCKED
    brne chk_stop
    rjmp handle_locked
chk_stop:
    cpi sys_state, ST_STOP
    brne chk_drive
    rjmp handle_stop
chk_drive:
    cpi sys_state, ST_DRIVE
    brne chk_brake
    rjmp handle_drive
chk_brake:
    cpi sys_state, ST_BRAKE
    brne loop_end
    rjmp handle_brake
loop_end:
    rjmp fsm_loop

// STATE 0: Terkunci (Cek RFID)
handle_locked:
    cpi prev_state, ST_LOCKED
    breq hl_skip_print          
    ldi r16, ST_LOCKED
    mov prev_state, r16         
    
    // UART
    ldi ZH, hi8(msg_locked)
    ldi ZL, lo8(msg_locked)
    rcall uart_send_string
    
    // LCD
    rcall lcd_clear
    ldi ZH, hi8(lcd_msg_locked)
    ldi ZL, lo8(lcd_msg_locked)
    rcall lcd_print_string

hl_skip_print:
    cbi PORTB, IND_PIN
    cbi PORTD, BLINK_PIN      
    rcall set_servo_zero    
    rcall check_card_present
    cpi r24, 0

    brne hl_card_detected
    rjmp fsm_loop       

hl_card_detected:   
    rcall read_card_uid

    ldi ZH, hi8(msg_uid)
    ldi ZL, lo8(msg_uid)
    rcall uart_send_string
    mov r24, r2
    rcall uart_send_number
    ldi r24, '-'
    rcall uart_send
    mov r24, r3
    rcall uart_send_number
    ldi r24, '-'
    rcall uart_send
    mov r24, r4
    rcall uart_send_number
    ldi r24, '-'
    rcall uart_send
    mov r24, r5
    rcall uart_send_number
    rcall uart_send_newline

    rcall authenticate_uid
    cpi r24, 1
    brne wait_lepas_1
    
    ldi sys_state, ST_STOP

init_lepas_1:
    ldi r25, 20
wait_lepas_1:               
    rcall delay_rfid
    rcall check_card_present
    cpi r24, 0
    brne init_lepas_1

    dec r25
    brne wait_lepas_1

    rcall delay_1sec
    rjmp fsm_loop

// STATE 1: Mesin Mati (Bisa jalan jika ditekan tombol, atau kunci lagi)
handle_stop:
    cpi prev_state, ST_STOP
    breq hs_skip_print
    ldi r16, ST_STOP
    mov prev_state, r16
    
    ldi ZH, hi8(msg_unlocked)
    ldi ZL, lo8(msg_unlocked)
    rcall uart_send_string
    
    rcall lcd_clear
    ldi ZH, hi8(lcd_msg_stop1)
    ldi ZL, lo8(lcd_msg_stop1)
    rcall lcd_print_string
    
    ldi r24, 0
    ldi r25, 1
    rcall lcd_set_cursor
    ldi ZH, hi8(lcd_msg_stop2)
    ldi ZL, lo8(lcd_msg_stop2)
    rcall lcd_print_string

hs_skip_print:
    sbi PORTB, IND_PIN
    sbi PORTD, BLINK_PIN      
    rcall set_servo_zero
    
    rcall check_card_present
    cpi r24, 0

    brne hs_card_detected
    rjmp fsm_loop

hs_card_detected:
    rcall read_card_uid

    ldi ZH, hi8(msg_uid)
    ldi ZL, lo8(msg_uid)
    rcall uart_send_string
    mov r24, r2
    rcall uart_send_number
    ldi r24, '-'
    rcall uart_send
    mov r24, r3
    rcall uart_send_number
    ldi r24, '-'
    rcall uart_send
    mov r24, r4
    rcall uart_send_number
    ldi r24, '-'
    rcall uart_send
    mov r24, r5
    rcall uart_send_number
    rcall uart_send_newline

    rcall authenticate_uid
    cpi r24, 1
    brne wait_lepas_2
    
    ldi sys_state, ST_LOCKED

init_lepas_2:
    ldi r25, 20
wait_lepas_2:               
    rcall delay_rfid
    rcall check_card_present
    cpi r24, 0
    brne init_lepas_2

    dec r25
    brne wait_lepas_2

    rcall delay_1sec
    rjmp fsm_loop

// STATE 2: Berkendara (Baca ADC, Hitung Arithmetic, Update PWM)
handle_drive:
    cpi prev_state, ST_DRIVE
    breq hd_skip_print
    ldi r16, ST_DRIVE
    mov prev_state, r16
    
    ldi ZH, hi8(msg_drive)
    ldi ZL, lo8(msg_drive)
    rcall uart_send_string
    
    rcall lcd_clear
    ldi ZH, hi8(lcd_msg_drive)
    ldi ZL, lo8(lcd_msg_drive)
    rcall lcd_print_string

hd_skip_print:
    cbi PORTD, BLINK_PIN
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

    inc print_tmr
    brne check_safety       
    
    ldi ZH, hi8(msg_speed)
    ldi ZL, lo8(msg_speed)
    rcall uart_send_string  
    mov r24, speed_val
    rcall uart_send_number  
    rcall uart_send_newline 
    
    ldi r24, 0
    ldi r25, 1
    rcall lcd_set_cursor
    ldi ZH, hi8(lcd_msg_speed)
    ldi ZL, lo8(lcd_msg_speed)
    rcall lcd_print_string
    mov r24, speed_val
    rcall lcd_print_number
    ldi r24, ' '
    rcall lcd_data
    rcall lcd_data

check_safety:
    cpi speed_val, 200      // Jika gas >= 200, nyalakan safety measure    
    brsh trigger_brake

    rjmp fsm_loop

trigger_brake:
    ldi sys_state, ST_BRAKE
    rjmp fsm_loop

// STATE 3: Pengereman Darurat (Auto Override & LCD Warning)
handle_brake:
    cpi prev_state, ST_BRAKE
    breq hb_gradual_start
    
    ldi r16, ST_BRAKE
    mov prev_state, r16
    
    ldi ZH, hi8(msg_brake)
    ldi ZL, lo8(msg_brake)
    rcall uart_send_string
    
    rcall lcd_clear
    ldi ZH, hi8(lcd_msg_warn1)
    ldi ZL, lo8(lcd_msg_warn1)
    rcall lcd_print_string
    ldi r24, 0
    ldi r25, 1
    rcall lcd_set_cursor
    ldi ZH, hi8(lcd_msg_warn2)
    ldi ZL, lo8(lcd_msg_warn2)
    rcall lcd_print_string

hb_gradual_start:
    cpi speed_val, 50
    brlo end_braking        // Jika speed_val < 50, berhenti brake

    subi speed_val, 3       

    mov r16, speed_val
    ldi r17, 250
    add r16, r17            
    clr r17
    adc r17, r17            
    sts OCR1AH, r17
    sts OCR1AL, r16

    ldi ZH, hi8(msg_speed)
    ldi ZL, lo8(msg_speed)
    rcall uart_send_string  
    mov r24, speed_val
    rcall uart_send_number  
    rcall uart_send_newline

    rcall delay_debounce    

    rjmp fsm_loop           

end_braking:
    rcall delay_1sec
    ldi sys_state, ST_DRIVE
    rjmp fsm_loop



// DRIVER I2C & LCD 1602 PCF8574

i2c_start:
    ldi r16, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
    sts TWCR, r16
wait_i2c_start:
    lds r16, TWCR
    sbrs r16, TWINT
    rjmp wait_i2c_start
    ret

i2c_stop:
    ldi r16, (1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
    sts TWCR, r16
    ret

i2c_write:
    sts TWDR, r24
    ldi r16, (1<<TWINT)|(1<<TWEN)
    sts TWCR, r16
wait_i2c_write:
    lds r16, TWCR
    sbrs r16, TWINT
    rjmp wait_i2c_write
    ret

i2c_transmit:
    push r24
    rcall i2c_start
    ldi r24, 0x4E
    rcall i2c_write
    pop r24
    rcall i2c_write
    rcall i2c_stop
    ret

lcd_send_nibble:
    push r24
    ori r24, 0x08
    rcall i2c_transmit
    rcall delay_lcd   

    pop r24
    push r24
    ori r24, 0x0C
    rcall i2c_transmit
    rcall delay_lcd   

    pop r24
    ori r24, 0x08
    rcall i2c_transmit
    rcall delay_lcd   
    ret

lcd_command:
    push r24
    andi r24, 0xF0
    rcall lcd_send_nibble
    pop r24
    swap r24
    andi r24, 0xF0
    rcall lcd_send_nibble
    rcall delay_lcd
    ret

lcd_data:
    push r24
    andi r24, 0xF0
    ori r24, 0x01
    rcall lcd_send_nibble
    pop r24
    swap r24
    andi r24, 0xF0
    ori r24, 0x01
    rcall lcd_send_nibble
    ret

lcd_init:
    rcall delay_1sec
    
    ldi r24, 0x30
    rcall lcd_send_nibble
    rcall delay_debounce
    
    ldi r24, 0x30
    rcall lcd_send_nibble
    rcall delay_debounce
    
    ldi r24, 0x30
    rcall lcd_send_nibble
    rcall delay_debounce
    
    ldi r24, 0x20
    rcall lcd_send_nibble
    rcall delay_debounce
    
    ldi r24, 0x28
    rcall lcd_command
    ldi r24, 0x0C          // Nyalakan layar, matikan kursor
    rcall lcd_command
    ldi r24, 0x06          // Auto-increment kursor dari kiri ke kanan
    rcall lcd_command
    ldi r24, 0x01          // Bersihkan sisa memori layar
    rcall lcd_command
    
    rcall delay_1sec       
    ret

lcd_clear:
    ldi r24, 0x01
    rcall lcd_command
    rcall delay_debounce
    ret

lcd_set_cursor:
    cpi r25, 0
    breq lsc_row0
    ldi r25, 0x40
    add r24, r25
lsc_row0:
    ori r24, 0x80
    rcall lcd_command
    ret

lcd_print_string:
lps_loop:
    lpm r24, Z+
    cpi r24, 0
    breq lps_done
    rcall lcd_data
    rjmp lps_loop
lps_done:
    ret

lcd_print_number:
    push r24
    push r25
    
    ldi r25, '0'-1          
lcd_get_100:
    inc r25
    subi r24, 100
    brcc lcd_get_100
    subi r24, -100
    push r24
    mov r24, r25
    rcall lcd_data
    
    pop r24
    ldi r25, '0'-1          
lcd_get_10:
    inc r25
    subi r24, 10
    brcc lcd_get_10
    subi r24, -10
    push r24
    mov r24, r25
    rcall lcd_data
    
    pop r24
    ldi r25, '0'            
    add r24, r25
    rcall lcd_data
    
    pop r25
    pop r24
    ret

// ============================================
// DRIVER SERIAL UART

uart_send:
    lds r16, UCSR0A
    sbrs r16, UDRE0         
    rjmp uart_send
    sts UDR0, r24           
    ret

uart_send_string:
    push r24
    push ZH
    push ZL
us_loop:
    lpm r24, Z+             
    cpi r24, 0              
    breq us_done
    rcall uart_send
    rjmp us_loop
us_done:
    pop ZL
    pop ZH
    pop r24
    ret

uart_send_newline:
    ldi r24, 13             
    rcall uart_send
    ldi r24, 10             
    rcall uart_send
    ret

uart_send_number:
    push r24
    push r25
    ldi r25, '0'-1          
get_100:
    inc r25
    subi r24, 100
    brcc get_100
    subi r24, -100
    push r24
    mov r24, r25
    rcall uart_send
    pop r24
    ldi r25, '0'-1          
get_10:
    inc r25
    subi r24, 10
    brcc get_10
    subi r24, -10
    push r24
    mov r24, r25
    rcall uart_send
    pop r24
    ldi r25, '0'            
    add r24, r25
    rcall uart_send
    pop r25
    pop r24
    ret

// Arithmetic & Actuator

set_servo_zero:
    ldi r16, 0x00
    sts OCR1AH, r16
    ldi r16, 250
    sts OCR1AL, r16
    ret

// UID yang diizinkan adalah 1:3:4:0 (dalam desimal), di simulasi Wokwi UID ini adalah Blue Card.
// Dalam simulasi dunia nyatanya, kita ganti UID ini dengan UID yang terdaftar pada kartu yang kita pegang
authenticate_uid:
    ldi r24, 0
    
    ldi r16, 1      // 57
    cp r2, r16
    brne auth_fail
    ldi r16, 3      // 55
    cp r3, r16
    brne auth_fail
    ldi r16, 4      // 99
    cp r4, r16
    brne auth_fail
    ldi r16, 0      // 18
    cp r5, r16
    brne auth_fail

    sbi PORTD, BUZZ_PIN
    rcall delay_100ms
    cbi PORTD, BUZZ_PIN
    
    ldi r24, 1
    ret 

auth_fail:
    ldi ZH, hi8(msg_deny)
    ldi ZL, lo8(msg_deny)
    rcall uart_send_string
    rcall uart_send_newline
    
    rcall lcd_clear
    ldi ZH, hi8(lcd_msg_deny)
    ldi ZL, lo8(lcd_msg_deny)
    rcall lcd_print_string

    sbi PORTD, BUZZ_PIN
    rcall delay_100ms
    rcall delay_100ms
    rcall delay_100ms
    cbi PORTD, BUZZ_PIN
    ret

check_card_present:
    ldi r24, 0x04
    ldi r22, 0x7F
    rcall rc522_write_reg

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
    
    rcall delay_rfid
    
    ldi r24, 0x0A 
    rcall rc522_read_reg 
    
    cpi r24, 2
    breq card_is_valid
    ldi r24, 0
    ret

read_card_uid:
    ldi r24, 0x04
    ldi r22, 0x7F
    rcall rc522_write_reg

    ldi r24, 0x0A
    ldi r22, 0x80
    rcall rc522_write_reg

    ldi r24, 0x09
    ldi r22, 0x93
    rcall rc522_write_reg
    ldi r24, 0x09
    ldi r22, 0x20
    rcall rc522_write_reg

    ldi r24, 0x0D
    ldi r22, 0x00
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

    rcall delay_rfid

    // Byte 1
    ldi r24, 0x09 
    rcall rc522_read_reg 
    mov r2, r24
    rcall delay_debounce

    // Byte 2
    ldi r24, 0x09 
    rcall rc522_read_reg 
    mov r3, r24
    rcall delay_debounce

    // Byte 3
    ldi r24, 0x09 
    rcall rc522_read_reg 
    mov r4, r24
    rcall delay_debounce

    // Byte 4
    ldi r24, 0x09 
    rcall rc522_read_reg 
    mov r5, r24
    
    ret

card_is_valid:
    ldi r24, 1
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

delay_100ms:
    push r20
    push r21
    push r22
    ldi r20, 8
d100_out:
    ldi r21, 255
d100_mid:
    ldi r22, 255
d100_in:
    dec r22
    brne d100_in
    dec r21
    brne d100_mid
    dec r20
    brne d100_out
    pop r22
    pop r21
    pop r20
    ret

delay_rfid:
    push r20
    push r21
    ldi r20, 20
dr_out:
    ldi r21, 255
dr_in:
    dec r21
    brne dr_in
    dec r20
    brne dr_out
    pop r21
    pop r20
    ret

delay_lcd:
    push r16
    ldi r16, 255
dl_loop:
    dec r16
    brne dl_loop
    pop r16
    ret

msg_uid:        .asciz "=> UID KARTU TERDETEKSI: "
msg_deny:       .asciz "=> ACCESS DENIED"
msg_locked:     .asciz "=> STATUS: SYSTEM LOCKED\r\n"
msg_unlocked:   .asciz "=> STATUS: UNLOCKED. (KLIK TOMBOL UNTUK START MESIN)\r\n"
msg_drive:      .asciz "=> ENGINE: STARTED! VROOM!\r\n"
msg_brake:      .asciz "=> WARNING: AUTO BRAKING ENGAGED!\r\n"
msg_speed:      .asciz "GAS VAL: "

lcd_msg_locked: .asciz "SYSTEM LOCKED"
lcd_msg_deny:   .asciz "ACCESS DENIED"
lcd_msg_stop1:  .asciz "ENGINE OFF"
lcd_msg_stop2:  .asciz "PRESS BTN START"
lcd_msg_drive:  .asciz "DRIVING MODE"
lcd_msg_speed:  .asciz "SPEED: "
lcd_msg_warn1:  .asciz "!! WARNING !!"
lcd_msg_warn2:  .asciz "AUTO BRAKING"