`timescale 1ns/1ps
`ifndef LANES
  `define LANES 4
`endif
module tb_dip_trace;
    localparam LANES = `LANES;
    localparam LW    = $clog2(LANES);
    localparam SRAM_AW = 18;
    localparam VAL_SIZE = 24;

    reg clk = 0, rst_n = 0, start = 0;
    reg [7:0] M, N, K;
    reg [SRAM_AW-1:0] base_A, base_B, base_C;
    wire done, err;
    wire [SRAM_AW-1:0]  sram_addr;
    wire                 sram_we;
    wire [VAL_SIZE-1:0] sram_wdata, sram_rdata;

    always #5 clk = ~clk;

    top_module #(.MAT_SIZE_BITS(8),.SRAM_AW(SRAM_AW),.VAL_SIZE(VAL_SIZE),.LANES(LANES)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),
        .M(M),.N(N),.K(K),
        .base_addr_in1(base_A),.base_addr_in2(base_B),.base_addr_out(base_C),
        .done(done),.err(err),
        .sram_addr(sram_addr),.sram_we(sram_we),
        .sram_wdata(sram_wdata),.sram_rdata(sram_rdata)
    );

    sram_model #(.DEPTH(2**SRAM_AW),.WIDTH(VAL_SIZE),.AW(SRAM_AW)) sram (
        .clk(clk),.we(sram_we),.addr(sram_addr),.din(sram_wdata),.dout(sram_rdata)
    );

    // Probe internals
    wire [3:0] state     = dut.ctrl.state;
    wire [LW-1:0] bcnt   = dut.ctrl.bcnt;
    wire [LW-1:0] hval   = dut.ctrl.hval;
    wire [3:0] pe_en     = dut.ctrl.pe_en;
    wire wshift          = dut.ctrl.wshift;
    wire load_w          = dut.ctrl.load_w_en;
    wire load_i          = dut.ctrl.load_i_en;
    wire wr              = dut.ctrl.write_en;
    wire [LW-1:0] lane   = dut.dtp.lane;
    wire [SRAM_AW-1:0] sa = dut.dtp.sram_addr;
    wire sw              = dut.dtp.sram_we;
    wire [SRAM_AW-1:0] wa = dut.dtp.wb_addr_r;

    wire signed [7:0] wl0 = dut.dtp.weight_lane[0];
    wire signed [7:0] wl1 = dut.dtp.weight_lane[1];
    wire signed [7:0] wl2 = dut.dtp.weight_lane[2];
    wire signed [7:0] wl3 = dut.dtp.weight_lane[3];
    wire signed [7:0] il0 = dut.dtp.in_lane[0];
    wire signed [7:0] il1 = dut.dtp.in_lane[1];
    wire signed [7:0] il2 = dut.dtp.in_lane[2];
    wire signed [7:0] il3 = dut.dtp.in_lane[3];
    wire signed [23:0] po0 = dut.dtp.pe_out[0];
    wire signed [23:0] po1 = dut.dtp.pe_out[1];
    wire signed [23:0] po2 = dut.dtp.pe_out[2];
    wire signed [23:0] po3 = dut.dtp.pe_out[3];

    integer cyc = 0;
    always @(posedge clk) cyc++;

    integer i;
    initial begin
        M=4; N=4; K=4;
        base_A=0; base_B=18'h40; base_C=18'h80;

        // A = all 1s
        for (i=0; i<16; i++) sram.mem[i] = 24'd1;
        // B = identity (pre-permuted = identity stays identity for DiP)
        for (i=0; i<16; i++) sram.mem[18'h40+i] = 24'd0;
        sram.mem[18'h40+ 0] = 24'd1; // B[0][0]
        sram.mem[18'h40+ 5] = 24'd1; // B[1][1]
        sram.mem[18'h40+10] = 24'd1; // B[2][2]
        sram.mem[18'h40+15] = 24'd1; // B[3][3]
        for (i=0; i<16; i++) sram.mem[18'h80+i] = 24'd0;

        rst_n=0; repeat(4) @(negedge clk);
        rst_n=1; repeat(4) @(negedge clk);
        @(negedge clk); start=1;
        @(negedge clk); start=0;

        $display("cyc  st bcnt h  pe   ws lw li wr | wlanes     | ilanes     | pe_out");
        repeat(200) begin
            @(posedge clk); #1;
            $display("%3d  %2d  %1d  %1d %04b %b  %b  %b  %b | %2d%2d%2d%2d | %2d%2d%2d%2d | %5d%5d%5d%5d | lane=%0d sa=%0d sw=%b wa=%0d",
                cyc,state,bcnt,hval,pe_en,wshift,load_w,load_i,wr,
                $signed(wl0),$signed(wl1),$signed(wl2),$signed(wl3),
                $signed(il0),$signed(il1),$signed(il2),$signed(il3),
                $signed(po0),$signed(po1),$signed(po2),$signed(po3),
                lane, sa, sw, wa);
            if (done) begin
                $display("DONE at cyc %0d", cyc);
                $display("C[0][0]=%0d C[0][1]=%0d C[0][2]=%0d C[0][3]=%0d",
                    $signed(sram.mem[18'h80+0]), $signed(sram.mem[18'h80+1]),
                    $signed(sram.mem[18'h80+2]), $signed(sram.mem[18'h80+3]));
                $finish;
            end
        end
        $display("TIMEOUT");
        $finish;
    end
endmodule
