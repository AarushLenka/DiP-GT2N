`timescale 1ns/1ps
// Testbench: 8x8x8 int8 matmul through top_module (multi-tile, b=c=2)
// Checks all 64 outputs against a golden CPU reference.
module tb_dip_8;
    localparam MAT_SIZE_BITS = 4;
    localparam BRAM_DEPTH    = 10;
    localparam VAL_SIZE      = 24;
    localparam int SZ = 8;

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

    // row-major A, B, C layouts in the BRAM (8-bit payload in 24-bit words)
    reg [7:0] MA [0:63];
    reg [7:0] MB [0:63];
    integer r, c, k, i, seed;

    task preload_ab;
        begin
            for (r = 0; r < SZ; r = r + 1)
                for (c = 0; c < SZ; c = c + 1) begin
                    dut.bram_inst.mem[r*SZ + c][7:0]     = MA[r*SZ + c];   // A @ 0
                    dut.bram_inst.mem[64 + r*SZ + c][7:0] = MB[r*SZ + c]; // B @ 64
                end
            for (i = 0; i < 64; i = i + 1)
                dut.bram_inst.mem[128 + i] = 24'd0; // clear C region
        end
    endtask

    task run_matmul;
        begin
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
            wait (done === 1'b1);
            @(negedge clk);
        end
    endtask

    function [31:0] gold; // signed 8x8·8 -> up to ~16k fits
        input integer rr, cc;
        integer t; reg signed [31:0] acc;
        begin
            acc = 0;
            for (t = 0; t < SZ; t = t + 1)
                acc = acc + $signed({24'h0, MA[rr*SZ + t]}) * $signed({24'h0, MB[t*SZ + cc]});
            gold = acc;
        end
    endfunction

    integer errors, val;
    initial begin
        seed = 32'hC0FFEE;
        for (i = 0; i < 64; i = i + 1) begin
            seed = seed * 1103515245 + 12345;
            MA[i] = seed[13:6];                 // 0..255
            seed = seed * 1103515245 + 12345;
            MB[i] = seed[13:6];
        end

        rst_n = 0;
        M = 8; N = 8; K = 8;
        base_addr_in1 = 10'd0; base_addr_in2 = 10'd64; base_addr_out = 10'd128;
        repeat (5) @(negedge clk);
        preload_ab;
        rst_n = 1;
        repeat (5) @(negedge clk);
        run_matmul;

        errors = 0;
        for (r = 0; r < SZ; r = r + 1)
            for (c = 0; c < SZ; c = c + 1) begin
                val = $signed(dut.bram_inst.mem[128 + r*SZ + c]);
                if (val !== $signed(gold(r, c))) begin
                    $display("MISMATCH C[%0d][%0d] = %0d, golden = %0d", r, c, val, $signed(gold(r, c)));
                    errors = errors + 1;
                end
            end
        if (errors == 0) $display("8x8x8: ALL 64 OUTPUTS MATCH GOLDEN");
        else             $display("8x8x8: TOTAL MISMATCHES = %0d", errors);
        $finish;
    end

    initial begin #500000; $display("TIMEOUT"); $finish; end
endmodule
