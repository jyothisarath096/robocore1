`default_nettype none
// ============================================================
// RoboCore-1 AXI4-Lite Formal — Production Grade v3
// Yosys 0.48 bind-based white-box, PROVE mode, full invariants
// 18 properties + 6 induction invariants + 11 cover goals
// ============================================================
module robocore1_axi_formal (
    input wire         aclk,
    input wire         aresetn,
    input wire [31:0]  awaddr,
    input wire         awvalid,
    input wire [31:0]  wdata,
    input wire [3:0]   wstrb,
    input wire         wvalid,
    input wire         bready,
    input wire [31:0]  araddr,
    input wire         arvalid,
    input wire         rready,
    input wire [15:0]  irq_in
);

// Access DUT internals via bind scope
wire        awready    = robocore1_axi.awready;
wire        wready     = robocore1_axi.wready;
wire [1:0]  bresp      = robocore1_axi.bresp;
wire        bvalid     = robocore1_axi.bvalid;
wire        arready    = robocore1_axi.arready;
wire [31:0] rdata      = robocore1_axi.rdata;
wire [1:0]  rresp      = robocore1_axi.rresp;
wire        rvalid     = robocore1_axi.rvalid;
wire        irq_out    = robocore1_axi.irq_out;
wire [1:0]  wr_state   = robocore1_axi.wr_state;
wire [1:0]  rd_state   = robocore1_axi.rd_state;
wire [31:0] wr_addr_r  = robocore1_axi.wr_addr_r;
wire [31:0] rd_addr_r  = robocore1_axi.rd_addr_r;
wire [31:0] wr_data_r  = robocore1_axi.wr_data_r;
wire [15:0] irq_mask   = robocore1_axi.irq_mask;
wire [15:0] irq_active = robocore1_axi.irq_active;
wire [15:0] irq_pending= robocore1_axi.irq_pending;
wire [31:0] sys_scratch= robocore1_axi.sys_scratch;
wire [3:0]  wd_pet     = robocore1_axi.wd_pet;

localparam WR_IDLE   = 2'd0;
localparam WR_DECODE = 2'd1;
localparam WR_RESP   = 2'd2;
localparam RD_IDLE   = 2'd0;
localparam RD_RESP   = 2'd2;
localparam OKAY      = 2'b00;
localparam SLVERR    = 2'b10;

// =========================================================================
// MASTER ASSUMPTIONS
// =========================================================================
always @(posedge aclk) begin
    if (!aresetn) begin
        assume(awvalid == 0); assume(wvalid  == 0);
        assume(arvalid == 0); assume(bready  == 0);
        assume(rready  == 0);
    end
end
always @(posedge aclk) begin
    if (aresetn && $past(awvalid) && !$past(awready)) assume(awvalid);
    if (aresetn && $past(wvalid)  && !$past(wready))  assume(wvalid);
    if (aresetn && $past(arvalid) && !$past(arready)) assume(arvalid);
    if (aresetn) assume(awvalid == wvalid);
    if (aresetn && $past(awvalid) && !$past(awready))
        assume(awaddr == $past(awaddr));
    if (aresetn && $past(arvalid) && !$past(arready))
        assume(araddr == $past(araddr));
end

// =========================================================================
// INDUCTION INVARIANTS — constrain reachable state for unbounded proof
// =========================================================================
// INV1: bvalid iff wr_state == WR_RESP
always @(posedge aclk)
    if (aresetn) assert(bvalid == (wr_state == WR_RESP));

// INV2: rvalid iff rd_state == RD_RESP
always @(posedge aclk)
    if (aresetn) assert(rvalid == (rd_state == RD_RESP));

// INV3: awready iff wr_state == WR_IDLE
always @(posedge aclk)
    if (aresetn) assert(awready == (wr_state == WR_IDLE));

// INV4: arready iff rd_state == RD_IDLE
always @(posedge aclk)
    if (aresetn) assert(arready == (rd_state == RD_IDLE));

// INV5: awready == wready always
always @(posedge aclk)
    if (aresetn) assert(awready == wready);

// INV6: irq_active exactly equals masked pending+in
always @(posedge aclk)
    if (aresetn)
        assert(irq_active == ((irq_pending | irq_in) & ~irq_mask));

// =========================================================================
// P1: BRESP only OKAY/SLVERR
// =========================================================================
always @(posedge aclk)
    if (aresetn && bvalid)
        assert(bresp == OKAY || bresp == SLVERR);

// =========================================================================
// P2: RRESP only OKAY/SLVERR
// =========================================================================
always @(posedge aclk)
    if (aresetn && rvalid)
        assert(rresp == OKAY || rresp == SLVERR);

// =========================================================================
// P3: BVALID sticky until BREADY
// =========================================================================
always @(posedge aclk)
    if (aresetn && $past(aresetn) && $past(bvalid) && !$past(bready))
        assert(bvalid);

// =========================================================================
// P4: RVALID sticky until RREADY
// =========================================================================
always @(posedge aclk)
    if (aresetn && $past(aresetn) && $past(rvalid) && !$past(rready))
        assert(rvalid);

// =========================================================================
// P5: AWREADY == WREADY always
// =========================================================================
always @(posedge aclk)
    if (aresetn) assert(awready == wready);

// =========================================================================
// P6: No new AW handshake while BVALID pending
// =========================================================================
always @(posedge aclk)
    if (aresetn && bvalid)
        assert(!(awvalid && awready));

// =========================================================================
// P7: BVALID only in WR_RESP
// =========================================================================
always @(posedge aclk)
    if (aresetn && bvalid)
        assert(wr_state == WR_RESP);

// =========================================================================
// P8: RVALID only in RD_RESP
// =========================================================================
always @(posedge aclk)
    if (aresetn && rvalid)
        assert(rd_state == RD_RESP);

// =========================================================================
// P9: wr_state in {0,1,2}
// =========================================================================
always @(posedge aclk)
    if (aresetn) assert(wr_state <= 2'd2);

// =========================================================================
// P10: rd_state in {0,1,2}
// =========================================================================
always @(posedge aclk)
    if (aresetn) assert(rd_state <= 2'd2);

// =========================================================================
// P11: CHIP_ID always correct
// =========================================================================
always @(posedge aclk)
    if (aresetn && rvalid &&
        rd_addr_r[19:16] == 4'h7 &&
        rd_addr_r[15:0]  == 16'h0000)
        assert(rdata == 32'hAC010002);

// =========================================================================
// P12: SLVERR on unmapped read
// =========================================================================
always @(posedge aclk)
    if (aresetn && rvalid && rd_addr_r[19:16] > 4'h7)
        assert(rresp == SLVERR);

// =========================================================================
// P13: SLVERR on unmapped write
// =========================================================================
always @(posedge aclk)
    if (aresetn && bvalid && wr_addr_r[19:16] > 4'h7)
        assert(bresp == SLVERR);

// =========================================================================
// P14: Scratch register round-trip
// =========================================================================
reg [31:0] scratch_written;
reg        scratch_valid;
always @(posedge aclk) begin
    if (!aresetn) begin
        scratch_written <= 0; scratch_valid <= 0;
    end else if (wr_state == WR_DECODE &&
                 wr_addr_r[19:16] == 4'h7 &&
                 wr_addr_r[15:0]  == 16'h0008) begin
        scratch_written <= wr_data_r; scratch_valid <= 1;
    end
end
always @(posedge aclk)
    if (aresetn && scratch_valid)
        assert(sys_scratch == scratch_written);

// =========================================================================
// P15: wd_pet is a pulse — zero outside WR_DECODE
// =========================================================================
always @(posedge aclk)
    if (aresetn && $past(aresetn) && wr_state != WR_DECODE)
        assert(wd_pet == 0);

// =========================================================================
// P16: irq_active & irq_mask == 0 always
// =========================================================================
always @(posedge aclk)
    if (aresetn) assert((irq_active & irq_mask) == 0);

// =========================================================================
// P17: irq_out == OR(irq_active)
// =========================================================================
always @(posedge aclk)
    if (aresetn) assert(irq_out == |irq_active);

// =========================================================================
// P18: irq_out low on first cycle after reset
// =========================================================================
always @(posedge aclk)
    if (aresetn && !$past(aresetn))
        assert(!irq_out);

// =========================================================================
// COVER GOALS
// =========================================================================
always @(posedge aclk) cover(aresetn && bvalid && bready && bresp==OKAY);
always @(posedge aclk) cover(aresetn && rvalid && rready && rresp==OKAY);
always @(posedge aclk) cover(aresetn && bvalid && bready && bresp==SLVERR);
always @(posedge aclk) cover(aresetn && rvalid && rready && rresp==SLVERR);
always @(posedge aclk) cover(aresetn && irq_out);
always @(posedge aclk) cover(aresetn && irq_out && $past(!irq_out));
always @(posedge aclk) cover(aresetn && rvalid && rdata==32'hAC010002);
always @(posedge aclk) cover(aresetn && wr_addr_r[19:16]==4'h5 && bvalid);
always @(posedge aclk) cover(aresetn && wr_addr_r[19:16]==4'h6 && bvalid);
always @(posedge aclk) cover(aresetn && rd_addr_r[19:16]==4'h3 && rvalid);
always @(posedge aclk) cover(aresetn && scratch_valid);

endmodule

// bind — attach to DUT without touching RTL
bind robocore1_axi robocore1_axi_formal formal_inst (
    .aclk(aclk), .aresetn(aresetn),
    .awaddr(awaddr), .awvalid(awvalid),
    .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid),
    .bready(bready), .araddr(araddr), .arvalid(arvalid),
    .rready(rready), .irq_in(irq_in)
);
`default_nettype wire
