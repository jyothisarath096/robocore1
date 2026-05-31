// Blackbox stub for sram_wrapper — matches actual hardened macro interface
module sram_wrapper (
    input  wire        clk,
    input  wire [8:0]  pd_addr,
    input  wire        pd_sel,
    input  wire [31:0] pd_wdata,
    input  wire        pd_we,
    input  wire        pd_re,
    output wire [31:0] pd_dout,
    input  wire [9:0]  rx_addr,
    input  wire [7:0]  rx_din,
    input  wire        rx_we,
    output wire [7:0]  rx_dout,
    input  wire [9:0]  tx_addr,
    output wire [7:0]  tx_dout
);
endmodule
