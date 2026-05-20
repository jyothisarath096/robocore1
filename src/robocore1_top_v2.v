// ============================================================
// RoboCore-1 v2.0 Top Level
// Constitution v1.0 | 100MHz SKY130 | Full RISC-V SoC
//
// Architecture:
//   PicoRV32 (RV32IMC) → AXI4-Lite → All peripherals
//   Boot ROM (1KB) — hardwired instructions
//   Safety subsystem — CPU-independent, always active
//
// Memory map:
//   0x0000_0000 — Boot ROM (1KB)
//   0x0001_0000 — SRAM (via EtherCAT MAC sram_wrapper)
//   0x000X_XXXX — Peripheral registers (robocore1_axi)
//
// Cardinal Principles:
//   Precision   — PicoRV32 deterministic pipeline
//   Reliability — Safety subsystem CPU-independent
//   Speed       — 100MHz AXI4-Lite registered decode
//   Future Proof — RISC-V open ISA, AXI4-Lite standard
// ============================================================

module robocore1_top (
    input  wire         clk,
    input  wire         rst_n,

    // --------------------------------------------------------
    // PWM outputs — 16 channels
    // --------------------------------------------------------
    output wire [15:0]  pwm_out,

    // --------------------------------------------------------
    // Encoder inputs — 16 channels
    // --------------------------------------------------------
    input  wire [15:0]  enc_a,
    input  wire [15:0]  enc_b,
    input  wire [15:0]  enc_idx,

    // --------------------------------------------------------
    // Safety
    // --------------------------------------------------------
    input  wire         estop_n,
    output wire         safe_state,
    output wire         heartbeat,  // = tick_1khz

    // --------------------------------------------------------
    // CAN FD
    // --------------------------------------------------------
    input  wire         can_rx,
    output wire         can_tx,

    // --------------------------------------------------------
    // EtherCAT RMII
    // --------------------------------------------------------
    input  wire [1:0]   rmii_rxd,
    input  wire         rmii_rx_dv,
    input  wire         rmii_rx_er,
    output wire [1:0]   rmii_txd,
    output wire         rmii_tx_en,
    input  wire         rmii_ref_clk,

    // --------------------------------------------------------
    // Debug UART (PicoRV32 trace)
    // --------------------------------------------------------
    output wire         uart_tx
);

// ============================================================
// Tick generator
// ============================================================
wire tick_10mhz, tick_1mhz, tick_100khz, tick_1khz;

tick_generator u_tick (
    .clk        (clk),
    .rst_n      (rst_n),
    .tick_10mhz (tick_10mhz),
    .tick_1mhz  (tick_1mhz),
    .tick_100khz(tick_100khz),
    .tick_1khz  (tick_1khz)
);

// ============================================================
// PWM Engine
// ============================================================
wire [3:0]  pwm_reg_ch;
wire        pwm_reg_we;
wire [19:0] pwm_reg_wdata;
wire        pwm_fault;

