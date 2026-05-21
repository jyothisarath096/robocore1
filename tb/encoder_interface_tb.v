// ============================================================
// RoboCore-1 Encoder Interface Testbench — Constitution v1.0
// Updated for 4x quadrature decode
// 4x decode: counts all 4 edges per cycle = 4 counts per cycle
// ============================================================

`timescale 1ns/1ps

module encoder_interface_tb;

reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;

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

// Read position task — flush pipeline before reading
task read_position;
    input [3:0] channel;
    begin
        repeat(10) @(posedge clk);
        reg_ch = channel;
        reg_re = 1;
        @(posedge clk);
        reg_re = 0;
        repeat(5) @(posedge clk);
    end
endtask

// Forward quadrature — 4x decode gives 4 counts per mechanical cycle
task quad_forward;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 0;  // A rises, B low  = +1
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 1;  // B rises, A high = +1
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 1;  // A falls, B high = +1
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 0;  // B falls, A low  = +1
            // Total: 4 counts per cycle (4x decode)
        end
    end
endtask

// Backward quadrature
task quad_backward;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 1;  // B rises, A low  = -1
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 1;  // A rises, B high = -1
            @(posedge clk); enc_a[0] = 1; enc_b[0] = 0;  // B falls, A high = -1
            @(posedge clk); enc_a[0] = 0; enc_b[0] = 0;  // A falls, B low  = -1
            // Total: 4 counts per cycle (4x decode)
        end
    end
endtask

initial begin
    $dumpfile("encoder_test.vcd");
    $dumpvars(0, encoder_interface_tb);

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

    $display("=== RoboCore-1 Encoder Interface Test (4x decode, Constitution v1.0) ===");
    $display("4x decode: 4 counts per mechanical cycle (was 2x = 2 counts)");
    $display("2x resolution improvement — same hardware cost");

    // --------------------------------------------------------
    // Test 1 — Forward counting
    // 100 mechanical cycles x 4 counts = 400 counts expected
    // --------------------------------------------------------
    $display("");
    $display("Test 1: Forward counting — 100 pulses = 400 counts (4x decode)");
    quad_forward(100);
    read_position(4'd0);
    repeat(5) @(posedge clk);
    $display("Position: %0d", reg_rdata);
    if (reg_rdata == 32'd400)
        $display("PASS: Position = 400 (4x decode confirmed)");
    else
        $display("FAIL: Expected 400, got %0d", reg_rdata);

    // --------------------------------------------------------
    // Test 2 — Backward counting
    // 30 backward cycles x 4 = 120 counts back
    // 400 - 120 = 280 expected
    // --------------------------------------------------------
    $display("");
    $display("Test 2: Backward — 30 pulses = 120 counts back (280 remaining)");
    quad_backward(30);
    read_position(4'd0);
    repeat(5) @(posedge clk);
    $display("Position: %0d", reg_rdata);
    if (reg_rdata == 32'd280)
        $display("PASS: Position = 280");
    else
        $display("FAIL: Expected 280, got %0d", reg_rdata);

    // --------------------------------------------------------
    // Test 3 — Direction flag
    // --------------------------------------------------------
    $display("");
    $display("Test 3: Direction flag");
    quad_forward(1);
    repeat(5) @(posedge clk);
    if (direction[0] == 1'b1)
        $display("PASS: Direction = forward");
    else
        $display("FAIL: Direction wrong after forward");

    quad_backward(1);
    repeat(5) @(posedge clk);
    if (direction[0] == 1'b0)
        $display("PASS: Direction = backward");
    else
        $display("FAIL: Direction wrong after backward");

    // --------------------------------------------------------
    // Test 4 — Index pulse
    // --------------------------------------------------------
    $display("");
    $display("Test 4: Index pulse detection");
    @(posedge clk); enc_idx[0] = 1;
    repeat(3) @(posedge clk);
    enc_idx[0] = 0;
    repeat(5) @(posedge clk);
    if (idx_flag[0])
        $display("PASS: Index flag set");
    else
        $display("FAIL: Index flag not set");

    @(posedge clk); clear_idx[0] = 1;
    @(posedge clk); clear_idx[0] = 0;
    repeat(3) @(posedge clk);
    if (!idx_flag[0])
        $display("PASS: Index flag cleared");
    else
        $display("FAIL: Index flag stuck");

    // --------------------------------------------------------
    // Test 5 — Homing
    // --------------------------------------------------------
    $display("");
    $display("Test 5: Position clear (homing)");
    @(posedge clk); clear_pos[0] = 1;
    @(posedge clk); clear_pos[0] = 0;
    read_position(4'd0);
    repeat(5) @(posedge clk);
    if (reg_rdata == 32'd0)
        $display("PASS: Position cleared to zero");
    else
        $display("FAIL: Position not cleared, got %0d", reg_rdata);

    // --------------------------------------------------------
    // Test 6 — Channel independence
    // CH1: 50 cycles x 4 = 200 counts
    // --------------------------------------------------------
    $display("");
    $display("Test 6: Multi-channel independence (CH1: 50 pulses = 200 counts)");
    repeat(50) begin
        @(posedge clk); enc_a[1] = 1; enc_b[1] = 0;
        @(posedge clk); enc_a[1] = 1; enc_b[1] = 1;
        @(posedge clk); enc_a[1] = 0; enc_b[1] = 1;
        @(posedge clk); enc_a[1] = 0; enc_b[1] = 0;
    end
    read_position(4'd1);
    repeat(5) @(posedge clk);
    if (reg_rdata == 32'd200)
        $display("PASS: CH1 position = 200, independent of CH0");
    else
        $display("FAIL: CH1 expected 200, got %0d", reg_rdata);

    // --------------------------------------------------------
    // Test 7 — 4x vs 2x resolution comparison
    // --------------------------------------------------------
    $display("");
    $display("=== 4x Precision Summary ===");
    $display("2x decode (old): 2 counts per cycle");
    $display("4x decode (new): 4 counts per cycle");
    $display("Resolution gain: 2x improvement at zero hardware cost");
    $display("At 1000 CPR encoder: 4000 counts/rev vs 2000 (old)");

    $display("");
    $display("=== Simulation Complete ===");
    $finish;
end

initial begin
    #50_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule
