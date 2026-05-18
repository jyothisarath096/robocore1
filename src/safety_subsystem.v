// ============================================================
// RoboCore-1 Safety Subsystem
// Watchdog timers, E-stop, brownout, fault management
// Designed for IEC 61508 SIL-2 compliance path
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module safety_subsystem #(
    parameter NUM_WATCHDOGS  = 4,         // independent watchdog timers
    parameter WD_WIDTH       = 24,        // watchdog counter width
    parameter NUM_FAULT_BITS = 16         // fault register width
)(
    // Clock and reset
    input  wire                          clk,
    input  wire                          rst_n,

    // --------------------------------------------------------
    // Watchdog interface
    // CPU must pet each watchdog within timeout period
    // If any watchdog expires — system fault
    // --------------------------------------------------------
    input  wire [NUM_WATCHDOGS-1:0]      wd_pet,       // pulse to reset timer
    input  wire [WD_WIDTH-1:0]           wd_timeout    [0:NUM_WATCHDOGS-1],
    input  wire [NUM_WATCHDOGS-1:0]      wd_enable,    // enable each watchdog

    // --------------------------------------------------------
    // Emergency stop
    // Active LOW — pulled low by hardware E-stop button
    // Bypasses all software — hardwired to safe_state output
    // --------------------------------------------------------
    input  wire                          estop_n,      // E-stop input (active low)

    // --------------------------------------------------------
    // Brownout detection
    // External voltage monitor asserts this when VCC drops
    // --------------------------------------------------------
    input  wire                          brownout_n,   // brownout input (active low)

    // --------------------------------------------------------
    // External fault inputs
    // From PID, encoder, PWM blocks
    // --------------------------------------------------------
    input  wire [NUM_FAULT_BITS-1:0]     fault_in,     // fault inputs from other blocks

    // --------------------------------------------------------
    // CPU interface
    // --------------------------------------------------------
    input  wire                          fault_clear,  // CPU clears fault register
    output reg  [NUM_FAULT_BITS-1:0]     fault_reg,    // latched fault register
    output reg  [NUM_WATCHDOGS-1:0]      wd_expired,   // which watchdog expired

    // --------------------------------------------------------
    // Safe state output
    // Goes HIGH on ANY fault — connect to motor enable pins
    // When HIGH: all motors must disable immediately
    // This is a dedicated output pin — not memory mapped
    // --------------------------------------------------------
    output wire                          safe_state,   // HIGH = fault = stop all

    // --------------------------------------------------------
    // Individual fault flags
    // --------------------------------------------------------
    output wire                          estop_active,
    output wire                          brownout_active,
    output wire                          watchdog_fault,
    output wire                          system_fault
);

// ============================================================
// Internal signals
// ============================================================

// Synchronise external inputs — double flop
reg estop_r1,    estop_r2;
reg brownout_r1, brownout_r2;

// Watchdog counters
reg [WD_WIDTH-1:0] wd_counter [0:NUM_WATCHDOGS-1];
reg [NUM_WATCHDOGS-1:0] wd_fault;

// Fault latch
reg fault_latched;

// ============================================================
// Input synchronisation
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        estop_r1    <= 1; estop_r2    <= 1;  // default safe (active low)
        brownout_r1 <= 1; brownout_r2 <= 1;
    end else begin
        estop_r1    <= estop_n;    estop_r2    <= estop_r1;
        brownout_r1 <= brownout_n; brownout_r2 <= brownout_r1;
    end
end

// ============================================================
// Watchdog timers — 4 independent counters
// CPU must pet each one within wd_timeout[n] cycles
// If counter reaches timeout without a pet — fault
// ============================================================
genvar w;
generate
    for (w = 0; w < NUM_WATCHDOGS; w = w + 1) begin : watchdogs
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                wd_counter[w] <= 0;
                wd_fault[w]   <= 0;
            end else begin
                if (!wd_enable[w]) begin
                    // Watchdog disabled — clear counter and fault
                    wd_counter[w] <= 0;
                    wd_fault[w]   <= 0;
                end else if (wd_pet[w]) begin
                    // CPU petted the watchdog — reset counter
                    wd_counter[w] <= 0;
                    wd_fault[w]   <= 0;
                end else if (wd_counter[w] >= wd_timeout[w]) begin
                    // Timeout expired — latch fault
                    wd_fault[w]   <= 1;
                end else begin
                    // Count up toward timeout
                    wd_counter[w] <= wd_counter[w] + 1;
                end
            end
        end
    end
endgenerate

// ============================================================
// Fault register — latches all fault sources
// Sticky — stays set until CPU clears it
// This is intentional: CPU must acknowledge every fault
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fault_reg     <= 0;
        wd_expired    <= 0;
        fault_latched <= 0;
    end else begin

        // Latch watchdog faults
        wd_expired <= wd_fault;

        // Build fault register
        // Bits 0-3:  watchdog expirations
        // Bits 4-7:  reserved for future watchdogs
        // Bit  8:    E-stop activated
        // Bit  9:    brownout detected
        // Bits 10-15: external fault inputs

        if (fault_clear && !safe_state) begin
            // CPU can only clear faults when system is safe
            // Cannot clear faults while E-stop is active
            fault_reg     <= 0;
            fault_latched <= 0;
        end else begin
            // Latch any new faults — sticky
            fault_reg[3:0]   <= fault_reg[3:0]   | wd_fault;
            fault_reg[8]     <= fault_reg[8]      | ~estop_r2;
            fault_reg[9]     <= fault_reg[9]      | ~brownout_r2;
            fault_reg[15:10] <= fault_reg[15:10]  | fault_in[5:0];

            // Set latched flag if any fault present
            if (|wd_fault || !estop_r2 || !brownout_r2 || |fault_in)
                fault_latched <= 1;
        end
    end
end

// ============================================================
// Output assignments
// ============================================================

// Individual fault flags
assign estop_active    = ~estop_r2;
assign brownout_active = ~brownout_r2;
assign watchdog_fault  = |wd_fault;
assign system_fault    = fault_latched;

// Safe state — OR of all fault conditions
// This is the master kill signal
// HIGH = fault present = disable all motors
assign safe_state = (~estop_r2)      |   // E-stop pressed
                   (~brownout_r2)    |   // power fault
                   (|wd_fault)       |   // any watchdog expired
                   (|fault_in);          // any external fault

endmodule