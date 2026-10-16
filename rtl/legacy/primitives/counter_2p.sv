// Three-point counter for the outer h-loop:
//  - counts 0.. maxVal (wraps to 0 on reaching maxVal)
//  - emits window markers isPoint1 (> THRESH-1) and isPoint2 (< maxVal - THRESH)
// DiP paper: h-scan input-load window is [0 .. THRESH-1], output-drain window is [THRESH .. maxVal]
// For a 64x64 array, THRESH = 64 (4 rows of the array = 4 input rows deep).
module counter_2p #(
    parameter THRESH = 64
)(
    input wire clk,
    input wire rst_n,
    input wire inc,
    input wire [7:0] maxVal,

    output wire isPoint1,
    output wire isPoint2,
    output wire isMax,
    output wire [7:0] value
);

    reg [7:0] out_tmp = 8'd0;   // power-up value; the FSM's rst via h_rstn

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_tmp <= 0;
        else if (inc) begin
            if (out_tmp == maxVal)
                out_tmp <= 0;
            else
                out_tmp <= out_tmp + 1;
        end
    end

    assign value   = out_tmp;
    assign isMax   = (out_tmp == maxVal);

    // Window markers (same convention as the 4x4 RTL: h > X means "in the window")
    assign isPoint1 = (out_tmp >  (THRESH - 1));      // drain-window start
    assign isPoint2 = (out_tmp <  (maxVal - THRESH)); // input-window end

endmodule
