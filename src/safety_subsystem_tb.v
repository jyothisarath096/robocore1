// ============================================================
// RoboCore-1 Safety Subsystem Testbench — Constitution v1.0
// Updated for 32-bit fault register
// ============================================================

`timescale 1ns/1ps

module safety_subsystem_tb;

reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;

reg  [3:0]  wd_pet;
reg  [95:0] wd_timeout_flat; // 4 x 24-bit flattened
reg  [3:0]  wd_enable;
reg         estop_n;
reg         brownout_n;
reg  [31:0] fault_in;      // was 16-bit — now 32-bit
reg         fault_clear;

wire [31:0] fault_reg;     // was 16-bit — now 32-bit
wire [3:0]  wd_expired;
wire        safe_state;
wire        estop_active;
wire        brownout_active;
wire        watchdog_fault;
wire        system_fault;

safety_subsystem #(
    .NUM_WATCHDOGS (4),
    .WD_WIDTH      (24),
    .NUM_FAULT_BITS(32)    // Constitution: 32-bit
) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .wd_pet         (wd_pet),
    .wd_timeout_flat(wd_timeout_flat),
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

integer i;

initial begin
    $dumpfile("safety_test.vcd");
    $dumpvars(0, safety_subsystem_tb);

    rst_n       = 0;
    wd_pet      = 4'hF;
    wd_enable   = 4'h0;
    estop_n     = 1;
    brownout_n  = 1;
    fault_in    = 32'h0;
    fault_clear = 0;

    // Pack 4x 24-bit timeouts into flat bus
    wd_timeout_flat = {24'd100, 24'd100, 24'd100, 24'd100};

    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    $display("=== RoboCore-1 Safety Subsystem Test (32-bit, Constitution v1.0) ===");

    // Test 1 — Clean start
    $display("");
    $display("Test 1: Clean start");
    repeat(10) @(posedge clk);
    if (!safe_state)
        $display("PASS: safe_state LOW — operational");
    else
        $display("FAIL: safe_state HIGH at clean start");

    // Test 2 — E-stop
    $display("");
    $display("Test 2: Emergency stop");
    estop_n = 0;
    repeat(5) @(posedge clk);
    if (safe_state && estop_active)
        $display("PASS: E-stop triggers safe_state");
    else
        $display("FAIL: E-stop not detected");

    estop_n     = 1;
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;
    repeat(5) @(posedge clk);
    if (!safe_state)
        $display("PASS: Recovered after E-stop release");
    else
        $display("FAIL: safe_state stuck after E-stop");

    // Test 3 — Brownout
    $display("");
    $display("Test 3: Brownout detection");
    brownout_n = 0;
    repeat(5) @(posedge clk);
    if (safe_state && brownout_active)
        $display("PASS: Brownout triggers safe_state");
    else
        $display("FAIL: Brownout not detected");

    brownout_n  = 1;
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;
    repeat(5) @(posedge clk);
    if (!safe_state)
        $display("PASS: Recovered after brownout");
    else
        $display("FAIL: safe_state stuck after brownout");

    // Test 4 — Watchdog timeout
    $display("");
    $display("Test 4: Watchdog timeout");
    wd_enable = 4'h1;
    wd_pet    = 4'h0;
    repeat(150) @(posedge clk);
    if (safe_state && watchdog_fault)
        $display("PASS: Watchdog expired — safe_state HIGH");
    else
        $display("FAIL: Watchdog did not trigger");
    if (wd_expired[0])
        $display("PASS: Watchdog 0 identified");
    else
        $display("FAIL: Watchdog 0 not flagged");

    // Test 5 — Watchdog recovery
    $display("");
    $display("Test 5: Watchdog recovery");
    wd_pet      = 4'hF;
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;
    repeat(10) @(posedge clk);
    if (!safe_state)
        $display("PASS: Recovered after watchdog pet");
    else
        $display("FAIL: Stuck after recovery");

    // Test 6 — External fault (PID block — bit 0)
    $display("");
    $display("Test 6: External fault — PID block (fault_in[0])");
    wd_enable  = 4'h0;
    fault_in   = 32'h00000001;   // PID fault
    repeat(5) @(posedge clk);
    if (safe_state && system_fault)
        $display("PASS: PID fault triggers safe_state");
    else
        $display("FAIL: PID fault not detected");
    if (fault_reg[10])
        $display("PASS: Fault latched at bit 10 (PID)");
    else
        $display("FAIL: Fault not latched at correct bit");

    fault_in    = 32'h0;
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;
    repeat(5) @(posedge clk);
    if (!safe_state)
        $display("PASS: Cleared after PID fault resolved");
    else
        $display("FAIL: safe_state stuck");

    // Test 7 — Future block fault bits (32-bit register)
    $display("");
    $display("Test 7: Future block fault bits (32-bit register)");
    fault_in = 32'h00000018;  // CAN FD (bit3) + EtherCAT (bit4)
    repeat(5) @(posedge clk);
    if (safe_state)
        $display("PASS: Future block faults trigger safe_state");
    else
        $display("FAIL: Future block faults not detected");
    if (fault_reg[13] && fault_reg[14])
        $display("PASS: CAN FD and EtherCAT faults latched correctly");
    else
        $display("FAIL: Future fault bits not latched correctly");

    fault_in    = 32'h0;
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;
    repeat(5) @(posedge clk);

    // Test 8 — Cannot clear during E-stop
    $display("");
    $display("Test 8: Cannot clear fault while E-stop active");
    estop_n     = 0;
    repeat(5) @(posedge clk);
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;
    if (safe_state)
        $display("PASS: Cannot clear fault while E-stop pressed");
    else
        $display("FAIL: Fault cleared during E-stop — DANGEROUS");

    estop_n     = 1;
    fault_clear = 1;
    repeat(5) @(posedge clk);
    fault_clear = 0;

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
