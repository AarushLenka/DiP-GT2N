// Behavioral SRAM model — combinational read, synchronous write.
// This matches ASIC SRAM semantics (no registered output latency)
// and eliminates all the pipeline-compensation logic that was needed
// for the Xilinx BRAM (blk_mem_gen_0) registered output model.
`timescale 1ns/1ps
module sram_model #(
    parameter DEPTH = 262144,   // 2^18 default
    parameter WIDTH = 24,
    parameter AW    = 18
)(
    input  wire             clk,
    input  wire             we,
    input  wire [AW-1:0]    addr,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout
);
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Combinational read — result available same cycle address is presented
    assign dout = mem[addr];

    // Synchronous write
    always @(posedge clk)
        if (we) mem[addr] <= din;

endmodule
