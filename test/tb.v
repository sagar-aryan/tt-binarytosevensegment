`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Dump waves
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // ---------------------------------------
  // Signals (UNCHANGED STRUCTURE)
  // ---------------------------------------
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;

  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // ---------------------------------------
  // DUT (FIXED NAME)
  // ---------------------------------------
  tt_um_i2c_display user_project (

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

  // ---------------------------------------
  // Clock
  // ---------------------------------------
  always #5 clk = ~clk;

  // ---------------------------------------
  // I2C EMULATION (ADDED)
  // ---------------------------------------

  reg sda_master;   // 1 = release, 0 = pull low
  reg scl_master;

  wire sda_line;

  // Open drain behavior
  assign sda_line = (sda_master == 0) ? 1'b0 :
                    (uio_oe[0] ? 1'b0 : 1'b1);

  always @(*) begin
    uio_in[0] = sda_line;
  end

  // SCL is input only
  always @(*) begin
    ui_in[0] = scl_master;
  end

  // ---------------------------------------
  // I2C TASKS (ADDED)
  // ---------------------------------------

  task i2c_start;
  begin
    sda_master = 1; #100;
    scl_master = 1; #100;
    sda_master = 0; #100;
    scl_master = 0; #100;
  end
  endtask

  task i2c_stop;
  begin
    sda_master = 0; #100;
    scl_master = 1; #100;
    sda_master = 1; #100;
  end
  endtask

  task i2c_write_byte;
    input [7:0] data;
    integer i;
  begin
    for (i = 7; i >= 0; i = i - 1) begin
      sda_master = data[i];
      #50;
      scl_master = 1; #100;
      scl_master = 0; #100;
    end

    // ACK cycle
    sda_master = 1;
    #50;
    scl_master = 1; #100;
    scl_master = 0; #100;
  end
  endtask

  // ---------------------------------------
  // TEST SEQUENCE (ADDED)
  // ---------------------------------------

  initial begin
    clk = 0;
    rst_n = 0;
    ena = 1;
    ui_in = 0;
    uio_in = 8'hFF;

    sda_master = 1;
    scl_master = 1;

    #200;
    rst_n = 1;

    #200;

    // Send I2C transaction
    i2c_start;

    i2c_write_byte(8'h68); // address (0x34 << 1)
    i2c_write_byte(8'h12);
    i2c_write_byte(8'h34);
    i2c_write_byte(8'h56);
    i2c_write_byte(8'h78);

    i2c_stop;

    #100000;

    $finish;
  end

endmodule
