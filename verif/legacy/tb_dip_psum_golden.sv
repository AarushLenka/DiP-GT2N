`timescale 1ns/1ps
// End-to-end confirmation of the unaccumulated-psum bug mechanism:
//  1) after i=0 drains, check each p_out_3X against per-tile golden row4 dot products
//  2) after i=1 drains, re-check the same p_out_3X (should be unchanged if not accumulated)
//  3) confirm final C mem for C[4..][.] equals p_out_3X (un-accumulated), not C0+C1.
module tb_dip_psum_golden;
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
    wire [23:0] p0 = dut.dtp_inst.systolic_module.p_out_30;
    wire [23:0] p1 = dut.dtp_inst.systolic_module.p_out_31;
    wire [23:0] p2 = dut.dtp_inst.systolic_module.p_out_32;
    wire [23:0] p3 = dut.dtp_inst.systolic_module.p_out_33;
    wire [4:0]  i_cycle_slots; // h_value - 4

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

    // capture p_out_30..33 values at the (i=0, h=11) drain latch vs (i=1, h=11) drain latch
    reg [23:0] p_first_pass [0:3];
    reg [23:0] p_second_pass [0:3];
    reg        seen_first = 0, seen_second = 0;

    always @(posedge clk) begin
        if (i_value == 0 && h_value == 11 && !seen_first) begin
            p_first_pass[0] = p0; p_first_pass[1] = p1;
            p_first_pass[2] = p2; p_first_pass[3] = p3;
            seen_first = 1;
        end
        if (i_value == 1 && h_value == 11 && !seen_second) begin
            p_second_pass[0] = p0; p_second_pass[1] = p1;
            p_second_pass[2] = p2; p_second_pass[3] = p3;
            seen_second = 1;
        end
    end

    function [31:0] tile_golden;
        input integer row, col, tile;
        integer t; reg signed [31:0] acc;
        begin
            acc = 0;
            for (t = 0; t < 4; t = t + 1)
                acc = acc + $signed({24'h0, MA[row*8 + tile*4 + t]})
                          * $signed({24'h0, MB[(tile*4 + t)*4 + col]});
            tile_golden = acc;
        end
    endfunction

    integer errors;
    final begin
        errors = 0;
        // Expected: p_first_pass[i] == tile_golden(4, i, 0) = C0 row for 4th-elem
        //           p_second_pass[i] == tile_golden(4, i, 1) = C1 row for 4th-elem (NOT sum)
        for (i = 0; i < 4; i = i + 1) begin
            if ($signed(p_first_pass[i])  !== $signed(tile_golden(4, i, 0))) begin
                $display("UNEXPECTED: p_first_pass[%0d]=%0d, first-tile golden=%0d", i, $signed(p_first_pass[i]), $signed(tile_golden(4, i, 0)));
                errors = errors + 1;
            end
            if ($signed(p_second_pass[i]) !== $signed(tile_golden(4, i, 1))) begin
                $display("BUG CONFIRMED? p_second_pass[%0d]=%0d, second-tile golden=%0d, full golden=%0d",
                         i, $signed(p_second_pass[i]), $signed(tile_golden(4, i, 1)),
                         $signed(tile_golden(4, i, 0)) + $signed(tile_golden(4, i, 1)));
                errors = errors + 1;
            end
        end
        // final memory check
        for (c = 0; c < 4; c = c + 1)
            if ($signed(dut.bram_inst.mem[320 + 4*4 + c]) !== $signed(tile_golden(4, c, 1))) begin
                $display("final mem C[4][%0d]=%0d differs from second-tile golden=%0d",
                    c, $signed(dut.bram_inst.mem[320 + 4*4 + c]), $signed(tile_golden(4, c, 1)));
                errors = errors + 1;
            end
        if (errors == 0)
            $display("CONFIRMED: systolic produces correct per-tile psums; final C = last-tile psum (no accumulation).");
        else
            $display("ERRORS = %0d", errors);
    end
endmodule
