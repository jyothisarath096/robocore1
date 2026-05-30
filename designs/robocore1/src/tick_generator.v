// ============================================================
// RoboCore-1 Tick Generator — Precision-First Edition
//
// Design philosophy:
//   Precision   — 10MHz PID update rate (10x industry standard)
//   Reliability — Independent counters, no shared state
//
// Tick outputs:
//   tick_10mhz  — PID controller (every 10 cycles at 100MHz)
//   tick_1mhz   — Fast peripherals (every 100 cycles)
//   tick_100khz — Slow peripherals (every 1000 cycles)
//   tick_1khz   — System heartbeat (every 100000 cycles)
//
// Part of the RoboCore-1 robotics SoC
// Open Source — MIT License
// ============================================================

module tick_generator #(
    parameter TICK_10MHZ_DIV  = 10,       // 100MHz / 10     = 10MHz
    parameter TICK_1MHZ_DIV   = 100,      // 100MHz / 100    = 1MHz
    parameter TICK_100KHZ_DIV = 1_000,    // 100MHz / 1000   = 100kHz
    parameter TICK_1KHZ_DIV   = 100_000   // 100MHz / 100000 = 1kHz
)(
    input  wire   clk,
    input  wire   rst_n,

    // Tick outputs — all single cycle pulses
    output reg    tick_10mhz,    // 10MHz  — PID update (precision-first)
    output reg    tick_1mhz,     // 1MHz   — fast peripherals
    output reg    tick_100khz,   // 100kHz — slow peripherals
    output reg    tick_1khz      // 1kHz   — heartbeat, watchdog reference
);

// ============================================================
// Counters — independently sized, no shared logic
// Independent counters = one counter failure cannot affect others
// This is the reliability guarantee
// ============================================================
reg [3:0]   cnt_10mhz;     // 4 bits  holds 0-9
reg [6:0]   cnt_1mhz;      // 7 bits  holds 0-99
reg [9:0]   cnt_100khz;    // 10 bits holds 0-999
reg [16:0]  cnt_1khz;      // 17 bits holds 0-99999

// ============================================================
// 10MHz tick — PID update rate
// Fires every 10 clock cycles = 100ns between PID corrections
// 10x faster than standard 1MHz implementations
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_10mhz  <= 0;
        tick_10mhz <= 0;
    end else begin
        if (cnt_10mhz == TICK_10MHZ_DIV - 1) begin
            cnt_10mhz  <= 0;
            tick_10mhz <= 1;
        end else begin
            cnt_10mhz  <= cnt_10mhz + 1;
            tick_10mhz <= 0;
        end
    end
end

// ============================================================
// 1MHz tick — fast peripheral reference
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_1mhz  <= 0;
        tick_1mhz <= 0;
    end else begin
        if (cnt_1mhz == TICK_1MHZ_DIV - 1) begin
            cnt_1mhz  <= 0;
            tick_1mhz <= 1;
        end else begin
            cnt_1mhz  <= cnt_1mhz + 1;
            tick_1mhz <= 0;
        end
    end
end

// ============================================================
// 100kHz tick — slow peripheral reference
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_100khz  <= 0;
        tick_100khz <= 0;
    end else begin
        if (cnt_100khz == TICK_100KHZ_DIV - 1) begin
            cnt_100khz  <= 0;
            tick_100khz <= 1;
        end else begin
            cnt_100khz  <= cnt_100khz + 1;
            tick_100khz <= 0;
        end
    end
end

// ============================================================
// 1kHz tick — system heartbeat
// Used by watchdog timers and status LED
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_1khz  <= 0;
        tick_1khz <= 0;
    end else begin
        if (cnt_1khz == TICK_1KHZ_DIV - 1) begin
            cnt_1khz  <= 0;
            tick_1khz <= 1;
        end else begin
            cnt_1khz  <= cnt_1khz + 1;
            tick_1khz <= 0;
        end
    end
end

endmodule
