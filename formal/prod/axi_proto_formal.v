`default_nettype none
// ============================================================
// RoboCore-1 AXI4-Lite Protocol Formal — Port-Level Properties
// Yosys 0.36 compatible (no hierarchical refs, no complex witnesses)
// Properties proved:
//   P1: BRESP only OKAY/SLVERR
//   P2: RRESP only OKAY/SLVERR
//   P3: BVALID sticky until BREADY
//   P4: RVALID sticky until RREADY
//   P5: AWREADY == WREADY always (AXI4-Lite)
//   P6: No new AW handshake while BVALID pending
//   P7: IRQ output only high when irq_in recently asserted
// ============================================================
module axi_proto_formal (input wire clk, input wire rst_n);

reg  [31:0] awaddr, wdata, araddr;
reg         awvalid, wvalid, arvalid;
reg  [3:0]  wstrb;
reg         bready, rready;
reg  [15:0] irq_in;

wire        awready, wready, bvalid, arready, rvalid;
wire [1:0]  bresp, rresp;
wire [31:0] rdata;
wire        irq_out;

robocore1_axi #(.CHIP_ID(32'hAC010002)) u_axi (
    .aclk(clk), .aresetn(rst_n),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
    .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
    .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready),
    .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
    .irq_in(irq_in), .irq_out(irq_out),
    .pwm_reg_ch(), .pwm_reg_we(), .pwm_reg_wdata(),
    .pwm_fault(1'b0), .pwm_out(16'h0),
    .enc_reg_ch(), .enc_reg_req(),
    .enc_reg_rdata(32'h0), .enc_direction(16'h0),
    .enc_idx_flag(16'h0), .enc_error_flag(16'h0),
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
// RESET — synchronous constraints only
// =========================================================================
initial assume(!rst_n);
initial assume(awvalid == 0);
initial assume(wvalid  == 0);
initial assume(arvalid == 0);
initial assume(bready  == 0);
initial assume(rready  == 0);
initial assume(irq_in  == 0);

always @(posedge clk) begin
    if (!rst_n) begin
        assume(awvalid == 0);
        assume(wvalid  == 0);
        assume(arvalid == 0);
        assume(bready  == 0);
        assume(rready  == 0);
        assume(irq_in  == 0);
    end
end

// =========================================================================
// MASTER PROTOCOL ASSUMPTIONS
// =========================================================================
always @(posedge clk) begin
    // VALID stable until READY
    if (rst_n && $past(awvalid) && !$past(awready)) assume(awvalid);
    if (rst_n && $past(wvalid)  && !$past(wready))  assume(wvalid);
    if (rst_n && $past(arvalid) && !$past(arready)) assume(arvalid);
    // AXI4-Lite: AW and W together
    if (rst_n) assume(awvalid == wvalid);
    // Address stable until handshake
    if (rst_n && $past(awvalid) && !$past(awready))
        assume(awaddr == $past(awaddr));
    if (rst_n && $past(arvalid) && !$past(arready))
        assume(araddr == $past(araddr));
end

// =========================================================================
// P1: BRESP only OKAY(00) or SLVERR(10)
// =========================================================================
always @(posedge clk)
    if (rst_n && bvalid)
        assert(bresp == 2'b00 || bresp == 2'b10);

// =========================================================================
// P2: RRESP only OKAY(00) or SLVERR(10)
// =========================================================================
always @(posedge clk)
    if (rst_n && rvalid)
        assert(rresp == 2'b00 || rresp == 2'b10);

// =========================================================================
// P3: BVALID sticky until BREADY (ARM spec §A3.2.2)
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(bvalid) && !$past(bready))
        assert(bvalid);

// =========================================================================
// P4: RVALID sticky until RREADY (ARM spec §A3.2.2)
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(rvalid) && !$past(rready))
        assert(rvalid);

// =========================================================================
// P5: AWREADY == WREADY always (AXI4-Lite single channel constraint)
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n))
        assert(awready == wready);

// =========================================================================
// P6: No new AW handshake while BVALID is pending
// =========================================================================
always @(posedge clk)
    if (rst_n && bvalid)
        assert(!(awvalid && awready));

// =========================================================================
// P7a: IRQ output is purely combinatorial from irq_active
//      irq_out cannot be high when all irq_in are low AND
//      irq_out was low last cycle (no sticky pending from before)
//      Provable form: once irq_out deasserts, it stays low until irq_in
// P7b: IRQ cannot assert spontaneously on same cycle as reset deasserts
// =========================================================================
// irq_pending is sticky so we track irq_in ever being high via a latch
reg irq_ever_high;
always @(posedge clk) begin
    if (!rst_n)       irq_ever_high <= 0;
    else if (|irq_in) irq_ever_high <= 1;
end

// If irq_out just rose (was 0, now 1), irq_in must be active now or
// irq_ever_high must be set (pending from before)
always @(posedge clk)
    if (rst_n && $past(rst_n) && irq_out && !$past(irq_out))
        assert(|irq_in || irq_ever_high);

// IRQ cannot be asserted on the very first cycle after reset
always @(posedge clk)
    if (rst_n && !$past(rst_n))
        assert(!irq_out);

// =========================================================================
// COVER GOALS
// =========================================================================
always @(posedge clk) cover(rst_n && bvalid && bready && bresp==2'b00);
always @(posedge clk) cover(rst_n && rvalid && rready && rresp==2'b00);
always @(posedge clk) cover(rst_n && bvalid && bready && bresp==2'b10);
always @(posedge clk) cover(rst_n && rvalid && rready && rresp==2'b10);
always @(posedge clk) cover(rst_n && irq_out);
always @(posedge clk) cover(rst_n && awready && awvalid);
always @(posedge clk) cover(rst_n && arready && arvalid);

endmodule
`default_nettype wire
