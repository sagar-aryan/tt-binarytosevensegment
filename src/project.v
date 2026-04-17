/*
 * Copyright (c) 2024 Aryan Sagar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_binary_bcd (
    input  wire [7:0] ui_in,    // Dedicated inputs 
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire [15:0]binary_concat;
    wire rst_inv;
  // All output pins must be assigned. If not used, assign to 0.
  //binary_seven_segment_display(output [6:0]cathode,output [7:0]anode,input[15:0]binary,input clk, reset);
    assign  binary_concat={uio_in,ui_in};
    assign rst_inv=~rst_n;
    binary_seven_segment_display display_driver(uo_out[6:0],uio_out,binary_concat,clk,rst_inv);
    assign uo_out[7]=0;
    assign uio_oe=0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

endmodule


module bcd_seven_segment(output reg [6:0]cathode,input [3:0]bcd);
always@(*)
begin
cathode=7'b1111111;
case(bcd)
4'd0:cathode=7'b1000000;
4'd1:cathode=7'b1111001;
4'd2:cathode=7'b0100100;
4'd3:cathode=7'b0110000;
4'd4:cathode=7'b0011001;
4'd5:cathode=7'b0010010;
4'd6:cathode=7'b0000010;
4'd7:cathode=7'b1111000;
4'd8:cathode=7'b0000000;
4'd9:cathode=7'b0011000;
default:cathode=7'b1111111;
endcase
end
endmodule


module anode_decoder(output [7:0]anode,input [2:0]select_line);
assign anode=~(8'b1<<select_line);
endmodule

module multiplexer(output [3:0]bcd,input [31:0]bcd_sequence,input[2:0]select_line);
assign bcd = bcd_sequence[select_line*4+:4];
endmodule

module refresh_counter(output reg [2:0]select_line,input clk,reset);

always@(posedge clk or posedge reset)
begin
if(reset)
select_line<=3'b0;
else
begin
select_line<=select_line+3'b1;
end
end
endmodule

module binary_bcd(output reg [31:0]bcd ,input [15:0]binary);
integer i;
always@(*)
begin
bcd=32'b0;
for(i=15;i>=0;i=i-1)
begin
if(bcd[19:16]>=5) bcd[19:16]=bcd[19:16]+3;
if(bcd[15:12]>=5) bcd[15:12]=bcd[15:12]+3;
if(bcd[11:8]>=5) bcd[11:8]=bcd[11:8]+3;
if(bcd[7:4]>=5) bcd[7:4]=bcd[7:4]+3;
if(bcd[3:0]>=5) bcd[3:0]=bcd[3:0]+3;
bcd=bcd<<1;
bcd[0]=binary[i];
end
end
endmodule

module binary_seven_segment_display(output [6:0]cathode,output [7:0]anode,input[15:0]binary,input clk, reset);
wire [3:0]bcd;
wire [31:0]bcd_sequence;
wire [2:0]select_line;
//bcd_seven_segment(output reg [6:0]cathode,input [3:0]bcd);
bcd_seven_segment a0(cathode,bcd);
//anode_decoder(output [7:0]anode,input [2:0]select_line);
anode_decoder a1(anode,select_line);
//multiplexer(output [3:0]bcd,input [31:0]bcd_sequence,input[2:0]select_line);
multiplexer a2(bcd,bcd_sequence,select_line);
//refresh_counter(output reg [2:0]select_line,input clk,reset);
refresh_counter a3(select_line,clk,reset);
//binary_bcd(output reg [31:0]bcd ,input [15:0]binary);
binary_bcd a4(bcd_sequence,binary);
endmodule

