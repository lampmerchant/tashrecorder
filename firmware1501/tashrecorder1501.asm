;;; 80 characters wide please ;;;;;;;;;;;;;;;;;;;;;;;;;; 8-space tabs please ;;;


;
;;;
;;;;;  TashRecorder
;;;
;


;;; Connections ;;;

;;;                                                  ;;;
;                    .--------.                        ;
;            Supply -|01 \/ 08|- Ground                ;
;     RxD- <--- RA5 -|02    07|- RA0 <--- Audio In     ;
;     RxD+ <--- RA4 -|03    06|- RA1 ---> Clock Out    ;
;    !MCLR ---> RA3 -|04    05|- RA2 ---> Peak LED     ;
;                    '--------'                        ;
;                                                      ;
;    Peak LED is active high.                          ;
;                                                      ;
;;;                                                  ;;;


;;; Assembler Directives ;;;

	list		P=PIC12F1501, F=INHX32, ST=OFF, MM=OFF, R=DEC, X=ON
	#include	P12F1501.inc
	errorlevel	-302	;Suppress "register not in bank 0" messages
	errorlevel	-224	;Suppress TRIS instruction not recommended msgs
	__config	_CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_OFF & _BOREN_OFF & _CLKOUTEN_OFF
			;_FOSC_INTOSC	Internal oscillator, I/O on RA5
			;_WDTE_OFF	Watchdog timer disabled
			;_PWRTE_ON	Keep in reset for 64 ms on start
			;_MCLRE_ON	RA3/!MCLR is !MCLR
			;_CP_OFF	Code protection off
			;_BOREN_OFF	Brownout reset off
			;_CLKOUTEN_OFF	CLKOUT disabled, I/O on RA4
	__config	_CONFIG2, _WRT_OFF & _STVREN_ON & _BORV_LO & _LPBOR_OFF &_LVP_OFF
			;_WRT_OFF	Write protection off
			;_STVREN_ON	Stack over/underflow causes reset
			;_BORV_LO	Brownout reset voltage low trip point
			;_LPBOR_OFF	Low power brownout reset disabled
			;_LVP_OFF	High-voltage on Vpp to program


;;; Macros ;;;

DELAY	macro	value		;Delay 3*W cycles, set W to 0
	movlw	value
	decfsz	WREG,F
	bra	$-1
	endm

DNOP	macro
	bra	$+1
	endm

WAITLAT	macro			;Wait until bit has been latched (BSR must be 0)
	btfss	PIR2,NCO1IF
	bra	$-1
	bcf	PIR2,NCO1IF
	endm


;;; Constants ;;;

;Pin Assignments
LED_PIN	equ	RA2	;Peak LED pin

;Parameters
PEAKPWR	equ	4	;2^n + 1 consecutive samples must peak to turn LED on


;;; Variable Storage ;;;

	cblock	0x70	;Bank-common registers
	
	FLAGS	;You've got to have flags
	SAMPLE	;Next sample to be clocked out
	PEAKCNT	;Counter for number of consecutive samples that have peaked
	X12
	X11
	X10
	X9
	X8
	X7
	X6
	X5
	X4
	X3
	X2
	X1
	X0
	
	endc


;;; Vectors ;;;

	org	0x0		;Reset vector
	goto	Init

	org	0x4		;Interrupt vector
	;fall through


;;; Interrupt Handler ;;;

Interrupt
	bra	$


;;; Hardware Initialization ;;;

Init
	banksel	OSCCON		;16 MHz high-freq internal oscillator
	movlw	B'01111000'
	movwf	OSCCON

	banksel	ADCON0		;ADC on, left justified, Fosc/32, Vref is Vdd,
	movlw	B'00100000'	; source AN0, auto-triggered by Timer2 match
	movwf	ADCON1
	movlw	B'01010000'
	movwf	ADCON2
	movlw	B'00000001'
	movwf	ADCON0

	banksel	CLC1CON		;CLC1 is a DFF clocked by the NCO (its input is
	clrf	CLC1SEL0	; CLC1POL[1]), CLC2 inverts CLC1
	clrf	CLC1SEL1
	clrf	CLC1POL
	movlw	B'01000000'
	movwf	CLC1GLS0
	clrf	CLC1GLS1
	clrf	CLC1GLS2
	clrf	CLC1GLS3
	movlw	B'11000100'
	movwf	CLC1CON
	clrf	CLC2SEL0
	clrf	CLC2SEL1
	clrf	CLC2POL
	movlw	B'00010000'
	movwf	CLC2GLS0
	movwf	CLC2GLS1
	clrf	CLC2GLS2
	clrf	CLC2GLS3
	movlw	B'11000000'
	movwf	CLC2CON

	banksel	NCO1CON		;NCO accumulator increments by 23419 in pulse
	movlw	B'10000000'	; mode, resulting in a clock of approximately
	movwf	NCO1CLK		; 357956 Hz, which is pretty close to one tenth
	movlw	0x5B		; the NTSC color burst frequency, with a pulse
	movwf	NCO1INCH	; width of 16 clocks of the 16 MHz oscillator,
	movlw	0xA3		; interrupting on the rising edge
	movwf	NCO1INCL
	movlw	B'11000001'
	movwf	NCO1CON

	banksel	T1CON		;Timer1 ticks 1:8 with instruction clock when
	movlw	B'00110000'	; running
	movwf	T1CON

	banksel	T2CON		;Timer2 ticks with instruction clock, rolls over
	movlw	86		; at a little under half the sample loop length
	movwf	PR2
	movlw	B'00000100'
	movwf	T2CON

	banksel	APFCON		;Move CLC1 to RA4
	movlw	B'00000010'
	movwf	APFCON

	banksel	ANSELA		;AN0 (RA0) pin analog, all others digital
	movlw	B'00000001'
	movwf	ANSELA

	banksel	LATA		;Default state of output pins is high
	movlw	B'00111111'
	movwf	LATA

	banksel	TRISA		;RxD, clock, and peak LED output, all other pins
	movlw	B'00001001'	; inputs
	movwf	TRISA

	movlb	0		;Initialize key globals
	movlw	high ADRESH
	movwf	FSR0H
	movlw	low ADRESH
	movwf	FSR0L
	movlw	high CLC1POL
	movwf	FSR1H
	movlw	low CLC1POL
	movwf	FSR1L

	;fall through


