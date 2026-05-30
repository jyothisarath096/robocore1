// ============================================================
// RoboCore-1 SRAM Wrapper
// Wraps SKY130 OpenRAM macros for EtherCAT process data memory
// Uses pre-hardened PDK macros — not synthesizable flip-flops
// ============================================================
module sram_wrapper (
    input  wire        clk,
    // Process data port (32-bit wide, 512 deep — via 2kbyte macro)
    input  wire [8:0]  pd_addr,
    input  wire        pd_sel,
    input  wire [31:0] pd_wdata,
    input  wire        pd_we,
    input  wire        pd_re,
    output reg  [31:0] pd_dout,
    // RX buffer port (8-bit wide, 1024 deep — via 1kbyte macro)
    input  wire [9:0]  rx_addr,
    input  wire [7:0]  rx_din,
    input  wire        rx_we,
    output reg  [7:0]  rx_dout,
    // TX buffer port (8-bit wide, 1024 deep — shared macro)
    input  wire [9:0]  tx_addr,
    output reg  [7:0]  tx_dout
);

// ============================================================
// Process data memory — sky130_sram_2kbyte_1rw1r_32x512_8
// Port 0: read/write (pd_addr, pd_wdata, pd_we)
// Port 1: read only  (pd_addr for readback)
// ============================================================
wire [31:0] pd_dout0, pd_dout1;

sky130_sram_2kbyte_1rw1r_32x512_8 u_pd_sram (
    // Port 0 — read/write
    .clk0  (clk),
    .csb0  (!(pd_we | pd_re)),
    .web0  (!pd_we),
    .wmask0(4'hF),
    .addr0 (pd_addr),
    .din0  (pd_wdata),
    .dout0 (pd_dout0),
    // Port 1 — read only
    .clk1  (clk),
    .csb1  (!pd_re),
    .addr1 (pd_addr),
    .dout1 (pd_dout1)
);

// ============================================================
// RX + TX memory — sky130_sram_1kbyte_1rw1r_8x1024_8
// Port 0: RX write / TX read (time-multiplexed)
// Port 1: RX read
// ============================================================
wire [7:0] rx_dout0, rx_dout1;

sky130_sram_1kbyte_1rw1r_8x1024_8 u_rx_sram (
    .clk0  (clk),
    .csb0  (!rx_we),
    .web0  (!rx_we),
    .wmask0(1'b1),
    .addr0 (rx_addr),
    .din0  (rx_din),
    .dout0 (rx_dout0),
    .clk1  (clk),
    .csb1  (1'b0),
    .addr1 (rx_addr),
    .dout1 (rx_dout1)
);

wire [7:0] tx_dout_w;
sky130_sram_1kbyte_1rw1r_8x1024_8 u_tx_sram (
    .clk0  (clk),
    .csb0  (1'b1),
    .web0  (1'b1),
    .wmask0(1'b0),
    .addr0 (tx_addr),
    .din0  (8'h0),
    .dout0 (),
    .clk1  (clk),
    .csb1  (1'b0),
    .addr1 (tx_addr),
    .dout1 (tx_dout_w)
);

// Output mux — 2-cycle latency from SRAM
always @(posedge clk) begin
    pd_dout  <= pd_sel ? pd_dout1 : pd_dout0;
    rx_dout  <= rx_dout1;
    tx_dout  <= tx_dout_w;
end

endmodule
