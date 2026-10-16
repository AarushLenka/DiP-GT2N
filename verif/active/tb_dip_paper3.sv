`timescale 1ns/1ps

// Directed reproduction of the paper's 3x3 Fig. 3 schedule.  This uses a
// non-power-of-two array size to ensure the parameterized diagonal boundary
// and Algorithm-1 permutation are not accidentally limited to powers of two.
module tb_dip_paper3;
    localparam integer L = 3;
    localparam integer AW = 8;
    localparam integer V = 24;
    reg clk = 0, rst_n = 0, start = 0;
    reg [7:0] M = L, N = L, K = L;
    reg [AW-1:0] base_A = 0, base_B = 32, base_C = 64;
    wire done, err;
    wire [AW-1:0] addr;
    wire we;
    wire [V-1:0] wdata, rdata;
    integer r, c, k, acc, errors;
    integer A [0:8];
    integer B [0:8];

    always #5 clk = ~clk;

    top_module #(
        .MAT_SIZE_BITS(8), .SRAM_AW(AW), .VAL_SIZE(V), .LANES(L),
        .WEIGHTS_PREPERMUTED(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .M(M), .N(N), .K(K),
        .base_addr_in1(base_A), .base_addr_in2(base_B),
        .base_addr_out(base_C), .done(done), .err(err),
        .sram_addr(addr), .sram_we(we), .sram_wdata(wdata),
        .sram_rdata(rdata)
    );

    sram_model #(.DEPTH(1 << AW), .WIDTH(V), .AW(AW)) mem (
        .clk(clk), .we(we), .addr(addr), .din(wdata), .dout(rdata)
    );

    initial begin
        // A = [[1,2,3],[4,5,6],[7,8,9]]
        // B = [[1,2,3],[4,5,6],[7,8,9]]
        for (r = 0; r < L; r = r + 1)
            for (c = 0; c < L; c = c + 1) begin
                A[r*L+c] = r*L+c+1;
                B[r*L+c] = r*L+c+1;
                mem.mem[base_A + r*L+c] = A[r*L+c];
            end
        for (r = 0; r < L; r = r + 1)
            for (c = 0; c < L; c = c + 1)
                // Algorithm 1: stored B_perm[r][c] = B[(r+c)%L][c].
                mem.mem[base_B + r*L+c] = B[((r+c)%L)*L+c];
        for (r = 0; r < L*L; r = r + 1)
            mem.mem[base_C + r] = 0;

        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait (done === 1'b1);

        errors = 0;
        for (r = 0; r < L; r = r + 1)
            for (c = 0; c < L; c = c + 1) begin
                acc = 0;
                for (k = 0; k < L; k = k + 1)
                    acc = acc + A[r*L+k] * B[k*L+c];
                if ($signed(mem.mem[base_C + r*L+c]) !== acc) begin
                    $display("MISMATCH C[%0d][%0d] got=%0d exp=%0d", r, c,
                             $signed(mem.mem[base_C + r*L+c]), acc);
                    errors = errors + 1;
                end
            end

        if (!err && errors == 0)
            $display("PASS: paper Fig. 3 3x3 DiP schedule");
        else begin
            $display("FAIL: paper3 err=%b mismatches=%0d", err, errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