;;; Mainline ;;;

Main
	movlw	0x80		;Load silence for first sample
	movwf	SAMPLE		; "
	bcf	PIR1,ADIF	;Wait until first ADC sample has been read
	btfss	PIR1,ADIF	; "
	bra	$-1		; "
	;fall through

SampleLoop
	WAITLAT			;Wait until last stop bit has been latched
	clrf	TMR2		;Reset Timer2 to keep in sync with NCO clock
	bcf	INDF1,1		;Load start bit
	nop			; -
	WAITLAT			;Wait until start bit has been latched
	btfsc	SAMPLE,7	;Load MSB of sample
	bsf	INDF1,1		; "
	movf	INDF0,W		;Grab first ADC sample
	WAITLAT			;Wait until MSB has been latched
	bcf	INDF1,1		;Load bit 6 of sample
	btfsc	SAMPLE,6	; "
	bsf	INDF1,1		; "
	WAITLAT			;Wait until bit 6 has been latched
	bcf	INDF1,1		;Load bit 5 of sample
	btfsc	SAMPLE,5	; "
	bsf	INDF1,1		; "
	WAITLAT			;Wait until bit 5 has been latched
	bcf	INDF1,1		;Load bit 4 of sample
	btfsc	SAMPLE,4	; "
	bsf	INDF1,1		; "
	WAITLAT			;Wait until bit 4 has been latched
	bcf	INDF1,1		;Load bit 3 of sample
	btfsc	SAMPLE,3	; "
	bsf	INDF1,1		; "
	WAITLAT			;Wait until bit 3 has been latched
	bcf	INDF1,1		;Load bit 2 of sample
	btfsc	SAMPLE,2	; "
	bsf	INDF1,1		; "
	WAITLAT			;Wait until bit 2 has been latched
	bcf	INDF1,1		;Load bit 1 of sample
	btfsc	SAMPLE,1	; "
	bsf	INDF1,1		; "
	WAITLAT			;Wait until bit 1 has been latched
	bcf	INDF1,1		;Load LSB of sample
	btfsc	SAMPLE,0	; "
	bsf	INDF1,1		; "
	WAITLAT			;Wait until LSB has been latched
	bsf	INDF1,1		;Load first stop bit
	addwf	INDF0,W		;Average first and second ADC sample, putting
	rrf	WREG,W		; the fraction bit into carry
	WAITLAT			;Wait until first stop bit has been latched
	movwf	SAMPLE		;Store averaged sample to transmit next
	nop			; -
	nop			; -
	WAITLAT			;Wait until second stop bit has been latched
	xorlw	B'11111111'	;Set Z if sample peaked (if it is 0xFF or 0x00),
	btfss	STATUS,Z	; else clear it
	xorlw	B'11111111'	; "
	WAITLAT			;Wait until third stop bit has been latched
	btfsc	STATUS,Z	;If sample peaked, skip ahead to deal with it
	bra	SamplePeaked	; "
	clrf	PEAKCNT		;Else clear the consecutive peak count
	WAITLAT			;Wait until fourth stop bit has been latched
	btfss	PIR1,TMR1IF	;If Timer1 hasn't overflowed, skip ahead to keep
	bra	KeepLedState	; the current state of the LED
	bcf	PORTA,LED_PIN	;If it has overflowed, turn the LED off
	WAITLAT			;Wait until fifth stop bit has been latched
	bcf	T1CON,TMR1ON	;Stop and clear Timer1
	clrf	TMR1L		; "
	clrf	TMR1H		; "
	WAITLAT			;Wait until sixth stop bit has been latched
	bcf	PIR1,TMR1IF	;Clear Timer1's interrupt flag
	bra	SampleLoop	;Loop

