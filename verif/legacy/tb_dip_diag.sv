`timescale 1ns/1ps
// Diagnostic testbench: 64x64 single-tile, print FSM state every 10 cycles
module tb_dip_diag;
    localparam MAT_SIZE_BITS = 8;
    localparam BRAM_DEPTH    = 18;
    localparam VAL_SIZE      = 24;
    localparam LANES         = 64;

    reg  clk = 0, rst_n = 0, start = 0;
    reg  [MAT_SIZE_BITS-1:0] M = 8'd64, N = 8'd64, K = 8'd64;
    reg  [BRAM_DEPTH-1:0] base_addr_in1 = 0, base_addr_in2 = 18'h10000, base_addr_out = 18'h20000;
    wire done, err;
    wire [VAL_SIZE-1:0]   din_mem_out;
    wire [BRAM_DEPTH-1:0] add_out;
    wire                  w_out;
    wire [VAL_SIZE-1:0]   dout_mem;

    always #5 clk = ~clk;

    top_module #(.MAT_SIZE_BITS(MAT_SIZE_BITS),.BRAM_DEPTH(BRAM_DEPTH),.VAL_SIZE(VAL_SIZE),.LANES(LANES)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .N(N), .K(K),
        .base_addr_in1(base_addr_in1), .base_addr_in2(base_addr_in2), .base_addr_out(base_addr_out),
        .done(done), .din_mem_out(din_mem_out), .add_out(add_out), .w_out(w_out),
        .err(err), .dout_mem_in(dout_mem)
    );

    blk_mem_gen_0 #(.DEPTH(2**BRAM_DEPTH), .WIDTH(VAL_SIZE), .AW(BRAM_DEPTH)) bram (
        .clka(clk), .wea(w_out), .addra(add_out), .dina(din_mem_out), .douta(dout_mem)
    );

    integer cycle_count;
    initial begin
        rst_n = 0; repeat(4) @(negedge clk);
        rst_n = 1; repeat(4) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        cycle_count = 0;
        repeat (20000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            if (cycle_count % 2000 == 0)
                $display("cy=%5d  %-16s h=%3d h_max=%b",
                    cycle_count, dut.ctrl_inst.state.name(),
                    dut.dtp_inst.counter_h.out_tmp, dut.h_max);
            if (done) begin
                $display("DONE at cycle %0d", cycle_count);
                $finish;
            end
        end
        $display("NOT DONE after %0d cycles", cycle_count);
        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
