`timescale 1ns / 1ps

// One WS2812B-2020 status pixel, driven from the board's 50 MHz clock.
// Wire format: G7..G0, R7..R0, B7..B0. The requested color is latched only
// at a frame boundary, so a UI/fault transition cannot mix two colors.
//
// Timing target: Worldsemi WS2812B-2020 V1.0, pages 3-4 (2018-07-25):
// https://www.mouser.com/pdfDocs/WS2812B-2020_V10_EN_181106150240761.pdf
// At 50 MHz: 64 clocks/bit = 1.28 us; zero = 320 ns high/960 ns low;
// one = 880 ns high/400 ns low; frame reset is at least 300 us low.
// The 44-clock one-high also meets that revision's 420 ns maximum T1L.
// Later WS2812B-2020 revisions publish different timing limits; this is not
// a claim of board validation or compatibility with every same-name revision.
module keyboard_status_led #(
    parameter integer CLK_HZ = 50000000
) (
    input wire clk,
    input wire rst_n,
    input wire [2:0] ui_state,
    input wire fault,
    output reg WS2812
);
    localparam [13:0] RESET_CYCLES = 14'd15000;
    localparam [5:0] ZERO_HIGH_LAST = 6'd15;
    localparam [5:0] ONE_HIGH_LAST = 6'd43;

    // synthesis translate_off
    initial begin
        if (CLK_HZ != 50000000) begin
            $display("FAIL keyboard_status_led requires a 50 MHz clock");
            $finish;
        end
    end
    // synthesis translate_on

    reg [23:0] requested_rgb;
    always @(*) begin
        // Small channel values keep the status LED at low brightness.
        case (ui_state)
            3'd0: requested_rgb = 24'h080808; // Uncalibrated: dim white.
            3'd1: requested_rgb = 24'h000010; // Confirm all keys released: blue.
            3'd2: requested_rgb = 24'h001010; // Endpoint capture running: cyan.
            3'd3: requested_rgb = 24'h101000; // Confirm selected full press: yellow.
            3'd4: requested_rgb = 24'h100010; // Release every key: purple.
            3'd5: requested_rgb = 24'h001000; // Ready to play: green.
            default: requested_rgb = 24'h100000; // Failed/invalid state: red.
        endcase
        if (fault) requested_rgb = 24'h100000; // Fault has display priority.
    end

    reg sending;
    reg [13:0] reset_count;
    reg [5:0] bit_cycle;
    reg [4:0] bits_left;
    reg [23:0] frame_grb;
    wire [5:0] high_last = frame_grb[23] ? ONE_HIGH_LAST : ZERO_HIGH_LAST;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            WS2812 <= 1'b0;
            sending <= 1'b0;
            reset_count <= 14'd0;
            bit_cycle <= 6'd0;
            bits_left <= 5'd23;
            frame_grb <= 24'd0;
        end else if (!sending) begin
            WS2812 <= 1'b0;
            if (reset_count == RESET_CYCLES) begin
                frame_grb <= {requested_rgb[15:8], requested_rgb[23:16], requested_rgb[7:0]};
                reset_count <= 14'd0;
                bit_cycle <= 6'd0;
                bits_left <= 5'd23;
                sending <= 1'b1;
                WS2812 <= 1'b1;
            end else begin
                reset_count <= reset_count + 1'b1;
            end
        end else if (bit_cycle == 6'd63) begin
            bit_cycle <= 6'd0;
            if (bits_left == 0) begin
                sending <= 1'b0;
                reset_count <= 14'd0;
                WS2812 <= 1'b0;
            end else begin
                frame_grb <= {frame_grb[22:0], 1'b0};
                bits_left <= bits_left - 1'b1;
                WS2812 <= 1'b1;
            end
        end else begin
            bit_cycle <= bit_cycle + 1'b1;
            if (bit_cycle == high_last) WS2812 <= 1'b0;
        end
    end

endmodule
