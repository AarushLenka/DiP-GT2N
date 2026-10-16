`timescale 1ns/1ps
// FSM debug: trace state transitions for the first few microseconds
module tb_dbg_fsm;
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

    reg [VAL_SIZE-1:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (w_out) mem[add_out] <= din_mem_out;
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

    wire [4:0]  state      = dut.ctrl_inst.state;
    wire [6:0]  burst_cnt  = dut.ctrl_inst.burst_cnt;
    wire        load_we    = dut.load_we;
    wire        am_en      = dut.am_en;
    wire        base_cal   = dut.base_cal;
    wire        err_found  = dut.err_found;
    wire        err_cal    = dut.err_cal;
    wire [7:0]  i_v        = dut.dtp_inst.i_value;
    wire [7:0]  j_v        = dut.dtp_inst.j_value;
    wire [7:0]  h_v        = dut.dtp_inst.h_value[7:0];
    wire [7:0]  b_q        = dut.dtp_inst.b_q;
    wire [17:0] boq        = dut.dtp_inst.bo_q;
    wire [8:0]  orow       = dut.dtp_inst.out_row;
    wire [23:0] pcol0      = dut.dtp_inst.pe_output[0];
    // probe the LAST-row PE (63,0) internals: weight/input regs and psum source
    wire [7:0]  w63        = dut.dtp_inst.systolic_module.ROW[63].COL[0].pe_inst.w_reg;
    wire [7:0]  i63        = dut.dtp_inst.systolic_module.ROW[63].COL[0].pe_inst.i_reg;
    wire [15:0] m63        = dut.dtp_inst.systolic_module.ROW[63].COL[0].pe_inst.mul_reg;
    wire [7:0]  wprev      = dut.dtp_inst.systolic_module.ROW[62].COL[0].pe_inst.w_reg;
    wire [23:0] psum63     = dut.dtp_inst.systolic_module.psum_in[63];
    wire [7:0]  i63src     = dut.dtp_inst.systolic_module.ROW[62].COL[63].pe_inst.i_reg;
    wire [23:0] fq         = dut.dtp_inst.fout_q;
    wire [23:0] frq        = dut.dtp_inst.f_result_q;
    wire [7:0]  c_q        = dut.dtp_inst.c_q;
    wire [8:0]  h_m_q      = dut.dtp_inst.h_m_q;
    wire        h_max      = dut.h_max;
    wire        i_max      = dut.i_max;

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    integer i, r, c, k;
    initial begin
        M = 64; N = 64; K = 64;
        base_addr_in1 = 0; base_addr_in2 = 18'h1000; base_addr_out = 18'h8000;
        // preload small known data: A[i][j] = 1, B[j][k] = 2 => C = 128
        for (i = 0; i < 64*64; i = i + 1) begin
            mem[i]             = 24'd1;
            mem[18'h1000 + i]  = 24'd2;
            mem[18'h8000 + i]  = 24'd0;
        end
        rst_n = 0; repeat (3) @(negedge clk);
        rst_n = 1; repeat (3) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
    end

    // trace: log every state change + every cycle in COMPUTE/WRITE_TIE states
    reg [4:0] st_prev = 5'hFF;
    always @(posedge clk) begin
        st_prev <= state;
        if (state != st_prev || state >= 5'd5)
            $display("cyc=%0d st=%0d burst=%0d load_we=%b w=%b h=%0d addr=%0d din=%0d pcol0=%0d | w63=%0d i63=%0d i63src=%0d",
                     cyc, state, burst_cnt, load_we, w_out,
                     h_v, add_out, din_mem_out, $signed(pcol0),
                     $signed(w63), $signed(i63), $signed(i63src));
    end

    integer errors;
    reg signed [31:0] acc;
    always @(posedge clk) begin
        if (state == 5'd16 && cyc > 30) begin
            errors = 0;
            for (r = 0; r < 64; r = r + 1)
                for (c = 0; c < 64; c = c + 1) begin
                    acc = 0;
                    for (k = 0; k < 64; k = k + 1)
                        acc = acc + $signed(mem[r*64 + k]) * $signed(mem[18'h1000 + k*64 + c]);
                    if ($signed(mem[18'h8000 + r*64 + c]) !== acc) begin
                        if (errors < 5)
                            $display("DBG MISMATCH C[%0d][%0d]=%0d golden=%0d (acc=%0d)", r, c, $signed(mem[18'h8000 + r*64 + c]), acc, acc);
                        errors = errors + 1;
                    end
                end
            $display("DBG: DONE seen. errors=%0d", errors);
            $finish;
        end
    end

    initial begin #3000000; $display("TIMEOUT_DBG"); $finish; end
endmodule
