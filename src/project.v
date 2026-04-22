/*
 * Copyright (c) 2025 Aryan
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_i2c_display (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // ========================================
    // Pin Assignments
    localparam SDA_PIN = 0;   
    
    // Internal I2C signals
    wire sda_in, sda_out;    
    
    // Seven-segment outputs (7 cathodes + dp on uo_out[7:0])
    // Anodes will need to use remaining uio pins
    wire [6:0] cathode;
    wire [7:0] anode;
    
    // Reset (active high internally)
    wire reset;
    assign reset = !rst_n;
    
    // ========================================
    // I2C Bidirectional Pin Handling
    // ========================================
    // Read inputs
    assign sda_in = uio_in[SDA_PIN];
    
    
    // Open-drain outputs (always drive 0, use OE to control)
    assign uio_out[SDA_PIN] = 1'b0;
    
    
    // Output enable (1 = drive low, 0 = hi-z/pulled high)
    assign uio_oe[SDA_PIN] = !sda_out;  // OE=1 when sda_out=0 (drive low)
 
    
    // ========================================
    // Inout wire emulation for module
    // ========================================
    wire sda_wire;
    
    // Simulate inout behavior
    assign sda_wire = sda_out ? 1'bz : 1'b0;
   
    wire scl_wire;
    assign scl_wire = ui_in[0];
    // ========================================
    // Seven-Segment Display Outputs
    // ========================================
    // Use uo_out for 7-segment cathodes (+ dp if needed)
    assign uo_out[7:1] = cathode;
    assign {uo_out[0],uio_out[7:1]}=anode;
    assign uio_oe[7:1]  = 7'b1111111;
    
    
    // Use remaining uio pins for anodes (uio[7:2] = 6 anodes)
    // Note: You have 8 anodes but only 6 available pins - you'll need to multiplex
    // or reduce to 6 digits
   
    
    // ========================================
    // Your I2C Display Module
    // ========================================
    i2c_slave_8_sevengenment_driver core (
        .sda(sda_wire),
        .scl(scl_wire),
        .clk(clk),
        .reset(reset),
        .cathode(cathode),
        .anode(anode)
    );
    
    // ========================================
    // Unused inputs
    // ========================================
    wire _unused = &{ena, ui_in, 1'b0};

endmodule






/*
 * I2C slave
 */
module i2c_slave #(
    parameter FILTER_LEN = 4
)
(
    input wire         clk,
    input wire         rst,

    /*
     * Host interface
     */
    input  wire        release_bus,

    input  wire [7:0]  s_axis_data_tdata,
    input  wire        s_axis_data_tvalid,
    output wire        s_axis_data_tready,
    input  wire        s_axis_data_tlast,

    output wire [7:0]  m_axis_data_tdata,
    output wire        m_axis_data_tvalid,
    input  wire        m_axis_data_tready,
    output wire        m_axis_data_tlast,

    /*
     * I2C interface
     */
    input  wire        scl_i,
    output wire        scl_o,
    output wire        scl_t,
    input  wire        sda_i,
    output wire        sda_o,
    output wire        sda_t,

    /*
     * Status
     */
    output wire        busy,
    output wire [6:0]  bus_address,
    output wire        bus_addressed,
    output wire        bus_active,

    /*
     * Configuration
     */
    input  wire        enable,
    input  wire [6:0]  device_address,
    input  wire [6:0]  device_address_mask
);


localparam [4:0]
    STATE_IDLE = 4'd0,
    STATE_ADDRESS = 4'd1,
    STATE_ACK = 4'd2,
    STATE_WRITE_1 = 4'd3,
    STATE_WRITE_2 = 4'd4,
    STATE_READ_1 = 4'd5,
    STATE_READ_2 = 4'd6,
    STATE_READ_3 = 4'd7;

reg [4:0] state_reg = STATE_IDLE, state_next;

reg [6:0] addr_reg = 7'd0, addr_next;
reg [7:0] data_reg = 8'd0, data_next;
reg data_valid_reg = 1'b0, data_valid_next;
reg data_out_reg_valid_reg = 1'b0, data_out_reg_valid_next;
reg last_reg = 1'b0, last_next;

reg mode_read_reg = 1'b0, mode_read_next;

reg [3:0] bit_count_reg = 4'd0, bit_count_next;

reg s_axis_data_tready_reg = 1'b0, s_axis_data_tready_next;

reg [7:0] m_axis_data_tdata_reg = 8'd0, m_axis_data_tdata_next;
reg m_axis_data_tvalid_reg = 1'b0, m_axis_data_tvalid_next;
reg m_axis_data_tlast_reg = 1'b0, m_axis_data_tlast_next;

