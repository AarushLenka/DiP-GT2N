`timescale 1ns/1ps
// Debug write-back: trace all write operations and PE outputs
module tb_write_debug;
    localparam LANES = 4;
    localparam MAT_SIZE_BITS = 8;
    localparam BRAM_DEPTH = 18;
    localparam VAL_SIZE = 24;

    reg clk = 0, rst_n = 0, start = 0;
    reg [MAT_SIZE_BITS-1:0] M, N, K;
    reg [BRAM_DEPTH-1:0] base_addr_in1, base_addr_in2, base_addr_out;
    wire done, err;
    wire [VAL_SIZE-1:0]  din_mem_out;
    wire [BRAM_DEPTH-1:0] add_out;
    wire w_out;
    wire [VAL_SIZE-1:0] dout_mem;

    always #5 clk = ~clk;

    top_module #(.MAT_SIZE_BITS(MAT_SIZE_BITS),.BRAM_DEPTH(BRAM_DEPTH),.VAL_SIZE(VAL_SIZE),.LANES(LANES)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),
        .M(M),.N(N),.K(K),
        .base_addr_in1(base_addr_in1),.base_addr_in2(base_addr_in2),.base_addr_out(base_addr_out),
        .done(done),.din_mem_out(din_mem_out),.add_out(add_out),.w_out(w_out),
        .err(err),.dout_mem_in(dout_mem)
    );

    blk_mem_gen_0 #(.DEPTH(2**BRAM_DEPTH),.WIDTH(VAL_SIZE),.AW(BRAM_DEPTH)) bram (
        .clka(clk),.wea(w_out),.addra(add_out),.dina(din_mem_out),.douta(dout_mem)
    );

    // Probe internal signals
    wire [4:0] state = dut.ctrl_inst.state;
    wire [2:0] wcnt = dut.ctrl_inst.write_cnt;
    wire w_phase = dut.w_ctrl;
    wire [6:0] load_pos = dut.load_pos;
    wire [3:0] pe_en = dut.pe_en;
    wire [3:0] mul_en = dut.mul_en;
    wire [3:0] adder_en = dut.adder_en;
    wire wshift = dut.wshift;

    // Probe PE outputs
    wire signed [23:0] pe0 = dut.dtp_inst.pe_output[0];
    wire signed [23:0] pe1 = dut.dtp_inst.pe_output[1];
    wire signed [23:0] pe2 = dut.dtp_inst.pe_output[2];
    wire signed [23:0] pe3 = dut.dtp_inst.pe_output[3];

    // Probe systolic internals (row 3 outputs)
    wire signed [7:0] w30 = dut.dtp_inst.systolic_module.w_reg[3][0];
    wire signed [7:0] i30 = dut.dtp_inst.systolic_module.i_reg[3][0];
    wire signed [23:0] p30 = dut.dtp_inst.systolic_module.p_out[3][0];

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    integer i;
    initial begin
        $display("Write-back debug: M=4 N=4 K=4");
        M=4; N=4; K=4;
        base_addr_in1=0; base_addr_in2=16; base_addr_out=32;

        // Simple data: A = ones, B = [1,2,3,4] per column
        for (i=0; i<16; i=i+1) bram.mem[i][7:0] = 8'd1;
        for (i=0; i<16; i=i+1) bram.mem[16+i][7:0] = (i%4) + 1;
        for (i=0; i<16; i=i+1) bram.mem[32+i] = 0;

        rst_n = 0; repeat(4) @(negedge clk);
        rst_n = 1; repeat(4) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        // Trace through all states
        $display("\n=== STATE TRACE ===");
        fork
            begin
                repeat(200) begin
                    @(posedge clk);
                    #1;
                    if (state >= 4 && state <= 9)  // LOAD_TILE through COMPUTE
                        $display("cyc=%3d st=%2d pe_en=%b mul_en=%b add_en=%b wsh=%b w30=%0d i30=%0d p30=%0d",
                                 cyc, state, pe_en, mul_en, adder_en, wshift, w30, i30, p30);
                end
            end
            begin
                wait(done == 1);
            end
        join_any
        disable fork;
        @(negedge clk);
        $display("\n=== FINAL RESULTS ===");
        for (i=0; i<16; i=i+1)
            $display("C[%0d][%0d] = %0d", i/4, i%4, $signed(bram.mem[32+i]));
        $finish;
    end
endmodule
