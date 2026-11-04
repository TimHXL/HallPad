`timescale 1ns/1ps
// Six shared percussion voices, seven components each. Independent of keyboard
// timbre/pitch selection. One context RAM, one sine ROM, two shared multipliers.
// A full-velocity hit exactly preserves the HallDrum11 modal envelope. Other
// MIDI velocities use (velocity+1)/128, with 127 = unity; master gain is applied
// once by the existing audio_volume/limiter after the keyboard+drum sum.
module drum_synth(
    input wire clk,rst_n,sample_tick,
    input wire event_valid,
    input wire [2:0] event_voice,
    input wire [6:0] event_velocity,
    output wire event_ready,
    output reg signed [23:0] pcm_wide,
    output reg pcm_valid,overrun,
    output wire ready
);
    localparam INIT=0,IDLE=1,READ_WAIT=2,SINE_WAIT=3,SETUP=4,VEL_MUL=5,
        VEL_APPLY=6,MULTIPLY=7,MIX=8,WRITE=9,OUTPUT_PCM=10;
    reg [3:0] state;
    reg [5:0] slot,init_address;
    reg [2:0] voice_id,component;
    (* syn_ramstyle="block_ram" *) reg [55:0] context_memory[0:63];
    reg [55:0] context_read;
    reg [31:0] pitch[0:5];
    reg signed [15:0] previous_noise[0:5];
    reg signed [17:0] noise_lp[0:5];
    reg [31:0] lfsr;
    reg [5:0] pending,frame_hits;
    reg [6:0] pending_velocity[0:5],frame_velocity[0:5];
    reg signed [23:0] accumulator;
    reg [31:0] phase_base,step_work,phase_sum;
    reg [23:0] env_work,env_next;
    reg [15:0] decay_work;
    reg signed [15:0] source_work;
    reg signed [40:0] amplitude_product;
    reg [39:0] decay_product;
    wire [31:0] increment;
    wire [23:0] initial_envelope;
    wire [15:0] decay;
    wire retrigger=frame_hits[voice_id];
    wire [9:0] sine_address=retrigger ? 10'd0:context_read[55:46];
    wire signed [15:0] sine_value;
    wire signed [16:0] noise_delta=$signed({lfsr[31],lfsr[31:16]})-$signed({previous_noise[voice_id][15],previous_noise[voice_id]});
    wire signed [16:0] noise_half=noise_delta>>>1;
    wire signed [18:0] lp_delta=$signed({{3{lfsr[31]}},lfsr[31:16]})-$signed({noise_lp[voice_id][17],noise_lp[voice_id]});
    wire signed [18:0] lp_updated=$signed({noise_lp[voice_id][17],noise_lp[voice_id]})+(lp_delta>>>1);
    wire signed [18:0] shaped_noise=lp_delta>>>1;
    wire signed [40:0] amplitude_scaled=amplitude_product>>>23;
    wire [23:0] envelope_decrement=decay_product[39:16];
    wire [7:0] hit_gain={1'b0,frame_velocity[voice_id]}+8'd1;
    wire [15:0] envelope_factor=state==VEL_MUL ? {8'd0,hit_gain}:decay_work;
    wire accept_event=event_valid && event_ready && event_voice<6 && event_velocity!=0;
    wire [5:0] incoming=accept_event ? (6'b1<<event_voice):6'd0;
    assign ready=state!=INIT;
    assign event_ready=ready;
    drum_parameter_rom u_parameters(.clk(clk),.address(slot),.increment(increment),.initial_envelope(initial_envelope),.decay(decay));
    drum_sine_rom u_sine(.clk(clk),.address(sine_address),.value(sine_value));
    always @(posedge clk) begin
        context_read<=context_memory[slot];
        if(state==INIT) context_memory[init_address]<=0;
        else if(state==WRITE) context_memory[slot]<={phase_sum,env_next};
        amplitude_product<=source_work*$signed({1'b0,env_work});
        decay_product<=env_work*envelope_factor;
    end
    function [31:0] initial_pitch(input [2:0] v);begin case(v)
        0:initial_pitch=32'd2684355;
        1:initial_pitch=32'd13287989;
        3:initial_pitch=32'd3579139;
        default:initial_pitch=0;
    endcase end endfunction
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=INIT;init_address<=0;slot<=0;voice_id<=0;component<=0;
            pending<=0;frame_hits<=0;accumulator<=0;lfsr<=32'h6a1f9235;
            phase_base<=0;step_work<=0;phase_sum<=0;env_work<=0;env_next<=0;decay_work<=0;source_work<=0;
            pcm_wide<=0;pcm_valid<=0;overrun<=0;
            for(i=0;i<6;i=i+1) begin
                pitch[i]<=0;previous_noise[i]<=0;noise_lp[i]<=0;
                pending_velocity[i]<=0;frame_velocity[i]<=0;
            end
        end else begin
            pcm_valid<=0;
            if(accept_event) begin
                pending[event_voice]<=1;
                if(!pending[event_voice] || event_velocity>pending_velocity[event_voice])
                    pending_velocity[event_voice]<=event_velocity;
            end
            if(sample_tick && state!=IDLE && state!=INIT) overrun<=1;
            case(state)
                INIT:if(init_address==41) state<=IDLE;else init_address<=init_address+1'b1;
                IDLE:if(sample_tick) begin
                    frame_hits<=pending|incoming;pending<=0;accumulator<=0;
                    for(i=0;i<6;i=i+1) begin
                        if(incoming[i] && (!pending[i] || event_velocity>pending_velocity[i])) frame_velocity[i]<=event_velocity;
                        else frame_velocity[i]<=pending_velocity[i];
                    end
                    slot<=0;voice_id<=0;component<=0;state<=READ_WAIT;
                end
                READ_WAIT:state<=SINE_WAIT;
                SINE_WAIT:state<=SETUP;
                SETUP:begin
                    env_work<=retrigger ? initial_envelope:context_read[23:0];
                    decay_work<=decay;
                    phase_base<=retrigger ? 32'd0:context_read[55:24];
                    step_work<=increment;
                    if(component==0) step_work<=increment+(retrigger ? initial_pitch(voice_id):pitch[voice_id]);
                    if(component==6) begin
                        if(voice_id==0) source_work<=shaped_noise[15:0];
                        else if(voice_id==1 || voice_id==3) source_work<=lfsr[31:16];
                        else source_work<=noise_half[15:0];
                        previous_noise[voice_id]<=lfsr[31:16];noise_lp[voice_id]<=lp_updated[17:0];
                        lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                        if(retrigger) pitch[voice_id]<=initial_pitch(voice_id);
                        else if(pitch[voice_id]>256)begin
                            if(voice_id==1) pitch[voice_id]<=pitch[voice_id]-(pitch[voice_id]>>7)-(pitch[voice_id]>>10)-(pitch[voice_id]>>12)-1'b1;
                            else pitch[voice_id]<=pitch[voice_id]-(pitch[voice_id]>>8)-1'b1;
                        end
                        else pitch[voice_id]<=0;
                    end else source_work<=sine_value;
                    state<=retrigger ? VEL_MUL:MULTIPLY;
                end
                VEL_MUL:state<=VEL_APPLY;
                VEL_APPLY:begin env_work<=decay_product[30:7];state<=MULTIPLY;end
                MULTIPLY:begin phase_sum<=phase_base+step_work;state<=MIX;end
                MIX:begin
                    accumulator<=accumulator+amplitude_scaled[23:0];
                    if(env_work==0 || env_work<=envelope_decrement+1'b1) env_next<=0;
                    else env_next<=env_work-envelope_decrement-1'b1;
                    state<=WRITE;
                end
                WRITE:if(slot==41) state<=OUTPUT_PCM;
                else begin
                    slot<=slot+1'b1;
                    if(component==6) begin component<=0;voice_id<=voice_id+1'b1;end
                    else component<=component+1'b1;
                    state<=READ_WAIT;
                end
                OUTPUT_PCM:begin pcm_wide<=accumulator;pcm_valid<=1;state<=IDLE;end
                default:begin state<=INIT;init_address<=0;pcm_wide<=0;overrun<=1;end
            endcase
        end
    end
endmodule
