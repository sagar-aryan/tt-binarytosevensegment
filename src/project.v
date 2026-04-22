/*
 * Copyright (c) 2024 Aryan Sagar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_uart_8digit (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
    /*uart_eight_driver(
                        output [6:0]cathode,
                        output [7:0]anode,
                        output tx,
                        input rx,
                        input clk,
                        input reset
                        );*/
    wire rst;
    assign rst=~rst_n;
    uart_eight_driver tinytapeout(.cathode(u0_out[7:1]),
                                  .anode(uio_out),
                                  .tx(uo_out[0]),
                                  .rx(ui_in[0]),
                                  .clk(clk),
                                  .reset(rst)
                                 );
  
  assign uio_oe=8'b11111111;
  // List all unused inputs to prevent warnings
    wire _unused = &{ena,ui_in,1'b0};

endmodule




module uart_accumulator #
(
    parameter DATA_WIDTH = 8
)
(
    input wire clk,
    input wire rst,

    input wire [DATA_WIDTH-1:0] rx_tdata,
    input wire rx_tvalid,
    output reg rx_tready,

    output reg [31:0] data_out,
    output reg data_valid
);

    reg [1:0] byte_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out   <= 0;
            data_valid <= 0;
            byte_count <= 0;
            rx_tready  <= 1;
        end else begin
            data_valid <= 0;

            if (rx_tvalid && rx_tready) begin
                data_out <= {rx_tdata, data_out[31:8]};
                byte_count <= byte_count + 1;

                if (byte_count == 3) begin
                    data_valid <= 1;
                    byte_count <= 0;
                end
            end
        end
    end

endmodule


module uart_accumulator_top #
(
    parameter DATA_WIDTH = 8
)
(
    input  wire clk,
    input  wire rst,

    // UART pins
    input  wire rxd,
    output wire txd,

    // Output data
    output wire [31:0] data_out,
    output wire        data_valid,

    // Config
    input  wire [15:0] prescale
);

// ================= RX SIDE =================
wire [DATA_WIDTH-1:0] rx_tdata;
wire                  rx_tvalid;
wire                  rx_tready;

uart_rx #(
    .DATA_WIDTH(DATA_WIDTH)
)
uart_rx_inst (
    .clk(clk),
    .rst(rst),

    .m_axis_tdata(rx_tdata),
    .m_axis_tvalid(rx_tvalid),
    .m_axis_tready(rx_tready),

    .rxd(rxd),

    .busy(),
    .overrun_error(),
    .frame_error(),

    .prescale(prescale)
);

// ================= ACCUMULATOR =================
wire acc_valid;

uart_accumulator #(
    .DATA_WIDTH(DATA_WIDTH)
)
acc_inst (
    .clk(clk),
    .rst(rst),

    .rx_tdata(rx_tdata),
    .rx_tvalid(rx_tvalid),
    .rx_tready(rx_tready),

    .data_out(data_out),
    .data_valid(acc_valid)
);

assign data_valid = acc_valid;

// ================= ACK LOGIC =================

// TX AXI signals
reg  [7:0] tx_tdata_reg;
reg        tx_tvalid_reg;
wire       tx_tready;

// ACK byte
localparam ACK = 8'h06;

// Simple FSM
reg sending_ack;

always @(posedge clk) begin
    if (rst) begin
        tx_tvalid_reg <= 0;
        tx_tdata_reg  <= 0;
        sending_ack   <= 0;
    end else begin
        // Default
        if (tx_tvalid_reg && tx_tready)
            tx_tvalid_reg <= 0;

        // Trigger ACK when 32-bit data is ready
        if (acc_valid && !sending_ack) begin
            tx_tdata_reg  <= ACK;
            tx_tvalid_reg <= 1;
            sending_ack   <= 1;
        end

        // Clear sending flag after send
        if (sending_ack && tx_tvalid_reg && tx_tready) begin
            sending_ack <= 0;
        end
    end
end

// ================= TX =================
uart_tx #(
    .DATA_WIDTH(DATA_WIDTH)
)
uart_tx_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata(tx_tdata_reg),
    .s_axis_tvalid(tx_tvalid_reg),
    .s_axis_tready(tx_tready),

    .txd(txd),

    .busy(),
    .prescale(prescale)
);

endmodule

