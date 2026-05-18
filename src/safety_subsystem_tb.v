// ============================================================
// RoboCore-1 Safety Subsystem Testbench
// Tests all fault conditions and safe state logic
// ============================================================

`timescale 1ns/1ps

module safety_subsystem_tb;

// ============================================================
// Clock and reset
// ============================================================
reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;

// ============================================================
// DUT connections
// ============================================================
reg  [3:0]  wd_pet;
reg  [23:0] wd_timeout [0:3];
reg  [3:0]  wd_enable;
reg         estop_n;
reg         brownout_n;
reg  [15:0] fault_in;
reg         fault_clear;

wire [15:0] fault_reg;
wire [3:0]  wd_expired;
wire        safe_state;
wire        estop_active;
wire        brownout_active;
wire        watchdog_fault;
wire        system_fault;

safety_subsystem #(
    .NUM_WATCHDOGS (4),
    .WD_WIDTH      (24),
    .NUM_FAULT_BITS(16)
) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .wd_pet         (wd_pet),
    .wd_timeout     (wd_timeout),
    .wd_enable      (wd_enable),
    .estop_n        (estop_n),
    .brownout_n     (brownout_n),
    .fault_in       (fault_in),
    .fault_clear    (fault_clear),
    .fault_reg      (fault_reg),
    .wd_expired     (wd_expired),
    .safe_state     (safe_state),
    .estop_active   (estop_active),
    .brownout_active(brownout_active),
    .watchdog_fault (watchdog_fault),
    .system_fault   (system_fault)
);

// ============================================================
// Main test
// ============================================================
integer i;

initial begin
    $dumpfile("safety_test.vcd");
    $dumpvars(0, safety_subsystem_tb);

    // Initialise — system safe by default
    rst_n       = 0;
    wd_pet      = 4'hF;    // all watchdogs petted
    wd_enable   = 4'h0;    // all disabled at start
    estop_n     = 1;       // E-stop not pressed
    brownout_n  = 1;       // power good
    fault_in    = 16'h0;   // no faults
    fault_clear = 0;

    // Set watchdog timeouts
    // Short timeouts for simulation speed
    for (i = 0; i < 4; i = i + 1)
        wd_timeout[i] = 24'd100;   // 100 cycle timeout

    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    $display("=== RoboCore-1 Safety Subsystem Test ===");

    // --------------------------------------------------------
    // Test 1 — Clean start, no faults
    // --------------------------------------------------------
    $display("");
    $display("Test 1: Clean start — no faults");
    repeat(10) @(posedge clk);

    if (!safe_state)
        $display("PASS: safe_state LOW — system operational");
    else
        $display("FAIL: safe_state HIGH at clean start");

    // --------------------------------------------------------
    // Test 2 — Emergency stop
    // --------------------------------------------------------
    $display("");
    $display("Test 2: Emergency stop");
    estop_n = 0;           // press E-stop
    repeat(5) @(posedge clk);

    if (safe_state && estop_active)
        $display("PASS: safe_state HIGH, estop_active on E-stop press");
    else
        $display("FAIL: E-stop not detected");

    // Release E-stop
    estop_n = 1;
    repeat(5) @(posedge clk);

    // Clear fault register
    fault_clear = 1;
    repeat(2) @(posedge clk);
    fault_clear = 0;
    repeat(5) @(posedge clk);

    if (!safe_state)
        $display("PASS: safe_state cleared after E-stop release");
    else
        $display("FAIL: safe_state stuck after E-stop release");

    // --------------------------------------------------------
    // Test 3 — Brownout detection
    // --------------------------------------------------------
    $display("");
    $display("Test 3: Brownout detection");
    brownout_n = 0;        // power droops
    repeat(5) @(posedge clk);

    if (safe_state && brownout_active)
        $display("PASS: safe_state HIGH on brownout");
    else
        $display("FAIL: Brownout not detected");

    brownout_n  = 1;
    fault_clear = 1;
    repeat(2) @(posedge clk);
    fault_clear = 0;
    repeat(5) @(posedge clk);

    if (!safe_state)
        $display("PASS: Recovered after brownout");
    else
        $display("FAIL: safe_state stuck after brownout");

    // --------------------------------------------------------
    // Test 4 — Watchdog timeout
    // CPU stops petting watchdog 0 — simulates CPU crash
    // --------------------------------------------------------
    $display("");
    $display("Test 4: Watchdog timeout (simulates CPU crash)");
    wd_enable = 4'h1;      // enable watchdog 0 only
    wd_pet    = 4'h0;      // stop petting — CPU "crashed"

    // Wait longer than timeout (100 cycles)
    repeat(150) @(posedge clk);

    if (safe_state && watchdog_fault)
        $display("PASS: Watchdog expired — safe_state HIGH");
    else
        $display("FAIL: Watchdog did not trigger");

    if (wd_expired[0])
        $display("PASS: Watchdog 0 identified as expired");
    else
        $display("FAIL: Watchdog 0 not flagged");

    // --------------------------------------------------------
    // Test 5 — Watchdog recovery
    // CPU recovers and pets the watchdog
    // --------------------------------------------------------
    $display("");
    $display("Test 5: Watchdog recovery");
    wd_pet      = 4'hF;    // pet all watchdogs
    repeat(5) @(posedge clk);
    fault_clear = 1;
    repeat(2) @(posedge clk);
    fault_clear = 0;
    repeat(10) @(posedge clk);

    if (!safe_state)
        $display("PASS: System recovered after watchdog pet");
    else
        $display("FAIL: System stuck after watchdog recovery");

    // --------------------------------------------------------
    // Test 6 — External fault input
    // --------------------------------------------------------
    $display("");
    $display("Test 6: External fault from PID/encoder block");
    wd_enable = 4'h0;      // disable watchdogs for this test
    fault_in  = 16'h0001;  // PID block signals fault

    repeat(5) @(posedge clk);

    if (safe_state && system_fault)
        $display("PASS: External fault triggers safe_state");
    else
        $display("FAIL: External fault not detected");

    fault_in    = 16'h0;
    fault_clear = 1;
    repeat(2) @(posedge clk);
    fault_clear = 0;
    repeat(5) @(posedge clk);

    if (!safe_state)
        $display("PASS: Cleared after external fault resolved");
    else
        $display("FAIL: safe_state stuck after fault clear");

    // --------------------------------------------------------
    // Test 7 — Cannot clear fault while E-stop active
    // --------------------------------------------------------
    $display("");
    $display("Test 7: Cannot clear fault while E-stop active");
    estop_n     = 0;       // press E-stop
    repeat(5) @(posedge clk);
    fault_clear = 1;       // try to clear while E-stop active
    repeat(5) @(posedge clk);
    fault_clear = 0;

    if (safe_state)
        $display("PASS: Cannot clear fault while E-stop pressed");
    else
        $display("FAIL: Fault cleared while E-stop active — DANGEROUS");

    // Release E-stop properly
    estop_n     = 1;
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;

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