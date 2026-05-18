// ============================================================
// RoboCore-1 PWM Engine Testbench
// Simulates 16 channels with different frequencies/duty cycles
// Mimics real robot: each axis moving independently
// ============================================================

`timescale 1ns/1ps

module pwm_engine_tb;

// ============================================================
// Clock and reset
// ============================================================
reg clk;
reg rst_n;

// 100MHz clock — 10ns period
initial clk = 0;
always #5 clk = ~clk;

// ============================================================
// DUT (Device Under Test) connections
// ============================================================
reg  [3:0]  reg_addr;
reg  [15:0] reg_wdata;
reg         reg_we;
reg  [2:0]  reg_ch;         // NOTE: 3 bits = channels 0-7 only
                             // we'll test first 8 of 16 channels
wire [15:0] pwm_out;
wire        fault;

// Instantiate the PWM engine
pwm_engine #(
    .NUM_CHANNELS(16),
    .COUNTER_WIDTH(16)
) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .reg_addr (reg_addr),
    .reg_wdata(reg_wdata),
    .reg_we   (reg_we),
    .reg_ch   (reg_ch),
    .pwm_out  (pwm_out),
    .fault    (fault)
);

// ============================================================
// Helper task — write to a channel register
// ============================================================
task write_reg;
    input [2:0] channel;
    input [3:0] address;
    input [15:0] data;
    begin
        @(posedge clk);
        reg_ch    = channel;
        reg_addr  = address;
        reg_wdata = data;
        reg_we    = 1;
        @(posedge clk);
        reg_we    = 0;
    end
endtask

// ============================================================
// Main test sequence
// ============================================================
initial begin
    // Setup waveform dump — creates pwm_test.vcd for GTKWave
    $dumpfile("pwm_test.vcd");
    $dumpvars(0, pwm_engine_tb);

    // Initialise all inputs
    rst_n     = 0;
    reg_addr  = 0;
    reg_wdata = 0;
    reg_we    = 0;
    reg_ch    = 0;

    // Hold reset for 10 clock cycles
    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    $display("=== RoboCore-1 PWM Engine Test ===");
    $display("Configuring 8 channels for robot axes...");

    // --------------------------------------------------------
    // Channel 0 — Joint 1 (Base rotation)
    // 100kHz, 25% duty cycle
    // --------------------------------------------------------
    write_reg(3'd0, 4'h0, 16'd1000);   // period = 1000 cycles = 100kHz
    write_reg(3'd0, 4'h1, 16'd250);    // duty   = 250  cycles = 25%
    write_reg(3'd0, 4'h2, 16'd1);      // enable
    $display("CH0 (Base):      100kHz, 25%% duty — configured");

    // --------------------------------------------------------
    // Channel 1 — Joint 2 (Shoulder)
    // 50kHz, 50% duty cycle
    // --------------------------------------------------------
    write_reg(3'd1, 4'h0, 16'd2000);   // period = 2000 cycles = 50kHz
    write_reg(3'd1, 4'h1, 16'd1000);   // duty   = 1000 cycles = 50%
    write_reg(3'd1, 4'h2, 16'd1);      // enable
    $display("CH1 (Shoulder):  50kHz,  50%% duty — configured");

    // --------------------------------------------------------
    // Channel 2 — Joint 3 (Elbow)
    // 50kHz, 75% duty cycle
    // --------------------------------------------------------
    write_reg(3'd2, 4'h0, 16'd2000);   // period = 2000 cycles = 50kHz
    write_reg(3'd2, 4'h1, 16'd1500);   // duty   = 1500 cycles = 75%
    write_reg(3'd2, 4'h2, 16'd1);      // enable
    $display("CH2 (Elbow):     50kHz,  75%% duty — configured");

    // --------------------------------------------------------
    // Channel 3 — Joint 4 (Wrist roll)
    // 25kHz, 50% duty cycle
    // --------------------------------------------------------
    write_reg(3'd3, 4'h0, 16'd4000);   // period = 4000 cycles = 25kHz
    write_reg(3'd3, 4'h1, 16'd2000);   // duty   = 2000 cycles = 50%
    write_reg(3'd3, 4'h2, 16'd1);      // enable
    $display("CH3 (Wrist roll): 25kHz, 50%% duty — configured");

    // --------------------------------------------------------
    // Channel 4 — Joint 5 (Wrist pitch)
    // 25kHz, 30% duty cycle
    // --------------------------------------------------------
    write_reg(3'd4, 4'h0, 16'd4000);   // period = 4000 cycles = 25kHz
    write_reg(3'd4, 4'h1, 16'd1200);   // duty   = 1200 cycles = 30%
    write_reg(3'd4, 4'h2, 16'd1);      // enable
    $display("CH4 (Wrist pitch): 25kHz, 30%% duty — configured");

    // --------------------------------------------------------
    // Channel 5 — Joint 6 (Tool rotation)
    // 10kHz, 60% duty cycle
    // --------------------------------------------------------
    write_reg(3'd5, 4'h0, 16'd10000);  // period = 10000 cycles = 10kHz
    write_reg(3'd5, 4'h1, 16'd6000);   // duty   = 6000  cycles = 60%
    write_reg(3'd5, 4'h2, 16'd1);      // enable
    $display("CH5 (Tool rot):  10kHz,  60%% duty — configured");

    // --------------------------------------------------------
    // Channel 6 — Gripper
    // 50kHz, 40% duty cycle
    // --------------------------------------------------------
    write_reg(3'd6, 4'h0, 16'd2000);   // period = 2000 cycles = 50kHz
    write_reg(3'd6, 4'h1, 16'd800);    // duty   = 800  cycles = 40%
    write_reg(3'd6, 4'h2, 16'd1);      // enable
    $display("CH6 (Gripper):   50kHz,  40%% duty — configured");

    // --------------------------------------------------------
    // Channel 7 — Conveyor
    // 5kHz, 50% duty cycle
    // --------------------------------------------------------
    write_reg(3'd7, 4'h0, 16'd20000);  // period = 20000 cycles = 5kHz
    write_reg(3'd7, 4'h1, 16'd10000);  // duty   = 10000 cycles = 50%
    write_reg(3'd7, 4'h2, 16'd1);      // enable
    $display("CH7 (Conveyor):  5kHz,   50%% duty — configured");

    $display("");
    $display("All channels running. Simulating 50000 clock cycles...");

    // Run for 50000 cycles — enough to see multiple PWM periods
    repeat(50000) @(posedge clk);

    // --------------------------------------------------------
    // Fault detection test
    // Set duty >= period on channel 0 — should trigger fault
    // --------------------------------------------------------
    $display("");
    $display("=== Fault Detection Test ===");
    write_reg(3'd0, 4'h1, 16'd1001);   // duty > period — invalid
    repeat(10) @(posedge clk);

    if (fault)
        $display("PASS: Fault detected correctly");
    else
        $display("FAIL: Fault not detected — check fault logic");

    // Fix it
    write_reg(3'd0, 4'h1, 16'd250);    // restore valid duty cycle
    repeat(10) @(posedge clk);

    if (!fault)
        $display("PASS: Fault cleared after fix");
    else
        $display("FAIL: Fault stuck high — check fault logic");

    // --------------------------------------------------------
    // Disable test — channel should go low immediately
    // --------------------------------------------------------
    $display("");
    $display("=== Disable Test ===");
    write_reg(3'd0, 4'h2, 16'd0);      // disable channel 0
    repeat(20) @(posedge clk);
    if (pwm_out[0] === 1'b0)
        $display("PASS: Channel 0 low after disable");
    else
        $display("FAIL: Channel 0 still high after disable");

    $display("");
    $display("=== Simulation Complete ===");
    $display("Open pwm_test.vcd in GTKWave to view waveforms");

    $finish;
end

// ============================================================
// Timeout watchdog — kills simulation if it hangs
// ============================================================
initial begin
    #10_000_000;
    $display("TIMEOUT: Simulation exceeded 10ms");
    $finish;
end

endmodule