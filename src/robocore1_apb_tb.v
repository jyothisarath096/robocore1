// ============================================================
// RoboCore-1 APB Bus Interface Testbench — Constitution v1.0
//
// Tests:
//   1. Chip ID register read
//   2. Scratch register write/read
//   3. PWM register write
//   4. Encoder register read
//   5. PID register write
//   6. Safety register read
//   7. CAN FD register write
//   8. EtherCAT register read
//   9. Invalid address detection
//  10. Interrupt mask/clear
// ============================================================

`timescale 1ns/1ps

module robocore1_apb_tb;

reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;

// ============================================================
// APB signals
// ============================================================
reg  [31:0] paddr;
reg         psel;
reg         penable;
reg         pwrite;
reg  [31:0] pwdata;
wire [31:0] prdata;
wire        pready;
wire        pslverr;

// ============================================================
// Peripheral mock signals
// ============================================================
wire [3:0]  pwm_reg_addr;
wire [19:0] pwm_reg_wdata;
wire        pwm_reg_we;
wire [3:0]  pwm_reg_ch;
reg  [15:0] pwm_out;
reg         pwm_fault;

wire [3:0]  enc_reg_ch;
wire        enc_reg_re;
reg  [31:0] enc_reg_rdata;
wire [15:0] enc_clear_pos;
wire [15:0] enc_clear_idx;
reg  [15:0] enc_direction;
reg  [15:0] enc_idx_flag;
reg  [15:0] enc_error_flag;

wire [31:0] pid_target  [0:7];
wire [15:0] pid_kp      [0:7];
wire [15:0] pid_ki      [0:7];
wire [15:0] pid_kd      [0:7];
wire [15:0] pid_out_max [0:7];
wire [7:0]  pid_enable;
reg  [15:0] pid_out     [0:7];
reg  [7:0]  pid_at_target;
reg  [7:0]  pid_saturated;

wire [3:0]  wd_pet;
wire [3:0]  wd_enable;
reg  [31:0] fault_reg;
wire        fault_clear;
reg         safe_state;
reg         estop_active;
reg         watchdog_fault;

wire [28:0] can_tx_id;
wire        can_tx_ide;
wire        can_tx_brs;
wire        can_tx_fdf;
wire [3:0]  can_tx_dlc;
wire [511:0]can_tx_data;
wire        can_tx_valid;
reg         can_tx_ready;
reg  [28:0] can_rx_id;
reg  [3:0]  can_rx_dlc;
reg  [511:0]can_rx_data;
reg         can_rx_valid;
wire        can_rx_ack;
reg  [7:0]  can_tx_err;
reg  [7:0]  can_rx_err;
reg         can_bus_off;

wire [15:0] ec_pd_addr;
wire [31:0] ec_pd_wdata;
wire        ec_pd_we;
wire        ec_pd_re;
reg  [31:0] ec_pd_rdata;
reg  [3:0]  ec_state;
reg         ec_operational;
reg         ec_timeout;
reg  [15:0] ec_wkc;

wire        irq_out;
reg  [15:0] irq_in;
wire [15:0] irq_mask;
wire [15:0] irq_clear;

robocore1_apb #(
    .CHIP_ID   (32'hAC010001),
    .NUM_IRQ   (16)
) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .paddr          (paddr),
    .psel           (psel),
    .penable        (penable),
    .pwrite         (pwrite),
    .pwdata         (pwdata),
    .prdata         (prdata),
    .pready         (pready),
    .pslverr        (pslverr),
    .pwm_reg_addr   (pwm_reg_addr),
    .pwm_reg_wdata  (pwm_reg_wdata),
    .pwm_reg_we     (pwm_reg_we),
    .pwm_reg_ch     (pwm_reg_ch),
    .pwm_out        (pwm_out),
    .pwm_fault      (pwm_fault),
    .enc_reg_ch     (enc_reg_ch),
    .enc_reg_re     (enc_reg_re),
    .enc_reg_rdata  (enc_reg_rdata),
    .enc_clear_pos  (enc_clear_pos),
    .enc_clear_idx  (enc_clear_idx),
    .enc_direction  (enc_direction),
    .enc_idx_flag   (enc_idx_flag),
    .enc_error_flag (enc_error_flag),
    .pid_target     (pid_target),
    .pid_kp         (pid_kp),
    .pid_ki         (pid_ki),
    .pid_kd         (pid_kd),
    .pid_out_max    (pid_out_max),
    .pid_enable     (pid_enable),
    .pid_out        (pid_out),
    .pid_at_target  (pid_at_target),
    .pid_saturated  (pid_saturated),
    .wd_pet         (wd_pet),
    .wd_enable      (wd_enable),
    .fault_reg      (fault_reg),
    .fault_clear    (fault_clear),
    .safe_state     (safe_state),
    .estop_active   (estop_active),
    .watchdog_fault (watchdog_fault),
    .can_tx_id      (can_tx_id),
    .can_tx_ide     (can_tx_ide),
    .can_tx_brs     (can_tx_brs),
    .can_tx_fdf     (can_tx_fdf),
    .can_tx_dlc     (can_tx_dlc),
    .can_tx_data    (can_tx_data),
    .can_tx_valid   (can_tx_valid),
    .can_tx_ready   (can_tx_ready),
    .can_rx_id      (can_rx_id),
    .can_rx_dlc     (can_rx_dlc),
    .can_rx_data    (can_rx_data),
    .can_rx_valid   (can_rx_valid),
    .can_rx_ack     (can_rx_ack),
    .can_tx_err     (can_tx_err),
    .can_rx_err     (can_rx_err),
    .can_bus_off    (can_bus_off),
    .ec_pd_addr     (ec_pd_addr),
    .ec_pd_wdata    (ec_pd_wdata),
    .ec_pd_we       (ec_pd_we),
    .ec_pd_re       (ec_pd_re),
    .ec_pd_rdata    (ec_pd_rdata),
    .ec_state       (ec_state),
    .ec_operational (ec_operational),
    .ec_timeout     (ec_timeout),
    .ec_wkc         (ec_wkc),
    .irq_out        (irq_out),
    .irq_in         (irq_in),
    .irq_mask       (irq_mask),
    .irq_clear      (irq_clear)
);

// ============================================================
// APB transaction tasks
// ============================================================
task apb_write;
    input [31:0] addr;
    input [31:0] data;
    begin
        @(posedge clk);
        paddr   = addr;
        pwdata  = data;
        pwrite  = 1;
        psel    = 1;
        penable = 0;
        @(posedge clk);
        penable = 1;
        @(posedge clk);
        psel    = 0;
        penable = 0;
        pwrite  = 0;
    end
endtask

task apb_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
        @(posedge clk);
        paddr   = addr;
        pwrite  = 0;
        psel    = 1;
        penable = 0;
        @(posedge clk);
        penable = 1;
        @(posedge clk);
        data    = prdata;
        psel    = 0;
        penable = 0;
    end
endtask

// ============================================================
// Main test
// ============================================================
reg [31:0] rdata;
integer    ch;

initial begin
    $dumpfile("apb_test.vcd");
    $dumpvars(0, robocore1_apb_tb);

    // Initialise
    rst_n        = 0;
    paddr        = 0;
    psel         = 0;
    penable      = 0;
    pwrite       = 0;
    pwdata       = 0;
    pwm_out      = 16'hAAAA;
    pwm_fault    = 0;
    enc_reg_rdata = 32'd12345;
    enc_direction = 16'hFF00;
    enc_idx_flag  = 16'h00FF;
    enc_error_flag = 0;
    fault_reg    = 32'h0;
    safe_state   = 0;
    estop_active = 0;
    watchdog_fault = 0;
    can_tx_ready = 1;
    can_rx_id    = 29'h1234567;
    can_rx_dlc   = 4'd8;
    can_rx_data  = 512'hDEADBEEF;
    can_rx_valid = 1;
    can_tx_err   = 8'd0;
    can_rx_err   = 8'd0;
    can_bus_off  = 0;
    ec_pd_rdata  = 32'hCAFEBABE;
    ec_state     = 4'd3;   // OP
    ec_operational = 1;
    ec_timeout   = 0;
    ec_wkc       = 16'd42;
    irq_in       = 16'h0;

    for (ch = 0; ch < 8; ch = ch + 1) begin
        pid_out[ch]       = 16'd500;
        pid_at_target[ch] = 0;
        pid_saturated[ch] = 0;
    end
    pid_at_target = 8'h0;
    pid_saturated = 8'h0;

    repeat(20) @(posedge clk);
    rst_n = 1;
    repeat(10) @(posedge clk);

    $display("=== RoboCore-1 APB Bus Interface Test (Constitution v1.0) ===");
    $display("APB3 | Unified Register Map | Hardware Interrupts");

    // --------------------------------------------------------
    // Test 1 — Chip ID
    // --------------------------------------------------------
    $display("");
    $display("Test 1: Chip ID register");
    apb_read(32'h0007_0000, rdata);
    if (rdata == 32'hAC010001)
        $display("PASS: Chip ID = 0xAC010001 (RoboCore-1 v0.0.1)");
    else
        $display("FAIL: Chip ID wrong: 0x%08X", rdata);

    // --------------------------------------------------------
    // Test 2 — Scratch register
    // --------------------------------------------------------
    $display("");
    $display("Test 2: Scratch register write/read");
    apb_write(32'h0007_0008, 32'hA5A5A5A5);
    apb_read (32'h0007_0008, rdata);
    if (rdata == 32'hA5A5A5A5)
        $display("PASS: Scratch register R/W (0xA5A5A5A5)");
    else
        $display("FAIL: Scratch wrong: 0x%08X", rdata);

    apb_write(32'h0007_0008, 32'h5A5A5A5A);
    apb_read (32'h0007_0008, rdata);
    if (rdata == 32'h5A5A5A5A)
        $display("PASS: Scratch register alternating bits (0x5A5A5A5A)");
    else
        $display("FAIL: Scratch wrong: 0x%08X", rdata);

    // --------------------------------------------------------
    // Test 3 — PWM register write
    // --------------------------------------------------------
    $display("");
    $display("Test 3: PWM register write");
    apb_write(32'h0000_0000, 32'h00000003);  // select channel 3
    apb_write(32'h0000_0004, 32'h00001000);  // period = 4096
    apb_write(32'h0000_0008, 32'h00000800);  // duty = 2048 (50%)
    apb_write(32'h0000_000C, 32'h00000001);  // enable
    repeat(5) @(posedge clk);
    if (pwm_reg_ch == 4'd3)
        $display("PASS: PWM channel 3 selected");
    else
        $display("FAIL: PWM channel wrong: %0d", pwm_reg_ch);

    // --------------------------------------------------------
    // Test 4 — Encoder position read
    // --------------------------------------------------------
    $display("");
    $display("Test 4: Encoder position read");
    apb_write(32'h0001_0000, 32'h00000005); // select channel 5
    apb_read (32'h0001_0004, rdata);        // read position
    if (rdata == 32'd12345)
        $display("PASS: Encoder position read = 12345");
    else
        $display("FAIL: Encoder position wrong: %0d", rdata);

    apb_read(32'h0001_0008, rdata);
    if (rdata == 32'h0000FF00)
        $display("PASS: Encoder direction register correct");
    else
        $display("FAIL: Direction wrong: 0x%08X", rdata);

    // --------------------------------------------------------
    // Test 5 — PID gains write
    // --------------------------------------------------------
    $display("");
    $display("Test 5: PID gains write (channel 0)");
    apb_write(32'h0002_0000, 32'd2000);   // target = 2000
    apb_write(32'h0002_0004, 32'd20);     // Kp = 20
    apb_write(32'h0002_0008, 32'd2);      // Ki = 2
    apb_write(32'h0002_000C, 32'd10);     // Kd = 10
    repeat(5) @(posedge clk);
    if (pid_target[0] == 32'd2000)
        $display("PASS: PID target[0] = 2000");
    else
        $display("FAIL: PID target wrong: %0d", pid_target[0]);
    if (pid_kp[0] == 16'd20)
        $display("PASS: PID Kp[0] = 20");
    else
        $display("FAIL: PID Kp wrong: %0d", pid_kp[0]);

    // --------------------------------------------------------
    // Test 6 — Safety register read
    // --------------------------------------------------------
    $display("");
    $display("Test 6: Safety register read");
    fault_reg  = 32'h00000100;  // bit 8 = E-stop
    safe_state = 1;
    apb_read(32'h0003_0000, rdata);
    if (rdata == 32'h00000100)
        $display("PASS: Fault register read correct (E-stop bit)");
    else
        $display("FAIL: Fault register wrong: 0x%08X", rdata);

    apb_read(32'h0003_0008, rdata);
    if (rdata == 32'h00000001)
        $display("PASS: Safe state register = 1");
    else
        $display("FAIL: Safe state wrong: 0x%08X", rdata);

    // --------------------------------------------------------
    // Test 7 — CAN FD TX register write
    // --------------------------------------------------------
    $display("");
    $display("Test 7: CAN FD TX register write");
    apb_write(32'h0005_0000, 32'h01234567); // TX ID
    apb_write(32'h0005_0004, 32'h0000008F); // ide=1,brs=0,fdf=0,dlc=8
    apb_write(32'h0005_0008, 32'hDEADBEEF); // data bytes 0-3
    apb_write(32'h0005_000C, 32'hCAFEBABE); // data bytes 4-7
    repeat(5) @(posedge clk);
    if (can_tx_id == 29'h1234567)
        $display("PASS: CAN TX ID = 0x1234567");
    else
        $display("FAIL: CAN TX ID wrong: 0x%07X", can_tx_id);
    if (can_tx_data[31:0] == 32'hDEADBEEF)
        $display("PASS: CAN TX data bytes 0-3 correct");
    else
        $display("FAIL: CAN TX data wrong: 0x%08X", can_tx_data[31:0]);

    // --------------------------------------------------------
    // Test 8 — EtherCAT register read
    // --------------------------------------------------------
    $display("");
    $display("Test 8: EtherCAT register read");
    apb_read(32'h0006_0000, rdata);
    if (rdata == 32'd3)
        $display("PASS: EtherCAT state = 3 (OP)");
    else
        $display("FAIL: EtherCAT state wrong: %0d", rdata);

    apb_read(32'h0006_0008, rdata);
    if (rdata == 32'd42)
        $display("PASS: EtherCAT WKC = 42");
    else
        $display("FAIL: EtherCAT WKC wrong: %0d", rdata);

    // --------------------------------------------------------
    // Test 9 — Invalid address
    // --------------------------------------------------------
    $display("");
    $display("Test 9: Invalid address detection");
    apb_read(32'h000F_0000, rdata);
    repeat(3) @(posedge clk);
    if (pslverr || rdata == 32'hDEAD_BEEF)
        $display("PASS: Invalid address returns error/marker");
    else
        $display("FAIL: Invalid address not detected");

    // --------------------------------------------------------
    // Test 10 — Interrupt mask and status
    // --------------------------------------------------------
    $display("");
    $display("Test 10: Interrupt system");
    // Unmask IRQ[5] (CAN RX)
    apb_write(32'h0007_0010, 32'h0000FFdf); // unmask bit 5
    irq_in = 16'h0020;                       // assert CAN RX IRQ
    repeat(5) @(posedge clk);

    apb_read(32'h0007_000C, rdata);
    if (rdata[5])
        $display("PASS: IRQ[5] (CAN RX) active in status register");
    else
        $display("FAIL: IRQ[5] not showing in status");

    if (irq_out)
        $display("PASS: IRQ output asserted to CPU");
    else
        $display("FAIL: IRQ output not asserted");

    $display("");
    $display("=== APB Register Map Summary ===");
    $display("0x0000_xxxx  PWM Engine      (20-bit, 16 channels)");
    $display("0x0001_xxxx  Encoder         (32-bit position, 16 channels)");
    $display("0x0002_xxxx  PID Controller  (8 channels, gains + status)");
    $display("0x0003_xxxx  Safety          (faults, watchdog, E-stop)");
    $display("0x0004_xxxx  Tick Generator  (status)");
    $display("0x0005_xxxx  CAN FD          (TX/RX, status)");
    $display("0x0006_xxxx  EtherCAT MAC    (state, PD memory, WKC)");
    $display("0x0007_xxxx  System          (ID, version, IRQ, scratch)");

    $display("");
    $display("=== Simulation Complete ===");
    $finish;
end

initial begin
    #5_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule