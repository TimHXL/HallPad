`timescale 1ns/1ps
// Musical reverb and metronome. Fixed latency at every reverb setting.
// Wet return is doubled; the dry attack and feedback decay are unchanged.
// All DSP uses wide PCM; final peak protection follows the master volume.
module audio_effects(input wire clk,rst_n,sample_tick,
    input wire external_mode,external_trigger,external_accent,external_clear,
    input wire signed [23:0] pcm_in,
    input wire [6:0] echo_percent,
    input wire metro_enable,input wire [3:0] metro_beats,metro_unit,
    input wire [7:0] metro_bpm,output reg signed [23:0] pcm_out,
    output reg beat_pulse,beat_accent);
    wire signed [23:0] room,room_mix;
    music_reverb u_reverb(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(pcm_in),.pcm_out(room));
    music_reverb_mix u_reverb_mix(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.percent(echo_percent),.dry_in(pcm_in),.wet_in(room),.pcm_out(room_mix));
    reg [23:0] beat_acc;
    reg [3:0] beat_number,last_beats,last_unit;
    reg [7:0] last_bpm;
    reg last_metro_enable,click_accent;
    wire [11:0] tempo_step=metro_bpm*metro_unit;
    reg [31:0] click_phase;
    reg [15:0] click_env;
    wire signed [15:0] click_wave;
    piano35_sine_lut u_click_wave(.phase_acc(click_phase),.sine_out(click_wave));
    reg signed [32:0] click_product;
    reg signed [23:0] click_sample,music_sample;
    reg [1:0] state;
    wire signed [25:0] mixed=$signed({{2{music_sample[23]}},music_sample})+$signed({{2{click_sample[23]}},click_sample});
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            beat_acc<=0;beat_number<=0;last_beats<=4;last_unit<=4;last_bpm<=120;last_metro_enable<=0;
            click_phase<=0;click_env<=0;click_accent<=0;beat_pulse<=0;beat_accent<=0;
            click_product<=0;click_sample<=0;music_sample<=0;pcm_out<=0;state<=0;
        end else begin
            beat_pulse<=0;
            if(sample_tick)begin
                music_sample<=room_mix;click_product<=click_wave*$signed({1'b0,click_env});state<=1;
                last_metro_enable<=metro_enable;last_beats<=metro_beats;last_unit<=metro_unit;last_bpm<=metro_bpm;
                click_phase<=click_phase+(click_accent ? 32'd178956971 : 32'd89478485);
                click_env<=click_env>16'd128 ? click_env-16'd128 : 16'd0;
                if(external_clear===1'b1)begin beat_acc<=0;beat_number<=0;click_env<=0;click_product<=0;end
                else if(external_mode===1'b1)begin
                    last_metro_enable<=0;beat_acc<=0;beat_number<=0;
                    if(external_trigger===1'b1)begin click_phase<=0;click_env<=16'hffff;click_accent<=external_accent;beat_pulse<=1;beat_accent<=external_accent;end
                end
                else if(!metro_enable)begin beat_acc<=0;beat_number<=0;end
                else if(!last_metro_enable || last_beats!=metro_beats || last_unit!=metro_unit || last_bpm!=metro_bpm)begin
                    beat_acc<=0;beat_number<=0;click_phase<=0;click_env<=16'hffff;click_accent<=1;beat_pulse<=1;beat_accent<=1;
                end else if(beat_acc+{12'd0,tempo_step}>=24'd11520000)begin
                    beat_acc<=beat_acc+{12'd0,tempo_step}-24'd11520000;
                    beat_number<=beat_number>=metro_beats-4'd1 ? 4'd0 : beat_number+4'd1;
                    click_accent<=beat_number>=metro_beats-4'd1;
                    beat_accent<=beat_number>=metro_beats-4'd1;
                    beat_pulse<=1;click_env<=16'hffff;click_phase<=0;
                end else beat_acc<=beat_acc+{12'd0,tempo_step};

            end else case(state)
                1:begin click_sample<=click_accent ? {{10{click_product[32]}},click_product[32:19]}:{{11{click_product[32]}},click_product[32:20]};state<=2;end
                2:begin
                    pcm_out<=mixed>26'sd8388607 ? 24'sd8388607 : mixed< -26'sd8388608 ? -24'sd8388608 : mixed[23:0];state<=0;
                end
                default:state<=0;
            endcase
            // Clear between audio samples too; preserve music pipeline latency.
            if(external_clear===1'b1)begin beat_acc<=0;beat_number<=0;last_metro_enable<=0;click_env<=0;click_phase<=0;click_product<=0;click_sample<=0;beat_pulse<=0;end
        end
    end
endmodule

// Add 2x the previous wet return at the same setting; dry stays at unity.
// 328 approximates 32768/100 to <0.1%; the endpoint is clamped exactly.
// The fixed pipeline and ~21 ms gain slew avoid bypass and knob discontinuities.
module music_reverb_mix(input wire clk,rst_n,sample_tick,
    input wire [6:0] percent,input wire signed [23:0] dry_in,wet_in,
    output reg signed [23:0] pcm_out);
    wire [15:0] wet_target=percent>=100 ? 16'd32768:percent*16'd328;
    reg [15:0] wet_gain;
    reg [1:0] state;
    reg signed [23:0] dry,wet;
    reg signed [40:0] product;
    reg signed [41:0] mixed;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin wet_gain<=0;state<=0;dry<=0;wet<=0;product<=0;mixed<=0;pcm_out<=0;end
        else if(sample_tick)begin
            dry<=dry_in;wet<=wet_in;state<=1;
            if(wet_gain<wet_target)wet_gain<=wet_target-wet_gain<=32 ? wet_target:wet_gain+16'd32;
            else if(wet_gain>wet_target)wet_gain<=wet_gain-wet_target<=32 ? wet_target:wet_gain-16'd32;
        end else case(state)
            1:begin product<=wet*$signed({1'b0,wet_gain});state<=2;end
            2:begin mixed<=$signed({{18{dry[23]}},dry})+(product>>>14);state<=3;end
            3:begin pcm_out<=mixed>8388607 ? 24'sd8388607:mixed< -8388608 ? -24'sd8388608:mixed[23:0];state<=0;end
            default:state<=0;
        endcase
    end
endmodule
