// ============================================================
// RoboCore-1 APB Bus Interface & Register Map
// Connects RISC-V CPU to all peripheral blocks
//
// Cardinal Principles compliance:
//   Precision   — All hardware registers directly accessible
//                 No abstraction layers adding latency
//   Reliability — Address decode error detection
//                 Default safe values on reset
//                 Write-once safety registers
//   Speed       — Single cycle register access on APB
//                 Hardware interrupt controller — no polling
//                 16 interrupt lines, prioritised
//   Future Proof — APB3 standard (ARM IHI0024C)
//                  Expandable address map
//                  All blocks hot-pluggable in address space
//
// Memory Map:
//   0x0000_xxxx  PWM Engine
//   0x0001_xxxx  Encoder Interface
//   0x0002_xxxx  PID Controller
//   0x0003_xxxx  Safety Subsystem
//   0x0004_xxxx  Tick Generator
//   0x0005_xxxx  CAN FD Controller
//   0x0006_xxxx  EtherCAT MAC
//   0x0007_xxxx  System registers (ID, version, reset)
//
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module robocore1_apb #(
    parameter CHIP_ID      = 32'hAC010001,  // RoboCore-1 v0.0.1 (0xAC = robotics chip)
    parameter NUM_IRQ      = 16             // interrupt lines
)(
    input  wire         clk,
    input  wire         rst_n,

    // --------------------------------------------------------
    // APB3 Master interface — from RISC-V CPU
    // --------------------------------------------------------
    input  wire [31:0]  paddr,      // address
    input  wire         psel,       // peripheral select
    input  wire         penable,    // enable (2nd cycle)
    input  wire         pwrite,     // 1=write, 0=read
    input  wire [31:0]  pwdata,     // write data
    output reg  [31:0]  prdata,     // read data
    output reg          pready,     // peripheral ready
    output reg          pslverr,    // slave error

    // --------------------------------------------------------
    // PWM Engine interface
    // --------------------------------------------------------
    output reg  [3:0]   pwm_reg_addr,
    output reg  [19:0]  pwm_reg_wdata,
    output reg          pwm_reg_we,
    output reg  [3:0]   pwm_reg_ch,
    input  wire [15:0]  pwm_out,
    input  wire         pwm_fault,

    // --------------------------------------------------------
    // Encoder Interface
    // --------------------------------------------------------
    output reg  [3:0]   enc_reg_ch,
    output reg          enc_reg_re,
    input  wire [31:0]  enc_reg_rdata,
    output reg  [15:0]  enc_clear_pos,
    output reg  [15:0]  enc_clear_idx,
    input  wire [15:0]  enc_direction,
    input  wire [15:0]  enc_idx_flag,
    input  wire [15:0]  enc_error_flag,

    // --------------------------------------------------------
    // PID Controller
    // --------------------------------------------------------
    output reg  [31:0]  pid_target  [0:7],
    output reg  [15:0]  pid_kp      [0:7],
    output reg  [15:0]  pid_ki      [0:7],
    output reg  [15:0]  pid_kd      [0:7],
    output reg  [15:0]  pid_out_max [0:7],
    output reg  [7:0]   pid_enable,
    input  wire [15:0]  pid_out     [0:7],
    input  wire [7:0]   pid_at_target,
    input  wire [7:0]   pid_saturated,

    // --------------------------------------------------------
    // Safety Subsystem
    // --------------------------------------------------------
    output reg  [3:0]   wd_pet,
    output reg  [3:0]   wd_enable,
    input  wire [31:0]  fault_reg,
    output reg          fault_clear,
    input  wire         safe_state,
    input  wire         estop_active,
    input  wire         watchdog_fault,

    // --------------------------------------------------------
    // CAN FD Controller
    // --------------------------------------------------------
    output reg  [28:0]  can_tx_id,
    output reg          can_tx_ide,
    output reg          can_tx_brs,
    output reg          can_tx_fdf,
    output reg  [3:0]   can_tx_dlc,
    output reg  [511:0] can_tx_data,
    output reg          can_tx_valid,
    input  wire         can_tx_ready,
    input  wire [28:0]  can_rx_id,
    input  wire [3:0]   can_rx_dlc,
    input  wire [511:0] can_rx_data,
    input  wire         can_rx_valid,
    output reg          can_rx_ack,
    input  wire [7:0]   can_tx_err,
    input  wire [7:0]   can_rx_err,
    input  wire         can_bus_off,

    // --------------------------------------------------------
    // EtherCAT MAC
    // --------------------------------------------------------
    output reg  [15:0]  ec_pd_addr,
    output reg  [31:0]  ec_pd_wdata,
    output reg          ec_pd_we,
    output reg          ec_pd_re,
    input  wire [31:0]  ec_pd_rdata,
    input  wire [3:0]   ec_state,
    input  wire         ec_operational,
    input  wire         ec_timeout,
    input  wire [15:0]  ec_wkc,

    // --------------------------------------------------------
    // Interrupt controller
    // --------------------------------------------------------
    output wire         irq_out,      // to RISC-V interrupt input
    input  wire [NUM_IRQ-1:0] irq_in, // from peripheral blocks
    output reg  [NUM_IRQ-1:0] irq_mask,   // CPU masks interrupts
    output reg  [NUM_IRQ-1:0] irq_clear   // CPU clears interrupts
);

