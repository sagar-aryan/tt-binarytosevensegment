/*
 * Copyright (c) 2024 Aryan
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_binary_to_bcd_7seg (
    input  wire [7:0] ui_in,    // Dedicated inputs - Binary[7:0]
    output wire [7:0] uo_out,   // Dedicated outputs - Cathode[6:0] + unused
    input  wire [7:0] uio_in,   // IOs: Input path - Binary[15:8]
    output wire [7:0] uio_out,  // IOs: Output path - Anode[7:0]
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock - 25MHz input
    input  wire       rst_n     // reset_n - low to reset
);

  // Configure uio pins as outputs for anode signals
  assign uio_oe = 8'b11111111;

  // Clock divider to generate ~1kHz from 25MHz
  // 25MHz / 25000 = 1kHz
  reg [14:0] clk_counter;
  reg clk_1khz;
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      clk_counter <= 15'd0;
      clk_1khz <= 1'b0;
    end else begin
      if (clk_counter == 15'd12499) begin  // Toggle every 12500 cycles for 1kHz
        clk_counter <= 15'd0;
        clk_1khz <= ~clk_1khz;
      end else begin
        clk_counter <= clk_counter + 1'b1;
      end
    end
  end

  // Invert reset for active-high reset modules
  wire reset;
  assign reset = ~rst_n;

  // Combine binary inputs from ui_in and uio_in
  wire [15:0] binary_input;
  assign binary_input = {uio_in[7:0], ui_in[7:0]};

  // Internal signals
  wire [6:0] cathode;
  wire [7:0] anode;

  // Instantiate the complete binary-to-BCD module
  complete u_complete (
    .cathode(cathode),
    .anode(anode),
    .binary(binary_input),
    .clk(clk_1khz),
    .reset(reset)
  );

  // Assign outputs according to Option 2
  assign uo_out[6:0] = cathode[6:0];  // Cathode segments a-g
  assign uo_out[7] = 1'b0;             // Unused
  assign uio_out[7:0] = anode[7:0];    // All 8 anodes

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

endmodule

// ============================================================================
// Sub-modules from design.v
// ============================================================================

module bcd_seven_segment(output reg [6:0]cathode, input [3:0]bcd);
  always @(*) begin
    cathode = 7'b1111111;
    case(bcd)
      4'd0: cathode = 7'b1000000;
      4'd1: cathode = 7'b1111001;
      4'd2: cathode = 7'b0100100;
      4'd3: cathode = 7'b0110000;
      4'd4: cathode = 7'b0011001;
      4'd5: cathode = 7'b0010010;
      4'd6: cathode = 7'b0000010;
      4'd7: cathode = 7'b1111000;
      4'd8: cathode = 7'b0000000;
      4'd9: cathode = 7'b0011000;
      default: cathode = 7'b1111111;
    endcase
  end
endmodule

module anode_decoder(output [7:0]anode, input [2:0]select_line);
  assign anode = ~(8'b1 << select_line);
endmodule

module multiplexer(output [3:0]bcd, input [31:0]bcd_sequence, input [2:0]select_line);
  assign bcd = bcd_sequence[select_line*4 +: 4];
endmodule

module refresh_counter(output reg [2:0]select_line, input clk, reset);
  always @(posedge clk or posedge reset) begin
    if (reset)
      select_line <= 3'b0;
    else begin
      select_line <= select_line + 1'b1;
    end
  end
endmodule

module binary_bcd(output reg [31:0]bcd, input [15:0]binary);
  integer i;
  always @(*) begin
    bcd = 32'b0;
    for (i = 15; i >= 0; i = i - 1) begin
      if (bcd[31:28] >= 5) bcd[31:28] = bcd[31:28] + 3;
      if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 3;
      if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 3;
      if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
      if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
      if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;
      if (bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;
      if (bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;  // Fixed bug: was bcd[3:4]
      bcd = bcd << 1;
      bcd[0] = binary[i];
    end
  end
endmodule

module complete(output [6:0]cathode, output [7:0]anode, input [15:0]binary, input clk, reset);
  wire [3:0] bcd;
  wire [31:0] bcd_sequence;
  wire [2:0] select_line;
  
  bcd_seven_segment a0(cathode, bcd);
  anode_decoder a1(anode, select_line);
  multiplexer a2(bcd, bcd_sequence, select_line);
  refresh_counter a3(select_line, clk, reset);
  binary_bcd a4(bcd_sequence, binary);
endmodule
