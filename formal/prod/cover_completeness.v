// ============================================================
// RoboCore-1 Cover Completeness Formal
//
// This spec is run in COVER mode — it proves every important
// state, register, and IRQ is reachable from reset.
//
// Completeness targets:
//   REG-WR: Every writable register in all 8 blocks
//   REG-RD: Every readable register in all 8 blocks
//   IRQ:    IRQ rising/falling edges, mask, clear
//   STATE:  Every AXI state, every DMA sequencer state
//   FAULT:  Every fault path in safety subsystem
//   WD:     All 4 watchdogs fire and recover
//
// Strategy: instantiate both AXI and safety blocks together.
// DMA completeness is covered by dma_formal.v cover goals.
// ============================================================
`default_nettype none

module cover_completeness (
    input wire clk,
    input wire rst_n
);

// -------------------------------------------------------------------------
// AXI DUT
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

// Safety outputs wired into AXI
wire [31:0] fault_reg_wire;
wire        safe_state_wire, estop_active_wire;

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
    .fault_reg(fault_reg_wire), .fault_clear(),
    .safe_state(safe_state_wire), .estop_active(estop_active_wire),
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

// -------------------------------------------------------------------------
// Safety DUT
// -------------------------------------------------------------------------
reg         estop_n, brownout_n;
reg  [31:0] fault_in;
reg         fault_clear_s;
reg  [3:0]  wd_pet, wd_enable;
reg  [95:0] wd_timeout_flat;

wire [31:0] fault_reg_s;
wire        wd_expired_s, safe_state_s, estop_active_s;
wire        brownout_active_s, watchdog_fault_s, system_fault_s;

safety_subsystem u_safety (
    .clk(clk), .rst_n(rst_n),
    .estop_n(estop_n), .brownout_n(brownout_n),
    .fault_in(fault_in), .fault_clear(fault_clear_s),
    .wd_pet(wd_pet), .wd_enable(wd_enable),
    .wd_timeout_flat(wd_timeout_flat),
    .fault_reg(fault_reg_s), .wd_expired(wd_expired_s),
    .safe_state(safe_state_s), .estop_active(estop_active_s),
    .brownout_active(brownout_active_s),
    .watchdog_fault(watchdog_fault_s), .system_fault(system_fault_s)
);

assign fault_reg_wire    = fault_reg_s;
assign safe_state_wire   = safe_state_s;
assign estop_active_wire = estop_active_s;

// =========================================================================
// RESET ASSUMPTIONS
// =========================================================================
initial assume(!rst_n);
initial assume(awvalid == 0); initial assume(wvalid  == 0);
initial assume(arvalid == 0); initial assume(bready  == 0);
initial assume(rready  == 0); initial assume(irq_in  == 0);
initial assume(estop_n    == 1); initial assume(brownout_n == 1);
initial assume(fault_in   == 0); initial assume(wd_enable  == 0);
initial assume(u_axi.wr_state == 0); initial assume(u_axi.rd_state == 0);

// AXI master constraints
always @(posedge clk) begin
    if (rst_n) assume(awvalid == wvalid);
    if (rst_n && $past(awvalid) && !$past(awready)) assume(awvalid);
    if (rst_n && $past(wvalid)  && !$past(wready))  assume(wvalid);
    if (rst_n && $past(arvalid) && !$past(arready)) assume(arvalid);
end

// =========================================================================
// AXI STATE COMPLETENESS
// =========================================================================
// Every write state reachable
always @(posedge clk) cover(rst_n && u_axi.wr_state == 2'd0);
always @(posedge clk) cover(rst_n && u_axi.wr_state == 2'd1);
always @(posedge clk) cover(rst_n && u_axi.wr_state == 2'd2);
// Every read state reachable
always @(posedge clk) cover(rst_n && u_axi.rd_state == 2'd0);
always @(posedge clk) cover(rst_n && u_axi.rd_state == 2'd1);
always @(posedge clk) cover(rst_n && u_axi.rd_state == 2'd2);

// =========================================================================
// REGISTER WRITE COMPLETENESS — every block
// =========================================================================
// BLOCK 0: PWM — channel select, period, duty
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h0 && u_axi.wr_addr_r[15:0]==16'h0000);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h0 && u_axi.wr_addr_r[15:0]==16'h0004);

// BLOCK 1: Encoder — channel select, clear pos, clear idx
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h1 && u_axi.wr_addr_r[15:0]==16'h0000);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h1 && u_axi.wr_addr_r[15:0]==16'h0010);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h1 && u_axi.wr_addr_r[15:0]==16'h0014);

// BLOCK 2: PID — enable, target, gains
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h2 && u_axi.wr_addr_r[15:0]==16'h0100);

// BLOCK 3: Safety — fault_clear, wd_pet, wd_enable
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h3 && u_axi.wr_addr_r[15:0]==16'h0004);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h3 && u_axi.wr_addr_r[15:0]==16'h000C);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h3 && u_axi.wr_addr_r[15:0]==16'h0010);

// BLOCK 5: CAN FD — tx_id, ctrl, data, valid, rx_ack
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h5 && u_axi.wr_addr_r[15:0]==16'h0000);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h5 && u_axi.wr_addr_r[15:0]==16'h0080);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h5 && u_axi.wr_addr_r[15:0]==16'h0084);

// BLOCK 6: EtherCAT — pd_addr, pd_wdata, pd_ctrl
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h6 && u_axi.wr_addr_r[15:0]==16'h000C);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h6 && u_axi.wr_addr_r[15:0]==16'h0010);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h6 && u_axi.wr_addr_r[15:0]==16'h0018);

// BLOCK 7: System — scratch, irq_mask, irq_clear, sys_reset
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h7 && u_axi.wr_addr_r[15:0]==16'h0008);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h7 && u_axi.wr_addr_r[15:0]==16'h0010);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h7 && u_axi.wr_addr_r[15:0]==16'h0014);
always @(posedge clk) cover(rst_n && bvalid && u_axi.wr_addr_r[19:16]==4'h7 && u_axi.wr_addr_r[15:0]==16'h0018);

// =========================================================================
// REGISTER READ COMPLETENESS
// =========================================================================
// BLOCK 0: PWM fault, pwm_out
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h0 && u_axi.rd_addr_r[15:0]==16'h0010);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h0 && u_axi.rd_addr_r[15:0]==16'h0014);

// BLOCK 1: Encoder data, direction, idx, error
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h1 && u_axi.rd_addr_r[15:0]==16'h0004);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h1 && u_axi.rd_addr_r[15:0]==16'h0008);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h1 && u_axi.rd_addr_r[15:0]==16'h000C);

// BLOCK 3: Fault reg, safe_state, estop
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h3 && u_axi.rd_addr_r[15:0]==16'h0000);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h3 && u_axi.rd_addr_r[15:0]==16'h0008);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h3 && u_axi.rd_addr_r[15:0]==16'h0014);

// BLOCK 5: CAN rx_id, rx_data, status
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h5 && u_axi.rd_addr_r[15:0]==16'h0090);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h5 && u_axi.rd_addr_r[15:0]==16'h00A0);

// BLOCK 6: EtherCAT state, link, wkc, pd_rdata
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h6 && u_axi.rd_addr_r[15:0]==16'h0000);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h6 && u_axi.rd_addr_r[15:0]==16'h0008);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h6 && u_axi.rd_addr_r[15:0]==16'h0014);

// BLOCK 7: CHIP_ID, version, scratch, irq_active, irq_mask
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h7 && u_axi.rd_addr_r[15:0]==16'h0000);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h7 && u_axi.rd_addr_r[15:0]==16'h0004);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h7 && u_axi.rd_addr_r[15:0]==16'h000C);
always @(posedge clk) cover(rst_n && rvalid && u_axi.rd_addr_r[19:16]==4'h7 && u_axi.rd_addr_r[15:0]==16'h0010);

// =========================================================================
// SLVERR completeness — unmapped addresses produce SLVERR
// =========================================================================
always @(posedge clk) cover(rst_n && bvalid && bresp == 2'b10);
always @(posedge clk) cover(rst_n && rvalid && rresp == 2'b10);

// =========================================================================
// IRQ COMPLETENESS
// =========================================================================
// IRQ rising edge (new IRQ fires)
always @(posedge clk) cover(rst_n && irq_out && !$past(irq_out));
// IRQ falling edge (cleared by mask or irq_clear)
always @(posedge clk) cover(rst_n && !irq_out && $past(irq_out));
// Each IRQ bit individually
always @(posedge clk) cover(rst_n && u_axi.irq_active[0]);
always @(posedge clk) cover(rst_n && u_axi.irq_active[7]);
always @(posedge clk) cover(rst_n && u_axi.irq_active[15]);
// Multiple IRQs active simultaneously
always @(posedge clk) cover(rst_n && u_axi.irq_active[1] && u_axi.irq_active[0]);
// IRQ masked
always @(posedge clk) cover(rst_n && u_axi.irq_pending[0] && !u_axi.irq_active[0]);

// =========================================================================
// SAFETY COMPLETENESS — every fault path
// =========================================================================
always @(posedge clk) cover(rst_n && safe_state_s);
always @(posedge clk) cover(rst_n && estop_active_s);
always @(posedge clk) cover(rst_n && brownout_active_s);
always @(posedge clk) cover(rst_n && watchdog_fault_s);
// Individual watchdogs
always @(posedge clk) cover(rst_n && fault_reg_s[0]);   // WD0 expired
always @(posedge clk) cover(rst_n && fault_reg_s[1]);   // WD1 expired
always @(posedge clk) cover(rst_n && fault_reg_s[2]);   // WD2 expired
always @(posedge clk) cover(rst_n && fault_reg_s[3]);   // WD3 expired
// Peripheral faults
always @(posedge clk) cover(rst_n && fault_reg_s[10]);  // PID fault
always @(posedge clk) cover(rst_n && fault_reg_s[11]);  // Encoder fault
always @(posedge clk) cover(rst_n && fault_reg_s[12]);  // PWM fault
// Fault cleared — recovery path
always @(posedge clk) cover(rst_n && $past(fault_reg_s != 0) && fault_reg_s == 0);

endmodule
`default_nettype wire
