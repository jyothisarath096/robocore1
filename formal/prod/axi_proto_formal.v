// ============================================================
// RoboCore-1 Production AXI4-Lite Protocol Formal Verification
// ZipCPU-style properties — full ARM AXI4-Lite spec compliance
//
// Covers:
//   1. AWVALID/WVALID stability once asserted
//   2. ARVALID stability once asserted
//   3. BVALID never without a preceding write
//   4. RVALID never without a preceding read
//   5. BRESP/RRESP only OKAY(00) or SLVERR(10) — never EXOKAY/DECERR
//   6. State machine always in valid states
//   7. Simultaneous write address + data handshake required (AXI4-Lite)
//   8. No BVALID deassert without BREADY
//   9. No RVALID deassert without RREADY
//   10. awready/wready always in sync (AXI4-Lite)
//   11. IRQ only when irq_pending & ~irq_mask
//   12. SLVERR on unmapped addresses
//   13. CHIP_ID register always returns correct value
//   14. Scratch register round-trips
//   15. Cover: every channel written and read back
// ============================================================
`default_nettype none

module axi_proto_formal (
    input wire clk,
    input wire rst_n
);

// -------------------------------------------------------------------------
// DUT connections
// -------------------------------------------------------------------------
reg  [31:0] awaddr, wdata, araddr;
reg         awvalid, wvalid, arvalid;
reg  [3:0]  wstrb;
reg         bready, rready;
wire        awready, wready, bvalid, arready, rvalid;
wire [1:0]  bresp, rresp;
wire [31:0] rdata;
wire        irq_out;
reg  [15:0] irq_in;

robocore1_axi #(.CHIP_ID(32'hAC010002)) u_axi (
    .aclk(clk), .aresetn(rst_n),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
    .wdata(wdata),  .wstrb(wstrb),  .wvalid(wvalid),  .wready(wready),
    .bresp(bresp),  .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready),
    .rdata(rdata),   .rresp(rresp),   .rvalid(rvalid), .rready(rready),
    .irq_in(irq_in), .irq_out(irq_out),
    // Tie off all sub-block IOs
    .pwm_reg_ch(), .pwm_reg_we(), .pwm_reg_wdata(),
    .pwm_fault(1'b0), .pwm_out(16'h0),
    .enc_reg_ch(), .enc_reg_req(),
    .enc_reg_rdata(32'h0), .enc_direction(16'h0),
    .enc_idx_flag(16'h0),  .enc_error_flag(16'h0),
    .enc_clear_pos(), .enc_clear_idx(),
    .pid_target_flat(), .pid_kp_flat(), .pid_ki_flat(),
    .pid_kd_flat(), .pid_out_max_flat(), .pid_enable(),
    .pid_out_flat(128'h0), .pid_at_target(8'h0), .pid_saturated(8'h0),
    .fault_reg(32'h0), .fault_clear(),
    .safe_state(1'b0), .estop_active(1'b0),
    .wd_pet(), .wd_enable(),
    .can_tx_id(), .can_tx_ide(), .can_tx_rtr(),
    .can_tx_brs(), .can_tx_fdf(), .can_tx_dlc(),
    .can_tx_data(), .can_tx_valid(),
    .can_rx_ack(), .can_rx_id(29'h0),
    .can_rx_ide(1'b0), .can_rx_brs(1'b0), .can_rx_fdf(1'b0),
    .can_rx_dlc(4'h0), .can_rx_data(512'h0), .can_rx_valid(1'b0),
    .can_bus_off(1'b0), .can_err_passive(1'b0),
    .can_tx_err_cnt(8'h0), .can_rx_err_cnt(8'h0),
    .ec_pd_addr(), .ec_pd_wdata(), .ec_pd_we(), .ec_pd_re(),
    .ec_pd_rdata(32'h0), .ec_pd_valid(1'b0),
    .ec_state(4'h0), .ec_link(1'b0),
    .ec_operational(1'b0), .ec_wkc(16'h0), .ec_timeout(1'b0),
    .sys_reset_req()
);

// =========================================================================
// RESET ASSUMPTIONS — full state constrain at cycle 0
// =========================================================================
initial assume(!rst_n);
initial assume(awvalid == 0);
initial assume(wvalid  == 0);
initial assume(arvalid == 0);
initial assume(bready  == 0);
initial assume(rready  == 0);
initial assume(irq_in  == 0);
initial assume(u_axi.wr_state == 2'd0);
initial assume(u_axi.rd_state == 2'd0);
initial assume(u_axi.bvalid   == 0);
initial assume(u_axi.rvalid   == 0);
initial assume(u_axi.awready  == 0);
initial assume(u_axi.wready   == 0);
initial assume(u_axi.arready  == 0);

// =========================================================================
// MASTER PROTOCOL ASSUMPTIONS
// AXI4-Lite spec §A3: once VALID is asserted, it must hold until READY
// =========================================================================

// A1: AW channel — AWVALID must not deassert without AWREADY
always @(posedge clk) begin
    if (rst_n && $past(awvalid) && !$past(awready))
        assume(awvalid);
end

// A2: W channel — WVALID must not deassert without WREADY
always @(posedge clk) begin
    if (rst_n && $past(wvalid) && !$past(wready))
        assume(wvalid);
end

// A3: AR channel — ARVALID must not deassert without ARREADY
always @(posedge clk) begin
    if (rst_n && $past(arvalid) && !$past(arready))
        assume(arvalid);
end

// A4: AXI4-Lite — AWVALID and WVALID always arrive together
// (No support for split AW/W — both must be asserted simultaneously)
always @(posedge clk) begin
    if (rst_n) assume(awvalid == wvalid);
end

// A5: Address stability — once latched, addr must not change until handshake
always @(posedge clk) begin
    if (rst_n && $past(awvalid) && !$past(awready))
        assume(awaddr == $past(awaddr));
end

always @(posedge clk) begin
    if (rst_n && $past(arvalid) && !$past(arready))
        assume(araddr == $past(araddr));
end

// A6: WSTRB — only valid combinations (no X states)
always @(posedge clk) begin
    if (rst_n && wvalid)
        assume(wstrb != 4'bxxxx);
end

// =========================================================================
// AXI4-LITE SLAVE PROTOCOL PROPERTIES
// =========================================================================

// P1: Write state machine stays in valid states
always @(posedge clk) begin
    if (rst_n) assert(u_axi.wr_state <= 2'd2);
end

// P2: Read state machine stays in valid states
always @(posedge clk) begin
    if (rst_n) assert(u_axi.rd_state <= 2'd2);
end

// P3: BRESP must be OKAY(00) or SLVERR(10) — ARM spec §A3.4.4
// Never EXOKAY(01) or DECERR(11)
always @(posedge clk) begin
    if (rst_n && bvalid)
        assert(bresp == 2'b00 || bresp == 2'b10);
end

// P4: RRESP same constraint
always @(posedge clk) begin
    if (rst_n && rvalid)
        assert(rresp == 2'b00 || rresp == 2'b10);
end

// P5: BVALID must not deassert without BREADY — ARM spec §A3.2.2
always @(posedge clk) begin
    if (rst_n && $past(bvalid) && !$past(bready))
        assert(bvalid);
end

// P6: RVALID must not deassert without RREADY — ARM spec §A3.2.2
always @(posedge clk) begin
    if (rst_n && $past(rvalid) && !$past(rready))
        assert(rvalid);
end

// P7: BVALID only asserted after a write was accepted
// (wr_state must have been in WR_DECODE or WR_RESP, never spontaneously)
always @(posedge clk) begin
    if (rst_n && bvalid)
        assert(u_axi.wr_state == 2'd2 || u_axi.wr_state == 2'd1);
end

// P8: No simultaneous BVALID and new AWVALID handshake (pipelining disallowed
// in AXI4-Lite — single outstanding transaction)
always @(posedge clk) begin
    if (rst_n && bvalid)
        assert(!(awvalid && awready));
end

// P9: awready and wready are always in sync (AXI4-Lite constraint)
always @(posedge clk) begin
    if (rst_n)
        assert(u_axi.awready == u_axi.wready);
end

// P10: IRQ output is strictly the OR of active IRQs
always @(posedge clk) begin
    if (rst_n)
        assert(irq_out == |u_axi.irq_active);
end

// P11: irq_active is always masked — no IRQ can escape the mask
always @(posedge clk) begin
    if (rst_n)
        assert((u_axi.irq_active & u_axi.irq_mask) == 0);
end

// P12: CHIP_ID read always returns 32'hAC010002 (BLOCK_SYS, offset 0x0000)
always @(posedge clk) begin
    if (rst_n && rvalid && (u_axi.rd_addr_r[19:16] == 4'h7) && (u_axi.rd_addr_r[15:0] == 16'h0000))
        assert(rdata == 32'hAC010002);
end

// P13: RRESP=SLVERR on unmapped read addresses (BLOCK > 7)
always @(posedge clk) begin
    if (rst_n && rvalid && (u_axi.rd_addr_r[19:16] > 4'h7))
        assert(rresp == 2'b10);
end

// P14: BRESP=SLVERR on unmapped write addresses (BLOCK > 7)
always @(posedge clk) begin
    if (rst_n && bvalid && (u_axi.wr_addr_r[19:16] > 4'h7))
        assert(bresp == 2'b10);
end

// P15: Scratch register must be writable — what we write is readable back
// (tracked via a witness register)
reg  [31:0] scratch_written;
reg         scratch_was_written;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scratch_written    <= 0;
        scratch_was_written <= 0;
    end else begin
        // Track when we write BLOCK_SYS offset 0x0008
        if (u_axi.wr_state == 2'd1 &&
            u_axi.wr_addr_r[19:16] == 4'h7 &&
            u_axi.wr_addr_r[15:0]  == 16'h0008) begin
            scratch_written     <= u_axi.wr_data_r;
            scratch_was_written <= 1;
        end
    end
end

always @(posedge clk) begin
    if (rst_n && scratch_was_written)
        assert(u_axi.sys_scratch == scratch_written);
end

// P16: wd_pet and wd_enable are pulse signals — cleared next cycle
// (important for safety — a stuck wd_pet would defeat the watchdog)
always @(posedge clk) begin
    if (rst_n && $past(rst_n) && $past(u_axi.wr_state != 2'd1))
        assert(u_axi.wd_pet == 0);
end

// =========================================================================
// COVER GOALS — all channels must be reachable
// =========================================================================
always @(posedge clk) cover(rst_n && bvalid && bready && bresp == 2'b00);
always @(posedge clk) cover(rst_n && rvalid && rready && rresp == 2'b00);
always @(posedge clk) cover(rst_n && bvalid && bready && bresp == 2'b10);
always @(posedge clk) cover(rst_n && rvalid && rready && rresp == 2'b10);
always @(posedge clk) cover(rst_n && irq_out);
always @(posedge clk) cover(rst_n && irq_out && $past(!irq_out));  // rising edge
always @(posedge clk) cover(rst_n && rvalid && rdata == 32'hAC010002); // CHIP_ID read
always @(posedge clk) cover(rst_n && u_axi.wr_addr_r[19:16] == 4'h5 && bvalid); // CAN write
always @(posedge clk) cover(rst_n && u_axi.wr_addr_r[19:16] == 4'h6 && bvalid); // EC write
always @(posedge clk) cover(rst_n && u_axi.rd_addr_r[19:16] == 4'h3 && rvalid); // Safety read

endmodule
`default_nettype wire
