// ============================================================
// RoboCore-1 v2.0 Top Level
// Constitution v2.0 | 92MHz SKY130 | Full RISC-V SoC + DMA
//
// Architecture:
//   PicoRV32 (RV32IMC) ──┐
//                         ├── AXI arbiter ──► robocore1_axi ──► peripherals
//   DMA engine      ──────┘
//   DMA config ◄── CPU AXI (0x000F_0000)
//
// Memory map:
//   0x0000_0000 — Boot ROM (1KB)
//   0x000X_XXXX — Peripheral registers (robocore1_axi)
//   0x000F_0000 — DMA config registers
//
// Cardinal Principles:
//   Precision   — DMA moves data in sync with EtherCAT SYNC0
//   Reliability — Safety subsystem CPU-independent always
//   Speed       — 92MHz, zero-copy DMA data path
//   Future Proof — RISC-V + AXI4-Lite + open standards
// ============================================================

module robocore1_top (
    input  wire         clk,
    input  wire         rst_n,

    // PWM outputs — 16 channels
    output wire [15:0]  pwm_out,

    // Encoder inputs — 16 channels
    input  wire [15:0]  enc_a,
    input  wire [15:0]  enc_b,
    input  wire [15:0]  enc_idx,

    // Safety
    input  wire         estop_n,
    output wire         safe_state,
    output wire         heartbeat,

    // CAN FD
    input  wire         can_rx,
    output wire         can_tx,

    // EtherCAT RMII
    input  wire [1:0]   rmii_rxd,
    input  wire         rmii_rx_dv,
    input  wire         rmii_rx_er,
    output wire [1:0]   rmii_txd,
    output wire         rmii_tx_en,
    input  wire         rmii_ref_clk,

    // Debug UART
    output wire         uart_tx
);

// ============================================================
// Tick generator
// ============================================================
wire tick_10mhz, tick_1mhz, tick_100khz, tick_1khz;
tick_generator u_tick (
    .clk(clk), .rst_n(rst_n),
    .tick_10mhz(tick_10mhz), .tick_1mhz(tick_1mhz),
    .tick_100khz(tick_100khz), .tick_1khz(tick_1khz)
);


