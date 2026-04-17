`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Dump waveform
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Inputs
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;

  // Outputs
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // 👉 Replace this with your actual module name if different
  tt_um_example user_project (

`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
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

  // ✅ Clock generation (100 MHz)
  initial clk = 0;
  always #5 clk = ~clk;

  // ✅ Stimulus block
  initial begin
    // Initialize everything
    rst_n  = 0;
    ena    = 0;
    ui_in  = 8'd0;
    uio_in = 8'd0;

    // Apply reset
    #20;
    rst_n = 1;
    ena   = 1;

    // ======================
    // TEST CASES
    // ======================

    // Test 1
    #10;
    ui_in = 8'h12;

    // Test 2
    #10;
    ui_in = 8'h34;

    // Test 3
    #10;
    ui_in = 8'hAB;

    // Test 4
    #10;
    ui_in = 8'hFF;

    // If using uio_in (buttons / control)
    #10;
    uio_in = 8'h01;

    #10;
    uio_in = 8'h02;

    // Wait and finish
    #50;
    $finish;
  end

endmodule
