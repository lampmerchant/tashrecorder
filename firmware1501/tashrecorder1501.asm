;;; 80 characters wide please ;;;;;;;;;;;;;;;;;;;;;;;;;; 8-space tabs please ;;;


;
;;;
;;;;;  TashRecorder
;;;
;


;;; Connections ;;;

;;;                                                            ;;;
;                          .--------.                            ;
;                  Supply -|01 \/ 08|- Ground                    ;
;           RxD- <--- RA5 -|02    07|- RA0 <--- MIDI/Audio In    ;
;           RxD+ <--- RA4 -|03    06|- RA1 ---> Clock Out        ;
;    Mode Select ---> RA3 -|04    05|- RA2 ---> LED              ;
;                          '--------'                            ;
;                                                                ;
;    LED is active high.  Mode Select is MIDI when pulled low    ;
;    and audio digitizer when allowed to float high.             ;
;                                                                ;
;;;                                                            ;;;


;;; Assembler Directives ;;;

	list		P=PIC12F1501, F=INHX32, ST=OFF, MM=OFF, R=DEC, X=ON
	#include	P12F1501.inc
	errorlevel	-302	;Suppress "register not in bank 0" messages
	errorlevel	-224	;Suppress TRIS instruction not recommended msgs
	__config	_CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_OFF & _BOREN_OFF & _CLKOUTEN_OFF
			;_FOSC_INTOSC	Internal oscillator, I/O on RA5
			;_WDTE_OFF	Watchdog timer disabled
			;_PWRTE_ON	Keep in reset for 64 ms on start
			;_MCLRE_OFF	RA3/!MCLR is RA3
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
INP_PIN	equ	RA0	;MIDI/audio pin
INP_ADC	equ	0 ;AN0	;Audio ADC input
LED_PIN	equ	RA2	;Peak LED pin
SEL_PIN	equ	RA3	;Mode select pin

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


;;; Common Hardware Initialization ;;;

Init
	banksel	OSCCON		;16 MHz high-freq internal oscillator
	movlw	B'01111000'
	movwf	OSCCON

	banksel	ADCON0		;ADC left justified, Fosc/32, Vref is Vdd,
	movlw	B'00100000'	; source AN0, auto-triggered by Timer2 match
	movwf	ADCON1
	movlw	B'01010000'
	movwf	ADCON2

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

	banksel	WPUA		;Weak pullup enabled on mode select only
	movlw	1 << SEL_PIN
	movwf	WPUA

	banksel	OPTION_REG	;Weak pullups enabled
	movlw	B'01111111'
	movwf	OPTION_REG

	banksel	LATA		;Default state of output pins is low
	clrf	LATA

	banksel	TRISA		;RxD, clock, and peak LED output, all other pins
	movlw	B'00001001'	; inputs
	movwf	TRISA

	movlw	high ADRESH	;Initialize key globals
	movwf	FSR0H
	movlw	low ADRESH
	movwf	FSR0L
	movlw	high CLC1POL
	movwf	FSR1H
	movlw	low CLC1POL
	movwf	FSR1L

	movlb	0		;Enter audio digitizer or MIDI initialization
	btfss	PORTA,SEL_PIN	; depending on whether mode select pin is high
	goto	MidiInit	; or low
	;fall through


;;; Audio Digitizer Hardware Initialization ;;;

AudioInit
	banksel	ADCON0		;Turn on ADC, source audio input pin
	movlw	B'00000001' | (INP_ADC << 2)
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

	banksel	ANSELA		;Audio input pin analog, all others digital
	movlw	1 << INP_PIN
	movwf	ANSELA

	;fall through


;;; Audio Mainline ;;;

AudioMain
	movlw	0x80		;Load silence for first sample
	movwf	SAMPLE		; "
	movlb	0		;Wait until first ADC sample has been read
	bcf	PIR1,ADIF	; "
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
	btfss	PORTA,SEL_PIN	;If we've been switched into MIDI mode, switch
	bra	MidiInit	; into MIDI mode
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


;;; MIDI Hardware Initialization ;;;

MidiInit
	banksel	ADCON0		;Turn off ADC
	clrf	ADCON0

	banksel	CLC1CON		;CLC2 inverts CLC2IN1 (RA0), CLC1 inverts CLC2,
	movlw	B'01010000'	; this along with an external pullup allows
	movwf	CLC1SEL0	; CLC2IN1 to be connected directly to the output
	clrf	CLC1SEL1	; of a MIDI optocoupler such as the 6N138
	clrf	CLC1POL
	movlw	B'00000100'
	movwf	CLC1GLS0
	movwf	CLC1GLS1
	clrf	CLC1GLS2
	clrf	CLC1GLS3
	movlw	B'11001000'
	movwf	CLC1CON
	movlw	B'00000001'
	movwf	CLC2SEL0
	clrf	CLC2SEL1
	clrf	CLC2POL
	movwf	CLC2GLS0
	movwf	CLC2GLS1
	clrf	CLC2GLS2
	clrf	CLC2GLS3
	movlw	B'11000000'
	movwf	CLC2CON

	banksel	NCO1CON		;NCO accumulator increments by 0xFFFF in pulse
	movlw	B'01100000'	; mode with a pulse width of 8 16 MHz clock
	movwf	NCO1CLK		; periods, resulting in a clock of approximately
	movlw	0xFF		; 1 MHz, which is 32 times the MIDI baud rate of
	movwf	NCO1INCH	; 31250 Hz and matches the clock used by the
	movwf	NCO1INCL	; Apple MIDI interface
	movlw	B'11000001'
	movwf	NCO1CON

	banksel	ANSELA		;All pins digital, not analog
	clrf	ANSELA

	;fall through


;;; MIDI Mainline ;;;

MidiMain
	movlb	0		;Turn Timer1 on
	bsf	T1CON,TMR1ON	; "
	;fall through

MidiLoop
	btfsc	PIR1,TMR1IF	;If Timer1 has overflowed, turn the LED off
	bcf	PORTA,LED_PIN	; "
	btfsc	PORTA,SEL_PIN	;If we've been switched into audio digitizer
	bra	AudioInit	; mode, switch into audio digitizer mode
	btfss	PIR3,CLC1IF	;If MIDI line has gone low (activity), continue,
	bra	MidiLoop	; else loop around
	bcf	PIR3,CLC1IF	;Clear the interrupt
	bsf	PORTA,LED_PIN	;Turn LED on to indicate activity
	clrf	TMR1L		;Reset Timer1 so it can be used to turn the LED
	clrf	TMR1H		; off after it's been on long enough to see
	bcf	PIR1,TMR1IF	; "
	bra	MidiLoop	;Loop


;;; End of Program ;;;
	end
