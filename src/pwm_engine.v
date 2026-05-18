// ============================================================
// RoboCore-1 PWM Engine — Constitution v1.0 Compliant
//
// Cardinal Principles compliance:
//   Precision   — 20-bit counter (1,048,576 steps, 16x over original)
//   Reliability — Fault detection, active-low reset, safe default off
//   Speed       — Pure hardware, no CPU cycles after configuration
//   Future Proof — Fully parameterized, portable Verilog
//
// 16 independent PWM channels for full factory cell coverage:
//   CH0-5:  6-axis robot arm joints
//   CH6:    End effector / gripper
//   CH7-8:  Conveyor / rotary table
//   CH9-15: Spare / second arm / expansion
//
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module pwm_engine #(
    parameter NUM_CHANNELS   = 16,    // covers full factory cell
    parameter COUNTER_WIDTH  = 20     // 20-bit = 1,048,576 steps (Constitution: minimum 20-bit)
)(
    // Clock and reset
    input  wire                          clk,
    input  wire                          rst_n,

    // CPU interface (APB-style simple register bus)
    input  wire [3:0]                    reg_addr,
    input  wire [COUNTER_WIDTH-1:0]      reg_wdata,
    input  wire                          reg_we,
    input  wire [3:0]                    reg_ch,      // 4 bits for 16 channels

    // PWM outputs
    output wire [NUM_CHANNELS-1:0]       pwm_out,

    // Status
    output wire                          fault
);

// ============================================================
// Register map:
//   0x0 = PERIOD — PWM period in clock cycles
//   0x1 = DUTY   — high time in clock cycles
//   0x2 = ENABLE — 1 to enable channel
// ============================================================

reg [COUNTER_WIDTH-1:0] period  [0:NUM_CHANNELS-1];
reg [COUNTER_WIDTH-1:0] duty    [0:NUM_CHANNELS-1];
reg                     enable  [0:NUM_CHANNELS-1];
reg [COUNTER_WIDTH-1:0] counter [0:NUM_CHANNELS-1];
reg [NUM_CHANNELS-1:0]  pwm_reg;

integer i;

// ============================================================
// Register write — CPU configures channels
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
            period[i] <= 20'd1000;   // default 100kHz at 100MHz
            duty[i]   <= 20'd500;    // default 50% duty cycle
            enable[i] <= 1'b0;       // default disabled — safe state
        end
    end else if (reg_we) begin
        case (reg_addr)
            4'h0: period[reg_ch] <= reg_wdata;
            4'h1: duty[reg_ch]   <= reg_wdata;
            4'h2: enable[reg_ch] <= reg_wdata[0];
            default: ;
        endcase
    end
end

// ============================================================
// PWM generation — fully hardware, 16 independent channels
// 20-bit counters give 1,048,576 steps of resolution
// At 100MHz: minimum step = 952 picoseconds
// ============================================================
genvar ch;
generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : pwm_gen
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                counter[ch] <= 0;
                pwm_reg[ch] <= 0;
            end else if (enable[ch]) begin
                if (counter[ch] >= period[ch] - 1) begin
                    counter[ch] <= 0;
                    pwm_reg[ch] <= 1;
                end else begin
                    counter[ch] <= counter[ch] + 1;
                    if (counter[ch] >= duty[ch])
                        pwm_reg[ch] <= 0;
                end
            end else begin
                pwm_reg[ch] <= 0;   // disabled = always low = safe
                counter[ch] <= 0;
            end
        end
    end
endgenerate

// ============================================================
// Output and fault
// ============================================================
assign pwm_out = pwm_reg;

// Fault: duty >= period on any enabled channel
assign fault = |(
    {(duty[15] >= period[15]) & enable[15],
     (duty[14] >= period[14]) & enable[14],
     (duty[13] >= period[13]) & enable[13],
     (duty[12] >= period[12]) & enable[12],
     (duty[11] >= period[11]) & enable[11],
     (duty[10] >= period[10]) & enable[10],
     (duty[9]  >= period[9])  & enable[9],
     (duty[8]  >= period[8])  & enable[8],
     (duty[7]  >= period[7])  & enable[7],
     (duty[6]  >= period[6])  & enable[6],
     (duty[5]  >= period[5])  & enable[5],
     (duty[4]  >= period[4])  & enable[4],
     (duty[3]  >= period[3])  & enable[3],
     (duty[2]  >= period[2])  & enable[2],
     (duty[1]  >= period[1])  & enable[1],
     (duty[0]  >= period[0])  & enable[0]}
);

endmodule
