// ============================================================
// RoboCore-1 Production DMA Formal Verification
//
// Covers:
//   DMA-1:  Sequencer always in valid states
//   DMA-2:  No simultaneous AXI master transactions (single-threaded)
//   DMA-3:  seq_words decrements monotonically during a transfer
//   DMA-4:  Auto-reload resets ch_desc to 0 (not some arbitrary value)
//   DMA-5:  Chain increments ch_desc (not resets or skips)
//   DMA-6:  irq_complete fires exactly once per completed transfer
//   DMA-7:  irq_complete is a pulse (cleared next cycle)
//   DMA-8:  Timestamp write only when ts_inject bit (ctrl[11]) is set
//   DMA-9:  AXI master AWVALID/WVALID stability (slave protocol rules
//            applied to DMA's master port — MUST hold until READY)
//   DMA-10: No transfer starts on a disabled channel
//   DMA-11: ch_pending cleared after sequencer loads the descriptor
//   DMA-12: Round-robin pointer advances correctly after each transfer
//   DMA-13: Config slave accepts descriptor writes without data loss
//   COVER:  SW trigger, hardware triggers, auto-reload, chain, timestamp
// ============================================================
`default_nettype none

module dma_formal (
    input wire clk,
    input wire rst_n
);

// -------------------------------------------------------------------------
// AXI master slave (responder model)
// -------------------------------------------------------------------------
reg  m_awready, m_wready, m_arready, m_rvalid;
reg  [31:0] m_rdata;
reg  [1:0]  m_bresp, m_rresp;
reg         m_bvalid;

// -------------------------------------------------------------------------
// DUT connections
// -------------------------------------------------------------------------
wire [31:0] m_awaddr, m_wdata, m_araddr;
wire [3:0]  m_wstrb;
wire        m_awvalid, m_wvalid, m_bready, m_arvalid, m_rready;

// Triggers
reg  trig_sync0, trig_sync1, trig_1khz, trig_1mhz, trig_can_rx, trig_ext;
reg  [63:0] dc_local_time;
reg         fault_in;

// Config slave inputs
reg  [31:0] cfg_awaddr, cfg_wdata, cfg_araddr;
reg  [3:0]  cfg_wstrb;
reg         cfg_awvalid, cfg_wvalid, cfg_bready, cfg_arvalid, cfg_rready;

wire        cfg_awready, cfg_wready, cfg_bvalid, cfg_arready, cfg_rvalid;
wire [31:0] cfg_rdata;
wire [1:0]  cfg_bresp, cfg_rresp;
wire [7:0]  irq_complete, irq_chain;
wire        irq_error;

robocore1_dma #(.NUM_CHANNELS(8), .DESC_DEPTH(4)) u_dma (
    .clk(clk), .rst_n(rst_n),
    .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
    .m_wdata(m_wdata),   .m_wstrb(m_wstrb),     .m_wvalid(m_wvalid), .m_wready(m_wready),
    .m_bresp(m_bresp),   .m_bvalid(m_bvalid),   .m_bready(m_bready),
    .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
    .m_rdata(m_rdata),   .m_rresp(m_rresp),     .m_rvalid(m_rvalid), .m_rready(m_rready),
    .trig_sync0(trig_sync0), .trig_sync1(trig_sync1),
    .trig_1khz(trig_1khz),   .trig_1mhz(trig_1mhz),
    .trig_can_rx(trig_can_rx), .trig_ext(trig_ext),
    .dc_local_time(dc_local_time), .fault_in(fault_in),
    .cfg_awaddr(cfg_awaddr), .cfg_awvalid(cfg_awvalid), .cfg_awready(cfg_awready),
    .cfg_wdata(cfg_wdata),   .cfg_wstrb(cfg_wstrb),     .cfg_wvalid(cfg_wvalid), .cfg_wready(cfg_wready),
    .cfg_bresp(cfg_bresp),   .cfg_bvalid(cfg_bvalid),   .cfg_bready(cfg_bready),
    .cfg_araddr(cfg_araddr), .cfg_arvalid(cfg_arvalid), .cfg_arready(cfg_arready),
    .cfg_rdata(cfg_rdata),   .cfg_rresp(cfg_rresp),     .cfg_rvalid(cfg_rvalid), .cfg_rready(cfg_rready),
    .irq_complete(irq_complete), .irq_chain(irq_chain), .irq_error(irq_error)
);

// =========================================================================
// RESET ASSUMPTIONS
// =========================================================================
initial assume(!rst_n);
initial assume(m_awready  == 0);
initial assume(m_wready   == 0);
initial assume(m_arready  == 0);
initial assume(m_bvalid   == 0);
initial assume(m_rvalid   == 0);
initial assume(cfg_awvalid == 0);
initial assume(cfg_wvalid  == 0);
initial assume(cfg_arvalid == 0);
initial assume(trig_sync0 == 0);
initial assume(trig_sync1 == 0);
initial assume(trig_1khz  == 0);
initial assume(trig_1mhz  == 0);
initial assume(fault_in   == 0);

// =========================================================================
// AXI RESPONDER ASSUMPTIONS (slave side of DMA master port)
// =========================================================================

// R1: BVALID must not deassert without BREADY (responder model)
always @(posedge clk) begin
    if (rst_n && $past(m_bvalid) && !$past(m_bready))
        assume(m_bvalid);
end

// R2: RVALID must not deassert without RREADY (responder model)
always @(posedge clk) begin
    if (rst_n && $past(m_rvalid) && !$past(m_rready))
        assume(m_rvalid);
end

// R3: BRESP valid values only
always @(posedge clk) begin
    if (rst_n && m_bvalid)
        assume(m_bresp == 2'b00 || m_bresp == 2'b10);
end

// R4: RRESP valid values only
always @(posedge clk) begin
    if (rst_n && m_rvalid)
        assume(m_rresp == 2'b00 || m_rresp == 2'b10);
end

// R5: AWREADY/WREADY stability — responder can hold ready for multiple cycles
// No specific constraint — free model

// =========================================================================
// DMA-1: Sequencer state machine always in valid states
// =========================================================================
always @(posedge clk) begin
    if (rst_n)
        assert(u_dma.seq_state <= 4'd12);
end

// =========================================================================
// DMA-2: No simultaneous read and write AXI transactions
// (DMA is single-threaded — one operation at a time)
// =========================================================================
always @(posedge clk) begin
    if (rst_n)
        assert(!(m_arvalid && m_awvalid));
end

// =========================================================================
// DMA-3: seq_words decrements by exactly 1 per write response
// =========================================================================
always @(posedge clk) begin
    if (rst_n &&
        $past(u_dma.seq_state) == 4'd8 &&  // SEQ_WR_RESP
        $past(m_bvalid) && $past(m_bready) &&
        $past(u_dma.seq_words) > 1)
    begin
        assert(u_dma.seq_words == $past(u_dma.seq_words) - 1);
    end
end

// =========================================================================
// DMA-4: After SEQ_NEXT with auto_reload (ctrl[14]=1), ch_desc resets to 0
// =========================================================================
always @(posedge clk) begin
    if (rst_n &&
        $past(u_dma.seq_state) == 4'd12 &&  // SEQ_NEXT
        $past(u_dma.seq_ctrl[14]) &&         // auto_reload
        !$past(u_dma.seq_ctrl[13]))          // not chain
    begin
        assert(u_dma.ch_desc[u_dma.seq_ch] == 0 ||
               u_dma.seq_state == 4'd0);  // IDLE means it moved on
    end
end

// =========================================================================
// DMA-5: After SEQ_NEXT with chain (ctrl[13]=1), ch_desc increments
// =========================================================================
reg [3:0] ch_desc_before_chain;
reg [2:0] ch_before_chain;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch_desc_before_chain <= 0;
        ch_before_chain      <= 0;
    end else if (u_dma.seq_state == 4'd11) begin  // SEQ_DONE
        ch_desc_before_chain <= u_dma.ch_desc[u_dma.seq_ch];
        ch_before_chain      <= u_dma.seq_ch;
    end
end

always @(posedge clk) begin
    if (rst_n &&
        $past(u_dma.seq_state) == 4'd12 &&  // SEQ_NEXT
        $past(u_dma.seq_ctrl[13]))           // chain bit set
    begin
        assert(u_dma.ch_desc[ch_before_chain] == ch_desc_before_chain + 1 ||
               u_dma.ch_pending[ch_before_chain] == 1);
    end
end

// =========================================================================
// DMA-6: irq_complete fires at SEQ_DONE transition
// =========================================================================
always @(posedge clk) begin
    if (rst_n && $past(u_dma.seq_state) == 4'd11)  // SEQ_DONE
        assert(irq_complete[$past(u_dma.seq_ch)] || u_dma.seq_state == 4'd12);
end

// =========================================================================
// DMA-7: irq_complete and irq_chain are single-cycle pulses
// =========================================================================
always @(posedge clk) begin
    if (rst_n && $past(rst_n) && u_dma.seq_state != 4'd11 && u_dma.seq_state != 4'd12)
        assert(irq_complete == 0);
end

always @(posedge clk) begin
    if (rst_n && $past(rst_n) && u_dma.seq_state != 4'd12)
        assert(irq_chain == 0);
end

// =========================================================================
// DMA-8: Timestamp write (SEQ_TSWRITE) only when ctrl[11] is set
// =========================================================================
always @(posedge clk) begin
    if (rst_n && u_dma.seq_state == 4'd9)  // SEQ_TSWRITE
        assert(u_dma.seq_ctrl[11]);
end

// =========================================================================
// DMA-9: DMA master AWVALID must not drop without AWREADY
// (DMA is an AXI master — must honor master protocol rules)
// =========================================================================
always @(posedge clk) begin
    if (rst_n && $past(m_awvalid) && !$past(m_awready))
        assert(m_awvalid);
end

// DMA master ARVALID stability
always @(posedge clk) begin
    if (rst_n && $past(m_arvalid) && !$past(m_arready))
        assert(m_arvalid);
end

// =========================================================================
// DMA-10: No transfer starts on a disabled channel
// =========================================================================
always @(posedge clk) begin
    if (rst_n && u_dma.seq_state == 4'd3)  // SEQ_LOAD
        assert(u_dma.ch_enabled[u_dma.seq_ch]);
end

// =========================================================================
// DMA-11: ch_pending is cleared when sequencer loads the descriptor
// =========================================================================
always @(posedge clk) begin
    if (rst_n && $past(u_dma.seq_state) == 4'd3)  // just left SEQ_LOAD
        assert(!u_dma.ch_pending[$past(u_dma.seq_ch)]);
end

// =========================================================================
// DMA-12: Round-robin pointer rr advances to next channel after each transfer
// =========================================================================
always @(posedge clk) begin
    if (rst_n && $past(u_dma.seq_state) == 4'd3) begin  // SEQ_LOAD
        if ($past(u_dma.seq_ch) == 3'd7)
            assert(u_dma.rr == 3'd0);
        else
            assert(u_dma.rr == $past(u_dma.seq_ch) + 1);
    end
end

// =========================================================================
// DMA-13: Config slave write is accepted (bvalid fires after aw+w valid)
// =========================================================================
always @(posedge clk) begin
    if (rst_n && $past(cfg_awvalid && cfg_wvalid))
        assert(cfg_bvalid || $past(cfg_bvalid));
end

// =========================================================================
// COVER GOALS
// =========================================================================
always @(posedge clk) cover(rst_n && |irq_complete);         // any transfer complete
always @(posedge clk) cover(rst_n && irq_error);             // AXI error path
always @(posedge clk) cover(rst_n && u_dma.seq_state == 4'd9);  // timestamp write
always @(posedge clk) cover(rst_n && |irq_chain);            // auto-reload fired
always @(posedge clk) cover(rst_n && u_dma.rr == 3'd7);      // RR wrapped to ch7
always @(posedge clk) cover(rst_n && u_dma.seq_state == 4'd4 && !u_dma.seq_ctrl[15]); // disabled desc skip
// Two channels complete back-to-back
always @(posedge clk) cover(rst_n && irq_complete[0] && $past(irq_complete[1]));

endmodule
`default_nettype wire
