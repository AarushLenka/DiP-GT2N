// blk_mem_gen_0 behavioral model:
// simple single-port BRAM with registered (1-cycle) read,
// matching the typical Xilinx blk_mem_gen latency behavior.
module blk_mem_gen_0 #(
    parameter DEPTH = 1024,
    parameter WIDTH = 24,
    parameter AW     = 10
)(
    input  wire             clka,
    input  wire             wea,
    input  wire [AW-1:0]    addra,
    input  wire [WIDTH-1:0] dina,
    output reg  [WIDTH-1:0] douta
);
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    //integer i;
    //initial begin
    //    for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WIDTH{1'b0}};
    //end

    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;
        douta <= mem[addra];
    end
endmodule
