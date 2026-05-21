// ============================================================
// RoboCore-1 Robotics DMA Engine v3
// Constitution v2.0 | 92MHz SKY130
//
// Architecture: Centralized sequencer, round-robin arbitration
// 8 channels, 16 descriptors each, AXI4-Lite master
//
// Descriptor (4 words):
//   [0] src_addr
//   [1] dst_addr
//   [2] ctrl: [7:0]=len [10:8]=trig [11]=ts_inject
//             [12]=skip_fault [14]=auto_reload [15]=enable
//   [3] reserved
//
// Trigger sources: 0=SW 1=SYNC0 2=SYNC1 3=1kHz 4=1MHz 5=CAN 6=EXT
// ============================================================

module robocore1_dma #(
    parameter NUM_CHANNELS = 8,
    parameter DESC_DEPTH   = 16
)(
    input  wire        clk, rst_n,

    // AXI4-Lite Master
    output reg  [31:0] m_awaddr,  output reg  m_awvalid, input wire m_awready,
    output reg  [31:0] m_wdata,   output reg  [3:0] m_wstrb,
    output reg         m_wvalid,  input wire  m_wready,
    input  wire [1:0]  m_bresp,   input wire  m_bvalid,  output reg m_bready,
    output reg  [31:0] m_araddr,  output reg  m_arvalid, input wire m_arready,
    input  wire [31:0] m_rdata,   input wire  [1:0] m_rresp,
    input  wire        m_rvalid,  output reg  m_rready,

    // Triggers
    input  wire        trig_sync0, trig_sync1, trig_1khz, trig_1mhz,
    input  wire        trig_can_rx, trig_ext,

    // DC timestamp
    input  wire [63:0] dc_local_time,
    input  wire        fault_in,

    // Config slave
    input  wire [31:0] cfg_awaddr, input  wire cfg_awvalid, output reg cfg_awready,
    input  wire [31:0] cfg_wdata,  input  wire [3:0] cfg_wstrb,
    input  wire        cfg_wvalid, output reg cfg_wready,
    output reg  [1:0]  cfg_bresp,  output reg cfg_bvalid, input wire cfg_bready,
    input  wire [31:0] cfg_araddr, input  wire cfg_arvalid, output reg cfg_arready,
    output reg  [31:0] cfg_rdata,  output reg [1:0] cfg_rresp,
    output reg         cfg_rvalid, input wire cfg_rready,

    // IRQs
    output reg  [NUM_CHANNELS-1:0] irq_complete,
    output reg  [NUM_CHANNELS-1:0] irq_chain,
    output reg                     irq_error
);

// ============================================================
// Trigger edge detection
// ============================================================
reg ts0r, ts1r, t1kr, t1mr, tcrr, texr;
wire p_sync0 = trig_sync0 & ~ts0r;
wire p_sync1 = trig_sync1 & ~ts1r;
wire p_1khz  = trig_1khz  & ~t1kr;
wire p_1mhz  = trig_1mhz  & ~t1mr;
wire p_can   = trig_can_rx & ~tcrr;
wire p_ext   = trig_ext   & ~texr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin ts0r<=0; ts1r<=0; t1kr<=0; t1mr<=0; tcrr<=0; texr<=0; end
    else begin
        ts0r<=trig_sync0; ts1r<=trig_sync1; t1kr<=trig_1khz;
        t1mr<=trig_1mhz;  tcrr<=trig_can_rx; texr<=trig_ext;
    end
end

// ============================================================
// Descriptor RAM — flat array: index = ch*64 + desc*4 + word
// ============================================================
reg [31:0] desc_ram [0:511]; // 8*16*4 = 512 entries
integer di;
initial for (di = 0; di < 512; di = di + 1) desc_ram[di] = 0;

// ============================================================
// Per-channel state
// ============================================================
reg [NUM_CHANNELS-1:0] ch_enabled;
reg [NUM_CHANNELS-1:0] ch_sw_trig;
reg [NUM_CHANNELS-1:0] ch_pending;
reg [3:0] ch_desc [0:NUM_CHANNELS-1];

// ============================================================
// Trigger detection — one always block per channel
// ============================================================
genvar gi;
generate
for (gi = 0; gi < NUM_CHANNELS; gi = gi + 1) begin : trig_gen
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ch_pending[gi] <= 0;
            ch_sw_trig[gi] <= 0;
        end else if (ch_enabled[gi] && !ch_pending[gi]) begin
            case (desc_ram[gi*64 + ch_desc[gi]*4 + 2][10:8])
                3'd0: if (ch_sw_trig[gi]) begin ch_pending[gi]<=1; ch_sw_trig[gi]<=0; end
                3'd1: if (p_sync0) ch_pending[gi] <= 1;
                3'd2: if (p_sync1) ch_pending[gi] <= 1;
                3'd3: if (p_1khz)  ch_pending[gi] <= 1;
                3'd4: if (p_1mhz)  ch_pending[gi] <= 1;
                3'd5: if (p_can)   ch_pending[gi] <= 1;
                3'd6: if (p_ext)   ch_pending[gi] <= 1;
                default: ;
            endcase
        end
    end
