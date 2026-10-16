`timescale 1ns/1ps
// Full re-verification with SIGNED INT8 golden semantics.
module tb_dip_signed;
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
        input integer b1, b2, b3;
        reg [7:0] elem;
        integer errors, val, cellsC;
        reg signed [31:0] acc;
        begin
            mM = mm; mN = nn; mK = kk;
            M = mm[3:0]; N = nn[3:0]; K = kk[3:0];
            base_addr_in1 = b1; base_addr_in2 = b2; base_addr_out = b3;

            for (r = 0; r < mM; r = r + 1)
                for (c = 0; c < mN; c = c + 1) begin
                    elem = (r*13 + c*7 + 5) % 256;
                    MA[r*mN + c] = elem;
                    dut.bram_inst.mem[b1 + r*mN + c][7:0] = elem;
                end
            for (r = 0; r < mN; r = r + 1)
                for (c = 0; c < mK; c = c + 1) begin
                    elem = (r*5 + c*11 + 3) % 256;
                    MB[r*mK + c] = elem;
                    dut.bram_inst.mem[b2 + r*mK + c][7:0] = elem;
                end
            cellsC = mM * mK + 8;
            for (i = 0; i < cellsC; i = i + 1)
                dut.bram_inst.mem[b3 + i] = 24'd0;

            rst_n = 0; repeat (3) @(negedge clk);
            rst_n = 1; repeat (3) @(negedge clk);
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
            wait (done === 1'b1);
            @(negedge clk);

            errors = 0;
            for (r = 0; r < mM; r = r + 1)
                for (c = 0; c < mK; c = c + 1) begin
                    val = $signed(dut.bram_inst.mem[b3 + r*mK + c]);
                    acc = 0;
                    for (k = 0; k < mN; k = k + 1)
                        acc = acc + $signed(MA[r*mN + k]) * $signed(MB[k*mK + c]);
                    if (val !== acc) begin
                        $display("cfg M=%0d N=%0d K=%0d MISMATCH C[%0d][%0d] = %0d, signed golden = %0d",
                                 mM, mN, mK, r, c, val, acc);
                        errors = errors + 1;
                    end
                end
            if (errors == 0) $display("cfg M=%0d N=%0d K=%0d (bases %0d/%0d/%0d) : PASS (%0d outputs, signed INT8 golden)", mM, mN, mK, b1, b2, b3, mM*mK);
            else             $display("cfg M=%0d N=%0d K=%0d (bases %0d/%0d/%0d) : FAIL (%0d mismatches)", mM, mN, mK, b1, b2, b3, errors);
        end
    endtask

    initial begin
        load_and_run(4, 4, 4,   0, 64, 128);
        load_and_run(8, 8, 8,   0, 64, 512);
        load_and_run(8, 4, 4,   0, 64, 320);
        load_and_run(4, 4, 8,   0, 64, 320);
        load_and_run(8, 8, 4,   0, 64, 320);
        load_and_run(8, 4, 8,   0, 32, 360);
        load_and_run(12, 12, 12, 0, 256, 512);
        $finish;
    end

    initial begin #1200000; $display("TIMEOUT"); $finish; end
endmodule
