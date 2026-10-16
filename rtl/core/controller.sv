`timescale 1ns/1ps

// DiP tile controller.
//
// The paper's array consumes one complete input row per cycle while the
// weights are stationary.  The external interface in this repository is a
// scalar SRAM interface, so the datapath first gathers an LxL tile and this
// controller then schedules the same diagonal wavefront through the array.
//
// For every output tile (i,j) and reduction tile k the schedule is:
//
//   LOAD_B      gather the LxL weight tile from SRAM
//   CLEAR_ARRAY clear the PE pipeline before loading the new stationary tile
//   SHIFT_W     load one permuted weight row per cycle, top to bottom
//   LOAD_A      gather the LxL activation tile from SRAM
//   RUN         stream L input rows, then flush the two-stage MAC wavefront
//   STORE       write the accumulated output tile to SRAM
//
// Reduction tiles repeat LOAD_B..RUN without clearing the output tile.  This
// is equivalent to the paper's tiled matrix multiplication and also handles
// dimensions that are not exact multiples of LANES by zero-padding edge tiles.
module controller #(
    parameter LANES         = 64,
    parameter MAT_SIZE_BITS = 16,
    parameter PHASE_W       = ((LANES * LANES > 2 * LANES + 2) ?
                               $clog2(LANES * LANES) :
                               $clog2(2 * LANES + 2))
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic done,

    input  logic [MAT_SIZE_BITS-1:0] M,
    input  logic [MAT_SIZE_BITS-1:0] N,
    input  logic [MAT_SIZE_BITS-1:0] K,

    input  logic err_found,
    output logic err_cal,

    // phase is used as a scalar tile index for memory phases and as a
    // wavefront cycle index during SHIFT_W/RUN.
    output logic [PHASE_W-1:0] mem_phase,
    output logic               mem_phase_valid,
    output logic               load_w_en,
    output logic               load_i_en,
    output logic               write_en,

    output logic wshift,
    output logic [LANES-1:0] pe_en,
    output logic [LANES-1:0] mul_en,
    output logic [LANES-1:0] adder_en,
    output logic array_clear,
    output logic acc_clear,

    output logic [MAT_SIZE_BITS-1:0] tile_i,
    output logic [MAT_SIZE_BITS-1:0] tile_j,
    output logic [MAT_SIZE_BITS-1:0] tile_k,

    // Retained as compatibility outputs for older wrappers.  The new
    // datapath owns the SRAM write-enable and tile counters directly.
    output logic mem_we,
    output logic i_inc,
    output logic j_inc,
    output logic h_inc,
    output logic i_rst,
    output logic j_rst,
    output logic h_rst,
    input  logic i_max,
    input  logic j_max,
    input  logic h_max
);
    localparam integer TILE_CYCLES = LANES * LANES;
    localparam integer RUN_CYCLES  = 2 * LANES + 2;
    localparam integer PHASE_MAX   = (TILE_CYCLES > RUN_CYCLES) ?
                                     TILE_CYCLES : RUN_CYCLES;

    typedef enum logic [3:0] {
        IDLE,
        SETUP,
        ERR_CHK,
        LOAD_B,
        CLEAR_ARRAY,
        SHIFT_W,
        LOAD_A,
        RUN,
        STORE,
        FINISH
    } state_t;

    state_t state, next_state;
    logic start_armed;

    logic [PHASE_W-1:0] phase;
    logic [MAT_SIZE_BITS-1:0] M_q, N_q, K_q;

    function automatic integer tile_count(input logic [MAT_SIZE_BITS-1:0] dim);
        begin
            tile_count = (dim + LANES - 1) / LANES;
        end
    endfunction

    wire phase_tile_last = (phase == TILE_CYCLES - 1);
    wire phase_shift_last = (phase == LANES - 1);
    wire phase_run_last = (phase == RUN_CYCLES - 1);

    wire last_reduction = (tile_k + 1 >= tile_count(N_q));
    wire last_column    = (tile_j + 1 >= tile_count(K_q));
    wire last_row       = (tile_i + 1 >= tile_count(M_q));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            phase  <= '0;
            M_q    <= '0;
            N_q    <= '0;
            K_q    <= '0;
            tile_i <= '0;
            tile_j <= '0;
            tile_k <= '0;
            start_armed <= 1'b1;
        end else begin
            state <= next_state;

            // Accept one start pulse only after the input has returned low.
            // This prevents a held level from launching a second operation
            // when FINISH returns to IDLE.
            if (!start)
                start_armed <= 1'b1;
            else if (state == IDLE && start_armed)
                start_armed <= 1'b0;

            if (state == SETUP) begin
                M_q    <= M;
                N_q    <= N;
                K_q    <= K;
                tile_i <= '0;
                tile_j <= '0;
                tile_k <= '0;
            end

            if (state == LOAD_B || state == SHIFT_W ||
                state == LOAD_A || state == RUN || state == STORE) begin
                if ((state == LOAD_B || state == LOAD_A || state == STORE) && phase_tile_last)
                    phase <= '0;
                else if (state == SHIFT_W && phase_shift_last)
                    phase <= '0;
                else if (state == RUN && phase_run_last)
                    phase <= '0;
                else
                    phase <= phase + 1'b1;
            end else begin
                phase <= '0;
            end

            // Tile counters advance only after the complete output tile has
            // been written, except that an intermediate reduction tile must
            // advance k immediately after RUN because it has no STORE phase.
            if (state == RUN && phase_run_last && !last_reduction) begin
                tile_k <= tile_k + 1'b1;
            end

            // k is the reduction-tile counter for the final partial sum.
            if (state == STORE && phase_tile_last) begin
                if (!last_reduction) begin
                    tile_k <= tile_k + 1'b1;
                end else begin
                    tile_k <= '0;
                    if (!last_column) begin
                        tile_j <= tile_j + 1'b1;
                    end else begin
                        tile_j <= '0;
                        if (!last_row)
                            tile_i <= tile_i + 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:        if (start && start_armed) next_state = SETUP;
            SETUP:                            next_state = ERR_CHK;
            ERR_CHK:     if (err_found)       next_state = FINISH;
                         else                 next_state = LOAD_B;
            LOAD_B:      if (phase_tile_last) next_state = CLEAR_ARRAY;
            CLEAR_ARRAY:                      next_state = SHIFT_W;
            SHIFT_W:     if (phase_shift_last) next_state = LOAD_A;
            LOAD_A:      if (phase_tile_last) next_state = RUN;
            RUN: begin
                if (phase_run_last) begin
                    if (last_reduction)
                        next_state = STORE;
                    else
                        next_state = LOAD_B;
                end
            end
            STORE: begin
                if (phase_tile_last) begin
                    if (last_reduction && last_column && last_row)
                        next_state = FINISH;
                    else
                        next_state = LOAD_B;
                end
            end
            FINISH:                           next_state = IDLE;
            default:                          next_state = IDLE;
        endcase
    end

    integer r;
    always_comb begin
        done             = 1'b0;
        err_cal          = 1'b0;
        mem_phase        = phase;
        mem_phase_valid  = 1'b0;
        load_w_en        = 1'b0;
        load_i_en        = 1'b0;
        write_en         = 1'b0;
        wshift           = 1'b0;
        array_clear      = 1'b0;
        acc_clear        = 1'b0;
        pe_en            = '0;
        mul_en           = '0;
        adder_en         = '0;

        // Compatibility signals are intentionally quiescent.  New wrappers
        // use tile_i/tile_j/tile_k and the explicit phase enables above.
        mem_we = 1'b0;
        i_inc  = 1'b0;
        j_inc  = 1'b0;
        h_inc  = 1'b0;
        i_rst  = 1'b0;
        j_rst  = 1'b0;
        h_rst  = 1'b0;

        case (state)
            SETUP: begin
                err_cal = 1'b1;
                i_rst   = 1'b1;
                j_rst   = 1'b1;
                h_rst   = 1'b1;
            end
            LOAD_B: begin
                mem_phase_valid = 1'b1;
                load_w_en       = 1'b1;
            end
            CLEAR_ARRAY: begin
                array_clear = 1'b1;
                acc_clear   = (tile_k == 0);
            end
            SHIFT_W: begin
                mem_phase_valid = 1'b1;
                wshift          = 1'b1;
            end
            LOAD_A: begin
                mem_phase_valid = 1'b1;
                load_i_en       = 1'b1;
            end
            RUN: begin
                mem_phase_valid = 1'b1;
                // Row r captures the wavefront for input rows m where
                // r <= phase-m < r+LANES.  The two following expressions
                // account for the multiply and add pipeline stages.
                for (r = 0; r < LANES; r = r + 1) begin
                    if ((phase >= r) && (phase < r + LANES))
                        pe_en[r] = 1'b1;
                    if ((phase >= r + 1) && (phase < r + LANES + 1))
                        mul_en[r] = 1'b1;
                    if ((phase >= r + 2) && (phase < r + LANES + 2))
                        adder_en[r] = 1'b1;
                end
            end
            STORE: begin
                mem_phase_valid = 1'b1;
                write_en        = 1'b1;
            end
            FINISH: begin
                done = 1'b1;
                i_rst = 1'b1;
                j_rst = 1'b1;
                h_rst = 1'b1;
            end
            default: ;
        endcase
    end
endmodule
