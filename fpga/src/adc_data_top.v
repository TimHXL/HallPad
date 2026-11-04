`timescale 1ns / 1ps

// HallPad V1.0 ADC acquisition subsystem: adc_scan -> adc_data_filter.
// U36/U37/U38 share MOSI/SCLK/active-low CS; their MISO lanes remain separate.
// A clean scan produces 35 Hall samples and two joystick samples.
// ADC_PROFILE=1: assembled board/F407 map, X=U38 CH1 and Y=CH0.
// ADC_PROFILE=0: legacy schematic map, X=U38 CH7 and Y=CH8.
// Chip/channel identity is preserved for downstream calibration/key mapping.
//
// All logic uses clk (default 50 MHz). rst_n asserts asynchronously; release
// it synchronously upstream after the clock and ADC supplies/reference settle.
// bypass must be synchronous to clk; tie it to 1'b0 for normal filtering.
// SCLK_HALF_CYCLES >= 2; IIR shifts must be in 0..8, as in the child modules.
//
// Consume EVERY clk with filtered_valid=1; no ready/backpressure is provided.
// filtered_raw_data belongs to the SAME sample as filtered_data and identity.
// The filter adds three clks after the scanner; this wrapper adds no registers.
// filtered_scan_done/tag_error are independent of filtered_valid. scan_done
// marks a scan boundary even if bad tags suppressed samples in that scan.
//
// Instantiate below the board-level top: filtered_* and bypass are FPGA
// internal signals, not extra board pins. Calibration, key events and audio
// processing consume this interface downstream.
module adc_data_top #(
    parameter integer SCLK_HALF_CYCLES  = 10,
    parameter integer POWERUP_CYCLES    = 50000,
    parameter integer HALL_IIR_SHIFT     = 2,
    parameter integer JOYSTICK_IIR_SHIFT = 4,
    parameter integer ADC_PROFILE        = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,

    input  wire        ADC_MISO_1,
    input  wire        ADC_MISO_2,
    input  wire        ADC_MISO_3,
    output wire        ADC_MOSI,
    output wire        ADC_SCLK,
    output wire        ADC_CS,

    output wire        filtered_valid,
    output wire [1:0]  filtered_chip,
    output wire [3:0]  filtered_channel,
    output wire [11:0] filtered_data,
    output wire [11:0] filtered_raw_data,
    output wire        filtered_is_joystick,
    output wire        filtered_scan_done,
    output wire [2:0]  filtered_tag_error
);

    // Raw samples and undelayed status stay within this subsystem.
    wire        sample_valid;
    wire [1:0]  sample_chip;
    wire [3:0]  sample_channel;
    wire [11:0] sample_data;
    wire        scan_done;
    wire [2:0]  tag_error;

    adc_scan #(
        .SCLK_HALF_CYCLES(SCLK_HALF_CYCLES),
        .POWERUP_CYCLES(POWERUP_CYCLES),
        .ADC_PROFILE(ADC_PROFILE)
    ) u_adc_scan (
        .clk(clk),
        .rst_n(rst_n),
        .ADC_MISO_1(ADC_MISO_1),
        .ADC_MISO_2(ADC_MISO_2),
        .ADC_MISO_3(ADC_MISO_3),
        .ADC_MOSI(ADC_MOSI),
        .ADC_SCLK(ADC_SCLK),
        .ADC_CS(ADC_CS),
        .sample_valid(sample_valid),
        .sample_chip(sample_chip),
        .sample_channel(sample_channel),
        .sample_data(sample_data),
        .tag_error(tag_error),
        .scan_done(scan_done)
    );

    adc_data_filter #(
        .HALL_IIR_SHIFT(HALL_IIR_SHIFT),
        .JOYSTICK_IIR_SHIFT(JOYSTICK_IIR_SHIFT),
        .ADC_PROFILE(ADC_PROFILE)
    ) u_adc_data_filter (
        .clk(clk),
        .rst_n(rst_n),
        .bypass(bypass),
        .sample_valid(sample_valid),
        .sample_chip(sample_chip),
        .sample_channel(sample_channel),
        .sample_data(sample_data),
        .scan_done(scan_done),
        .tag_error(tag_error),
        .filtered_valid(filtered_valid),
        .filtered_chip(filtered_chip),
        .filtered_channel(filtered_channel),
        .filtered_data(filtered_data),
        .filtered_raw_data(filtered_raw_data),
        .filtered_is_joystick(filtered_is_joystick),
        .filtered_scan_done(filtered_scan_done),
        .filtered_tag_error(filtered_tag_error)
    );


endmodule
