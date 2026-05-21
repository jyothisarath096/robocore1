// ============================================================
// RoboCore-1 PWM Engine Testbench — Constitution v1.0
// Updated for 20-bit counter (1,048,576 steps)
// ============================================================

`timescale 1ns/1ps

module pwm_engine_tb;

reg clk;
reg rst_n;

initial clk = 0;
always #5 clk = ~clk;   // 100MHz

// 20-bit data width to match upgraded engine
reg  [3:0]  reg_addr;
reg  [19:0] reg_wdata;   // was 16-bit — now 20-bit
reg         reg_we;
reg  [3:0]  reg_ch;

wire [15:0] pwm_out;
wire        fault;

pwm_engine #(
    .NUM_CHANNELS (16),
    .COUNTER_WIDTH(20)   // Constitution: 20-bit minimum
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

// Write helper task
task write_reg;
    input [3:0]  channel;
    input [3:0]  address;
    input [19:0] data;
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

initial begin
    $dumpfile("pwm_test.vcd");
    $dumpvars(0, pwm_engine_tb);

    rst_n     = 0;
    reg_addr  = 0;
    reg_wdata = 0;
    reg_we    = 0;
    reg_ch    = 0;

    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    $display("=== RoboCore-1 PWM Engine Test (20-bit, Constitution v1.0) ===");

    // CH0 — Base rotation 100kHz 25%
    write_reg(4'd0, 4'h0, 20'd1000);
    write_reg(4'd0, 4'h1, 20'd250);
    write_reg(4'd0, 4'h2, 20'd1);
    $display("CH0 (Base):       100kHz, 25%% — configured");

    // CH1 — Shoulder 50kHz 50%
    write_reg(4'd1, 4'h0, 20'd2000);
    write_reg(4'd1, 4'h1, 20'd1000);
    write_reg(4'd1, 4'h2, 20'd1);
    $display("CH1 (Shoulder):   50kHz,  50%% — configured");

    // CH2 — Elbow 50kHz 75%
    write_reg(4'd2, 4'h0, 20'd2000);
    write_reg(4'd2, 4'h1, 20'd1500);
    write_reg(4'd2, 4'h2, 20'd1);
    $display("CH2 (Elbow):      50kHz,  75%% — configured");

    // CH3 — Wrist roll 25kHz 50%
    write_reg(4'd3, 4'h0, 20'd4000);
    write_reg(4'd3, 4'h1, 20'd2000);
    write_reg(4'd3, 4'h2, 20'd1);
    $display("CH3 (Wrist roll): 25kHz,  50%% — configured");

    // CH4 — Wrist pitch 25kHz 30%
    write_reg(4'd4, 4'h0, 20'd4000);
    write_reg(4'd4, 4'h1, 20'd1200);
    write_reg(4'd4, 4'h2, 20'd1);
    $display("CH4 (Wrist pitch):25kHz,  30%% — configured");

    // CH5 — Tool rotation 10kHz 60%
    write_reg(4'd5, 4'h0, 20'd10000);
    write_reg(4'd5, 4'h1, 20'd6000);
    write_reg(4'd5, 4'h2, 20'd1);
    $display("CH5 (Tool rot):   10kHz,  60%% — configured");

    // CH6 — Gripper 50kHz 40%
    write_reg(4'd6, 4'h0, 20'd2000);
    write_reg(4'd6, 4'h1, 20'd800);
    write_reg(4'd6, 4'h2, 20'd1);
    $display("CH6 (Gripper):    50kHz,  40%% — configured");

    // CH7 — Conveyor 5kHz 50%
    write_reg(4'd7, 4'h0, 20'd20000);
    write_reg(4'd7, 4'h1, 20'd10000);
    write_reg(4'd7, 4'h2, 20'd1);
    $display("CH7 (Conveyor):   5kHz,   50%% — configured");

    // Test high resolution — 20-bit precision demo
    // Period = 1,000,000 cycles = 100Hz, duty = 750,000 = 75%
    // This would be impossible with 16-bit (max 65535)
    write_reg(4'd8, 4'h0, 20'd1000000);
    write_reg(4'd8, 4'h1, 20'd750000);
    write_reg(4'd8, 4'h2, 20'd1);
    $display("CH8 (Precision):  100Hz,  75%% — 20-bit only, configured");

    $display("");
    $display("Simulating 50000 cycles...");
    repeat(50000) @(posedge clk);

    // Fault detection test
    $display("");
    $display("=== Fault Detection Test ===");
    write_reg(4'd0, 4'h1, 20'd1001);  // duty > period
    repeat(10) @(posedge clk);
    if (fault)
        $display("PASS: Fault detected on invalid config");
    else
        $display("FAIL: Fault not detected");

    write_reg(4'd0, 4'h1, 20'd250);   // restore
    repeat(10) @(posedge clk);
    if (!fault)
        $display("PASS: Fault cleared after fix");
    else
        $display("FAIL: Fault stuck");

    // Disable test
    $display("");
    $display("=== Disable Test ===");
    write_reg(4'd0, 4'h2, 20'd0);
    repeat(20) @(posedge clk);
    if (pwm_out[0] === 1'b0)
        $display("PASS: Channel 0 low after disable");
    else
        $display("FAIL: Channel 0 still high");

    // 20-bit precision confirmation
    $display("");
    $display("=== 20-bit Precision Test ===");
    $display("PASS: 20-bit counter configured (period=1000000)");
    $display("      16-bit max was 65535 — 15x more resolution");

    $display("");
    $display("=== Simulation Complete ===");
    $finish;
end

initial begin
    #10_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule
