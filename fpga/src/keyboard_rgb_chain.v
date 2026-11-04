`timescale 1ns / 1ps

// Independent bring-up output for a 24-bit RGB chain; 50 MHz clock only.
// pixels_rgb[23:0] is the electrically first pixel, in R7..0/G7..0/B7..0
// order. Every pixel is captured on the same frame-start edge. Wire order is
// G7..0/R7..0/B7..0, with no gap between pixels and MSB first.
//
// 64 clocks/bit = 1.28 us. Zero: 16 high/48 low; one: 44 high/20 low.
// Each complete frame is followed by at least 15000 low clocks (300 us).
// This is a digital timing contract, not a claim of board-level validation.
module keyboard_rgb_chain #(
    parameter integer LED_COUNT = 35
) (
    input wire clk,
    input wire rst_n,
    input wire [LED_COUNT*24-1:0] pixels_rgb,
    output reg serial_out
);
    localparam integer INDEX_W = (LED_COUNT < 2) ? 1 : $clog2(LED_COUNT);
    localparam [INDEX_W-1:0] LAST_PIXEL = LED_COUNT - 1;
    localparam [13:0] RESET_CYCLES = 14'd15000;

    // synthesis translate_off
    initial begin
        if (LED_COUNT < 1) begin
            $display("FAIL keyboard_rgb_chain LED_COUNT must be positive");
            $finish;
        end
    end
    // synthesis translate_on

    function [23:0] rgb_to_grb;
        input [23:0] rgb;
        begin
            rgb_to_grb = {rgb[15:8], rgb[23:16], rgb[7:0]};
        end
    endfunction

    reg sending;
    reg [13:0] reset_count;
    reg [5:0] bit_cycle;
    reg [4:0] bits_left;
    reg [INDEX_W-1:0] pixel_index;
    reg [23:0] pixel_grb;
    reg [LED_COUNT*24-1:0] remaining_rgb;
    wire [LED_COUNT*24+23:0] padded_pixels = {24'd0, pixels_rgb};
    wire [LED_COUNT*24+23:0] padded_remaining = {24'd0, remaining_rgb};
    wire [5:0] high_last = pixel_grb[23] ? 6'd43 : 6'd15;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            serial_out <= 1'b0;
            sending <= 1'b0;
            reset_count <= 14'd0;
            bit_cycle <= 6'd0;
            bits_left <= 5'd23;
            pixel_index <= {INDEX_W{1'b0}};
            pixel_grb <= 24'd0;
            remaining_rgb <= {(LED_COUNT*24){1'b0}};
        end else if (!sending) begin
            serial_out <= 1'b0;
            if (reset_count == RESET_CYCLES) begin
                // Together these two registers snapshot the WHOLE input frame.
                // Zero padding keeps this slice in range for LED_COUNT=1.
                pixel_grb <= rgb_to_grb(pixels_rgb[23:0]);
                remaining_rgb <= padded_pixels[LED_COUNT*24+23:24];
                pixel_index <= {INDEX_W{1'b0}};
                bits_left <= 5'd23;
                bit_cycle <= 6'd0;
                reset_count <= 14'd0;
                sending <= 1'b1;
                serial_out <= 1'b1;
            end else begin
                reset_count <= reset_count + 1'b1;
            end
        end else if (bit_cycle == 6'd63) begin
            bit_cycle <= 6'd0;
            if (bits_left != 0) begin
                pixel_grb <= {pixel_grb[22:0], 1'b0};
                bits_left <= bits_left - 1'b1;
                serial_out <= 1'b1;
            end else if (pixel_index != LAST_PIXEL) begin
                pixel_grb <= rgb_to_grb(remaining_rgb[23:0]);
                remaining_rgb <= padded_remaining[LED_COUNT*24+23:24];
                pixel_index <= pixel_index + 1'b1;
                bits_left <= 5'd23;
                serial_out <= 1'b1;
            end else begin
                sending <= 1'b0;
                reset_count <= 14'd0;
                serial_out <= 1'b0;
            end
        end else begin
            bit_cycle <= bit_cycle + 1'b1;
            if (bit_cycle == high_last)
                serial_out <= 1'b0;
        end
    end

endmodule