pwm_engine u_pwm (
    .clk          (clk),
    .rst_n        (rst_n),
    .reg_addr     (4'h0),
    .reg_ch       (pwm_reg_ch),
    .reg_we       (pwm_reg_we),
    .reg_wdata    (pwm_reg_wdata),
    .pwm_out      (pwm_out),
    .fault        (pwm_fault)
);

// ============================================================
// Encoder Interface
// ============================================================
wire [3:0]  enc_reg_ch;
wire        enc_reg_req;
wire [31:0] enc_reg_rdata;
wire [15:0] enc_direction;
wire [15:0] enc_idx_flag;
wire [15:0] enc_error_flag;
wire [15:0] enc_clear_pos;
wire [15:0] enc_clear_idx;
wire [31:0] enc_position_flat;

encoder_interface u_enc (
    .clk          (clk),
    .rst_n        (rst_n),
    .enc_a        (enc_a),
    .enc_b        (enc_b),
    .enc_idx      (enc_idx),
    .reg_ch       (enc_reg_ch),
    .reg_re       (enc_reg_req),
    .reg_rdata    (enc_reg_rdata),
    .direction    (enc_direction),
    .idx_flag     (enc_idx_flag),
    .error_flag   (enc_error_flag),
    .clear_pos    (enc_clear_pos),
    .clear_idx    (enc_clear_idx)
);

// Encoder position for PID actual — channel 0 position
wire [31:0] enc_reg_rdata_ch0;
assign enc_reg_rdata_ch0 = enc_reg_rdata;

// ============================================================
// PID Controller
// ============================================================
wire [255:0] pid_target_flat;
wire [127:0] pid_kp_flat, pid_ki_flat, pid_kd_flat, pid_out_max_flat;
wire [7:0]   pid_enable;
wire [127:0] pid_out_flat;
wire [7:0]   pid_at_target, pid_saturated;

// Actual positions — wire encoder output to all channels
wire [255:0] pid_actual_flat;
wire [383:0] pid_int_limit_flat;
wire [95:0]  wd_timeout_flat;
wire [23:0]  wd_timeout_val = 24'd10_000_000;

genvar pa;
generate
    for (pa = 0; pa < 8; pa = pa + 1) begin : pid_actual_connect
        assign pid_actual_flat[pa*32 +: 32]  = enc_reg_rdata_ch0;
        assign pid_int_limit_flat[pa*48 +: 48] = 48'd100000;
    end
endgenerate

assign wd_timeout_flat[0*24 +: 24] = wd_timeout_val;
assign wd_timeout_flat[1*24 +: 24] = wd_timeout_val;
assign wd_timeout_flat[2*24 +: 24] = wd_timeout_val;
assign wd_timeout_flat[3*24 +: 24] = wd_timeout_val;

pid_controller u_pid (
    .clk            (clk),
    .rst_n          (rst_n),
    .tick_1mhz      (tick_1mhz),
    .target_flat    (pid_target_flat),
    .actual_flat    (pid_actual_flat),
    .kp_flat        (pid_kp_flat),
    .ki_flat        (pid_ki_flat),
    .kd_flat        (pid_kd_flat),
    .out_max_flat   (pid_out_max_flat),
    .enable         (pid_enable),
    .int_limit_flat (pid_int_limit_flat),
    .pid_out_flat   (pid_out_flat),
    .at_target      (pid_at_target),
    .saturated      (pid_saturated)
);

// ============================================================
// Safety Subsystem — CPU independent
// ============================================================
wire [31:0] fault_reg;
wire        fault_clear;
wire        estop_active;
wire [3:0]  wd_pet, wd_enable;

safety_subsystem u_safety (
    .clk            (clk),
    .rst_n          (rst_n),
    .estop_n        (estop_n),
    .brownout_n     (1'b1),
    .fault_in       ({27'h0, |enc_error_flag, pwm_fault, ~estop_n}),
    .fault_clear    (fault_clear),
    .wd_pet         (wd_pet),
    .wd_enable      (wd_enable),
    .wd_timeout_flat(wd_timeout_flat),
    .fault_reg      (fault_reg),
    .wd_expired     (),
    .safe_state     (safe_state),
    .estop_active   (estop_active),
    .brownout_active(),
    .watchdog_fault (),
    .system_fault   ()
);

// ============================================================
// CAN FD Controller
// ============================================================
wire [28:0] can_tx_id;
wire        can_tx_ide, can_tx_rtr, can_tx_brs, can_tx_fdf;
wire [3:0]  can_tx_dlc;
wire [511:0] can_tx_data;
wire        can_tx_valid, can_rx_ack;
wire [28:0] can_rx_id;
wire        can_rx_ide, can_rx_brs, can_rx_fdf;
wire [3:0]  can_rx_dlc;
wire [511:0] can_rx_data;
wire        can_rx_valid, can_bus_off, can_err_passive;
wire [7:0]  can_tx_err_cnt, can_rx_err_cnt;

can_fd_controller u_can (
    .clk            (clk),
    .rst_n          (rst_n),
    .can_rx         (can_rx),
    .can_tx         (can_tx),
    .tx_id          (can_tx_id),
    .tx_ide         (can_tx_ide),
    .tx_rtr         (can_tx_rtr),
    .tx_brs         (can_tx_brs),
    .tx_fdf         (can_tx_fdf),
    .tx_dlc         (can_tx_dlc),
    .tx_data        (can_tx_data),
    .tx_valid       (can_tx_valid),
    .rx_id          (can_rx_id),
    .rx_ide         (can_rx_ide),
    .rx_brs         (can_rx_brs),
    .rx_fdf         (can_rx_fdf),
    .rx_dlc         (can_rx_dlc),
    .rx_data        (can_rx_data),
    .rx_valid       (can_rx_valid),
    .rx_ack         (can_rx_ack),
    .bus_off        (can_bus_off),
    .err_passive    (can_err_passive),
    .tx_err_cnt     (can_tx_err_cnt),
    .rx_err_cnt     (can_rx_err_cnt)
);

// ============================================================
// EtherCAT MAC
// ============================================================
wire [15:0] ec_pd_addr;
wire [31:0] ec_pd_wdata;
wire        ec_pd_we, ec_pd_re;
wire [31:0] ec_pd_rdata;
wire        ec_pd_valid;
wire [3:0]  ec_state;
wire        ec_link, ec_operational, ec_timeout;
wire [15:0] ec_wkc;
wire [63:0] dc_local_time;
wire        dc_sync0, dc_sync1;

ethercat_mac u_ec (
    .clk            (clk),
    .rst_n          (rst_n),
    .rmii_rxd       (rmii_rxd),
    .rmii_rx_dv     (rmii_rx_dv),
    .rmii_rx_er     (rmii_rx_er),
    .rmii_txd       (rmii_txd),
    .rmii_tx_en     (rmii_tx_en),
    .rmii_ref_clk   (rmii_ref_clk),
    .pd_addr        (ec_pd_addr),
    .pd_wdata       (ec_pd_wdata),
    .pd_we          (ec_pd_we),
    .pd_re          (ec_pd_re),
    .pd_rdata       (ec_pd_rdata),
    .pd_valid       (ec_pd_valid),
    .dc_local_time  (dc_local_time),
    .dc_offset      (64'h0),
    .dc_sync0       (dc_sync0),
    .dc_sync1       (dc_sync1),
    .dc_sync0_period(64'd1_000_000),
    .dc_sync1_period(64'd2_000_000),
    .ec_state       (ec_state),
    .ec_link        (ec_link),
    .ec_frame_rx    (),
    .ec_frame_tx    (),
    .ec_wkc         (ec_wkc),
    .ec_timeout     (ec_timeout),
    .ec_operational (ec_operational),
    .fault          ()
);

// ============================================================
// AXI4-Lite Bus Interface
// ============================================================
wire [31:0] axi_awaddr, axi_wdata, axi_araddr, axi_rdata;
wire        axi_awvalid, axi_awready;
wire        axi_wvalid, axi_wready;
wire [3:0]  axi_wstrb;
wire [1:0]  axi_bresp;
wire        axi_bvalid, axi_bready;
wire        axi_arvalid, axi_arready;
wire [1:0]  axi_rresp;
wire        axi_rvalid, axi_rready;
wire        axi_irq_out;
wire [15:0] irq_in;

// IRQ sources
assign irq_in[0]  = pwm_fault;
assign irq_in[1]  = |enc_error_flag;
assign irq_in[2]  = safe_state;
assign irq_in[3]  = estop_active;
assign irq_in[4]  = can_bus_off;
assign irq_in[5]  = can_rx_valid;
assign irq_in[6]  = ec_timeout;
assign irq_in[7]  = ec_operational;
assign irq_in[15:8] = 8'h0;

robocore1_axi u_axi (
    .aclk           (clk),
    .aresetn        (rst_n),
    .awaddr         (axi_awaddr),   .awvalid(axi_awvalid), .awready(axi_awready),
    .wdata          (axi_wdata),    .wstrb  (axi_wstrb),
    .wvalid         (axi_wvalid),   .wready (axi_wready),
    .bresp          (axi_bresp),    .bvalid (axi_bvalid),  .bready (axi_bready),
    .araddr         (axi_araddr),   .arvalid(axi_arvalid), .arready(axi_arready),
    .rdata          (axi_rdata),    .rresp  (axi_rresp),
    .rvalid         (axi_rvalid),   .rready (axi_rready),
    .irq_in         (irq_in),       .irq_out(axi_irq_out),
    .pwm_reg_ch     (pwm_reg_ch),   .pwm_reg_we(pwm_reg_we),
    .pwm_reg_wdata  (pwm_reg_wdata),.pwm_fault(pwm_fault), .pwm_out(pwm_out),
    .enc_reg_ch     (enc_reg_ch),   .enc_reg_req(enc_reg_req),
    .enc_reg_rdata  (enc_reg_rdata),.enc_direction(enc_direction),
    .enc_idx_flag   (enc_idx_flag), .enc_error_flag(enc_error_flag),
    .enc_clear_pos  (enc_clear_pos),.enc_clear_idx(enc_clear_idx),
    .pid_target_flat(pid_target_flat), .pid_kp_flat(pid_kp_flat),
    .pid_ki_flat    (pid_ki_flat),  .pid_kd_flat(pid_kd_flat),
    .pid_out_max_flat(pid_out_max_flat), .pid_enable(pid_enable),
    .pid_out_flat   (pid_out_flat), .pid_at_target(pid_at_target),
    .pid_saturated  (pid_saturated),
    .fault_reg      (fault_reg),    .fault_clear(fault_clear),
    .safe_state     (safe_state),   .estop_active(estop_active),
    .wd_pet         (wd_pet),       .wd_enable(wd_enable),
    .can_tx_id      (can_tx_id),    .can_tx_ide(can_tx_ide),
    .can_tx_rtr     (can_tx_rtr),   .can_tx_brs(can_tx_brs),
    .can_tx_fdf     (can_tx_fdf),   .can_tx_dlc(can_tx_dlc),
    .can_tx_data    (can_tx_data),  .can_tx_valid(can_tx_valid),
    .can_rx_ack     (can_rx_ack),   .can_rx_id(can_rx_id),
    .can_rx_ide     (can_rx_ide),   .can_rx_brs(can_rx_brs),
    .can_rx_fdf     (can_rx_fdf),   .can_rx_dlc(can_rx_dlc),
    .can_rx_data    (can_rx_data),  .can_rx_valid(can_rx_valid),
    .can_bus_off    (can_bus_off),  .can_err_passive(can_err_passive),
    .can_tx_err_cnt (can_tx_err_cnt),.can_rx_err_cnt(can_rx_err_cnt),
    .ec_pd_addr     (ec_pd_addr),   .ec_pd_wdata(ec_pd_wdata),
    .ec_pd_we       (ec_pd_we),     .ec_pd_re(ec_pd_re),
    .ec_pd_rdata    (ec_pd_rdata),  .ec_pd_valid(ec_pd_valid),
    .ec_state       (ec_state),     .ec_link(ec_link),
    .ec_operational (ec_operational),.ec_wkc(ec_wkc), .ec_timeout(ec_timeout),
    .sys_reset_req  ()
);

// ============================================================
// Boot ROM AXI slave — 256 x 32-bit = 1KB at 0x0000_0000
// PicoRV32 fetches instructions via AXI read channel
// ============================================================
reg [31:0] boot_rom [0:255];
integer ri;
initial begin
    for (ri = 0; ri < 256; ri = ri + 1)
        boot_rom[ri] = 32'h0000_0013; // NOP
    boot_rom[0] = 32'h0000_006F;      // jal x0, 0 (infinite loop)
end

// AXI read response for ROM — intercept reads to 0x0000_xxxx
wire        rom_sel    = (axi_araddr[31:10] == 22'h0);
reg         rom_rvalid_r;
reg  [31:0] rom_rdata_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rom_rvalid_r <= 0;
        rom_rdata_r  <= 0;
    end else begin
        rom_rvalid_r <= 0;
        if (axi_arvalid && rom_sel) begin
            rom_rdata_r  <= boot_rom[axi_araddr[9:2]];
            rom_rvalid_r <= 1;
        end
    end
end

// MUX: ROM or peripheral bus for read data
wire        cpu_rvalid = rom_sel ? rom_rvalid_r : axi_rvalid;
wire [31:0] cpu_rdata  = rom_sel ? rom_rdata_r  : axi_rdata;
wire        cpu_arready= rom_sel ? 1'b1          : axi_arready;
wire        cpu_awready_w = axi_awready;
wire        cpu_wready_w  = axi_wready;
wire        cpu_bvalid_w  = axi_bvalid;

// ============================================================
// PicoRV32 AXI4-Lite CPU
// ============================================================
wire        cpu_trap;
wire [2:0]  cpu_awprot, cpu_arprot;

picorv32_axi #(
    .ENABLE_MUL     (1),
    .ENABLE_DIV     (1),
    .COMPRESSED_ISA (1),
    .ENABLE_IRQ     (1),
    .PROGADDR_RESET (32'h0000_0000),
    .STACKADDR      (32'h0000_0FFC)
) u_cpu (
    .clk            (clk),
    .resetn         (rst_n),
    .trap           (cpu_trap),

    // Instruction fetch — from Boot ROM via AXI
    .mem_axi_awvalid(axi_awvalid),
    .mem_axi_awready(cpu_awready_w),
    .mem_axi_awaddr (axi_awaddr),
    .mem_axi_awprot (cpu_awprot),
    .mem_axi_wvalid (axi_wvalid),
    .mem_axi_wready (cpu_wready_w),
    .mem_axi_wdata  (axi_wdata),
    .mem_axi_wstrb  (axi_wstrb),
    .mem_axi_bvalid (cpu_bvalid_w),
    .mem_axi_bready (axi_bready),
    .mem_axi_arvalid(axi_arvalid),
    .mem_axi_arready(cpu_arready),
    .mem_axi_araddr (axi_araddr),
    .mem_axi_arprot (cpu_arprot),
    .mem_axi_rvalid (cpu_rvalid),
    .mem_axi_rready (axi_rready),
    .mem_axi_rdata  (cpu_rdata),

    // IRQ
    .irq            ({16'h0, irq_in} | {31'h0, axi_irq_out}),
    .eoi            (),

    // Trace
    .trace_valid    (),
    .trace_data     ()
);

// ============================================================
// UART TX — simple bit-bang from CPU trap signal for debug
// ============================================================
assign uart_tx  = ~cpu_trap;
assign heartbeat = tick_1khz;
assign cpu_instr_req  = 1'b0; // CPU uses AXI for all memory
assign cpu_instr_addr = 32'h0;
assign cpu_data_addr  = axi_awaddr;
assign cpu_data_we    = axi_awvalid & axi_wvalid;

endmodule
