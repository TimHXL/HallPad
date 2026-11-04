`timescale 1ns / 1ps

// Runtime brightness/mode layer for the full-scale 35-pixel ripple palette.
// One 8x6 multiplier is reused for all 105 RGB channels. Each pass snapshots
// pixels, brightness and mode together, then publishes all 840 bits atomically.
// Optional practice guidance snapshots only a target mask and two note flags.
// A pass takes 106 clocks (one snapshot + 105 channels); outputs remain stable
// in between. The downstream RGB serializer also snapshots complete frames.
// Brightness uses the original contract floor(channel * brightness / 255),
// clamped to 0..32. Mode 0=ripple, 1=fixed INITIAL_COLOR, 2/3=off.
// Ripple generation is independent: hiding it does not discard pending waves.
module keyboard_light_runtime #(
    parameter [2:0] INITIAL_COLOR = 3'd0,parameter integer USE_CUSTOM_COLOR=0,
    parameter integer USE_RIPPLE_ENVELOPE=0,USE_PALETTE_SOURCE=0,USE_PRACTICE_GUIDE=0
) (
    input wire clk,
    input wire rst_n,
    input wire [839:0] ripple_pixels,input wire [23:0] solid_rgb,
    input wire [104:0] palette_indices,
    input wire practice_active,practice_long,practice_holding,
    input wire [34:0] practice_mask,practice_yellow,practice_green,practice_red,
    input wire [314:0] ripple_intensities,
    input wire [5:0] brightness,
    input wire [1:0] light_mode,
    output reg [839:0] pixels_rgb,
    output reg frame_update
);
    function [23:0] palette_rgb;
        input [2:0] index;
        begin
            case (index)
                0: palette_rgb = 24'h0000FF;
                1: palette_rgb = 24'h00FFFF;
                2: palette_rgb = 24'h00FF00;
                3: palette_rgb = 24'hFFFF00;
                4: palette_rgb = 24'hFF8000;
                5: palette_rgb = 24'hFF0000;
                6: palette_rgb = 24'h8000FF;
                7: palette_rgb = 24'hFF0080;
                default: palette_rgb = 24'h0000FF;
            endcase
        end
    endfunction
    localparam [23:0] SOLID_RGB = palette_rgb(INITIAL_COLOR);
    reg active;
    reg [6:0] channel_index;
    reg [5:0] frame_brightness;
    reg [1:0] component;
    reg [839:0] source_pixels;
    // The top-level ripple has eight fixed colors: snapshot 105 palette bits
    // instead of 840 decoded RGB bits. Generic full-RGB mode remains available.
    reg [104:0] frame_palette;
    reg [23:0] frame_solid;
    reg [1:0] frame_mode;
    reg frame_practice,frame_long,frame_holding;
    reg [34:0] frame_guide,frame_yellow,frame_green,frame_red;
    reg [5:0] guide_brightness;
    wire [23:0] palette_pixel=palette_rgb(frame_palette[2:0]);
    wire [23:0] current_pixel=frame_mode==0 ? palette_pixel:frame_mode==1 ? frame_solid:24'd0;
    wire [7:0] palette_channel=component==0 ? current_pixel[7:0]:component==1 ? current_pixel[15:8]:current_pixel[23:16];
    reg [839:0] building_pixels;
    reg [314:0] frame_intensities;
    wire [16:0] envelope_product = (USE_PALETTE_SOURCE!=0 ? palette_channel:source_pixels[7:0]) * frame_intensities[8:0];
    wire [7:0] envelope_channel = envelope_product[15:8];
    wire [13:0] product = envelope_channel * frame_brightness;
    // For 0<=p<=8160, floor(p/255)=(p+1+floor(p/256))>>8 exactly.
    wire [14:0] divide_sum = {1'b0, product} + 15'd1 +
                             {9'd0, product[13:8]};
    wire [7:0] scaled_channel = {1'b0, divide_sum[14:8]};
    // Short=cyan, long=amber, held=green. One shared byte decoder
    // replaces 35 parallel RGB overlays; all non-target pixels stay black.
    wire [7:0] guide_level={2'd0,guide_brightness};
    wire [7:0] guide_component=frame_holding ? (component==1 ? guide_level:8'd0):
        frame_long ? (component==2 ? guide_level:component==1 ? (guide_level>>1):8'd0):
        (component==2 ? 8'd0:guide_level);
    wire [7:0] guided_channel=frame_red[0] ? (component==2 ? guide_level:8'd0):
        frame_yellow[0] ? (component==1 || component==2 ? guide_level:8'd0):
        frame_green[0] ? (component==1 ? guide_level:8'd0):
        frame_guide[0] ? guide_component:8'd0;
    wire [7:0] output_channel=USE_PRACTICE_GUIDE!=0 && frame_practice ? guided_channel:scaled_channel;
    wire [839:0] next_pixels = {output_channel, building_pixels[839:8]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixels_rgb <= 840'd0;
            frame_update <= 0;
            active <= 0;
            channel_index <= 0;
            frame_brightness <= 0;
            source_pixels <= 0;frame_palette<=0;frame_solid<=0;frame_mode<=0;frame_practice<=0;frame_long<=0;frame_holding<=0;frame_guide<=0;frame_yellow<=0;frame_green<=0;frame_red<=0;guide_brightness<=8;
            building_pixels <= 0;
            frame_intensities <= {35{9'd256}};
            component <= 0;
        end else begin
            frame_update <= 0;
            if (!active) begin
                frame_practice<=USE_PRACTICE_GUIDE!=0 && practice_active;
                frame_yellow<=practice_yellow;frame_green<=practice_green;frame_red<=practice_red;frame_guide<=practice_mask;frame_long<=practice_long;frame_holding<=practice_holding;
                guide_brightness<=brightness<8 ? 6'd8:brightness>32 ? 6'd32:brightness;
                if(USE_PALETTE_SOURCE!=0)begin
                    frame_palette<=palette_indices;
                    frame_solid<=USE_CUSTOM_COLOR!=0 ? solid_rgb:SOLID_RGB;
                    frame_mode<=light_mode;
                end else case (light_mode)
                    2'd0: source_pixels <= ripple_pixels;
                    2'd1: source_pixels <= {35{USE_CUSTOM_COLOR!=0 ? solid_rgb:SOLID_RGB}};
                    default: source_pixels <= 840'd0;
                endcase
                frame_brightness <= (brightness > 32) ? 6'd32 : brightness;
                frame_intensities <= USE_RIPPLE_ENVELOPE != 0 && light_mode == 0 ?
                                     ripple_intensities : {35{9'd256}};
                component <= 0;
                building_pixels <= 0;
                channel_index <= 0;
                active <= 1;
            end else begin
                if(USE_PALETTE_SOURCE==0)source_pixels <= {8'd0, source_pixels[839:8]};
                if (component == 2) begin
                    frame_guide<={1'b0,frame_guide[34:1]};frame_yellow<={1'b0,frame_yellow[34:1]};frame_green<={1'b0,frame_green[34:1]};frame_red<={1'b0,frame_red[34:1]};
                    component <= 0;
                    if(USE_PALETTE_SOURCE!=0)frame_palette<={3'd0,frame_palette[104:3]};
                    frame_intensities <= {9'd0,frame_intensities[314:9]};
                end else component <= component + 1'b1;
                building_pixels <= next_pixels;
                if (channel_index == 104) begin
                    pixels_rgb <= next_pixels;
                    frame_update <= 1;
                    active <= 0;
                end else channel_index <= channel_index + 1'b1;
            end
        end
    end

endmodule