reg [FILTER_LEN-1:0] scl_i_filter = {FILTER_LEN{1'b1}};
reg [FILTER_LEN-1:0] sda_i_filter = {FILTER_LEN{1'b1}};

reg scl_i_reg = 1'b1;
reg sda_i_reg = 1'b1;

reg scl_o_reg = 1'b1, scl_o_next;
reg sda_o_reg = 1'b1, sda_o_next;

reg last_scl_i_reg = 1'b1;
reg last_sda_i_reg = 1'b1;

reg busy_reg = 1'b0;
reg bus_active_reg = 1'b0;
reg bus_addressed_reg = 1'b0, bus_addressed_next;

assign bus_address = addr_reg;

assign s_axis_data_tready = s_axis_data_tready_reg;

assign m_axis_data_tdata = m_axis_data_tdata_reg;
assign m_axis_data_tvalid = m_axis_data_tvalid_reg;
assign m_axis_data_tlast = m_axis_data_tlast_reg;

assign scl_o = 1'b1;
assign scl_t = 1'b1;
assign sda_o = sda_o_reg;
assign sda_t = sda_o_reg;

assign busy = busy_reg;
assign bus_active = bus_active_reg;
assign bus_addressed = bus_addressed_reg;

assign scl_posedge = scl_i_reg && !last_scl_i_reg;
assign scl_negedge = !scl_i_reg && last_scl_i_reg;
assign sda_posedge = sda_i_reg && !last_sda_i_reg;
assign sda_negedge = !sda_i_reg && last_sda_i_reg;

assign start_bit = sda_negedge && scl_i_reg;
assign stop_bit = sda_posedge && scl_i_reg;

always @* begin
    state_next = STATE_IDLE;

    addr_next = addr_reg;
    data_next = data_reg;
    data_valid_next = data_valid_reg;
    data_out_reg_valid_next = data_out_reg_valid_reg;
    last_next = last_reg;

    mode_read_next = mode_read_reg;

    bit_count_next = bit_count_reg;

    s_axis_data_tready_next = 1'b0;

    m_axis_data_tdata_next = m_axis_data_tdata_reg;
    m_axis_data_tvalid_next = m_axis_data_tvalid_reg && !m_axis_data_tready;
    m_axis_data_tlast_next = m_axis_data_tlast_reg;

    scl_o_next = scl_o_reg;
    sda_o_next = sda_o_reg;

    bus_addressed_next = bus_addressed_reg;

    if (start_bit) begin
        // got start bit, latch out data, read address
        data_valid_next = 1'b0;
        data_out_reg_valid_next = 1'b0;
        bit_count_next = 4'd7;
        m_axis_data_tlast_next = 1'b1;
        m_axis_data_tvalid_next = data_out_reg_valid_reg;
        bus_addressed_next = 1'b0;
        state_next = STATE_ADDRESS;
    end else if (release_bus || stop_bit) begin
        // got stop bit or release bus command, latch out data, return to idle
        data_valid_next = 1'b0;
        data_out_reg_valid_next = 1'b0;
        m_axis_data_tlast_next = 1'b1;
        m_axis_data_tvalid_next = data_out_reg_valid_reg;
        bus_addressed_next = 1'b0;
        state_next = STATE_IDLE;
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                // line idle
                data_valid_next = 1'b0;
                data_out_reg_valid_next = 1'b0;
                bus_addressed_next = 1'b0;
                state_next = STATE_IDLE;
            end
            STATE_ADDRESS: begin
                // read address
                if (scl_posedge) begin
                    if (bit_count_reg > 0) begin
                        // shift in address
                        bit_count_next = bit_count_reg-1;
                        data_next = {data_reg[6:0], sda_i_reg};
                        state_next = STATE_ADDRESS;
                    end else begin
                        // check address
                        if (enable && (device_address & device_address_mask) == (data_reg[6:0] & device_address_mask)) begin
                            // it's a match, save read/write bit and send ACK
                            addr_next = data_reg[6:0];
                            mode_read_next = sda_i_reg;
                            bus_addressed_next = 1'b1;
                            state_next = STATE_ACK;
                        end else begin
                            // no match, return to idle
                            state_next = STATE_IDLE;
                        end
                    end
                end else begin
                    state_next = STATE_ADDRESS;
                end
            end
            STATE_ACK: begin
                // send ACK bit
                if (scl_negedge) begin
                    sda_o_next = 1'b0;
                    bit_count_next = 4'd7;
                    if (mode_read_reg) begin
                        // reading
                        s_axis_data_tready_next = 1'b1;
                        data_valid_next = 1'b0;
                        state_next = STATE_READ_1;
                    end else begin
                        // writing
                        state_next = STATE_WRITE_1;
                    end
                end else begin
                    state_next = STATE_ACK;
                end
            end
            STATE_WRITE_1: begin
                // write data byte
                if (scl_negedge || !scl_o_reg) begin
                    sda_o_next = 1'b1;
                    if (m_axis_data_tvalid && !m_axis_data_tready) begin
                        // data waiting in output register, so stretch clock
                        scl_o_next = 1'b0;
                        state_next = STATE_WRITE_1;
                    end else begin
                        scl_o_next = 1'b1;
                        if (data_valid_reg) begin
                            // store data in output register
                            m_axis_data_tdata_next = data_reg;
                            m_axis_data_tlast_next = 1'b0;
                        end
                        data_valid_next = 1'b0;
                        data_out_reg_valid_next = data_valid_reg;
                        state_next = STATE_WRITE_2;
                    end
                end else begin
                    state_next = STATE_WRITE_1;
                end
            end
            STATE_WRITE_2: begin
                // write data byte
                if (scl_posedge) begin
                    // shift in data bit
                    data_next = {data_reg[6:0], sda_i_reg};
                    if (bit_count_reg > 0) begin
                        bit_count_next = bit_count_reg-1;
                        state_next = STATE_WRITE_2;
                    end else begin
                        // latch out previous data byte since we now know it's not the last one
                        m_axis_data_tvalid_next = data_out_reg_valid_reg;
                        data_out_reg_valid_next = 1'b0;
                        data_valid_next = 1'b1;
                        state_next = STATE_ACK;
                    end
                end else begin
                    state_next = STATE_WRITE_2;
                end
            end
            STATE_READ_1: begin
                // read data byte
                if (s_axis_data_tready && s_axis_data_tvalid) begin
                    // data valid; latch it in
                    s_axis_data_tready_next = 1'b0;
                    data_next = s_axis_data_tdata;
                    data_valid_next = 1'b1;
                end else begin
                    // keep ready high if we're waiting for data
                    s_axis_data_tready_next = !data_valid_reg;
                end

                if (scl_negedge || !scl_o_reg) begin
                    // shift out data bit
                    if (!data_valid_reg) begin
                        // waiting for data, so stretch clock
                        scl_o_next = 1'b0;
                        state_next = STATE_READ_1;
                    end else begin
                        scl_o_next = 1'b1;
                        {sda_o_next, data_next} = {data_reg, 1'b0};
                        
                        if (bit_count_reg > 0) begin
                            bit_count_next = bit_count_reg-1;
                            state_next = STATE_READ_1;
                        end else begin
                            state_next = STATE_READ_2;
                        end
                    end
                end else begin
                    state_next = STATE_READ_1;
                end
            end
            STATE_READ_2: begin
                // read ACK bit
                if (scl_negedge) begin
                    // release SDA
                    sda_o_next = 1'b1;
                    state_next = STATE_READ_3;
                end else begin
                    state_next = STATE_READ_2;
                end
            end
            STATE_READ_3: begin
                // read ACK bit
                if (scl_posedge) begin
                    if (sda_i_reg) begin
                        // NACK, return to idle
                        state_next = STATE_IDLE;
                    end else begin
                        // ACK, read another byte
                        bit_count_next = 4'd7;
                        s_axis_data_tready_next = 1'b1;
                        data_valid_next = 1'b0;
                        state_next = STATE_READ_1;
                    end
                end else begin
                    state_next = STATE_READ_3;
                end
            end
        endcase
    end
end

always @(posedge clk) begin
    state_reg <= state_next;

    addr_reg <= addr_next;
    data_reg <= data_next;
    data_valid_reg <= data_valid_next;
    data_out_reg_valid_reg <= data_out_reg_valid_next;
    last_reg <= last_next;

    mode_read_reg <= mode_read_next;

    bit_count_reg <= bit_count_next;

    s_axis_data_tready_reg <= s_axis_data_tready_next;

    m_axis_data_tdata_reg <= m_axis_data_tdata_next;
    m_axis_data_tvalid_reg <= m_axis_data_tvalid_next;
    m_axis_data_tlast_reg <= m_axis_data_tlast_next;

    scl_i_filter <= (scl_i_filter << 1) | scl_i;
    sda_i_filter <= (sda_i_filter << 1) | sda_i;

    if (scl_i_filter == {FILTER_LEN{1'b1}}) begin
        scl_i_reg <= 1'b1;
    end else if (scl_i_filter == {FILTER_LEN{1'b0}}) begin
        scl_i_reg <= 1'b0;
    end

    if (sda_i_filter == {FILTER_LEN{1'b1}}) begin
        sda_i_reg <= 1'b1;
    end else if (sda_i_filter == {FILTER_LEN{1'b0}}) begin
        sda_i_reg <= 1'b0;
    end

    scl_o_reg <= scl_o_next;
    sda_o_reg <= sda_o_next;

    last_scl_i_reg <= scl_i_reg;
    last_sda_i_reg <= sda_i_reg;

    busy_reg <= !(state_reg == STATE_IDLE);

    if (start_bit) begin
        bus_active_reg <= 1'b1;
    end else if (stop_bit) begin
        bus_active_reg <= 1'b0;
    end else begin
        bus_active_reg <= bus_active_reg;
    end

    bus_addressed_reg <= bus_addressed_next;

    if (rst) begin
        state_reg <= STATE_IDLE;
        s_axis_data_tready_reg <= 1'b0;
        m_axis_data_tvalid_reg <= 1'b0;
        scl_o_reg <= 1'b1;
        sda_o_reg <= 1'b1;
        busy_reg <= 1'b0;
        bus_active_reg <= 1'b0;
        bus_addressed_reg <= 1'b0;
    end
end

endmodule







module i2c_32bit_store (
    input  wire clk,
    input  wire rst,

    inout  wire sda,
    input  wire scl,

    output reg [31:0] data_32bit,
    output reg data_valid
);

    // =============================
    // I2C signals
    // =============================
    wire [7:0] rx_data;
    wire rx_valid;

    reg [7:0] tx_data;
    reg tx_valid;
    wire tx_ready;

    // =============================
    // Internal storage
    // =============================
    reg [1:0] byte_count;

    // =============================
    // I2C core wiring (NO clock stretch)
    // =============================
    wire scl_i = scl;
    wire sda_i, sda_o;

    assign sda_i = sda;
    assign sda   = sda_o ? 1'bz : 1'b0;

    // DO NOT DRIVE SCL
    // (you already learned this lesson 😄)

    // =============================
    // I2C SLAVE INSTANCE
    // =============================
    i2c_slave uut (
        .clk(clk),
        .rst(rst),

        .release_bus(1'b0),

        // WRITE (Master → FPGA)
        .m_axis_data_tdata(rx_data),
        .m_axis_data_tvalid(rx_valid),
        .m_axis_data_tready(1'b1),
        .m_axis_data_tlast(),

        // READ (optional, keep simple)
        .s_axis_data_tdata(tx_data),
        .s_axis_data_tvalid(tx_valid),
        .s_axis_data_tready(tx_ready),
        .s_axis_data_tlast(1'b0),

        // I2C
        .scl_i(scl_i),
        .scl_o(),   // NOT USED
        .scl_t(),
        .sda_i(sda_i),
        .sda_o(sda_o),
        .sda_t(),

        // Status
        .busy(),
        .bus_address(),
        .bus_addressed(),
        .bus_active(),

        // Config
        .enable(1'b1),
        .device_address(7'h34),
        .device_address_mask(7'h7F)
    );

    // =============================
    // 32-BIT ACCUMULATION LOGIC
    // =============================
    always @(posedge clk) begin
        if (rst) begin
            data_32bit   <= 32'd0;
            byte_count   <= 2'd0;
            data_valid   <= 1'b0;
        end else begin
            data_valid <= 1'b0;  // default

            if (rx_valid) begin
                // shift left and insert new byte
                data_32bit <= {data_32bit[23:0], rx_data};

                if (byte_count == 2'd3) begin
                    byte_count <= 2'd0;
                    data_valid <= 1'b1;  // 4 bytes complete
                end else begin
                    byte_count <= byte_count + 1'b1;
                end
            end
        end
    end

    // =============================
    // OPTIONAL: echo MSB on read
    // =============================
   always @(posedge clk) begin
    if (rst) begin
        tx_valid <= 0;
    end else begin
        if (!tx_valid && tx_ready) begin
            tx_data  <= data_32bit[31:24];
            tx_valid <= 1'b1;
        end else if (tx_valid && tx_ready) begin
            tx_valid <= 1'b0;
        end
    end
end

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

module i2c_slave_8_sevengenment_driver(inout  wire sda,
                                       input  wire scl,
                                       input  wire clk,
                                       input  wire reset,
                                       output [6:0]cathode,
                                       output [7:0]anode
                                        );
wire data_valid;
wire [31:0]data_32bit;
/*module i2c_32bit_store (
    input  wire clk,
    input  wire rst,

    inout  wire sda,
    input  wire scl,

    output reg [31:0] data_32bit,
    output reg data_valid
);*/
i2c_32bit_store a0(clk,reset,sda,scl,data_32bit,data_valid);
//eight_driver(output [6:0]cathode,output [7:0]anode,input [26:0]decimal,input data_32bit_valid,clk_in,reset);
eight_driver a1(cathode,anode,data_32bit[26:0],data_valid,clk,reset);
endmodule