SamplePeaked
	WAITLAT			;Wait until fourth stop bit has been latched
	btfss	PEAKCNT,PEAKPWR	;If we haven't got the requisite number of
	bra	NoLedYet	; consecutive peaked samples yet, skip ahead
	bsf	PORTA,LED_PIN	;If we have, turn the LED on
	WAITLAT			;Wait until fifth stop bit has been latched
	clrf	TMR1L		;Clear and start Timer1 to keep the LED on long
	clrf	TMR1H		; enough that it can be seen (~131 ms)
	bsf	T1CON,TMR1ON	; "
	WAITLAT			;Wait until sixth stop bit has been latched
	bcf	PIR1,TMR1IF	;Clear Timer1's interrupt flag
	bra	SampleLoop	;Loop

NoLedYet
	WAITLAT			;Wait until fifth stop bit has been latched
	nop			; -
	nop			; -
	nop			; -
	WAITLAT			;Wait until sixth stop bit has been latched
	incf	PEAKCNT,F	;Increment the consecutive peaked sample count
	bra	SampleLoop	;Loop

KeepLedState
	WAITLAT			;Wait until fifth stop bit has been latched
	nop			; -
	nop			; -
	nop			; -
	WAITLAT			;Wait until sixth stop bit has been latched
	nop			; -
	bra	SampleLoop	;Loop


;;; Lookup Tables ;;;

	org	0x100

;Test tone: five periods of a sine wave of just under 440 Hz (concert A)
;(currently unused)
Tone
	dt	0x80,0x8F,0x9E,0xAD,0xBB,0xC9,0xD5,0xE0
	dt	0xE9,0xF1,0xF7,0xFB,0xFE,0xFE,0xFD,0xFA
	dt	0xF5,0xEE,0xE6,0xDB,0xD0,0xC3,0xB6,0xA7
	dt	0x98,0x89,0x79,0x6A,0x5B,0x4C,0x3E,0x31
	dt	0x26,0x1B,0x13,0x0B,0x06,0x02,0x01,0x01
	dt	0x03,0x07,0x0D,0x14,0x1D,0x28,0x34,0x41
	dt	0x4F,0x5E,0x6D,0x7C,0x8C,0x9B,0xAA,0xB9
	dt	0xC6,0xD2,0xDE,0xE7,0xF0,0xF6,0xFB,0xFE
	dt	0xFF,0xFE,0xFB,0xF6,0xF0,0xE7,0xDE,0xD2
	dt	0xC6,0xB9,0xAA,0x9B,0x8C,0x7C,0x6D,0x5E
	dt	0x4F,0x41,0x34,0x28,0x1D,0x14,0x0D,0x07
	dt	0x03,0x01,0x01,0x02,0x06,0x0B,0x13,0x1B
	dt	0x26,0x31,0x3E,0x4C,0x5B,0x6A,0x79,0x89
	dt	0x98,0xA7,0xB6,0xC3,0xD0,0xDB,0xE6,0xEE
	dt	0xF5,0xFA,0xFD,0xFE,0xFE,0xFB,0xF7,0xF1
	dt	0xE9,0xE0,0xD5,0xC9,0xBB,0xAD,0x9E,0x8F
	dt	0x80,0x70,0x61,0x52,0x44,0x36,0x2A,0x1F
	dt	0x16,0x0E,0x08,0x04,0x01,0x01,0x02,0x05
	dt	0x0A,0x11,0x19,0x24,0x2F,0x3C,0x49,0x58
	dt	0x67,0x76,0x86,0x95,0xA4,0xB3,0xC1,0xCE
	dt	0xD9,0xE4,0xEC,0xF4,0xF9,0xFD,0xFE,0xFE
	dt	0xFC,0xF8,0xF2,0xEB,0xE2,0xD7,0xCB,0xBE
	dt	0xB0,0xA1,0x92,0x83,0x73,0x64,0x55,0x46
	dt	0x39,0x2D,0x21,0x18,0x0F,0x09,0x04,0x01
	dt	0x01,0x01,0x04,0x09,0x0F,0x18,0x21,0x2D
	dt	0x39,0x46,0x55,0x64,0x73,0x83,0x92,0xA1
	dt	0xB0,0xBE,0xCB,0xD7,0xE2,0xEB,0xF2,0xF8
	dt	0xFC,0xFE,0xFE,0xFD,0xF9,0xF4,0xEC,0xE4
	dt	0xD9,0xCE,0xC1,0xB3,0xA4,0x95,0x86,0x76
	dt	0x67,0x58,0x49,0x3C,0x2F,0x24,0x19,0x11
	dt	0x0A,0x05,0x02,0x01,0x01,0x04,0x08,0x0E
	dt	0x16,0x1F,0x2A,0x36,0x44,0x52,0x61,0x70


;;; End of Program ;;;
	end
