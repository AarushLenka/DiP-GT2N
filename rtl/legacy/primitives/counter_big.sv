// Parameterized-width wrap counter
module counter_big #(
    parameter WIDTH = 8
)(
    input clk,
    input rst_n,
    input inc,
    input [WIDTH-1:0] maxVal,
    output isMax,
    output [WIDTH-1:0] value
);
    reg [WIDTH-1:0] out_tmp;

    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            out_tmp <= {WIDTH{1'b0}};
        end else if (inc == 1'b1) begin
            out_tmp <= out_tmp + 1;
        end
    end

    assign isMax = (value == maxVal);
    assign value = out_tmp;
endmodule
