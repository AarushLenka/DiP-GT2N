`timescale 1ns / 1ps

// 64×64 DiP systolic array, per the paper's Fig. 2(a) architecture:
//   - inputs move diagonally across rows, with wraparound connection
//     from the LEFT edge of row r-1 to the RIGHT edge of row r
//   - weights loaded vertically (top -> bottom)
//   - psums accumulated vertically (top -> bottom)
//   - output tapped from the LAST row
module systolic #(
    parameter LANES = 64
)(
    input clk,
    input rst_n,

    // Control signals
    input wshift,
    input [LANES-1:0] pe_en,
    input [LANES-1:0] mul_en,
    input [LANES-1:0] adder_en,

    // Inputs (packed, one 8-bit element per PE)
    input [8*LANES-1:0]  weight_flat,
    input [8*LANES-1:0]  I_flat,

    // Outputs (packed, one 24-bit psum per PE in the last row)
    output [24*LANES-1:0] pe_output_flat,

    // Optional synchronous clear forwarded to every PE.  Leaving this
    // port unconnected is safe; pe treats Z/X as inactive.
    input clear
);

    // ====================================================
    // 1. UNPACKING INPUTS
    // ====================================================
    wire [23:0] psum_in [0:LANES-1];
    wire [7:0]  w_in    [0:LANES-1];
    wire [7:0]  I_in    [0:LANES-1];

    genvar k;
    generate
        for (k = 0; k < LANES; k = k + 1) begin : UNPACK
            assign psum_in[k] = 24'd0;         // no external psum source (paper-style DiP)
            assign w_in[k]    = weight_flat[8*(k+1)-1 : 8*k];
            assign I_in[k]    = I_flat[8*(k+1)-1 : 8*k];
        end
    endgenerate

    // ====================================================
    // 3. PE REGISTERS (internal to each pe instance)
    // ====================================================
    // 2D arrays: element [r][c] = PE(row r, col c)
    wire [7:0]  i_reg [0:LANES-1][0:LANES-1];
    wire [7:0]  w_reg [0:LANES-1][0:LANES-1];
    wire [23:0] p_out [0:LANES-1][0:LANES-1];

    // ====================================================
    // 4. PE GENERATION + INTERCONNECT
    // ====================================================
    genvar r, c;
    generate
        // ---------- ROW 0: sources come from external inputs ----------
        for (c = 0; c < LANES; c = c + 1) begin : ROW0
            pe pe_inst (
                .clk(clk), .rst_n(rst_n),
                .wshift(wshift),
                .pe_en(pe_en[0]), .mul_en(mul_en[0]), .adder_en(adder_en[0]),
                .Inp(I_in[c]),
                .weight(w_in[c]),
                .psum(psum_in[c]),
                .Input_shifted(i_reg[0][c]),
                .weight_shifted(w_reg[0][c]),
                .pe_output(p_out[0][c]),
                .clear(clear)
            );
        end

        // ---------- ROWS 1..LANES-1: diagonal input + vertical weight/psum ----------
        for (r = 1; r < LANES; r = r + 1) begin : ROW
            for (c = 0; c < LANES; c = c + 1) begin : COL
                // Diagonal input: PE[r][c] reads PE[r-1][(c+1)%LANES].
                // Thus [1,2,3] becomes [2,3,1], including the boundary
                // connection from the prior row's left edge to this row's
                // right edge.
                //
                // Weight: vertical feed from row above, same column.  On a
                // wshift edge row 0 captures the current weight_flat value,
                // while each lower row captures the previously registered
                // value from the row above.  This preserves distinct
                // row-specific weights when weight_flat changes per cycle.
                // Psum: vertical feed from row above, same column
                pe pe_inst (
                    .clk(clk), .rst_n(rst_n),
                    .wshift(wshift),
                    .pe_en(pe_en[r]), .mul_en(mul_en[r]), .adder_en(adder_en[r]),
                    .Inp   (i_reg[r-1][(c + 1) % LANES]),
                    .weight(w_reg[r-1][c]),
                    .psum  (p_out[r-1][c]),
                    .Input_shifted  (i_reg[r][c]),
                    .weight_shifted (w_reg[r][c]),
                    .pe_output      (p_out[r][c]),
                    .clear          (clear)
                );
            end
        end
    endgenerate

    // ====================================================
    // 5. PACKING OUTPUTS (from the LAST row only)
    // ====================================================
    genvar j;
    generate
        for (j = 0; j < LANES; j = j + 1) begin : PACK
            assign pe_output_flat[24*(j+1)-1 : 24*j] = p_out[LANES-1][j];
        end
    endgenerate

endmodule
