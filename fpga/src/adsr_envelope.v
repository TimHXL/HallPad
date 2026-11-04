module adsr_envelope #(parameter integer CONTEXT_MODE=0) (
    input wire context_load,context_enable,
    input wire [18:0] context_in,
    output wire [18:0] context_out,

    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,

    // gate = 1：琴键按住
    // gate = 0：琴键松开
    input  wire        gate,
    input  wire [1:0]  timbre_sel,

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

    reg [15:0] HOLD_LEVEL;
    reg [15:0] ATTACK_STEP;
    reg [15:0] DECAY_STEP;
    reg [15:0] RELEASE_STEP;

    // Timbre is captured by voice_adsr on gate rise, never by the live menu.
    // Values are increments per 48 kHz sample; only ORGAN and BELL use this core.
    always @* begin
        case (timbre_sel)
            2'd2: begin // ORGAN: sustained tone, short release.
                ATTACK_STEP=16'd256; DECAY_STEP=16'd0;
                HOLD_LEVEL=16'd65535; RELEASE_STEP=16'd64;
            end
            2'd3: begin // BELL: fast strike, longer decay.
                ATTACK_STEP=16'd4096; DECAY_STEP=16'd1;
                HOLD_LEVEL=16'd0; RELEASE_STEP=16'd4;
            end
            default: begin
                ATTACK_STEP=16'd0; DECAY_STEP=16'd0;
                HOLD_LEVEL=16'd0; RELEASE_STEP=16'd0;
            end
        endcase
    end


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