end
endgenerate

// ============================================================
// Sequencer
// ============================================================
localparam SEQ_IDLE     = 4'd0;
localparam SEQ_ARB0     = 4'd1;  // check ch0
localparam SEQ_ARB1     = 4'd2;  // check ch1..7
localparam SEQ_LOAD     = 4'd3;
localparam SEQ_CHECK    = 4'd4;
localparam SEQ_RD_ADDR  = 4'd5;
localparam SEQ_RD_DATA  = 4'd6;
localparam SEQ_WR_ADDR  = 4'd7;
localparam SEQ_WR_RESP  = 4'd8;
localparam SEQ_TSWRITE  = 4'd9;
localparam SEQ_TSRESP   = 4'd10;
localparam SEQ_DONE     = 4'd11;
localparam SEQ_NEXT     = 4'd12;

reg [3:0]  seq_state;
reg [2:0]  seq_ch;
reg [7:0]  seq_words;
reg [31:0] seq_src, seq_dst, seq_ctrl, seq_rdata;
reg [2:0]  rr;         // round-robin pointer
reg [2:0]  arb_cnt;    // arbiter scan counter

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        seq_state <= SEQ_IDLE;
        seq_ch    <= 0; seq_words <= 0;
        seq_src   <= 0; seq_dst   <= 0;
        seq_ctrl  <= 0; seq_rdata <= 0;
        rr        <= 0; arb_cnt   <= 0;
        m_awvalid <= 0; m_wvalid  <= 0; m_bready  <= 0;
        m_arvalid <= 0; m_rready  <= 0;
        m_awaddr  <= 0; m_wdata   <= 0; m_wstrb   <= 4'hF;
        m_araddr  <= 0;
        irq_complete <= 0; irq_chain <= 0; irq_error <= 0;
        ch_enabled   <= 0;
    end else begin
        irq_complete <= 0;
        irq_chain    <= 0;
        irq_error    <= (m_bresp[1] & m_bvalid) | (m_rresp[1] & m_rvalid);

        case (seq_state)
            SEQ_IDLE: begin
                arb_cnt   <= 0;
                seq_ch    <= rr;
                seq_state <= SEQ_ARB0;
            end

            SEQ_ARB0: begin
                // Check if current channel is pending
                if (ch_pending[seq_ch]) begin
                    seq_state <= SEQ_LOAD;
                end else begin
                    // Advance to next channel
                    arb_cnt <= arb_cnt + 1;
                    if (seq_ch == 3'd7)
                        seq_ch <= 3'd0;
                    else
                        seq_ch <= seq_ch + 1;
                    if (arb_cnt == 3'd7)
                        seq_state <= SEQ_IDLE; // no pending channels
                    else
                        seq_state <= SEQ_ARB0;
                end
            end

            SEQ_LOAD: begin
                seq_src   <= desc_ram[seq_ch*64 + ch_desc[seq_ch]*4 + 0];
                seq_dst   <= desc_ram[seq_ch*64 + ch_desc[seq_ch]*4 + 1];
                seq_ctrl  <= desc_ram[seq_ch*64 + ch_desc[seq_ch]*4 + 2];
                seq_words <= desc_ram[seq_ch*64 + ch_desc[seq_ch]*4 + 2][7:0];
                ch_pending[seq_ch] <= 0;
                rr <= (seq_ch == 3'd7) ? 3'd0 : seq_ch + 1;
                seq_state <= SEQ_CHECK;
            end

            SEQ_CHECK: begin
                if (!seq_ctrl[15]) begin
                    seq_state <= SEQ_NEXT;
                end else if (seq_ctrl[12] && fault_in) begin
                    irq_complete[seq_ch] <= 1;
                    seq_state <= SEQ_NEXT;
                end else if (seq_words == 0) begin
                    seq_state <= seq_ctrl[11] ? SEQ_TSWRITE : SEQ_DONE;
                end else begin
                    seq_state <= SEQ_RD_ADDR;
                end
            end

            SEQ_RD_ADDR: begin
                m_araddr  <= seq_src;
                m_arvalid <= 1;
                m_rready  <= 1;
                seq_state <= SEQ_RD_DATA;
            end

            SEQ_RD_DATA: begin
                if (m_arvalid && m_arready) m_arvalid <= 0;
                if (m_rvalid && m_rready) begin
                    seq_rdata <= m_rdata;
                    m_rready  <= 0;
                    seq_src   <= seq_src + 4;
                    seq_state <= SEQ_WR_ADDR;
                end
            end

            SEQ_WR_ADDR: begin
                m_awaddr  <= seq_dst;
                m_awvalid <= 1;
                m_wdata   <= seq_rdata;
                m_wstrb   <= 4'hF;
                m_wvalid  <= 1;
                m_bready  <= 1;
                seq_state <= SEQ_WR_RESP;
            end

            SEQ_WR_RESP: begin
                if (m_awvalid && m_awready) m_awvalid <= 0;
                if (m_wvalid  && m_wready)  m_wvalid  <= 0;
                if (m_bvalid && m_bready) begin
                    m_bready  <= 0;
                    seq_dst   <= seq_dst + 4;
                    seq_words <= seq_words - 1;
                    if (seq_words == 8'd1)
                        seq_state <= seq_ctrl[11] ? SEQ_TSWRITE : SEQ_DONE;
                    else
                        seq_state <= SEQ_RD_ADDR;
                end
            end

            SEQ_TSWRITE: begin
                m_awaddr  <= seq_dst;
                m_awvalid <= 1;
                m_wdata   <= dc_local_time[31:0];
                m_wstrb   <= 4'hF;
                m_wvalid  <= 1;
                m_bready  <= 1;
                seq_state <= SEQ_TSRESP;
            end

            SEQ_TSRESP: begin
                if (m_awvalid && m_awready) m_awvalid <= 0;
                if (m_wvalid  && m_wready)  m_wvalid  <= 0;
                if (m_bvalid && m_bready) begin
                    m_bready  <= 0;
                    seq_state <= SEQ_DONE;
                end
            end

            SEQ_DONE: begin
                irq_complete[seq_ch] <= 1;
                seq_state <= SEQ_NEXT;
            end

            SEQ_NEXT: begin
                if (seq_ctrl[13]) begin
                    // Chain — advance to next descriptor, fire immediately
                    ch_desc[seq_ch]    <= ch_desc[seq_ch] + 1;
                    ch_pending[seq_ch] <= 1;
                    seq_state <= SEQ_IDLE;
                end else if (seq_ctrl[14]) begin
                    // Auto-reload — restart from desc 0, wait for next trigger
                    ch_desc[seq_ch]   <= 0;
                    irq_chain[seq_ch] <= 1;
                    seq_state <= SEQ_IDLE;
                end else begin
                    // Single shot — disable channel
                    ch_desc[seq_ch]    <= 0;
                    ch_enabled[seq_ch] <= 0;
                    irq_chain[seq_ch]  <= 1;
                    seq_state <= SEQ_IDLE;
                end
            end

            default: seq_state <= SEQ_IDLE;
        endcase
    end
end

// ============================================================
// Config slave
// ============================================================
integer ci;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cfg_awready <= 1; cfg_wready <= 1; cfg_bvalid <= 0;
        cfg_arready <= 1; cfg_rvalid <= 0;
        cfg_bresp   <= 0; cfg_rresp  <= 0; cfg_rdata  <= 0;
        ch_sw_trig  <= 0;
        for (ci = 0; ci < NUM_CHANNELS; ci = ci + 1)
            ch_desc[ci] <= 0;
    end else begin
        cfg_bvalid <= 0;
        cfg_rvalid <= 0;

        if (cfg_awvalid && cfg_wvalid) begin
            cfg_bvalid <= 1;
            cfg_bresp  <= 0;
            if (cfg_awaddr[11] == 0) begin
                ci = cfg_awaddr[10:8];
                desc_ram[ci*64 + cfg_awaddr[7:4]*4 + cfg_awaddr[3:2]] <= cfg_wdata;
            end else begin
                ci = cfg_awaddr[4:2];
                if (ci < NUM_CHANNELS) begin
                    if (cfg_wdata[0]) ch_enabled[ci] <= 1;
                    if (cfg_wdata[1]) ch_sw_trig[ci] <= 1;
                end
            end
        end
        if (cfg_bvalid && cfg_bready) cfg_bvalid <= 0;

        if (cfg_arvalid) begin
            cfg_rvalid <= 1;
            cfg_rresp  <= 0;
            if (cfg_araddr[11] == 0) begin
                ci = cfg_araddr[10:8];
                cfg_rdata <= desc_ram[ci*64 + cfg_araddr[7:4]*4 + cfg_araddr[3:2]];
            end else begin
                ci = cfg_araddr[4:2];
                cfg_rdata <= {24'h0, ch_enabled[ci], ch_pending[ci],
                              seq_state, ch_desc[ci]};
            end
        end
        if (cfg_rvalid && cfg_rready) cfg_rvalid <= 0;
    end
end

endmodule