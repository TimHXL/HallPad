`timescale 1ns / 1ps

// Active-low physical button: two-flop synchronization, stable-level debounce,
// then one pulse per press. A held button never repeats. 50 MHz default: 10 ms.
module keyboard_button #(
    parameter integer DEBOUNCE_CYCLES = 500000
) (
    input wire clk,
    input wire rst_n,
    input wire button_n,
    output reg press_pulse
);
    localparam integer COUNT_W = (DEBOUNCE_CYCLES < 2) ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam [COUNT_W-1:0] LAST_COUNT = DEBOUNCE_CYCLES - 1;
    (* syn_preserve = 1 *) reg sync_meta, sync_level;
    reg stable_level;
    reg [COUNT_W-1:0] count;

    // synthesis translate_off
    initial begin
        if (DEBOUNCE_CYCLES < 1) begin
            $display("FAIL keyboard_button DEBOUNCE_CYCLES must be positive");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_meta <= 1'b1;
            sync_level <= 1'b1;
            stable_level <= 1'b1;
            count <= {COUNT_W{1'b0}};
            press_pulse <= 1'b0;
        end else begin
            sync_meta <= button_n;
            sync_level <= sync_meta;
            press_pulse <= 1'b0;
            if (sync_level == stable_level)
                count <= {COUNT_W{1'b0}};
            else if (count == LAST_COUNT) begin
                stable_level <= sync_level;
                count <= {COUNT_W{1'b0}};
                press_pulse <= !sync_level;
            end else
                count <= count + 1'b1;
        end
    end

endmodule
