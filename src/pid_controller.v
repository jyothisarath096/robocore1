// ============================================================
// RoboCore-1 PID Controller — Time-Multiplexed v2
// Constitution v1.0 | Yosys/OpenLane Compatible
//
// v2 change: single shared multiplier instead of 24 parallel
// ~4x smaller, routes cleanly on SKY130 130nm
//
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module pid_controller #(
    parameter NUM_CHANNELS  = 8,
    parameter POS_WIDTH     = 32,
    parameter GAIN_WIDTH    = 16,
    parameter OUT_WIDTH     = 16,
    parameter ACC_WIDTH     = 48
)(
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  tick_1mhz,

    // Flat buses — Yosys compatible (no unpacked array ports)
    input  wire [POS_WIDTH*NUM_CHANNELS-1:0]     target_flat,
    input  wire [POS_WIDTH*NUM_CHANNELS-1:0]     actual_flat,
    input  wire [GAIN_WIDTH*NUM_CHANNELS-1:0]    kp_flat,
    input  wire [GAIN_WIDTH*NUM_CHANNELS-1:0]    ki_flat,
    input  wire [GAIN_WIDTH*NUM_CHANNELS-1:0]    kd_flat,
    input  wire [OUT_WIDTH*NUM_CHANNELS-1:0]     out_max_flat,
    input  wire [NUM_CHANNELS-1:0]               enable,
    input  wire [ACC_WIDTH*NUM_CHANNELS-1:0]     int_limit_flat,

    output wire [OUT_WIDTH*NUM_CHANNELS-1:0]     pid_out_flat,
    output reg  [NUM_CHANNELS-1:0]               at_target,
    output reg  [NUM_CHANNELS-1:0]               saturated
);

// ============================================================
// Unpack input buses
// ============================================================
wire signed [POS_WIDTH-1:0]  target    [0:NUM_CHANNELS-1];
wire signed [POS_WIDTH-1:0]  actual    [0:NUM_CHANNELS-1];
wire signed [GAIN_WIDTH-1:0] kp        [0:NUM_CHANNELS-1];
wire signed [GAIN_WIDTH-1:0] ki        [0:NUM_CHANNELS-1];
wire signed [GAIN_WIDTH-1:0] kd        [0:NUM_CHANNELS-1];
wire        [OUT_WIDTH-1:0]  out_max   [0:NUM_CHANNELS-1];
wire signed [ACC_WIDTH-1:0]  int_limit [0:NUM_CHANNELS-1];

genvar pu;
generate
    for (pu = 0; pu < NUM_CHANNELS; pu = pu + 1) begin : unpack
        assign target[pu]    = target_flat   [pu*POS_WIDTH  +: POS_WIDTH];
        assign actual[pu]    = actual_flat   [pu*POS_WIDTH  +: POS_WIDTH];
        assign kp[pu]        = kp_flat       [pu*GAIN_WIDTH +: GAIN_WIDTH];
        assign ki[pu]        = ki_flat       [pu*GAIN_WIDTH +: GAIN_WIDTH];
        assign kd[pu]        = kd_flat       [pu*GAIN_WIDTH +: GAIN_WIDTH];
        assign out_max[pu]   = out_max_flat  [pu*OUT_WIDTH  +: OUT_WIDTH];
        assign int_limit[pu] = int_limit_flat[pu*ACC_WIDTH  +: ACC_WIDTH];
    end
endgenerate

// ============================================================
// Per-channel persistent state
// ============================================================
reg signed [ACC_WIDTH-1:0]  integrator  [0:NUM_CHANNELS-1];
reg signed [POS_WIDTH:0]    error_prev  [0:NUM_CHANNELS-1];
reg        [OUT_WIDTH-1:0]  pid_out_reg [0:NUM_CHANNELS-1];

// Pack output
genvar po;
generate
    for (po = 0; po < NUM_CHANNELS; po = po + 1) begin : pack_out
        assign pid_out_flat[po*OUT_WIDTH +: OUT_WIDTH] = pid_out_reg[po];
    end
endgenerate

