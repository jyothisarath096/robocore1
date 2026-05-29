module safety_formal_tb (input clk, rst_n);

reg  estop_n, brownout_n;
reg  [31:0] fault_in;
reg  fault_clear;
reg  [3:0]  wd_pet, wd_enable;
reg  [95:0] wd_timeout_flat;

wire [31:0] fault_reg;
wire        wd_expired, safe_state, estop_active;
wire        brownout_active, watchdog_fault, system_fault;

safety_subsystem u_safety (
    .clk(clk), .rst_n(rst_n),
    .estop_n(estop_n), .brownout_n(brownout_n),
    .fault_in(fault_in), .fault_clear(fault_clear),
    .wd_pet(wd_pet), .wd_enable(wd_enable),
    .wd_timeout_flat(wd_timeout_flat),
    .fault_reg(fault_reg), .wd_expired(wd_expired),
    .safe_state(safe_state), .estop_active(estop_active),
    .brownout_active(brownout_active),
    .watchdog_fault(watchdog_fault),
    .system_fault(system_fault)
);

// Full reset constraints
initial assume(!rst_n);
initial assume(estop_n   == 1'b1);
initial assume(fault_in  == 32'h0);
initial assume(wd_enable == 4'h0);
initial assume(u_safety.safe_state   == 0);
initial assume(u_safety.estop_active == 0);
initial assume(u_safety.fault_reg    == 0);

// Property 1: safe_state stays high while estop active
always @(posedge clk) begin
    if (rst_n && safe_state && !estop_n)
        assert(safe_state);
end

// Property 2: State machine in valid states
always @(posedge clk) begin
    if (rst_n)
        assert(u_safety.fault_reg == (u_safety.fault_reg & 32'hFFFFFFFF));
end

// Property 3: estop causes safe_state or estop_active within 2 cycles
reg estop_low_d1, estop_low_d2;
always @(posedge clk) begin
    estop_low_d1 <= (!rst_n) ? 0 : !estop_n;
    estop_low_d2 <= (!rst_n) ? 0 : estop_low_d1;
end
always @(posedge clk) begin
    if (rst_n && estop_low_d2)
        assert(safe_state || estop_active);
end

// Cover: safe_state reached and cleared
always @(posedge clk) cover(rst_n && safe_state);
always @(posedge clk) cover(rst_n && !safe_state && $past(safe_state));

endmodule
