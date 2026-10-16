`timescale 1ns/1ps
// ============================================================
// DiP verification testbench — parameterized LANES
//
// Tests:
//   LANES=4  : small tiles, fast simulation, functional validation
//   LANES=64 : single 64x64 tile (smoke test), plus larger configs
//
// Architecture:
//   top_module (parameterized LANES, MAT_SIZE_BITS=8, BRAM_DEPTH=18)
//   blk_mem_gen_0 external BRAM wired via dout_mem_in port
// ============================================================
module tb_dip_256;

    // Override at compile time with -DLANES=4 or -DLANES=64
    `ifndef LANES
      `define LANES 4
    `endif
    localparam LANES         = `LANES;
    localparam MAT_SIZE_BITS = 8;
    localparam BRAM_DEPTH    = 18;
    localparam VAL_SIZE      = 24;

    reg  clk = 0, rst_n = 0, start = 0;
    reg  [MAT_SIZE_BITS-1:0] M, N, K;
    reg  [BRAM_DEPTH-1:0]    base_addr_in1, base_addr_in2, base_addr_out;
    wire done, err;
    wire [VAL_SIZE-1:0]   din_mem_out;
    wire [BRAM_DEPTH-1:0] add_out;
    wire                  w_out;
    wire [VAL_SIZE-1:0]   dout_mem;

    always #5 clk = ~clk;

    top_module #(
        .MAT_SIZE_BITS(MAT_SIZE_BITS), .BRAM_DEPTH(BRAM_DEPTH),
        .VAL_SIZE(VAL_SIZE), .LANES(LANES)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .N(N), .K(K),
        .base_addr_in1(base_addr_in1), .base_addr_in2(base_addr_in2), .base_addr_out(base_addr_out),
        .done(done), .din_mem_out(din_mem_out), .add_out(add_out), .w_out(w_out),
        .err(err), .dout_mem_in(dout_mem)
    );

    blk_mem_gen_0 #(.DEPTH(2**BRAM_DEPTH), .WIDTH(VAL_SIZE), .AW(BRAM_DEPTH)) bram (
        .clka(clk), .wea(w_out), .addra(add_out), .dina(din_mem_out), .douta(dout_mem)
    );

    reg signed [7:0]  A [0:65535];
    reg signed [7:0]  B [0:65535];
    integer errors_total;

    // Estimate cycle budget per test
    function integer timeout_cycles;
        input integer mm, nn, kk;
        integer tiles, cpt;
        begin
            tiles = (mm/LANES) * (nn/LANES) * (kk/LANES);
            cpt   = LANES * 134 + LANES + 20;
            timeout_cycles = tiles * cpt * 2 + 500;
        end
    endfunction

    task run_test;
        input integer mm, nn, kk;
        input integer b1, b2, b3;
        integer r, c, k;
        reg [7:0] elem;
        integer errors, tocy, waited;
        reg signed [31:0] acc;
        reg signed [23:0] got;
        reg timed_out;
        reg [7:0] B_orig [0:65535];  // Original B matrix
        reg [7:0] B_perm [0:65535];  // Permuted B matrix (DiP Algorithm 1)
        begin
            $display("--------------------------------------------------");
            $display("TEST  M=%0d  N=%0d  K=%0d", mm, nn, kk);

            // Load A matrix (no permutation needed)
            for (r = 0; r < mm; r = r + 1)
                for (c = 0; c < nn; c = c + 1) begin
                    elem = (r * 17 + c * 13 + 3) & 8'hFF;
                    A[r*nn + c] = $signed(elem);
                    bram.mem[b1 + r*nn + c][7:0]  = elem;
                    bram.mem[b1 + r*nn + c][23:8] = 0;
                end

            // Load B matrix AND permute per DiP Algorithm 1
            // Original B: B[r][c]
            // Permuted B: B_perm[r][c] = B[(r+c)%nn][c]
            for (r = 0; r < nn; r = r + 1)
                for (c = 0; c < kk; c = c + 1) begin
                    elem = (r * 11 + c * 7 + 5) & 8'hFF;
                    B_orig[r*kk + c] = elem;
                end

            // Apply DiP permutation: shift and rotate each column by its index
            for (c = 0; c < kk; c = c + 1)
                for (r = 0; r < nn; r = r + 1) begin
                    B_perm[r*kk + c] = B_orig[((r + c) % nn)*kk + c];
                end

            // Store permuted weights in BRAM
            for (r = 0; r < nn; r = r + 1)
                for (c = 0; c < kk; c = c + 1) begin
                    elem = B_perm[r*kk + c];
                    B[r*kk + c] = $signed(elem);  // Store permuted for golden calc
                    bram.mem[b2 + r*kk + c][7:0]  = elem;
                    bram.mem[b2 + r*kk + c][23:8] = 0;
                end

            for (r = 0; r < mm*kk; r = r + 1)
                bram.mem[b3 + r] = 24'd0;

            M = mm[MAT_SIZE_BITS-1:0];
            N = nn[MAT_SIZE_BITS-1:0];
            K = kk[MAT_SIZE_BITS-1:0];
            base_addr_in1 = b1[BRAM_DEPTH-1:0];
            base_addr_in2 = b2[BRAM_DEPTH-1:0];
            base_addr_out = b3[BRAM_DEPTH-1:0];

            rst_n = 0; repeat (4) @(negedge clk);
            rst_n = 1; repeat (4) @(negedge clk);
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;

            tocy  = timeout_cycles(mm, nn, kk);
            waited = 0;
            while (!done && waited < tocy) begin
                @(posedge clk);
                waited = waited + 1;
            end

            if (!done) begin
                $display("  TIMEOUT after %0d cycles (budget %0d)", waited, tocy);
                errors_total = errors_total + 1;
                timed_out = 1;
            end else begin
                timed_out = 0;
            end

            if (!timed_out) begin
            @(negedge clk);

            errors = 0;
            for (r = 0; r < mm; r = r + 1)
                for (c = 0; c < kk; c = c + 1) begin
                    acc = 0;
                    for (k = 0; k < nn; k = k + 1)
                        acc = acc + A[r*nn + k] * B[k*kk + c];
                    got = $signed(bram.mem[b3 + r*kk + c]);
                    if (got !== acc[23:0]) begin
                        if (errors < 5)
                            $display("  MISMATCH C[%0d][%0d]: got %0d  expected %0d",
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
        errors_total = 0;

        if (LANES == 4) begin
            run_test(4,  4,  4,  18'h00000, 18'h00040, 18'h00080);
            run_test(8,  4,  4,  18'h00000, 18'h00040, 18'h00080);
            run_test(4,  4,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test(4,  8,  4,  18'h00000, 18'h00040, 18'h00080);
            run_test(8,  8,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test(8,  4,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test(4,  8,  8,  18'h00000, 18'h00040, 18'h00080);
            run_test(12, 12, 12, 18'h00000, 18'h00040, 18'h00080);
            run_test(12, 4,  8,  18'h00000, 18'h00040, 18'h00080);
        end else begin
            // LANES=64 suite
            run_test(64,  64,  64,  18'h00000, 18'h10000, 18'h20000);
            run_test(64,  128, 64,  18'h00000, 18'h10000, 18'h20000);
            run_test(128, 64,  64,  18'h00000, 18'h10000, 18'h20000);
            run_test(64,  64,  128, 18'h00000, 18'h10000, 18'h20000);
            run_test(128, 128, 128, 18'h00000, 18'h10000, 18'h20000);
            run_test(256, 256, 256, 18'h00000, 18'h10000, 18'h20000);
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
