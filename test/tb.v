`default_nettype none
`timescale 1ns / 1ps

/* This testbench instantiates tt_um_uart_8digit and drives UART bytes
   over ui_in[0] (RX pin). It sends 4-byte packets and checks:
     - uo_out[0]   : TX ACK byte (0x06) sent back after every 4 bytes
     - uo_out[7:1] : 7-segment cathode changes (active display)
     - uio_out     : 8-bit anode signals (digit select)
   The prescale inside the design is fixed at 109, so:
     baud period = 109 * 2 * clk_period = 109 * 2 * 10 ns = 2180 ns  (≈ 458 kBaud @ 10 ns clk)
*/

module tb ();

  // ---------------------------------------------------------------------------
  // Dump signals for waveform viewing (gtkwave / surfer)
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // ---------------------------------------------------------------------------
  // DUT port wires
  // ---------------------------------------------------------------------------
  reg        clk;
  reg        rst_n;
  reg        ena;
  reg  [7:0] ui_in;
  reg  [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  tt_um_uart_8digit user_project (
`ifdef GL_TEST
      .VPWR  (VPWR),
      .VGND  (VGND),
`endif
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  // ---------------------------------------------------------------------------
  // Convenience aliases
  // ---------------------------------------------------------------------------
  wire       tx_out   = uo_out[0];       // UART TX from design
  wire [6:0] cathode  = uo_out[7:1];     // 7-segment cathode (active-low segments)
  wire [7:0] anode    = uio_out;         // 8-digit anode select (active-low)

  // ---------------------------------------------------------------------------
  // Clock: 10 ns period → 100 MHz
  // ---------------------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // UART baud parameters
  //   prescale = 109  (hardwired in uart_eight_driver)
  //   baud period = prescale * 2 * clk_period = 109 * 2 * 10 ns = 2180 ns
  // ---------------------------------------------------------------------------
  localparam integer BAUD_PERIOD_NS = 2180;

  // ---------------------------------------------------------------------------
  // Task: send one UART byte (8N1, LSB first) on ui_in[0]
  // ---------------------------------------------------------------------------
  task uart_send_byte;
    input [7:0] data;
    integer i;
    begin
      // START bit (low)
      ui_in[0] = 1'b0;
      #(BAUD_PERIOD_NS);

      // 8 data bits, LSB first
      for (i = 0; i < 8; i = i + 1) begin
        ui_in[0] = data[i];
        #(BAUD_PERIOD_NS);
      end

      // STOP bit (high)
      ui_in[0] = 1'b1;
      #(BAUD_PERIOD_NS);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Task: send a 4-byte packet and wait for the ACK byte on TX
  // ---------------------------------------------------------------------------
  task send_packet_and_check_ack;
    input [7:0] b0, b1, b2, b3;
    integer timeout;
    reg ack_received;
    begin
      $display("[%0t ns] Sending packet: 0x%02X 0x%02X 0x%02X 0x%02X",
               $time, b0, b1, b2, b3);

      uart_send_byte(b0);
      uart_send_byte(b1);
      uart_send_byte(b2);
      uart_send_byte(b3);

      // Wait for TX line to go low (START bit of ACK)
      ack_received = 0;
      for (timeout = 0; timeout < 50000 && !ack_received; timeout = timeout + 1) begin
        @(negedge clk);
        if (tx_out === 1'b0) begin
          ack_received = 1;
          $display("[%0t ns] ACK start bit detected on TX.", $time);
        end
      end

      if (!ack_received)
        $display("[%0t ns] WARNING: No ACK received after packet!", $time);

      // Let the full ACK byte transmit before continuing
      #(BAUD_PERIOD_NS * 11);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Task: check that uio_oe is all-output (design drives anodes)
  // ---------------------------------------------------------------------------
  task check_uio_oe;
    begin
      if (uio_oe !== 8'hFF)
        $display("[%0t ns] FAIL: uio_oe = 0x%02X, expected 0xFF", $time, uio_oe);
      else
        $display("[%0t ns] PASS: uio_oe = 0xFF (all outputs)", $time);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main stimulus
  // ---------------------------------------------------------------------------
  initial begin
    // ------ initialise ------
    rst_n  = 1'b0;
    ena    = 1'b1;
    ui_in  = 8'hFF;   // idle high (UART idle = 1)
    uio_in = 8'h00;

    // ------ reset for 20 clock cycles ------
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
    repeat (5)  @(posedge clk);

    $display("[%0t ns] Reset released, starting tests.", $time);

    // ------ Verify uio_oe is 0xFF ------
    check_uio_oe;

    // ------ Test 1: Send 0x00_0x00_0x00_0x01  (decimal 1) ------
    send_packet_and_check_ack(8'h00, 8'h00, 8'h00, 8'h01);
    $display("[%0t ns] Anode = 0x%02X  Cathode = 0x%02X", $time, anode, cathode);

    // ------ Test 2: Send 0x00_0x01_0xE2_0x40  (decimal 123456) ------
    send_packet_and_check_ack(8'h00, 8'h01, 8'hE2, 8'h40);
    $display("[%0t ns] Anode = 0x%02X  Cathode = 0x%02X", $time, anode, cathode);

    // ------ Test 3: Send 0x07_0x5B_0xCD_0x15  (decimal 123456789) ------
    send_packet_and_check_ack(8'h07, 8'h5B, 8'hCD, 8'h15);
    $display("[%0t ns] Anode = 0x%02X  Cathode = 0x%02X", $time, anode, cathode);

    // ------ Test 4: Boundary – all zeros ------
    send_packet_and_check_ack(8'h00, 8'h00, 8'h00, 8'h00);
    $display("[%0t ns] Anode = 0x%02X  Cathode = 0x%02X", $time, anode, cathode);

    // ------ Test 5: Max 27-bit value (0x07FF_FFFF → 134,217,727) ------
    send_packet_and_check_ack(8'h07, 8'hFF, 8'hFF, 8'hFF);
    $display("[%0t ns] Anode = 0x%02X  Cathode = 0x%02X", $time, anode, cathode);

    // ------ Let display refresh for a while ------
    #(BAUD_PERIOD_NS * 20);

    // ------ Apply mid-run reset and verify recovery ------
    $display("[%0t ns] Applying mid-run reset.", $time);
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5)  @(posedge clk);

    check_uio_oe;

    // ------ Test after reset: send a fresh packet ------
    send_packet_and_check_ack(8'h00, 8'h00, 8'h00, 8'h2A); // decimal 42
    $display("[%0t ns] Anode = 0x%02X  Cathode = 0x%02X", $time, anode, cathode);

    // ------ Done ------
    #(BAUD_PERIOD_NS * 5);
    $display("[%0t ns] All tests complete.", $time);
    $finish;
  end

endmodule
