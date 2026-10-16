`timescale 1ns/1ps

// One paper-sized functional smoke test: a 64x64 DiP array performs a
// 64x64x64 signed INT8 matrix multiplication through the scalar SRAM wrapper.
module tb_dip_target64;
    localparam integer L = 64;
    localparam integer AW = 18;
    localparam integer V = 24;
    localparam integer DEPTH = 1 << AW;
    reg clk = 0, rst_n = 0, start = 0;
    reg [11:0] M = L, N = L, K = L;
    reg [AW-1:0] base_A = 0, base_B = 8192, base_C = 16384;
    wire done, err;
    wire [AW-1:0] sram_addr;
    wire sram_we;
    wire [V-1:0] sram_wdata, sram_rdata;
    integer r, c, k, errors, acc, got;

    always #5 clk = ~clk;

    top_module #(
        .MAT_SIZE_BITS(12), .SRAM_AW(AW), .VAL_SIZE(V), .LANES(L),
        .WEIGHTS_PREPERMUTED(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .M(M), .N(N), .K(K),
        .base_addr_in1(base_A), .base_addr_in2(base_B),
        .base_addr_out(base_C), .done(done), .err(err),
        .sram_addr(sram_addr), .sram_we(sram_we),
        .sram_wdata(sram_wdata), .sram_rdata(sram_rdata)
    );

    sram_model #(.DEPTH(DEPTH), .WIDTH(V), .AW(AW)) mem (
        .clk(clk), .we(sram_we), .addr(sram_addr),
        .din(sram_wdata), .dout(sram_rdata)
    );

    function integer aval(input integer row, input integer col);
        begin aval = ((row + col) % 7) - 3; end
    endfunction
    function integer bval(input integer row, input integer col);
        begin bval = ((3*row + col) % 7) - 3; end
    endfunction

    initial begin
        // Store A in ordinary row-major form.
        for (r = 0; r < L; r = r + 1)
            for (c = 0; c < L; c = c + 1)
                mem.mem[base_A + r*L + c] = aval(r,c) & 8'hff;

        // Store B after the paper's software permutation:
        // B_perm[r][c] = B_orig[(r+c) mod N][c].
        for (r = 0; r < L; r = r + 1)
            for (c = 0; c < L; c = c + 1)
                mem.mem[base_B + r*L + c] = bval((r+c)%L,c) & 8'hff;

        for (r = 0; r < L; r = r + 1)
            for (c = 0; c < L; c = c + 1)
                mem.mem[base_C + r*L + c] = 0;

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
                    acc = acc + aval(r,k) * bval(k,c);
                got = $signed(mem.mem[base_C + r*L + c]);
                if (got !== acc) begin
                    if (errors < 5)
                        $display("MISMATCH C[%0d][%0d] got=%0d exp=%0d", r,c,got,acc);
                    errors = errors + 1;
                end
            end

        if (!err && errors == 0)
            $display("PASS: 64x64 DiP array, 64x64x64 signed INT8 matmul");
        else begin
            $display("FAIL: target64 err=%b mismatches=%0d", err, errors);
            $fatal(1);
        end
        $finish;
    end
endmodule
