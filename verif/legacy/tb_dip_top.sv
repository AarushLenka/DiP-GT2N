`timescale 1ns/1ps
// Testbench: drive top_module with a fixed matrix multiply workload
// (M=4, N=4, K=4 tiles => the only legal config for error_check with 4-bit dims)
// and compare against a golden CPU reference computed in the TB.

module tb_dip_top;
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

    always #5 clk = ~clk; // 100 MHz

    // seed values written into "memory" by TB before run (references for golden model)
    reg [7:0] matrixA [0:15]; // A: M x N, row-major, base 0
    reg [7:0] matrixB [0:15]; // B: N x K, row-major, base 16 (per datapath addr calc? TBD)
    reg [VAL_SIZE-1:0] out_readback [0:15];

    wire [VAL_SIZE-1:0] dout_mem;

    top_module dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .N(N), .K(K),
        .base_addr_in1(base_addr_in1), .base_addr_in2(base_addr_in2), .base_addr_out(base_addr_out),
        .done(done), .din_mem_out(din_mem_out), .add_out(add_out), .w_out(w_out),
        .err(err)
    );

    // TB-side BRAM (replaces the Xilinx blk_mem_gen_0 from the original netlist)
    blk_mem_gen_0 #(.DEPTH(1024), .WIDTH(VAL_SIZE)) bram (
        .clka(clk), .wea(w_out),
        .addra(add_out), .dina(din_mem_out), .douta(dout_mem)
    );

    // preload memory
    integer row, col;
    initial begin
        for (row = 0; row < 4; row = row + 1) begin
            for (col = 0; col < 4; col = col + 1) begin
                matrixA[row*4+col] = row*4 + col + 1;        // A[row][col]
                matrixB[row*4+col] = ((row*4+col + 2) % 9); // B[row][col]
            end
        end
    end

    // preload helper task: push A word-by-word into 24-bit memory image
    // NOTE: layout in the BRAM depends on datapath addressing. Initialized here
    // assuming each 24-bit "element" cell is indexed exactly as the datapath
    // computes addr_in1 with a stride of 4 (bi1 = base + i*<<2).
    reg [23:0] memimage [0:1023];
    integer idx;
    initial begin
        for (idx = 0; idx < 1024; idx = idx + 1) memimage[idx] = 24'd0;
        // A: base_addr_in1 = 0, each element is a 24-bit word with lower 8 bits = value
        for (row = 0; row < 4; row = row + 1) begin
            for (col = 0; col < 4; col = col + 1) begin
                // datapath computes addr_in1 = bi1_q + N_q*h_value + bi1_o_sel
                // with bi1 = base + i*<<2  => "i" is in the tile-index space, stride 4
                // so a 4x4 A tile is addressed as a 4x4 word grid of row stride N=4
                // A[row][col], h (inner loop) iterates over N, bi1_o_sel over sub-index
                // col group of 4 -> index = row*N + col
                memimage[row*4 + col][7:0] = matrixA[row*4 + col];
            end
        end
        // B: base_addr_in2 = 64; bi2 uses K_q*i_value*4 + j_value*4.
        // Layout TBD, initialize as row-major for now.
        for (row = 0; row < 4; row = row + 1) begin
            for (col = 0; col < 4; col = col + 1) begin
                memimage[64 + row*4 + col][7:0] = matrixB[row*4 + col];
            end
        end
    end

    // re-load the RTL BRAM instance from memimage at start of sim, interleaved accesses
    // (write before start, read by DUT)
    task load_bram;
        integer i;
        begin
            // We have to write into the live bram hierarchy from the TB.
            for (i = 0; i < 1024; i = i + 1)
                dut.bram_inst.mem[i] = memimage[i];
        end
    endtask

    // run one multiply
    task run_matmul;
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
            wait (done === 1'b1);
            @(negedge clk);
        end
    endtask

    integer errors = 0;
    reg [VAL_SIZE-1:0] golden [0:15];

    initial begin
        rst_n = 0;
        M = 4; N = 4; K = 4;
        base_addr_in1  = 10'd0;
        base_addr_in2  = 10'd64;
        base_addr_out  = 10'd128;
        repeat (5) @(negedge clk);
        load_bram;
        rst_n = 1;
        repeat (5) @(negedge clk);
        run_matmul;

        // compute golden
        for (row = 0; row < 4; row = row + 1) begin
            for (col = 0; col < 4; col = col + 1) begin
                golden[row*4+col] = 0;
                for (idx = 0; idx < 4; idx = idx + 1)
                    golden[row*4+col] = golden[row*4+col] + matrixA[row*4+idx] * matrixB[idx*4+col];
            end
        end

        // verify BRAM out region
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                if (dut.bram_inst.mem[128 + row*4 + col] !== golden[row*4+col]) begin
                    $display("MISMATCH out[%0d][%0d] = %0d, golden = %0d",
                        row, col, $signed(dut.bram_inst.mem[128 + row*4 + col]), $signed(golden[row*4+col]));
                    errors = errors + 1;
                end

        if (errors == 0)
            $display("ALL 16 OUTPUTS MATCH GOLDEN");
        else
            $display("TOTAL MISMATCHES = %0d", errors);
        $finish;
    end

    // timeout
    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