module clock_divider(output clk_out, input clk_in,reset);
    reg [15:0]internal;
    assign clk_out = (internal == 16'hFFFF);
    always@(posedge clk_in or posedge reset)
        begin
            if(reset)
            internal<=16'b0;
            else
            internal<=internal+1;
        end
endmodule

module refresh_counter(output reg [2:0]select_lines,input clk_in, reset);
    wire clk_out;
    clock_divider a0(clk_out,clk_in,reset);
    always@(posedge clk_in or posedge reset)
        begin
            if(reset)
            select_lines<=3'b0;
            else if(clk_out)
            select_lines<=select_lines+1;
        end
endmodule

module anode_decoder(output [7:0]y, input [2:0]select_lines);
    assign y=~(8'd1<<select_lines);
endmodule

module multiplexer(output [3:0]y ,input [31:0]i, input [2:0]select_lines,input done,clk,reset);
   reg [31:0]temp;
    always@(posedge clk or posedge reset)
    begin 
        if(reset)
        begin 
            temp<=0;
        end
        else
        begin 
            if(done)
            begin
            temp<=i;
            end
        end
    end 
    assign y=temp[(select_lines<<2)+:4];
endmodule

module bcd_decoder(output reg [6:0]cathode,input [3:0]bcd);
    always@(*)
        begin
            cathode=7'b0;
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
                4'd10:cathode=7'b0111111;//this isfor negative sign`
                4'd11:cathode=7'b1000110;//for [
                4'd12:cathode=7'b0000110;//for E
                4'd13:cathode=7'b0001000;//for R
                4'd14:cathode=7'b1000000;//for o
                4'd15:cathode=7'b1110000;//fro ]
                /*
                4'd10:cathode=7'b0111111;//this [
                4'd11:cathode=7'b1000110;//for 
                4'd12:cathode=7'b0000110;//for E
                4'd13:cathode=7'b0001000;//for R
                4'd14:cathode=7'b1000000;//for o
                4'd15:cathode=7'b1110000;//fro ]
                */
                default:cathode=7'b1000000;
            endcase
        end
endmodule


module binary_bcd_decoder (
    input clk,
    input reset,
    input start,
    input [26:0] decimal,
    output reg [31:0] result,
    output reg done
);

    reg [5:0] count;
    reg [26:0] temp;
    reg busy;
    
    // Intermediate value for add-3 step (combinational)
    reg [31:0] result_adj;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            result <= 32'd0;
            temp   <= 27'd0;
            count  <= 6'd0;
            done   <= 1'b0;
            busy   <= 1'b0;
        end
        else if (start && !busy) begin
            result <= 32'd0;
            temp   <= decimal;
            count  <= 6'd0;
            done   <= 1'b0;
            busy   <= 1'b1;
        end
        else if (busy && count < 27) begin
            // Perform add-3 adjustment on current result
            result_adj = result;  // Blocking assignment for intermediate calc
            
            if(result[31:28] >= 5) result_adj[31:28] = result[31:28] + 3;
            if(result[27:24] >= 5) result_adj[27:24] = result[27:24] + 3;
            if(result[23:20] >= 5) result_adj[23:20] = result[23:20] + 3;
            if(result[19:16] >= 5) result_adj[19:16] = result[19:16] + 3;
            if(result[15:12] >= 5) result_adj[15:12] = result[15:12] + 3;
            if(result[11:8]  >= 5) result_adj[11:8]  = result[11:8]  + 3;
            if(result[7:4]   >= 5) result_adj[7:4]   = result[7:4]   + 3;
            if(result[3:0]   >= 5) result_adj[3:0]   = result[3:0]   + 3;

            // Now shift the adjusted result (non-blocking for register update)
            result <= {result_adj[30:0], temp[26]};
            temp   <= temp << 1;
            count  <= count + 1;
        end
        else if (busy) begin
            done <= 1'b1;
            busy <= 1'b0;
        end
        else begin
            done <= 1'b0;
        end
    end

endmodule

module eight_driver(output [6:0]cathode,output [7:0]anode,input [26:0]decimal,input data_32bit_valid,clk_in,reset);
    wire [2:0]select_lines;
    wire [3:0]bcd_mux_out;
    wire [31:0]binary_bcd_out;
    wire done;
    reg [26:0] latched_data;
    reg start_d;

always @(posedge clk_in or posedge reset)
begin
    if (reset)
        start_d <= 0;
    else
        start_d <= data_32bit_valid;
end

wire start_pulse = data_32bit_valid & ~start_d;

always @(posedge clk_in) begin
    if (data_32bit_valid)
        latched_data <= decimal;
end
//refresh_counter(output reg [2:0]select_lines,input clk_in, reset); has ineternal clock divider
    refresh_counter a0(select_lines,clk_in,reset);
//anode_decoder(output [7:0]y, input [2:0]select_lines);
    anode_decoder a1(anode,select_lines);
//multiplexer(output [3:0]y ,input [31:0]i, input [2:0]select_lines,input done,clk,reset);
    multiplexer a2(bcd_mux_out,binary_bcd_out,select_lines,done,clk_in,reset);
//bcd_decoder(output reg [6:0]cathode,input [3:0]bcd);
    bcd_decoder a3(cathode,bcd_mux_out);
/*module binary_bcd_decoder (
    input clk,
    input reset,
    input start,
    input [26:0] decimal,
    output reg [31:0] result,
    output reg done
);
*/
   binary_bcd_decoder a4(clk_in,reset,start_pulse,latched_data,binary_bcd_out,done);
endmodule


/*module uart_accumulator_top #
(
    parameter DATA_WIDTH = 8
)
(
    input  wire clk,
    input  wire rst,

    // UART pins
    input  wire rxd,
    output wire txd,

    // Output data
    output wire [31:0] data_out,
    output wire        data_valid,

    // Config
    input  wire [15:0] prescale
);*/
//module eight_driver(output [6:0]cathode,output [7:0]anode,input [26:0]decimal,input data_32bit_valid,clk_in,reset);
module uart_eight_driver(
                        output [6:0]cathode,
                        output [7:0]anode,
                        output tx,
                        input rx,
                        input clk,
                        input reset
                        );
    wire data_valid;
    wire [31:0]data_out;
     // UART module
    uart_accumulator_top uart_inst (
        .clk(clk),
        .rst(reset),
        .rxd(rx),
        .txd(tx),
        .data_out(data_out),
        .data_valid(data_valid),
        .prescale(16'd109)
    );

    // 8-digit display driver
    eight_driver display_inst (
        .cathode(cathode),
        .anode(anode),
        .decimal(data_out[26:0]),   // truncate to 27-bit
        .data_32bit_valid(data_valid),
        .clk_in(clk),
        .reset(reset)
    );
endmodule

