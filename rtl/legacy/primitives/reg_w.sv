// parameterized-width register (Synchronous reset-to-zero on rst_n assert, Enable-controlled)
module reg_w #(
    parameter WIDTH = 8
)(
    input clk,
    input rst_n,
    input en,
    input [WIDTH-1:0] d,
    output reg [WIDTH-1:0] q
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) q <= {WIDTH{1'b0}};
        else if (en) q <= d;
    end
endmodule
