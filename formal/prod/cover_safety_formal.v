`default_nettype none
// ============================================================
// RoboCore-1 Safety Cover Completeness — Production Grade
// DUT instantiated directly — all signals via ports
// ============================================================
module cover_safety_top;

reg        clk, rst_n;
reg        estop_n, brownout_n;
reg [31:0] fault_in;
reg        fault_clear;
reg [3:0]  wd_pet, wd_enable;
reg [95:0] wd_timeout_flat;

wire        wd_expired, safe_state, estop_active;
wire        brownout_active, watchdog_fault, system_fault;
wire [31:0] fault_reg;

safety_subsystem u_safety (
    .clk(clk), .rst_n(rst_n),
    .estop_n(estop_n), .brownout_n(brownout_n),
    .fault_in(fault_in), .fault_clear(fault_clear),
    .wd_pet(wd_pet), .wd_enable(wd_enable),
    .wd_timeout_flat(wd_timeout_flat),
    .fault_reg(fault_reg), .wd_expired(wd_expired),
    .safe_state(safe_state), .estop_active(estop_active),
    .brownout_active(brownout_active),
    .watchdog_fault(watchdog_fault), .system_fault(system_fault)
);

// Internal signals via hierarchical ref — valid since u_safety is local
wire [3:0] wd_fault = u_safety.wd_fault[3:0];

// =========================================================================
// RESET + ASSUMPTIONS
// =========================================================================
initial assume(!rst_n);
initial assume(estop_n==1); initial assume(brownout_n==1);
initial assume(fault_in==0); initial assume(wd_enable==0);
initial assume(wd_pet==0);
// Use small timeouts for cover reachability
initial assume(wd_timeout_flat == {4{24'd4}});

always @(posedge clk) begin
    if (!rst_n) begin
        assume(estop_n==1); assume(brownout_n==1);
        assume(fault_in==0); assume(wd_enable==0);
    end
    // Timeout fixed
    assume(wd_timeout_flat == $past(wd_timeout_flat));
end

// =========================================================================
// COVER GOALS — every fault source reachable
// =========================================================================
always @(posedge clk) cover(rst_n && safe_state);
always @(posedge clk) cover(rst_n && estop_active);
always @(posedge clk) cover(rst_n && brownout_active);
always @(posedge clk) cover(rst_n && watchdog_fault);
always @(posedge clk) cover(rst_n && system_fault);
// Every fault register bit
always @(posedge clk) cover(rst_n && fault_reg[0]);   // WD0
always @(posedge clk) cover(rst_n && fault_reg[1]);   // WD1
always @(posedge clk) cover(rst_n && fault_reg[2]);   // WD2
always @(posedge clk) cover(rst_n && fault_reg[3]);   // WD3
always @(posedge clk) cover(rst_n && fault_reg[8]);   // ESTOP
always @(posedge clk) cover(rst_n && fault_reg[9]);   // Brownout
always @(posedge clk) cover(rst_n && fault_reg[10]);  // PID fault
always @(posedge clk) cover(rst_n && fault_reg[11]);  // Encoder fault
always @(posedge clk) cover(rst_n && fault_reg[12]);  // PWM fault
// Recovery paths
always @(posedge clk) cover(rst_n && !safe_state && $past(safe_state));
always @(posedge clk) cover(rst_n && $past(fault_reg!=0) && fault_reg==0);
// Multiple simultaneous faults
always @(posedge clk) cover(rst_n && estop_active && brownout_active);
// All 4 watchdogs expired
always @(posedge clk) cover(rst_n && fault_reg[3:0]==4'hF);

endmodule
`default_nettype wire
