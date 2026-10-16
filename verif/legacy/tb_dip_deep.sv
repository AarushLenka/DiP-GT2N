`timescale 1ns/1ps
// Deep-trace testbench for M=8 N=8 K=4
module tb_dip_deep;
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

    wire [4:0] h_value  = dut.dtp_inst.counter_h.value;
    wire [1:0] i_value  = dut.dtp_inst.i_value;
    wire [1:0] j_value  = dut.dtp_inst.j_value;
    wire [3:0] pe_en_fast = dut.pe_en;
    wire [3:0] mul_en_fast= dut.mul_en;
    wire [3:0] adder_en_fast = dut.adder_en;
    wire wshift_fast = dut.wshift;
    wire done_cnt = dut.fout_en; // fout_en = d_en marker of whether we're in drain mode

    wire [23:0] p0 = dut.dtp_inst.systolic_module.p_out_00;
    wire [23:0] p1 = dut.dtp_inst.systolic_module.p_out_10;
    wire [23:0] p2 = dut.dtp_inst.systolic_module.p_out_20;
    wire [23:0] p3 = dut.dtp_inst.systolic_module.p_out_30;
    wire [7:0]  i0 = dut.dtp_inst.systolic_module.i_out_00;
    wire [7:0]  i1 = dut.dtp_inst.systolic_module.i_out_10;
    wire [7:0]  i2 = dut.dtp_inst.systolic_module.i_out_20;
    wire [7:0]  i3 = dut.dtp_inst.systolic_module.i_out_30;
    wire [7:0]  w0 = dut.dtp_inst.systolic_module.w_out_00;
    wire [7:0]  w1 = dut.dtp_inst.systolic_module.w_out_10;
    wire [7:0]  w2 = dut.dtp_inst.systolic_module.w_out_20;
    wire [7:0]  w3 = dut.dtp_inst.systolic_module.w_out_30;
    wire [23:0] fo = dut.dtp_inst.fout;
    wire [23:0] fout_q = dut.dtp_inst.fout_q;
    wire [23:0] res_q = dut.dtp_inst.result_q;
    wire [23:0] fres = dut.dtp_inst.f_result_q;

    reg [7:0] MA [0:255];
    reg [7:0] MB [0:255];
    integer r, c, k, i, target = 0;

    initial begin
        M = 8; N = 8; K = 4;
        base_addr_in1 = 10'd0; base_addr_in2 = 10'd64; base_addr_out = 10'd320;

        for (r = 0; r < 8; r = r + 1)
            for (c = 0; c < 8; c = c + 1) begin
                MA[r*8 + c] = (r*13 + c*7 + 5) % 251;
                dut.bram_inst.mem[r*8 + c][7:0] = MA[r*8 + c];
            end
        for (r = 0; r < 8; r = r + 1)
            for (c = 0; c < 4; c = c + 1) begin
                MB[r*4 + c] = (r*5 + c*11 + 3) % 251;
                dut.bram_inst.mem[64 + r*4 + c][7:0] = MB[r*4 + c];
            end
        for (i = 0; i < 32; i = i + 1)
            dut.bram_inst.mem[320 + i] = 24'd0;

        rst_n = 0; repeat (3) @(negedge clk);
        rst_n = 1; repeat (3) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait (done === 1'b1);
        @(negedge clk);
        $finish;
    end

    // trace section: log every cycle once the systolic pipeline enters total drain
    // detect "drain" = (pe_en == 4'b0000 && fout_en == 1)
    always @(posedge clk) begin
        if ($time > 2000) begin
            // print only if any of the drain-relevant signals change to non-default
            if (adder_en_fast === 4'b1111 || pe_en_fast === 4'b1111 || mul_en_fast === 4'b1111 ||
                w_out === 1'b1) begin
                $display("t=%0t h=%0d i=%0d j=%0d | pe_en=%b mul_en=%b adder_en=%b wshift=%b w_out=%b | A0,A1,A2,A3=%h,%h,%h,%h (i0..3=%0d,%0d,%0d,%0d) (w0..3=%0d,%0d,%0d,%0d)",
                    $time, h_value, i_value, j_value, pe_en_fast, mul_en_fast, adder_en_fast, wshift_fast, w_out,
                    p0, p1, p2, p3, i0, i1, i2, i3, w0, w1, w2, w3);
            end
        end
    end

    initial begin #800000; $display("TIMEOUT"); $finish; end
endmodule
