`timescale 1ns/1ps

// Optional interface mode check.  The paper normally prepares B with
// Algorithm 1 in software; WEIGHTS_PREPERMUTED=0 exercises the equivalent
// local permutation in the staging datapath from an ordinary row-major B.
module tb_dip_raw;
    localparam integer L = 4;
    localparam integer AW = 10;
    localparam integer V = 24;
    reg clk = 0, rst_n = 0, start = 0;
    reg [7:0] M = 4, N = 4, K = 4;
    reg [AW-1:0] base_A = 0, base_B = 64, base_C = 128;
    wire done, err;
    wire [AW-1:0] sram_addr;
    wire sram_we;
    wire [V-1:0] sram_wdata, sram_rdata;
    integer r, c, k, errors, acc;

    always #5 clk = ~clk;

    top_module #(
        .MAT_SIZE_BITS(8), .SRAM_AW(AW), .VAL_SIZE(V), .LANES(L),
        .WEIGHTS_PREPERMUTED(0)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .M(M), .N(N), .K(K),
        .base_addr_in1(base_A), .base_addr_in2(base_B),
        .base_addr_out(base_C), .done(done), .err(err),
        .sram_addr(sram_addr), .sram_we(sram_we),
        .sram_wdata(sram_wdata), .sram_rdata(sram_rdata)
    );

    sram_model #(.DEPTH(1 << AW), .WIDTH(V), .AW(AW)) mem (
        .clk(clk), .we(sram_we), .addr(sram_addr),
        .din(sram_wdata), .dout(sram_rdata)
    );

    initial begin
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
                mem.mem[base_A + r*4 + c] = r*9 + c + 1;
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
                mem.mem[base_B + r*4 + c] = r*5 + c + 2;
        for (r = 0; r < 16; r = r + 1)
            mem.mem[base_C + r] = 0;

        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait (done === 1'b1);

        errors = 0;
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1) begin
                acc = 0;
                for (k = 0; k < 4; k = k + 1)
                    acc = acc + (r*9 + k + 1) * (k*5 + c + 2);
                if ($signed(mem.mem[base_C + r*4 + c]) !== acc) begin
                    $display("MISMATCH C[%0d][%0d] got=%0d exp=%0d", r, c,
                             $signed(mem.mem[base_C + r*4 + c]), acc);
                    errors = errors + 1;
                end
            end

        if (errors == 0 && !err)
            $display("PASS: raw row-major B mode");
        else begin
            $display("FAIL: raw row-major B mode (%0d errors, err=%b)", errors, err);
            $fatal(1);
        end
        $finish;
    end
endmodule
