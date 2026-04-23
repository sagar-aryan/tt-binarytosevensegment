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
    uart_eight_driver tinytapeout(.cathode(uo_out[7:1]),
                                  .anode(uio_out),
                                  .tx(uo_out[0]),
                                  .rx(ui_in[0]),
                                  .clk(clk),
                                  .reset(rst)
                                  );
  
  assign uio_oe=8'b11111111;
  // List all unused inputs to prevent warnings
    wire _unused = &{ena,ui_in[7:1],1'b0};

endmodule









// ============================================================
// uart_accumulator  -  collects 4 bytes (little-endian) into
//                      a 32-bit word, asserts data_valid the
//                      cycle AFTER the last byte is stored.
// ============================================================
module uart_accumulator #
(
    parameter DATA_WIDTH = 8
)
(
    input  wire clk,
    input  wire rst,

    input  wire [DATA_WIDTH-1:0] rx_tdata,
    input  wire                  rx_tvalid,
    output reg                   rx_tready,

    output reg [31:0] data_out,
    output reg        data_valid
);

    reg [1:0] byte_count;
    reg       last_byte_written;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out          <= 0;
            data_valid        <= 0;
            byte_count        <= 0;
            rx_tready         <= 1;   // start ready to receive
            last_byte_written <= 0;
        end else begin
            data_valid        <= 0;
            last_byte_written <= 0;

            // Default: re-assert ready so we can receive the next byte
            rx_tready <= 1;

            if (rx_tvalid && rx_tready) begin
                // Consume this byte, then go NOT-ready for 1 cycle so
                // the UART RX de-asserts tvalid before we sample again.
                // Without this, tvalid stays high 2+ cycles and we
                // double-count every byte (getting 4E 4E 61 61 instead
                // of 4E 61 BC 00, producing 78787878 on the display).
                rx_tready <= 0;

                // Little-endian: first byte → LSB
                case (byte_count)
                    2'd0: data_out[7:0]   <= rx_tdata;
                    2'd1: data_out[15:8]  <= rx_tdata;
                    2'd2: data_out[23:16] <= rx_tdata;
                    2'd3: data_out[31:24] <= rx_tdata;
                endcase
                byte_count <= byte_count + 1;

                if (byte_count == 2'd3) begin
                    last_byte_written <= 1;
                    byte_count        <= 0;
                end
            end

            // data_valid fires ONE cycle after byte 3 is written
            // so data_out is fully settled before anyone samples it
            if (last_byte_written)
                data_valid <= 1;
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
    input  wire rxd,
    output wire txd,
    output wire [31:0] data_out,
    output wire        data_valid,
    input  wire [15:0] prescale
);

wire [DATA_WIDTH-1:0] rx_tdata;
wire                  rx_tvalid;
wire                  rx_tready;
wire                  acc_valid;

uart_rx #(.DATA_WIDTH(DATA_WIDTH)) uart_rx_inst (
    .clk(clk), .rst(rst),
    .m_axis_tdata(rx_tdata), .m_axis_tvalid(rx_tvalid), .m_axis_tready(rx_tready),
    .rxd(rxd), .busy(), .overrun_error(), .frame_error(),
    .prescale(prescale)
);

uart_accumulator #(.DATA_WIDTH(DATA_WIDTH)) acc_inst (
    .clk(clk), .rst(rst),
    .rx_tdata(rx_tdata), .rx_tvalid(rx_tvalid), .rx_tready(rx_tready),
    .data_out(data_out), .data_valid(acc_valid)
);

assign data_valid = acc_valid;

// ---- ACK logic ----
reg [7:0] tx_tdata_reg;
reg       tx_tvalid_reg;
wire      tx_tready;
reg       sending_ack;
localparam ACK = 8'h06;

always @(posedge clk) begin
    if (rst) begin
        tx_tvalid_reg <= 0;
        tx_tdata_reg  <= 0;
        sending_ack   <= 0;
    end else begin
        if (tx_tvalid_reg && tx_tready)
            tx_tvalid_reg <= 0;

        if (acc_valid && !sending_ack) begin
            tx_tdata_reg  <= ACK;
            tx_tvalid_reg <= 1;
            sending_ack   <= 1;
        end

        if (sending_ack && tx_tvalid_reg && tx_tready)
            sending_ack <= 0;
    end
end

uart_tx #(.DATA_WIDTH(DATA_WIDTH)) uart_tx_inst (
    .clk(clk), .rst(rst),
    .s_axis_tdata(tx_tdata_reg), .s_axis_tvalid(tx_tvalid_reg), .s_axis_tready(tx_tready),
    .txd(txd), .busy(), .prescale(prescale)
);

endmodule


