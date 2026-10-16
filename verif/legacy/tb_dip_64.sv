`timescale 1ns/1ps
// 64x64 DiP testbench.
// Memory is modeled in the TB (no hierarchical backdoor access needed),
// behaving like a single-port BRAM: registered read, write on w_out.
module tb_dip_64;
    localparam MAT_SIZE_BITS = 8;
    localparam BRAM_DEPTH    = 18;
    localparam VAL_SIZE      = 24;
    localparam DEPTH         = 262144;

    reg clk = 0, rst_n = 0, start = 0;
    reg  [MAT_SIZE_BITS-1:0] M, N, K;
    reg  [BRAM_DEPTH-1:0] base_addr_in1, base_addr_in2, base_addr_out;
    wire done, err;

    wire [VAL_SIZE-1:0]    din_mem_out;
    wire [BRAM_DEPTH-1:0]  add_out;
    wire                   w_out;
    reg  [VAL_SIZE-1:0]    dout_mem;

    // -------- TB-side memory model --------
    reg [VAL_SIZE-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (w_out)
            mem[add_out] <= din_mem_out;
        dout_mem <= mem[add_out];
    end

    always #5 clk = ~clk;

    top_module dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .N(N), .K(K),
        .base_addr_in1(base_addr_in1), .base_addr_in2(base_addr_in2), .base_addr_out(base_addr_out),
        .done(done), .din_mem_out(din_mem_out), .add_out(add_out), .w_out(w_out),
        .err(err)
    );

    reg [7:0] MA [0:4095];
    reg [7:0] MB [0:8191];
    integer r, c, k, i;

    task load_and_run;
        input integer mm, nn, kk;
        input integer b1, b2, b3;
        reg [7:0] elem;
        integer errors, val, cellsA, cellsB, cellsC;
        reg signed [31:0] acc;
        begin
            M = mm[7:0]; N = nn[7:0]; K = kk[7:0];
            base_addr_in1 = b1; base_addr_in2 = b2; base_addr_out = b3;

            cellsA = mm * nn; cellsB = nn * kk; cellsC = mm * kk;
            for (r = 0; r < mm; r = r + 1)
                for (c = 0; c < nn; c = c + 1) begin
                    elem = (r*7 + c*11 + 3) % 250; // < 128: signed-safe
                    MA[r*nn + c] = elem;
                    mem[b1 + r*nn + c] = 24'd0 | elem;
                end
            for (r = 0; r < nn; r = r + 1)
                for (c = 0; c < kk; c = c + 1) begin
                    elem = (r*13 + c*5 + 9) % 250;
                    MB[r*kk + c] = elem;
                    mem[b2 + r*kk + c] = 24'd0 | elem;
                end
            for (i = 0; i < cellsC; i = i + 1)
                mem[b3 + i] = 24'd0;

            rst_n = 0; repeat (3) @(negedge clk);
            rst_n = 1; repeat (3) @(negedge clk);
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
            fork
                begin : wait_done
                    wait (done === 1'b1);
                end
                begin : watchdog
                    #40000000;
                    $display("WATCHDOG TIMEOUT (cfg %0dx%0dx%0d)", mm, nn, kk);
                    $finish;
                end
            join_any
            disable fork;
            @(negedge clk);

            errors = 0;
            for (r = 0; r < mm; r = r + 1)
                for (c = 0; c < kk; c = c + 1) begin
                    val = $signed(mem[b3 + r*kk + c]);
                    acc = 0;
                    for (k = 0; k < nn; k = k + 1)
                        acc = acc + $signed(MA[r*nn + k]) * $signed(MB[k*kk + c]);
                    if (val !== acc) begin
                        if (errors < 5)
                            $display("cfg MxNxK=%0dx%0dx%0d MISMATCH C[%0d][%0d] = %0d, golden = %0d",
                                     mm, nn, kk, r, c, val, acc);
                        errors = errors + 1;
                    end
                end
            if (errors == 0) $display("cfg MxNxK=%0dx%0dx%0d : PASS (%0d outputs)", mm, nn, kk, mm*kk);
            else             $display("cfg MxNxK=%0dx%0dx%0d : FAIL (%0d mismatches)", mm, nn, kk, errors);
        end
    endtask

    initial begin
        load_and_run(64, 64, 64,  0, 4096, 32768);
        load_and_run(128, 64, 64, 0, 4096, 32768);
        $finish;
    end

    initial begin #200000000; $display("TIMEOUT2"); $finish; end
endmodule
