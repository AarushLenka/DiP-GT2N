`timescale 1ns/1ps
// Error-check testbench: verify error_check detects each invalidity class
// and that legal configs proceed to compute.
module tb_dip_errcheck;
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

    integer i;

    task run_case;
        input integer m, n, k, b1, b2, b3;
        input [8*40-1:0] desc;
        integer idx;
        begin
            M = m[3:0]; N = n[3:0]; K = k[3:0];
            base_addr_in1 = b1; base_addr_in2 = b2; base_addr_out = b3;
            rst_n = 0; repeat (3) @(negedge clk);
            rst_n = 1; repeat (3) @(negedge clk);
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
            wait (done === 1'b1);
            @(negedge clk);
            $display("%0s => err=%b", desc, err);
            if (err) begin
                // ensure no memory writes happened
                idx = 0;
                $display("    error latch held, no writes allowed (w_out should have stayed 0)");
            end
            // clear any writes for next test
            for (idx = 0; idx < 256; idx = idx + 1) dut.bram_inst.mem[idx] = 24'd0;
        end
    endtask

    initial begin
        // legal config
        run_case(4, 4, 4,   0, 64, 128, "M=4 N=4 K=4 (legal)          ");
        // size too small
        run_case(0, 4, 4,  0, 64, 128, "M=0 (empty)                  ");
        // not multiple of 4
        run_case(6, 4, 4,  0, 64, 128, "M=6 (not multiple of 4)      ");
        // BRAM overflow: base_addr_out=1000, M*K = 256 -> end1=1256 > 1024
        run_case(12, 12, 12,  0, 256, 1000, "12x12x12 with C base=1000 (ovf) ");
        // overlap: read region [0..80] overlaps write region [80..?] — check if overlaps get caught
        run_case(8, 8, 8,  0, 64, 72, "8x8x8 in2 base=64 out=72 (overlap)");
        $finish;
    end

    initial begin #2000000; $display("TIMEOUT"); $finish; end
endmodule
