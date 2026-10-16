`timescale 1ns/1ps

// DiP datapath.
//
// The paper assumes banked memories capable of presenting an entire array
// row in parallel.  The repository-level top interface is a scalar SRAM
// port, therefore this datapath gathers one LxL A tile and one LxL B tile in
// local arrays before starting the systolic wavefront.  The local arrays are
// staging registers, not input/output synchronization FIFOs: the actual
// compute path is the diagonal-input, permuted-weight stationary array in
// systolic.sv.
module datapath #(
    parameter MAT_SIZE_BITS      = 16,
    parameter SRAM_AW            = 18,
    parameter VAL_SIZE           = 24,
    parameter LANES              = 64,
    parameter WEIGHTS_PREPERMUTED = 1,
    parameter PHASE_W            = ((LANES * LANES > 2 * LANES + 2) ?
                                     $clog2(LANES * LANES) :
                                     $clog2(2 * LANES + 2))
)(
    input clk,
    input rst_n,

    input [MAT_SIZE_BITS-1:0] M,
    input [MAT_SIZE_BITS-1:0] N,
    input [MAT_SIZE_BITS-1:0] K,
    input [SRAM_AW-1:0] base_A,
    input [SRAM_AW-1:0] base_B,
    input [SRAM_AW-1:0] base_C,
    input latch_dims,

    input [PHASE_W-1:0] mem_phase,
    input mem_phase_valid,
    input load_w_en,
    input load_i_en,
    input write_en,

    input wshift,
    input [LANES-1:0] pe_en,
    input [LANES-1:0] mul_en,
    input [LANES-1:0] adder_en,
    input array_clear,
    input acc_clear,
    input run_en,

    input [MAT_SIZE_BITS-1:0] tile_i,
    input [MAT_SIZE_BITS-1:0] tile_j,
    input [MAT_SIZE_BITS-1:0] tile_k,

    // Legacy counter controls are intentionally ignored.  They remain in
    // the port list so older wrappers can still elaborate this module.
    input i_inc,
    input j_inc,
    input h_inc,
    input i_rst,
    input j_rst,
    input h_rst,

    output reg [SRAM_AW-1:0] sram_addr,
    output reg sram_we,
    output reg [VAL_SIZE-1:0] sram_wdata,
    input [VAL_SIZE-1:0] sram_rdata,

    output i_max,
    output j_max,
    output h_max,

    input err_cal,
    output err_found
);
    localparam integer TILE_CYCLES = LANES * LANES;

    reg [MAT_SIZE_BITS-1:0] M_q, N_q, K_q;
    reg [SRAM_AW-1:0] bA_q, bB_q, bC_q;

    // The paper's Algorithm 1 stores B_perm[row][col] =
    // B[(row+col) % LANES][col].  The default interface expects that
    // software-prepared tile.  Set WEIGHTS_PREPERMUTED=0 to perform the same
    // permutation in this staging datapath for ordinary row-major B tiles.
    reg [7:0] a_tile [0:LANES-1][0:LANES-1];
    reg [7:0] b_tile [0:LANES-1][0:LANES-1];
    reg signed [VAL_SIZE-1:0] c_tile [0:LANES-1][0:LANES-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_q  <= '0;
            N_q  <= '0;
            K_q  <= '0;
            bA_q <= '0;
            bB_q <= '0;
            bC_q <= '0;
        end else if (latch_dims) begin
            M_q  <= M;
            N_q  <= N;
            K_q  <= K;
            bA_q <= base_A;
            bB_q <= base_B;
            bC_q <= base_C;
        end
    end

    integer rr;
    integer cc;
    integer b_capture_row;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (rr = 0; rr < LANES; rr = rr + 1) begin
                for (cc = 0; cc < LANES; cc = cc + 1) begin
                    a_tile[rr][cc] <= 8'd0;
                    b_tile[rr][cc] <= 8'd0;
                    c_tile[rr][cc] <= '0;
                end
            end
        end else begin
            if (load_w_en && mem_phase_valid) begin
                if (WEIGHTS_PREPERMUTED)
                    b_capture_row = (tile_k * LANES) +
                                    (((mem_phase / LANES) + (mem_phase % LANES)) % LANES);
                else
                    b_capture_row = (tile_k * LANES) + (mem_phase / LANES);

                if ((b_capture_row < N_q) &&
                    ((tile_j * LANES) + (mem_phase % LANES) < K_q))
                    b_tile[mem_phase / LANES][mem_phase % LANES] <= sram_rdata[7:0];
                else
                    b_tile[mem_phase / LANES][mem_phase % LANES] <= 8'd0;
            end

            if (load_i_en && mem_phase_valid) begin
                if (((tile_i * LANES) + (mem_phase / LANES) < M_q) &&
                    ((tile_k * LANES) + (mem_phase % LANES) < N_q))
                    a_tile[mem_phase / LANES][mem_phase % LANES] <= sram_rdata[7:0];
                else
                    a_tile[mem_phase / LANES][mem_phase % LANES] <= 8'd0;
            end

            if (acc_clear) begin
                for (rr = 0; rr < LANES; rr = rr + 1)
                    for (cc = 0; cc < LANES; cc = cc + 1)
                        c_tile[rr][cc] <= '0;
            end else if (output_capture) begin
                for (cc = 0; cc < LANES; cc = cc + 1)
                    c_tile[output_row][cc] <=
                        $signed(c_tile[output_row][cc]) + $signed(pe_out[cc]);
            end
        end
    end

    // One extra RUN phase is retained after the last adder edge so the
    // registered final-row output can be captured on the following edge.
    wire output_capture = run_en &&
                          (mem_phase >= LANES + 2) &&
                          (mem_phase < 2 * LANES + 2);
    integer output_row;
    always @* begin
        output_row = mem_phase - (LANES + 2);
    end

    // Scalar SRAM address generation.  Address and write data are kept
    // combinational so the synchronous SRAM observes an aligned tuple at its
    // active clock edge.
    integer addr_phase;
    integer addr_row;
    integer addr_col;
    integer b_target_row;
    integer b_global_col;
    integer b_source_row;
    always @* begin
        addr_phase = mem_phase;
        addr_row   = addr_phase / LANES;
        addr_col   = addr_phase % LANES;
        b_target_row = (tile_k * LANES) + addr_row;
        b_global_col = (tile_j * LANES) + addr_col;
        b_source_row = b_target_row;

        // A pre-permuted B matrix may have been generated for the complete
        // reduction dimension, not independently for each local tile.  Map
        // the local diagonal weight (r,c) back to the stored row before the
        // scalar read.  For an LxL problem this reduces to the usual local
        // Algorithm-1 permutation.
        if (WEIGHTS_PREPERMUTED && (N_q != 0)) begin
            // Add N_q before taking the modulo so the expression is
            // non-negative even when the output-column offset is larger
            // than the reduction dimension.  This is synthesis-friendly
            // (unlike an unbounded procedural wrap loop).
            b_source_row = ((tile_k * LANES) +
                            ((addr_row + addr_col) % LANES) + N_q -
                            (b_global_col % N_q)) % N_q;
        end

        sram_addr  = {SRAM_AW{1'b0}};
        sram_we    = 1'b0;
        sram_wdata = {VAL_SIZE{1'b0}};

        if (load_w_en) begin
            sram_addr = bB_q +
                        (b_source_row * K_q) + b_global_col;
        end else if (load_i_en) begin
            sram_addr = bA_q +
                        (((tile_i * LANES) + addr_row) * N_q) +
                        ((tile_k * LANES) + addr_col);
        end else if (write_en) begin
            sram_addr = bC_q +
                        (((tile_i * LANES) + addr_row) * K_q) +
                        ((tile_j * LANES) + addr_col);

            if (((tile_i * LANES) + addr_row < M_q) &&
                ((tile_j * LANES) + addr_col < K_q)) begin
                sram_we    = 1'b1;
                sram_wdata = c_tile[addr_row][addr_col];
            end
        end
    end

    reg [8*LANES-1:0] weight_flat;
    reg [8*LANES-1:0] input_flat;
    integer stream_row;
    integer stream_col;
    integer input_row;
    always @* begin
        weight_flat = {(8*LANES){1'b0}};
        input_flat  = {(8*LANES){1'b0}};

        stream_row = LANES - 1 - mem_phase;
        if (wshift && (mem_phase < LANES)) begin
            for (stream_col = 0; stream_col < LANES; stream_col = stream_col + 1) begin
                if (WEIGHTS_PREPERMUTED)
                    weight_flat[8*stream_col +: 8] = b_tile[stream_row][stream_col];
                else
                    weight_flat[8*stream_col +: 8] =
                        b_tile[(stream_row + stream_col) % LANES][stream_col];
            end
        end

        input_row = mem_phase;
        if (run_en && (mem_phase < LANES)) begin
            for (stream_col = 0; stream_col < LANES; stream_col = stream_col + 1)
                input_flat[8*stream_col +: 8] = a_tile[input_row][stream_col];
        end
    end

    wire [24*LANES-1:0] pe_out_flat;
    systolic #(.LANES(LANES)) sa (
        .clk(clk),
        .rst_n(rst_n),
        .wshift(wshift),
        .pe_en(pe_en),
        .mul_en(mul_en),
        .adder_en(adder_en),
        .weight_flat(weight_flat),
        .I_flat(input_flat),
        .pe_output_flat(pe_out_flat),
        .clear(array_clear)
    );

    wire [23:0] pe_out [0:LANES-1];
    genvar g;
    generate
        for (g = 0; g < LANES; g = g + 1) begin : OUT_UNPACK
            assign pe_out[g] = pe_out_flat[24*g +: 24];
        end
    endgenerate

    // The legacy loop outputs are not used by the tiled controller.
    assign i_max = 1'b0;
    assign j_max = 1'b0;
    assign h_max = 1'b0;

    error_check #(
        .MAT_SIZE_BITS(MAT_SIZE_BITS),
        .BRAM_DEPTH(SRAM_AW),
        .LANES(LANES)
    ) ec (
        .clk(clk),
        .rst_n(rst_n),
        .err_cal(err_cal),
        .M(M),
        .N(N),
        .K(K),
        .base_addr_in1(base_A),
        .base_addr_in2(base_B),
        .base_addr_out(base_C),
        .err_found(err_found)
    );
endmodule
