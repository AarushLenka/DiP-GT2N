`timescale 1ns/1ps
// Detailed write-back trace: see every write operation
module tb_writeback_trace;
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
    wire [2:0] wcnt = dut.ctrl_inst.write_cnt;
    wire w_phase = dut.w_ctrl;
    wire [6:0] load_pos = dut.load_pos;
    wire [6:0] load_pos_r = dut.dtp_inst.load_pos_r;
    wire w_phase_r = dut.dtp_inst.w_phase_r;

    // PE outputs
    wire signed [23:0] pe0 = dut.dtp_inst.pe_output[0];
    wire signed [23:0] pe1 = dut.dtp_inst.pe_output[1];
    wire signed [23:0] pe2 = dut.dtp_inst.pe_output[2];
    wire signed [23:0] pe3 = dut.dtp_inst.pe_output[3];

    // Write-back signals
    wire [1:0] write_col_r = dut.dtp_inst.write_col_r;
    wire signed [23:0] pe_col_r = dut.dtp_inst.pe_col_r;
    wire signed [23:0] rsum = dut.dtp_inst.rsum;

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    integer i;
    initial begin
        $display("Write-back detailed trace: M=4 N=4 K=4");
        M=4; N=4; K=4;
        base_addr_in1=0; base_addr_in2=16; base_addr_out=32;

        // Simple data: A = ones, B = identity-ish
        for (i=0; i<16; i=i+1) bram.mem[i][7:0] = 8'd1;
        for (i=0; i<4; i=i+1) begin
            bram.mem[16+i*4+0][7:0] = 8'd1;
            bram.mem[16+i*4+1][7:0] = 8'd2;
            bram.mem[16+i*4+2][7:0] = 8'd3;
            bram.mem[16+i*4+3][7:0] = 8'd4;
        end
        for (i=0; i<16; i=i+1) bram.mem[32+i] = 0;

        rst_n = 0; repeat(4) @(negedge clk);
        rst_n = 1; repeat(4) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        $display("\n=== WRITE_TILE TRACE ===");
        $display("cyc st wcnt w_ph w_ph_r lp lp_r wcol_r w_out addr pe0 pe1 pe2 pe3 pe_col_r dout rsum din");
        fork
            begin
                repeat(400) begin
                    @(posedge clk);
                    #1;
                    if (state >= 10 && state <= 11)  // WRITE_TILE, DRAIN_W
                        $display("%3d %2d  %1d   %b    %b    %2d  %2d   %1d      %b  %4d %4d %4d %4d %4d %6d %6d %6d %6d",
                                 cyc, state, wcnt, w_phase, w_phase_r, load_pos, load_pos_r, write_col_r,
                                 w_out, add_out,
                                 $signed(pe0), $signed(pe1), $signed(pe2), $signed(pe3),
                                 $signed(pe_col_r), $signed(dout_mem), $signed(rsum), $signed(din_mem_out));
                end
            end
            begin
                wait(done == 1);
            end
        join_any
        disable fork;

        @(negedge clk);
        $display("\n=== FINAL RESULTS ===");
        $display("PE outputs at end: pe0=%0d pe1=%0d pe2=%0d pe3=%0d", $signed(pe0), $signed(pe1), $signed(pe2), $signed(pe3));
        for (i=0; i<16; i=i+1)
            $display("C[%0d][%0d] = %0d", i/4, i%4, $signed(bram.mem[32+i]));
        $finish;
    end
endmodule
