`timescale 1ns/1ps
// Experimental real-time synthesis palette, not PCM playback.
// IDs: 4 XYLO, 5 MARIMBA, 6 EPIANO, 7 PLUCK, 8 FLUTE,
//      9 BASS, 11 SNARE, 13 STRINGS; IDs 0, 10, 12 are unused.
// One independent physical-model string delay line per voice. Its contents
// are generated from noise at trigger, never initialized from recorded audio.
module test_instrument_voice #(parameter integer CONTEXT_MODE=0, parameter integer CONTEXT_SLOTS=18) (
    output wire [31:0] phase_observe,
    output wire [15:0] env_observe,output wire [6:0] velocity_observe,

    input wire context_load,context_enable,
    input wire [428:0] context_in,
    output wire [428:0] context_out,
    input wire [4:0] context_slot,

    input wire clk, rst_n, sample_tick,
    input wire [21:0] pitch_gain,
    input wire custom_pitch,input wire [31:0] custom_increment,input wire [9:0] custom_string_length,
    input wire [5:0] note_sel,
    input wire [6:0] velocity,
    input wire [3:0] timbre_sel,
    input wire gate,
    output reg signed [15:0] audio_out,
    output wire active
);

    // Packed, per-physical-key state; scratch registers are restored as well.
    // CONTEXT_MODE=0 keeps the original standalone behavior.
    wire do_context_load=(CONTEXT_MODE!=0) && context_load;
    wire do_context_step=(CONTEXT_MODE==0) || context_enable;

    reg gate_d;
    reg init_busy;
    reg signed [15:0] ram_current, ram_next;
    wire signed [17:0] ram_interpolated;
    reg [5:0] note_seen, note_latched;
    reg [6:0] velocity_latched;
    reg [3:0] mode;
    reg [1:0] env_state;
    reg [16:0] env, bright;
    reg [16:0] attack_step, hold_level;
    reg [4:0] decay_shift, release_shift, bright_shift;
    reg hold_tone, one_shot;
    reg [31:0] phase, phase_aux, phase_third;
    reg [31:0] lfsr;
    reg signed [15:0] noise_previous;
    wire event_now = gate && (!gate_d || note_sel != note_seen);
    assign active = (env_state != 0) || event_now || init_busy;

    function [31:0] note_increment;
        input [5:0] note;
        begin
            case(note)
                6'd1: note_increment=32'd5852465;
                6'd2: note_increment=32'd6569170;
                6'd3: note_increment=32'd7373644;
                6'd4: note_increment=32'd7812103;
                6'd5: note_increment=32'd8768789;
                6'd6: note_increment=32'd9842633;
                6'd7: note_increment=32'd11047982;
                6'd8: note_increment=32'd11704930;
                6'd9: note_increment=32'd13138339;
                6'd10: note_increment=32'd14747287;
                6'd11: note_increment=32'd15624207;
                6'd12: note_increment=32'd17537579;
                6'd13: note_increment=32'd19685267;
                6'd14: note_increment=32'd22095965;
                6'd15: note_increment=32'd23409859;
                6'd16: note_increment=32'd26276679;
                6'd17: note_increment=32'd29494575;
                6'd18: note_increment=32'd31248413;
                6'd19: note_increment=32'd35075158;
                6'd20: note_increment=32'd39370534;
                6'd21: note_increment=32'd44191930;
                6'd22: note_increment=32'd46819719;
                6'd23: note_increment=32'd52553357;
                6'd24: note_increment=32'd58989149;
                6'd25: note_increment=32'd62496826;
                6'd26: note_increment=32'd70150316;
                6'd27: note_increment=32'd78741067;
                6'd28: note_increment=32'd88383859;
                6'd29: note_increment=32'd93639437;
                6'd30: note_increment=32'd105106715;
                6'd31: note_increment=32'd117978298;
                6'd32: note_increment=32'd124993653;
                6'd33: note_increment=32'd140300631;
                6'd34: note_increment=32'd157482134;
                6'd35: note_increment=32'd176767719;
                default: note_increment = 0;
            endcase
        end
    endfunction
    function [9:0] string_length;
        input [5:0] note;
        begin
            case(note)
                6'd1: string_length=10'd733;
                6'd2: string_length=10'd653;
                6'd3: string_length=10'd582;
                6'd4: string_length=10'd549;
                6'd5: string_length=10'd489;
                6'd6: string_length=10'd436;
                6'd7: string_length=10'd388;
                6'd8: string_length=10'd366;
                6'd9: string_length=10'd326;
                6'd10: string_length=10'd291;
                6'd11: string_length=10'd274;
                6'd12: string_length=10'd244;
                6'd13: string_length=10'd218;
                6'd14: string_length=10'd194;
                6'd15: string_length=10'd183;
                6'd16: string_length=10'd163;
                6'd17: string_length=10'd145;
                6'd18: string_length=10'd137;
                6'd19: string_length=10'd122;
                6'd20: string_length=10'd109;
                6'd21: string_length=10'd97;
                6'd22: string_length=10'd91;
                6'd23: string_length=10'd81;
                6'd24: string_length=10'd72;
                6'd25: string_length=10'd68;
                6'd26: string_length=10'd61;
                6'd27: string_length=10'd54;
                6'd28: string_length=10'd48;
                6'd29: string_length=10'd45;
                6'd30: string_length=10'd40;
                6'd31: string_length=10'd36;
                6'd32: string_length=10'd34;
                6'd33: string_length=10'd30;
                6'd34: string_length=10'd27;
                6'd35: string_length=10'd24;
                default: string_length = 10'd109;
            endcase
        end
    endfunction
    wire [31:0] base_inc=(custom_pitch===1'b1) ? custom_increment:note_increment(note_latched);
    wire [53:0] bent_product=base_inc*pitch_gain;
    wire [31:0] inc = bent_product[51:20];
    always @* begin
        attack_step=17'd274; hold_level=17'd0;
        decay_shift=5'd14; release_shift=5'd11; bright_shift=5'd11;
        hold_tone=0; one_shot=0;
        case(mode)
            4: begin attack_step=17'd4096; decay_shift=5'd12; bright_shift=5'd8; one_shot=1; end
            5: begin attack_step=17'd2048; decay_shift=5'd14; bright_shift=5'd10; one_shot=1; end
            6: begin attack_step=17'd274; decay_shift=5'd15; bright_shift=5'd12; end
            7: begin attack_step=17'd2048; decay_shift=5'd16; release_shift=5'd11; end
            8: begin attack_step=17'd69; hold_level=17'd65536; hold_tone=1; release_shift=5'd11; end
            9: begin attack_step=17'd683; hold_level=17'd45056; hold_tone=1; decay_shift=5'd10; release_shift=5'd9; end
            11: begin attack_step=17'd8192; decay_shift=5'd11; one_shot=1; end
            13: begin attack_step=17'd18; hold_level=17'd65536; hold_tone=1; release_shift=5'd12; end
            default: begin end
        endcase
    end
    wire [16:0] decay_step = (env >> decay_shift) + 17'd1;
    wire [16:0] release_step = (env >> release_shift) + 17'd1;
    wire [16:0] bright_step = (bright >> bright_shift) + 17'd1;
    wire [31:0] lfsr_next = {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            gate_d<=0; note_seen<=0; note_latched<=0; velocity_latched<=0;
            mode<=4'd4; env_state<=0; env<=0; bright<=0;
            phase<=0; phase_aux<=0; phase_third<=0;
            lfsr<=32'h6c8e9cf5; noise_previous<=0;
        end
        else if(do_context_load)begin
            gate_d<=context_in[412];
            note_seen<=context_in[378:373];
            note_latched<=context_in[372:367];
            velocity_latched<=context_in[366:360];
            mode<=context_in[359:356];
            env_state<=context_in[355:354];
            env<=context_in[353:337];
            bright<=context_in[336:320];
            phase<=context_in[319:288];
            phase_aux<=context_in[287:256];
            phase_third<=context_in[255:224];
            lfsr<=context_in[223:192];
            noise_previous<=context_in[191:176];
        end else if(do_context_step)begin
            begin
            gate_d<=gate;
            if(gate)note_seen<=note_sel;
            if(init_busy || sample_tick) lfsr<=lfsr_next;
            if(event_now) begin
                note_latched<=note_sel; velocity_latched<=velocity; mode<=timbre_sel;
                env<=0; bright<=17'd32768+{2'd0,velocity,8'd0};
                env_state<= (note_sel>=1 && note_sel<=35 && velocity!=0) ? 2'd1 : 2'd0;
                phase<=0; phase_aux<=0; phase_third<=0;
            end else if(sample_tick) begin
                noise_previous<=$signed(lfsr[31:16]);
                phase<=phase+inc;
                if(mode==4) phase_aux<=phase_aux+(inc<<1)+(inc>>1)+(inc>>2);
                else if(mode==5)phase_aux<=phase_aux+(inc<<2);
                else if(mode==13)phase_aux<=phase_aux+inc+(inc>>9);
                else phase_aux<=phase_aux+(inc<<1);
                phase_third<=phase_third+inc-(inc>>9);
                if(bright<=bright_step)bright<=0;else bright<=bright-bright_step;
                case(env_state)
                    0: env<=0;
                    1: if(!init_busy)begin
                        if(env>=17'd65536-attack_step)begin env<=17'd65536;env_state<=2;end
                        else env<=env+attack_step;
                    end
                    2: begin
                        if(!gate && !one_shot)env_state<=3;
                        if(hold_tone && env<=hold_level+decay_step)env<=hold_level;
                        else if(env<=decay_step)begin env<=0;env_state<=0;end
                        else env<=env-decay_step;
                    end
                    3: if(env<=release_step)begin env<=0;env_state<=0;end
                       else env<=env-release_step;
                endcase
            end
        end
    
        end
    end
    wire signed [15:0] sine_main, sine_aux, sine_fm;
    reg signed [15:0] sine_main_q,sine_aux_q,sine_fm_q;
    reg signed [33:0] partial_product_q;
    reg [31:0] fm_phase_q;
    wire signed [33:0] mod_product=partial_product_q;
    wire signed [15:0] mod_wave = mod_product[31:16];
    piano35_sine_lut lut1(.phase_acc(phase),.sine_out(sine_main));
    piano35_sine_lut lut2(.phase_acc(phase_aux),.sine_out(sine_aux));
    piano35_sine_lut lut3(.phase_acc(fm_phase_q),.sine_out(sine_fm));
    wire signed [17:0] s1={{2{sine_main_q[15]}},sine_main_q};
    wire signed [17:0] s2={{2{sine_aux_q[15]}},sine_aux_q};
    wire signed [17:0] sf={{2{sine_fm_q[15]}},sine_fm_q};
    wire signed [17:0] saw1={{2{phase[31]}},phase[31:16]};
    wire signed [17:0] saw2={{2{phase_aux[31]}},phase_aux[31:16]};
    wire signed [17:0] saw3={{2{phase_third[31]}},phase_third[31:16]};
    wire signed [17:0] noise={{2{lfsr[31]}},lfsr[31:16]};
    wire signed [17:0] noise_high=noise-$signed({{2{noise_previous[15]}},noise_previous});
    wire signed [33:0] partial_product=partial_product_q;
    wire signed [17:0] bright_partial={{2{partial_product[31]}},partial_product[31:16]};
    reg signed [17:0] bass_filter;
    reg signed [17:0] wave;
    always @* begin
        wave=0;
        case(mode)
            4: wave=(s1>>>1)+(bright_partial>>>2);
            5: wave=(s1>>>1)+(bright_partial>>>3);
            6: wave=(sf>>>1)+(s1>>>3);
            7: wave=ram_interpolated;
            8: wave=(s1>>>1)+(s1>>>2)+(s2>>>4)+(noise>>>6);
            9: wave=bass_filter;
            11: wave=(noise_high>>>2)+(s1>>>2);
            13: wave=(saw1>>>2)+(saw2>>>2)+(saw3>>>2);
            default: wave=0;
        endcase
    end

    // Synchronous reads, one write port; RAM is only read after noise fill.
    localparam integer STRING_WORDS=(CONTEXT_MODE!=0) ? CONTEXT_SLOTS*1024 : 1024;
    (* syn_ramstyle="block_ram" *) reg signed [15:0] string_ram[0:STRING_WORDS-1];
    wire [4:0] string_bank=(CONTEXT_MODE!=0) ? context_slot : 5'd0;
    reg [9:0] ram_length, ram_pointer, init_pointer;
    reg [19:0] ram_fraction;
    // Shared scratch stages settle before render state 8; no extra audio clocks.
    reg [63:0] string_rate_product;
    reg [53:0] string_bend_product;
    always @(posedge clk) begin
        string_rate_product<={32'd0,custom_increment}*{53'd0,ram_length,1'b1};
        string_bend_product<=string_rate_product[44:13]*pitch_gain;
    end
    // Saturate a resampling rate that rounds just above 4x; never wrap it to
    // nearly zero on a large bend. Feedback damping runs at the native rate.
    wire [21:0] custom_string_rate=(|string_bend_product[53:42]) ? 22'd4194303:string_bend_product[41:20];
    wire [21:0] string_rate=(custom_pitch===1'b1) ? custom_string_rate:pitch_gain;
    wire [22:0] ram_advance={3'd0,ram_fraction}+{1'b0,string_rate};
    wire [10:0] ram_advanced_pointer={1'b0,ram_pointer}+{8'd0,ram_advance[22:20]};
    wire [10:0] ram_wrap_once=ram_advanced_pointer>={1'b0,ram_length} ? ram_advanced_pointer-{1'b0,ram_length}:ram_advanced_pointer;
    wire [10:0] ram_wrapped_pointer=ram_wrap_once>={1'b0,ram_length} ? ram_wrap_once-{1'b0,ram_length}:ram_wrap_once;
    wire signed [16:0] ram_difference=$signed({ram_next[15],ram_next})-$signed({ram_current[15],ram_current});
    wire signed [37:0] ram_interpolation=ram_difference*$signed({1'b0,ram_fraction});
    assign ram_interpolated=$signed({{2{ram_current[15]}},ram_current})+$signed(ram_interpolation[37:20]);


    wire [9:0] ram_next_pointer = (ram_pointer==ram_length-10'd1) ? 10'd0 : ram_pointer+10'd1;
    // Preserve the signed, zero-ending damping exactly, while separating
    // the RAM read, average, magnitude, damping and sign restoration.
    reg signed [16:0] ram_average_q,ram_magnitude_q,ram_damped_q,ram_filtered_q;
    reg signed [15:0] feedback_current_q;
    // After noise initialization, reuse init_pointer as the native-rate
    // feedback cursor. It is already saved per key: no wider context RAM.
    wire [9:0] feedback_next=init_pointer==ram_length-1'b1 ? 10'd0:init_pointer+1'b1;
    reg ram_negative_q,ram_zero_q;
    reg [3:0] render_state;
    reg signed [17:0] render_wave;
    reg [16:0] render_env;
    reg [6:0] render_velocity;
    reg signed [35:0] env_product;
    reg signed [25:0] velocity_product;
    wire signed [25:0] final_wide=velocity_product>>>7;
    // A single synchronous read port and a single write port have no reset or
    // context-load mux. Voice scratch registers capture the port one cycle later.
    reg signed [15:0] string_read_data;
    wire [9:0] string_read_pointer=mode==7 && render_state==3 ? init_pointer:
        mode==7 && render_state==12 ? feedback_next:render_state==1 ? ram_pointer:ram_next_pointer;
    wire [14:0] string_read_address={string_bank,string_read_pointer};
    wire string_write=rst_n && do_context_step && !do_context_load && !event_now && (init_busy || (!sample_tick && render_state==8 && mode==7 && env_state!=0));
    wire [14:0] string_write_address={string_bank,init_pointer};
    wire [15:0] string_write_data=init_busy ? lfsr[31:16]:ram_filtered_q[15:0];
    always @(posedge clk) begin
        if(string_write) string_ram[string_write_address]<=string_write_data;
        string_read_data<=string_ram[string_read_address];
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ram_length<=10'd109;ram_fraction<=0;ram_pointer<=0;init_pointer<=0;init_busy<=0;
            ram_current<=0;ram_next<=0;render_state<=0;render_wave<=0;
            render_env<=0;render_velocity<=0;env_product<=0;velocity_product<=0;
            audio_out<=0;bass_filter<=0;
            ram_average_q<=0;ram_magnitude_q<=0;ram_damped_q<=0;ram_filtered_q<=0;
            ram_negative_q<=0;ram_zero_q<=1;feedback_current_q<=0;
        end
        else if(do_context_load)begin
            ram_length<=context_in[157:148];
            ram_fraction<=context_in[127:108];
            ram_pointer<=context_in[147:138];
            init_pointer<=context_in[137:128];
            init_busy<=context_in[411];
            ram_current<=context_in[410:395];
            ram_next<=context_in[394:379];
            render_state<=context_in[107:104];
            render_wave<=context_in[103:86];
            render_env<=context_in[85:69];
            render_velocity<=context_in[68:62];
            env_product<=context_in[61:26];
            velocity_product<=context_in[25:0];
            audio_out<=context_in[428:413];
            bass_filter<=context_in[175:158];
        end else if(do_context_step)begin
            if(event_now)begin
            render_state<=0;audio_out<=0;bass_filter<=0;
            ram_pointer<=0;ram_fraction<=0;init_pointer<=0;
            ram_length<=(custom_pitch===1'b1) ? custom_string_length:string_length(note_sel);
            init_busy<=timbre_sel==7 && note_sel>=1 && note_sel<=35 && velocity!=0;
        end else if(init_busy)begin
            if(init_pointer==ram_length-10'd1)begin init_busy<=0;ram_pointer<=0;init_pointer<=0;end
            else init_pointer<=init_pointer+10'd1;
        end else if(sample_tick)begin
            render_state<=1;
        end else case(render_state)
            0:begin end
            1:begin
                render_env<=env;render_velocity<=velocity_latched;
                render_state<=2;
            end
            2:begin ram_current<=string_read_data;render_state<=3;end
            3:begin
                ram_next<=string_read_data;
                if(mode==7)render_state<=12;
                else begin ram_average_q<=($signed({ram_current[15],ram_current})+$signed({string_read_data[15],string_read_data}))>>>1;render_state<=7;end
            end
            12:begin feedback_current_q<=string_read_data;render_state<=13;end
            13:begin ram_average_q<=($signed({feedback_current_q[15],feedback_current_q})+$signed({string_read_data[15],string_read_data}))>>>1;render_state<=7;end
            7:begin
                ram_negative_q<=ram_average_q[16];ram_zero_q<=ram_average_q==0;
                ram_magnitude_q<=ram_average_q<0 ? -ram_average_q : ram_average_q;
                render_state<=9;
            end
            9:begin ram_damped_q<=ram_magnitude_q-(ram_magnitude_q>>>10)-17'sd1;render_state<=10;end
            10:begin ram_filtered_q<=ram_zero_q ? 17'sd0 : ram_negative_q ? -ram_damped_q : ram_damped_q;render_state<=11;end
            11:render_state<=8;
            8:begin
                render_wave<=wave;
                if(mode==7 && env_state!=0)begin
                    ram_pointer<=ram_wrapped_pointer[9:0];ram_fraction<=ram_advance[19:0];init_pointer<=feedback_next;
                end
                bass_filter<=bass_filter+(((saw1>>>1)+(phase_aux[31] ? 18'sd4096 : -18'sd4096)-bass_filter)>>>3);
                render_state<=4;
            end
            4:begin env_product<=render_wave*$signed({1'b0,render_env});render_state<=5;end
            5:begin velocity_product<=$signed(env_product[33:16])*$signed({1'b0,render_velocity});render_state<=6;end
            6:begin
                if(final_wide>26'sd32767)audio_out<=16'sd32767;
                else if(final_wide< -26'sd32768)audio_out<= -16'sd32768;
                else audio_out<=final_wide[15:0];
                render_state<=0;
            end
            default:render_state<=0;
        endcase
    
        end
    end
assign phase_observe=phase;
assign env_observe=env[16] ? 16'hffff : env[15:0];
assign velocity_observe=velocity_latched;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin sine_main_q<=0;sine_aux_q<=0;partial_product_q<=0;fm_phase_q<=0;sine_fm_q<=0;end
        else if(do_context_step)begin
            sine_main_q<=sine_main;sine_aux_q<=sine_aux;
            partial_product_q<=sine_aux_q*$signed({1'b0,bright});
            fm_phase_q<=phase+($signed({{16{mod_wave[15]}},mod_wave})<<<15);
            sine_fm_q<=sine_fm;
        end
    end

assign context_out={audio_out,gate_d,init_busy,ram_current,ram_next,note_seen,note_latched,velocity_latched,mode,env_state,env,bright,phase,phase_aux,phase_third,lfsr,noise_previous,bass_filter,ram_length,ram_pointer,init_pointer,ram_fraction,render_state,render_wave,render_env,render_velocity,env_product,velocity_product};
endmodule