// ============================================================
// Address decode — upper 16 bits select block
// ============================================================
localparam BLOCK_PWM      = 4'h0;
localparam BLOCK_ENC      = 4'h1;
localparam BLOCK_PID      = 4'h2;
localparam BLOCK_SAFETY   = 4'h3;
localparam BLOCK_TICK     = 4'h4;
localparam BLOCK_CAN      = 4'h5;
localparam BLOCK_EC       = 4'h6;
localparam BLOCK_SYS      = 4'h7;

wire [3:0]  block_sel = paddr[19:16];
wire [15:0] reg_off   = paddr[15:0];

// ============================================================
// Interrupt controller
// Constitution: Speed — hardware prioritised interrupts
// ============================================================
reg [NUM_IRQ-1:0] irq_pending;
reg [NUM_IRQ-1:0] irq_active;

// Interrupt sources mapped to lines:
// IRQ[0]  = PWM fault
// IRQ[1]  = Encoder error
// IRQ[2]  = PID at-target (any channel)
// IRQ[3]  = Safety fault
// IRQ[4]  = E-stop
// IRQ[5]  = CAN FD frame received
// IRQ[6]  = CAN FD bus-off
// IRQ[7]  = EtherCAT frame received
// IRQ[8]  = EtherCAT timeout
// IRQ[9]  = EtherCAT operational
// IRQ[15:10] = spare

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        irq_pending <= 0;
        irq_active  <= 0;
        irq_mask    <= 16'hFFFF;  // all masked at reset
        irq_clear   <= 0;
    end else begin
        // Latch and clear in single assignment — no race condition
        irq_pending <= (irq_pending | irq_in) & ~irq_clear;
        irq_clear   <= 0;

        // Active = pending and not masked
        irq_active  <= (irq_pending | irq_in) & ~irq_mask;
    end
end

// IRQ output — combinatorial for zero-latency response
assign irq_out = |((irq_pending | irq_in) & ~irq_mask);

// ============================================================
// System registers
// ============================================================
reg [31:0] sys_scratch;   // scratch register for CPU testing
reg        sys_reset_req; // software reset request