module clock_divider(output clk_out, input clk_in, reset);
    reg [15:0] internal;
    assign clk_out = (internal == 16'hFFFF);
    always @(posedge clk_in or posedge reset)
        if (reset) internal <= 0;
        else       internal <= internal + 1;
endmodule

module refresh_counter(output reg [2:0] select_lines, input clk_in, reset);
    wire clk_out;
    clock_divider a0(clk_out, clk_in, reset);
    always @(posedge clk_in or posedge reset)
        if (reset)    select_lines <= 0;
        else if (clk_out) select_lines <= select_lines + 1;
endmodule

module anode_decoder(output [7:0] y, input [2:0] select_lines);
    assign y = ~(8'd1 << select_lines);
endmodule

module multiplexer(output [3:0] y, input [31:0] i, input [2:0] select_lines, input done, clk, reset);
    reg [31:0] temp;
    always @(posedge clk or posedge reset)
        if (reset)    temp <= 0;
        else if (done) temp <= i;
    // FIXED - zero-extend select_lines to 5 bits before shifting
        assign y = temp[({2'b0, select_lines} << 2) +: 4];
endmodule

module bcd_decoder(output reg [6:0] cathode, input [3:0] bcd);
    always @(*) begin
        cathode = 7'b0;
        case (bcd)
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
            default: cathode = 7'b1000000;
        endcase
    end
endmodule


// ============================================================
// binary_bcd_decoder  -  Double-Dabble, FIXED
//
// BUG that was here before:
//   result <= {result_adj[30:0], temp[31]}   ← drops bit 31 every cycle!
//
// FIX:
//   Use a 40-bit BCD register (10 BCD digits).
//   A 32-bit binary number needs up to 10 decimal digits.
//   We only display the bottom 8 digits (32 bits of result),
//   but we need 40 bits of BCD accumulation to avoid overflow
//   corrupting the upper displayed digits.
// ============================================================
module binary_bcd_decoder (
    input        clk,
    input        reset,
    input        start,
    input [31:0] decimal,
    output reg [31:0] result,   // bottom 8 BCD digits for display
    output reg   done,
    output reg   busy
);

    reg [5:0]  count;
    reg [31:0] bin_shift;   // binary shift register
    reg [39:0] bcd;         // 40-bit BCD accumulator (10 digits)

    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bcd       <= 0;
            bin_shift <= 0;
            count     <= 0;
            result    <= 0;
            done      <= 0;
            busy      <= 0;
        end
        else if (start && !busy) begin
            bcd       <= 0;
            bin_shift <= decimal;
            count     <= 0;
            done      <= 0;
            busy      <= 1;
        end
        else if (busy && count < 32) begin
            // Add-3 (adjust) step on all 10 BCD digits
            // Must use blocking assignments for the intermediate value
            if (bcd[39:36] >= 5) bcd[39:36] = bcd[39:36] + 3;
            if (bcd[35:32] >= 5) bcd[35:32] = bcd[35:32] + 3;
            if (bcd[31:28] >= 5) bcd[31:28] = bcd[31:28] + 3;
            if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 3;
            if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 3;
            if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
            if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
            if (bcd[11:8]  >= 5) bcd[11:8]  = bcd[11:8]  + 3;
            if (bcd[7:4]   >= 5) bcd[7:4]   = bcd[7:4]   + 3;
            if (bcd[3:0]   >= 5) bcd[3:0]   = bcd[3:0]   + 3;

            // Shift left: MSB of bin_shift feeds into LSB of bcd
            bcd       <= {bcd[38:0], bin_shift[31]};
            bin_shift <= bin_shift << 1;
            count     <= count + 1;
        end
        else if (busy) begin
            result <= bcd[31:0];   // bottom 8 digits → display
            done   <= 1;
            busy   <= 0;
        end
        else begin
            done <= 0;
        end
    end

endmodule


// ============================================================
// eight_driver  -  latches data_out, starts BCD conversion,
//                  drives 8-digit 7-segment display
// ============================================================
module eight_driver(
    output [6:0] cathode,
    output [7:0] anode,
    input [31:0] decimal,
    input        data_32bit_valid,
    input        clk_in,
    input        reset
);
    wire [2:0]  select_lines;
    wire [3:0]  bcd_mux_out;
    wire [31:0] binary_bcd_out;
    wire        done;
    wire        busy;

    reg [31:0] latched_data;
    reg        valid_d1, valid_d2;   // two-stage pipe

    always @(posedge clk_in or posedge reset) begin
        if (reset) begin
            valid_d1     <= 0;
            valid_d2     <= 0;
            latched_data <= 0;
        end else begin
            valid_d1 <= data_32bit_valid;
            valid_d2 <= valid_d1;

            // Latch on rising edge of data_32bit_valid
            if (data_32bit_valid && !valid_d1)
                latched_data <= decimal;
        end
    end

    // start_pulse: one cycle after latch (valid_d1 rising), and not busy
    wire start_pulse = valid_d1 && !valid_d2 && !busy;

    refresh_counter    a0(select_lines,  clk_in, reset);
    anode_decoder      a1(anode,         select_lines);
    multiplexer        a2(bcd_mux_out,   binary_bcd_out, select_lines, done, clk_in, reset);
    bcd_decoder        a3(cathode,       bcd_mux_out);
    binary_bcd_decoder a4(clk_in, reset, start_pulse, latched_data, binary_bcd_out, done, busy);

endmodule


module uart_eight_driver(
    output [6:0] cathode,
    output [7:0] anode,
    output       tx,
    input        rx,
    input        clk,
    input        reset
);
    wire        data_valid;
    wire [31:0] data_out;

    uart_accumulator_top uart_inst (
        .clk(clk), .rst(reset),
        .rxd(rx),  .txd(tx),
        .data_out(data_out),
        .data_valid(data_valid),
        .prescale(16'd109)
    );

    eight_driver display_inst (
        .cathode(cathode),
        .anode(anode),
        .decimal(data_out),
        .data_32bit_valid(data_valid),
        .clk_in(clk),
        .reset(reset)
    );
endmodule

module dipslay_fpga(
    output [6:0] seg,
    output [7:0] an,
    output       tx,
    input        rx,
    input        clk,
    input        btnC
);
    uart_eight_driver fpga_instnatiation(
        .cathode(seg), .anode(an),
        .tx(tx), .rx(rx),
        .clk(clk), .reset(btnC)
    );
endmodule

module echod_fpga(
    output tx,
    input  rx,
    input  clk,
    input  btnC
);
    uart_echo_top echo_instance(
        .clk(clk), .rst(btnC),
        .rxd(rx),  .txd(tx),
        .prescale(16'd109)
    );
endmodule

