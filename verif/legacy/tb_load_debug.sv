`timescale 1ns/1ps
// Debug LOAD_TILE phase to see lane loading
module tb_load_debug;
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

    // Probe load signals
    wire [4:0] state = dut.ctrl_inst.state;
    wire load_we = dut.load_we;
    wire [6:0] load_pos = dut.load_pos;
    wire [6:0] load_pos_r1 = dut.dtp_inst.load_pos_r1;
    wire load_we_r = dut.dtp_inst.load_we_r;
    wire is_input_phase_r = dut.dtp_inst.is_input_phase_r;
    wire [2:0] lane_idx_r = dut.dtp_inst.lane_idx_r;
    wire [7:0] data_in_burst = dut.dtp_inst.data_in_burst;

    // Lane hit signals
    wire w_hit0 = dut.dtp_inst.LANE_FANOUT[0].w_hit;
    wire w_hit1 = dut.dtp_inst.LANE_FANOUT[1].w_hit;
    wire i_hit0 = dut.dtp_inst.LANE_FANOUT[0].i_hit;
    wire i_hit1 = dut.dtp_inst.LANE_FANOUT[1].i_hit;
    wire i_hit2 = dut.dtp_inst.LANE_FANOUT[2].i_hit;
    wire i_hit3 = dut.dtp_inst.LANE_FANOUT[3].i_hit;

    // Lane outputs
    wire signed [7:0] in_lane0 = dut.dtp_inst.in_lane[0];
    wire signed [7:0] in_lane1 = dut.dtp_inst.in_lane[1];
    wire signed [7:0] in_lane2 = dut.dtp_inst.in_lane[2];
    wire signed [7:0] in_lane3 = dut.dtp_inst.in_lane[3];

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    integer i;
    initial begin
        $display("LOAD_TILE debug trace: M=4 N=4 K=4");
        M=4; N=4; K=4;
        base_addr_in1=0; base_addr_in2=16; base_addr_out=32;

        // Matrix A values 1-16
        for (i=0; i<16; i=i+1) bram.mem[i][7:0] = i + 1;
        // Matrix B = identity
        for (i=0; i<16; i=i+1) bram.mem[16+i][7:0] = (i%5 == 0) ? 1 : 0;
        for (i=0; i<16; i=i+1) bram.mem[32+i] = 0;

        rst_n = 0; repeat(4) @(negedge clk);
        rst_n = 1; repeat(4) @(negedge clk);
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;

        $display("\n=== FIRST LOAD_TILE ===");
        $display("cyc st lwe lp lp_r1 lwe_r inp_ph lane_idx data i_hits       | in_lanes");
        fork
            begin
                repeat(100) begin
                    @(posedge clk);
                    #1;
                    if (state == 4 || state == 5)  // LOAD_TILE, LATCH_W
                        $display("%3d %2d  %b  %2d   %2d    %b     %b      %1d      %3d  %b%b%b%b | %3d %3d %3d %3d",
                                 cyc, state, load_we, load_pos, load_pos_r1, load_we_r, is_input_phase_r, lane_idx_r,
                                 data_in_burst,
                                 i_hit0, i_hit1, i_hit2, i_hit3,
                                 $signed(in_lane0), $signed(in_lane1), $signed(in_lane2), $signed(in_lane3));
                end
            end
            begin
                wait(state == 6);  // Wait until COMPUTE_PE
            end
        join_any
        disable fork;

        $display("\n=== AFTER FIRST h-iteration ===");
        $display("in_lanes: %0d %0d %0d %0d", $signed(in_lane0), $signed(in_lane1), $signed(in_lane2), $signed(in_lane3));

        $finish;
    end
endmodule
