module sample_tick_48k #(
    parameter integer CLK_FREQ    = 50_000_000,
    parameter integer SAMPLE_RATE = 48_000
)(
    input  wire clk,
    input  wire rst_n,

    output reg  sample_tick
);

    reg [31:0] acc;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            acc         <= 32'd0;
            sample_tick <= 1'b0;

        end
        else begin

            // 默认情况下没有采样脉冲
            sample_tick <= 1'b0;

            // 判断下一次累加是否会超过 CLK_FREQ
            if (acc >= CLK_FREQ - SAMPLE_RATE) begin

                acc <= acc - (CLK_FREQ - SAMPLE_RATE);

                // 产生一个时钟周期宽度的采样脉冲
                sample_tick <= 1'b1;

            end
            else begin

                acc <= acc + SAMPLE_RATE;

            end

        end

    end


endmodule