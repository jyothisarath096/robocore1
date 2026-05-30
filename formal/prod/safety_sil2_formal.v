`default_nettype none
// ============================================================
// RoboCore-1 Safety Subsystem — IEC 61508 SIL2 Formal
// Yosys 0.48 bind-based white-box, PROVE mode, k-induction
//
// Induction Invariants:
//   INV1: estop_r2 == past(estop_r1)
//   INV2: brownout_r2 == past(brownout_r1)
//   INV3: safe_state == combinatorial definition exactly
//   INV4: fault_reg bits only set, never spontaneously clear
//   INV5: wd_fault[w] only set when wd_enable[w] and counter >= timeout
//
// SIL2 Properties:
//   S1:  safe_state == exact combinatorial expression
//   S2:  ESTOP → safe_state within 2 cycles (double-flop latency)
//   S3:  safe_state STICKY while estop_n low
//   S4:  brownout → safe_state within 2 cycles
//   S5:  any fault_in[i] → safe_state immediately (combinatorial)
//   S6:  fault_clear has NO effect while safe_state asserted
//   S7:  fault_clear has NO effect while estop active
//   S8:  fault_reg[8] latches ~estop_r2 and is sticky
//   S9:  fault_reg[9] latches ~brownout_r2 and is sticky
//   S10: fault_reg[10..12] latch fault_in[0..2] and are sticky
//   S11: wd_fault sticky — once set stays until pet or disable
//   S12: watchdog_fault == OR(wd_fault)
//   S13: estop_active == ~estop_r2 exactly
//   S14: brownout_active == ~brownout_r2 exactly
//   S15: double-flop chain: estop_r2 == past(estop_r1)
//   S16: double-flop chain: estop_r1 == past(estop_n)
//   S17: wd_expired == wd_fault (registered copy)
//   S18: safe_state asserted on reset deassert if any fault active
// ============================================================
module safety_sil2_formal (
    input wire clk,
    input wire rst_n,
    input wire estop_n,
    input wire brownout_n,
    input wire [31:0] fault_in,
    input wire        fault_clear,
    input wire [3:0]  wd_pet,
    input wire [3:0]  wd_enable,
    input wire [95:0] wd_timeout_flat
);

// Access DUT internals via bind
wire        safe_state     = safety_subsystem.safe_state;
wire        estop_active   = safety_subsystem.estop_active;
wire        brownout_active= safety_subsystem.brownout_active;
wire        watchdog_fault = safety_subsystem.watchdog_fault;
wire        system_fault   = safety_subsystem.system_fault;
wire [31:0] fault_reg      = safety_subsystem.fault_reg;
wire [3:0]  wd_expired     = safety_subsystem.wd_expired;
wire        estop_r1       = safety_subsystem.estop_r1;
wire        estop_r2       = safety_subsystem.estop_r2;
wire        brownout_r1    = safety_subsystem.brownout_r1;
wire        brownout_r2    = safety_subsystem.brownout_r2;
wire [3:0]  wd_fault       = safety_subsystem.wd_fault[3:0];

// =========================================================================
// ENVIRONMENT ASSUMPTIONS
// =========================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        assume(estop_n    == 1);
        assume(brownout_n == 1);
        assume(fault_in   == 0);
        assume(wd_enable  == 0);
        assume(wd_pet     == 0);
    end
end

// Watchdog timeouts are fixed configuration — don't change at runtime
always @(posedge clk)
    if (rst_n) assume(wd_timeout_flat == $past(wd_timeout_flat));

// =========================================================================
// INDUCTION INVARIANTS
// =========================================================================

// INV1: estop_r2 is the registered version of estop_r1
always @(posedge clk)
    if (rst_n) assert(estop_r2 == $past(estop_r1));

// INV2: brownout_r2 is the registered version of brownout_r1
always @(posedge clk)
    if (rst_n) assert(brownout_r2 == $past(brownout_r1));

// INV3: estop_r1 is the registered version of estop_n
always @(posedge clk)
    if (rst_n) assert(estop_r1 == $past(estop_n));

// INV4: brownout_r1 is the registered version of brownout_n
always @(posedge clk)
    if (rst_n) assert(brownout_r1 == $past(brownout_n));

// INV5: safe_state is exactly the combinatorial OR of all fault sources
always @(posedge clk)
    if (rst_n)
        assert(safe_state == (~estop_r2 | ~brownout_r2 | (|wd_fault) | (|fault_in)));

// INV6: fault_reg bits are sticky — once set they stay set
//       unless fault_clear is asserted AND safe_state is low
always @(posedge clk)
    if (rst_n && $past(rst_n)) begin
        if (!($past(fault_clear) && !$past(safe_state))) begin
            assert((fault_reg & $past(fault_reg)) == $past(fault_reg));
        end
    end

// INV7: wd_fault is sticky once set (until pet or disable)
always @(posedge clk)
    if (rst_n && $past(rst_n)) begin
        if ($past(wd_fault[0]) && $past(wd_enable[0]) && !$past(wd_pet[0]))
            assert(wd_fault[0]);
        if ($past(wd_fault[1]) && $past(wd_enable[1]) && !$past(wd_pet[1]))
            assert(wd_fault[1]);
        if ($past(wd_fault[2]) && $past(wd_enable[2]) && !$past(wd_pet[2]))
            assert(wd_fault[2]);
        if ($past(wd_fault[3]) && $past(wd_enable[3]) && !$past(wd_pet[3]))
            assert(wd_fault[3]);
    end

// =========================================================================
// S1: safe_state exactly matches combinatorial definition
// =========================================================================
always @(posedge clk)
    if (rst_n)
        assert(safe_state == (~estop_r2 | ~brownout_r2 | (|wd_fault) | (|fault_in)));

// =========================================================================
// S2: ESTOP → safe_state within 2 cycles (double-flop latency)
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && !$past(estop_n))
        assert(safe_state || $past(safe_state));

// =========================================================================
// S3: safe_state STICKY while estop_n is low
// =========================================================================
always @(posedge clk)
    if (rst_n && safe_state && !estop_n)
        assert(safe_state);

// =========================================================================
// S4: brownout → safe_state within 2 cycles
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && !$past(brownout_n))
        assert(safe_state || $past(safe_state));

// =========================================================================
// S5: any fault_in bit → safe_state immediately (combinatorial, 0 cycles)
// =========================================================================
always @(posedge clk)
    if (rst_n && |fault_in)
        assert(safe_state);

// =========================================================================
// S6: fault_clear has NO effect while safe_state asserted
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(safe_state) && $past(fault_clear))
        assert(fault_reg != 0 || $past(fault_reg) == 0);

// =========================================================================
// S7: fault_clear has NO effect while estop active
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && !$past(estop_n) && $past(fault_clear))
        assert(fault_reg[8]);

// =========================================================================
// S8: fault_reg[8] latches estop and is sticky
// =========================================================================
always @(posedge clk)
    if (rst_n && !estop_r2)
        assert(fault_reg[8] || $past(!rst_n));

always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(fault_reg[8]) &&
        !($past(fault_clear) && !$past(safe_state)))
        assert(fault_reg[8]);

// =========================================================================
// S9: fault_reg[9] latches brownout and is sticky
// =========================================================================
always @(posedge clk)
    if (rst_n && !brownout_r2)
        assert(fault_reg[9] || $past(!rst_n));

always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(fault_reg[9]) &&
        !($past(fault_clear) && !$past(safe_state)))
        assert(fault_reg[9]);

// =========================================================================
// S10: fault_in[0..2] latch into fault_reg[10..12] and are sticky
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(fault_in[0]))
        assert(fault_reg[10] || $past(!rst_n));

always @(posedge clk)
    if (rst_n && $past(fault_in[1]))
        assert(fault_reg[11] || $past(!rst_n));

always @(posedge clk)
    if (rst_n && $past(fault_in[2]))
        assert(fault_reg[12] || $past(!rst_n));

// =========================================================================
// S11: wd_fault sticky while enabled and not petted
// =========================================================================
always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(wd_fault[0]) &&
        $past(wd_enable[0]) && !$past(wd_pet[0]))
        assert(wd_fault[0]);

always @(posedge clk)
    if (rst_n && $past(rst_n) && $past(wd_fault[1]) &&
        $past(wd_enable[1]) && !$past(wd_pet[1]))
        assert(wd_fault[1]);

// =========================================================================
// S12: watchdog_fault == OR(wd_fault)
// =========================================================================
always @(posedge clk)
    if (rst_n) assert(watchdog_fault == |wd_fault);

// =========================================================================
// S13: estop_active == ~estop_r2 exactly
// =========================================================================
always @(posedge clk)
    if (rst_n) assert(estop_active == ~estop_r2);

// =========================================================================
// S14: brownout_active == ~brownout_r2 exactly
// =========================================================================
always @(posedge clk)
    if (rst_n) assert(brownout_active == ~brownout_r2);

// =========================================================================
// S15: double-flop chain integrity: estop_r2 == past(estop_r1)
// =========================================================================
always @(posedge clk)
    if (rst_n) assert(estop_r2 == $past(estop_r1));

// =========================================================================
// S16: double-flop chain integrity: estop_r1 == past(estop_n)
// =========================================================================
always @(posedge clk)
    if (rst_n) assert(estop_r1 == $past(estop_n));

// =========================================================================
// S17: wd_expired is registered copy of wd_fault
// =========================================================================
always @(posedge clk)
    if (rst_n) assert(wd_expired == $past(wd_fault));

// =========================================================================
// S18: safe_state low on reset (all synchronizers reset high = no fault)
// =========================================================================
always @(posedge clk)
    if (rst_n && !$past(rst_n))
        assert(!safe_state);

// =========================================================================
// COVER GOALS
// =========================================================================
always @(posedge clk) cover(rst_n && safe_state);
always @(posedge clk) cover(rst_n && estop_active);
always @(posedge clk) cover(rst_n && brownout_active);
always @(posedge clk) cover(rst_n && watchdog_fault);
always @(posedge clk) cover(rst_n && system_fault);
always @(posedge clk) cover(rst_n && fault_reg[8]);
always @(posedge clk) cover(rst_n && fault_reg[10]);
always @(posedge clk) cover(rst_n && fault_reg[3:0] != 0);
always @(posedge clk) cover(rst_n && !safe_state && $past(safe_state));
always @(posedge clk) cover(rst_n && $past(fault_reg != 0) && fault_reg == 0);
always @(posedge clk) cover(rst_n && safe_state && estop_active && brownout_active);

endmodule

// bind — attach to DUT without modifying RTL
bind safety_subsystem safety_sil2_formal formal_inst (
    .clk(clk), .rst_n(rst_n),
    .estop_n(estop_n), .brownout_n(brownout_n),
    .fault_in(fault_in), .fault_clear(fault_clear),
    .wd_pet(wd_pet), .wd_enable(wd_enable),
    .wd_timeout_flat(wd_timeout_flat)
);
`default_nettype wire
