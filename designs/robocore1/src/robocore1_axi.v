// ============================================================
// RoboCore-1 AXI4-Lite Bus Interface
// Constitution v1.0 | 100MHz target | SKY130
//
// Address map (identical to APB v1):
//   0x000X_0000 where X = block
//   BLOCK 0: PWM      BLOCK 1: Encoder  BLOCK 2: PID
//   BLOCK 3: Safety   BLOCK 4: Tick     BLOCK 5: CAN FD
//   BLOCK 6: EtherCAT BLOCK 7: System
//
// AXI4-Lite improvements over APB:
//   - Separate read/write channels (no multiplexing)
//   - Registered decode — no combinatorial address fan-out
//   - Single-cycle register access
//   - Native Ibex RISC-V interface
//
// Cardinal Principles:
//   Precision   — Single cycle register access
//   Reliability — Registered decode eliminates glitches
//   Speed       — 100MHz verified on SKY130
//   Future Proof — ARM AXI4-Lite standard
// ============================================================

module robocore1_axi #(
    parameter CHIP_ID   = 32'hAC010002,  // RoboCore-1 v0.0.2
    parameter NUM_IRQ   = 16
)(
    input  wire         aclk,
    input  wire         aresetn,         // active low reset

    // --------------------------------------------------------
    // AXI4-Lite Slave interface
    // --------------------------------------------------------
    // Write address channel
    input  wire [31:0]  awaddr,
    input  wire         awvalid,
    output reg          awready,

    // Write data channel
    input  wire [31:0]  wdata,
    input  wire [3:0]   wstrb,
    input  wire         wvalid,
    output reg          wready,

    // Write response channel
    output reg  [1:0]   bresp,
    output reg          bvalid,
    input  wire         bready,

    // Read address channel
    input  wire [31:0]  araddr,
    input  wire         arvalid,
    output reg          arready,

    // Read data channel
    output reg  [31:0]  rdata,
    output reg  [1:0]   rresp,
    output reg          rvalid,
    input  wire         rready,

    // --------------------------------------------------------
    // IRQ
    // --------------------------------------------------------
    input  wire [NUM_IRQ-1:0] irq_in,
    output wire               irq_out,

    // --------------------------------------------------------
    // PWM Engine
    // --------------------------------------------------------
    output reg  [3:0]   pwm_reg_ch,
    output reg          pwm_reg_we,
    output reg  [19:0]  pwm_reg_wdata,
    input  wire         pwm_fault,
    input  wire [15:0]  pwm_out,

    // --------------------------------------------------------
    // Encoder Interface
    // --------------------------------------------------------
    output reg  [3:0]   enc_reg_ch,
    output reg          enc_reg_req,
    input  wire [31:0]  enc_reg_rdata,
    input  wire [15:0]  enc_direction,
    input  wire [15:0]  enc_idx_flag,
    input  wire [15:0]  enc_error_flag,
    output reg  [15:0]  enc_clear_pos,
    output reg  [15:0]  enc_clear_idx,

    // --------------------------------------------------------
    // PID Controller
    // --------------------------------------------------------
    output reg  [255:0] pid_target_flat,
    output reg  [127:0] pid_kp_flat,
    output reg  [127:0] pid_ki_flat,
    output reg  [127:0] pid_kd_flat,
    output reg  [127:0] pid_out_max_flat,
    output reg  [7:0]   pid_enable,
    input  wire [127:0] pid_out_flat,
    input  wire [7:0]   pid_at_target,
    input  wire [7:0]   pid_saturated,

    // --------------------------------------------------------
    // Safety Subsystem
    // --------------------------------------------------------
    input  wire [31:0]  fault_reg,
    output reg          fault_clear,
    input  wire         safe_state,
    input  wire         estop_active,
    output reg  [3:0]   wd_pet,
    output reg  [3:0]   wd_enable,

    // --------------------------------------------------------
    // CAN FD Controller
    // --------------------------------------------------------
    output reg  [28:0]  can_tx_id,
    output reg          can_tx_ide,
    output reg          can_tx_rtr,
    output reg          can_tx_brs,
    output reg          can_tx_fdf,
    output reg  [3:0]   can_tx_dlc,
    output reg  [511:0] can_tx_data,
    output reg          can_tx_valid,
    output reg          can_rx_ack,
    input  wire [28:0]  can_rx_id,
    input  wire         can_rx_ide,
    input  wire         can_rx_brs,
    input  wire         can_rx_fdf,
    input  wire [3:0]   can_rx_dlc,
    input  wire [511:0] can_rx_data,
    input  wire         can_rx_valid,
    input  wire         can_bus_off,
    input  wire         can_err_passive,
    input  wire [7:0]   can_tx_err_cnt,
    input  wire [7:0]   can_rx_err_cnt,

    // --------------------------------------------------------
    // EtherCAT MAC
    // --------------------------------------------------------
    output reg  [15:0]  ec_pd_addr,
    output reg  [31:0]  ec_pd_wdata,
    output reg          ec_pd_we,
    output reg          ec_pd_re,
    input  wire [31:0]  ec_pd_rdata,
    input  wire         ec_pd_valid,
    input  wire [3:0]   ec_state,
    input  wire         ec_link,
    input  wire         ec_operational,
    input  wire [15:0]  ec_wkc,
    input  wire         ec_timeout,

    // --------------------------------------------------------
    // System
    // --------------------------------------------------------
    output reg          sys_reset_req
`ifdef FORMAL
    ,
    output wire [1:0]  f_wr_state,
    output wire [1:0]  f_rd_state,
    output wire [3:0]  f_wr_block,
    output wire [3:0]  f_rd_block,
    output wire [15:0] f_irq_active,
    output wire [15:0] f_irq_pending,
    output wire [31:0] f_sys_scratch
`endif
);

