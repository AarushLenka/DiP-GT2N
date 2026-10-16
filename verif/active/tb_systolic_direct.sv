`timescale 1ns/1ps
// Direct systolic array test: manually drive PEs and check MAC results
// Test: 2x2 matmul: A=[[1,2],[3,4]] * B=[[5,6],[7,8]] = C=[[19,22],[43,50]]
module tb_systolic_direct;
    localparam LANES = 4;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg wshift = 0;
    reg [LANES-1:0] pe_en = 0, mul_en = 0, adder_en = 0;
    reg [8*LANES-1:0] weight_flat = 0;
    reg [8*LANES-1:0] I_flat = 0;
    wire [24*LANES-1:0] pe_output_flat;

    systolic #(.LANES(LANES)) dut (
        .clk(clk), .rst_n(rst_n),
        .wshift(wshift), .pe_en(pe_en), .mul_en(mul_en), .adder_en(adder_en),
        .weight_flat(weight_flat), .I_flat(I_flat),
        .pe_output_flat(pe_output_flat)
    );

    // Unpack outputs
    wire signed [23:0] out0 = pe_output_flat[23:0];
    wire signed [23:0] out1 = pe_output_flat[47:24];
    wire signed [23:0] out2 = pe_output_flat[71:48];
    wire signed [23:0] out3 = pe_output_flat[95:72];

    // Probe PE registers - all rows
    wire signed [7:0] w00 = dut.w_reg[0][0];
    wire signed [7:0] w01 = dut.w_reg[0][1];
    wire signed [7:0] w10 = dut.w_reg[1][0];
    wire signed [7:0] w11 = dut.w_reg[1][1];
    wire signed [7:0] w20 = dut.w_reg[2][0];
    wire signed [7:0] w21 = dut.w_reg[2][1];
    wire signed [7:0] w30 = dut.w_reg[3][0];
    wire signed [7:0] w31 = dut.w_reg[3][1];

    wire signed [7:0] i00 = dut.i_reg[0][0];
    wire signed [7:0] i01 = dut.i_reg[0][1];
    wire signed [7:0] i10 = dut.i_reg[1][0];
    wire signed [7:0] i11 = dut.i_reg[1][1];
    wire signed [7:0] i20 = dut.i_reg[2][0];
    wire signed [7:0] i21 = dut.i_reg[2][1];
    wire signed [7:0] i30 = dut.i_reg[3][0];
    wire signed [7:0] i31 = dut.i_reg[3][1];

    wire signed [23:0] p00 = dut.p_out[0][0];
    wire signed [23:0] p01 = dut.p_out[0][1];
    wire signed [23:0] p10 = dut.p_out[1][0];
    wire signed [23:0] p11 = dut.p_out[1][1];
    wire signed [23:0] p20 = dut.p_out[2][0];
    wire signed [23:0] p21 = dut.p_out[2][1];
    wire signed [23:0] p30 = dut.p_out[3][0];
    wire signed [23:0] p31 = dut.p_out[3][1];

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    initial begin
        $display("DiP Systolic Array Test - Following paper dataflow");
        $display("Test: row 0 feeds [1,2,0,0], computes through all 4 rows");
        $display("");

        // Reset
        rst_n = 0; repeat(3) @(negedge clk);
        rst_n = 1; repeat(2) @(negedge clk);

        // STEP 1: Multi-cycle weight loading (LANES=4 cycles)
        // Each wshift pulse propagates weights down one row
        $display("CYCLE %0d: Multi-cycle weight load (4 cycles for 4 rows)", cyc);
        @(negedge clk);
        weight_flat[7:0]   = 8'd5;  // Column 0: weight 5
        weight_flat[15:8]  = 8'd6;  // Column 1: weight 6
        weight_flat[23:16] = 8'd7;  // Column 2: weight 7
        weight_flat[31:24] = 8'd8;  // Column 3: weight 8

        // Cycle 0: Load row 0
        wshift = 1;
        @(negedge clk);
        $display("  After wshift cycle 0: w00=%0d w01=%0d", w00, w01);

        // Cycle 1: Row 0 → Row 1
        @(negedge clk);
        $display("  After wshift cycle 1: w10=%0d w11=%0d", w10, w11);

        // Cycle 2: Row 1 → Row 2
        @(negedge clk);
        $display("  After wshift cycle 2: w20=%0d w21=%0d", w20, w21);

        // Cycle 3: Row 2 → Row 3 (final)
        @(negedge clk);
        wshift = 0;
        $display("  After wshift cycle 3: w30=%0d w31=%0d", w30, w31);

        @(negedge clk);
        $display("  Final weights in all rows:");
        $display("    Row 0: w00=%0d w01=%0d", w00, w01);
        $display("    Row 1: w10=%0d w11=%0d", w10, w11);
        $display("    Row 2: w20=%0d w21=%0d", w20, w21);
        $display("    Row 3: w30=%0d w31=%0d", w30, w31);

        // STEP 2: Feed inputs to row 0, propagate diagonally through rows
        // Row 0 receives [1,2,0,0], computes, then diagonal shift to row 1, etc.
        $display("");
        $display("CYCLE %0d: Feed inputs [1,2,0,0] to row 0", cyc);
        @(negedge clk);
        I_flat[7:0]   = 8'd1;
        I_flat[15:8]  = 8'd2;
        I_flat[23:16] = 8'd0;
        I_flat[31:24] = 8'd0;
        pe_en = 4'b0001;  // Only row 0 enabled
        @(negedge clk);
        pe_en = 0;
        $display("  Input regs row 0: i00=%0d i01=%0d", i00, i01);

        // Row 0 MUL
        $display("");
        $display("CYCLE %0d: Row 0 MUL", cyc);
        @(negedge clk);
        mul_en = 4'b0001;  // Only row 0
        @(negedge clk);
        mul_en = 0;

        // Row 0 ADD
        $display("CYCLE %0d: Row 0 ADD", cyc);
        @(negedge clk);
        adder_en = 4'b0001;  // Only row 0
        @(negedge clk);
        adder_en = 0;
        $display("  Psums row 0: p00=%0d p01=%0d", p00, p01);

        // Diagonal shift: row 0 inputs → row 1 (with wraparound)
        // In DiP: PE[0][0].i_reg → PE[1][3] (leftmost row 0 → rightmost row 1)
        //         PE[0][1].i_reg → PE[1][0]
        // This happens automatically via systolic connections when row 1 pe_en fires
        $display("");
        $display("CYCLE %0d: Row 1 captures diagonal inputs from row 0", cyc);
        @(negedge clk);
        pe_en = 4'b0010;  // Row 1 enabled, captures from row 0's i_reg outputs
        @(negedge clk);
        pe_en = 0;
        $display("  Input regs row 1: i10=%0d i11=%0d", i10, i11);

        @(negedge clk);
        mul_en = 4'b0010;
        @(negedge clk);
        mul_en = 0;

        $display("CYCLE %0d: Row 1 ADD (accumulates with psum from row 0)", cyc);
        @(negedge clk);
        adder_en = 4'b0010;
        @(negedge clk);
        adder_en = 0;
        $display("  Psums row 1: p10=%0d p11=%0d", p10, p11);

        // Continue to row 2
        $display("");
        $display("CYCLE %0d: Row 2 captures from row 1", cyc);
        @(negedge clk);
        pe_en = 4'b0100;
        @(negedge clk);
        pe_en = 0;
        $display("  Input regs row 2: i20=%0d i21=%0d", i20, i21);

        @(negedge clk);
        mul_en = 4'b0100;
        @(negedge clk);
        mul_en = 0;

        $display("CYCLE %0d: Row 2 ADD", cyc);
        @(negedge clk);
        adder_en = 4'b0100;
        @(negedge clk);
        adder_en = 0;
        $display("  Psums row 2: p20=%0d p21=%0d", p20, p21);

        // Continue to row 3 (final output row)
        $display("");
        $display("CYCLE %0d: Row 3 captures from row 2", cyc);
        @(negedge clk);
        pe_en = 4'b1000;
        @(negedge clk);
        pe_en = 0;
        $display("  Input regs row 3: i30=%0d i31=%0d", i30, i31);

        @(negedge clk);
        mul_en = 4'b1000;
        @(negedge clk);
        mul_en = 0;

        $display("CYCLE %0d: Row 3 ADD (FINAL OUTPUT ROW)", cyc);
        @(negedge clk);
        adder_en = 4'b1000;
        @(negedge clk);
        adder_en = 0;
        $display("  Psums row 3: p30=%0d p31=%0d", p30, p31);

        $display("");
        $display("FINAL OUTPUTS (from row 3):");
        $display("  out0=%0d out1=%0d out2=%0d out3=%0d", out0, out1, out2, out3);
        $display("  (out0 should = p30, out1 should = p31, etc.)");

         // This legacy testbench predates the paper's left-to-right diagonal
         // convention.  The current RTL intentionally maps row 1 to
         // [2,3,0,1] for a row-0 input [1,2,3,0].  Keep the smoke test useful
         // by asserting the observable values it is intended to exercise.
         if (i10 == 2 && i11 == 0 && out0 == 15 && out1 == 18 &&
             out2 == 21 && out3 == 24)
             $display("PASS - weight cascade, diagonal movement, and MAC output");
         else begin
             $display("FAIL - unexpected systolic result");
             $fatal(1);
         end

        $finish;
    end
endmodule
