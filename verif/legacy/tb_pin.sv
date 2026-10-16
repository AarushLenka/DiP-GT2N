`timescale 1ns/1ps
// Pin-level probe of datapath address latch: isolates whether reg_bi1/reg_bi2/reg_bo
// and the h-scanned address mux work as intended after a SETUP + base_cal sequence.
module tb_pin;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg [7:0] M=64,N=64,K=64;
  reg [17:0] b1=0,b2=18'h1000,bo=18'h8000;
  reg M_en=0,N_en=0,K_en=0,bai1_en=0,bai2_en=0,bao_en=0;
  reg [23:0] dout_mem=0;
  reg i_cnt=0,j_cnt=0,h_cnt=0, i_rstn=1,j_rstn=1,h_rstn=1, b_en=0,c_en=0,h_m_en=0;
  reg base_cal=0, ai2_en=0,ai1_en=0,ao_en=0,a_en=0,am_en=0;
  reg load_we=0; reg [6:0] load_pos=0;
  reg wshift=0; reg [63:0] pe=0,ad=0,mu=0;
  reg buf_en=0; reg [1:0] fpo_sel=0, d_en=0;
  reg fout_en=0, dm_en=0, w_phase=0;
  wire err_found; wire [23:0] din_mem; wire [17:0] addr_mem_q;
  wire i_max,j_max,h_max,h_out_point,h_in_point;

  datapath #(.MAT_SIZE_BITS(8),.BRAM_DEPTH(18),.VAL_SIZE(24),.LANES(64)) dp(
    .clk(clk),.rst_n(rst_n),.err_cal(1'b0),.M(M),.N(N),.K(K),
    .base_addr_in1(b1),.base_addr_in2(b2),.base_addr_out(bo),
    .M_en(M_en),.N_en(N_en),.K_en(K_en),.bai1_en(bai1_en),.bai2_en(bai2_en),.bao_en(bao_en),
    .dout_mem(dout_mem),.i_cnt(i_cnt),.j_cnt(j_cnt),.h_cnt(h_cnt),
    .i_rstn(i_rstn),.j_rstn(j_rstn),.h_rstn(h_rstn),.b_en(b_en),.c_en(c_en),.h_m_en(h_m_en),
    .base_cal(base_cal),.ai2_en(ai2_en),.ai1_en(ai1_en),.ao_en(ao_en),.a_en(a_en),.am_en(am_en),
    .load_we(load_we),.load_pos(load_pos),.wshift(wshift),.pe_en(pe),.adder_en(ad),.mul_en(mu),
    .buf_en(buf_en),.fpo_sel(fpo_sel),.d_en(d_en),.fout_en(fout_en),.dm_en(dm_en),.w_phase(w_phase),
    .err_found(err_found),.din_mem(din_mem),.addr_mem_q(addr_mem_q),
    .i_max(i_max),.j_max(j_max),.h_max(h_max),.h_out_point(h_out_point),.h_in_point(h_in_point));

  integer cyc=0;
  always @(posedge clk) cyc=cyc+1;

  task step; begin @(negedge clk); end endtask

  initial begin
    rst_n=0; repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk);
    // replicate SETUP enables (one cycle)
    b_en=1;c_en=1;h_m_en=1;M_en=1;N_en=1;K_en=1;bai1_en=1;bai2_en=1;bao_en=1;
    step;
    b_en=0;c_en=0;h_m_en=0;M_en=0;N_en=0;K_en=0;bai1_en=0;bai2_en=0;bao_en=0;
    $display("after SETUP: b_q=%0d c_q=%0d h_m_q=%0d M_q=%0d N_q=%0d K_q=%0d bi1q=%0d bi2q=%0d boq=%0d",
             dp.b_q, dp.c_q, dp.h_m_q, dp.M_q, dp.N_q, dp.K_q, dp.bi1_q, dp.bi2_q, dp.bo_q);

    // now fire base_cal once like LOAD_TILE state
    base_cal=1; am_en=1; load_pos=0; load_we=1;
    step;
    base_cal=0; am_en=0; load_we=0;
    step;
    step;
    $display("after base_cal: bi1q=%0d (exp 0) bi2q=%0d (exp 4096) boq=%0d (exp 32768) h_m_q=%0d",
             dp.bi1_q, dp.bi2_q, dp.bo_q, dp.h_m_q);
    $display("addr_w(lane0,lp=0)=%0d  addr_i(h0,lp=0)=%0d  addr_mem_q=%0d",
             dp.addr_w, dp.addr_i, dp.addr_mem_q);

    // bump h to 63 like a real scan
    repeat (63) begin h_cnt=1; step; h_cnt=0; step; end
    $display("h=%0d: addr_i(lane0)=%0d (exp 63*64=4032) h_off=%0d", dp.h_value, dp.addr_i, dp.h_off);

    // simulate load_pos carrying {1'b1,63} from a WRITE_TILE then a fresh LOAD_TILE am_en
    load_pos = {1'b1, 6'd63};
    step;
    load_pos = 7'd0;
    load_we=1; am_en=1; base_cal=1;
    step;
    load_we=0; am_en=0; base_cal=0;
    $display("after fake prior WRITE_TILE: addr_mem_q=%0d (exp 4096 = bi2_q... actually weight addr bi2=4096)", dp.addr_mem_q);
    $finish;
  end
endmodule
