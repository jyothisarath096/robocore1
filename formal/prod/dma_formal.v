`default_nettype none
// ============================================================
// RoboCore-1 DMA Correctness Formal — Production Grade v4
// Uses `ifdef FORMAL observation ports on DUT (f_* signals)
// bind passes all DUT outputs + f_* ports to formal module
// ============================================================
module dma_formal (
    input wire        clk, rst_n,
    // AXI master outputs (DUT drives these)
    input wire [31:0] m_awaddr,
    input wire        m_awvalid,
    input wire [31:0] m_wdata,
    input wire [3:0]  m_wstrb,
    input wire        m_wvalid,
    input wire        m_bready,
    input wire [31:0] m_araddr,
    input wire        m_arvalid,
    input wire        m_rready,
    // AXI master inputs (environment drives these)
    input wire        m_awready, m_wready,
    input wire [1:0]  m_bresp,
    input wire        m_bvalid,
    input wire        m_arready,
    input wire [31:0] m_rdata,
    input wire [1:0]  m_rresp,
    input wire        m_rvalid,
    // Triggers
    input wire        trig_sync0, trig_sync1,
    input wire        trig_1khz,  trig_1mhz,
    input wire        trig_can_rx, trig_ext,
    input wire [63:0] dc_local_time,
    input wire        fault_in,
    // IRQ outputs
    input wire [7:0]  irq_complete,
    input wire [7:0]  irq_chain,
    input wire        irq_error,
    // Formal observation ports (from `ifdef FORMAL in DUT)
    input wire [3:0]  f_seq_state,
    input wire [2:0]  f_seq_ch,
    input wire [7:0]  f_seq_words,
    input wire [31:0] f_seq_ctrl,
    input wire [2:0]  f_rr,
    input wire [7:0]  f_ch_enabled,
    input wire [7:0]  f_ch_pending
);

localparam SEQ_LOAD    = 4'd3;
localparam SEQ_RD_DATA = 4'd6;
localparam SEQ_WR_RESP = 4'd8;
localparam SEQ_TSWRITE = 4'd9;
localparam SEQ_TSRESP  = 4'd10;
localparam SEQ_DONE    = 4'd11;
localparam SEQ_NEXT    = 4'd12;

// =========================================================================
// AXI RESPONDER ASSUMPTIONS
// =========================================================================
always @(posedge clk) begin
    if (!rst_n) begin assume(m_bvalid==0); assume(m_rvalid==0); end
end
always @(posedge clk) begin
    if (rst_n && $past(m_bvalid) && !$past(m_bready)) assume(m_bvalid);
    if (rst_n && $past(m_rvalid) && !$past(m_rready)) assume(m_rvalid);
    if (rst_n && m_bvalid) assume(m_bresp==2'b00 || m_bresp==2'b10);
    if (rst_n && m_rvalid) assume(m_rresp==2'b00 || m_rresp==2'b10);
end

// =========================================================================
// INDUCTION INVARIANTS
// =========================================================================
always @(posedge clk) if (rst_n) assert(f_seq_state <= 4'd12);
always @(posedge clk) if (rst_n) assert(f_seq_ch <= 3'd7);
always @(posedge clk) if (rst_n) assert(f_rr <= 3'd7);
always @(posedge clk) if (rst_n) assert(m_awvalid == m_wvalid);
always @(posedge clk)
    if (rst_n && f_seq_state != SEQ_DONE && f_seq_state != SEQ_NEXT)
        assert(irq_complete == 0);
always @(posedge clk)
    if (rst_n && f_seq_state != SEQ_NEXT)
        assert(irq_chain == 0);
always @(posedge clk)
    if (rst_n) assert(!(m_arvalid && m_awvalid));
always @(posedge clk)
    if (rst_n && m_bready)
        assert(f_seq_state == SEQ_WR_RESP || f_seq_state == SEQ_TSRESP);
always @(posedge clk)
    if (rst_n && m_rready) assert(f_seq_state == SEQ_RD_DATA);

// =========================================================================
// D1: seq_state in {0..12}
// =========================================================================
always @(posedge clk) if (rst_n) assert(f_seq_state <= 4'd12);

// =========================================================================
// D2: seq_ch in {0..7}
// =========================================================================
always @(posedge clk) if (rst_n) assert(f_seq_ch <= 3'd7);

// =========================================================================
// D3: no simultaneous AXI master read+write
// =========================================================================
always @(posedge clk) if (rst_n) assert(!(m_arvalid && m_awvalid));

// =========================================================================
// D4: seq_words decrements by 1 per write response
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) &&
        $past(f_seq_state) == SEQ_WR_RESP &&
        $past(m_bvalid) && $past(m_bready) &&
        $past(f_seq_words) > 1)
        assert(f_seq_words == $past(f_seq_words) - 1);

// =========================================================================
// D5: irq_complete fires on transition out of SEQ_DONE
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(f_seq_state) == SEQ_DONE)
        assert(irq_complete[$past(f_seq_ch)] || f_seq_state == SEQ_NEXT);

// =========================================================================
// D6: irq_complete zero outside SEQ_DONE/SEQ_NEXT
// =========================================================================
always @(posedge clk)
    if (rst_n && f_seq_state != SEQ_DONE && f_seq_state != SEQ_NEXT)
        assert(irq_complete == 0);

// =========================================================================
// D7: irq_chain zero outside SEQ_NEXT
// =========================================================================
always @(posedge clk)
    if (rst_n && f_seq_state != SEQ_NEXT) assert(irq_chain == 0);

// =========================================================================
// D8: timestamp write only when f_seq_ctrl[11] set
// =========================================================================
always @(posedge clk)
    if (rst_n && f_seq_state == SEQ_TSWRITE) assert(f_seq_ctrl[11]);

// =========================================================================
// D9: AWVALID stable until AWREADY
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(m_awvalid) && !$past(m_awready))
        assert(m_awvalid);

// =========================================================================
// D10: ARVALID stable until ARREADY
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(m_arvalid) && !$past(m_arready))
        assert(m_arvalid);

