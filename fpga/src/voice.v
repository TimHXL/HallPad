module voice #(parameter integer CONTEXT_MODE=0) (
    output wire [31:0] phase_observe,

    input wire context_load,context_enable,
    input wire [31:0] context_in,
    output wire [31:0] context_out,

    input  wire        clk,
    input  wire        rst_n,

    // 所有 Voice 共用的 48 kHz 采样脉冲
    input  wire        sample_tick,
    input wire [21:0] pitch_gain,
    input wire custom_pitch,input wire [31:0] custom_increment,

    // 0 = 静音
    // 1~35 = C3 ~ A#5
    input  wire [5:0]  note_sel,

    // 力度
    // 0~127
    input  wire [6:0]  velocity,
    input  wire [1:0]  timbre_sel,

    // 本声部最终 PCM 输出
    output wire signed [15:0] audio_out
);

    // Packed, per-physical-key state; scratch registers are restored as well.
    // CONTEXT_MODE=0 keeps the original standalone behavior.
    wire do_context_step=(CONTEXT_MODE==0) || context_enable;
    wire [31:0] context_u_dds;



//==================================================
// Voice 内部信号
//==================================================

wire [31:0]        phase_acc;
wire signed [15:0] wave_out;
reg signed [15:0] wave_q;


//==================================================
// 1. 模块 A1：DDS 相位累加器
//==================================================

dds_phase #(.CONTEXT_MODE(CONTEXT_MODE)) u_dds (
        .context_load(context_load),.context_enable(context_enable),
        .context_in(context_in[31:0]),.context_out(context_u_dds),
    .clk         (clk),
    .rst_n       (rst_n),
    .sample_tick (sample_tick),
    .note_sel    (note_sel),
    .custom_pitch(custom_pitch),.custom_increment(custom_increment),.pitch_gain(pitch_gain), .phase_acc   (phase_acc)
);


//==================================================
// 2. 模块 A2：音色波形查找表
//==================================================

timbre_wave_lut u_wave_lut (
    .phase_acc (phase_acc),
    .timbre_sel(timbre_sel),
    .wave_out  (wave_out)
);


//==================================================
// 3. 模块 B：力度 / 响度控制
//==================================================

amplitude_scaler u_amplitude_scaler (
    .sine_in   (wave_q),
    .velocity  (velocity),
    .audio_out (audio_out)
);


assign phase_observe=phase_acc;
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)wave_q<=0;else if(do_context_step)wave_q<=wave_out;
end
assign context_out={context_u_dds};
endmodule