module top_monitor_module
    #(parameter MAT_SIZE_BITS = 4,
    BRAM_DEPTH = 10,
    VAL_SIZE = 24,
    LANES = 4
    )
    (
    input wire clk,
    input wire start,
    input wire rst_n,
    output wire done
    );

    wire [MAT_SIZE_BITS - 1:0] M, N, K;
    wire start_db;
    wire [BRAM_DEPTH - 1:0] base_addr_in1, base_addr_in2, base_addr_out;
    wire [VAL_SIZE - 1:0] sram_wdata;
    wire [BRAM_DEPTH - 1:0] sram_addr;
    wire sram_we;
    wire [VAL_SIZE - 1:0] sram_rdata;
    wire err;

    button_debouncer db_inst (
    .clk(clk),
    .btn_in(start),
    .btn_out(start_db)
    );

    top_module#(.MAT_SIZE_BITS(MAT_SIZE_BITS),
                .SRAM_AW(BRAM_DEPTH),
                .VAL_SIZE(VAL_SIZE),
                .LANES(LANES)
                )
    dut_top_inst (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_db),
    .M(M), .N(N), .K(K),
    .base_addr_in1(base_addr_in1),
    .base_addr_in2(base_addr_in2),
    .base_addr_out(base_addr_out),
    .done(done),
    .sram_addr(sram_addr),
    .sram_we(sram_we),
    .sram_wdata(sram_wdata),
    .sram_rdata(sram_rdata),
    .err(err)
    );

    vio_0 vio_inst (
    .clk(clk),
    .probe_out0(M[MAT_SIZE_BITS - 1:0]),
    .probe_out1(N[MAT_SIZE_BITS - 1:0]),
    .probe_out2(K[MAT_SIZE_BITS - 1:0]),
    .probe_out3(base_addr_in1[BRAM_DEPTH - 1:0]),
    .probe_out4(base_addr_in2[BRAM_DEPTH - 1:0]),
    .probe_out5(base_addr_out[BRAM_DEPTH - 1:0])
    );
endmodule
