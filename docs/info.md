## How it works

The `uart_eight_driver` module implements a complete pipeline that receives serial data via UART, converts it into a numeric value, and displays it on an 8-digit seven-segment display.

The system operates in the following stages:

1. **UART Reception**
   Incoming serial data is received through the `rx` pin using the `uart_rx` module. The UART operates using a prescale value of 109, which corresponds to a 100 MHz clock and a baud rate of 115200.

2. **Data Accumulation**
   The received bytes are passed to the `uart_accumulator`, which collects 4 consecutive bytes to form a 32-bit number. The bytes are received in little-endian format (LSB first) and internally rearranged to form the correct 32-bit value.
   Once all 4 bytes are received, a `data_valid` signal is generated for one clock cycle.

3. **Data Latching**
   The `eight_driver` module captures the complete 32-bit value when `data_valid` is asserted. This ensures that the displayed value remains stable even if new data starts arriving.

4. **Binary to BCD Conversion**
   The latched binary number is converted into BCD format using the `binary_bcd_decoder`. This allows each decimal digit to be displayed independently.

5. **Multiplexed Display Control**
   The system uses a refresh counter and multiplexer to drive all 8 digits using time-multiplexing.

   * The `refresh_counter` cycles through digit positions
   * The `multiplexer` selects the corresponding BCD digit
   * The `bcd_decoder` converts it into seven-segment signals

6. **Acknowledgment Transmission**
   After receiving a complete 32-bit value, the system sends an acknowledgment byte (`0x06`) back through UART using the `tx` pin.

---

## How to test

1. **Simulation (Testbench)**

   * Use the provided testbench to simulate UART transmission.
   * Send 4 bytes representing a 32-bit number (LSB first).
   * Example: To send decimal 1234 → transmit `D2 04 00 00`.
   * Verify:

     * `data_valid` pulses after 4 bytes
     * Correct data reconstruction
     * UART acknowledgment (`0x06`) is transmitted

2. **Hardware Testing (FPGA)**

   * Program the FPGA with the design.
   * Connect a UART interface (USB-to-Serial or Arduino).
   * Send raw binary data (not ASCII).

   Example using Arduino:

   ```cpp
   uint32_t num = 1234;
   Serial.write((uint8_t*)&num, 4);
   ```

3. **Expected Behavior**

   * After sending 4 bytes, the number appears on the 7-segment display
   * The display remains stable until new valid data is received
   * An acknowledgment byte is sent back via UART

---

## External hardware

The following external hardware is required:

* **FPGA Development Board** (with 100 MHz clock)
* **8-digit Seven-Segment Display** (multiplexed)
* **UART Interface**

  * USB-to-Serial converter OR
  * Arduino / ESP32 (for sending test data)
* **Push Button** (used as reset input)

Optional:

* Logic analyzer or oscilloscope for debugging UART signals