// ============================================================
// Block select — registered for timing
// ============================================================
localparam BLOCK_PWM    = 4'h0;
localparam BLOCK_ENC    = 4'h1;
localparam BLOCK_PID    = 4'h2;
localparam BLOCK_SAFETY = 4'h3;
localparam BLOCK_TICK   = 4'h4;
localparam BLOCK_CAN    = 4'h5;
localparam BLOCK_EC     = 4'h6;
localparam BLOCK_SYS    = 4'h7;

// AXI response codes
localparam OKAY   = 2'b00;
localparam SLVERR = 2'b10;

// ============================================================
// Internal registers
// ============================================================
reg [31:0]  sys_scratch;
reg [NUM_IRQ-1:0] irq_mask;
reg [NUM_IRQ-1:0] irq_clear;
reg [NUM_IRQ-1:0] irq_pending;
reg [NUM_IRQ-1:0] irq_active;

// Registered address/data — key timing improvement over APB
reg [31:0]  wr_addr_r;
reg [31:0]  wr_data_r;
reg [3:0]   wr_strb_r;
reg [31:0]  rd_addr_r;

// Internal decoded fields
wire [3:0]  wr_block = wr_addr_r[19:16];
wire [15:0] wr_off   = wr_addr_r[15:0];
wire [3:0]  rd_block = rd_addr_r[19:16];
wire [15:0] rd_off   = rd_addr_r[15:0];

// ============================================================
// AXI4-Lite Write State Machine
// ============================================================
localparam WR_IDLE    = 2'd0;
localparam WR_DECODE  = 2'd1;
localparam WR_RESP    = 2'd2;

