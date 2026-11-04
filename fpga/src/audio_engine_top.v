`timescale 1ns/1ps
// 35 independent physical-key voices, two context-switched synthesis lanes.
// Each lane visits 18 slots; no key steals another key's release tail.
// 44 render clocks cover the restored original piano and scratch pipelines. Context RAM
// stores persistent voice state, plus retrigger/minimum-gate state. Shared
// waveform/multiplier scratch pipelines refill within each slot.
// The whole frame fits below 1000 clk cycles; final limiting follows all effects
// versus the 1041/1042 available at 50 MHz / 48 kHz.
module audio_engine_top #(parameter integer USE_EXTERNAL_TICK=0,USER_ENVELOPE=0)(
    input wire clk,rst_n,external_sample_tick,
    input wire [21:0] pitch_gain,
    input wire key_config_valid,input wire [251:0] key_midi,input wire [143:0] key_timbre,
    input wire [3:0] timbre_sel,
    input wire [215:0] voice_note,
    input wire [251:0] voice_velocity,
    input wire [35:0] voice_gate,input wire [323:0] user_gain,
    input wire [287:0] voice_revision,
    input wire probe_armed,input wire [5:0] probe_key,input wire [7:0] probe_revision,
    output wire probe_rendered,
    output reg [35:0] voice_active,
    output reg signed [15:0] pcm_out,
    output reg signed [23:0] pcm_wide,
    output wire pcm_valid,
    output reg frame_overrun,
    output wire [3:0] active_timbre_out,
    output wire timbre_switching,
    output wire engine_ready
);
    function [31:0] midi_increment(input [6:0] m);begin case(m)
        7'd0:midi_increment=32'd731558;
        7'd1:midi_increment=32'd775059;
        7'd2:midi_increment=32'd821146;
        7'd3:midi_increment=32'd869974;
        7'd4:midi_increment=32'd921705;
        7'd5:midi_increment=32'd976513;
        7'd6:midi_increment=32'd1034579;
        7'd7:midi_increment=32'd1096099;
        7'd8:midi_increment=32'd1161276;
        7'd9:midi_increment=32'd1230329;
        7'd10:midi_increment=32'd1303488;
        7'd11:midi_increment=32'd1380998;
        7'd12:midi_increment=32'd1463116;
        7'd13:midi_increment=32'd1550118;
        7'd14:midi_increment=32'd1642292;
        7'd15:midi_increment=32'd1739948;
        7'd16:midi_increment=32'd1843411;
        7'd17:midi_increment=32'd1953026;
        7'd18:midi_increment=32'd2069159;
        7'd19:midi_increment=32'd2192197;
        7'd20:midi_increment=32'd2322552;
        7'd21:midi_increment=32'd2460658;
        7'd22:midi_increment=32'd2606977;
        7'd23:midi_increment=32'd2761996;
        7'd24:midi_increment=32'd2926232;
        7'd25:midi_increment=32'd3100235;
        7'd26:midi_increment=32'd3284585;
        7'd27:midi_increment=32'd3479896;
        7'd28:midi_increment=32'd3686822;
        7'd29:midi_increment=32'd3906052;
        7'd30:midi_increment=32'd4138318;
        7'd31:midi_increment=32'd4384395;
        7'd32:midi_increment=32'd4645104;
        7'd33:midi_increment=32'd4921317;
        7'd34:midi_increment=32'd5213953;
        7'd35:midi_increment=32'd5523991;
        7'd36:midi_increment=32'd5852465;
        7'd37:midi_increment=32'd6200470;
        7'd38:midi_increment=32'd6569170;
        7'd39:midi_increment=32'd6959793;
        7'd40:midi_increment=32'd7373644;
        7'd41:midi_increment=32'd7812103;
        7'd42:midi_increment=32'd8276635;
        7'd43:midi_increment=32'd8768789;
        7'd44:midi_increment=32'd9290209;
        7'd45:midi_increment=32'd9842633;
        7'd46:midi_increment=32'd10427907;
        7'd47:midi_increment=32'd11047982;
        7'd48:midi_increment=32'd11704930;
        7'd49:midi_increment=32'd12400941;
        7'd50:midi_increment=32'd13138339;
        7'd51:midi_increment=32'd13919586;
        7'd52:midi_increment=32'd14747287;
        7'd53:midi_increment=32'd15624207;
        7'd54:midi_increment=32'd16553270;
        7'd55:midi_increment=32'd17537579;
        7'd56:midi_increment=32'd18580418;
        7'd57:midi_increment=32'd19685267;
        7'd58:midi_increment=32'd20855814;
        7'd59:midi_increment=32'd22095965;
        7'd60:midi_increment=32'd23409859;
        7'd61:midi_increment=32'd24801882;
        7'd62:midi_increment=32'd26276679;
        7'd63:midi_increment=32'd27839171;
        7'd64:midi_increment=32'd29494575;
        7'd65:midi_increment=32'd31248413;
        7'd66:midi_increment=32'd33106541;
        7'd67:midi_increment=32'd35075158;
        7'd68:midi_increment=32'd37160835;
        7'd69:midi_increment=32'd39370534;
        7'd70:midi_increment=32'd41711627;
        7'd71:midi_increment=32'd44191930;
        7'd72:midi_increment=32'd46819719;
        7'd73:midi_increment=32'd49603764;
        7'd74:midi_increment=32'd52553357;
        7'd75:midi_increment=32'd55678342;
        7'd76:midi_increment=32'd58989149;
        7'd77:midi_increment=32'd62496826;
        7'd78:midi_increment=32'd66213081;
        7'd79:midi_increment=32'd70150316;
        7'd80:midi_increment=32'd74321671;
        7'd81:midi_increment=32'd78741067;
        7'd82:midi_increment=32'd83423255;
        7'd83:midi_increment=32'd88383859;
        7'd84:midi_increment=32'd93639437;
        7'd85:midi_increment=32'd99207528;
        7'd86:midi_increment=32'd105106715;
        7'd87:midi_increment=32'd111356685;
        7'd88:midi_increment=32'd117978298;
        7'd89:midi_increment=32'd124993653;
        7'd90:midi_increment=32'd132426162;
        7'd91:midi_increment=32'd140300631;
        7'd92:midi_increment=32'd148643341;
        7'd93:midi_increment=32'd157482134;
        7'd94:midi_increment=32'd166846509;
        7'd95:midi_increment=32'd176767719;
        7'd96:midi_increment=32'd187278874;
        7'd97:midi_increment=32'd198415056;
        7'd98:midi_increment=32'd210213429;
        7'd99:midi_increment=32'd222713370;
        7'd100:midi_increment=32'd235956596;
        7'd101:midi_increment=32'd249987305;
        7'd102:midi_increment=32'd264852324;
        7'd103:midi_increment=32'd280601263;
        7'd104:midi_increment=32'd297286682;
        7'd105:midi_increment=32'd314964268;
        7'd106:midi_increment=32'd333693018;
        7'd107:midi_increment=32'd353535438;
        7'd108:midi_increment=32'd374557749;
        7'd109:midi_increment=32'd396830112;
        7'd110:midi_increment=32'd420426858;
        7'd111:midi_increment=32'd445426740;
        7'd112:midi_increment=32'd471913192;
        7'd113:midi_increment=32'd499974611;
        7'd114:midi_increment=32'd529704648;
        7'd115:midi_increment=32'd561202526;
        7'd116:midi_increment=32'd594573365;
        7'd117:midi_increment=32'd629928537;
        7'd118:midi_increment=32'd667386037;
        7'd119:midi_increment=32'd707070876;
        7'd120:midi_increment=32'd749115498;
        7'd121:midi_increment=32'd793660223;
        7'd122:midi_increment=32'd840853716;
        7'd123:midi_increment=32'd890853480;
        7'd124:midi_increment=32'd943826385;
        7'd125:midi_increment=32'd999949222;
        7'd126:midi_increment=32'd1059409297;
        7'd127:midi_increment=32'd1122405052;
    endcase end endfunction
    function [5:0] midi_profile(input [6:0] m);begin case(m)
        7'd0:midi_profile=6'd1;
        7'd1:midi_profile=6'd1;
        7'd2:midi_profile=6'd1;
        7'd3:midi_profile=6'd1;
        7'd4:midi_profile=6'd1;
        7'd5:midi_profile=6'd1;
        7'd6:midi_profile=6'd1;
        7'd7:midi_profile=6'd1;
        7'd8:midi_profile=6'd1;
        7'd9:midi_profile=6'd1;
        7'd10:midi_profile=6'd1;
        7'd11:midi_profile=6'd1;
        7'd12:midi_profile=6'd1;
        7'd13:midi_profile=6'd1;
        7'd14:midi_profile=6'd1;
        7'd15:midi_profile=6'd1;
        7'd16:midi_profile=6'd1;
        7'd17:midi_profile=6'd1;
        7'd18:midi_profile=6'd1;
        7'd19:midi_profile=6'd1;
        7'd20:midi_profile=6'd1;
        7'd21:midi_profile=6'd1;
        7'd22:midi_profile=6'd1;
        7'd23:midi_profile=6'd1;
        7'd24:midi_profile=6'd1;
        7'd25:midi_profile=6'd1;
        7'd26:midi_profile=6'd1;
        7'd27:midi_profile=6'd1;
        7'd28:midi_profile=6'd1;
        7'd29:midi_profile=6'd1;
        7'd30:midi_profile=6'd1;
        7'd31:midi_profile=6'd1;
        7'd32:midi_profile=6'd1;
        7'd33:midi_profile=6'd1;
        7'd34:midi_profile=6'd1;
        7'd35:midi_profile=6'd1;
        7'd36:midi_profile=6'd1;
        7'd37:midi_profile=6'd1;
        7'd38:midi_profile=6'd2;
        7'd39:midi_profile=6'd2;
        7'd40:midi_profile=6'd3;
        7'd41:midi_profile=6'd4;
        7'd42:midi_profile=6'd4;
        7'd43:midi_profile=6'd5;
        7'd44:midi_profile=6'd5;
        7'd45:midi_profile=6'd6;
        7'd46:midi_profile=6'd6;
        7'd47:midi_profile=6'd7;
        7'd48:midi_profile=6'd8;
        7'd49:midi_profile=6'd8;
        7'd50:midi_profile=6'd9;
        7'd51:midi_profile=6'd9;
        7'd52:midi_profile=6'd10;
        7'd53:midi_profile=6'd11;
        7'd54:midi_profile=6'd11;
        7'd55:midi_profile=6'd12;
        7'd56:midi_profile=6'd12;
        7'd57:midi_profile=6'd13;
        7'd58:midi_profile=6'd13;
        7'd59:midi_profile=6'd14;
        7'd60:midi_profile=6'd15;
        7'd61:midi_profile=6'd15;
        7'd62:midi_profile=6'd16;
        7'd63:midi_profile=6'd16;
        7'd64:midi_profile=6'd17;
        7'd65:midi_profile=6'd18;
        7'd66:midi_profile=6'd18;
        7'd67:midi_profile=6'd19;
        7'd68:midi_profile=6'd19;
        7'd69:midi_profile=6'd20;
        7'd70:midi_profile=6'd20;
        7'd71:midi_profile=6'd21;
        7'd72:midi_profile=6'd22;
        7'd73:midi_profile=6'd22;
        7'd74:midi_profile=6'd23;
        7'd75:midi_profile=6'd23;
        7'd76:midi_profile=6'd24;
        7'd77:midi_profile=6'd25;
        7'd78:midi_profile=6'd25;
        7'd79:midi_profile=6'd26;
        7'd80:midi_profile=6'd26;
        7'd81:midi_profile=6'd27;
        7'd82:midi_profile=6'd27;
        7'd83:midi_profile=6'd28;
        7'd84:midi_profile=6'd29;
        7'd85:midi_profile=6'd29;
        7'd86:midi_profile=6'd30;
        7'd87:midi_profile=6'd30;
        7'd88:midi_profile=6'd31;
        7'd89:midi_profile=6'd32;
        7'd90:midi_profile=6'd32;
        7'd91:midi_profile=6'd33;
        7'd92:midi_profile=6'd33;
        7'd93:midi_profile=6'd34;
        7'd94:midi_profile=6'd34;
        7'd95:midi_profile=6'd35;
        7'd96:midi_profile=6'd35;
        7'd97:midi_profile=6'd35;
        7'd98:midi_profile=6'd35;
        7'd99:midi_profile=6'd35;
        7'd100:midi_profile=6'd35;
        7'd101:midi_profile=6'd35;
        7'd102:midi_profile=6'd35;
        7'd103:midi_profile=6'd35;
        7'd104:midi_profile=6'd35;
        7'd105:midi_profile=6'd35;
        7'd106:midi_profile=6'd35;
        7'd107:midi_profile=6'd35;
        7'd108:midi_profile=6'd35;
        7'd109:midi_profile=6'd35;
        7'd110:midi_profile=6'd35;
        7'd111:midi_profile=6'd35;
        7'd112:midi_profile=6'd35;
        7'd113:midi_profile=6'd35;
        7'd114:midi_profile=6'd35;
        7'd115:midi_profile=6'd35;
        7'd116:midi_profile=6'd35;
        7'd117:midi_profile=6'd35;
        7'd118:midi_profile=6'd35;
        7'd119:midi_profile=6'd35;
        7'd120:midi_profile=6'd35;
        7'd121:midi_profile=6'd35;
        7'd122:midi_profile=6'd35;
        7'd123:midi_profile=6'd35;
        7'd124:midi_profile=6'd35;
        7'd125:midi_profile=6'd35;
        7'd126:midi_profile=6'd35;
        7'd127:midi_profile=6'd35;
    endcase end endfunction
    function [9:0] midi_string_length(input [6:0] m);begin case(m)
        7'd0:midi_string_length=10'd1023;
        7'd1:midi_string_length=10'd1023;
        7'd2:midi_string_length=10'd1023;
        7'd3:midi_string_length=10'd1023;
        7'd4:midi_string_length=10'd1023;
        7'd5:midi_string_length=10'd1023;
        7'd6:midi_string_length=10'd1023;
        7'd7:midi_string_length=10'd1023;
        7'd8:midi_string_length=10'd1023;
        7'd9:midi_string_length=10'd1023;
        7'd10:midi_string_length=10'd1023;
        7'd11:midi_string_length=10'd1023;
        7'd12:midi_string_length=10'd1023;
        7'd13:midi_string_length=10'd1023;
        7'd14:midi_string_length=10'd1023;
        7'd15:midi_string_length=10'd1023;
        7'd16:midi_string_length=10'd1023;
        7'd17:midi_string_length=10'd1023;
        7'd18:midi_string_length=10'd1023;
        7'd19:midi_string_length=10'd1023;
        7'd20:midi_string_length=10'd1023;
        7'd21:midi_string_length=10'd1023;
        7'd22:midi_string_length=10'd1023;
        7'd23:midi_string_length=10'd1023;
        7'd24:midi_string_length=10'd1023;
        7'd25:midi_string_length=10'd1023;
        7'd26:midi_string_length=10'd1023;
        7'd27:midi_string_length=10'd1023;
        7'd28:midi_string_length=10'd1023;
        7'd29:midi_string_length=10'd1023;
        7'd30:midi_string_length=10'd1023;
        7'd31:midi_string_length=10'd979;
        7'd32:midi_string_length=10'd924;
        7'd33:midi_string_length=10'd872;
        7'd34:midi_string_length=10'd823;
        7'd35:midi_string_length=10'd777;
        7'd36:midi_string_length=10'd733;
        7'd37:midi_string_length=10'd692;
        7'd38:midi_string_length=10'd653;
        7'd39:midi_string_length=10'd616;
        7'd40:midi_string_length=10'd581;
        7'd41:midi_string_length=10'd549;
        7'd42:midi_string_length=10'd518;
        7'd43:midi_string_length=10'd489;
        7'd44:midi_string_length=10'd461;
        7'd45:midi_string_length=10'd435;
        7'd46:midi_string_length=10'd411;
        7'd47:midi_string_length=10'd388;
        7'd48:midi_string_length=10'd366;
        7'd49:midi_string_length=10'd345;
        7'd50:midi_string_length=10'd326;
        7'd51:midi_string_length=10'd308;
        7'd52:midi_string_length=10'd290;
        7'd53:midi_string_length=10'd274;
        7'd54:midi_string_length=10'd258;
        7'd55:midi_string_length=10'd244;
        7'd56:midi_string_length=10'd230;
        7'd57:midi_string_length=10'd217;
        7'd58:midi_string_length=10'd205;
        7'd59:midi_string_length=10'd193;
        7'd60:midi_string_length=10'd182;
        7'd61:midi_string_length=10'd172;
        7'd62:midi_string_length=10'd162;
        7'd63:midi_string_length=10'd153;
        7'd64:midi_string_length=10'd145;
        7'd65:midi_string_length=10'd136;
        7'd66:midi_string_length=10'd129;
        7'd67:midi_string_length=10'd121;
        7'd68:midi_string_length=10'd115;
        7'd69:midi_string_length=10'd108;
        7'd70:midi_string_length=10'd102;
        7'd71:midi_string_length=10'd96;
        7'd72:midi_string_length=10'd91;
        7'd73:midi_string_length=10'd86;
        7'd74:midi_string_length=10'd81;
        7'd75:midi_string_length=10'd76;
        7'd76:midi_string_length=10'd72;
        7'd77:midi_string_length=10'd68;
        7'd78:midi_string_length=10'd64;
        7'd79:midi_string_length=10'd60;
        7'd80:midi_string_length=10'd57;
        7'd81:midi_string_length=10'd54;
        7'd82:midi_string_length=10'd50;
        7'd83:midi_string_length=10'd48;
        7'd84:midi_string_length=10'd45;
        7'd85:midi_string_length=10'd42;
        7'd86:midi_string_length=10'd40;
        7'd87:midi_string_length=10'd38;
        7'd88:midi_string_length=10'd35;
        7'd89:midi_string_length=10'd33;
        7'd90:midi_string_length=10'd31;
        7'd91:midi_string_length=10'd30;
        7'd92:midi_string_length=10'd28;
        7'd93:midi_string_length=10'd26;
        7'd94:midi_string_length=10'd25;
        7'd95:midi_string_length=10'd23;
        7'd96:midi_string_length=10'd22;
        7'd97:midi_string_length=10'd21;
        7'd98:midi_string_length=10'd19;
        7'd99:midi_string_length=10'd18;
        7'd100:midi_string_length=10'd17;
        7'd101:midi_string_length=10'd16;
        7'd102:midi_string_length=10'd15;
        7'd103:midi_string_length=10'd14;
        7'd104:midi_string_length=10'd13;
        7'd105:midi_string_length=10'd13;
        7'd106:midi_string_length=10'd12;
        7'd107:midi_string_length=10'd11;
        7'd108:midi_string_length=10'd10;
        7'd109:midi_string_length=10'd10;
        7'd110:midi_string_length=10'd9;
        7'd111:midi_string_length=10'd9;
        7'd112:midi_string_length=10'd8;
        7'd113:midi_string_length=10'd8;
        7'd114:midi_string_length=10'd7;
        7'd115:midi_string_length=10'd7;
        7'd116:midi_string_length=10'd6;
        7'd117:midi_string_length=10'd6;
        7'd118:midi_string_length=10'd5;
        7'd119:midi_string_length=10'd5;
        7'd120:midi_string_length=10'd5;
        7'd121:midi_string_length=10'd4;
        7'd122:midi_string_length=10'd4;
        7'd123:midi_string_length=10'd4;
        7'd124:midi_string_length=10'd4;
        7'd125:midi_string_length=10'd3;
        7'd126:midi_string_length=10'd3;
        7'd127:midi_string_length=10'd3;
    endcase end endfunction
    localparam integer CORE_BITS=1027,CONTEXT_BITS=CORE_BITS+10;
    localparam [4:0] WAIT=0,READ=1,LOAD=2,PREP=3,TICK=4,RENDER=5,
        STORE=6,BASS_ENV=7,BASS_VEL=8,ACCUMULATE=9,DIVIDE=10,
        GAIN=11,MULTIPLY=12,OUTPUT=13,CLEAR=14,
        GAIN_TARGET=15,GAIN_DELTA=16,PRODUCT=17,USER_GAIN=18;
    reg [4:0] state;
    reg [4:0] slot,clear_slot;
    reg clear_half;
    reg [5:0] render_count;
    reg [3:0] active_timbre;
    reg [6:0] sound_gain,frame_sound_gain;
    wire sample_tick;
    generate if(USE_EXTERNAL_TICK!=0)begin:g_external
        assign sample_tick=external_sample_tick;
    end else begin:g_internal
        sample_tick_generator u_tick(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick));
    end endgenerate
    wire custom_keys=(key_config_valid===1'b1);
    assign active_timbre_out=active_timbre;
    assign timbre_switching=(!custom_keys && active_timbre!=timbre_sel) || state==CLEAR;
    assign pcm_valid=sample_tick;
    assign engine_ready=rst_n && state!=CLEAR;
    wire core_rst_n=rst_n && state!=CLEAR;
    wire load_context=state==LOAD;
    wire step_context=state==PREP || state==TICK || state==RENDER;
    wire core_tick=state==TICK;
    wire [5:0] index0={1'b0,slot},index1={1'b0,slot}+6'd18;
    wire valid1=index1<36;
    // Two half-width words per saved voice. Read low during WAIT/ACCUMULATE,
    // high during READ; LOAD sees the complete previous context without stalls.
    localparam integer CONTEXT_WORD_BITS=(CONTEXT_BITS+1)/2;
    (* syn_ramstyle="block_ram" *) reg [CONTEXT_WORD_BITS-1:0] contexts0[0:35];
    (* syn_ramstyle="block_ram" *) reg [CONTEXT_WORD_BITS-1:0] contexts1[0:35];
    reg [CONTEXT_WORD_BITS-1:0] context_read0,context_read1,context_low0,context_low1;
    wire [CONTEXT_BITS-1:0] context0={context_read0[CONTEXT_BITS-CONTEXT_WORD_BITS-1:0],context_low0};
    wire [CONTEXT_BITS-1:0] context1={context_read1[CONTEXT_BITS-CONTEXT_WORD_BITS-1:0],context_low1};
    wire [CORE_BITS-1:0] core0_out,core1_out;
    // Pack the two related tables into a dual-read synchronous ROM. The
    // existing READ clock supplies the latency; the audio schedule is unchanged.
    (* syn_ramstyle="block_ram" *) reg [41:0] midi_rom[0:127];
    integer midi_index;
    initial begin for(midi_index=0;midi_index<128;midi_index=midi_index+1) midi_rom[midi_index]={midi_increment(midi_index[6:0]),midi_string_length(midi_index[6:0])};end
    // Keep the hidden key's release tail at its old pitch until the next ON.
    reg [287:0] held_revisions;
    reg [6:0] hidden_held_midi;
    wire [6:0] hidden_render_midi=voice_revision[280+:8]!=held_revisions[280+:8] ? key_midi[245+:7]:hidden_held_midi;
    wire [6:0] render_midi1=index1==35 ? hidden_render_midi:key_midi[index1*7+:7];
    reg [41:0] midi_meta0,midi_meta1;
    reg metadata_ready,metadata_lane1;
    always @(posedge clk)begin
        if(state==READ)begin midi_meta0<=midi_rom[key_midi[index0*7 +:7]];midi_meta1<=midi_rom[valid1 ? render_midi1:7'd0];end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin metadata_ready<=0;metadata_lane1<=0;end
        else if(state==READ)begin metadata_ready<=1;metadata_lane1<=valid1;end
    end
    wire [31:0] increment0=metadata_ready ? midi_meta0[41:10]:32'd0;
    wire [31:0] increment1=metadata_ready && metadata_lane1 ? midi_meta1[41:10]:32'd0;
    wire [9:0] string_length0=metadata_ready ? midi_meta0[9:0]:10'd733;
    wire [9:0] string_length1=metadata_ready && metadata_lane1 ? midi_meta1[9:0]:10'd733;
    reg [3:0] timbre0,timbre1;
    reg [143:0] held_timbres;
    reg [5:0] note0,note1;
    reg [6:0] velocity0,velocity1;
    reg gate0_snapshot,gate1_snapshot,gate0,gate1,trigger0,trigger1;
    reg [7:0] revision0,revision1;
    reg [1:0] pulse0,pulse1;
    wire fresh0=revision0!=context0[CONTEXT_BITS-1:CORE_BITS+2];
    wire fresh1=revision1!=context1[CONTEXT_BITS-1:CORE_BITS+2];
    wire [1:0] saved_pulse0=context0[CORE_BITS+1:CORE_BITS];
    wire [1:0] saved_pulse1=context1[CORE_BITS+1:CORE_BITS];
    wire active0,active1;
    wire signed [15:0] audio0,audio1;
    wire [31:0] phase0,phase1;
    wire [15:0] envelope0,envelope1;
    wire [6:0] tone_velocity0,tone_velocity1;
    // Serialize only the RAM ports, retaining the original synthesis schedule.
    // STORE writes low; BASS_ENV writes high while the voice core is frozen.
    // CLEAR uses two cycles per slot (36 clocks total, +0.36 us at 50 MHz).
    wire context_clearing=state==CLEAR;
    wire context_write=rst_n && (context_clearing || state==STORE || state==BASS_ENV);
    wire context_write_half=context_clearing ? clear_half:state==BASS_ENV;
    wire [4:0] context_write_slot=context_clearing ? clear_slot:slot;
    wire [5:0] context_write_address={context_write_slot,context_write_half};
    wire [CONTEXT_WORD_BITS*2-1:0] context_write0=context_clearing ? {voice_revision[clear_slot*8 +:8],2'd0,core0_out}:{revision0,pulse0,core0_out};
    wire [CONTEXT_WORD_BITS*2-1:0] context_write1=context_clearing ? {(clear_slot<17 ? voice_revision[(clear_slot+18)*8 +:8]:8'd0),2'd0,core1_out}:{revision1,pulse1,core1_out};
    wire [4:0] context_next_slot=slot==17 ? 5'd0:slot+5'd1;
    wire [5:0] context_read_address=state==WAIT ? 6'd0:
        state==ACCUMULATE ? {context_next_slot,1'b0}:{slot,1'b1};
    always @(posedge clk)begin
        context_read0<=contexts0[context_read_address];
        context_read1<=contexts1[context_read_address];
        if(state==READ)begin context_low0<=context_read0;context_low1<=context_read1;end
        if(context_write)contexts0[context_write_address]<=context_write_half ? context_write0[CONTEXT_WORD_BITS +:CONTEXT_WORD_BITS]:context_write0[0 +:CONTEXT_WORD_BITS];
        if(context_write && (context_clearing || valid1))contexts1[context_write_address]<=context_write_half ? context_write1[CONTEXT_WORD_BITS +:CONTEXT_WORD_BITS]:context_write1[0 +:CONTEXT_WORD_BITS];
    end
    voice_adsr lane0(.clk(clk),.rst_n(core_rst_n),.sample_tick(core_tick),
        .context_load(load_context),.context_enable(step_context),.context_slot(slot),
        .context_in(context0[CORE_BITS-1:0]),.context_out(core0_out),
        .gate(state==PREP && trigger0 ? 1'b0 : gate0),
        .custom_pitch(custom_keys),.custom_string_length(string_length0),.custom_increment(increment0),.note_sel(note0),.velocity(velocity0),.pitch_gain(pitch_gain),.timbre_sel(timbre0),
        .active(active0),.audio_out(audio0),.tone_phase(phase0),.tone_env(envelope0),.tone_velocity(tone_velocity0));
    voice_adsr lane1(.clk(clk),.rst_n(core_rst_n && valid1),.sample_tick(core_tick),
        .context_load(load_context),.context_enable(step_context),.context_slot(slot),
        .context_in(context1[CORE_BITS-1:0]),.context_out(core1_out),
        .gate(state==PREP && trigger1 ? 1'b0 : gate1),
        .custom_pitch(custom_keys),.custom_string_length(string_length1),.custom_increment(increment1),.note_sel(note1),.velocity(velocity1),.pitch_gain(pitch_gain),.timbre_sel(timbre1),
        .active(active1),.audio_out(audio1),.tone_phase(phase1),.tone_env(envelope1),.tone_velocity(tone_velocity1));

    // Subtle virtual-fundamental reinforcement for C2..B2. The fundamental
    // DDS increment is unchanged; only octave/fifth harmonics are added.
    wire signed [15:0] h20,h30,h21,h31;
    reg [31:0] bass_phase20,bass_phase30,bass_phase21,bass_phase31;
    reg signed [15:0] h20_q,h30_q,h21_q,h31_q;
    reg signed [16:0] bass_wave0_q,bass_wave1_q;
    piano35_sine_lut bass20(.phase_acc(bass_phase20),.sine_out(h20));
    piano35_sine_lut bass30(.phase_acc(bass_phase30),.sine_out(h30));
    piano35_sine_lut bass21(.phase_acc(bass_phase21),.sine_out(h21));
    piano35_sine_lut bass31(.phase_acc(bass_phase31),.sine_out(h31));
    wire signed [16:0] bass_wave0=(note0>7) ? 17'sd0 : timbre0==1 ?
        (($signed({h20_q[15],h20_q})>>>4)+($signed({h30_q[15],h30_q})>>>5)) : note0<=3 ?
        ($signed({h20_q[15],h20_q})>>>3)+($signed({h30_q[15],h30_q})>>>4) :
        ($signed({h20_q[15],h20_q})>>>4)+($signed({h30_q[15],h30_q})>>>5);
    wire signed [16:0] bass_wave1=(note1>7) ? 17'sd0 : timbre1==1 ?
        (($signed({h21_q[15],h21_q})>>>4)+($signed({h31_q[15],h31_q})>>>5)) : note1<=3 ?
        ($signed({h21_q[15],h21_q})>>>3)+($signed({h31_q[15],h31_q})>>>4) :
        ($signed({h21_q[15],h21_q})>>>4)+($signed({h31_q[15],h31_q})>>>5);
    // Refill the shared bass scratch pipeline inside each 44-clock slot.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            bass_phase20<=0;bass_phase30<=0;bass_phase21<=0;bass_phase31<=0;
            h20_q<=0;h30_q<=0;h21_q<=0;h31_q<=0;bass_wave0_q<=0;bass_wave1_q<=0;
        end else if(step_context)begin
            bass_phase20<=phase0<<1;bass_phase30<=phase0+(phase0<<1);
            bass_phase21<=phase1<<1;bass_phase31<=phase1+(phase1<<1);
            h20_q<=h20;h30_q<=h30;h21_q<=h21;h31_q<=h31;
            bass_wave0_q<=bass_wave0;bass_wave1_q<=bass_wave1;
        end
    end
    reg signed [33:0] bass_env0,bass_env1;
    reg signed [24:0] bass_velocity0,bass_velocity1;
    reg signed [15:0] raw0,raw1;
    reg [6:0] render_velocity0,render_velocity1;
    wire signed [17:0] enhanced0=$signed({{2{raw0[15]}},raw0})+$signed(bass_velocity0[24:7]);
    wire signed [17:0] enhanced1=$signed({{2{raw1[15]}},raw1})+$signed(bass_velocity1[24:7]);
    function signed [15:0] clip16(input signed [17:0] value);
        begin clip16=value>18'sd32767 ? 16'sd32767 : value< -18'sd32768 ? -16'sd32768 : value[15:0];end
    endfunction
    wire signed [15:0] contribution0=clip16(enhanced0),contribution1=clip16(enhanced1);
    // Total per-key Q16 gain, replacing the old uniform 1.30x on C2..B2.
    // Compensate C2..F3 progressively; G3..B6 and invalid notes stay at unity.
    // The nominal key selects gain even during JOY bend and the release tail.
    // Register the small table at LOAD, away from the render multiplier path.
    function signed [18:0] low_key_gain_q16(input [5:0] nominal_note);
        begin case(nominal_note)
            6'd1:low_key_gain_q16=19'sd170394; // C2 2.60x
            6'd2:low_key_gain_q16=19'sd157286; // D2 2.40x
            6'd3:low_key_gain_q16=19'sd144179; // E2 2.20x
            6'd4:low_key_gain_q16=19'sd137626; // F2 2.10x
            6'd5:low_key_gain_q16=19'sd127795; // G2 1.95x
            6'd6:low_key_gain_q16=19'sd117965; // A2 1.80x
            6'd7:low_key_gain_q16=19'sd108134; // B2 1.65x
            6'd8:low_key_gain_q16=19'sd98304; // C3 1.50x
            6'd9:low_key_gain_q16=19'sd88474; // D3 1.35x
            6'd10:low_key_gain_q16=19'sd78643; // E3 1.20x
            6'd11:low_key_gain_q16=19'sd72090; // F3 1.10x
            default:low_key_gain_q16=19'sd65536;
        endcase end
    endfunction
    reg signed [18:0] key_gain0,key_gain1;
    reg signed [34:0] key_gain_product0,key_gain_product1;
    wire signed [17:0] unscaled0=key_gain_product0[33:16],unscaled1=key_gain_product1[33:16];
    reg signed [27:0] user_product0,user_product1;
    wire signed [17:0] keyed0=user_product0[25:8],keyed1=user_product1[25:8];
    wire [8:0] user_gain0=USER_ENVELOPE==0 ? 9'd256:user_gain[index0*9 +:9];
    wire [8:0] user_gain1=USER_ENVELOPE==0 || !valid1 ? 9'd256:user_gain[index1*9 +:9];
    // 23 bits also cover 35 simultaneous full-scale copies of the lowest key.
    // Retain all peaks here; only the existing final lookahead limiter reduces them.
    reg signed [22:0] mix_sum;
    reg [5:0] active_count;
    wire signed [22:0] pair_sum=$signed({{5{keyed0[17]}},keyed0})+
        (valid1 ? $signed({{5{keyed1[17]}},keyed1}) : 23'sd0);
    reg probe_frame;
    assign probe_rendered=rst_n && state==OUTPUT && probe_frame;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)probe_frame<=0;
        else if(state==CLEAR || (state==WAIT && sample_tick))probe_frame<=0;
        else if(state==ACCUMULATE && probe_armed &&
            ((index0==probe_key && revision0==probe_revision && keyed0!=0) ||
             (valid1 && index1==probe_key && revision1==probe_revision && keyed1!=0)))probe_frame<=1;
    end
    // 1/4 gain for <=4 voices, preserving the preceding single-note level.
    // Above four voices use smooth power normalization with a wide PCM output.
    function [15:0] poly_gain(input [5:0] count);
        begin case(count)
            6'd0:poly_gain=16'd16384;
            6'd1:poly_gain=16'd16384;
            6'd2:poly_gain=16'd16384;
            6'd3:poly_gain=16'd16384;
            6'd4:poly_gain=16'd16384;
            6'd5:poly_gain=16'd14654;
            6'd6:poly_gain=16'd13377;
            6'd7:poly_gain=16'd12385;
            6'd8:poly_gain=16'd11585;
            6'd9:poly_gain=16'd10922;
            6'd10:poly_gain=16'd10362;
            6'd11:poly_gain=16'd9879;
            6'd12:poly_gain=16'd9459;
            6'd13:poly_gain=16'd9088;
            6'd14:poly_gain=16'd8757;
            6'd15:poly_gain=16'd8460;
            6'd16:poly_gain=16'd8192;
            6'd17:poly_gain=16'd7947;
            6'd18:poly_gain=16'd7723;
            6'd19:poly_gain=16'd7517;
            6'd20:poly_gain=16'd7327;
            6'd21:poly_gain=16'd7150;
            6'd22:poly_gain=16'd6986;
            6'd23:poly_gain=16'd6832;
            6'd24:poly_gain=16'd6688;
            6'd25:poly_gain=16'd6553;
            6'd26:poly_gain=16'd6426;
            6'd27:poly_gain=16'd6306;
            6'd28:poly_gain=16'd6192;
            6'd29:poly_gain=16'd6084;
            6'd30:poly_gain=16'd5982;
            6'd31:poly_gain=16'd5885;
            6'd32:poly_gain=16'd5792;
            6'd33:poly_gain=16'd5704;
            6'd34:poly_gain=16'd5619;
            6'd35:poly_gain=16'd5538;
            6'd36:poly_gain=16'd5460;
            default:poly_gain=16'd5538;
        endcase end
    endfunction
    // Voice-count normalization changes slowly, independently of waveform peaks.
    // A 64-frame lookahead limiter after effects/master gain protects the DAC.
    reg [15:0] requested_gain,applied_mix_gain;
    reg [15:0] gain_target;
    wire [15:0] next_mix_gain=applied_mix_gain>gain_target ?
        (applied_mix_gain-gain_target<=16 ? gain_target : applied_mix_gain-16'd16) :
        (gain_target-applied_mix_gain<=4 ? gain_target : applied_mix_gain+16'd4);
    reg signed [39:0] mixed_product;
    reg signed [29:0] faded_product;
    wire signed [31:0] faded_product_full=$signed(mixed_product[39:16])*$signed({1'b0,frame_sound_gain});
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=CLEAR;slot<=0;clear_slot<=0;clear_half<=0;render_count<=0;active_timbre<=1;
            sound_gain<=0;frame_sound_gain<=0;voice_active<=0;pcm_out<=0;pcm_wide<=0;frame_overrun<=0;
            hidden_held_midi<=60;held_timbres<=0;held_revisions<=0;timbre0<=1;timbre1<=1;note0<=0;note1<=0;velocity0<=0;velocity1<=0;revision0<=0;revision1<=0;
            gate0_snapshot<=0;gate1_snapshot<=0;gate0<=0;gate1<=0;trigger0<=0;trigger1<=0;pulse0<=0;pulse1<=0;
            raw0<=0;raw1<=0;render_velocity0<=0;render_velocity1<=0;
            bass_env0<=0;bass_env1<=0;bass_velocity0<=0;bass_velocity1<=0;
            key_gain_product0<=0;key_gain_product1<=0;
            key_gain0<=19'sd65536;key_gain1<=19'sd65536;
            mix_sum<=0;active_count<=0;requested_gain<=16384;applied_mix_gain<=16384;
            gain_target<=16384;
            mixed_product<=0;faded_product<=0;user_product0<=0;user_product1<=0;
        end else if(sample_tick && state!=WAIT && state!=CLEAR)begin
            // Fail closed on a broken frame-clock contract. The top-level
            // bridge resets this engine and retries; no stale partial mix.
            frame_overrun<=1;pcm_out<=0;pcm_wide<=0;state<=WAIT;
        end else begin
            if(sample_tick && state!=CLEAR)begin
                if(custom_keys)begin active_timbre<=timbre_sel;if(sound_gain<64)sound_gain<=sound_gain+1'b1;end
                else if(timbre_sel!=active_timbre)begin if(sound_gain!=0)sound_gain<=sound_gain-1'b1;end
                else if(sound_gain<64)sound_gain<=sound_gain+1'b1;
            end
            case(state)
                CLEAR:begin
                    pcm_out<=0;pcm_wide<=0;sound_gain<=0;voice_active<=0;active_timbre<=timbre_sel;
                    if(!clear_half)clear_half<=1;
                    else begin
                        clear_half<=0;
                        if(clear_slot==17)begin clear_slot<=0;slot<=0;state<=WAIT;end
                        else clear_slot<=clear_slot+1'b1;
                    end
                end
                WAIT:if(sample_tick)begin
                    if(!custom_keys && timbre_sel!=active_timbre && sound_gain==0)begin clear_slot<=0;clear_half<=0;state<=CLEAR;end
                    else begin slot<=0;mix_sum<=0;active_count<=0;frame_sound_gain<=sound_gain;state<=READ;end
                end
                READ:begin
                    timbre0<=!custom_keys ? active_timbre:voice_revision[index0*8 +:8]!=held_revisions[index0*8 +:8] || held_timbres[index0*4 +:4]==0 ? (key_timbre[index0*4 +:4]!=0 ? key_timbre[index0*4 +:4]:timbre_sel):held_timbres[index0*4 +:4];
                    timbre1<=!custom_keys || !valid1 ? active_timbre:voice_revision[index1*8 +:8]!=held_revisions[index1*8 +:8] || held_timbres[index1*4 +:4]==0 ? (key_timbre[index1*4 +:4]!=0 ? key_timbre[index1*4 +:4]:timbre_sel):held_timbres[index1*4 +:4];
                    note0<=custom_keys && voice_note[index0*6 +:6]!=0 ? midi_profile(key_midi[index0*7 +:7]):voice_note[index0*6 +:6];velocity0<=voice_velocity[index0*7 +:7];
                    revision0<=voice_revision[index0*8 +:8];gate0_snapshot<=voice_gate[index0];
                    note1<=valid1 ? (custom_keys && voice_note[index1*6 +:6]!=0 ? midi_profile(render_midi1):voice_note[index1*6 +:6]) : 6'd0;
                    velocity1<=valid1 ? voice_velocity[index1*7 +:7] : 7'd0;
                    revision1<=valid1 ? voice_revision[index1*8 +:8] : 8'd0;
                    gate1_snapshot<=valid1 && voice_gate[index1];state<=LOAD;
                end
                LOAD:begin
                    if(custom_keys && index1==35) hidden_held_midi<=render_midi1;
                    if(custom_keys) begin held_timbres[index0*4 +:4]<=timbre0;held_revisions[index0*8 +:8]<=revision0;if(valid1)begin held_timbres[index1*4 +:4]<=timbre1;held_revisions[index1*8 +:8]<=revision1;end end
                    key_gain0<=low_key_gain_q16(note0);key_gain1<=low_key_gain_q16(note1);
                    trigger0<=fresh0;trigger1<=fresh1;
                    gate0<=gate0_snapshot || fresh0 || saved_pulse0!=0;
                    gate1<=valid1 && (gate1_snapshot || fresh1 || saved_pulse1!=0);
                    pulse0<=fresh0 ? 2'd1 : saved_pulse0!=0 ? saved_pulse0-1'b1 : 2'd0;
                    pulse1<=fresh1 ? 2'd1 : saved_pulse1!=0 ? saved_pulse1-1'b1 : 2'd0;
                    state<=PREP;
                end
                PREP:state<=TICK;
                TICK:begin render_count<=0;state<=RENDER;end
                RENDER:if(render_count==43)state<=STORE;else render_count<=render_count+1'b1;
                STORE:begin
                    voice_active[index0]<=active0;if(valid1)voice_active[index1]<=active1;
                    active_count<=active_count+{5'd0,active0}+{5'd0,(valid1 && active1)};
                    raw0<=audio0;raw1<=valid1 ? audio1 : 16'sd0;
                    render_velocity0<=tone_velocity0;render_velocity1<=tone_velocity1;
                    bass_env0<=bass_wave0_q*$signed({1'b0,envelope0});
                    bass_env1<=bass_wave1_q*$signed({1'b0,envelope1});state<=BASS_ENV;
                end
                BASS_ENV:begin
                    bass_velocity0<=$signed(bass_env0[32:16])*$signed({1'b0,render_velocity0});
                    bass_velocity1<=$signed(bass_env1[32:16])*$signed({1'b0,render_velocity1});state<=BASS_VEL;
                end
                BASS_VEL:begin
                    key_gain_product0<=contribution0*key_gain0;
                    key_gain_product1<=contribution1*key_gain1;
                    state<=USER_GAIN;
                end
                USER_GAIN:begin user_product0<=unscaled0*$signed({1'b0,user_gain0});user_product1<=unscaled1*$signed({1'b0,user_gain1});state<=ACCUMULATE;end
                ACCUMULATE:begin
                    mix_sum<=mix_sum+pair_sum;
                    if(slot==17)state<=DIVIDE;
                    else begin slot<=slot+1'b1;state<=READ;end
                end
                DIVIDE:begin requested_gain<=poly_gain(active_count);state<=GAIN_TARGET;end
                GAIN_TARGET:begin gain_target<=requested_gain;state<=GAIN_DELTA;end
                GAIN_DELTA:state<=GAIN;
                GAIN:begin applied_mix_gain<=next_mix_gain;state<=PRODUCT;end
                PRODUCT:begin mixed_product<=mix_sum*$signed({1'b0,applied_mix_gain});state<=MULTIPLY;end
                MULTIPLY:begin faded_product<=faded_product_full[29:0];state<=OUTPUT;end
                OUTPUT:begin
                    pcm_wide<=faded_product[29:6];
                    // Compatibility/debug port only. The production path uses pcm_wide.
                    pcm_out<=(faded_product>>>6)>32767 ? 16'sd32767 :
                        (faded_product>>>6)< -32768 ? -16'sd32768 : faded_product[21:6];
                    state<=WAIT;
                end
                default:begin state<=CLEAR;clear_slot<=0;clear_half<=0;pcm_out<=0;pcm_wide<=0;end
            endcase
        end
    end
endmodule

// Synthesis-time diagnostic option AUDIO_TEST_MODE=2. Thirty-five different
// natural-note fundamentals, individual phase/envelope state, no recorded PCM.
// This branch is absent from the normal AUDIO_TEST_MODE=0 bitstream.
module poly35_selftest(input wire clk,rst_n,sample_tick,
    input wire [21:0] pitch_gain,
    input wire key_config_valid,input wire [251:0] key_midi,input wire [143:0] key_timbre,output wire signed [15:0] pcm_out);
    wire signed [15:0] samples[0:34];
    genvar g;
    generate for(g=0;g<35;g=g+1)begin:oscillators
        poly35_test_oscillator #(.NOTE(g+1),.START_DELAY(g*4)) u_osc(
            .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pitch_gain(pitch_gain),.audio_out(samples[g]));
    end endgenerate
    reg signed [16:0] sum1[0:17];reg signed [17:0] sum2[0:8];
    reg signed [18:0] sum3[0:4];reg signed [19:0] sum4[0:2];
    reg signed [20:0] sum5[0:1];reg signed [21:0] sum6;
    integer i;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            for(i=0;i<18;i=i+1)sum1[i]<=0;
            for(i=0;i<9;i=i+1)sum2[i]<=0;
            for(i=0;i<5;i=i+1)sum3[i]<=0;
            for(i=0;i<3;i=i+1)sum4[i]<=0;
            for(i=0;i<2;i=i+1)sum5[i]<=0;sum6<=0;
        end else begin
            for(i=0;i<17;i=i+1)sum1[i]<=$signed({samples[2*i][15],samples[2*i]})+$signed({samples[2*i+1][15],samples[2*i+1]});
            sum1[17]<={samples[34][15],samples[34]};
            for(i=0;i<9;i=i+1)sum2[i]<=$signed({sum1[2*i][16],sum1[2*i]})+$signed({sum1[2*i+1][16],sum1[2*i+1]});
            for(i=0;i<4;i=i+1)sum3[i]<=$signed({sum2[2*i][17],sum2[2*i]})+$signed({sum2[2*i+1][17],sum2[2*i+1]});
            sum3[4]<={sum2[8][17],sum2[8]};
            for(i=0;i<2;i=i+1)sum4[i]<=$signed({sum3[2*i][18],sum3[2*i]})+$signed({sum3[2*i+1][18],sum3[2*i+1]});
            sum4[2]<={sum3[4][18],sum3[4]};
            sum5[0]<=$signed({sum4[0][19],sum4[0]})+$signed({sum4[1][19],sum4[1]});sum5[1]<={sum4[2][19],sum4[2]};
            sum6<=$signed({sum5[0][20],sum5[0]})+$signed({sum5[1][20],sum5[1]});
        end
    end
    assign pcm_out=sum6>>>6;
endmodule
module poly35_test_oscillator #(parameter integer NOTE=1,START_DELAY=0)(
    input wire clk,rst_n,sample_tick,input wire [21:0] pitch_gain,
    input wire key_config_valid,input wire [251:0] key_midi,input wire [143:0] key_timbre,
    output wire signed [15:0] audio_out);
    wire [31:0] phase;wire signed [15:0] wave;
    reg [15:0] envelope;reg [7:0] start_count;
    dds_phase u_dds(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.note_sel(NOTE[5:0]),.pitch_gain(pitch_gain),.phase_acc(phase));
    sine_lut u_sine(.phase_acc(phase),.sine_out(wave));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin envelope<=0;start_count<=0;end
        else if(sample_tick)begin
            if(start_count<START_DELAY)start_count<=start_count+1'b1;
            else if(envelope<16'hff00)envelope<=envelope+16'd256;
            else envelope<=16'hffff;
        end
    end
    wire signed [32:0] product=wave*$signed({1'b0,envelope});
    assign audio_out=product>>>16;
endmodule
