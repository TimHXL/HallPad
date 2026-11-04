`timescale 1ns/1ps
// Two copies of this reusable core render 35 independent saved voices.
// All timbres retain their existing synthesis arithmetic and envelopes.
module voice_adsr (
    input wire clk,rst_n,sample_tick,gate,context_load,context_enable,
    input wire [4:0] context_slot,
    input wire [21:0] pitch_gain,
    input wire custom_pitch,input wire [31:0] custom_increment,input wire [9:0] custom_string_length,
    input wire [5:0] note_sel,
    input wire [6:0] velocity,
    input wire [3:0] timbre_sel,
    input wire [1026:0] context_in,output wire [1026:0] context_out,
    output wire active,output wire signed [15:0] audio_out,
    output wire [31:0] tone_phase,output wire [15:0] tone_env,
    output wire [6:0] tone_velocity
);
    wire piano=timbre_sel==1,violin=timbre_sel==14;
    wire test_voice=timbre_sel>=4 && timbre_sel<=13;
    wire legacy=!piano && !violin && !test_voice;
    reg gate_d;reg [5:0] held_note;reg [6:0] held_velocity;
    wire [15:0] legacy_env,piano_env,violin_env,test_env;
    wire [31:0] piano_phase,violin_phase,test_phase,legacy_phase;
    wire [6:0] piano_velocity,violin_velocity,test_velocity;
    wire signed [15:0] piano_audio,test_audio,violin_audio,legacy_audio,velocity_audio;
    wire piano_active,test_active,violin_active;
    wire [467:0] ctx_piano35_voice;
    wire [428:0] ctx_test_instrument_voice;
    wire [64:0] ctx_levelmatched_violin_voice;
    wire [31:0] ctx_voice;
    wire [18:0] ctx_adsr_envelope;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin gate_d<=0;held_note<=0;held_velocity<=0;end
        else if(context_load)begin
            {gate_d,held_note,held_velocity}<=context_in[1026:1013];
        end else if(context_enable)begin
            gate_d<=gate;
            if(gate && !gate_d)begin held_note<=note_sel;held_velocity<=velocity;end
            else if(!gate && legacy_env==0)begin held_note<=0;held_velocity<=0;end
        end
    end
    piano35_voice #(.CONTEXT_MODE(1)) u_piano (
        .phase_observe(piano_phase),.env_observe(piano_env),.velocity_observe(piano_velocity),
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[1012:545]),.context_out(ctx_piano35_voice),
        .clk(clk),.rst_n(rst_n && piano),.sample_tick(sample_tick),.gate(gate),
        .note_sel(note_sel),.velocity(velocity),.custom_pitch(custom_pitch),.custom_increment(custom_increment),.pitch_gain(pitch_gain),.audio_out(piano_audio),.active(piano_active)
    );
    test_instrument_voice #(.CONTEXT_MODE(1)) u_test (
        .phase_observe(test_phase),.env_observe(test_env),.velocity_observe(test_velocity),
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[544:116]),.context_out(ctx_test_instrument_voice), .context_slot(context_slot),
        .clk(clk),.rst_n(rst_n && test_voice),.sample_tick(sample_tick),.gate(gate),
        .note_sel(note_sel),.velocity(velocity),.custom_string_length(custom_string_length),.custom_pitch(custom_pitch),.custom_increment(custom_increment),.pitch_gain(pitch_gain),.timbre_sel(timbre_sel),.audio_out(test_audio),.active(test_active)
    );
    levelmatched_violin_voice #(.CONTEXT_MODE(1)) u_violin (
        .phase_observe(violin_phase),.env_observe(violin_env),.velocity_observe(violin_velocity),
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[115:51]),.context_out(ctx_levelmatched_violin_voice),
        .clk(clk),.rst_n(rst_n && violin),.sample_tick(sample_tick),.gate(gate),
        .note_sel(note_sel),.velocity(velocity),.custom_pitch(custom_pitch),.custom_increment(custom_increment),.pitch_gain(pitch_gain),.audio_out(violin_audio),.active(violin_active)
    );
    voice #(.CONTEXT_MODE(1)) u_legacy (
        .phase_observe(legacy_phase),
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[50:19]),.context_out(ctx_voice),
        .clk(clk),.rst_n(rst_n && legacy),.sample_tick(sample_tick),
        .note_sel(held_note),.velocity(held_velocity),.custom_pitch(custom_pitch),.custom_increment(custom_increment),.pitch_gain(pitch_gain),.timbre_sel(timbre_sel[1:0]),.audio_out(velocity_audio)
    );
    adsr_envelope #(.CONTEXT_MODE(1)) u_legacy_env (
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[18:0]),.context_out(ctx_adsr_envelope),
        .clk(clk),.rst_n(rst_n && legacy),.sample_tick(sample_tick),.gate(gate),.timbre_sel(timbre_sel[1:0]),.env_level(legacy_env)
    );
    envelope_scaler u_scale(.audio_in(velocity_audio),.env_level(legacy_env),.audio_out(legacy_audio));
    assign active=gate || (piano ? piano_active : violin ? violin_active : test_voice ? test_active : legacy_env!=0);
    assign audio_out=piano ? piano_audio : violin ? violin_audio : test_voice ? test_audio : legacy_audio;
    assign tone_phase=piano ? piano_phase : violin ? violin_phase : test_voice ? test_phase : legacy_phase;
    assign tone_env=piano ? piano_env : violin ? violin_env :
        test_voice ? test_env : legacy_env;
    assign tone_velocity=piano ? piano_velocity : violin ? violin_velocity : test_voice ? test_velocity : held_velocity;
assign context_out={gate_d,held_note,held_velocity,ctx_piano35_voice,ctx_test_instrument_voice,ctx_levelmatched_violin_voice,ctx_voice,ctx_adsr_envelope};
endmodule


// Archive violin: identical harmonic weights, velocity scaling and ADSR.
// Only the DDS note table is the existing board's C2..B6 natural-note map.
module levelmatched_violin_voice #(parameter integer CONTEXT_MODE=0) (
    output wire [31:0] phase_observe,
    output wire [15:0] env_observe,output wire [6:0] velocity_observe,

    input wire context_load,context_enable,
    input wire [64:0] context_in,
    output wire [64:0] context_out,

    input wire clk,rst_n,sample_tick,gate,
    input wire [5:0] note_sel,
    input wire [6:0] velocity,
    input wire [21:0] pitch_gain,
    input wire custom_pitch,input wire [31:0] custom_increment,
    output wire signed [15:0] audio_out,
    output wire active
);

    // Packed, per-physical-key state; scratch registers are restored as well.
    // CONTEXT_MODE=0 keeps the original standalone behavior.
    wire do_context_load=(CONTEXT_MODE!=0) && context_load;
    wire do_context_step=(CONTEXT_MODE==0) || context_enable;
    wire [31:0] context_u_dds;
    wire [18:0] context_u_envelope;

    reg gate_d;
    reg [5:0] note_latched;
    reg [6:0] velocity_latched;
    wire [15:0] env_level;
    wire [31:0] phase_acc;
    wire signed [15:0] wave,velocity_audio;
    reg signed [15:0] wave_q,velocity_audio_q;
    assign active=gate || env_level!=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin gate_d<=0;note_latched<=0;velocity_latched<=0;end
        else if(do_context_load)begin
            gate_d<=context_in[64];
            note_latched<=context_in[63:58];
            velocity_latched<=context_in[57:51];
        end else if(do_context_step)begin
            begin
            gate_d<=gate;
            if(gate && !gate_d)begin note_latched<=note_sel;velocity_latched<=velocity;end
            else if(gate)note_latched<=note_sel;
            else if(env_level==0)begin note_latched<=0;velocity_latched<=0;end
        end
    
        end
    end
    dds_phase #(.CONTEXT_MODE(CONTEXT_MODE)) u_dds (
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[50:19]),.context_out(context_u_dds),.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .note_sel(note_latched),.custom_pitch(custom_pitch),.custom_increment(custom_increment),.pitch_gain(pitch_gain),.phase_acc(phase_acc));
    levelmatched_violin_timbre u_timbre(.phase_acc(phase_acc),.timbre_out(wave));
    amplitude_scaler u_velocity(.sine_in(wave_q),.velocity(velocity_latched),.audio_out(velocity_audio));
    levelmatched_violin_envelope #(.CONTEXT_MODE(CONTEXT_MODE)) u_envelope (
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[18:0]),.context_out(context_u_envelope),.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),
        .gate(gate),.env_level(env_level));
    envelope_scaler u_scale(.audio_in(velocity_audio_q),.env_level(env_level),.audio_out(audio_out));
assign phase_observe=phase_acc;
assign env_observe=env_level;
assign velocity_observe=velocity_latched;
always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin wave_q<=0;velocity_audio_q<=0;end
        else if(do_context_step)begin wave_q<=wave;velocity_audio_q<=velocity_audio;end
    end
assign context_out={gate_d,note_latched,velocity_latched,context_u_dds,context_u_envelope};
endmodule
module levelmatched_violin_timbre (
    input  wire [31:0] phase_acc,


    output reg signed [15:0] timbre_out
);


//==================================================
// Harmonic phases
//==================================================

wire [31:0] phase_h1;
wire [31:0] phase_h2;
wire [31:0] phase_h3;
wire [31:0] phase_h4;
wire [31:0] phase_h5;
wire [31:0] phase_h6;
wire [31:0] phase_h7;
wire [31:0] phase_h8;


assign phase_h1 = phase_acc;

assign phase_h2 =
    phase_acc << 1;

assign phase_h3 =
    phase_acc + (phase_acc << 1);

assign phase_h4 =
    phase_acc << 2;

assign phase_h5 =
    phase_acc + (phase_acc << 2);

assign phase_h6 =
    (phase_acc << 1) + (phase_acc << 2);

assign phase_h7 =
    phase_acc
    + (phase_acc << 1)
    + (phase_acc << 2);

assign phase_h8 =
    phase_acc << 3;


//==================================================
// Sine LUTs
//==================================================

wire signed [15:0] sine_1;
wire signed [15:0] sine_2;
wire signed [15:0] sine_3;
wire signed [15:0] sine_4;
wire signed [15:0] sine_5;
wire signed [15:0] sine_6;
wire signed [15:0] sine_7;
wire signed [15:0] sine_8;


sine_lut u_sine_1 (
    .phase_acc (phase_h1),
    .sine_out  (sine_1)
);

sine_lut u_sine_2 (
    .phase_acc (phase_h2),
    .sine_out  (sine_2)
);

sine_lut u_sine_3 (
    .phase_acc (phase_h3),
    .sine_out  (sine_3)
);

sine_lut u_sine_4 (
    .phase_acc (phase_h4),
    .sine_out  (sine_4)
);

sine_lut u_sine_5 (
    .phase_acc (phase_h5),
    .sine_out  (sine_5)
);

sine_lut u_sine_6 (
    .phase_acc (phase_h6),
    .sine_out  (sine_6)
);

sine_lut u_sine_7 (
    .phase_acc (phase_h7),
    .sine_out  (sine_7)
);

sine_lut u_sine_8 (
    .phase_acc (phase_h8),
    .sine_out  (sine_8)
);


//==================================================
// Violin-style harmonic weighting
//
// H1 = 1/2
// H2 = 1/8
// H3 = 1/8
// H4 = 1/16
// H5 = 1/32
// H6 = 1/32
// H7 = 1/64
// H8 = 1/64
//
// Total maximum weighting < 1.0
//==================================================

wire signed [15:0] violin_h1;
wire signed [15:0] violin_h2;
wire signed [15:0] violin_h3;
wire signed [15:0] violin_h4;
wire signed [15:0] violin_h5;
wire signed [15:0] violin_h6;
wire signed [15:0] violin_h7;
wire signed [15:0] violin_h8;


assign violin_h1 =
    $signed(sine_1) >>> 1;

assign violin_h2 =
    $signed(sine_2) >>> 3;

assign violin_h3 =
    $signed(sine_3) >>> 3;

assign violin_h4 =
    $signed(sine_4) >>> 4;

assign violin_h5 =
    $signed(sine_5) >>> 5;

assign violin_h6 =
    $signed(sine_6) >>> 5;

assign violin_h7 =
    $signed(sine_7) >>> 6;

assign violin_h8 =
    $signed(sine_8) >>> 6;


//==================================================
// Violin harmonic mix
//==================================================

wire signed [19:0] violin_mix;


assign violin_mix =

      {{4{violin_h1[15]}}, violin_h1}
    + {{4{violin_h2[15]}}, violin_h2}
    + {{4{violin_h3[15]}}, violin_h3}
    + {{4{violin_h4[15]}}, violin_h4}

    + {{4{violin_h5[15]}}, violin_h5}
    + {{4{violin_h6[15]}}, violin_h6}
    + {{4{violin_h7[15]}}, violin_h7}
    + {{4{violin_h8[15]}}, violin_h8};


// The board selects this core only for VIOLIN.
always @* timbre_out=violin_mix[15:0];

endmodule
module levelmatched_violin_envelope #(parameter integer CONTEXT_MODE=0) (
    input wire context_load,context_enable,
    input wire [18:0] context_in,
    output wire [18:0] context_out,

    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,

    // gate = 1：琴键按住
    // gate = 0：琴键松开
    input  wire        gate,

    // 0 ~ 65535
    // 代表当前包络幅度
    output reg [15:0]  env_level
);
    // Packed, per-physical-key state; scratch registers are restored as well.
    // CONTEXT_MODE=0 keeps the original standalone behavior.
    wire do_context_load=(CONTEXT_MODE!=0) && context_load;
    wire do_context_step=(CONTEXT_MODE==0) || context_enable;


    //==================================================
    // ADSR 状态
    //==================================================
    localparam IDLE    = 3'd0;
    localparam ATTACK  = 3'd1;
    localparam DECAY   = 3'd2;
    localparam HOLD = 3'd3;
    localparam RELEASE = 3'd4;

    reg [2:0] state;


    //==================================================
    // ADSR 参数
    //
    // sample_tick = 48 kHz
    //
    // Attack  ≈ 50 ms
    // Decay   ≈ 100 ms
    // Sustain = 70%
    // Release ≈ 200 ms（从 Sustain 电平附近开始）
    //==================================================

    localparam [15:0] MAX_LEVEL =
        16'd65535;

    localparam [15:0] HOLD_LEVEL =
        16'd45874;      // 65535 × 0.7 ≈ 45874

    localparam [15:0] ATTACK_STEP =
        16'd27;

    localparam [15:0] DECAY_STEP =
        16'd4;

    localparam [15:0] RELEASE_STEP =
        16'd5;


    //==================================================
    // ADSR 状态机
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin

            state     <= IDLE;
            env_level <= 16'd0;

        end
        else if(do_context_load)begin
            state<=context_in[2:0];
            env_level<=context_in[18:3];
        end else if(do_context_step)begin
            if (sample_tick) begin

            case (state)

                //==========================================
                // IDLE
                // 等待按键
                //==========================================
                IDLE: begin

                    env_level <= 16'd0;

                    if (gate)
                        state <= ATTACK;

                end


                //==========================================
                // ATTACK
                // 从0逐渐上升到最大值
                //==========================================
                ATTACK: begin

                    // Attack过程中提前松键
                    if (!gate) begin

                        state <= RELEASE;

                    end

                    else if (
                        env_level >=
                        (MAX_LEVEL - ATTACK_STEP)
                    ) begin

                        env_level <= MAX_LEVEL;
                        state     <= DECAY;

                    end

                    else begin

                        env_level <=
                            env_level + ATTACK_STEP;

                    end

                end


                //==========================================
                // DECAY
                // 从最大值下降到 Sustain 电平
                //==========================================
                DECAY: begin

                    if (!gate) begin

                        state <= RELEASE;

                    end

                    else if (
                        env_level <=
                        (HOLD_LEVEL + DECAY_STEP)
                    ) begin

                        env_level <= HOLD_LEVEL;
                        state     <= HOLD;

                    end

                    else begin

                        env_level <=
                            env_level - DECAY_STEP;

                    end

                end


                //==========================================
                // HOLD
                // 按键持续按住时保持固定幅度
                //==========================================
                HOLD: begin

                    env_level <= HOLD_LEVEL;

                    if (!gate)
                        state <= RELEASE;

                end


                //==========================================
                // RELEASE
                // 松键后逐渐衰减到0
                //==========================================
                RELEASE: begin

                    // Release过程中再次按下
                    // 从当前幅度重新开始Attack
                    if (gate) begin

                        state <= ATTACK;

                    end

                    else if (
                        env_level <= RELEASE_STEP
                    ) begin

                        env_level <= 16'd0;
                        state     <= IDLE;

                    end

                    else begin

                        env_level <=
                            env_level - RELEASE_STEP;

                    end

                end


                //==========================================
                // 异常状态保护
                //==========================================
                default: begin

                    state     <= IDLE;
                    env_level <= 16'd0;

                end

            endcase

        end

    
        end
    end

assign context_out={env_level,state};
endmodule
