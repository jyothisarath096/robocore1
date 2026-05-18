// ============================================================
// RoboCore-1 Encoder Interface
// 16-channel quadrature encoder position tracker
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module encoder_interface #(
    parameter NUM_CHANNELS  = 16,    // one per motor axis
    parameter COUNTER_WIDTH = 32     // 32-bit position = 4B counts
)(
    // Clock and reset
    input  wire                          clk,
    input  wire                          rst_n,

    // Encoder inputs — connect directly to encoder ICs
    // Each channel has two quadrature signals A and B
    input  wire [NUM_CHANNELS-1:0]       enc_a,
    input  wire [NUM_CHANNELS-1:0]       enc_b,

    // Index pulse — one per revolution, used for homing
    input  wire [NUM_CHANNELS-1:0]       enc_idx,

    // CPU read interface
    input  wire [3:0]                    reg_ch,     // which channel to read
    input  wire                          reg_re,     // read enable
    output reg  [COUNTER_WIDTH-1:0]      reg_rdata,  // position data out

    // Control interface
    input  wire [NUM_CHANNELS-1:0]       clear_pos,  // reset position to zero
    input  wire [NUM_CHANNELS-1:0]       clear_idx,  // clear index flag

    // Status outputs
    output wire [NUM_CHANNELS-1:0]       direction,  // 1=forward, 0=backward
    output wire [NUM_CHANNELS-1:0]       idx_flag,   // index pulse seen
    output wire [NUM_CHANNELS-1:0]       error_flag  // signal integrity error
);

// ============================================================
// Internal signals
// ============================================================

// Double-register encoder inputs to prevent metastability
// Critical for signals coming from outside the chip
reg [NUM_CHANNELS-1:0] enc_a_r1, enc_a_r2, enc_a_r3;
reg [NUM_CHANNELS-1:0] enc_b_r1, enc_b_r2, enc_b_r3;
reg [NUM_CHANNELS-1:0] enc_idx_r1, enc_idx_r2;

// Position counters — one per channel
reg signed [COUNTER_WIDTH-1:0] position [0:NUM_CHANNELS-1];

// Direction registers
reg [NUM_CHANNELS-1:0] dir_reg;

// Index flag registers
reg [NUM_CHANNELS-1:0] idx_reg;

// Error flag registers
reg [NUM_CHANNELS-1:0] err_reg;

// ============================================================
// Input synchronisation — double flop all external signals
// This is mandatory for any signal crossing clock domains
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enc_a_r1   <= 0; enc_a_r2   <= 0; enc_a_r3   <= 0;
        enc_b_r1   <= 0; enc_b_r2   <= 0; enc_b_r3   <= 0;
        enc_idx_r1 <= 0; enc_idx_r2 <= 0;
    end else begin
        enc_a_r1   <= enc_a;   enc_a_r2   <= enc_a_r1;   enc_a_r3 <= enc_a_r2;
        enc_b_r1   <= enc_b;   enc_b_r2   <= enc_b_r1;
        enc_idx_r1 <= enc_idx; enc_idx_r2 <= enc_idx_r1;
    end
end

// ============================================================
// Quadrature decode — one instance per channel
// State machine based on Gray code transitions
// ============================================================
genvar ch;
generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : enc_decode

        // Previous A and B values for edge detection
        wire a_curr = enc_a_r2[ch];
        wire b_curr = enc_b_r2[ch];
        wire a_prev = enc_a_r3[ch];

        // Detect A rising and falling edges
        wire a_rise = ( a_curr & ~a_prev);
        wire a_fall = (~a_curr &  a_prev);

        // On A rising edge: B=0 means forward, B=1 means backward
        // On A falling edge: B=1 means forward, B=0 means backward
        wire count_up   = (a_rise & ~b_curr) | (a_fall &  b_curr);
        wire count_down = (a_rise &  b_curr) | (a_fall & ~b_curr);

        // Index pulse detection — rising edge on idx
        wire idx_rise = (enc_idx_r2[ch] & ~enc_idx_r1[ch]);

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                position[ch] <= 0;
                dir_reg[ch]  <= 0;
                idx_reg[ch]  <= 0;
                err_reg[ch]  <= 0;
            end else begin

                // Position counter
                if (clear_pos[ch]) begin
                    position[ch] <= 0;          // CPU commanded home
                end else if (count_up & count_down) begin
                    err_reg[ch] <= 1;           // both edges same cycle = error
                end else if (count_up) begin
                    position[ch] <= position[ch] + 1;
                    dir_reg[ch]  <= 1;          // forward
                end else if (count_down) begin
                    position[ch] <= position[ch] - 1;
                    dir_reg[ch]  <= 0;          // backward
                end

                // Index flag — set on index pulse, cleared by CPU
                if (clear_idx[ch])
                    idx_reg[ch] <= 0;
                else if (idx_rise)
                    idx_reg[ch] <= 1;

            end
        end

    end
endgenerate

// ============================================================
// CPU read interface — returns position of selected channel
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reg_rdata <= 0;
    end else if (reg_re) begin
        reg_rdata <= position[reg_ch];
    end
end

// ============================================================
// Output assignments
// ============================================================
assign direction  = dir_reg;
assign idx_flag   = idx_reg;
assign error_flag = err_reg;

endmodule