// Error checking for a DiP tiled matrix multiply.
//
// Edge tiles are zero padded by datapath.sv, so dimensions do not need to be
// multiples of LANES.  The actual invalid cases checked here are empty
// matrices, address overflow, and overlapping A/B/C regions.
module error_check #(
    parameter MAT_SIZE_BITS = 16,
    parameter BRAM_DEPTH = 18,
    parameter LANES = 64
)(
    input clk,
    input rst_n,
    input err_cal,
    input [MAT_SIZE_BITS-1:0] M, N, K,
    input [BRAM_DEPTH-1:0] base_addr_in1,
    input [BRAM_DEPTH-1:0] base_addr_in2,
    input [BRAM_DEPTH-1:0] base_addr_out,
    output reg err_found
);

    // Enough bits for a base address plus the product of two dimensions.
    // The old implementation hardcoded 8-bit dimensions here, which could
    // silently truncate the paper's larger transformer workloads.
    localparam SZW = BRAM_DEPTH + (2 * MAT_SIZE_BITS) + 1;

    wire empty_flag = (M == 0) | (N == 0) | (K == 0);

    // ---- ovf_flag: base + size fits in BRAM_DEPTH bits ----
    wire [SZW-1:0] M_ext = {{(SZW-MAT_SIZE_BITS){1'b0}}, M};
    wire [SZW-1:0] N_ext = {{(SZW-MAT_SIZE_BITS){1'b0}}, N};
    wire [SZW-1:0] K_ext = {{(SZW-MAT_SIZE_BITS){1'b0}}, K};
    wire [SZW-1:0] size1 = M_ext * N_ext;
    wire [SZW-1:0] size2 = N_ext * K_ext;
    wire [SZW-1:0] size3 = M_ext * K_ext;

    // promote bases to SZW before adding
    wire [SZW-1:0] b1x = {{(SZW-BRAM_DEPTH){1'b0}}, base_addr_in1};
    wire [SZW-1:0] b2x = {{(SZW-BRAM_DEPTH){1'b0}}, base_addr_in2};
    wire [SZW-1:0] b3x = {{(SZW-BRAM_DEPTH){1'b0}}, base_addr_out};

    wire [SZW-1:0] end1 = b1x + size1;
    wire [SZW-1:0] end2 = b2x + size2;
    wire [SZW-1:0] end3 = b3x + size3;

    // endN is an exclusive upper bound.  A region ending exactly at 2^AW is
    // legal because its last element is address 2^AW-1.
    wire [SZW-1:0] capacity =
        {{(SZW-BRAM_DEPTH-1){1'b0}}, 1'b1, {BRAM_DEPTH{1'b0}}};
    wire ovf_flag = (end1 > capacity) | (end2 > capacity) | (end3 > capacity);

    // ---- ovl_flag: regions must not overlap ----
    wire ovl_1_2 = (b1x < end2) && (b2x < end1);
    wire ovl_2_3 = (b2x < end3) && (b3x < end2);
    wire ovl_1_3 = (b1x < end3) && (b3x < end1);

    wire ovl_flag = ovl_1_2 | ovl_2_3 | ovl_1_3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            err_found <= 1'b0;
        else if (err_cal) begin
            if (empty_flag || ovf_flag || ovl_flag)
                err_found <= 1'b1;
            else
                err_found <= 1'b0;
        end
    end

endmodule
