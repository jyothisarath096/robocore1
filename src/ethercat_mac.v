// RoboCore-1 EtherCAT MAC — SRAM Wrapper Edition
// Uses sram_wrapper hardened macro for all memory
// Constitution v1.0 | Open Source MIT License

module ethercat_mac #(
    parameter NODE_ADDR = 16'h0001,
    parameter FIFO_DEPTH = 8,
    parameter DC_WIDTH = 64
)(
    input  wire         clk, rst_n,
    input  wire [1:0]   rmii_rxd,
    input  wire         rmii_rx_dv, rmii_rx_er,
    output reg  [1:0]   rmii_txd,
    output reg          rmii_tx_en,
    input  wire         rmii_ref_clk,
    input  wire [15:0]  pd_addr,
    input  wire [31:0]  pd_wdata,
    input  wire         pd_we, pd_re,
    output reg  [31:0]  pd_rdata,
    output reg          pd_valid,
    output reg  [DC_WIDTH-1:0] dc_local_time,
    input  wire [DC_WIDTH-1:0] dc_offset,
    output reg          dc_sync0, dc_sync1,
    input  wire [DC_WIDTH-1:0] dc_sync0_period, dc_sync1_period,
    output reg  [3:0]   ec_state,
    output reg          ec_link, ec_frame_rx, ec_frame_tx,
    output reg  [15:0]  ec_wkc,
    output reg          ec_timeout,
    output wire         ec_operational, fault
);

localparam EC_INIT=4'd0,EC_PREOP=4'd1,EC_SAFEOP=4'd2,EC_OP=4'd3;
localparam RX_IDLE=3'd0,RX_PREAMBLE=3'd1,RX_DATA=3'd2;
localparam TX_IDLE=3'd0,TX_PREAMBLE=3'd1,TX_DATA=3'd2,TX_FCS=3'd3;

// Input sync
reg [1:0] rxd_r1,rxd_r2; reg rxdv_r1,rxdv_r2,rxer_r1,rxer_r2;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rxd_r1<=0;rxd_r2<=0;rxdv_r1<=0;rxdv_r2<=0;rxer_r1<=0;rxer_r2<=0; end
    else begin rxd_r1<=rmii_rxd;rxd_r2<=rxd_r1;rxdv_r1<=rmii_rx_dv;rxdv_r2<=rxdv_r1;rxer_r1<=rmii_rx_er;rxer_r2<=rxer_r1; end
end

// CRC32
/* verilator lint_off BLKSEQ */
function [31:0] crc32_step;
    input [31:0] crc; input din; reg inv;
    begin
        inv=din^crc[31];
        crc32_step[31]=crc[30]^inv; crc32_step[30]=crc[29]; crc32_step[29]=crc[28]; crc32_step[28]=crc[27];
        crc32_step[27]=crc[26]^inv; crc32_step[26]=crc[25]^inv; crc32_step[25]=crc[24]; crc32_step[24]=crc[23];
        crc32_step[23]=crc[22]; crc32_step[22]=crc[21]; crc32_step[21]=crc[20]; crc32_step[20]=crc[19];
        crc32_step[19]=crc[18]^inv; crc32_step[18]=crc[17]; crc32_step[17]=crc[16]; crc32_step[16]=crc[15];
        crc32_step[15]=crc[14]; crc32_step[14]=crc[13]; crc32_step[13]=crc[12]; crc32_step[12]=crc[11]^inv;
        crc32_step[11]=crc[10]^inv; crc32_step[10]=crc[9]^inv; crc32_step[9]=crc[8]; crc32_step[8]=crc[7]^inv;
        crc32_step[7]=crc[6]^inv; crc32_step[6]=crc[5]; crc32_step[5]=crc[4]^inv; crc32_step[4]=crc[3]^inv;
        crc32_step[3]=crc[2]; crc32_step[2]=crc[1]^inv; crc32_step[1]=crc[0]^inv; crc32_step[0]=inv;
    end
endfunction
/* verilator lint_on BLKSEQ */

// SRAM wrapper interface
wire [8:0]  sw_pd_addr = pd_addr[10:2];
wire        sw_pd_sel  = pd_addr[11];
wire [31:0] sw_pd_dout;
reg  [9:0]  sw_rx_addr; reg [7:0] sw_rx_din; reg sw_rx_we;
wire [7:0]  sw_rx_dout;
reg  [9:0]  sw_tx_addr; wire [7:0] sw_tx_dout;

