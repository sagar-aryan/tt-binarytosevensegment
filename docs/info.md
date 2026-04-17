## How it works

This design implements a 16-bit binary to BCD (Binary-Coded Decimal) converter with an optimized 7-segment display driver. The goal is to minimize pin usage — driving 8 seven-segment displays with only 15 wires instead of the usual 56.

**Architecture:**
- **Input:** 16-bit unsigned binary value + 1 kHz clock + asynchronous reset
- **Binary-to-BCD conversion:** Uses the double-dabble algorithm to convert the 16-bit binary input into a 32-bit BCD representation (8 BCD digits, 4 bits each)
- **Multiplexed display:** A 31:4 multiplexer selects one BCD digit at a time
- **BCD-to-7-segment decoder:** Converts the selected 4-bit BCD digit into 7-segment cathode signals
- **Time-division multiplexing:** Cycles through all 8 digits rapidly using the 1 kHz clock, so only one digit is active at any moment

**Pin assignment:**
- 7 wires for cathode signals (shared across all 8 displays)
- 8 wires for anode control (one per digit, driving PNP transistors)
- Total: 15 I/O pins instead of 56

The displays are common-anode types with anodes tied together and controlled via PNP transistors. By rapidly cycling through digits (persistence of vision), all 8 digits appear continuously lit to the human eye.

## How to test

1. Connect 8 common-anode seven-segment displays via PNP transistor drivers
   - Wire cathodes (a-g) to the 7 cathode output pins (shared across all displays)
   - Wire each display's anode through a PNP transistor to one of the 8 anode control pins
2. Provide a 1 kHz clock input
3. Assert and release reset (`rst_n`)
4. Apply a 16-bit binary test value (e.g., `0x1234` = 4660 decimal)
5. Observe the decimal equivalent displayed across the 8 seven-segment digits

**Expected output:** The 16-bit binary input displayed as its decimal equivalent (0 to 65535) across 8 digits, with leading zeros shown or blanked depending on implementation.

## External hardware

- 8× common-anode seven-segment displays
- 8× PNP transistors (e.g., 2N3906 or equivalent) for anode switching
- Current-limiting resistors for cathode segments (typically 220Ω–330Ω per segment)
- Pull-up/pull-down resistors as needed for transistor base connections