// =========================================================================
// D11: no transfer on disabled channel
// =========================================================================
always @(posedge clk)
    if (rst_n && f_seq_state == SEQ_LOAD)
        assert(f_ch_enabled[f_seq_ch]);

// =========================================================================
// D12: rr in {0..7}
// =========================================================================
always @(posedge clk) if (rst_n) assert(f_rr <= 3'd7);

// =========================================================================
// D13: rr advances (f_seq_ch+1) mod 8 after SEQ_LOAD
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(f_seq_state) == SEQ_LOAD) begin
        if ($past(f_seq_ch) == 3'd7) assert(f_rr == 3'd0);
        else                         assert(f_rr == $past(f_seq_ch) + 1);
    end

// =========================================================================
// D14: m_awvalid == m_wvalid always
// =========================================================================
always @(posedge clk) if (rst_n) assert(m_awvalid == m_wvalid);

// =========================================================================
// D15: irq_error only on AXI error response
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && irq_error)
        assert($past(m_bresp[1] & m_bvalid) || $past(m_rresp[1] & m_rvalid));

// =========================================================================
// D16: m_bready only in SEQ_WR_RESP or SEQ_TSRESP
// =========================================================================
always @(posedge clk)
    if (rst_n && m_bready)
        assert(f_seq_state == SEQ_WR_RESP || f_seq_state == SEQ_TSRESP);

// =========================================================================
// COVER GOALS
// =========================================================================
always @(posedge clk) cover(rst_n && |irq_complete);
always @(posedge clk) cover(rst_n && |irq_chain);
always @(posedge clk) cover(rst_n && irq_error);
always @(posedge clk) cover(rst_n && f_seq_state == SEQ_TSWRITE);
always @(posedge clk) cover(rst_n && f_rr == 3'd0 && $past(f_rr) == 3'd7);
always @(posedge clk) cover(rst_n && f_seq_state == SEQ_DONE);

endmodule

bind robocore1_dma dma_formal formal_inst (
    .clk(clk), .rst_n(rst_n),
    .m_awaddr(m_awaddr), .m_awvalid(m_awvalid),
    .m_wdata(m_wdata),   .m_wstrb(m_wstrb),
    .m_wvalid(m_wvalid), .m_bready(m_bready),
    .m_araddr(m_araddr), .m_arvalid(m_arvalid),
    .m_rready(m_rready),
    .m_awready(m_awready), .m_wready(m_wready),
    .m_bresp(m_bresp),     .m_bvalid(m_bvalid),
    .m_arready(m_arready), .m_rdata(m_rdata),
    .m_rresp(m_rresp),     .m_rvalid(m_rvalid),
    .trig_sync0(trig_sync0), .trig_sync1(trig_sync1),
    .trig_1khz(trig_1khz),   .trig_1mhz(trig_1mhz),
    .trig_can_rx(trig_can_rx), .trig_ext(trig_ext),
    .dc_local_time(dc_local_time), .fault_in(fault_in),
    .irq_complete(irq_complete),
    .irq_chain(irq_chain),
    .irq_error(irq_error),
    .f_seq_state(f_seq_state),
    .f_seq_ch(f_seq_ch),
    .f_seq_words(f_seq_words),
    .f_seq_ctrl(f_seq_ctrl),
    .f_rr(f_rr),
    .f_ch_enabled(f_ch_enabled),
    .f_ch_pending(f_ch_pending)
);
`default_nettype wire