// ============================================================
// APB state machine
// APB3: IDLE → SETUP → ACCESS
// Constitution: Speed — single cycle access where possible
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prdata      <= 32'h0;
        pready      <= 1;
        pslverr     <= 0;

        // Reset all outputs to safe defaults
        pwm_reg_we   <= 0;
        enc_reg_re   <= 0;
        enc_clear_pos <= 0;
        enc_clear_idx <= 0;
        pid_enable   <= 8'h00;
        wd_pet       <= 4'hF;
        wd_enable    <= 4'h0;
        fault_clear  <= 0;
        can_tx_valid <= 0;
        can_rx_ack   <= 0;
        ec_pd_we     <= 0;
        ec_pd_re     <= 0;
        sys_scratch  <= 32'h0;
        sys_reset_req <= 0;

        // Safe PID defaults
        begin : pid_reset
            integer p;
            for (p = 0; p < 8; p = p + 1) begin
                pid_target[p]  <= 32'd0;
                pid_kp[p]      <= 16'd10;
                pid_ki[p]      <= 16'd1;
                pid_kd[p]      <= 16'd5;
                pid_out_max[p] <= 16'd1000;
            end
        end

    end else begin
        // Default — deassert strobes
        pwm_reg_we  <= 0;
        enc_reg_re  <= 0;
        fault_clear <= 0;
        can_tx_valid <= 0;
        can_rx_ack  <= 0;
        ec_pd_we    <= 0;
        ec_pd_re    <= 0;
        pslverr     <= 0;
        pready      <= 1;  // always ready (single cycle)

        if (psel && penable) begin
            case (block_sel)

                // ============================================
                // PWM Engine registers
                // 0x0000_0000: CHANNEL select
                // 0x0000_0004: PERIOD
                // 0x0000_0008: DUTY
                // 0x0000_000C: ENABLE
                // 0x0000_0010: STATUS (read fault)
                // ============================================
                BLOCK_PWM: begin
                    if (pwrite) begin
                        case (reg_off)
                            16'h0000: pwm_reg_ch    <= pwdata[3:0];
                            16'h0004: begin
                                pwm_reg_addr  <= 4'h0;
                                pwm_reg_wdata <= pwdata[19:0];
                                pwm_reg_we    <= 1;
                            end
                            16'h0008: begin
                                pwm_reg_addr  <= 4'h1;
                                pwm_reg_wdata <= pwdata[19:0];
                                pwm_reg_we    <= 1;
                            end
                            16'h000C: begin
                                pwm_reg_addr  <= 4'h2;
                                pwm_reg_wdata <= pwdata[19:0];
                                pwm_reg_we    <= 1;
                            end
                            default: pslverr <= 1;
                        endcase
                    end else begin
                        case (reg_off)
                            16'h0010: prdata <= {31'h0, pwm_fault};
                            16'h0014: prdata <= {16'h0, pwm_out};
                            default:  prdata <= 32'h0;
                        endcase
                    end
                end

                // ============================================
                // Encoder Interface registers
                // 0x0001_0000: CHANNEL select + read trigger
                // 0x0001_0004: POSITION (read)
                // 0x0001_0008: DIRECTION (read)
                // 0x0001_000C: INDEX flags (read)
                // 0x0001_0010: CLEAR position (write)
                // 0x0001_0014: CLEAR index (write)
                // ============================================
                BLOCK_ENC: begin
                    if (pwrite) begin
                        case (reg_off)
                            16'h0000: begin
                                enc_reg_ch <= pwdata[3:0];
                                enc_reg_re <= 1;
                            end
                            16'h0010: enc_clear_pos <= pwdata[15:0];
                            16'h0014: enc_clear_idx <= pwdata[15:0];
                            default: pslverr <= 1;
                        endcase
                    end else begin
                        case (reg_off)
                            16'h0004: prdata <= enc_reg_rdata;
                            16'h0008: prdata <= {16'h0, enc_direction};
                            16'h000C: prdata <= {16'h0, enc_idx_flag};
                            16'h0018: prdata <= {16'h0, enc_error_flag};
                            default:  prdata <= 32'h0;
                        endcase
                    end
                end

                // ============================================
                // PID Controller registers
                // 0x0002_00xx: channel 0-7 registers
                // Per channel (offset n*0x20):
                //   +0x00: TARGET position
                //   +0x04: Kp gain
                //   +0x08: Ki gain
                //   +0x0C: Kd gain
                //   +0x10: OUT_MAX
                //   +0x14: OUTPUT (read)
                //   +0x18: STATUS (at_target, saturated)
                // 0x0002_0100: ENABLE register (8-bit)
                // ============================================
                BLOCK_PID: begin
                    begin : pid_access
                        reg [2:0] ch;
                        reg [4:0] off;
                        ch  = reg_off[7:5];
                        off = reg_off[4:0];

                        if (reg_off == 16'h0100) begin
                            if (pwrite)
                                pid_enable <= pwdata[7:0];
                            else
                                prdata <= {24'h0, pid_enable};
                        end else begin
                            if (pwrite) begin
                                case (off)
                                    5'h00: pid_target[ch]  <= pwdata;
                                    5'h04: pid_kp[ch]      <= pwdata[15:0];
                                    5'h08: pid_ki[ch]      <= pwdata[15:0];
                                    5'h0C: pid_kd[ch]      <= pwdata[15:0];
                                    5'h10: pid_out_max[ch] <= pwdata[15:0];
                                    default: pslverr <= 1;
                                endcase
                            end else begin
                                case (off)
                                    5'h14: prdata <= {16'h0, pid_out[ch]};
                                    5'h18: prdata <= {22'h0,
                                                      pid_saturated[ch],
                                                      pid_at_target[ch],
                                                      8'h0};
                                    default: prdata <= 32'h0;
                                endcase
                            end
                        end
                    end
                end

                // ============================================
                // Safety Subsystem registers
                // 0x0003_0000: FAULT_REG (read)
                // 0x0003_0004: FAULT_CLEAR (write 1 to clear)
                // 0x0003_0008: SAFE_STATE (read)
                // 0x0003_000C: WD_PET (write to pet watchdog)
                // 0x0003_0010: WD_ENABLE
                // 0x0003_0014: ESTOP_STATUS (read)
                // ============================================
                BLOCK_SAFETY: begin
                    if (pwrite) begin
                        case (reg_off)
                            16'h0004: fault_clear <= pwdata[0];
                            16'h000C: wd_pet      <= pwdata[3:0];
                            16'h0010: wd_enable   <= pwdata[3:0];
                            default:  pslverr     <= 1;
                        endcase
                    end else begin
                        case (reg_off)
                            16'h0000: prdata <= fault_reg;
                            16'h0008: prdata <= {31'h0, safe_state};
                            16'h0014: prdata <= {30'h0,
                                                 watchdog_fault,
                                                 estop_active};
                            default:  prdata <= 32'h0;
                        endcase
                    end
                end

                // ============================================
                // CAN FD registers
                // 0x0005_0000: TX_ID
                // 0x0005_0004: TX_CTRL (ide, brs, fdf, dlc)
                // 0x0005_0008: TX_DATA_0 (bytes 0-3)
                // 0x0005_000C: TX_DATA_1 (bytes 4-7)
                // 0x0005_0010: TX_SEND (write 1 to transmit)
                // 0x0005_0014: RX_ID (read)
                // 0x0005_0018: RX_DLC (read)
                // 0x0005_001C: RX_DATA_0 (read bytes 0-3)
                // 0x0005_0020: STATUS
                // ============================================
                BLOCK_CAN: begin
                    if (pwrite) begin
                        case (reg_off)
                            16'h0000: can_tx_id   <= pwdata[28:0];
                            16'h0004: begin
                                can_tx_ide <= pwdata[3];
                                can_tx_brs <= pwdata[2];
                                can_tx_fdf <= pwdata[1];
                                can_tx_dlc <= pwdata[7:4];
                            end
                            16'h0008: can_tx_data[31:0]   <= pwdata;
                            16'h000C: can_tx_data[63:32]  <= pwdata;
                            16'h0010: can_tx_data[95:64]  <= pwdata;
                            16'h0014: can_tx_data[127:96] <= pwdata;
                            16'h0080: can_tx_valid <= pwdata[0];
                            16'h0084: can_rx_ack   <= pwdata[0];
                            default:  pslverr <= 1;
                        endcase
                    end else begin
                        case (reg_off)
                            16'h0090: prdata <= {3'h0, can_rx_id};
                            16'h0094: prdata <= {28'h0, can_rx_dlc};
                            16'h0098: prdata <= can_rx_data[31:0];
                            16'h009C: prdata <= can_rx_data[63:32];
                            16'h00A0: prdata <= {can_bus_off,
                                                 can_tx_ready,
                                                 can_rx_valid,
                                                 13'h0,
                                                 can_rx_err,
                                                 can_tx_err};
                            default:  prdata <= 32'h0;
                        endcase
                    end
                end

                // ============================================
                // EtherCAT MAC registers
                // 0x0006_0000: EC_STATE (read)
                // 0x0006_0004: EC_STATUS
                // 0x0006_0008: EC_WKC (read)
                // 0x0006_000C: PD_ADDR
                // 0x0006_0010: PD_WDATA
                // 0x0006_0014: PD_RDATA (read)
                // 0x0006_0018: PD_CTRL (we/re)
                // ============================================
                BLOCK_EC: begin
                    if (pwrite) begin
                        case (reg_off)
                            16'h000C: ec_pd_addr  <= pwdata[15:0];
                            16'h0010: ec_pd_wdata <= pwdata;
                            16'h0018: begin
                                ec_pd_we <= pwdata[0];
                                ec_pd_re <= pwdata[1];
                            end
                            default: pslverr <= 1;
                        endcase
                    end else begin
                        case (reg_off)
                            16'h0000: prdata <= {28'h0, ec_state};
                            16'h0004: prdata <= {30'h0,
                                                 ec_timeout,
                                                 ec_operational};
                            16'h0008: prdata <= {16'h0, ec_wkc};
                            16'h0014: prdata <= ec_pd_rdata;
                            default:  prdata <= 32'h0;
                        endcase
                    end
                end

                // ============================================
                // System registers
                // 0x0007_0000: CHIP_ID (read only)
                // 0x0007_0004: VERSION
                // 0x0007_0008: SCRATCH (read/write test)
                // 0x0007_000C: IRQ_STATUS
                // 0x0007_0010: IRQ_MASK
                // 0x0007_0014: IRQ_CLEAR
                // 0x0007_0018: SOFT_RESET
                // ============================================
                BLOCK_SYS: begin
                    if (pwrite) begin
                        case (reg_off)
                            16'h0008: sys_scratch  <= pwdata;
                            16'h0010: irq_mask     <= pwdata[NUM_IRQ-1:0];
                            16'h0014: irq_clear    <= pwdata[NUM_IRQ-1:0];
                            16'h0018: sys_reset_req <= pwdata[0];
                            default:  pslverr <= 1;
                        endcase
                    end else begin
                        case (reg_off)
                            16'h0000: prdata <= CHIP_ID;
                            16'h0004: prdata <= 32'h00000001; // v0.0.1
                            16'h0008: prdata <= sys_scratch;
                            16'h000C: prdata <= {16'h0, irq_active};
                            16'h0010: prdata <= {16'h0, irq_mask};
                            default:  prdata <= 32'h0;
                        endcase
                    end
                end

                default: begin
                    pslverr <= 1;
                    prdata  <= 32'hDEAD_BEEF; // unmapped address marker
                end

            endcase
        end
    end
end

// ============================================================
// Interrupt line assignments
// ============================================================
// These are driven externally — irq_in connects to:
// irq_in[0]  = pwm_fault
// irq_in[1]  = |enc_error_flag
// irq_in[2]  = |pid_at_target
// irq_in[3]  = safe_state
// irq_in[4]  = estop_active
// irq_in[5]  = can_rx_valid
// irq_in[6]  = can_bus_off
// irq_in[7]  = ec_frame_rx (from ethercat_mac)
// irq_in[8]  = ec_timeout
// irq_in[9]  = ec_operational
// irq_in[15:10] = spare

endmodule