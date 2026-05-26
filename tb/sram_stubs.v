// ============================================================
// SKY130 SRAM Behavioral Stubs — for simulation only
// Real macros used during OpenLane synthesis
// ============================================================

module sky130_sram_2kbyte_1rw1r_32x512_8 (
    input         clk0, csb0, web0,
    input  [3:0]  wmask0,
    input  [8:0]  addr0,
    input  [31:0] din0,
    output reg [31:0] dout0,
    input         clk1, csb1,
    input  [8:0]  addr1,
    output reg [31:0] dout1
);
    reg [31:0] mem [0:511];
    integer i;
    initial for (i=0; i<512; i=i+1) mem[i] = 0;
    always @(posedge clk0) begin
        if (!csb0 && !web0) mem[addr0] <= din0;
        if (!csb0 &&  web0) dout0 <= mem[addr0];
    end
    always @(posedge clk1) begin
        if (!csb1) dout1 <= mem[addr1];
    end
endmodule

module sky130_sram_1kbyte_1rw1r_8x1024_8 (
    input        clk0, csb0, web0,
    input        wmask0,
    input [9:0]  addr0,
    input [7:0]  din0,
    output reg [7:0] dout0,
    input        clk1, csb1,
    input [9:0]  addr1,
    output reg [7:0] dout1
);
    reg [7:0] mem [0:1023];
    integer i;
    initial for (i=0; i<1024; i=i+1) mem[i] = 0;
    always @(posedge clk0) begin
        if (!csb0 && !web0) mem[addr0] <= din0;
        if (!csb0 &&  web0) dout0 <= mem[addr0];
    end
    always @(posedge clk1) begin
        if (!csb1) dout1 <= mem[addr1];
    end
endmodule

module sram_wrapper (
    input  wire        clk,
    input  wire [8:0]  pd_addr,
    input  wire        pd_sel,
    input  wire [31:0] pd_wdata,
    input  wire        pd_we,
    input  wire        pd_re,
    output reg  [31:0] pd_dout,
    input  wire [9:0]  rx_addr,
    input  wire [7:0]  rx_din,
    input  wire        rx_we,
    output reg  [7:0]  rx_dout,
    input  wire [9:0]  tx_addr,
    output reg  [7:0]  tx_dout
);
    reg [31:0] pd_mem_lo [0:511];
    reg [31:0] pd_mem_hi [0:511];
    reg [7:0]  rx_mem [0:1023];
    reg [7:0]  tx_mem [0:1023];
    integer si;
    initial begin
        for (si=0; si<512; si=si+1) begin pd_mem_lo[si]=0; pd_mem_hi[si]=0; end
        for (si=0; si<1024; si=si+1) begin rx_mem[si]=0; tx_mem[si]=0; end
    end
    always @(posedge clk) begin
        // Write first, then read (write-first mode)
        if (pd_we && !pd_sel) begin
            pd_mem_lo[pd_addr] <= pd_wdata;
        end
        if (pd_we &&  pd_sel) pd_mem_hi[pd_addr] <= pd_wdata;
        // Read always — latch output every cycle
        pd_dout <= pd_sel ? pd_mem_hi[pd_addr] : pd_mem_lo[pd_addr];
        if (rx_we) rx_mem[rx_addr] <= rx_din;
        rx_dout <= rx_mem[rx_addr];
        tx_dout <= tx_mem[tx_addr];
    end
endmodule

// SKY130 clock gate stub for simulation
module sky130_fd_sc_hd__dlclkp_1 (
    input  CLK,
    input  GATE,
    output GCLK
);
    assign GCLK = CLK; // simulation: always pass clock through
endmodule
