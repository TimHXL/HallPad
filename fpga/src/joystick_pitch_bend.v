`timescale 1ns/1ps
// ADC front end for the shared App/physical pitch mapper. Calibrated low Y is
// up. Horizontal modulation depths reversed from Drum80: low X=127, high X=32. Use the same wire
// units as App: quadratic signed bend +/-8191 and linear modulation 0..127,
// with 32/127 small/big depth. 0x70 sensitivity is applied exactly once here.
// A single 32-step divider serves both normalizations and both wire values.
// Both axes remain live together, including diagonals and small center moves.
// No center dead zone, dominant-axis lock or acquisition dwell. Stale input
// recovery, calibrated endpoint clamping and sensitivity remain unchanged.
module joystick_pitch_bend #(
    parameter [11:0] X_CENTER=1245,X_MIN=5,X_MAX=2538,
    parameter [11:0] Y_CENTER=1390,Y_MIN=122,Y_MAX=2606
)(
    input wire clk,rst_n,sample_tick,
    input wire [6:0] joy_percent,
    input wire joy_valid,joy_axis,input wire [11:0] joy_data,
    output wire signed [15:0] bend,output wire [6:0] modulation,
    output wire center_ready
);
    reg [11:0] x,y;
    reg seen_x,seen_y;
    reg [12:0] age_x,age_y;
    reg [10:0] x_norm,y_norm;
    reg x_low,y_low;
    reg [1:0] next_job,work_job;
    reg work_low,dividing;
    reg [5:0] div_count;
    reg [31:0] numerator,quotient;
    reg [16:0] remainder,divisor;
    wire [17:0] trial={remainder,numerator[31]};
    wire take_bit=trial>={1'b0,divisor};
    wire [17:0] reduced=trial-{1'b0,divisor};
    wire [31:0] next_quotient={quotient[30:0],take_bit};
    wire both_fresh=seen_x && seen_y && age_x<4800 && age_y<4800;
    wire enabled=joy_percent!=0 && both_fresh;
    reg signed [15:0] bend_value;
    reg [6:0] mod_value;
    assign bend=enabled ? bend_value:16'sd0;
    assign modulation=enabled ? mod_value:7'd0;
    assign center_ready=seen_x && seen_y;
    reg [11:0] value,center,endpoint;
    reg [12:0] magnitude,span;
    reg low_side,fresh;
    always @* begin
        value=next_job[0] ? y:x;center=next_job[0] ? Y_CENTER:X_CENTER;
        low_side=value<center;
        endpoint=next_job[0] ? (low_side ? Y_MIN:Y_MAX):(low_side ? X_MIN:X_MAX);
        magnitude=low_side ? {1'b0,center}-{1'b0,value}:{1'b0,value}-{1'b0,center};
        span=low_side ? {1'b0,center}-{1'b0,endpoint}:{1'b0,endpoint}-{1'b0,center};
        fresh=next_job[0] ? seen_y && age_y<4800:seen_x && age_x<4800;
        if(magnitude>span)magnitude=span;
        // Keep the complete calibrated travel; integer quantization is the
        // only rounding near center. Missing/stale axes still return neutral.
        if(!fresh)magnitude=0;
        if(span==0)span=1;
    end
    wire [6:0] percent=joy_percent>100 ? 7'd100:joy_percent;
    reg [21:0] y_square;
    reg [17:0] y_strength,x_strength;
    reg [24:0] mod_numerator;
    wire [31:0] bend_numerator=({14'd0,y_strength}<<13)-{14'd0,y_strength};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            x<=X_CENTER;y<=Y_CENTER;seen_x<=0;seen_y<=0;age_x<=8191;age_y<=8191;
            x_norm<=0;y_norm<=0;x_low<=0;y_low<=0;
            next_job<=0;work_job<=0;work_low<=0;dividing<=0;div_count<=0;
            numerator<=0;quotient<=0;remainder<=0;divisor<=1;
            y_square<=0;y_strength<=0;x_strength<=0;mod_numerator<=0;bend_value<=0;mod_value<=0;
        end else begin
            y_square<=y_norm*y_norm;
            y_strength<=y_square[20:10]*percent;
            x_strength<=x_norm*percent;
            mod_numerator<=x_strength*(x_low ? 7'd127:7'd32)+25'd51200;
            if(joy_valid)begin
                if(joy_axis)begin y<=joy_data;seen_y<=1;age_y<=0;end
                else begin x<=joy_data;seen_x<=1;age_x<=0;end
            end
            if(sample_tick)begin
                if(!joy_valid || !joy_axis)begin if(age_y<8191)age_y<=age_y+1'b1;end
                if(!joy_valid || joy_axis)begin if(age_x<8191)age_x<=age_x+1'b1;end
                if(!dividing)begin
                    work_job<=next_job;next_job<=next_job+1'b1;
                    work_low<=next_job==2 ? y_low:low_side;
                    if(next_job<2)begin numerator<={9'd0,magnitude,10'd0};divisor<={4'd0,span};end
                    else if(next_job==2)begin numerator<=bend_numerator;divisor<=102400;end
                    else begin numerator<={7'd0,mod_numerator};divisor<=102400;end
                    quotient<=0;remainder<=0;div_count<=0;dividing<=1;
                end
            end
            if(dividing)begin
                numerator<={numerator[30:0],1'b0};quotient<=next_quotient;
                remainder<=take_bit ? reduced[16:0]:trial[16:0];
                if(div_count==31)begin
                    dividing<=0;
                    case(work_job)
                        0:begin x_norm<=next_quotient>1024 ? 11'd1024:next_quotient[10:0];x_low<=work_low;end
                        1:begin y_norm<=next_quotient>1024 ? 11'd1024:next_quotient[10:0];y_low<=work_low;end
                        2:bend_value<=work_low ? $signed(next_quotient[15:0]):-$signed(next_quotient[15:0]);
                        3:mod_value<=next_quotient>127 ? 7'd127:next_quotient[6:0];
                    endcase
                end else div_count<=div_count+1'b1;
            end
        end
    end
endmodule
