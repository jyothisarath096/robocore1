// ============================================================
// RoboCore-1 AXI4-Lite Bus Interface Testbench
// Constitution v1.0 | 17 tests matching APB tb coverage
// ============================================================

`timescale 1ns/1ps

module robocore1_axi_tb;

// Clock and reset
reg         aclk;
reg         aresetn;

// AXI4-Lite write address channel
reg  [31:0] awaddr;
reg         awvalid;
wire        awready;

// AXI4-Lite write data channel
reg  [31:0] wdata;
reg  [3:0]  wstrb;
reg         wvalid;
wire        wready;

// AXI4-Lite write response channel
wire [1:0]  bresp;
wire        bvalid;
reg         bready;

// AXI4-Lite read address channel
reg  [31:0] araddr;
reg         arvalid;
wire        arready;

// Read data channel
wire [31:0] rdata;
wire [1:0]  rresp;
wire        rvalid;
reg         rready;

// IRQ
reg  [15:0] irq_in;
wire        irq_out;

// PWM
wire [3:0]  pwm_reg_ch;
wire        pwm_reg_we;
wire [19:0] pwm_reg_wdata;
reg         pwm_fault;
reg  [15:0] pwm_out;

// Encoder
wire [3:0]  enc_reg_ch;
wire        enc_reg_req;
reg  [31:0] enc_reg_rdata;
reg  [15:0] enc_direction;
reg  [15:0] enc_idx_flag;
reg  [15:0] enc_error_flag;
wire [15:0] enc_clear_pos;
wire [15:0] enc_clear_idx;

// PID
wire [255:0] pid_target_flat;
wire [127:0] pid_kp_flat;
wire [127:0] pid_ki_flat;
wire [127:0] pid_kd_flat;
wire [127:0] pid_out_max_flat;
wire [7:0]   pid_enable;
reg  [127:0] pid_out_flat;
reg  [7:0]   pid_at_target;
reg  [7:0]   pid_saturated;

// Safety
reg  [31:0] fault_reg;
wire        fault_clear;
reg         safe_state;
reg         estop_active;
wire [3:0]  wd_pet;
wire [3:0]  wd_enable;

// CAN FD
wire [28:0] can_tx_id;
wire        can_tx_ide, can_tx_rtr, can_tx_brs, can_tx_fdf;
wire [3:0]  can_tx_dlc;
wire [511:0] can_tx_data;
wire        can_tx_valid;
wire        can_rx_ack;
reg  [28:0] can_rx_id;
reg         can_rx_ide, can_rx_brs, can_rx_fdf;
reg  [3:0]  can_rx_dlc;
reg  [511:0] can_rx_data;
reg         can_rx_valid;
reg         can_bus_off;
reg         can_err_passive;
reg  [7:0]  can_tx_err_cnt;
reg  [7:0]  can_rx_err_cnt;

// EtherCAT
wire [15:0] ec_pd_addr;
wire [31:0] ec_pd_wdata;
wire        ec_pd_we, ec_pd_re;
reg  [31:0] ec_pd_rdata;
reg         ec_pd_valid;
reg  [3:0]  ec_state;
reg         ec_link, ec_operational;
reg  [15:0] ec_wkc;
reg         ec_timeout;

// System
wire        sys_reset_req;

// DUT
robocore1_axi dut (
    .aclk(aclk), .aresetn(aresetn),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
    .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
    .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready),
    .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
    .irq_in(irq_in), .irq_out(irq_out),
    .pwm_reg_ch(pwm_reg_ch), .pwm_reg_we(pwm_reg_we),
    .pwm_reg_wdata(pwm_reg_wdata), .pwm_fault(pwm_fault), .pwm_out(pwm_out),
    .enc_reg_ch(enc_reg_ch), .enc_reg_req(enc_reg_req),
    .enc_reg_rdata(enc_reg_rdata), .enc_direction(enc_direction),
    .enc_idx_flag(enc_idx_flag), .enc_error_flag(enc_error_flag),
    .enc_clear_pos(enc_clear_pos), .enc_clear_idx(enc_clear_idx),
    .pid_target_flat(pid_target_flat), .pid_kp_flat(pid_kp_flat),
    .pid_ki_flat(pid_ki_flat), .pid_kd_flat(pid_kd_flat),
    .pid_out_max_flat(pid_out_max_flat), .pid_enable(pid_enable),
    .pid_out_flat(pid_out_flat), .pid_at_target(pid_at_target),
    .pid_saturated(pid_saturated),
    .fault_reg(fault_reg), .fault_clear(fault_clear),
    .safe_state(safe_state), .estop_active(estop_active),
    .wd_pet(wd_pet), .wd_enable(wd_enable),
    .can_tx_id(can_tx_id), .can_tx_ide(can_tx_ide), .can_tx_rtr(can_tx_rtr),
    .can_tx_brs(can_tx_brs), .can_tx_fdf(can_tx_fdf), .can_tx_dlc(can_tx_dlc),
    .can_tx_data(can_tx_data), .can_tx_valid(can_tx_valid),
    .can_rx_ack(can_rx_ack), .can_rx_id(can_rx_id), .can_rx_ide(can_rx_ide),
    .can_rx_brs(can_rx_brs), .can_rx_fdf(can_rx_fdf), .can_rx_dlc(can_rx_dlc),
    .can_rx_data(can_rx_data), .can_rx_valid(can_rx_valid),
    .can_bus_off(can_bus_off), .can_err_passive(can_err_passive),
    .can_tx_err_cnt(can_tx_err_cnt), .can_rx_err_cnt(can_rx_err_cnt),
    .ec_pd_addr(ec_pd_addr), .ec_pd_wdata(ec_pd_wdata),
    .ec_pd_we(ec_pd_we), .ec_pd_re(ec_pd_re),
    .ec_pd_rdata(ec_pd_rdata), .ec_pd_valid(ec_pd_valid),
    .ec_state(ec_state), .ec_link(ec_link),
    .ec_operational(ec_operational), .ec_wkc(ec_wkc), .ec_timeout(ec_timeout),
    .sys_reset_req(sys_reset_req)
);

// Clock — 10ns period = 100MHz
initial aclk = 0;
always #5 aclk = ~aclk;

// ============================================================
// AXI4-Lite transaction tasks
// ============================================================
task axi_write;
    input [31:0] addr;
    input [31:0] data;
    begin
        @(posedge aclk);
        #1;
        awaddr  = addr;
        awvalid = 1;
        wdata   = data;
        wstrb   = 4'hF;
        wvalid  = 1;
        bready  = 1;
        // Wait for both address and data accepted
        wait(awready && wready);
        @(posedge aclk);
        #1;
        awvalid = 0;
        wvalid  = 0;
        // Wait for response
        wait(bvalid);
        @(posedge aclk);
        #1;
        bready = 0;
    end
endtask

task axi_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
        @(posedge aclk);
        #1;
        araddr  = addr;
        arvalid = 1;
        rready  = 1;
        wait(arready);
        @(posedge aclk);
        #1;
        arvalid = 0;
        wait(rvalid);
        data = rdata;
        @(posedge aclk);
        #1;
        rready = 0;
    end
endtask

// ============================================================
// Test stimulus
// ============================================================
integer ch;
reg [31:0] rd;

initial begin
    // Initialise
    aresetn = 0;
    awvalid = 0; wvalid = 0; bready = 0;
    arvalid = 0; rready = 0;
    awaddr = 0; wdata = 0; wstrb = 0; araddr = 0;
    irq_in = 0; pwm_fault = 0; pwm_out = 16'hAAAA;
    enc_reg_rdata = 32'd12345; enc_direction = 16'hFF00;
    enc_idx_flag = 0; enc_error_flag = 0;
    pid_out_flat = 0;
    for (ch = 0; ch < 8; ch = ch + 1)
        pid_out_flat[ch*16 +: 16] = 16'd500;
    pid_at_target = 8'h0; pid_saturated = 8'h0;
    fault_reg = 32'h0000_0001; safe_state = 0; estop_active = 0;
    can_rx_id = 29'h1234567; can_rx_ide = 0; can_rx_brs = 1;
    can_rx_fdf = 1; can_rx_dlc = 4'hF;
    can_rx_data = 512'h0; can_rx_valid = 0;
    can_bus_off = 0; can_err_passive = 0;
    can_tx_err_cnt = 0; can_rx_err_cnt = 0;
    ec_pd_rdata = 0; ec_pd_valid = 0;
    ec_state = 4'd3; ec_link = 1; ec_operational = 1;
    ec_wkc = 16'd42; ec_timeout = 0;

    repeat(4) @(posedge aclk);
    aresetn = 1;
    repeat(4) @(posedge aclk);

    $display("=== RoboCore-1 AXI4-Lite Interface Test (Constitution v1.0) ===");
    $display("AXI4-Lite | 100MHz | Registered decode | Ibex-compatible");
    $display("");

    // Test 1: Chip ID
    $display("Test 1: Chip ID");
    axi_read(32'h0007_0000, rd);
    if (rd == 32'hAC010002)
        $display("PASS: Chip ID = 0x%08X (RoboCore-1 v0.0.2)", rd);
    else
        $display("FAIL: Chip ID wrong: 0x%08X", rd);

    // Test 2: Scratch register R/W
    $display("Test 2: Scratch register R/W");
    axi_write(32'h0007_0008, 32'hA5A5A5A5);
    axi_read(32'h0007_0008, rd);
    if (rd == 32'hA5A5A5A5)
        $display("PASS: Scratch register R/W (0xA5A5A5A5)");
    else
        $display("FAIL: Scratch wrong: 0x%08X", rd);

    // Test 3: Scratch alternating bits
    axi_write(32'h0007_0008, 32'h5A5A5A5A);
    axi_read(32'h0007_0008, rd);
    if (rd == 32'h5A5A5A5A)
        $display("PASS: Scratch register alternating bits (0x5A5A5A5A)");
    else
        $display("FAIL: Scratch alternating wrong: 0x%08X", rd);

    // Test 4: PWM channel select
    $display("Test 4: PWM channel select");
    axi_write(32'h0000_0000, 32'h0000_0003);
    repeat(2) @(posedge aclk);
    if (pwm_reg_ch == 4'd3)
        $display("PASS: PWM channel 3 selected");
    else
        $display("FAIL: PWM channel wrong: %0d", pwm_reg_ch);

    // Test 5: Encoder position read
    $display("Test 5: Encoder position read");
    axi_read(32'h0001_0004, rd);
    if (rd == 32'd12345)
        $display("PASS: Encoder position read = %0d", rd);
    else
        $display("FAIL: Encoder wrong: %0d", rd);

    // Test 6: Encoder direction
    axi_read(32'h0001_0008, rd);
    if (rd[15:0] == 16'hFF00)
        $display("PASS: Encoder direction register correct");
    else
        $display("FAIL: Encoder direction wrong: 0x%04X", rd[15:0]);

    // Test 7: PID target write/read
    $display("Test 7: PID target write");
    axi_write(32'h0002_0000, 32'd2000);
    repeat(2) @(posedge aclk);
    if (pid_target_flat[31:0] == 32'd2000)
        $display("PASS: PID target[0] = 2000");
    else
        $display("FAIL: PID target wrong: %0d", pid_target_flat[31:0]);

    // Test 8: PID Kp write
    axi_write(32'h0002_0004, 32'd20);
    repeat(2) @(posedge aclk);
    if (pid_kp_flat[15:0] == 16'd20)
        $display("PASS: PID Kp[0] = 20");
    else
        $display("FAIL: PID Kp wrong: %0d", pid_kp_flat[15:0]);

    // Test 9: Fault register
    $display("Test 9: Fault register");
    axi_read(32'h0003_0000, rd);
    if (rd == 32'h0000_0001)
        $display("PASS: Fault register read correct (E-stop bit)");
    else
        $display("FAIL: Fault reg wrong: 0x%08X", rd);

    // Test 10: Safe state
    safe_state = 1;
    axi_read(32'h0003_0008, rd);
    if (rd[0] == 1)
        $display("PASS: Safe state = 1");
    else
        $display("FAIL: Safe state wrong");
    safe_state = 0;

    // Test 11: CAN TX ID
    $display("Test 11: CAN TX");
    axi_write(32'h0005_0000, 32'h0123_4567);
    repeat(2) @(posedge aclk);
    if (can_tx_id == 29'h1234567)
        $display("PASS: CAN TX ID = 0x%07X", can_tx_id);
    else
        $display("FAIL: CAN TX ID wrong: 0x%07X", can_tx_id);

    // Test 12: CAN TX data
    axi_write(32'h0005_0008, 32'hDEAD_BEEF);
    axi_write(32'h0005_000C, 32'hCAFE_BABE);
    repeat(2) @(posedge aclk);
    if (can_tx_data[31:0] == 32'hDEAD_BEEF && can_tx_data[63:32] == 32'hCAFE_BABE)
        $display("PASS: CAN TX data bytes 0-3 correct");
    else
        $display("FAIL: CAN TX data wrong");

    // Test 13: EtherCAT state
    $display("Test 13: EtherCAT");
    axi_read(32'h0006_0000, rd);
    if (rd[3:0] == 4'd3)
        $display("PASS: EtherCAT state = %0d (OP)", rd[3:0]);
    else
        $display("FAIL: EtherCAT state wrong: %0d", rd[3:0]);

    // Test 14: EtherCAT WKC
    axi_read(32'h0006_0008, rd);
    if (rd[15:0] == 16'd42)
        $display("PASS: EtherCAT WKC = %0d", rd[15:0]);
    else
        $display("FAIL: EtherCAT WKC wrong: %0d", rd[15:0]);

    // Test 15: Invalid address returns SLVERR
    $display("Test 15: Invalid address");
    axi_read(32'h00FF_0000, rd);
    if (rd == 32'hDEAD_BEEF)
        $display("PASS: Invalid address returns DEAD_BEEF marker");
    else
        $display("FAIL: Invalid address wrong: 0x%08X", rd);

    // Test 16: IRQ
    $display("Test 16: IRQ");
    axi_write(32'h0007_0010, 32'h0000_0000); // unmask all IRQs
    irq_in[5] = 1;
    repeat(3) @(posedge aclk);
    axi_read(32'h0007_000C, rd);
    if (rd[5] == 1)
        $display("PASS: IRQ[5] (CAN RX) active in status register");
    else
        $display("FAIL: IRQ[5] not active: 0x%08X", rd);

    // Test 17: IRQ output
    repeat(2) @(posedge aclk);
    if (irq_out == 1)
        $display("PASS: IRQ output asserted to CPU");
    else
        $display("FAIL: IRQ output not asserted");

    $display("");
    $display("=== AXI4-Lite Interface Test Complete ===");
    $display("100MHz registered decode — timing improvement over APB v1");
    #100;
    $finish;
end

endmodule
