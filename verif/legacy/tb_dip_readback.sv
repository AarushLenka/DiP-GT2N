`timescale 1ns/1ps
// Readback-capture trace: every-cycle dump in the window when (i=1, h=5) drains
module tb_dip_readback;
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
    wire [5:0] st       = dut.ctrl_inst.state;
    wire [3:0] pe_en_f     = dut.pe_en;
    wire [3:0] mul_en_f    = dut.mul_en;
    wire [3:0] adder_en_f  = dut.adder_en;
    wire wshift_f = dut.wshift;

    // readback capture chain
    wire        ro_en     = dut.dtp_inst.ro_en;
    wire [23:0] result    = dut.dtp_inst.result;    // ro_reg out
    wire [23:0] result_q  = dut.dtp_inst.result_q;  // buf out
    wire        buf_en_f  = dut.buf_en;
    wire [1:0]  fpo_sel_f = dut.fpo_sel;
    wire [23:0] pe0       = dut.dtp_inst.pe_output[0];
    wire [23:0] pe1       = dut.dtp_inst.pe_output[1];
    wire [23:0] fout      = dut.dtp_inst.fout;
    wire [23:0] fout_q2   = dut.dtp_inst.fout_q;
    wire [23:0] f_res     = dut.dtp_inst.f_result;
    wire [23:0] f_res_q   = dut.dtp_inst.f_result_q;
    wire d_en_f  = dut.d_en;
    wire fout_en_f = dut.fout_en;
    wire dm_en_f  = dut.dm_en;
    wire w_f      = dut.w;
    wire [9:0] addr_out_f = dut.dtp_inst.addr_out_q;
    wire [9:0] addr_mem_f = dut.dtp_inst.addr_mem_q;

    reg [7:0] MA [0:255];
    reg [7:0] MB [0:255];
    integer r, c, k, i;

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

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    // every-cycle dump in the critical window
    always @(posedge clk) begin
        if (cyc >= 345 && cyc <= 380) begin
            $display("cyc=%0d t=%0t h=%0d i=%0d st=%0d | pe=%b mul=%b add=%b wsh=%b | ro_en=%b roen_rslt=%0d bufen=%b bufq=%0d | fpo=%b d_en=%b fouten=%b foutq=%0d | f_res_q=%0d w=%b addrout=%0d addrmem=%0d",
                cyc, $time, h_value, i_value, st,
                pe_en_f, mul_en_f, adder_en_f, wshift_f,
                ro_en, $signed(result), buf_en_f, $signed(result_q),
                fpo_sel_f, d_en_f, fout_en_f, $signed(fout_q2),
                $signed(f_res_q), w_f, addr_out_f, addr_mem_f);
        end
    end

    initial begin #800000; $display("TIMEOUT"); $finish; end
endmodule
