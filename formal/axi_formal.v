module axi_formal_tb (input clk, rst_n);

reg  [31:0] awaddr, wdata, araddr;
reg         awvalid, wvalid, arvalid;
reg  [3:0]  wstrb;
reg         bready, rready;
wire        awready, wready, bvalid, arready, rvalid;
wire [1:0]  bresp, rresp;
wire [31:0] rdata;
wire        irq_out;
reg  [15:0] irq_in;

robocore1_axi u_axi (
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

// Full reset assumptions — constrain ALL state to reset values
initial assume(!rst_n);
initial assume(awvalid == 0);
initial assume(wvalid  == 0);
initial assume(arvalid == 0);
initial assume(irq_in  == 0);
initial assume(u_axi.wr_state == 2'd0);
initial assume(u_axi.rd_state == 2'd0);
initial assume(u_axi.bvalid   == 0);
initial assume(u_axi.rvalid   == 0);
initial assume(u_axi.awready  == 0);
initial assume(u_axi.wready   == 0);
initial assume(u_axi.arready  == 0);
initial assume(bready == 0);
initial assume(rready == 0);

// AXI master protocol
always @(posedge clk) begin
    if (rst_n) assume(awvalid == wvalid);
    if (rst_n && awvalid && !awready) assume(awvalid);
    if (rst_n && wvalid  && !wready)  assume(wvalid);
    if (rst_n && arvalid && !arready) assume(arvalid);
end

// Property 1: State machine in valid states only
always @(posedge clk) begin
    if (rst_n) assert(u_axi.wr_state <= 2'd2);
    if (rst_n) assert(u_axi.rd_state <= 2'd2);
end

// Property 2: BRESP always valid value
always @(posedge clk) begin
    if (rst_n && bvalid)
        assert(bresp == 2'b00 || bresp == 2'b10);
end

// Property 3: RRESP always valid value
always @(posedge clk) begin
    if (rst_n && rvalid)
        assert(rresp == 2'b00 || rresp == 2'b10);
end

// Cover goals
always @(posedge clk) cover(rst_n && bvalid && bready);
always @(posedge clk) cover(rst_n && rvalid && rready);

endmodule
