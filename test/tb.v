`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
that can be driven / tested by the cocotb test.py.
*/
module tb ();

// Dump the signals to a FST file. You can view it with gtkwave or surfer.
initial begin
$dumpfile("tb.fst");
$dumpvars(0, tb);
#1;
end

// ================= SIGNALS =================
reg clk;
reg rst_n;
reg ena;

reg  [7:0] ui_in;    // rx on ui_in[0]
reg  [7:0] uio_in;

wire [7:0] uo_out;   // tx on uo_out[0]
wire [7:0] uio_out;  // anode
wire [7:0] uio_oe;

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

// ================= DUT =================
tt_um_uart_8digit user_project (

`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

```
  .ui_in  (ui_in),    // rx = ui_in[0]
  .uo_out (uo_out),   // tx = uo_out[0], cathode = [7:1]
  .uio_in (uio_in),
  .uio_out(uio_out),  // anode
  .uio_oe (uio_oe),
  .ena    (ena),
  .clk    (clk),
  .rst_n  (rst_n)
```

);

// ================= CLOCK =================
initial clk = 0;
always #5 clk = ~clk;   // 100 MHz

// ================= INIT =================
initial begin
ena   = 1;
rst_n = 0;
ui_in = 8'hFF;   // idle UART high
uio_in = 8'h00;

```
#100;
rst_n = 1;
```

end

endmodule
