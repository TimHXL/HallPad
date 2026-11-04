`timescale 1ns/1ps
// Original master scale: 6.0x at 100%, 3.0x at default 50%.
// The separate +30% low-key boost is applied per voice in audio_engine_top.
// Wide PCM -> 30 Hz DC/subsonic removal -> smooth gain -> lookahead limiter.
// Below limiting, level scales linearly. Loud chords retain protection margin.
module audio_volume #(parameter integer RAMP_STEP=384)(
    input wire clk,rst_n,sample_tick,
    input wire [6:0] volume_percent,
    input wire signed [23:0] pcm_in,
    output wire signed [15:0] pcm_out,
    output reg [17:0] applied_gain
);
    function [17:0] percent_gain(input [6:0] percent);
        begin case(percent)
                7'd0: percent_gain=18'd0;
                7'd1: percent_gain=18'd1968;
                7'd2: percent_gain=18'd3930;
                7'd3: percent_gain=18'd5898;
                7'd4: percent_gain=18'd7866;
                7'd5: percent_gain=18'd9828;
                7'd6: percent_gain=18'd11796;
                7'd7: percent_gain=18'd13764;
                7'd8: percent_gain=18'd15726;
                7'd9: percent_gain=18'd17694;
                7'd10: percent_gain=18'd19662;
                7'd11: percent_gain=18'd21624;
                7'd12: percent_gain=18'd23592;
                7'd13: percent_gain=18'd25560;
                7'd14: percent_gain=18'd27528;
                7'd15: percent_gain=18'd29490;
                7'd16: percent_gain=18'd31458;
                7'd17: percent_gain=18'd33426;
                7'd18: percent_gain=18'd35388;
                7'd19: percent_gain=18'd37356;
                7'd20: percent_gain=18'd39324;
                7'd21: percent_gain=18'd41286;
                7'd22: percent_gain=18'd43254;
                7'd23: percent_gain=18'd45222;
                7'd24: percent_gain=18'd47184;
                7'd25: percent_gain=18'd49152;
                7'd26: percent_gain=18'd51120;
                7'd27: percent_gain=18'd53082;
                7'd28: percent_gain=18'd55050;
                7'd29: percent_gain=18'd57018;
                7'd30: percent_gain=18'd58980;
                7'd31: percent_gain=18'd60948;
                7'd32: percent_gain=18'd62916;
                7'd33: percent_gain=18'd64878;
                7'd34: percent_gain=18'd66846;
                7'd35: percent_gain=18'd68814;
                7'd36: percent_gain=18'd70776;
                7'd37: percent_gain=18'd72744;
                7'd38: percent_gain=18'd74712;
                7'd39: percent_gain=18'd76680;
                7'd40: percent_gain=18'd78642;
                7'd41: percent_gain=18'd80610;
                7'd42: percent_gain=18'd82578;
                7'd43: percent_gain=18'd84540;
                7'd44: percent_gain=18'd86508;
                7'd45: percent_gain=18'd88476;
                7'd46: percent_gain=18'd90438;
                7'd47: percent_gain=18'd92406;
                7'd48: percent_gain=18'd94374;
                7'd49: percent_gain=18'd96336;
                7'd50: percent_gain=18'd98304;
                7'd51: percent_gain=18'd100272;
                7'd52: percent_gain=18'd102234;
                7'd53: percent_gain=18'd104202;
                7'd54: percent_gain=18'd106170;
                7'd55: percent_gain=18'd108132;
                7'd56: percent_gain=18'd110100;
                7'd57: percent_gain=18'd112068;
                7'd58: percent_gain=18'd114030;
                7'd59: percent_gain=18'd115998;
                7'd60: percent_gain=18'd117966;
                7'd61: percent_gain=18'd119928;
                7'd62: percent_gain=18'd121896;
                7'd63: percent_gain=18'd123864;
                7'd64: percent_gain=18'd125832;
                7'd65: percent_gain=18'd127794;
                7'd66: percent_gain=18'd129762;
                7'd67: percent_gain=18'd131730;
                7'd68: percent_gain=18'd133692;
                7'd69: percent_gain=18'd135660;
                7'd70: percent_gain=18'd137628;
                7'd71: percent_gain=18'd139590;
                7'd72: percent_gain=18'd141558;
                7'd73: percent_gain=18'd143526;
                7'd74: percent_gain=18'd145488;
                7'd75: percent_gain=18'd147456;
                7'd76: percent_gain=18'd149424;
                7'd77: percent_gain=18'd151386;
                7'd78: percent_gain=18'd153354;
                7'd79: percent_gain=18'd155322;
                7'd80: percent_gain=18'd157284;
                7'd81: percent_gain=18'd159252;
                7'd82: percent_gain=18'd161220;
                7'd83: percent_gain=18'd163182;
                7'd84: percent_gain=18'd165150;
                7'd85: percent_gain=18'd167118;
                7'd86: percent_gain=18'd169080;
                7'd87: percent_gain=18'd171048;
                7'd88: percent_gain=18'd173016;
                7'd89: percent_gain=18'd174984;
                7'd90: percent_gain=18'd176946;
                7'd91: percent_gain=18'd178914;
                7'd92: percent_gain=18'd180882;
                7'd93: percent_gain=18'd182844;
                7'd94: percent_gain=18'd184812;
                7'd95: percent_gain=18'd186780;
                7'd96: percent_gain=18'd188742;
                7'd97: percent_gain=18'd190710;
                7'd98: percent_gain=18'd192678;
                7'd99: percent_gain=18'd194640;
                7'd100: percent_gain=18'd196608;
                default:percent_gain=18'd196608;
        endcase end
    endfunction
    wire [17:0] target_gain=percent_gain(volume_percent);
    localparam [17:0] GAIN_STEP=RAMP_STEP;
    reg signed [36:0] input_fixed,dc_state,hp_fixed;
    wire signed [37:0] dc_error=$signed({input_fixed[36],input_fixed})-$signed({dc_state[36],dc_state});
    wire signed [37:0] dc_update_full=$signed({dc_state[36],dc_state})+(dc_error>>>8);
    reg signed [24:0] hp_integer;
    reg signed [43:0] gain_product;
    reg signed [27:0] limiter_input;
    reg limiter_tick;
    reg [2:0] state;
    audio_lookahead_limiter u_limiter(.clk(clk),.rst_n(rst_n),
        .sample_tick(limiter_tick),.pcm_in(limiter_input),.pcm_out(pcm_out),
        .limiter_gain(),.guard_count());
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            applied_gain<=18'd98304;input_fixed<=0;dc_state<=0;hp_fixed<=0;
            hp_integer<=0;gain_product<=0;limiter_input<=0;limiter_tick<=0;state<=0;
        end else begin
            limiter_tick<=0;
            if(sample_tick)begin
                input_fixed<=$signed({pcm_in[23],pcm_in,12'd0});state<=1;
                if(applied_gain<target_gain)
                    applied_gain<=target_gain-applied_gain<=GAIN_STEP ? target_gain : applied_gain+GAIN_STEP;
                else if(applied_gain>target_gain)
                    applied_gain<=applied_gain-target_gain<=GAIN_STEP ? target_gain : applied_gain-GAIN_STEP;
            end else case(state)
                0:begin end
                1:begin
                    hp_fixed<=dc_error[36:0];
                    // Q12 state avoids a quantization deadband near silence.
                    dc_state<=dc_update_full[36:0];state<=2;
                end
                2:begin hp_integer<=hp_fixed[36:12];state<=3;end
                3:begin gain_product<=hp_integer*$signed({1'b0,applied_gain});state<=4;end
                4:begin limiter_input<=gain_product[42:15];state<=5;end
                5:begin limiter_tick<=1;state<=0;end
                default:state<=0;
            endcase
        end
    end
endmodule
