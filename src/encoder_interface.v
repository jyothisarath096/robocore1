// ============================================================
// RoboCore-1 Encoder Interface — Constitution v1.0 Compliant
//
// Cardinal Principles compliance:
//   Precision   — 4x quadrature decode (counts all 4 edges per cycle)
//                 2x position resolution over previous 2x implementation
//   Reliability — Double-flopped all external inputs, error detection
//   Speed       — Hardware counters, no CPU involvement
//   Future Proof — Parameterized, 32-bit counters, portable Verilog
//
// 4x decode explanation:
//   2x: counts A rising + A falling edges               = 2 counts/cycle
//   4x: counts A rising, A falling, B rising, B falling = 4 counts/cycle
//   Result: 4 billion / 4 = finer position per revolution
//
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module encoder_interface #(
    parameter NUM_CHANNELS  = 16,
    parameter COUNTER_WIDTH = 32     // 32-bit = 4,294,967,296 counts
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // Encoder inputs
    input  wire [NUM_CHANNELS-1:0]       enc_a,
    input  wire [NUM_CHANNELS-1:0]       enc_b,
    input  wire [NUM_CHANNELS-1:0]       enc_idx,

    // CPU read interface
    input  wire [3:0]                    reg_ch,
    input  wire                          reg_re,
    output reg  [COUNTER_WIDTH-1:0]      reg_rdata,

    // Control
    input  wire [NUM_CHANNELS-1:0]       clear_pos,
    input  wire [NUM_CHANNELS-1:0]       clear_idx,

    // Status
    output wire [NUM_CHANNELS-1:0]       direction,
    output wire [NUM_CHANNELS-1:0]       idx_flag,
    output wire [NUM_CHANNELS-1:0]       error_flag
);

// ============================================================
// Triple-register encoder inputs
// Three stages gives better metastability protection
// Constitution: Reliability — no single point of failure
// ============================================================
reg [NUM_CHANNELS-1:0] enc_a_r1, enc_a_r2, enc_a_r3;
reg [NUM_CHANNELS-1:0] enc_b_r1, enc_b_r2, enc_b_r3;
reg [NUM_CHANNELS-1:0] enc_idx_r1, enc_idx_r2;

reg signed [COUNTER_WIDTH-1:0] position [0:NUM_CHANNELS-1];
reg [NUM_CHANNELS-1:0] dir_reg;
reg [NUM_CHANNELS-1:0] idx_reg;
reg [NUM_CHANNELS-1:0] err_reg;

// ============================================================
// Input synchronisation — triple flop for reliability
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enc_a_r1   <= 0; enc_a_r2   <= 0; enc_a_r3   <= 0;
        enc_b_r1   <= 0; enc_b_r2   <= 0; enc_b_r3   <= 0;
        enc_idx_r1 <= 0; enc_idx_r2 <= 0;
    end else begin
        enc_a_r1   <= enc_a;   enc_a_r2 <= enc_a_r1; enc_a_r3 <= enc_a_r2;
        enc_b_r1   <= enc_b;   enc_b_r2 <= enc_b_r1; enc_b_r3 <= enc_b_r2;
        enc_idx_r1 <= enc_idx; enc_idx_r2 <= enc_idx_r1;
    end
end

// ============================================================
// 4x Quadrature decode — Constitution: Precision minimum 4x
//
// State table for 4x decode:
//   A_prev B_prev A_curr B_curr | direction
//   0      0      1      0      | forward  (A rises, B low)
//   1      0      1      1      | forward  (B rises, A high)
//   1      1      0      1      | forward  (A falls, B high)
//   0      1      0      0      | forward  (B falls, A low)
//   0      0      0      1      | backward (B rises, A low)
//   0      1      1      1      | backward (A rises, B high)
//   1      1      1      0      | backward (B falls, A high)
//   1      0      0      0      | backward (A falls, B low)
// ============================================================
genvar ch;
generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : enc_decode

        wire a_curr = enc_a_r2[ch];
        wire b_curr = enc_b_r2[ch];
        wire a_prev = enc_a_r3[ch];
        wire b_prev = enc_b_r3[ch];

        // All four edge detections
        wire a_rise = ( a_curr & ~a_prev);
        wire a_fall = (~a_curr &  a_prev);
        wire b_rise = ( b_curr & ~b_prev);
        wire b_fall = (~b_curr &  b_prev);

        // 4x decode: forward and backward from all four edges
        wire count_up =
            (a_rise & ~b_curr) |   // A rises, B low
            (b_rise &  a_curr) |   // B rises, A high
            (a_fall &  b_curr) |   // A falls, B high
            (b_fall & ~a_curr);    // B falls, A low

        wire count_down =
            (a_rise &  b_curr) |   // A rises, B high
            (b_rise & ~a_curr) |   // B rises, A low
            (a_fall & ~b_curr) |   // A falls, B low
            (b_fall &  a_curr);    // B falls, A high

        // Index pulse — rising edge detection
        wire idx_rise = (enc_idx_r2[ch] & ~enc_idx_r1[ch]);

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                position[ch] <= 0;
                dir_reg[ch]  <= 0;
                idx_reg[ch]  <= 0;
                err_reg[ch]  <= 0;
            end else begin
                if (clear_pos[ch]) begin
                    position[ch] <= 0;
                end else if (count_up & count_down) begin
                    err_reg[ch] <= 1;    // both directions same cycle = error
                end else if (count_up) begin
                    position[ch] <= position[ch] + 1;
                    dir_reg[ch]  <= 1;
                end else if (count_down) begin
                    position[ch] <= position[ch] - 1;
                    dir_reg[ch]  <= 0;
                end

                if (clear_idx[ch])
                    idx_reg[ch] <= 0;
                else if (idx_rise)
                    idx_reg[ch] <= 1;
            end
        end

    end
endgenerate

// ============================================================
// CPU read interface
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        reg_rdata <= 0;
    else if (reg_re)
        reg_rdata <= position[reg_ch];
end

assign direction  = dir_reg;
assign idx_flag   = idx_reg;
assign error_flag = err_reg;

endmodule
