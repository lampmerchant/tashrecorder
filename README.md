# TashRecorder

## Elevator Pitch

It's an audio interface that can be switched between imitating the Farallon MacRecorder, an audio digitizer for vintage Macintosh computers without audio input, and the Apple MIDI Interface, a standard MIDI interface for the Macintosh.  It targets the PIC12F1501 (8 pins, ~$0.96) microcontroller.


## Technical Details

### Connections

```
                      .--------.
              Supply -|01 \/ 08|- Ground
       RxD- <--- RA5 -|02    07|- RA0 <--- MIDI/Audio In
       RxD+ <--- RA4 -|03    06|- RA1 ---> Clock Out
Mode Select ---> RA3 -|04    05|- RA2 ---> LED
                      '--------'
```

Mode Select floats high and selects audio digitizer mode by default; pulling it low selects MIDI interface mode.  The mode can be changed at any time.

The LED output is active high.


### Audio Digitizer Mode

In Audio Digitizer mode, the firmware imitates a Farallon MacRecorder, generating a clock of approximately 358 kHz (one tenth the NTSC color burst frequency), oversampling the input pin at a rate of approximately 44 kHz and transmitting 8-bit samples to the Macintosh at a rate of approximately 22 kHz.

The LED flashes on when the audio has peaked for a set number of consecutive samples (17 by default, changeable by editing the PEAKPWR parameter in firmware).


### MIDI Interface Mode

In MIDI Interface Mode, the firmware imitates the input of an Apple MIDI Interface, generating a 1 MHz clock (32 times the MIDI baud rate of 31250 Hz) and relaying the input pin's state directly to the RxD pins.  The MIDI input pin's state is inverted before being reflected by the RxD pins; this allows it to be connected directly to the output of an optocoupler such as the 6N138 with the addition of an external pullup resistor.

The LED flashes on when data is being received over the MIDI interface.


### Building Firmware

Building the firmware requires Microchip MPASM, which is included with their development environment, MPLAB.  Note that you **must** use MPLAB X version 5.35 or earlier or MPLAB 8 as later versions of MPLAB X have removed MPASM.
