`timescale 1ns/1ps
// Quick debug: trace state, burst_cnt, write_cnt and first output values for M=N=K=4, LANES=4
module tb_quick_debug;
    localparam LANES = 4;
    localparam MAT_SIZE_BITS = 8;
    localparam BRAM_DEPTH    = 18;
    localparam VAL_SIZE      = 24;

    reg clk = 0, rst_n = 0, start = 0;
    reg [MAT_SIZE_BITS-1:0] M, N, K;
    reg [BRAM_DEPTH-1:0] base_addr_in1, base_addr_in2, base_addr_out;
    wire done, err;
    wire [VAL_SIZE-1:0]  din_mem_out;
    wire [BRAM_DEPTH-1:0] add_out;
    wire w_out;
    wire [VAL_SIZE-1:0]  dout_mem;

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

    // A = [[5,6,7,8],[9,10,11,12],[13,14,15,16],[17,18,19,20]]  (signed i8)
    // B = [[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]]
    // C[0][0] = 5*1+6*5+7*9+8*13 = 5+30+63+104 = 202
    // C[0][1] = 5*2+6*6+7*10+8*14 = 10+36+70+112 = 228

    integer i;
    wire [4:0] state = dut.ctrl_inst.state;
    wire [6:0] burst = dut.ctrl_inst.burst_cnt;
    wire [2:0] wcnt  = dut.ctrl_inst.write_cnt;
    wire [7:0] h_val = dut.dtp_inst.h_val8;
    wire       h_max = dut.h_max;
    wire       i_max = dut.i_max;
    wire       j_max = dut.j_max;
    wire [BRAM_DEPTH-1:0] bi2q = dut.dtp_inst.bi2_q;
    wire [BRAM_DEPTH-1:0] bi1q = dut.dtp_inst.bi1_q;

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    reg [4:0] prev_st = 5'hFF;
    always @(posedge clk) begin
        prev_st <= state;
        if (state == 4 || state == 11 || state == 12) // LOAD_TILE=4, WRITE_TILE=11, DRAIN_W=12
            $display("cyc=%3d ST=%2d burst=%2d wcnt=%2d load_we=%b load_pos=%2d w_out=%b addr=%3d bi1q=%3d bi2q=%3d",
                     cyc,state,burst,wcnt,dut.load_we,dut.load_pos,w_out,add_out,bi1q,bi2q);
        else if (state != prev_st)
            $display("cyc=%3d STATE->%2d  burst=%2d wcnt=%2d h=%2d i_max=%b j_max=%b h_max=%b done=%b err=%b",
                     cyc,state,burst,wcnt,h_val,i_max,j_max,h_max,done,err);
        if (w_out)
            $display("cyc=%3d WRITE  addr=%0d  data=%0d", cyc, add_out, $signed(din_mem_out));
    end

    initial begin
        M=4; N=4; K=4;
        base_addr_in1=0; base_addr_in2=18'h00010; base_addr_out=18'h00020;
        // A row-major at 0: rows=[5,6,7,8 | 9,10,11,12 | 13,14,15,16 | 17,18,19,20]
        for (i=0; i<4; i=i+1) begin
            bram.mem[0+i*4+0][7:0] = 5  + i*4; bram.mem[0+i*4+0][23:8] = 0;
            bram.mem[0+i*4+1][7:0] = 6  + i*4; bram.mem[0+i*4+1][23:8] = 0;
            bram.mem[0+i*4+2][7:0] = 7  + i*4; bram.mem[0+i*4+2][23:8] = 0;
            bram.mem[0+i*4+3][7:0] = 8  + i*4; bram.mem[0+i*4+3][23:8] = 0;
        end
        // B row-major at 16: rows=[1,2,3,4 | 5,6,7,8 | 9,10,11,12 | 13,14,15,16]
        for (i=0; i<4; i=i+1) begin
            bram.mem[16+i*4+0][7:0] = 1 + i*4; bram.mem[16+i*4+0][23:8] = 0;
            bram.mem[16+i*4+1][7:0] = 2 + i*4; bram.mem[16+i*4+1][23:8] = 0;
            bram.mem[16+i*4+2][7:0] = 3 + i*4; bram.mem[16+i*4+2][23:8] = 0;
            bram.mem[16+i*4+3][7:0] = 4 + i*4; bram.mem[16+i*4+3][23:8] = 0;
        end
        for (i=0; i<16; i=i+1) bram.mem[32+i] = 0;

        rst_n=0; repeat(4) @(negedge clk);
        rst_n=1; repeat(4) @(negedge clk);
        @(negedge clk); start=1;
        @(negedge clk); start=0;

        wait(done===1'b1 || cyc > 800);
        @(negedge clk);
        $display("--- RESULT ---");
        $display("C[0][0]=%0d (expect 202)", $signed(bram.mem[32]));
        $display("C[0][1]=%0d (expect 228)", $signed(bram.mem[33]));
        $display("C[0][2]=%0d (expect 254)", $signed(bram.mem[34]));
        $display("C[0][3]=%0d (expect 280)", $signed(bram.mem[35]));
        if (cyc > 800) $display("TIMEOUT");
        $finish;
    end
endmodule
