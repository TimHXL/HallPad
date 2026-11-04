`timescale 1ns/1ps
// 48 kHz, 64-frame (1.33 ms) lookahead, 50 ms hold, slow recovery.
// The gain attack is a linear ramp, never a per-waveform instantaneous clamp.
// A later, larger peak can only increase the attack slope: every peak reaches
// its safe gain before it leaves the delay. All arithmetic remains wide.
module audio_lookahead_limiter (
    input wire clk,rst_n,sample_tick,
    input wire signed [27:0] pcm_in,
    output reg signed [15:0] pcm_out,
    output reg [16:0] limiter_gain,
    output reg [31:0] guard_count
);
    (* syn_ramstyle="block_ram" *) reg signed [27:0] delay_ram[0:63];
    reg clearing;
    reg [5:0] clear_pointer,pointer;
    reg [3:0] state;
    reg signed [27:0] delayed;
    reg [27:0] divisor;
    reg [31:0] numerator,quotient;
    reg [28:0] remainder;
    reg [5:0] divide_count;
    wire [29:0] shifted={remainder,numerator[31]};
    wire quotient_bit=shifted>={2'b0,divisor};
    wire [29:0] next_remainder=quotient_bit ? shifted-{2'b0,divisor} : shifted;
    wire [16:0] required_gain=quotient>=32'd65536 ? 17'd65536 : quotient[16:0];
    reg [16:0] held_gain,target_gain;
    reg [11:0] hold_count;
    reg [10:0] attack_step;
    reg [17:0] gain_difference;
    wire [17:0] rounded_gain_difference=gain_difference+18'd63;
    reg [10:0] proposed_step;
    reg [10:0] selected_step;
    reg signed [45:0] product;
    wire signed [45:0] scaled=product>>>16;
    wire [27:0] magnitude=pcm_in[27] ? -pcm_in : pcm_in;
    // No reset mux on RAM cells. A bounded walk initializes the complete ring.
    always @(posedge clk)begin
        if(rst_n && clearing)delay_ram[clear_pointer]<=0;
        else if(rst_n && sample_tick && state==0)delay_ram[pointer]<=pcm_in;
        if(rst_n && !clearing && sample_tick && state==0)delayed<=delay_ram[pointer];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            clearing<=1;clear_pointer<=0;pointer<=0;state<=0;
            pcm_out<=0;limiter_gain<=65536;guard_count<=0;
            divisor<=1;numerator<=0;quotient<=0;remainder<=0;divide_count<=0;
            held_gain<=65536;target_gain<=65536;hold_count<=0;attack_step<=0;
            gain_difference<=0;proposed_step<=0;selected_step<=0;product<=0;
        end else if(clearing)begin
            pcm_out<=0;
            if(clear_pointer==63)begin clearing<=0;clear_pointer<=0;end
            else clear_pointer<=clear_pointer+1'b1;
        end else if(sample_tick && state==0)begin
            pointer<=pointer+1'b1;
            divisor<=magnitude==0 ? 28'd1 : magnitude;
            numerator<=32'd1966080000; // 30000 * 65536, 0.77 dB output margin
            quotient<=0;remainder<=0;divide_count<=0;state<=1;
        end else case(state)
            0:begin end
            1:begin
                numerator<={numerator[30:0],1'b0};
                quotient<={quotient[30:0],quotient_bit};remainder<=next_remainder[28:0];
                if(divide_count==31)state<=2;
                else divide_count<=divide_count+1'b1;
            end
            2:begin
                if(required_gain<=held_gain)begin
                    held_gain<=required_gain;target_gain<=required_gain;hold_count<=2400;
                end else if(hold_count!=0)begin
                    hold_count<=hold_count-1'b1;target_gain<=held_gain;
                end else begin
                    held_gain<=required_gain-held_gain<=8 ? required_gain : held_gain+17'd8;
                    target_gain<=required_gain-held_gain<=8 ? required_gain : held_gain+17'd8;
                end
                state<=3;
            end
            3:begin
                gain_difference<={1'b0,limiter_gain}-{1'b0,target_gain};state<=4;
            end
            4:begin
                // Ceiling division by 64; a newer peak must not slow an attack.
                proposed_step<=gain_difference[17] ? 11'd0 : rounded_gain_difference[16:6];
                state<=5;
            end
            5:begin
                selected_step<=attack_step>proposed_step ? attack_step : proposed_step;state<=6;
            end
            6:begin
                if(limiter_gain>target_gain)begin
                    limiter_gain<=limiter_gain-target_gain<=selected_step ? target_gain : limiter_gain-selected_step;
                    attack_step<=selected_step;
                end else begin
                    attack_step<=0;
                    if(limiter_gain<target_gain)
                        limiter_gain<=target_gain-limiter_gain<=4 ? target_gain : limiter_gain+17'd4;
                end
                state<=7;
            end
            7:begin product<=delayed*$signed({1'b0,limiter_gain});state<=8;end
            8:begin
                // Numerical guard, not the normal limiter. The lookahead proof
                // and regression require guard_count to remain zero.
                if(scaled>30000)begin pcm_out<=30000;guard_count<=guard_count+1'b1;end
                else if(scaled< -30000)begin pcm_out<= -30000;guard_count<=guard_count+1'b1;end
                else pcm_out<=scaled[15:0];
                state<=0;
            end
            default:state<=0;
        endcase
    end
endmodule
