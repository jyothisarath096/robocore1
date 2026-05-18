// ============================================================
// RoboCore-1 Encoder Interface Testbench
// Tests position counting, direction, index, and error detect
// ============================================================

`timescale 1ns/1ps

module encoder_interface_tb;

// ============================================================
// Clock and reset
// ============================================================
reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;      // 100MHz

// ============================================================
// DUT connections
// ============================================================
reg  [15:0] enc_a;
reg  [15:0] enc_b;
reg  [15:0] enc_idx;
reg  [3:0]  reg_ch;
reg         reg_re;
reg  [15:0] clear_pos;
reg  [15:0] clear_idx;

wire [31:0] reg_rdata;
wire [15:0] direction;
wire [15:0] idx_flag;
wire [15:0] error_flag;

encoder_interface #(
    .NUM_CHANNELS(16),
    .COUNTER_WIDTH(32)
) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .enc_a     (enc_a),
    .enc_b     (enc_b),
    .enc_idx   (enc_idx),
    .reg_ch    (reg_ch),
    .reg_re    (reg_re),
    .reg_rdata (reg_rdata),
    .clear_pos (clear_pos),
    .clear_idx (clear_idx),
    .direction (direction),
    .idx_flag  (idx_flag),
    .error_flag(error_flag)
);

// ============================================================
// Task — read position of a channel
// ============================================================
task read_position;
    input [3:0] channel;
    begin
        repeat(10) @(posedge clk);  // flush synchroniser pipeline
        reg_ch = channel;
        reg_re = 1;
        @(posedge clk);
        reg_re = 0;
        repeat(5) @(posedge clk);  // wait for data to settle
    end
endtask

// ============================================================
// Task — generate N forward quadrature pulses on channel 0
// ============================================================
task quad_forward;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            // A rises, B is low = forward
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 0;
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 1;
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 1;
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 0;
        end
    end
endtask

// ============================================================
// Task — generate N backward quadrature pulses on channel 0
// ============================================================
task quad_backward;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            // A rises, B is high = backward
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 1;
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 1;
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 0;
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 0;
        end
    end
endtask

// ============================================================
// Main test
// ============================================================
integer pos;

initial begin
    $dumpfile("encoder_test.vcd");
    $dumpvars(0, encoder_interface_tb);

    // Initialise
    rst_n     = 0;
    enc_a     = 0;
    enc_b     = 0;
    enc_idx   = 0;
    reg_ch    = 0;
    reg_re    = 0;
    clear_pos = 0;
    clear_idx = 0;

    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    $display("=== RoboCore-1 Encoder Interface Test ===");

    // --------------------------------------------------------
    // Test 1 — Forward counting
    // --------------------------------------------------------
    $display("");
    $display("Test 1: Forward counting — 100 pulses = 200 counts (2x decode) on CH0");
    quad_forward(100);
    read_position(4'd0);
    repeat(5) @(posedge clk);
    $display("Position after 100 forward pulses: %0d", reg_rdata);
    if (reg_rdata == 32'd200)
        $display("PASS: Position = 200");
    else
        $display("FAIL: Expected 200, got %0d", reg_rdata);

    // --------------------------------------------------------
    // Test 2 — Backward counting
    // --------------------------------------------------------
    $display("");
    $display("Test 2: Backward counting — 30 pulses back = 60 counts");
    quad_backward(30);
    read_position(4'd0);
    repeat(5) @(posedge clk);
    $display("Position after 30 backward pulses: %0d", reg_rdata);
    if (reg_rdata == 32'd140)
        $display("PASS: Position = 140");
    else
        $display("FAIL: Expected 140, got %0d", reg_rdata);

    // --------------------------------------------------------
    // Test 3 — Direction flag
    // --------------------------------------------------------
    $display("");
    $display("Test 3: Direction flag");
    quad_forward(1);
    repeat(5) @(posedge clk);
    if (direction[0] == 1'b1)
        $display("PASS: Direction = forward after forward pulse");
    else
        $display("FAIL: Direction wrong after forward pulse");

    quad_backward(1);
    repeat(5) @(posedge clk);
    if (direction[0] == 1'b0)
        $display("PASS: Direction = backward after backward pulse");
    else
        $display("FAIL: Direction wrong after backward pulse");

    // --------------------------------------------------------
    // Test 4 — Index pulse detection
    // --------------------------------------------------------
    $display("");
    $display("Test 4: Index pulse detection");
    @(posedge clk); enc_idx[0] = 1;
    repeat(3) @(posedge clk);
    enc_idx[0] = 0;
    repeat(5) @(posedge clk);
    if (idx_flag[0] == 1'b1)
        $display("PASS: Index flag set on index pulse");
    else
        $display("FAIL: Index flag not set");

    // Clear index flag
    @(posedge clk); clear_idx[0] = 1;
    @(posedge clk); clear_idx[0] = 0;
    repeat(3) @(posedge clk);
    if (idx_flag[0] == 1'b0)
        $display("PASS: Index flag cleared by CPU");
    else
        $display("FAIL: Index flag stuck high");

    // --------------------------------------------------------
    // Test 5 — Position clear (homing)
    // --------------------------------------------------------
    $display("");
    $display("Test 5: Position clear (robot homing)");
    @(posedge clk); clear_pos[0] = 1;
    @(posedge clk); clear_pos[0] = 0;
    read_position(4'd0);
    repeat(5) @(posedge clk);
    if (reg_rdata == 32'd0)
        $display("PASS: Position cleared to zero — homing works");
    else
        $display("FAIL: Position not cleared, got %0d", reg_rdata);

    // --------------------------------------------------------
    // Test 6 — Multiple channels independent
    // --------------------------------------------------------
    $display("");
    $display("Test 6: Multiple channels independent");
    // Drive channel 1 forward 50 pulses
    repeat(50) begin
        @(posedge clk); enc_a[1] = 1; enc_b[1] = 0;
        @(posedge clk); enc_a[1] = 1; enc_b[1] = 1;
        @(posedge clk); enc_a[1] = 0; enc_b[1] = 1;
        @(posedge clk); enc_a[1] = 0; enc_b[1] = 0;
    end
    read_position(4'd1);
    repeat(5) @(posedge clk);
    if (reg_rdata == 32'd100)
        $display("PASS: CH1 position = 100, independent of CH0");
    else
        $display("FAIL: CH1 expected 100, got %0d", reg_rdata);

    $display("");
    $display("=== Simulation Complete ===");
    $finish;
end

// Timeout watchdog
initial begin
    #50_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule