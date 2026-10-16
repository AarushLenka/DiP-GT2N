`timescale 1ns/1ps
// ============================================================
// DiP verification testbench — ASIC-style SRAM model
// ============================================================
`ifndef LANES
  `define LANES 4
`endif

module tb_dip_sram;
    localparam LANES         = `LANES;
    localparam MAT_SIZE_BITS = 10;
    localparam SRAM_AW       = 18;
    localparam VAL_SIZE      = 24;
    localparam SRAM_DEPTH    = 2**SRAM_AW;

    reg  clk = 0, rst_n = 0, start = 0;
    reg  [MAT_SIZE_BITS-1:0] M, N, K;
    reg  [SRAM_AW-1:0] base_A, base_B, base_C;
    wire done, err;

    wire [SRAM_AW-1:0]  sram_addr;
    wire                 sram_we;
    wire [VAL_SIZE-1:0] sram_wdata;
    wire [VAL_SIZE-1:0] sram_rdata;

    always #5 clk = ~clk;

    top_module #(
        .MAT_SIZE_BITS(MAT_SIZE_BITS),
        .SRAM_AW(SRAM_AW),
        .VAL_SIZE(VAL_SIZE),
        .LANES(LANES)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .N(N), .K(K),
        .base_addr_in1(base_A),
        .base_addr_in2(base_B),
        .base_addr_out(base_C),
        .done(done), .err(err),
        .sram_addr(sram_addr),
        .sram_we(sram_we),
        .sram_wdata(sram_wdata),
        .sram_rdata(sram_rdata)
    );

    sram_model #(
        .DEPTH(SRAM_DEPTH),
        .WIDTH(VAL_SIZE),
        .AW(SRAM_AW)
    ) sram (
        .clk(clk),
        .we(sram_we),
        .addr(sram_addr),
        .din(sram_wdata),
        .dout(sram_rdata)
    );

    integer errors_total = 0;

    // Budget includes scalar SRAM tile gathering, weight loading, the
    // two-stage wavefront, and tile writeback.  It is deliberately generous
    // because this wrapper models a scalar memory rather than the paper's
    // banked wide memory.
    function integer budget;
        input integer mm, nn, kk;
        integer ti, tj, tk;
        begin
            ti = (mm + LANES - 1) / LANES;
            tj = (kk + LANES - 1) / LANES;
            tk = (nn + LANES - 1) / LANES;
            // Conservative upper bound for scalar tile gathering, weight
            // loading, the two-stage wavefront, and final tile writeback.
            budget = ti * tj * tk *
                     (3 * LANES * LANES + 3 * LANES + 16) + 500;
        end
    endfunction

    task run_test;
        input integer mm, nn, kk;
        input integer bA, bB, bC;
        integer r, c, k;
        reg [7:0] elem;
        reg signed [7:0]  A [0:65535];
        reg signed [7:0]  B_orig [0:65535];
        reg signed [7:0]  B_perm [0:65535];
        reg signed [31:0] acc;
        reg signed [23:0] got;
        integer errors, waited, tocy;
        begin
            $display("--------------------------------------------------");
            $display("TEST  M=%0d  N=%0d  K=%0d", mm, nn, kk);

            // Fill A
            for (r = 0; r < mm; r = r + 1)
                for (c = 0; c < nn; c = c + 1) begin
                    elem = (r * 17 + c * 13 + 3) & 8'hFF;
                    A[r*nn + c] = $signed(elem);
                    sram.mem[bA + r*nn + c] = {{(VAL_SIZE-8){1'b0}}, elem};
                end

            // Fill B with DiP Algorithm 1 permutation:
            // B_perm[r][c] = B_orig[(r+c) % nn][c]
            for (r = 0; r < nn; r = r + 1)
                for (c = 0; c < kk; c = c + 1) begin
                    elem = (r * 11 + c * 7 + 5) & 8'hFF;
                    B_orig[r*kk + c] = $signed(elem);
                end
            for (c = 0; c < kk; c = c + 1)
                for (r = 0; r < nn; r = r + 1)
                    B_perm[r*kk + c] = B_orig[((r+c) % nn)*kk + c];

            // Store permuted B in SRAM (weights)
            for (r = 0; r < nn; r = r + 1)
                for (c = 0; c < kk; c = c + 1)
                    sram.mem[bB + r*kk + c] = {{(VAL_SIZE-8){1'b0}}, B_perm[r*kk+c][7:0]};

            // Zero C
            for (r = 0; r < mm*kk; r = r + 1)
                sram.mem[bC + r] = '0;

            M = mm; N = nn; K = kk;
            base_A = bA[SRAM_AW-1:0];
            base_B = bB[SRAM_AW-1:0];
            base_C = bC[SRAM_AW-1:0];

            rst_n = 0; repeat(4) @(negedge clk);
            rst_n = 1; repeat(4) @(negedge clk);
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;

            tocy  = budget(mm, nn, kk);
            waited = 0;
            while (!done && waited < tocy) begin
                @(posedge clk); waited = waited + 1;
            end

            if (!done) begin
                $display("  TIMEOUT (%0d cycles, budget %0d)", waited, tocy);
                errors_total = errors_total + 1;
            end else begin
                // Check C = A * B_orig
                errors = 0;
                for (r = 0; r < mm; r = r + 1)
                    for (c = 0; c < kk; c = c + 1) begin
                        acc = 0;
                        for (k = 0; k < nn; k = k + 1)
                            acc = acc + A[r*nn + k] * B_orig[k*kk + c];
                        got = $signed(sram.mem[bC + r*kk + c]);
                        if (got !== acc[23:0]) begin
                            if (errors < 5)
                                $display("  MISMATCH C[%0d][%0d]: got %0d  exp %0d",
                                         r, c, $signed(got), acc);
                            errors = errors + 1;
                        end
                    end
                if (errors == 0)
                    $display("  PASS  (%0d outputs, %0d cycles)", mm*kk, waited);
                else begin
                    $display("  FAIL  (%0d/%0d mismatches)", errors, mm*kk);
                    errors_total = errors_total + errors;
                end
            end
        end
    endtask

    initial begin
        if (LANES == 4) begin
            run_test( 4,  4,  4,  18'h00000, 18'h00040, 18'h00080);
            run_test( 8,  4,  4,  18'h00000, 18'h00040, 18'h00080);
            run_test( 4,  4,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test( 4,  8,  4,  18'h00000, 18'h00040, 18'h00080);
            run_test( 8,  8,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test( 8,  4,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test( 4,  8,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test( 5,  6,  7,  18'h00000, 18'h00040, 18'h00080);
            run_test(12, 12, 12,  18'h00000, 18'h00100, 18'h00200);
            run_test(12,  4,  8,  18'h00000, 18'h00040, 18'h00080);
        end else if (LANES == 8) begin
            // Keep the parameterization check bounded while still covering
            // one reduction tile and multi-tile M/K dimensions.
            run_test( 8,  8,  8,  18'h00000, 18'h01000, 18'h02000);
            run_test( 8, 16,  8,  18'h00000, 18'h01000, 18'h02000);
            run_test(16,  8,  8,  18'h00000, 18'h01000, 18'h02000);
        end else begin
            run_test( 64,  64,  64,  18'h00000, 18'h10000, 18'h20000);
            run_test( 64, 128,  64,  18'h00000, 18'h10000, 18'h20000);
            run_test(128,  64,  64,  18'h00000, 18'h10000, 18'h20000);
            run_test( 64,  64, 128,  18'h00000, 18'h10000, 18'h20000);
            run_test(128, 128, 128,  18'h00000, 18'h10000, 18'h20000);
            run_test(256, 256, 256,  18'h00000, 18'h10000, 18'h20000);
        end
        $display("==================================================");
        if (errors_total == 0)
            $display("ALL TESTS PASSED  (LANES=%0d)", LANES);
        else
            $display("TOTAL ERRORS: %0d  (LANES=%0d)", errors_total, LANES);
        $display("==================================================");
        $finish;
    end
endmodule