sram_wrapper u_sram (
    .clk(clk),
    .pd_addr(sw_pd_addr), .pd_sel(sw_pd_sel), .pd_wdata(pd_wdata),
    .pd_we(pd_we), .pd_re(pd_re), .pd_dout(sw_pd_dout),
    .rx_addr(sw_rx_addr), .rx_din(sw_rx_din), .rx_we(sw_rx_we), .rx_dout(sw_rx_dout),
    .tx_addr(sw_tx_addr), .tx_dout(sw_tx_dout)
);

reg pd_re_r, pd_re_r2;  // 2-cycle delay for SRAM output latency
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin pd_re_r<=0; pd_re_r2<=0; pd_rdata<=0; pd_valid<=0; end
    else begin
        pd_re_r  <= pd_re;
        pd_re_r2 <= pd_re_r;
        if (pd_re_r2) begin pd_rdata<=sw_pd_dout; pd_valid<=1; end
        else pd_valid<=0;
    end
end

// Distributed clocks
reg [DC_WIDTH-1:0] dc_counter,dc_s0_next,dc_s1_next;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin dc_counter<=0;dc_local_time<=0;dc_sync0<=0;dc_sync1<=0;dc_s0_next<=0;dc_s1_next<=0; end
    else begin
        dc_counter<=dc_counter+64'd10; dc_local_time<=dc_counter+dc_offset;
        dc_sync0<=0; if(dc_local_time>=dc_s0_next) begin dc_sync0<=1; dc_s0_next<=dc_s0_next+dc_sync0_period; end
        dc_sync1<=0; if(dc_local_time>=dc_s1_next) begin dc_sync1<=1; dc_s1_next<=dc_s1_next+dc_sync1_period; end
    end
end

