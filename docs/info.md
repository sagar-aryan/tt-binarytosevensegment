## How it works

This project implements an I²C-controlled 8-digit 7-segment display driver.

An external I²C master (such as an ESP32 or microcontroller) sends data bytes to the chip. The design includes an I²C slave interface that receives serial data over the SDA line (with SCL as clock input). The received data is processed and displayed on a multiplexed 7-segment display.

Internal Working:
I²C Communication
The module acts as an I²C slave with a fixed address (0x34).
Incoming data is received byte-by-byte via SDA.
The design uses open-drain behavior for SDA.
Data Storage
Every 4 bytes received are combined into a 32-bit register.
Once 4 bytes are received, a data_valid signal is generated.
Binary to BCD Conversion
The 32-bit binary number is converted into BCD format using the shift-add-3 (double dabble) algorithm.
This produces 8 decimal digits for display.
Multiplexed Display Driving
A refresh counter continuously cycles through 8 digits.
A multiplexer selects the correct BCD digit.
A BCD-to-7-segment decoder converts the digit into segment signals.
Output Driving
Segment lines (cathodes) are driven through dedicated output pins.
Digit select lines (anodes) are driven using transistor-based switching.
Only one digit is active at a time (multiplexing), creating the illusion of a continuous display.
🧪 ## How to test
Required setup:
I²C master (ESP32 / Arduino / FPGA)
7-segment display (8-digit, multiplexed)
Pull-up resistors on SDA and SCL (typically 4.7kΩ)
Steps:
Power the design
Provide clock and reset signals.
Ensure pull-up resistors are connected to SDA and SCL.
Connect I²C master
SDA → chip SDA pin
SCL → chip SCL pin
Send data over I²C
Use slave address: 0x34
Send 4 bytes (32-bit data)

Example (ESP32 / Arduino pseudo-code):

Wire.beginTransmission(0x34);
Wire.write(0x12);
Wire.write(0x34);
Wire.write(0x56);
Wire.write(0x78);
Wire.endTransmission();
Observe output
The transmitted 32-bit value will be displayed as decimal digits on the 7-segment display.
The display continuously refreshes using multiplexing.
🔌 ## External hardware

The following external components are required:

1. 7-Segment Display
8-digit multiplexed 7-segment display
Common anode or common cathode depending on transistor configuration
2. Transistor Driver Circuit (IMPORTANT)
Required for driving digit anodes
Ensures sufficient current for LEDs

Recommended:

NPN transistors (e.g., BC547) or NMOS
Base resistor (~1kΩ–10kΩ)
3. Pull-up Resistors
SDA → 4.7kΩ to VCC
SCL → 4.7kΩ to VCC
4. I²C Master Device
ESP32 / Arduino / Raspberry Pi / FPGA
5. Power Supply
Typically 3.3V or 5V (depending on display and logic compatibility)
💡 Final Note

This design demonstrates:

I²C protocol handling
Serial-to-parallel data conversion
Binary-to-BCD conversion
Multiplexed display control under strict pin constraints
