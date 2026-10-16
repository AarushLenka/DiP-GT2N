`timescale 1ns/1ps
// Trace input propagation through systolic array
module tb_input_trace;
    localparam LANES = 4;
    localparam MAT_SIZE_BITS = 8;
    localparam BRAM_DEPTH = 18;
    localparam VAL_SIZE = 24;

    reg clk = 0, rst_n = 0, start = 0;
    reg [MAT_SIZE_BITS-1:0] M, N, K;
    reg [BRAM_DEPTH-1:0] base_addr_in1, base_addr_in2, base_addr_out;
    wire done, err;
    wire [VAL_SIZE-1:0]  din_mem_out;
    wire [BRAM_DEPTH-1:0] add_out;
    wire w_out;
    wire [VAL_SIZE-1:0] dout_mem;

    always #5 clk = ~clk;

    top_module #(.MAT_SIZE_BITS(MAT_SIZE_BITS),.BRAM_DEPTH(BRAM_DEPTH),.VAL_SIZE(VAL_SIZE),.LANES(LANES)) dut (
        .clk(clk),.rst_n(rst_n),.start(start),
        .M(M),.N(N),.K(K),
        .base_addr_in1(base_addr_in1),.base_addr_in2(base_addr_in2),.base_addr_out(base_addr_out),
        .done(done),.din_mem_out(din_mem_out),.add_out(add_out),.w_out(w_out),
        .err(err),.dout_mem_in(dout_mem)
    );

    blk_mem_gen_0 #(.DEPTH(2**BRAM_DEPTH),.WIDTH(VAL_SIZE),.AW(BRAM_DEPTH)) bram (
        .clka(clk),.wea(w_out),.addra(add_out),.dina(din_mem_out),.douta(dout_mem)
    );

    // Probe internal signals
    wire [4:0] state = dut.ctrl_inst.state;
    wire [3:0] pe_en = dut.pe_en;
    wire [3:0] mul_en = dut.mul_en;
    wire [3:0] adder_en = dut.adder_en;
    wire [1:0] h_val = dut.dtp_inst.h_val8;
    wire wshift = dut.wshift;

    // Input lane registers (what was loaded from BRAM)
    wire signed [7:0] in_lane0 = dut.dtp_inst.in_lane[0];
    wire signed [7:0] in_lane1 = dut.dtp_inst.in_lane[1];
    wire signed [7:0] in_lane2 = dut.dtp_inst.in_lane[2];
    wire signed [7:0] in_lane3 = dut.dtp_inst.in_lane[3];

    // Weight lane registers
    wire signed [7:0] w_lane0 = dut.dtp_inst.weight_lane[0];
    wire signed [7:0] w_lane1 = dut.dtp_inst.weight_lane[1];
    wire signed [7:0] w_lane2 = dut.dtp_inst.weight_lane[2];
    wire signed [7:0] w_lane3 = dut.dtp_inst.weight_lane[3];

    // Systolic array row 0 i_reg (PE input registers after pe_en)
    wire signed [7:0] i00 = dut.dtp_inst.systolic_module.i_reg[0][0];
    wire signed [7:0] i01 = dut.dtp_inst.systolic_module.i_reg[0][1];
    wire signed [7:0] i02 = dut.dtp_inst.systolic_module.i_reg[0][2];
    wire signed [7:0] i03 = dut.dtp_inst.systolic_module.i_reg[0][3];

    // Row 3 for comparison
    wire signed [7:0] i30 = dut.dtp_inst.systolic_module.i_reg[3][0];
    wire signed [7:0] w30 = dut.dtp_inst.systolic_module.w_reg[3][0];
    wire signed [23:0] p30 = dut.dtp_inst.systolic_module.p_out[3][0];

    // All row 3 outputs
    wire signed [23:0] p30_all [0:3];
    assign p30_all[0] = dut.dtp_inst.systolic_module.p_out[3][0];
    assign p30_all[1] = dut.dtp_inst.systolic_module.p_out[3][1];
    assign p30_all[2] = dut.dtp_inst.systolic_module.p_out[3][2];
    assign p30_all[3] = dut.dtp_inst.systolic_module.p_out[3][3];

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    integer i;
    initial begin
        $display("Input propagation trace: M=4 N=4 K=4");
        M=4; N=4; K=4;
        base_addr_in1=0; base_addr_in2=16; base_addr_out=32;

        // Matrix A = [[1,2,3,4], [5,6,7,8], [9,10,11,12], [13,14,15,16]]
        for (i=0; i<16; i=i+1) bram.mem[i][7:0] = i + 1;
        // Matrix B = [[1,0,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1]]  (identity)
        for (i=0; i<16; i=i+1) bram.mem[16+i][7:0] = (i%5 == 0) ? 1 : 0;
        for (i=0; i<16; i=i+1) bram.mem[32+i] = 0;

        rst_n = 0; repeat(4) @(negedge clk);
        rst_n = 1; repeat(4) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        $display("\n=== COMPUTE TRACE ===");
        $display("cyc st h pe mul add wsh | in_lanes    | w_lanes     | i_row0      | i30 w30 p30   | p_row3");
        fork
            begin
                repeat(200) begin
                    @(posedge clk);
                    #1;
                    if (state >= 5 && state <= 9)  // LATCH_W through INC_H
                        $display("%3d %2d %d  %b  %b  %b  %b | %2d %2d %2d %2d | %2d %2d %2d %2d | %2d %2d %2d %2d | %2d %2d %5d | %5d %5d %5d %5d",
                                 cyc, state, h_val, pe_en, mul_en, adder_en, wshift,
                                 $signed(in_lane0), $signed(in_lane1), $signed(in_lane2), $signed(in_lane3),
                                 $signed(w_lane0), $signed(w_lane1), $signed(w_lane2), $signed(w_lane3),
                                 $signed(i00), $signed(i01), $signed(i02), $signed(i03),
                                 $signed(i30), $signed(w30), $signed(p30),
                                 $signed(p30_all[0]), $signed(p30_all[1]), $signed(p30_all[2]), $signed(p30_all[3]));
                end
            end
            begin
                wait(done == 1);
            end
        join_any
        disable fork;

        @(negedge clk);
        $display("\n=== FINAL RESULTS ===");
        for (i=0; i<16; i=i+1)
            $display("C[%0d][%0d] = %0d", i/4, i%4, $signed(bram.mem[32+i]));
        $finish;
    end
endmodule
