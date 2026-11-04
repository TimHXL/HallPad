// Original pre-archive additive piano (20261021_182308), with shared-context scheduling.
// 48 kHz DDS tuning follows the applied C2..B6 natural-note table.
// Pure additive synthesis; no recorded PCM. 5 ms attack, 450 ms release.
// An audible retrigger uses a zero-slope cubic fade over 128 samples (2.667 ms).
// At silence the DDS phase is reset; the new strike uses the original 5 ms attack.
// One quarter-wave ROM and one time-multiplexed multiply per voice.
// A render completes within 42 clk cycles after sample_tick, including pipelined DDS.
module piano35_voice #(parameter integer CONTEXT_MODE=0) (
    input wire context_load,context_enable,
    input wire [467:0] context_in,output wire [467:0] context_out,
    output wire [31:0] phase_observe,output wire [15:0] env_observe,
    output wire [6:0] velocity_observe,
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_tick,
    input wire [21:0] pitch_gain,
    input wire custom_pitch,input wire [31:0] custom_increment,
    input  wire [5:0]         note_sel,
    input  wire [6:0]         velocity,
    input  wire               gate,
    output reg signed [15:0]  audio_out,
    output wire              active
);

    wire do_context_load=(CONTEXT_MODE!=0) && context_load;
    wire do_context_step=(CONTEXT_MODE==0) || context_enable;
    wire [31:0] dds_context;
    localparam [1:0] ENV_IDLE    = 2'd0;
    localparam [1:0] ENV_ATTACK  = 2'd1;
    localparam [1:0] ENV_DECAY   = 2'd2;
    localparam [1:0] ENV_RELEASE = 2'd3;

    localparam [4:0] R_DDS_WAIT1=5'd18,R_DDS_WAIT2=5'd19;
    localparam [4:0] R_IDLE       = 5'd0;
    localparam [4:0] R_PREP       = 5'd1;
    localparam [4:0] R_LUT        = 5'd2;
    localparam [4:0] R_ACCUM      = 5'd3;
    localparam [4:0] R_LOW_SETUP  = 5'd4;
    localparam [4:0] R_LOW_MUL    = 5'd5;
    localparam [4:0] R_LOW_SAVE   = 5'd6;
    localparam [4:0] R_HIGH_SETUP = 5'd7;
    localparam [4:0] R_HIGH_MUL   = 5'd8;
    localparam [4:0] R_HIGH_SAVE  = 5'd9;
    localparam [4:0] R_SUM        = 5'd10;
    localparam [4:0] R_VEL_SETUP  = 5'd11;
    localparam [4:0] R_VEL_MUL    = 5'd12;
    localparam [4:0] R_OUTPUT     = 5'd13;
    localparam [4:0] R_REL_SETUP = 5'd14;
    localparam [4:0] R_REL_MUL = 5'd15;
    localparam [4:0] R_REL_SAVE = 5'd16;

    reg gate_d;
    reg [5:0] note_seen;
    reg pending_event;
    reg [5:0] pending_note;
    reg [6:0] pending_velocity;
    reg [5:0] active_note;
    reg [6:0] velocity_latched;

    reg [1:0] env_state;
    reg [23:0] main_env,bright_env,bright_peak;
    // Only seven persistent fade bits use formerly constant context space.
    // Both outgoing envelopes and release phase stay frozen during the fade.
    // A later strike updates pending data without extending this bounded fade.
    reg [6:0] retrigger_left;
    // Q16 smoothstep(r/128): zero slope at both ends, exact integer constants.
    function [16:0] retrigger_curve(input [6:0] remaining);
        begin case(remaining)
            7'd0:retrigger_curve=17'd65536; // inactive: transparent
            7'd1:retrigger_curve=17'd12;
            7'd2:retrigger_curve=17'd48;
            7'd3:retrigger_curve=17'd106;
            7'd4:retrigger_curve=17'd188;
            7'd5:retrigger_curve=17'd292;
            7'd6:retrigger_curve=17'd419;
            7'd7:retrigger_curve=17'd567;
            7'd8:retrigger_curve=17'd736;
            7'd9:retrigger_curve=17'd926;
            7'd10:retrigger_curve=17'd1138;
            7'd11:retrigger_curve=17'd1369;
            7'd12:retrigger_curve=17'd1620;
            7'd13:retrigger_curve=17'd1891;
            7'd14:retrigger_curve=17'd2181;
            7'd15:retrigger_curve=17'd2489;
            7'd16:retrigger_curve=17'd2816;
            7'd17:retrigger_curve=17'd3161;
            7'd18:retrigger_curve=17'd3524;
            7'd19:retrigger_curve=17'd3903;
            7'd20:retrigger_curve=17'd4300;
            7'd21:retrigger_curve=17'd4713;
            7'd22:retrigger_curve=17'd5143;
            7'd23:retrigger_curve=17'd5588;
            7'd24:retrigger_curve=17'd6048;
            7'd25:retrigger_curve=17'd6523;
            7'd26:retrigger_curve=17'd7014;
            7'd27:retrigger_curve=17'd7518;
            7'd28:retrigger_curve=17'd8036;
            7'd29:retrigger_curve=17'd8568;
            7'd30:retrigger_curve=17'd9113;
            7'd31:retrigger_curve=17'd9670;
            7'd32:retrigger_curve=17'd10240;
            7'd33:retrigger_curve=17'd10822;
            7'd34:retrigger_curve=17'd11416;
            7'd35:retrigger_curve=17'd12020;
            7'd36:retrigger_curve=17'd12636;
            7'd37:retrigger_curve=17'd13262;
            7'd38:retrigger_curve=17'd13899;
            7'd39:retrigger_curve=17'd14545;
            7'd40:retrigger_curve=17'd15200;
            7'd41:retrigger_curve=17'd15864;
            7'd42:retrigger_curve=17'd16538;
            7'd43:retrigger_curve=17'd17219;
            7'd44:retrigger_curve=17'd17908;
            7'd45:retrigger_curve=17'd18605;
            7'd46:retrigger_curve=17'd19309;
            7'd47:retrigger_curve=17'd20019;
            7'd48:retrigger_curve=17'd20736;
            7'd49:retrigger_curve=17'd21459;
            7'd50:retrigger_curve=17'd22188;
            7'd51:retrigger_curve=17'd22921;
            7'd52:retrigger_curve=17'd23660;
            7'd53:retrigger_curve=17'd24403;
            7'd54:retrigger_curve=17'd25151;
            7'd55:retrigger_curve=17'd25902;
            7'd56:retrigger_curve=17'd26656;
            7'd57:retrigger_curve=17'd27413;
            7'd58:retrigger_curve=17'd28174;
            7'd59:retrigger_curve=17'd28936;
            7'd60:retrigger_curve=17'd29700;
            7'd61:retrigger_curve=17'd30466;
            7'd62:retrigger_curve=17'd31233;
            7'd63:retrigger_curve=17'd32000;
            7'd64:retrigger_curve=17'd32768;
            7'd65:retrigger_curve=17'd33536;
            7'd66:retrigger_curve=17'd34304;
            7'd67:retrigger_curve=17'd35070;
            7'd68:retrigger_curve=17'd35836;
            7'd69:retrigger_curve=17'd36600;
            7'd70:retrigger_curve=17'd37363;
            7'd71:retrigger_curve=17'd38123;
            7'd72:retrigger_curve=17'd38880;
            7'd73:retrigger_curve=17'd39634;
            7'd74:retrigger_curve=17'd40386;
            7'd75:retrigger_curve=17'd41133;
            7'd76:retrigger_curve=17'd41876;
            7'd77:retrigger_curve=17'd42615;
            7'd78:retrigger_curve=17'd43349;
            7'd79:retrigger_curve=17'd44077;
            7'd80:retrigger_curve=17'd44800;
            7'd81:retrigger_curve=17'd45517;
            7'd82:retrigger_curve=17'd46228;
            7'd83:retrigger_curve=17'd46931;
            7'd84:retrigger_curve=17'd47628;
            7'd85:retrigger_curve=17'd48317;
            7'd86:retrigger_curve=17'd48999;
            7'd87:retrigger_curve=17'd49672;
            7'd88:retrigger_curve=17'd50336;
            7'd89:retrigger_curve=17'd50991;
            7'd90:retrigger_curve=17'd51638;
            7'd91:retrigger_curve=17'd52274;
            7'd92:retrigger_curve=17'd52900;
            7'd93:retrigger_curve=17'd53516;
            7'd94:retrigger_curve=17'd54121;
            7'd95:retrigger_curve=17'd54714;
            7'd96:retrigger_curve=17'd55296;
            7'd97:retrigger_curve=17'd55866;
            7'd98:retrigger_curve=17'd56424;
            7'd99:retrigger_curve=17'd56968;
            7'd100:retrigger_curve=17'd57500;
            7'd101:retrigger_curve=17'd58018;
            7'd102:retrigger_curve=17'd58523;
            7'd103:retrigger_curve=17'd59013;
            7'd104:retrigger_curve=17'd59488;
            7'd105:retrigger_curve=17'd59948;
            7'd106:retrigger_curve=17'd60394;
            7'd107:retrigger_curve=17'd60823;
            7'd108:retrigger_curve=17'd61236;
            7'd109:retrigger_curve=17'd61633;
            7'd110:retrigger_curve=17'd62013;
            7'd111:retrigger_curve=17'd62375;
            7'd112:retrigger_curve=17'd62720;
            7'd113:retrigger_curve=17'd63047;
            7'd114:retrigger_curve=17'd63356;
            7'd115:retrigger_curve=17'd63645;
            7'd116:retrigger_curve=17'd63916;
            7'd117:retrigger_curve=17'd64167;
            7'd118:retrigger_curve=17'd64399;
            7'd119:retrigger_curve=17'd64610;
            7'd120:retrigger_curve=17'd64800;
            7'd121:retrigger_curve=17'd64969;
            7'd122:retrigger_curve=17'd65118;
            7'd123:retrigger_curve=17'd65244;
            7'd124:retrigger_curve=17'd65348;
            7'd125:retrigger_curve=17'd65430;
            7'd126:retrigger_curve=17'd65489;
            7'd127:retrigger_curve=17'd65524;
        endcase end
    endfunction
    wire ready_for_strike=(retrigger_left==0) &&
        (env_state==ENV_IDLE || (main_env==0 && bright_env==0));

    // Event capture runs at clk, not sample_tick. A pulse lasting one
    // clk is therefore retained even when it falls between audio ticks.
    // The last event before a tick wins; the interface has one voice.
    wire event_now;
    assign event_now = gate && ((!gate_d) || (note_sel != note_seen));

    wire [5:0] trigger_note;
    wire [6:0] trigger_velocity;
    assign trigger_note = event_now ? note_sel : pending_note;
    assign trigger_velocity = event_now ? velocity : pending_velocity;

    wire [5:0] dds_note;
    // Preserve the outgoing phase while audible. Only after both envelopes
    // reach zero, clear DDS phase/pending arithmetic before the next strike.
    // The real sample tick then follows the unchanged first-strike DDS path.
    wire silent_restart=ready_for_strike && env_state!=ENV_IDLE &&
                        (event_now || pending_event) && !sample_tick;
    assign dds_note = silent_restart ? 6'd0 :
                      ready_for_strike && (event_now || pending_event) ?
                      trigger_note : active_note;
    wire [31:0] phase_acc;
    // Identical note increments; share the existing context-aware DDS.
    dds_phase #(.CONTEXT_MODE(CONTEXT_MODE),.PIPELINED(1)) u_piano_dds (
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[31:0]),.context_out(dds_context),
        .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .note_sel(dds_note<=35 ? dds_note : 6'd0),.custom_pitch(custom_pitch),.custom_increment(custom_increment),.pitch_gain(pitch_gain),.phase_acc(phase_acc)
    );

    reg [7:0] attack_count;
    // 240 samples = 5 ms. Release is exactly 21600 samples = 450 ms.
    reg [14:0] release_count;
    reg [14:0] release_error;
    reg [16:0] release_phase;
    wire [15:0] release_u = release_phase[16] ? 16'hffff : release_phase[15:0];
    reg [31:0] release_square_product,release_cube_product;
    wire [15:0] release_square = release_square_product[31:16];

    wire [15:0] release_cube = release_cube_product[31:16];
    reg signed [19:0] release_curve;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin release_square_product<=0;release_cube_product<=0;release_curve<=65536;end
        else if(do_context_step)begin
            release_square_product<=release_u*release_u;
            release_cube_product<=release_square*release_u;
            release_curve<=20'sd65536-$signed({2'b00,release_square,2'b00})
                +$signed({4'b0000,release_square})+$signed({3'b000,release_cube,1'b0});
        end
    end
    wire [16:0] release_gain = (env_state != ENV_RELEASE) ? 17'd65536 :
        (release_phase[16] || release_curve <= 0) ? 17'd0 :
        (release_curve >= 20'sd65536) ? 17'd65536 : release_curve[16:0];
    // Shared scratch pipelines refill inside the existing 44-clock slot.
    // The registered curve lookup avoids a ROM-to-multiplier timing path.
    reg [16:0] fade_gain_q;
    reg [33:0] common_gain_product;
    wire [16:0] common_gain=common_gain_product[32:16];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin fade_gain_q<=65536;common_gain_product<=34'd4294967296;end
        else if(do_context_step && !do_context_load)begin
            fade_gain_q<=retrigger_curve(retrigger_left);
            common_gain_product<=release_gain*fade_gain_q;
        end
    end
    // Bass reinforcement and the original waveform use the same effective
    // release/fade factor, including the already-fixed 450 ms low-note tail.
    reg [32:0] observed_env_product;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)observed_env_product<=0;
        else if(do_context_step && !do_context_load)
            observed_env_product<=main_env[23:8]*common_gain;
    end
    assign active = (env_state != ENV_IDLE) || pending_event || event_now;


    // 25..99.4 percent high-partial amplitude, before velocity volume.
    // Constant shifts are wiring and small adders, with no barrel shifter.
    wire [23:0] trigger_bright_peak;
    assign trigger_bright_peak = 24'h400000
                               + {1'b0, trigger_velocity, 16'd0}
                               + {2'b00, trigger_velocity, 15'd0};

    function [16:0] bright_step(input [6:0] v);
        begin case(v)
            7'd0:bright_step=17'd17476;
            7'd1:bright_step=17'd17885;
            7'd2:bright_step=17'd18295;
            7'd3:bright_step=17'd18705;
            7'd4:bright_step=17'd19114;
            7'd5:bright_step=17'd19524;
            7'd6:bright_step=17'd19933;
            7'd7:bright_step=17'd20343;
            7'd8:bright_step=17'd20753;
            7'd9:bright_step=17'd21162;
            7'd10:bright_step=17'd21572;
            7'd11:bright_step=17'd21981;
            7'd12:bright_step=17'd22391;
            7'd13:bright_step=17'd22801;
            7'd14:bright_step=17'd23210;
            7'd15:bright_step=17'd23620;
            7'd16:bright_step=17'd24029;
            7'd17:bright_step=17'd24439;
            7'd18:bright_step=17'd24849;
            7'd19:bright_step=17'd25258;
            7'd20:bright_step=17'd25668;
            7'd21:bright_step=17'd26077;
            7'd22:bright_step=17'd26487;
            7'd23:bright_step=17'd26897;
            7'd24:bright_step=17'd27306;
            7'd25:bright_step=17'd27716;
            7'd26:bright_step=17'd28125;
            7'd27:bright_step=17'd28535;
            7'd28:bright_step=17'd28945;
            7'd29:bright_step=17'd29354;
            7'd30:bright_step=17'd29764;
            7'd31:bright_step=17'd30173;
            7'd32:bright_step=17'd30583;
            7'd33:bright_step=17'd30993;
            7'd34:bright_step=17'd31402;
            7'd35:bright_step=17'd31812;
            7'd36:bright_step=17'd32221;
            7'd37:bright_step=17'd32631;
            7'd38:bright_step=17'd33041;
            7'd39:bright_step=17'd33450;
            7'd40:bright_step=17'd33860;
            7'd41:bright_step=17'd34269;
            7'd42:bright_step=17'd34679;
            7'd43:bright_step=17'd35089;
            7'd44:bright_step=17'd35498;
            7'd45:bright_step=17'd35908;
            7'd46:bright_step=17'd36317;
            7'd47:bright_step=17'd36727;
            7'd48:bright_step=17'd37137;
            7'd49:bright_step=17'd37546;
            7'd50:bright_step=17'd37956;
            7'd51:bright_step=17'd38365;
            7'd52:bright_step=17'd38775;
            7'd53:bright_step=17'd39185;
            7'd54:bright_step=17'd39594;
            7'd55:bright_step=17'd40004;
            7'd56:bright_step=17'd40413;
            7'd57:bright_step=17'd40823;
            7'd58:bright_step=17'd41233;
            7'd59:bright_step=17'd41642;
            7'd60:bright_step=17'd42052;
            7'd61:bright_step=17'd42461;
            7'd62:bright_step=17'd42871;
            7'd63:bright_step=17'd43281;
            7'd64:bright_step=17'd43690;
            7'd65:bright_step=17'd44100;
            7'd66:bright_step=17'd44509;
            7'd67:bright_step=17'd44919;
            7'd68:bright_step=17'd45329;
            7'd69:bright_step=17'd45738;
            7'd70:bright_step=17'd46148;
            7'd71:bright_step=17'd46557;
            7'd72:bright_step=17'd46967;
            7'd73:bright_step=17'd47377;
            7'd74:bright_step=17'd47786;
            7'd75:bright_step=17'd48196;
            7'd76:bright_step=17'd48605;
            7'd77:bright_step=17'd49015;
            7'd78:bright_step=17'd49425;
            7'd79:bright_step=17'd49834;
            7'd80:bright_step=17'd50244;
            7'd81:bright_step=17'd50653;
            7'd82:bright_step=17'd51063;
            7'd83:bright_step=17'd51473;
            7'd84:bright_step=17'd51882;
            7'd85:bright_step=17'd52292;
            7'd86:bright_step=17'd52701;
            7'd87:bright_step=17'd53111;
            7'd88:bright_step=17'd53521;
            7'd89:bright_step=17'd53930;
            7'd90:bright_step=17'd54340;
            7'd91:bright_step=17'd54749;
            7'd92:bright_step=17'd55159;
            7'd93:bright_step=17'd55569;
            7'd94:bright_step=17'd55978;
            7'd95:bright_step=17'd56388;
            7'd96:bright_step=17'd56797;
            7'd97:bright_step=17'd57207;
            7'd98:bright_step=17'd57617;
            7'd99:bright_step=17'd58026;
            7'd100:bright_step=17'd58436;
            7'd101:bright_step=17'd58845;
            7'd102:bright_step=17'd59255;
            7'd103:bright_step=17'd59665;
            7'd104:bright_step=17'd60074;
            7'd105:bright_step=17'd60484;
            7'd106:bright_step=17'd60893;
            7'd107:bright_step=17'd61303;
            7'd108:bright_step=17'd61713;
            7'd109:bright_step=17'd62122;
            7'd110:bright_step=17'd62532;
            7'd111:bright_step=17'd62941;
            7'd112:bright_step=17'd63351;
            7'd113:bright_step=17'd63761;
            7'd114:bright_step=17'd64170;
            7'd115:bright_step=17'd64580;
            7'd116:bright_step=17'd64989;
            7'd117:bright_step=17'd65399;
            7'd118:bright_step=17'd65809;
            7'd119:bright_step=17'd66218;
            7'd120:bright_step=17'd66628;
            7'd121:bright_step=17'd67037;
            7'd122:bright_step=17'd67447;
            7'd123:bright_step=17'd67857;
            7'd124:bright_step=17'd68266;
            7'd125:bright_step=17'd68676;
            7'd126:bright_step=17'd69085;
            7'd127:bright_step=17'd69495;
            default:bright_step=17'd0;
        endcase end
    endfunction
    reg [23:0] main_decay_step;
    reg [23:0] bright_decay_step;
    always @(*) begin
        // C2..B2, C3..B3, C4..B4, C5..B5, C6..B6.
        // Main time constants approx 1.37, 1.09, .91, .78, .68 seconds.
        if (active_note <= 6'd7) begin
            main_decay_step = (main_env >> 16) + 24'd1;
            bright_decay_step = (bright_env >> 12) + 24'd1;
        end else if (active_note <= 6'd14) begin
            main_decay_step = (main_env >> 16) + (main_env >> 18) + 24'd1;
            bright_decay_step = (bright_env >> 12) + (bright_env >> 14) + 24'd1;
        end else if (active_note <= 6'd21) begin
            main_decay_step = (main_env >> 16) + (main_env >> 17) + 24'd1;
            bright_decay_step = (bright_env >> 12) + (bright_env >> 13) + 24'd1;
        end else if (active_note <= 6'd28) begin
            main_decay_step = (main_env >> 16) + (main_env >> 17) + (main_env >> 18) + 24'd1;
            bright_decay_step = (bright_env >> 12) + (bright_env >> 13) + (bright_env >> 14) + 24'd1;
        end else begin
            main_decay_step = (main_env >> 15) + 24'd1;
            bright_decay_step = (bright_env >> 11) + 24'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_d           <= 1'b0;
            note_seen        <= 6'd0;
            pending_event    <= 1'b0;
            pending_note     <= 6'd0;
            pending_velocity <= 7'd0;
            active_note      <= 6'd0;
            velocity_latched <= 7'd0;
            env_state        <= ENV_IDLE;
            attack_count     <= 8'd0;
            main_env         <= 24'd0;
            bright_env       <= 24'd0;
            bright_peak      <= 24'd0;
            release_count <= 15'd0; release_error <= 15'd0; release_phase <= 17'd0;
            retrigger_left<=0;
        end
        else if(do_context_load)begin
            {gate_d,note_seen,pending_event,pending_note,pending_velocity,active_note,velocity_latched,env_state,attack_count,main_env,bright_env,bright_peak,release_count,release_error,release_phase}<=context_in[194:32];
            retrigger_left<=context_in[217:211];
        end else if(do_context_step)begin
            gate_d <= gate;
            if (gate)
                note_seen <= note_sel;

            if (event_now) begin
                pending_event    <= 1'b1;
                pending_note     <= note_sel;
                pending_velocity <= velocity;
            end

            if (sample_tick) begin
                if(retrigger_left!=0)begin
                    retrigger_left<=retrigger_left-1'b1;
                    if(retrigger_left==1)begin main_env<=0;bright_env<=0;end
                end else if(event_now || pending_event)begin
                    if(!ready_for_strike)begin
                        pending_event<=1'b1;
                        retrigger_left<=7'd127;
                    end else begin
                        pending_event <= 1'b0;
                        release_count <= 15'd0; release_error <= 15'd0; release_phase <= 17'd0;
                        attack_count  <= 8'd0;
                        main_env      <= 24'd0;
                        bright_env    <= 24'd0;
                        if ((trigger_note >= 6'd1)
                            && (trigger_note <= 6'd35)
                            && (trigger_velocity != 7'd0)) begin
                            active_note      <= trigger_note;
                            velocity_latched <= trigger_velocity;
                            bright_peak      <= trigger_bright_peak;
                            env_state        <= ENV_ATTACK;
                        end
                        else begin
                            active_note      <= 6'd0;
                            velocity_latched <= 7'd0;
                            bright_peak      <= 24'd0;
                            env_state        <= ENV_IDLE;
                        end
                    end
                end
                else begin
                    case (env_state)
                        ENV_IDLE: begin
                            main_env   <= 24'd0;
                            bright_env <= 24'd0;
                        end
                        ENV_ATTACK: begin
                            // A hammer strike completes its 240-sample
                            // rise even if the gate pulse was very short.
                            if (attack_count == 8'd239) begin
                                main_env   <= 24'hffffff;
                                bright_env <= bright_peak;
                                env_state  <= gate ? ENV_DECAY : ENV_RELEASE;
                            end
                            else begin
                                attack_count <= attack_count + 8'd1;
                                main_env <= main_env + 24'd69905;
                                bright_env <= bright_env + {7'd0,bright_step(velocity_latched)};
                            end
                        end
                        ENV_DECAY: begin
                            main_env <= (main_env <= main_decay_step)
                                      ? 24'd0 : main_env - main_decay_step;
                            bright_env <= (bright_env <= bright_decay_step)
                                        ? 24'd0 : bright_env - bright_decay_step;
                            if (!gate) begin
                                release_count <= 15'd0; release_error <= 15'd0; release_phase <= 17'd0;
                                env_state <= ENV_RELEASE;
                            end
                            else if ((main_env == 24'd0) && (bright_env == 24'd0)) begin
                                env_state        <= ENV_IDLE;
                                active_note      <= 6'd0;
                                velocity_latched <= 7'd0;
                            end
                        end
                        ENV_RELEASE: begin
                            // Freeze the current natural envelopes; apply a
                            // smoothstep multiplier from unity to zero instead.
                            // phase advance: 65536 = 21600*3 + 736.
                            if (release_count == 15'd21599) begin
                                release_phase <= 17'd65536;
                                main_env <= 24'd0; bright_env <= 24'd0;
                                active_note <= 6'd0; velocity_latched <= 7'd0;
                                env_state <= ENV_IDLE;
                            end else begin
                                release_count <= release_count + 15'd1;
                                if (release_error >= 15'd20864) begin
                                    release_error <= release_error - 15'd20864;
                                    release_phase <= release_phase + 17'd4;
                                end else begin
                                    release_error <= release_error + 15'd736;
                                    release_phase <= release_phase + 17'd3;
                                end
                            end
                        end
                        default: begin
                            env_state        <= ENV_IDLE;
                            active_note      <= 6'd0;
                            velocity_latched <= 7'd0;
                            main_env         <= 24'd0;
                            bright_env       <= 24'd0;
                        end
                    endcase
                end
            end
        end
    end

    reg [4:0] render_state;
    reg [2:0] harmonic_index;
    reg [31:0] phase_base;
    reg [31:0] harmonic_phase;
    wire signed [15:0] rom_sine;
    reg signed [15:0] sine_value;
    reg signed [15:0] low_mix;
    reg signed [15:0] high_mix;
    reg [23:0] render_main_env;
    reg [23:0] render_bright_env;
    reg [6:0] render_velocity;

    reg signed [15:0] mul_a;
    reg signed [24:0] mul_b;
    reg signed [40:0] mul_product;
    reg signed [15:0] scaled_low;
    reg signed [15:0] scaled_high;
    reg signed [15:0] combined_audio;
    wire signed [16:0] combined_wide;
    assign combined_wide = {scaled_low[15], scaled_low}
                         + {scaled_high[15], scaled_high};

    piano35_sine_lut u_piano_sine (
        .phase_acc (harmonic_phase),
        .sine_out  (rom_sine)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            render_state      <= R_IDLE;
            harmonic_index    <= 3'd0;
            phase_base        <= 32'd0;
            harmonic_phase    <= 32'd0;
            sine_value        <= 16'sd0;
            low_mix           <= 16'sd0;
            high_mix          <= 16'sd0;
            render_main_env   <= 24'd0;
            render_bright_env <= 24'd0;
            render_velocity   <= 7'd0;

            mul_a             <= 16'sd0;
            mul_b             <= 25'sd0;
            mul_product       <= 41'sd0;
            scaled_low        <= 16'sd0;
            scaled_high       <= 16'sd0;
            combined_audio    <= 16'sd0;
            audio_out         <= 16'sd0;
        end
        else if(do_context_load)begin
            render_state<=R_IDLE;audio_out<=context_in[210:195];
        end else if(do_context_step)begin
        if (sample_tick) begin
            // The DDS captures the exact tick note/gain, multiplies, then adds.
            // Two existing render slack clocks absorb the pipeline latency.
            render_state <= R_DDS_WAIT1;
        end
        else begin
            case (render_state)
                R_IDLE: begin end
                R_DDS_WAIT1:render_state<=R_DDS_WAIT2;
                R_DDS_WAIT2:render_state<=R_PREP;
                R_PREP: begin
                    if ((active_note == 6'd0) || (active_note > 6'd35)
                        || (velocity_latched == 7'd0)
                        || ((main_env == 24'd0) && (bright_env == 24'd0))) begin
                        audio_out    <= 16'sd0;
                        render_state <= R_IDLE;
                    end
                    else begin
                        phase_base        <= phase_acc;
                        harmonic_phase    <= phase_acc;
                        harmonic_index    <= 3'd0;
                        low_mix           <= 16'sd0;
                        high_mix          <= 16'sd0;
                        render_main_env   <= main_env;
                        render_bright_env <= bright_env;
                        render_velocity   <= velocity_latched;

                        render_state      <= R_LUT;
                    end
                end
                R_LUT: begin
                    sine_value   <= rom_sine;
                    render_state <= R_ACCUM;
                end
                R_ACCUM: begin
                    // Absolute coefficient bounds:
                    // low = 1/2 H1 + 1/8 H2 (<= 5/8 FS);
                    // high = 1/8 H2 + 1/8 H3 + 1/16 H4
                    //      + 1/32 H5 + 1/64 H6 + 1/128 H7 + 1/128 H8
                    //      (<= 3/8 FS). No 16-bit accumulator can overflow.
                    case (harmonic_index)
                        3'd0: low_mix <= $signed(sine_value) >>> 1;
                        3'd1: begin
                            low_mix  <= low_mix + ($signed(sine_value) >>> 3);
                            high_mix <= $signed(sine_value) >>> 3;
                        end
                        3'd2: high_mix <= high_mix + ($signed(sine_value) >>> 3);
                        3'd3: high_mix <= high_mix + ($signed(sine_value) >>> 4);
                        3'd4: high_mix <= high_mix + ($signed(sine_value) >>> 5);
                        3'd5: high_mix <= high_mix + ($signed(sine_value) >>> 6);
                        3'd6: high_mix <= high_mix + ($signed(sine_value) >>> 7);
                        3'd7: high_mix <= high_mix + ($signed(sine_value) >>> 7);
                    endcase
                    if (harmonic_index == 3'd7)
                        render_state <= R_LOW_SETUP;
                    else begin
                        harmonic_index <= harmonic_index + 3'd1;
                        harmonic_phase <= harmonic_phase + phase_base;
                        render_state   <= R_LUT;
                    end
                end
                R_LOW_SETUP: begin
                    mul_a        <= low_mix;
                    mul_b        <= $signed({1'b0, render_main_env});
                    render_state <= R_LOW_MUL;
                end
                R_LOW_MUL: begin
                    mul_product  <= mul_a * mul_b;
                    render_state <= R_LOW_SAVE;
                end
                R_LOW_SAVE: begin
                    scaled_low   <= mul_product[39:24];
                    render_state <= R_HIGH_SETUP;
                end
                R_HIGH_SETUP: begin
                    mul_a        <= high_mix;
                    mul_b        <= $signed({1'b0, render_bright_env});
                    render_state <= R_HIGH_MUL;
                end
                R_HIGH_MUL: begin
                    mul_product  <= mul_a * mul_b;
                    render_state <= R_HIGH_SAVE;
                end
                R_HIGH_SAVE: begin
                    scaled_high  <= mul_product[39:24];
                    render_state <= R_SUM;
                end
                R_SUM: begin
                    if (combined_wide > 17'sd32767)
                        combined_audio <= 16'sd32767;
                    else if (combined_wide < -17'sd32768)
                        combined_audio <= -16'sd32768;
                    else
                        combined_audio <= combined_wide[15:0];
                    render_state <= R_REL_SETUP;
                end
                R_REL_SETUP: begin
                    mul_a <= combined_audio;
                    mul_b <= $signed({8'd0, common_gain});
                    render_state <= R_REL_MUL;
                end
                R_REL_MUL: begin
                    mul_product <= mul_a * mul_b;
                    render_state <= R_REL_SAVE;
                end
                R_REL_SAVE: begin
                    combined_audio <= mul_product[31:16];
                    render_state <= R_VEL_SETUP;
                end
                R_VEL_SETUP: begin
                    mul_a        <= combined_audio;
                    mul_b        <= $signed({1'b0, render_velocity, 17'd0});
                    render_state <= R_VEL_MUL;
                end
                R_VEL_MUL: begin
                    mul_product  <= mul_a * mul_b;
                    render_state <= R_OUTPUT;
                end
                R_OUTPUT: begin
                    audio_out    <= mul_product[39:24];
                    render_state <= R_IDLE;
                end
                default: begin
                    audio_out    <= 16'sd0;
                    render_state <= R_IDLE;
                end
            endcase
        end
        end
    end

    // Only persistent state is saved. Render scratch settles within this key's
    // slot, and the original smooth release gain is consumed after 20 clocks.
    assign context_out={250'd0,retrigger_left,audio_out,gate_d,note_seen,pending_event,pending_note,pending_velocity,active_note,velocity_latched,env_state,attack_count,main_env,bright_env,bright_peak,release_count,release_error,release_phase,dds_context};
    assign phase_observe=phase_acc;
    assign env_observe=observed_env_product[31:16];
    assign velocity_observe=velocity_latched;

endmodule

