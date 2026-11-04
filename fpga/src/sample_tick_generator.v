module sample_tick_generator (
    input  wire clk,
    input  wire rst_n,
    output wire sample_tick
);

    //==================================================
    // 50 MHz system clock → 48 kHz audio sample tick
    //
    // 直接复用已经实现好的分数分频模块
    //==================================================

    sample_tick_48k #(
        .CLK_FREQ    (50_000_000),
        .SAMPLE_RATE (48_000)
    )
    u_sample_tick_48k (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_tick (sample_tick)
    );


endmodule