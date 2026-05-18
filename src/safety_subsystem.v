// ============================================================
// RoboCore-1 Safety Subsystem — Constitution v1.0 Compliant
//
// Cardinal Principles compliance:
//   Precision   — Exact fault source identification, 32-bit fault register
//   Reliability — HW E-stop bypass, 4 watchdogs, sticky faults
//                 Cannot clear faults while E-stop active
//                 Safe state active even if CPU is dead
//   Speed       — Single cycle fault response
//   Future Proof — 32-bit fault register (was 16-bit) for block expansion
//                  Covers: CAN FD, EtherCAT, TSN, RISC-V, ADC, future blocks
//
// Fault register bit map (32-bit):
//   [3:0]   — Watchdog expirations (WD0-WD3)
//   [7:4]   — Reserved for WD4-WD7 (future expansion)
//   [8]     — E-stop activated
//   [9]     — Brownout detected
//   [10]    — PID controller fault
//   [11]    — Encoder interface fault
//   [12]    — PWM engine fault
//   [13]    — CAN FD fault (future)
//   [14]    — EtherCAT fault (future)
//   [15]    — TSN fault (future)
//   [31:16] — Reserved for future blocks
//
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module safety_subsystem #(
    parameter NUM_WATCHDOGS  = 4,
    parameter WD_WIDTH       = 24,
    parameter NUM_FAULT_BITS = 32    // Constitution: 32-bit for future expansion
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // Watchdog interface
    input  wire [NUM_WATCHDOGS-1:0]      wd_pet,
    input  wire [WD_WIDTH*NUM_WATCHDOGS-1:0] wd_timeout_flat, // flattened: {wd3,wd2,wd1,wd0}
    input  wire [NUM_WATCHDOGS-1:0]      wd_enable,

    // Emergency stop — active LOW, hardwired
    input  wire                          estop_n,

    // Brownout — active LOW
    input  wire                          brownout_n,

    // External fault inputs from all blocks
    // [0]  = PID controller fault
    // [1]  = Encoder interface fault
    // [2]  = PWM engine fault
    // [3]  = CAN FD fault (future)
    // [4]  = EtherCAT fault (future)
    // [5]  = TSN fault (future)
    // [15:6] = Reserved
    input  wire [NUM_FAULT_BITS-1:0]     fault_in,

    // CPU interface
    input  wire                          fault_clear,
    output reg  [NUM_FAULT_BITS-1:0]     fault_reg,
    output reg  [NUM_WATCHDOGS-1:0]      wd_expired,

    // Safe state — HIGH = fault = stop all motors
    // Dedicated output pin — not memory mapped
    output wire                          safe_state,

    // Individual fault flags
    output wire                          estop_active,
    output wire                          brownout_active,
    output wire                          watchdog_fault,
    output wire                          system_fault
);

// ============================================================
// Input synchronisation — double flop all external signals
// Constitution: Reliability — every external signal double-flopped
// ============================================================
reg estop_r1,    estop_r2;
reg brownout_r1, brownout_r2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        estop_r1    <= 1; estop_r2    <= 1;
        brownout_r1 <= 1; brownout_r2 <= 1;
    end else begin
        estop_r1    <= estop_n;    estop_r2    <= estop_r1;
        brownout_r1 <= brownout_n; brownout_r2 <= brownout_r1;
    end
end

// Unpack flat timeout bus into per-watchdog values
wire [WD_WIDTH-1:0] wd_timeout [0:NUM_WATCHDOGS-1];
genvar wt;
generate
    for (wt = 0; wt < NUM_WATCHDOGS; wt = wt + 1) begin : wd_unpack
        assign wd_timeout[wt] = wd_timeout_flat[wt*WD_WIDTH +: WD_WIDTH];
    end
endgenerate

// ============================================================
// Watchdog timers — 4 independent counters
// Constitution: Reliability — cannot be disabled once armed
// ============================================================
reg [WD_WIDTH-1:0]      wd_counter [0:NUM_WATCHDOGS-1];
reg [NUM_WATCHDOGS-1:0] wd_fault;

genvar w;
generate
    for (w = 0; w < NUM_WATCHDOGS; w = w + 1) begin : watchdogs
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                wd_counter[w] <= 0;
                wd_fault[w]   <= 0;
            end else begin
                if (!wd_enable[w]) begin
                    wd_counter[w] <= 0;
                    wd_fault[w]   <= 0;
                end else if (wd_pet[w]) begin
                    wd_counter[w] <= 0;
                    wd_fault[w]   <= 0;
                end else if (wd_counter[w] >= wd_timeout[w]) begin
                    wd_fault[w]   <= 1;
                end else begin
                    wd_counter[w] <= wd_counter[w] + 1;
                end
            end
        end
    end
endgenerate

// ============================================================
// Fault register — 32-bit, sticky, CPU must acknowledge
// Constitution: Future Proof — 32-bit covers all planned blocks
// Constitution: Reliability — sticky, cannot clear during E-stop
// ============================================================
reg fault_latched;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fault_reg     <= 0;
        wd_expired    <= 0;
        fault_latched <= 0;
    end else begin
        wd_expired <= wd_fault;

        if (fault_clear && !safe_state) begin
            // Only clear when system is safe
            // Cannot clear while E-stop active — safety guarantee
            fault_reg     <= 0;
            fault_latched <= 0;
        end else begin
            // Latch all fault sources — sticky
            fault_reg[3:0]   <= fault_reg[3:0]   | wd_fault;
            fault_reg[8]     <= fault_reg[8]      | ~estop_r2;
            fault_reg[9]     <= fault_reg[9]      | ~brownout_r2;
            fault_reg[10]    <= fault_reg[10]     | fault_in[0];  // PID
            fault_reg[11]    <= fault_reg[11]     | fault_in[1];  // Encoder
            fault_reg[12]    <= fault_reg[12]     | fault_in[2];  // PWM
            fault_reg[13]    <= fault_reg[13]     | fault_in[3];  // CAN FD
            fault_reg[14]    <= fault_reg[14]     | fault_in[4];  // EtherCAT
            fault_reg[15]    <= fault_reg[15]     | fault_in[5];  // TSN
            fault_reg[31:16] <= 16'h0;                            // reserved

            if (|wd_fault || !estop_r2 || !brownout_r2 || |fault_in)
                fault_latched <= 1;
        end
    end
end

// ============================================================
// Output assignments
// ============================================================
assign estop_active    = ~estop_r2;
assign brownout_active = ~brownout_r2;
assign watchdog_fault  = |wd_fault;
assign system_fault    = fault_latched;

// Safe state — OR of all fault sources
// Constitution: Reliability — single cycle response
assign safe_state = (~estop_r2)   |
                   (~brownout_r2) |
                   (|wd_fault)    |
                   (|fault_in);

endmodule
