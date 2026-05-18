// ============================================================
// RoboCore-1 PWM Engine
// 8-channel hardware PWM for motor control
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module pwm_engine #(
    parameter NUM_CHANNELS = 16,       // number of PWM outputs
    parameter COUNTER_WIDTH = 16      // 16-bit = 65536 steps resolution
)(
    // Clock and reset
    input  wire                          clk,        // 100MHz system clock
    input  wire                          rst_n,      // active-low reset

    // CPU interface (APB-style simple register bus)
    input  wire [3:0]                    reg_addr,   // which register to write
    input  wire [COUNTER_WIDTH-1:0]      reg_wdata,  // data to write
    input  wire                          reg_we,     // write enable
    input  wire [2:0]                    reg_ch,     // which channel (0-7)

    // PWM outputs — connect directly to motor driver ICs
    output wire [NUM_CHANNELS-1:0]       pwm_out,

    // Status
    output wire                          fault       // 1 if any channel misconfigured
);

// ============================================================
// Register map (reg_addr):
//   0x0 = PERIOD    — sets PWM period in clock cycles
//   0x1 = DUTY      — sets high time in clock cycles
//   0x2 = ENABLE    — 1 to enable this channel, 0 to disable
// ============================================================

// Per-channel registers
reg [COUNTER_WIDTH-1:0] period  [0:NUM_CHANNELS-1];
reg [COUNTER_WIDTH-1:0] duty    [0:NUM_CHANNELS-1];
reg                     enable  [0:NUM_CHANNELS-1];

// Per-channel counters
reg [COUNTER_WIDTH-1:0] counter [0:NUM_CHANNELS-1];

// PWM output registers
reg [NUM_CHANNELS-1:0] pwm_reg;

// ============================================================
// Register write logic — CPU configures channels here
// ============================================================
integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
            period[i] <= 16'd1000;   // default: 100kHz at 100MHz clock
            duty[i]   <= 16'd500;    // default: 50% duty cycle
            enable[i] <= 1'b0;       // default: disabled
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
// PWM generation — runs entirely in hardware
// no CPU involvement after configuration
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
                    counter[ch] <= 0;           // reset counter at period
                    pwm_reg[ch] <= 1;           // go high at start of cycle
                end else begin
                    counter[ch] <= counter[ch] + 1;
                    // go low when counter hits duty cycle threshold
                    if (counter[ch] >= duty[ch])
                        pwm_reg[ch] <= 0;
                end
            end else begin
                pwm_reg[ch] <= 0;               // disabled = always low
                counter[ch] <= 0;
            end
        end
    end
endgenerate

// ============================================================
// Output assignments
// ============================================================
assign pwm_out = pwm_reg;

// Fault: any channel where duty >= period is misconfigured
assign fault = |({
    (duty[7] >= period[7]) & enable[7],
    (duty[6] >= period[6]) & enable[6],
    (duty[5] >= period[5]) & enable[5],
    (duty[4] >= period[4]) & enable[4],
    (duty[3] >= period[3]) & enable[3],
    (duty[2] >= period[2]) & enable[2],
    (duty[1] >= period[1]) & enable[1],
    (duty[0] >= period[0]) & enable[0]
});

endmodule