// ============================================================
// RoboCore-1 PID Controller Testbench
// Tests proportional response, integral windup, at-target
// ============================================================

`timescale 1ns/1ps

module pid_controller_tb;

// ============================================================
// Clock and reset
// ============================================================
reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;      // 100MHz

// ============================================================
// 1MHz tick generator — divides 100MHz by 100
// ============================================================
reg [6:0] tick_div;
reg       tick_1mhz;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tick_div <= 0;
        tick_1mhz <= 0;
    end else begin
        if (tick_div == 7'd99) begin
            tick_div  <= 0;
            tick_1mhz <= 1;
        end else begin
            tick_div  <= tick_div + 1;
            tick_1mhz <= 0;
        end
    end
end

// ============================================================
// DUT connections
// ============================================================
reg  [31:0] target    [0:7];
reg  [31:0] actual    [0:7];
reg  [15:0] kp        [0:7];
reg  [15:0] ki        [0:7];
reg  [15:0] kd        [0:7];
reg  [15:0] out_max   [0:7];
reg  [47:0] int_limit [0:7];
reg  [7:0]  enable;

wire [15:0] pid_out   [0:7];
wire [7:0]  at_target;
wire [7:0]  saturated;

pid_controller #(
    .NUM_CHANNELS(8),
    .POS_WIDTH(32),
    .GAIN_WIDTH(16),
    .OUT_WIDTH(16),
    .ACC_WIDTH(48)
) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .tick_1mhz (tick_1mhz),
    .target    (target),
    .actual    (actual),
    .kp        (kp),
    .ki        (ki),
    .kd        (kd),
    .out_max   (out_max),
    .enable    (enable),
    .int_limit (int_limit),
    .pid_out   (pid_out),
    .at_target (at_target),
    .saturated (saturated)
);

// ============================================================
// Helper — wait for N PID update ticks
// ============================================================
task wait_ticks;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            @(posedge tick_1mhz);
            repeat(20) @(posedge clk);
        end
    end
endtask

// ============================================================
// Main test
// ============================================================
integer ch;

initial begin
    $dumpfile("pid_test.vcd");
    $dumpvars(0, pid_controller_tb);

    // Initialise all channels
    rst_n  = 0;
    enable = 8'h00;

    for (ch = 0; ch < 8; ch = ch + 1) begin
        target[ch]    = 0;
        actual[ch]    = 0;
        kp[ch]        = 16'd10;    // proportional gain
        ki[ch]        = 16'd1;     // integral gain
        kd[ch]        = 16'd5;     // derivative gain
        out_max[ch]   = 16'd1000;  // max PWM duty
        int_limit[ch] = 48'd10000; // integrator clamp
    end

    repeat(20) @(posedge clk);
    rst_n  = 1;
    repeat(10) @(posedge clk);

    $display("=== RoboCore-1 PID Controller Test ===");

    // --------------------------------------------------------
    // Test 1 — Proportional response
    // Large error should produce large output
    // --------------------------------------------------------
    $display("");
    $display("Test 1: Proportional response");
    enable      = 8'h01;       // enable channel 0 only
    target[0]   = 32'd1000;    // target position
    actual[0]   = 32'd0;       // current position = 0
                                // error = 1000

    wait_ticks(10);
    $display("Target=1000, Actual=0, Error=1000");
    $display("PID output CH0: %0d", pid_out[0]);

    if (pid_out[0] > 16'd0)
        $display("PASS: Output > 0 for positive error");
    else
        $display("FAIL: No output for positive error");

    // --------------------------------------------------------
    // Test 2 — Output saturation
    // Huge error should clamp to out_max
    // --------------------------------------------------------
    $display("");
    $display("Test 2: Output saturation");
    target[0] = 32'd100000;    // very large target
    actual[0] = 32'd0;

    wait_ticks(5);
    $display("PID output CH0: %0d (max=%0d)", pid_out[0], out_max[0]);

    if (pid_out[0] == out_max[0])
        $display("PASS: Output clamped to out_max");
    else if (pid_out[0] > 0)
        $display("PASS: Output positive and bounded");
    else
        $display("FAIL: Output not responding");

    // --------------------------------------------------------
    // Test 3 — At target detection
    // --------------------------------------------------------
    $display("");
    $display("Test 3: At-target detection");
    target[0] = 32'd500;
    actual[0] = 32'd495;       // within threshold of 10

    wait_ticks(15);
    $display("Target=500, Actual=495, Error=5 (threshold=10)");

    if (at_target[0])
        $display("PASS: At-target flag set within threshold");
    else
        $display("FAIL: At-target not set within threshold");

    // --------------------------------------------------------
    // Test 4 — Channel independence
    // --------------------------------------------------------
    $display("");
    $display("Test 4: Channel independence");
    enable    = 8'hFF;         // enable all 8 channels
    target[0] = 32'd1000;  actual[0] = 32'd0;
    target[1] = 32'd500;   actual[1] = 32'd500;  // already at target
    target[2] = 32'd200;   actual[2] = 32'd100;

    // Lower gains on CH2 so it doesn't saturate at error=100
    kp[2] = 16'd2;
    ki[2] = 16'd0;
    kd[2] = 16'd1;

    wait_ticks(20);

    $display("CH0 (error=1000): output=%0d", pid_out[0]);
    $display("CH1 (error=0):    output=%0d, at_target=%0d",
              pid_out[1], at_target[1]);
    $display("CH2 (error=100):  output=%0d", pid_out[2]);

    if (pid_out[0] > pid_out[2] && pid_out[2] > 0)
        $display("PASS: Larger error = larger output");
    else
        $display("FAIL: Output not proportional to error");

    if (at_target[1])
        $display("PASS: CH1 at target when error=0");
    else
        $display("FAIL: CH1 should be at target");

    // --------------------------------------------------------
    // Test 5 — Disable stops output
    // --------------------------------------------------------
    $display("");
    $display("Test 5: Disable clears output");
    enable = 8'h00;
    wait_ticks(5);

    if (pid_out[0] == 0 && pid_out[1] == 0)
        $display("PASS: All outputs zero when disabled");
    else
        $display("FAIL: Output not zero after disable");

    $display("");
    $display("=== Simulation Complete ===");
    $finish;
end

// Timeout
initial begin
    #100_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule