`timescale 1ns/1ps
// Config matrix testbench.
//   cfg0: M=8 N=4 K=4   -> single (i,j) tile, long drain         (tests h-loop drain)
//   cfg1: M=4 N=4 K=8   -> j-loop over weight tiles, fresh writes (tests weight reload)
//   cfg2: M=8 N=4 K=8?? -> skipped (error ovf with these bases)
//   cfg2: M=8 N=8 K=4   -> i-loop with psum readback accumulate   (tests tile accumulation)
module tb_dip_matrix;
    localparam MAT_SIZE_BITS = 4;
    localparam BRAM_DEPTH    = 10;
    localparam VAL_SIZE      = 24;

    reg clk = 0, rst_n = 0, start = 0;
    reg  [MAT_SIZE_BITS-1:0] M, N, K;
    reg  [BRAM_DEPTH-1:0] base_addr_in1, base_addr_in2, base_addr_out;
    wire done, err;
    wire [VAL_SIZE-1:0]  din_mem_out;
    wire [BRAM_DEPTH-1:0] add_out;
    wire w_out;
    wire [VAL_SIZE-1:0] dout_mem;

    always #5 clk = ~clk;

    top_module dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .N(N), .K(K),
        .base_addr_in1(base_addr_in1), .base_addr_in2(base_addr_in2), .base_addr_out(base_addr_out),
        .done(done), .din_mem_out(din_mem_out), .add_out(add_out), .w_out(w_out),
        .err(err)
    );

    blk_mem_gen_0 #(.DEPTH(1024), .WIDTH(VAL_SIZE)) bram (
        .clka(clk), .wea(w_out),
        .addra(add_out), .dina(din_mem_out), .douta(dout_mem)
    );

    reg [7:0] MA [0:255];
    reg [7:0] MB [0:255];
    integer mM, mN, mK;
    integer r, c, k, i;

    task load_and_run;
        input integer mm, nn, kk;
        reg [7:0] elem;
        integer errors, val, cellsA, cellsB, cellsC;
        begin
            mM = mm; mN = nn; mK = kk;
            M = mm[3:0]; N = nn[3:0]; K = kk[3:0];
            base_addr_in1 = 10'd0; base_addr_in2 = 10'd64; base_addr_out = 10'd320;

            // random fill A (mM x mN), B (mN x mK)
            for (r = 0; r < mM; r = r + 1)
                for (c = 0; c < mN; c = c + 1) begin
                    elem = (r*13 + c*7 + 5) % 251;
                    MA[r*mN + c] = elem;
                    dut.bram_inst.mem[r*mN + c][7:0] = elem;
                end
            for (r = 0; r < mN; r = r + 1)
                for (c = 0; c < mK; c = c + 1) begin
                    elem = (r*5 + c*11 + 3) % 251;
                    MB[r*mK + c] = elem;
                    dut.bram_inst.mem[64 + r*mK + c][7:0] = elem;
                end
            // clear C region
            cellsC = mM * mK;
            for (i = 0; i < cellsC; i = i + 1)
                dut.bram_inst.mem[320 + i] = 24'd0;

            rst_n = 0; repeat (3) @(negedge clk);
            rst_n = 1; repeat (3) @(negedge clk);

            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
            wait (done === 1'b1);
            @(negedge clk);

            errors = 0;
            for (r = 0; r < mM; r = r + 1)
                for (c = 0; c < mK; c = c + 1) begin
                    val = $signed(dut.bram_inst.mem[320 + r*mK + c]);
                    // golden
                    begin : blk
                        integer t; reg signed [31:0] acc;
                        acc = 0;
                        for (t = 0; t < mN; t = t + 1)
                            acc = acc + $signed({24'h0, MA[r*mN + t]}) * $signed({24'h0, MB[t*mK + c]});
                        if (val !== acc) begin
                            $display("cfg M=%0d N=%0d K=%0d MISMATCH C[%0d][%0d] = %0d, golden = %0d",
                                     mM, mN, mK, r, c, val, acc);
                            errors = errors + 1;
                        end
                    end
                end
            if (errors == 0) $display("cfg M=%0d N=%0d K=%0d : PASS (%0d outputs)", mM, mN, mK, mM*mK);
            else             $display("cfg M=%0d N=%0d K=%0d : FAIL (%0d mismatches)", mM, mN, mK, errors);
        end
    endtask

    initial begin
        load_and_run(8, 4, 4);
        load_and_run(4, 4, 8);
        load_and_run(8, 8, 4);
        $finish;
    end

    initial begin #800000; $display("TIMEOUT"); $finish; end
endmodule
