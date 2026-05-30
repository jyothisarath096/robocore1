module sram_wrapper (
    input  wire        clk,
    input  wire        csb,
    input  wire        web,
    input  wire [7:0]  wmask,
    input  wire [8:0]  addr,
    input  wire [63:0] din,
    output wire [63:0] dout,
    input  wire        vccd1,
    input  wire        vssd1,
    input  wire        vpwr,
    input  wire        vgnd
);
endmodule