// ============================================================
// PWM Engine
// ============================================================
wire [3:0]  pwm_reg_ch;
wire        pwm_reg_we;
wire [19:0] pwm_reg_wdata;
wire        pwm_fault;
pwm_engine u_pwm (
    .clk(clk), .rst_n(rst_n),
    .reg_addr(4'h0), .reg_ch(pwm_reg_ch),
    .reg_we(pwm_reg_we), .reg_wdata(pwm_reg_wdata),
    .pwm_out(pwm_out), .fault(pwm_fault)
);

// ============================================================
// Encoder Interface
// ============================================================
wire [3:0]  enc_reg_ch;
wire        enc_reg_req;
wire [31:0] enc_reg_rdata;
wire [15:0] enc_direction, enc_idx_flag, enc_error_flag;
wire [15:0] enc_clear_pos, enc_clear_idx;
encoder_interface u_enc (
    .clk(clk), .rst_n(rst_n),
    .enc_a(enc_a), .enc_b(enc_b), .enc_idx(enc_idx),
    .reg_ch(enc_reg_ch), .reg_re(enc_reg_req),
    .reg_rdata(enc_reg_rdata), .direction(enc_direction),
    .idx_flag(enc_idx_flag), .error_flag(enc_error_flag),
    .clear_pos(enc_clear_pos), .clear_idx(enc_clear_idx)
);

// ============================================================
// PID Controller
// ============================================================
wire [255:0] pid_target_flat;
wire [127:0] pid_kp_flat, pid_ki_flat, pid_kd_flat, pid_out_max_flat;
wire [7:0]   pid_enable;
wire [127:0] pid_out_flat;
wire [7:0]   pid_at_target, pid_saturated;
wire [255:0] pid_actual_flat;
wire [383:0] pid_int_limit_flat;
wire [95:0]  wd_timeout_flat;
wire [23:0]  wd_timeout_val = 24'd10_000_000;

genvar pa;
generate
    for (pa = 0; pa < 8; pa = pa + 1) begin : pid_actual_connect
        assign pid_actual_flat[pa*32 +: 32]   = enc_reg_rdata;
        assign pid_int_limit_flat[pa*48 +: 48] = 48'd100000;
    end
endgenerate
assign wd_timeout_flat[0*24 +: 24] = wd_timeout_val;
assign wd_timeout_flat[1*24 +: 24] = wd_timeout_val;
assign wd_timeout_flat[2*24 +: 24] = wd_timeout_val;
assign wd_timeout_flat[3*24 +: 24] = wd_timeout_val;

pid_controller u_pid (
    .clk(clk), .rst_n(rst_n), .tick_1mhz(tick_1mhz),
    .target_flat(pid_target_flat), .actual_flat(pid_actual_flat),
    .kp_flat(pid_kp_flat), .ki_flat(pid_ki_flat), .kd_flat(pid_kd_flat),
    .out_max_flat(pid_out_max_flat), .enable(pid_enable),
    .int_limit_flat(pid_int_limit_flat),
    .pid_out_flat(pid_out_flat), .at_target(pid_at_target), .saturated(pid_saturated)
);

// ============================================================
// Safety Subsystem — CPU independent
// ============================================================
wire [31:0] fault_reg;
wire        fault_clear, estop_active;
wire [3:0]  wd_pet, wd_enable;
safety_subsystem u_safety (
    .clk(clk), .rst_n(rst_n),
    .estop_n(estop_n), .brownout_n(1'b1),
    .fault_in({29'h0, |enc_error_flag, pwm_fault, ~estop_n}),
    .fault_clear(fault_clear),
    .wd_pet(wd_pet), .wd_enable(wd_enable),
    .wd_timeout_flat(wd_timeout_flat),
    .fault_reg(fault_reg), .wd_expired(),
    .safe_state(safe_state), .estop_active(estop_active),
    .brownout_active(), .watchdog_fault(), .system_fault()
);


// ============================================================
// Clock Gating — saves ~140mW (~34%)
// Safety/PWM/Encoder/PID/Tick — NEVER gated (real-time)
// CAN FD, EtherCAT, DMA — gated when idle
// Uses SKY130 dlclkp glitch-free ICG
// ============================================================
wire can_gclk, ec_gclk, dma_gclk;
reg  can_clk_en_r, ec_clk_en_r, dma_clk_en_r;

// Clock enable logic moved to end of file (after all wire declarations)

sky130_fd_sc_hd__dlclkp_1 u_cg_can (.CLK(clk), .GATE(can_clk_en_r), .GCLK(can_gclk));
sky130_fd_sc_hd__dlclkp_1 u_cg_ec  (.CLK(clk), .GATE(ec_clk_en_r),  .GCLK(ec_gclk));
sky130_fd_sc_hd__dlclkp_1 u_cg_dma (.CLK(clk), .GATE(dma_clk_en_r), .GCLK(dma_gclk));

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
    .clk(can_gclk), .rst_n(rst_n),
    .can_rx(can_rx), .can_tx(can_tx),
    .tx_id(can_tx_id), .tx_ide(can_tx_ide), .tx_rtr(can_tx_rtr),
    .tx_brs(can_tx_brs), .tx_fdf(can_tx_fdf), .tx_dlc(can_tx_dlc),
    .tx_data(can_tx_data), .tx_valid(can_tx_valid),
    .rx_id(can_rx_id), .rx_ide(can_rx_ide), .rx_brs(can_rx_brs),
    .rx_fdf(can_rx_fdf), .rx_dlc(can_rx_dlc),
    .rx_data(can_rx_data), .rx_valid(can_rx_valid), .rx_ack(can_rx_ack),
    .bus_off(can_bus_off), .err_passive(can_err_passive),
    .tx_err_cnt(can_tx_err_cnt), .rx_err_cnt(can_rx_err_cnt)
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
    .clk(ec_gclk), .rst_n(rst_n),
    .rmii_rxd(rmii_rxd), .rmii_rx_dv(rmii_rx_dv), .rmii_rx_er(rmii_rx_er),
    .rmii_txd(rmii_txd), .rmii_tx_en(rmii_tx_en), .rmii_ref_clk(rmii_ref_clk),
    .pd_addr(ec_pd_addr), .pd_wdata(ec_pd_wdata),
    .pd_we(ec_pd_we), .pd_re(ec_pd_re),
    .pd_rdata(ec_pd_rdata), .pd_valid(ec_pd_valid),
    .dc_local_time(dc_local_time), .dc_offset(64'h0),
    .dc_sync0(dc_sync0), .dc_sync1(dc_sync1),
    .dc_sync0_period(64'd1_000_000), .dc_sync1_period(64'd2_000_000),
    .ec_state(ec_state), .ec_link(ec_link),
    .ec_frame_rx(), .ec_frame_tx(),
    .ec_wkc(ec_wkc), .ec_timeout(ec_timeout),
    .ec_operational(ec_operational), .fault()
);

// ============================================================
// Peripheral AXI bus (robocore1_axi slave)
// ============================================================
wire [31:0] per_awaddr, per_wdata, per_araddr, per_rdata;
wire        per_awvalid, per_awready;
wire        per_wvalid, per_wready;
wire [3:0]  per_wstrb;
wire [1:0]  per_bresp;
wire        per_bvalid, per_bready;
wire        per_arvalid, per_arready;
wire [1:0]  per_rresp;
wire        per_rvalid, per_rready;
wire        per_irq_out;
wire [15:0] irq_in;

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
    .aclk(clk), .aresetn(rst_n),
    .awaddr(per_awaddr),   .awvalid(per_awvalid), .awready(per_awready),
    .wdata(per_wdata),     .wstrb(per_wstrb),
    .wvalid(per_wvalid),   .wready(per_wready),
    .bresp(per_bresp),     .bvalid(per_bvalid),   .bready(per_bready),
    .araddr(per_araddr),   .arvalid(per_arvalid), .arready(per_arready),
    .rdata(per_rdata),     .rresp(per_rresp),
    .rvalid(per_rvalid),   .rready(per_rready),
    .irq_in(irq_in),       .irq_out(per_irq_out),
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
    .sys_reset_req()
);

// ============================================================
// DMA Engine
// Triggers: dc_sync0/1, can_rx_valid, tick_1khz, tick_1mhz
// Config at 0x000F_0000 on CPU AXI bus
// ============================================================
wire [31:0] dma_m_awaddr, dma_m_wdata, dma_m_araddr;
wire        dma_m_awvalid, dma_m_awready;
wire [3:0]  dma_m_wstrb;
wire        dma_m_wvalid, dma_m_wready;
wire [1:0]  dma_m_bresp;
wire        dma_m_bvalid, dma_m_bready;
wire        dma_m_arvalid, dma_m_arready;
wire [31:0] dma_m_rdata;
wire [1:0]  dma_m_rresp;
wire        dma_m_rvalid, dma_m_rready;
wire [7:0]  dma_irq_complete, dma_irq_chain;
wire        dma_irq_error;

// DMA config slave wires (CPU writes descriptors here)
wire [31:0] dma_cfg_awaddr, dma_cfg_wdata, dma_cfg_araddr;
wire        dma_cfg_awvalid, dma_cfg_awready;
wire [3:0]  dma_cfg_wstrb;
wire        dma_cfg_wvalid, dma_cfg_wready;
wire [1:0]  dma_cfg_bresp;
wire        dma_cfg_bvalid, dma_cfg_bready;
wire        dma_cfg_arvalid, dma_cfg_arready;
wire [31:0] dma_cfg_rdata;
wire [1:0]  dma_cfg_rresp;
wire        dma_cfg_rvalid, dma_cfg_rready;

robocore1_dma u_dma (
    .clk(dma_gclk), .rst_n(rst_n),
    // AXI master — to peripheral bus via arbiter
    .m_awaddr(dma_m_awaddr),   .m_awvalid(dma_m_awvalid), .m_awready(dma_m_awready),
    .m_wdata(dma_m_wdata),     .m_wstrb(dma_m_wstrb),
    .m_wvalid(dma_m_wvalid),   .m_wready(dma_m_wready),
    .m_bresp(dma_m_bresp),     .m_bvalid(dma_m_bvalid),   .m_bready(dma_m_bready),
    .m_araddr(dma_m_araddr),   .m_arvalid(dma_m_arvalid), .m_arready(dma_m_arready),
    .m_rdata(dma_m_rdata),     .m_rresp(dma_m_rresp),
    .m_rvalid(dma_m_rvalid),   .m_rready(dma_m_rready),
    // Hardware triggers
    .trig_sync0(dc_sync0),     .trig_sync1(dc_sync1),
    .trig_1khz(tick_1khz),     .trig_1mhz(tick_1mhz),
    .trig_can_rx(can_rx_valid), .trig_ext(1'b0),
    // Timestamp
    .dc_local_time(dc_local_time),
    .fault_in(|fault_reg),
    // Config slave
    .cfg_awaddr(dma_cfg_awaddr),   .cfg_awvalid(dma_cfg_awvalid), .cfg_awready(dma_cfg_awready),
    .cfg_wdata(dma_cfg_wdata),     .cfg_wstrb(dma_cfg_wstrb),
    .cfg_wvalid(dma_cfg_wvalid),   .cfg_wready(dma_cfg_wready),
    .cfg_bresp(dma_cfg_bresp),     .cfg_bvalid(dma_cfg_bvalid),   .cfg_bready(dma_cfg_bready),
    .cfg_araddr(dma_cfg_araddr),   .cfg_arvalid(dma_cfg_arvalid), .cfg_arready(dma_cfg_arready),
    .cfg_rdata(dma_cfg_rdata),     .cfg_rresp(dma_cfg_rresp),
    .cfg_rvalid(dma_cfg_rvalid),   .cfg_rready(dma_cfg_rready),
    // IRQs
    .irq_complete(dma_irq_complete), .irq_chain(dma_irq_chain),
    .irq_error(dma_irq_error)
);

// ============================================================
// AXI4-Lite 2-master arbiter
// Priority: CPU > DMA (CPU gets bus when both request)
// Connects CPU + DMA masters to single peripheral slave
// ============================================================
// CPU AXI wires
wire [31:0] cpu_awaddr, cpu_wdata, cpu_araddr;
wire        cpu_awvalid, cpu_awready;
wire [3:0]  cpu_wstrb;
wire        cpu_wvalid, cpu_wready;
wire [1:0]  cpu_bresp;
wire        cpu_bvalid, cpu_bready;
wire        cpu_arvalid, cpu_arready;
wire [31:0] cpu_rdata;
wire [1:0]  cpu_rresp;
wire        cpu_rvalid, cpu_rready;

// Arbiter state
reg arb_dma;  // 1 = DMA owns bus

// Write address arbitration
assign per_awvalid  = arb_dma ? dma_m_awvalid  : cpu_awvalid;
assign per_awaddr   = arb_dma ? dma_m_awaddr   : cpu_awaddr;
assign cpu_awready  = arb_dma ? 1'b0           : per_awready;
assign dma_m_awready= arb_dma ? per_awready    : 1'b0;

// Write data
assign per_wvalid   = arb_dma ? dma_m_wvalid   : cpu_wvalid;
assign per_wdata    = arb_dma ? dma_m_wdata    : cpu_wdata;
assign per_wstrb    = arb_dma ? dma_m_wstrb    : cpu_wstrb;
assign cpu_wready   = arb_dma ? 1'b0           : per_wready;
assign dma_m_wready = arb_dma ? per_wready     : 1'b0;

// Write response
assign cpu_bvalid   = arb_dma ? 1'b0           : per_bvalid;
assign cpu_bresp    = per_bresp;
assign dma_m_bvalid = arb_dma ? per_bvalid     : 1'b0;
assign dma_m_bresp  = per_bresp;
assign per_bready   = arb_dma ? dma_m_bready   : cpu_bready;

// Read address
assign per_arvalid  = arb_dma ? dma_m_arvalid  : cpu_arvalid;
assign per_araddr   = arb_dma ? dma_m_araddr   : cpu_araddr;
assign cpu_arready  = arb_dma ? 1'b0           : per_arready;
assign dma_m_arready= arb_dma ? per_arready    : 1'b0;

// Read data
assign cpu_rvalid   = arb_dma ? 1'b0           : per_rvalid;
assign cpu_rdata    = per_rdata;
assign cpu_rresp    = per_rresp;
assign dma_m_rvalid = arb_dma ? per_rvalid     : 1'b0;
assign dma_m_rdata  = per_rdata;
assign dma_m_rresp  = per_rresp;
assign per_rready   = arb_dma ? dma_m_rready   : cpu_rready;

// Arbiter: grant DMA only when CPU is idle and DMA requests
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arb_dma <= 0;
    end else begin
        if (!arb_dma) begin
            // CPU has bus — give to DMA only if CPU not requesting
            if (!cpu_awvalid && !cpu_arvalid && (dma_m_awvalid || dma_m_arvalid))
                arb_dma <= 1;
        end else begin
            // DMA has bus — return to CPU when DMA transaction complete
            if (!dma_m_awvalid && !dma_m_arvalid && !dma_m_bready && !dma_m_rready)
                arb_dma <= 0;
        end
    end
end

// ============================================================
// DMA config decode — CPU writes to 0x000F_0000
// Route CPU AXI writes/reads to DMA config slave
// ============================================================
wire dma_cfg_sel_w = (cpu_awaddr[19:16] == 4'hF);
wire dma_cfg_sel_r = (cpu_araddr[19:16] == 4'hF);

assign dma_cfg_awaddr  = cpu_awaddr;
assign dma_cfg_awvalid = cpu_awvalid && dma_cfg_sel_w;
assign dma_cfg_wdata   = cpu_wdata;
assign dma_cfg_wstrb   = cpu_wstrb;
assign dma_cfg_wvalid  = cpu_wvalid && dma_cfg_sel_w;
assign dma_cfg_bready  = cpu_bready && dma_cfg_sel_w;
assign dma_cfg_araddr  = cpu_araddr;
assign dma_cfg_arvalid = cpu_arvalid && dma_cfg_sel_r;
assign dma_cfg_rready  = cpu_rready && dma_cfg_sel_r;

// ============================================================
// Boot ROM — 1KB at 0x0000_0000
// ============================================================
reg [31:0] boot_rom [0:255];
integer ri;
initial begin
    for (ri = 0; ri < 256; ri = ri + 1)
        boot_rom[ri] = 32'h0000_0013; // NOP
    // RoboCore-1 Boot Firmware v1.0
    // Init: stack, chip ID check, safety WD, PWM, PID, DMA, jump to 0x10000
    boot_rom[  0] = 32'h00001137; // lui  sp, 1        (sp=0x1000)
    boot_rom[  1] = 32'h00070537; // lui  a0, 0x70     (SYS base)
    boot_rom[  2] = 32'h00052583; // lw   a1, 0(a0)    (read CHIP_ID)
    boot_rom[  3] = 32'hAC010637; // lui  a2, 0xAC010
    boot_rom[  4] = 32'h00260613; // addi a2, a2, 2    (a2=0xAC010002)
    boot_rom[  5] = 32'h0AC59063; // bne  a1, a2, halt (wrong chip)
    boot_rom[  6] = 32'hB00706B7; // lui  a3, 0xB0070  (BOOTING marker)
    boot_rom[  7] = 32'h00D52423; // sw   a3, 8(a0)    (sys_scratch=BOOTING)
    boot_rom[  8] = 32'h00030537; // lui  a0, 0x30     (SAFETY base)
    boot_rom[  9] = 32'h00F00593; // addi a1, x0, 0xF  (all 4 WDs)
    boot_rom[ 10] = 32'h00B52823; // sw   a1, 0x10(a0) (wd_enable)
    boot_rom[ 11] = 32'h00B52623; // sw   a1, 0x0C(a0) (wd_pet)
    boot_rom[ 12] = 32'h00000537; // lui  a0, 0        (PWM base)
    boot_rom[ 13] = 32'h00000293; // addi t0, x0, 0    (ch=0)
    boot_rom[ 14] = 32'h01000313; // addi t1, x0, 16   (16 channels)
    boot_rom[ 15] = 32'h00552023; // sw   t0, 0(a0)    (select ch)
    boot_rom[ 16] = 32'h7D000393; // addi t2, x0, 0x7D0 (period=2000)
    boot_rom[ 17] = 32'h00752223; // sw   t2, 4(a0)    (set period)
    boot_rom[ 18] = 32'h00052423; // sw   x0, 8(a0)    (duty_h=0)
    boot_rom[ 19] = 32'h00052623; // sw   x0, 12(a0)   (duty_l=0)
    boot_rom[ 20] = 32'h00128293; // addi t0, t0, 1
    boot_rom[ 21] = 32'hFE62C4E3; // blt  t0, t1, -24  (pwm_loop)
    boot_rom[ 22] = 32'h00020537; // lui  a0, 0x20     (PID base)
    boot_rom[ 23] = 32'h10052023; // sw   x0, 0x100(a0) (pid_enable=0)
    boot_rom[ 24] = 32'h000F0537; // lui  a0, 0xF0     (DMA base)
    boot_rom[ 25] = 32'h000605B7; // lui  a1, 0x60     (EC PD base)
    boot_rom[ 26] = 32'h01458593; // addi a1, a1, 0x14 (ec_pd_rdata)
    boot_rom[ 27] = 32'h00B52023; // sw   a1, 0(a0)    (desc src)
    boot_rom[ 28] = 32'h000705B7; // lui  a1, 0x70     (SYS base)
    boot_rom[ 29] = 32'h00858593; // addi a1, a1, 8    (sys_scratch)
    boot_rom[ 30] = 32'h00B52223; // sw   a1, 4(a0)    (desc dst)
    boot_rom[ 31] = 32'h0000C5B7; // lui  a1, 0xC      (0xC000)
    boot_rom[ 32] = 32'h10158593; // addi a1, a1, 0x101 (ctrl=0xC101)
    boot_rom[ 33] = 32'h00B52423; // sw   a1, 8(a0)    (desc ctrl)
    boot_rom[ 34] = 32'h00052623; // sw   x0, 12(a0)   (reserved)
    boot_rom[ 35] = 32'h000F1537; // lui  a0, 0xF1     (DMA ctrl base)
    boot_rom[ 36] = 32'h80050513; // addi a0, a0, -0x800 (0xF0800)
    boot_rom[ 37] = 32'h00100593; // addi a1, x0, 1    (enable=1)
    boot_rom[ 38] = 32'h00B52023; // sw   a1, 0(a0)    (DMA CH0 enable)
    boot_rom[ 39] = 32'h00070537; // lui  a0, 0x70     (SYS base)
    boot_rom[ 40] = 32'h600DB5B7; // lui  a1, 0x600DB  (GOOD_BOOT hi)
    boot_rom[ 41] = 32'h00758593; // addi a1, a1, 7    (0x600DB007)
    boot_rom[ 42] = 32'h00B52423; // sw   a1, 8(a0)    (sys_scratch=GOOD)
    boot_rom[ 43] = 32'h00010537; // lui  a0, 0x10     (user fw base)
    boot_rom[ 44] = 32'h00050067; // jalr x0, 0(a0)    (jump to user fw)
    // halt (chip ID mismatch)
    boot_rom[ 45] = 32'h00070537; // lui  a0, 0x70
    boot_rom[ 46] = 32'hDEAD05B7; // lui  a1, 0xDEAD0  (DEAD marker)
    boot_rom[ 47] = 32'h00058593; // addi a1, a1, 0
    boot_rom[ 48] = 32'h00B52423; // sw   a1, 8(a0)    (sys_scratch=DEAD)
    boot_rom[ 49] = 32'h0000006F; // jal  x0, 0        (dead loop)
end

wire        rom_sel     = (cpu_araddr[31:10] == 22'h0);
reg         rom_rvalid_r;
reg  [31:0] rom_rdata_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rom_rvalid_r <= 0; rom_rdata_r <= 0; end
    else begin
        rom_rvalid_r <= 0;
        if (cpu_arvalid && rom_sel) begin
            rom_rdata_r  <= boot_rom[cpu_araddr[9:2]];
            rom_rvalid_r <= 1;
        end
    end
end

// ============================================================
// CPU read mux: ROM / DMA cfg / peripheral
// ============================================================
wire cpu_rvalid_mux = rom_sel      ? rom_rvalid_r    :
                      dma_cfg_sel_r ? dma_cfg_rvalid  :
                      cpu_rvalid;
wire [31:0] cpu_rdata_mux = rom_sel       ? rom_rdata_r   :
                             dma_cfg_sel_r ? dma_cfg_rdata :
                             cpu_rdata;
wire cpu_arready_mux = rom_sel      ? 1'b1            :
                       dma_cfg_sel_r ? dma_cfg_arready :
                       cpu_arready;

// ============================================================
// PicoRV32 RISC-V CPU
// ============================================================
wire        cpu_trap;
wire [2:0]  cpu_awprot_w, cpu_arprot_w;

picorv32_axi #(
    .ENABLE_MUL(0), .ENABLE_DIV(0), .COMPRESSED_ISA(1),
    .ENABLE_IRQ(1),
    .PROGADDR_RESET(32'h0000_0000),
    .STACKADDR(32'h0000_0FFC)
) u_cpu (
    .clk(clk), .resetn(rst_n), .trap(cpu_trap),
    .mem_axi_awvalid(cpu_awvalid), .mem_axi_awready(cpu_awready),
    .mem_axi_awaddr(cpu_awaddr),   .mem_axi_awprot(cpu_awprot_w),
    .mem_axi_wvalid(cpu_wvalid),   .mem_axi_wready(cpu_wready),
    .mem_axi_wdata(cpu_wdata),     .mem_axi_wstrb(cpu_wstrb),
    .mem_axi_bvalid(cpu_bvalid),   .mem_axi_bready(cpu_bready),
    .mem_axi_arvalid(cpu_arvalid), .mem_axi_arready(cpu_arready_mux),
    .mem_axi_araddr(cpu_araddr),   .mem_axi_arprot(cpu_arprot_w),
    .mem_axi_rvalid(cpu_rvalid_mux), .mem_axi_rready(cpu_rready),
    .mem_axi_rdata(cpu_rdata_mux),
    .irq({16'h0, irq_in} | {24'h0, dma_irq_complete} | {31'h0, per_irq_out}),
    .eoi(), .trace_valid(), .trace_data()
);

assign uart_tx   = ~cpu_trap;
assign heartbeat = tick_1khz;

// ============================================================
// Clock gate enable logic — after all wire declarations
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        can_clk_en_r <= 1; ec_clk_en_r <= 1; dma_clk_en_r <= 1;
    end else begin
        can_clk_en_r <= can_tx_valid | can_rx_valid | can_bus_off | can_err_passive;
        ec_clk_en_r  <= ec_operational | ec_link | (ec_state != 4'h0);
        dma_clk_en_r <= (|dma_irq_complete) | dma_m_awvalid | dma_m_arvalid;
    end
end


endmodule