// RX state machine
reg [2:0] rx_state; reg [7:0] rx_byte; reg [2:0] rx_bit_cnt; reg [9:0] rx_byte_cnt;
reg rx_frame_valid; reg [31:0] crc_reg; reg [7:0] rx_b12,rx_b13,rx_b16,rx_b17;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state<=RX_IDLE; rx_bit_cnt<=0; rx_byte_cnt<=0; rx_frame_valid<=0;
        ec_frame_rx<=0; ec_wkc<=0; crc_reg<=32'hFFFFFFFF;
        sw_rx_we<=0; sw_rx_addr<=0; sw_rx_din<=0;
        rx_b12<=0; rx_b13<=0; rx_b16<=0; rx_b17<=0;
    end else begin
        ec_frame_rx<=0; sw_rx_we<=0;
        case (rx_state)
            RX_IDLE: begin
                crc_reg<=32'hFFFFFFFF;
                if (rxdv_r2) begin rx_state<=RX_PREAMBLE; rx_bit_cnt<=0; rx_byte_cnt<=0; end
            end
            RX_PREAMBLE: begin
                if (rxdv_r2) begin
                    rx_byte<={rxd_r2,rx_byte[7:2]};
                    if (rx_byte==8'hD5) begin rx_state<=RX_DATA; rx_byte_cnt<=0; rx_bit_cnt<=0; end
                end else rx_state<=RX_IDLE;
            end
            RX_DATA: begin
                if (rxdv_r2) begin
                    rx_byte<={rxd_r2,rx_byte[7:2]}; rx_bit_cnt<=rx_bit_cnt+1;
                    if (rx_bit_cnt==3) begin
                        sw_rx_addr<=rx_byte_cnt; sw_rx_din<={rxd_r2,rx_byte[7:2]}; sw_rx_we<=1;
                        case (rx_byte_cnt)
                            10'd12: rx_b12<={rxd_r2,rx_byte[7:2]};
                            10'd13: rx_b13<={rxd_r2,rx_byte[7:2]};
                            10'd16: rx_b16<={rxd_r2,rx_byte[7:2]};
                            10'd17: rx_b17<={rxd_r2,rx_byte[7:2]};
                            default: ;
                        endcase
                        rx_byte_cnt<=rx_byte_cnt+1; rx_bit_cnt<=0;
                        crc_reg<=crc32_step(crc_reg,rx_byte[0]);
                    end
                end else begin
                    rx_frame_valid<=(crc_reg==32'hC704DD7B); ec_frame_rx<=1;
                    if (rx_b12==8'h88 && rx_b13==8'hA4) ec_wkc<={rx_b16,rx_b17};
                    rx_state<=RX_IDLE;
                end
            end
            default: rx_state<=RX_IDLE;
        endcase
    end
end

// TX state machine
reg [2:0] tx_state; reg [2:0] tx_bit_cnt; reg [9:0] tx_byte_cnt;
reg [10:0] tx_frame_len; reg [31:0] tx_crc; reg tx_start;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state<=TX_IDLE; rmii_txd<=0; rmii_tx_en<=0; tx_bit_cnt<=0; tx_byte_cnt<=0;
        tx_frame_len<=11'd60; ec_frame_tx<=0; sw_tx_addr<=0; tx_start<=0; tx_crc<=32'hFFFFFFFF;
    end else begin
        ec_frame_tx<=0;
        case (tx_state)
            TX_IDLE: begin rmii_tx_en<=0; if(tx_start) begin tx_state<=TX_PREAMBLE; tx_bit_cnt<=0; tx_byte_cnt<=0; tx_crc<=32'hFFFFFFFF; end end
            TX_PREAMBLE: begin
                rmii_tx_en<=1;
                if (tx_byte_cnt<7) begin rmii_txd<=2'b01; if(tx_bit_cnt==3) begin tx_byte_cnt<=tx_byte_cnt+1; tx_bit_cnt<=0; end else tx_bit_cnt<=tx_bit_cnt+1; end
                else begin rmii_txd<=2'b11; if(tx_bit_cnt==3) begin tx_state<=TX_DATA; tx_byte_cnt<=0; tx_bit_cnt<=0; sw_tx_addr<=0; end else tx_bit_cnt<=tx_bit_cnt+1; end
            end
            TX_DATA: begin
                rmii_tx_en<=1; sw_tx_addr<=tx_byte_cnt;
                case(tx_bit_cnt) 0:rmii_txd<=sw_tx_dout[1:0]; 1:rmii_txd<=sw_tx_dout[3:2]; 2:rmii_txd<=sw_tx_dout[5:4]; 3:rmii_txd<=sw_tx_dout[7:6]; default:rmii_txd<=0; endcase
                if (tx_bit_cnt==3) begin tx_bit_cnt<=0; tx_crc<=crc32_step(tx_crc,sw_tx_dout[0]); if(tx_byte_cnt==tx_frame_len-1) begin tx_state<=TX_FCS; tx_byte_cnt<=0; end else tx_byte_cnt<=tx_byte_cnt+1; end
                else tx_bit_cnt<=tx_bit_cnt+1;
            end
            TX_FCS: begin
                case(tx_byte_cnt[1:0]) 0:rmii_txd<=tx_crc[1:0]; 1:rmii_txd<=tx_crc[9:8]; 2:rmii_txd<=tx_crc[17:16]; 3:rmii_txd<=tx_crc[25:24]; default:rmii_txd<=0; endcase
                if(tx_byte_cnt==3) begin rmii_tx_en<=0; tx_state<=TX_IDLE; ec_frame_tx<=1; end else tx_byte_cnt<=tx_byte_cnt+1;
            end
            default: tx_state<=TX_IDLE;
        endcase
    end
end

// EtherCAT state machine
reg [23:0] ec_init_timer;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin ec_state<=EC_INIT; ec_link<=0; ec_init_timer<=0; end
    else begin
        ec_link<=rmii_rx_dv|rxdv_r2;
        case (ec_state)
            EC_INIT:   begin ec_init_timer<=ec_init_timer+1; if(ec_init_timer==24'hFFFFFF) ec_state<=EC_PREOP; end
            EC_PREOP:  if(ec_frame_rx) ec_state<=EC_SAFEOP;
            EC_SAFEOP: if(ec_frame_rx && rx_frame_valid) ec_state<=EC_OP;
            EC_OP:     if(ec_timeout) ec_state<=EC_SAFEOP;
            default:   ec_state<=EC_INIT;
        endcase
    end
end

// Watchdog — single always block owns ec_timeout
reg [23:0] wd_counter; localparam WD_TIMEOUT=24'd1_000_000;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin wd_counter<=0; ec_timeout<=0; end
    else begin
        if (ec_frame_rx) begin wd_counter<=0; ec_timeout<=0; end
        else begin wd_counter<=wd_counter+1; if(wd_counter>=WD_TIMEOUT) begin ec_timeout<=1; wd_counter<=0; end end
    end
end

assign ec_operational = (ec_state==EC_OP);
assign fault = ec_timeout | rxer_r2;

endmodule
