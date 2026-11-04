// PIPELINED=1 captures note/gain on sample_tick and commits phase two clocks
// later. Its caller must allow those clocks before reading phase/context or
// issuing another tick. Piano scheduling reserves them explicitly.
module dds_phase #(parameter integer CONTEXT_MODE=0, parameter integer PIPELINED=0) (
    input wire context_load,context_enable,
    input wire [31:0] context_in,
    output wire [31:0] context_out,

    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,
    input wire [21:0] pitch_gain,
    input wire custom_pitch,input wire [31:0] custom_increment,

    // 0 = 静音
    // 1~35 = C2 ~ B6 (natural notes only)
    input  wire [5:0]  note_sel,

    output reg  [31:0] phase_acc
);
    // Packed, per-physical-key state; scratch registers are restored as well.
    // CONTEXT_MODE=0 keeps the original standalone behavior.
    wire do_context_load=(CONTEXT_MODE!=0) && context_load;
    wire do_context_step=(CONTEXT_MODE==0) || context_enable;


reg [31:0] phase_inc;
wire [53:0] bent_product=((custom_pitch===1'b1) ? custom_increment:phase_inc)*pitch_gain;

//==================================================
// 根据琴键编号产生 DDS 相位步进值
//
// Fs = 48 kHz
// phase_inc = f_out × 2^32 / 48000
//
// note_sel = 0     静音
// note_sel = 1~35  C2 ~ B6 (natural notes only)
//==================================================

always @(*) begin

    case (note_sel)

        6'd0:  phase_inc = 32'd0;         // 静音

        // -------------------------------
        // Note slots 1..12
        // -------------------------------

        6'd1: phase_inc = 32'd5852465; // C2 65.40639 Hz
        6'd2: phase_inc = 32'd6569170; // D2 73.41619 Hz
        6'd3: phase_inc = 32'd7373644; // E2 82.40689 Hz
        6'd4: phase_inc = 32'd7812103; // F2 87.30706 Hz
        6'd5: phase_inc = 32'd8768789; // G2 97.99886 Hz
        6'd6: phase_inc = 32'd9842633; // A2 110.00000 Hz
        6'd7: phase_inc = 32'd11047982; // B2 123.47083 Hz
        6'd8: phase_inc = 32'd11704930; // C3 130.81278 Hz
        6'd9: phase_inc = 32'd13138339; // D3 146.83238 Hz
        6'd10: phase_inc = 32'd14747287; // E3 164.81378 Hz
        6'd11: phase_inc = 32'd15624207; // F3 174.61412 Hz
        6'd12: phase_inc = 32'd17537579; // G3 195.99772 Hz


        // -------------------------------
        // Note slots 13..24
        // -------------------------------

        6'd13: phase_inc = 32'd19685267; // A3 220.00000 Hz
        6'd14: phase_inc = 32'd22095965; // B3 246.94165 Hz
        6'd15: phase_inc = 32'd23409859; // C4 261.62557 Hz
        6'd16: phase_inc = 32'd26276679; // D4 293.66477 Hz
        6'd17: phase_inc = 32'd29494575; // E4 329.62756 Hz
        6'd18: phase_inc = 32'd31248413; // F4 349.22823 Hz
        6'd19: phase_inc = 32'd35075158; // G4 391.99544 Hz
        6'd20: phase_inc = 32'd39370534; // A4 440.00000 Hz
        6'd21: phase_inc = 32'd44191930; // B4 493.88330 Hz
        6'd22: phase_inc = 32'd46819719; // C5 523.25113 Hz
        6'd23: phase_inc = 32'd52553357; // D5 587.32954 Hz
        6'd24: phase_inc = 32'd58989149; // E5 659.25511 Hz


        // -------------------------------
        // Note slots 25..35
        // -------------------------------

        6'd25: phase_inc = 32'd62496826; // F5 698.45646 Hz
        6'd26: phase_inc = 32'd70150316; // G5 783.99087 Hz
        6'd27: phase_inc = 32'd78741067; // A5 880.00000 Hz
        6'd28: phase_inc = 32'd88383859; // B5 987.76660 Hz
        6'd29: phase_inc = 32'd93639437; // C6 1046.50226 Hz
        6'd30: phase_inc = 32'd105106715; // D6 1174.65907 Hz
        6'd31: phase_inc = 32'd117978298; // E6 1318.51023 Hz
        6'd32: phase_inc = 32'd124993653; // F6 1396.91293 Hz
        6'd33: phase_inc = 32'd140300631; // G6 1567.98174 Hz
        6'd34: phase_inc = 32'd157482134; // A6 1760.00000 Hz
        6'd35: phase_inc = 32'd176767719; // B6 1975.53321 Hz

        default:
            phase_inc = 32'd0;

    endcase

end


//==================================================
// DDS 相位累加器
//==================================================

generate if(PIPELINED!=0)begin:g_pipeline
    reg [31:0] increment_q;
    reg [21:0] pitch_q;
    reg [53:0] product_q;
    reg [1:0] pending;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            phase_acc<=0;increment_q<=0;pitch_q<=0;product_q<=0;pending<=0;
        end else if(do_context_load)begin
            phase_acc<=context_in;pending<=0;
        end else if(do_context_step)begin
            pending<={pending[0],sample_tick && note_sel!=0};
            if(sample_tick)begin increment_q<=(custom_pitch===1'b1) ? custom_increment:phase_inc;pitch_q<=pitch_gain;end
            if(pending[0])product_q<=increment_q*pitch_q;
            if(note_sel==0)begin phase_acc<=0;pending<=0;end
            else if(pending[1])phase_acc<=phase_acc+product_q[51:20];
        end
    end
end else begin:g_direct
always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin

        phase_acc <= 32'd0;

    end
        else if(do_context_load)begin
            phase_acc<=context_in[31:0];
        end else if(do_context_step)begin
            if (note_sel == 6'd0) begin

        phase_acc <= 32'd0;

    end

    else if (sample_tick) begin

        phase_acc <= phase_acc + bent_product[51:20];

    end


        end
    end

end endgenerate

assign context_out={phase_acc};
endmodule
