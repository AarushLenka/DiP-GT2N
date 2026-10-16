`timescale 1ns/1ps

module top_module #(
    parameter MAT_SIZE_BITS       = 16,
    parameter SRAM_AW             = 18,
    parameter VAL_SIZE            = 24,
    parameter LANES               = 64,
    parameter WEIGHTS_PREPERMUTED = 1
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [MAT_SIZE_BITS-1:0] M,
    input wire [MAT_SIZE_BITS-1:0] N,
    input wire [MAT_SIZE_BITS-1:0] K,
    input wire [SRAM_AW-1:0] base_addr_in1,
    input wire [SRAM_AW-1:0] base_addr_in2,
    input wire [SRAM_AW-1:0] base_addr_out,
    output wire done,
    output wire err,

    // Scalar SRAM interface: combinational read, synchronous write.
    output wire [SRAM_AW-1:0]  sram_addr,
    output wire                sram_we,
    output wire [VAL_SIZE-1:0] sram_wdata,
    input wire [VAL_SIZE-1:0]  sram_rdata
);
    localparam integer PHASE_W = ((LANES * LANES > 2 * LANES + 2) ?
                                  $clog2(LANES * LANES) :
                                  $clog2(2 * LANES + 2));

    wire [PHASE_W-1:0] mem_phase;
    wire mem_phase_valid;
    wire load_w_en, load_i_en, write_en;
    wire wshift, array_clear, acc_clear;
    wire run_en;
    wire [LANES-1:0] pe_en, mul_en, adder_en;
    wire [MAT_SIZE_BITS-1:0] tile_i, tile_j, tile_k;
    wire err_cal, err_found;

    assign err = err_found;

    controller #(
        .LANES(LANES),
        .MAT_SIZE_BITS(MAT_SIZE_BITS),
        .PHASE_W(PHASE_W)
    ) ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .M(M),
        .N(N),
        .K(K),
        .err_found(err_found),
        .err_cal(err_cal),
        .mem_phase(mem_phase),
        .mem_phase_valid(mem_phase_valid),
        .load_w_en(load_w_en),
        .load_i_en(load_i_en),
        .write_en(write_en),
        .wshift(wshift),
        .pe_en(pe_en),
        .mul_en(mul_en),
        .adder_en(adder_en),
        .array_clear(array_clear),
        .acc_clear(acc_clear),
        .tile_i(tile_i),
        .tile_j(tile_j),
        .tile_k(tile_k),
        .mem_we(),
        .i_inc(),
        .j_inc(),
        .h_inc(),
        .i_rst(),
        .j_rst(),
        .h_rst(),
        .i_max(1'b0),
        .j_max(1'b0),
        .h_max(1'b0)
    );

    assign run_en = mem_phase_valid && !load_w_en && !load_i_en &&
                    !write_en && (wshift == 1'b0) && (array_clear == 1'b0);

    datapath #(
        .MAT_SIZE_BITS(MAT_SIZE_BITS),
        .SRAM_AW(SRAM_AW),
        .VAL_SIZE(VAL_SIZE),
        .LANES(LANES),
        .WEIGHTS_PREPERMUTED(WEIGHTS_PREPERMUTED),
        .PHASE_W(PHASE_W)
    ) dtp (
        .clk(clk),
        .rst_n(rst_n),
        .M(M),
        .N(N),
        .K(K),
        .base_A(base_addr_in1),
        .base_B(base_addr_in2),
        .base_C(base_addr_out),
        .latch_dims(err_cal),
        .mem_phase(mem_phase),
        .mem_phase_valid(mem_phase_valid),
        .load_w_en(load_w_en),
        .load_i_en(load_i_en),
        .write_en(write_en),
        .wshift(wshift),
        .pe_en(pe_en),
        .mul_en(mul_en),
        .adder_en(adder_en),
        .array_clear(array_clear),
        .acc_clear(acc_clear),
        .run_en(run_en),
        .tile_i(tile_i),
        .tile_j(tile_j),
        .tile_k(tile_k),
        .i_inc(1'b0),
        .j_inc(1'b0),
        .h_inc(1'b0),
        .i_rst(1'b0),
        .j_rst(1'b0),
        .h_rst(1'b0),
        .sram_addr(sram_addr),
        .sram_we(sram_we),
        .sram_wdata(sram_wdata),
        .sram_rdata(sram_rdata),
        .i_max(),
        .j_max(),
        .h_max(),
        .err_cal(err_cal),
        .err_found(err_found)
    );
endmodule