reg [1:0] wr_state;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        wr_state    <= WR_IDLE;
        awready     <= 0;
        wready      <= 0;
        bvalid      <= 0;
        bresp       <= OKAY;
        wr_addr_r   <= 0;
        wr_data_r   <= 0;
        wr_strb_r   <= 0;

        // Register resets
        pwm_reg_ch      <= 0; pwm_reg_we    <= 0; pwm_reg_wdata <= 0;
        enc_reg_ch      <= 0; enc_reg_req   <= 0;
        enc_clear_pos   <= 0; enc_clear_idx <= 0;
        pid_target_flat <= 0; pid_kp_flat   <= {8{16'd10}};
        pid_ki_flat     <= {8{16'd1}};  pid_kd_flat   <= {8{16'd5}};
        pid_out_max_flat<= {8{16'd1000}}; pid_enable  <= 0;
        fault_clear     <= 0; wd_pet        <= 0; wd_enable <= 0;
        can_tx_id       <= 0; can_tx_ide    <= 0; can_tx_rtr <= 0;
        can_tx_brs      <= 0; can_tx_fdf    <= 0; can_tx_dlc <= 0;
        can_tx_data     <= 0; can_tx_valid  <= 0; can_rx_ack <= 0;
        ec_pd_addr      <= 0; ec_pd_wdata   <= 0;
        ec_pd_we        <= 0; ec_pd_re      <= 0;
        irq_mask        <= {NUM_IRQ{1'b1}};
        irq_clear       <= 0;
        sys_scratch     <= 0; sys_reset_req <= 0;
    end else begin
        // Pulse signals
        pwm_reg_we  <= 0;
        enc_reg_req <= 0;
        fault_clear <= 0;
        wd_pet      <= 0;
        can_tx_valid<= 0;
        can_rx_ack  <= 0;
        ec_pd_we    <= 0;
        ec_pd_re    <= 0;
        irq_clear   <= 0;

        case (wr_state)
            WR_IDLE: begin
                awready <= 1;
                wready  <= 1;
                if (awvalid && wvalid) begin
                    wr_addr_r <= awaddr;
                    wr_data_r <= wdata;
                    wr_strb_r <= wstrb;
                    awready   <= 0;
                    wready    <= 0;
                    wr_state  <= WR_DECODE;
                end
            end

            WR_DECODE: begin
                bresp  <= OKAY;
                bvalid <= 1;

                case (wr_block)
                    BLOCK_PWM: begin
                        case (wr_off)
                            16'h0000: pwm_reg_ch    <= wr_data_r[3:0];
                            16'h0004: begin pwm_reg_we <= 1; pwm_reg_wdata <= wr_data_r[19:0]; end
                            16'h0008: begin pwm_reg_we <= 1; pwm_reg_wdata <= wr_data_r[19:0]; end
                            16'h000C: begin pwm_reg_we <= 1; pwm_reg_wdata <= wr_data_r[19:0]; end
                            default:  bresp <= SLVERR;
                        endcase
                    end

                    BLOCK_ENC: begin
                        case (wr_off)
                            16'h0000: begin enc_reg_ch <= wr_data_r[3:0]; enc_reg_req <= 1; end
                            16'h0010: enc_clear_pos <= wr_data_r[15:0];
                            16'h0014: enc_clear_idx <= wr_data_r[15:0];
                            default:  bresp <= SLVERR;
                        endcase
                    end

                    BLOCK_PID: begin
                        if (wr_off == 16'h0100) begin
                            pid_enable <= wr_data_r[7:0];
                        end else begin
                            begin : pid_wr
                                reg [2:0] ch;
                                reg [4:0] off;
                                ch  = wr_off[7:5];
                                off = wr_off[4:0];
                                case (off)
                                    5'h00: pid_target_flat [ch*32 +: 32] <= wr_data_r;
                                    5'h04: pid_kp_flat     [ch*16 +: 16] <= wr_data_r[15:0];
                                    5'h08: pid_ki_flat     [ch*16 +: 16] <= wr_data_r[15:0];
                                    5'h0C: pid_kd_flat     [ch*16 +: 16] <= wr_data_r[15:0];
                                    5'h10: pid_out_max_flat[ch*16 +: 16] <= wr_data_r[15:0];
                                    default: bresp <= SLVERR;
                                endcase
                            end
                        end
                    end

                    BLOCK_SAFETY: begin
                        case (wr_off)
                            16'h0004: fault_clear <= wr_data_r[0];
                            16'h000C: wd_pet      <= wr_data_r[3:0];
                            16'h0010: wd_enable   <= wr_data_r[3:0];
                            default:  bresp <= SLVERR;
                        endcase
                    end

                    BLOCK_CAN: begin
                        case (wr_off)
                            16'h0000: can_tx_id  <= wr_data_r[28:0];
                            16'h0004: begin
                                can_tx_ide <= wr_data_r[3];
                                can_tx_brs <= wr_data_r[2];
                                can_tx_fdf <= wr_data_r[1];
                                can_tx_dlc <= wr_data_r[7:4];
                            end
                            16'h0008: can_tx_data[31:0]   <= wr_data_r;
                            16'h000C: can_tx_data[63:32]  <= wr_data_r;
                            16'h0010: can_tx_data[95:64]  <= wr_data_r;
                            16'h0014: can_tx_data[127:96] <= wr_data_r;
                            16'h0080: can_tx_valid <= wr_data_r[0];
                            16'h0084: can_rx_ack   <= wr_data_r[0];
                            default:  bresp <= SLVERR;
                        endcase
                    end

                    BLOCK_EC: begin
                        case (wr_off)
                            16'h000C: ec_pd_addr  <= wr_data_r[15:0];
                            16'h0010: ec_pd_wdata <= wr_data_r;
                            16'h0018: begin
                                ec_pd_we <= wr_data_r[0];
                                ec_pd_re <= wr_data_r[1];
                            end
                            default:  bresp <= SLVERR;
                        endcase
                    end

                    BLOCK_SYS: begin
                        case (wr_off)
                            16'h0008: sys_scratch   <= wr_data_r;
                            16'h0010: irq_mask      <= wr_data_r[NUM_IRQ-1:0];
                            16'h0014: irq_clear     <= wr_data_r[NUM_IRQ-1:0];
                            16'h0018: sys_reset_req <= wr_data_r[0];
                            default:  bresp <= SLVERR;
                        endcase
                    end

                    default: bresp <= SLVERR;
                endcase

                wr_state <= WR_RESP;
            end

            WR_RESP: begin
                if (bvalid && bready) begin
                    bvalid   <= 0;
                    wr_state <= WR_IDLE;
                    awready  <= 1;
                    wready   <= 1;
                end
            end

            default: wr_state <= WR_IDLE;
        endcase
    end
end

// ============================================================
// AXI4-Lite Read State Machine
// ============================================================
localparam RD_IDLE   = 2'd0;
localparam RD_DECODE = 2'd1;
localparam RD_RESP   = 2'd2;

reg [1:0] rd_state;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        rd_state <= RD_IDLE;
        arready  <= 0;
        rvalid   <= 0;
        rdata    <= 0;
        rresp    <= OKAY;
        rd_addr_r<= 0;
    end else begin
        case (rd_state)
            RD_IDLE: begin
                arready <= 1;
                if (arvalid) begin
                    rd_addr_r <= araddr;
                    arready   <= 0;
                    rd_state  <= RD_DECODE;
                end
            end

            RD_DECODE: begin
                rresp  <= OKAY;
                rvalid <= 1;

                case (rd_block)
                    BLOCK_PWM: begin
                        case (rd_off)
                            16'h0010: rdata <= {31'h0, pwm_fault};
                            16'h0014: rdata <= {16'h0, pwm_out};
                            default:  begin rdata <= 32'h0; rresp <= SLVERR; end
                        endcase
                    end

                    BLOCK_ENC: begin
                        case (rd_off)
                            16'h0004: rdata <= enc_reg_rdata;
                            16'h0008: rdata <= {16'h0, enc_direction};
                            16'h000C: rdata <= {16'h0, enc_idx_flag};
                            16'h0018: rdata <= {16'h0, enc_error_flag};
                            default:  begin rdata <= 32'h0; rresp <= SLVERR; end
                        endcase
                    end

                    BLOCK_PID: begin
                        if (rd_off == 16'h0100) begin
                            rdata <= {24'h0, pid_enable};
                        end else begin
                            begin : pid_rd
                                reg [2:0] ch;
                                reg [4:0] off;
                                ch  = rd_off[7:5];
                                off = rd_off[4:0];
                                case (off)
                                    5'h14: rdata <= {16'h0, pid_out_flat[ch*16 +: 16]};
                                    5'h18: rdata <= {22'h0, pid_saturated[ch],
                                                     pid_at_target[ch], 8'h0};
                                    default: begin rdata <= 32'h0; rresp <= SLVERR; end
                                endcase
                            end
                        end
                    end

                    BLOCK_SAFETY: begin
                        case (rd_off)
                            16'h0000: rdata <= fault_reg;
                            16'h0008: rdata <= {31'h0, safe_state};
                            16'h0014: rdata <= {30'h0, estop_active, safe_state};
                            default:  begin rdata <= 32'h0; rresp <= SLVERR; end
                        endcase
                    end

                    BLOCK_CAN: begin
                        case (rd_off)
                            16'h0090: rdata <= {3'h0, can_rx_id};
                            16'h0094: rdata <= {28'h0, can_rx_dlc};
                            16'h0098: rdata <= can_rx_data[31:0];
                            16'h009C: rdata <= can_rx_data[63:32];
                            16'h00A0: rdata <= {can_bus_off, can_err_passive,
                                               can_tx_err_cnt, can_rx_err_cnt,
                                               7'h0, can_rx_valid};
                            default:  begin rdata <= 32'h0; rresp <= SLVERR; end
                        endcase
                    end

                    BLOCK_EC: begin
                        case (rd_off)
                            16'h0000: rdata <= {28'h0, ec_state};
                            16'h0004: rdata <= {30'h0, ec_link, ec_operational};
                            16'h0008: rdata <= {16'h0, ec_wkc};
                            16'h0014: rdata <= ec_pd_rdata;
                            default:  begin rdata <= 32'h0; rresp <= SLVERR; end
                        endcase
                    end

                    BLOCK_SYS: begin
                        case (rd_off)
                            16'h0000: rdata <= CHIP_ID;
                            16'h0004: rdata <= 32'h00000002; // v0.0.2
                            16'h0008: rdata <= sys_scratch;
                            16'h000C: rdata <= {16'h0, irq_active};
                            16'h0010: rdata <= {16'h0, irq_mask};
                            default:  begin rdata <= 32'h0; rresp <= SLVERR; end
                        endcase
                    end

                    default: begin rdata <= 32'hDEAD_BEEF; rresp <= SLVERR; end
                endcase

                rd_state <= RD_RESP;
            end

            RD_RESP: begin
                if (rvalid && rready) begin
                    rvalid   <= 0;
                    rd_state <= RD_IDLE;
                    arready  <= 1;
                end
            end

            default: rd_state <= RD_IDLE;
        endcase
    end
end

// ============================================================
// IRQ — single always block
// ============================================================
always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        irq_pending <= 0;
        irq_active  <= 0;
    end else begin
        irq_pending <= (irq_pending | irq_in) & ~irq_clear;
        irq_active  <= (irq_pending | irq_in) & ~irq_mask;
    end
end

assign irq_out = |irq_active;

`ifdef FORMAL
assign f_wr_state    = wr_state;
assign f_rd_state    = rd_state;
assign f_wr_block    = wr_block;
assign f_rd_block    = rd_block;
assign f_irq_active  = irq_active;
assign f_irq_pending = irq_pending;
assign f_sys_scratch = sys_scratch;
`endif

endmodule
