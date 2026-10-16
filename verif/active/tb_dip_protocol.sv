`timescale 1ns/1ps

module tb_dip_protocol;
    localparam integer LANES = 4;
    localparam integer AW = 10;
    localparam integer V = 24;

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [7:0] M = 4, N = 4, K = 4;
    reg [AW-1:0] base_A = 0, base_B = 64, base_C = 128;
    wire done, err;
    wire [AW-1:0] sram_addr;
    wire sram_we;
    wire [V-1:0] sram_wdata, sram_rdata;
    integer done_edges;
    integer write_count;

    always #5 clk = ~clk;

    top_module #(
        .MAT_SIZE_BITS(8), .SRAM_AW(AW), .VAL_SIZE(V), .LANES(LANES)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .M(M), .N(N), .K(K),
        .base_addr_in1(base_A), .base_addr_in2(base_B),
        .base_addr_out(base_C), .done(done), .err(err),
        .sram_addr(sram_addr), .sram_we(sram_we),
        .sram_wdata(sram_wdata), .sram_rdata(sram_rdata)
    );

    sram_model #(.DEPTH(1 << AW), .WIDTH(V), .AW(AW)) mem (
        .clk(clk), .we(sram_we), .addr(sram_addr),
        .din(sram_wdata), .dout(sram_rdata)
    );

    always @(posedge clk) begin
        if (done)
            done_edges = done_edges + 1;
        if (sram_we)
            write_count = write_count + 1;
    end

    task pulse_start;
        begin
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
        end
    endtask

    integer i;
    initial begin
        done_edges = 0;
        write_count = 0;
        for (i = 0; i < 16; i = i + 1)
            mem.mem[base_A + i] = i + 1;
        for (i = 0; i < 16; i = i + 1)
            mem.mem[base_B + i] = 1;
        for (i = 0; i < 16; i = i + 1)
            mem.mem[base_C + i] = 0;

        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        pulse_start();
        // Raise start again while the operation is busy.  The controller
        // must not treat that held level as a second launch after FINISH.
        start = 1;

        // The operation must finish and expose one done pulse.
        wait (done === 1'b1);
        repeat (20) @(posedge clk);
        start = 0;
        #1;
        if (done_edges !== 1) begin
            $display("FAIL: expected one done edge, got %0d", done_edges);
            $fatal(1);
        end

        // Invalid dimensions terminate with err and perform no writes.
        M = 0;
        write_count = 0;
        pulse_start();
        wait (done === 1'b1);
        @(posedge clk);
        #1;
        if (!err || write_count !== 0) begin
            $display("FAIL: invalid dimensions err=%b writes=%0d", err, write_count);
            $fatal(1);
        end

        $display("PASS: done pulse, held-start behavior, and error abort");
        $finish;
    end
endmodule
