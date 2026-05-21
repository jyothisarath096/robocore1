// ============================================================
// RoboCore-1 Tick Generator Testbench — Precision-First
// Verifies all four tick frequencies by exact pulse counting
// ============================================================

`timescale 1ns/1ps

module tick_generator_tb;

// ============================================================
// Clock and reset
// ============================================================
reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;      // 100MHz — 10ns period

// ============================================================
// DUT
// ============================================================
wire tick_10mhz;
wire tick_1mhz;
wire tick_100khz;
wire tick_1khz;

tick_generator #(
    .TICK_10MHZ_DIV (10),
    .TICK_1MHZ_DIV  (100),
    .TICK_100KHZ_DIV(1_000),
    .TICK_1KHZ_DIV  (100_000)
) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .tick_10mhz (tick_10mhz),
    .tick_1mhz  (tick_1mhz),
    .tick_100khz(tick_100khz),
    .tick_1khz  (tick_1khz)
);

// ============================================================
// Pulse counters
// ============================================================
integer count_10mhz;
integer count_1mhz;
integer count_100khz;
integer count_1khz;

always @(posedge clk) begin
    if (!rst_n) begin
        count_10mhz  <= 0;
        count_1mhz   <= 0;
        count_100khz <= 0;
        count_1khz   <= 0;
    end else begin
        if (tick_10mhz)  count_10mhz  <= count_10mhz  + 1;
        if (tick_1mhz)   count_1mhz   <= count_1mhz   + 1;
        if (tick_100khz) count_100khz <= count_100khz + 1;
        if (tick_1khz)   count_1khz   <= count_1khz   + 1;
    end
end

// ============================================================
// Pulse width checker — every tick must be exactly 1 cycle
// ============================================================
integer pw_10mhz;
integer pw_violations;

always @(posedge clk) begin
    if (!rst_n) begin
        pw_10mhz      <= 0;
        pw_violations <= 0;
    end else begin
        if (tick_10mhz) begin
            pw_10mhz <= pw_10mhz + 1;
        end else begin
            if (pw_10mhz > 1)
                pw_violations <= pw_violations + 1;
            pw_10mhz <= 0;
        end
    end
end

// ============================================================
// Main test
// ============================================================
initial begin
    $dumpfile("tick_test.vcd");
    $dumpvars(0, tick_generator_tb);

    rst_n = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;

    $display("=== RoboCore-1 Tick Generator Test (Precision-First) ===");
    $display("Running 1,000,000 clock cycles = 10ms at 100MHz");
    $display("");
    $display("Expected pulse counts:");
    $display("  10MHz  tick: 100,000 pulses");
    $display("  1MHz   tick:  10,000 pulses");
    $display("  100kHz tick:   1,000 pulses");
    $display("  1kHz   tick:      10 pulses");
    $display("");

    repeat(1_000_010) @(posedge clk);

    $display("Actual results:");
    $display("  10MHz  ticks: %0d", count_10mhz);
    $display("  1MHz   ticks: %0d", count_1mhz);
    $display("  100kHz ticks: %0d", count_100khz);
    $display("  1kHz   ticks: %0d", count_1khz);
    $display("");

    $display("=== Frequency Accuracy Tests ===");

    if (count_10mhz == 100_000)
        $display("PASS: 10MHz tick — exact (100000 pulses)");
    else
        $display("FAIL: 10MHz tick — got %0d, expected 100000", count_10mhz);

    if (count_1mhz == 10_000)
        $display("PASS: 1MHz tick — exact (10000 pulses)");
    else
        $display("FAIL: 1MHz tick — got %0d, expected 10000", count_1mhz);

    if (count_100khz == 1_000)
        $display("PASS: 100kHz tick — exact (1000 pulses)");
    else
        $display("FAIL: 100kHz tick — got %0d, expected 1000", count_100khz);

    if (count_1khz == 10)
        $display("PASS: 1kHz tick — exact (10 pulses)");
    else
        $display("FAIL: 1kHz tick — got %0d, expected 10", count_1khz);

    $display("");
    $display("=== Pulse Width Test ===");

    if (pw_violations == 0)
        $display("PASS: All 10MHz ticks exactly 1 cycle wide");
    else
        $display("FAIL: %0d pulse width violations detected", pw_violations);

    $display("");
    $display("=== Simulation Complete ===");
    $finish;
end

// Timeout
initial begin
    #200_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule
