`timescale 1ns / 1ps

// Fixed board clock contract: 50 MHz clk -> 12.5 MHz codec MCLK.
// This output is NOT a clock for FPGA logic. All FPGA state uses clk.
// The TLV320DAC3100 PLL produces audio clocks and returns BCLK/WCLK.
module audio_clock_gen #(
    parameter integer CLK_HZ = 50000000,
    parameter integer READY_CYCLES = 64
) (
    input  wire clk,
    input  wire rst_n,
    output wire AUD_MCLK,
    output reg  clock_ready
);
    localparam integer READY_W = (READY_CYCLES < 2) ? 1 : $clog2(READY_CYCLES + 1);
    reg [1:0] divider;
    reg [READY_W-1:0] settle_count;

    assign AUD_MCLK = divider[1];

    // synthesis translate_off
    initial begin
        if (CLK_HZ != 50000000 || READY_CYCLES < 1) begin
            $display("FAIL audio_clock_gen requires 50 MHz and READY_CYCLES >= 1");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divider <= 2'd0;
            settle_count <= {READY_W{1'b0}};
            clock_ready <= 1'b0;
        end else begin
            divider <= divider + 2'd1;
            if (!clock_ready) begin
                if (settle_count == READY_CYCLES - 1)
                    clock_ready <= 1'b1;
                else
                    settle_count <= settle_count + 1'b1;
            end
        end
    end

endmodule