// ============================================================
// Time-multiplexed sequencer
// One channel processed per 4 clock cycles:
//   Cycle 0: calculate error, P term
//   Cycle 1: I term + anti-windup
//   Cycle 2: D term
//   Cycle 3: sum, clamp, output
// Total: 8 channels × 4 cycles = 32 cycles per full update
// ============================================================
localparam AT_TARGET_THRESHOLD = 10;

reg [2:0]  ch;
reg [1:0]  phase;
reg        updating;

reg signed [POS_WIDTH:0]    cur_error;
reg signed [ACC_WIDTH-1:0]  cur_p;
reg signed [ACC_WIDTH-1:0]  cur_i;
reg signed [ACC_WIDTH-1:0]  cur_d;
reg signed [ACC_WIDTH-1:0]  cur_integ;

integer j;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch        <= 0;
        phase     <= 0;
        updating  <= 0;
        cur_error <= 0;
        cur_p     <= 0;
        cur_i     <= 0;
        cur_d     <= 0;
        cur_integ <= 0;
        at_target <= 0;
        saturated <= 0;
        for (j = 0; j < NUM_CHANNELS; j = j + 1) begin
            integrator [j] <= 0;
            error_prev [j] <= 0;
            pid_out_reg[j] <= 0;
        end
    end else begin

        if (tick_1mhz && !updating) begin
            updating <= 1;
            ch       <= 0;
            phase    <= 0;
        end

        if (updating) begin
            case (phase)

                // Cycle 0 — calculate error, P term
                2'd0: begin
                    if (enable[ch]) begin
                        cur_error <= $signed(target[ch]) - $signed(actual[ch]);
                        // P term = Kp * error (registered multiply)
                        cur_p     <= kp[ch] * ($signed(target[ch]) - $signed(actual[ch]));
                        cur_integ <= integrator[ch];
                    end
                    phase <= 2'd1;
                end

                // Cycle 1 — I term with anti-windup
                2'd1: begin
                    if (enable[ch]) begin
                        // Update integrator
                        if (!saturated[ch]) begin
                            cur_integ <= cur_integ + cur_error;
                        end
                        // Clamp integrator
                        if (cur_integ + cur_error > int_limit[ch])
                            cur_integ <= int_limit[ch];
                        else if (cur_integ + cur_error < -int_limit[ch])
                            cur_integ <= -int_limit[ch];
                        // I term = Ki * integrator
                        cur_i <= ki[ch] * cur_integ;
                    end
                    phase <= 2'd2;
                end

                // Cycle 2 — D term
                2'd2: begin
                    if (enable[ch]) begin
                        // D term = Kd * (error - error_prev)
                        cur_d <= kd[ch] * (cur_error - $signed(error_prev[ch]));
                    end
                    phase <= 2'd3;
                end

                // Cycle 3 — sum, clamp, write output
                2'd3: begin
                    if (enable[ch]) begin
                        // Save state
                        integrator [ch] <= cur_integ;
                        error_prev [ch] <= cur_error;

                        // Sum P + I + D
                        begin : sum_block
                            reg signed [ACC_WIDTH-1:0] pid_sum;
                            pid_sum = cur_p + cur_i + cur_d;

                            // Clamp output
                            if (pid_sum < 0) begin
                                pid_out_reg[ch] <= 0;
                                saturated[ch]   <= 1;
                            end else if (pid_sum > $signed({1'b0, out_max[ch]})) begin
                                pid_out_reg[ch] <= out_max[ch];
                                saturated[ch]   <= 1;
                            end else begin
                                pid_out_reg[ch] <= pid_sum[OUT_WIDTH-1:0];
                                saturated[ch]   <= 0;
                            end

                            // At-target check
                            at_target[ch] <= (cur_error < AT_TARGET_THRESHOLD) &&
                                             (cur_error > -AT_TARGET_THRESHOLD);
                        end
                    end else begin
                        // Disabled — clear state
                        pid_out_reg[ch] <= 0;
                        integrator [ch] <= 0;
                        at_target  [ch] <= 0;
                        saturated  [ch] <= 0;
                    end

                    // Advance to next channel
                    phase <= 2'd0;
                    if (ch == NUM_CHANNELS - 1) begin
                        updating <= 0;
                        ch       <= 0;
                    end else begin
                        ch <= ch + 1;
                    end
                end

                default: phase <= 2'd0;

            endcase
        end
    end
end

endmodule
