`timescale 1ns/1ps
// Focused trace: dump key signals for M=N=K=4 with LANES=4
module tb_dip_trace2;
    localparam LANES = 4;
    localparam MAT_SIZE_BITS = 8;
    localparam BRAM_DEPTH = 10;   // small BRAM
    localparam VAL_SIZE = 24;

    reg clk = 0, rst_n = 0, start = 0;
    reg [MAT_SIZE_BITS-1:0] M = 4, N = 4, K = 4;
    reg [BRAM_DEPTH-1:0] base_addr_in1 = 0, base_addr_in2 = 64, base_addr_out = 128;
    wire done, err;
    wire [VAL_SIZE-1:0] din_mem_out;
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

    blk_mem_gen_0 #(.DEPTH(1024),.WIDTH(VAL_SIZE),.AW(BRAM_DEPTH)) bram (
        .clka(clk),.wea(w_out),.addra(add_out),.dina(din_mem_out),.douta(dout_mem)
    );

    // Load simple A=B=all-ones for easy golden: C[i][j] = N = 4 for all
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            bram.mem[i][7:0]    = 8'd1;  // A all-ones
            bram.mem[i][23:8]   = 0;
            bram.mem[64+i][7:0] = 8'd1;  // B all-ones
            bram.mem[64+i][23:8]= 0;
        end
        for (i = 0; i < 16; i = i + 1)
            bram.mem[128+i] = 0;
    end

    integer cycle;
    initial begin
        $dumpfile("verif/evidence/trace2.vcd");
        $dumpvars(0, tb_dip_trace2);

        rst_n = 0; repeat(4) @(negedge clk);
        rst_n = 1; repeat(4) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        for (cycle = 0; cycle < 400; cycle = cycle + 1) begin
            @(posedge clk);
            $display("cy=%3d %-12s bc=%2d wc=%2d wshift=%b pe_en=%b mul_en=%b add_en=%b w=%b add=%0d din=%0d dout=%0d",
                cycle,
                dut.ctrl_inst.state.name(),
                dut.ctrl_inst.burst_cnt,
                dut.ctrl_inst.write_cnt,
                dut.ctrl_inst.wshift,
                dut.ctrl_inst.pe_en,
                dut.ctrl_inst.mul_en,
                dut.ctrl_inst.adder_en,
                w_out, add_out,
                $signed(din_mem_out),
                $signed(dout_mem));
            if (done) begin
                $display("DONE at cycle %0d", cycle);
                $display("C[0][0]=%0d C[0][1]=%0d C[1][0]=%0d C[1][1]=%0d",
                    $signed(bram.mem[128]), $signed(bram.mem[129]),
                    $signed(bram.mem[132]), $signed(bram.mem[133]));
                $display("Expected: all %0d (A=B=all-ones, N=%0d)", N, N);
                $finish;
            end
        end
        $display("NOT DONE");
        $finish;
    end
endmodule
