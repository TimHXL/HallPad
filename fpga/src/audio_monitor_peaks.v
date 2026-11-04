`timescale 1ns/1ps
// Two streaming passes over raw positive-frequency FFT bins.
// Pass 0 finds the strongest local maximum; pass 1 finds the strongest
// remaining maximum outside its +/-2-bin Hann main lobe. No magnitude RAM.
module audio_monitor_peaks(
    input wire clk,rst_n,start_pass,second_pass,sample_valid,finish_pass,
    input wire [9:0] bin,
    input wire [17:0] magnitude,
    output reg [9:0] first_bin,second_bin,
    output reg [17:0] first_magnitude,second_magnitude
);
    reg [17:0] left_magnitude,middle_magnitude;
    reg [9:0] middle_bin;
    wire [17:0] right_magnitude=finish_pass ? 18'd0:magnitude;
    wire local_peak=middle_bin>=10'd17 && middle_magnitude>=18'd8 &&
        middle_magnitude>=left_magnitude && middle_magnitude>right_magnitude;
    wire [9:0] separation=middle_bin>=first_bin ? middle_bin-first_bin:first_bin-middle_bin;
    wire eligible_second=separation>10'd2 && middle_magnitude>=(first_magnitude>>5);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            left_magnitude<=0;middle_magnitude<=0;middle_bin<=0;
            first_bin<=0;second_bin<=0;first_magnitude<=0;second_magnitude<=0;
        end else if(start_pass)begin
            left_magnitude<=0;middle_magnitude<=0;middle_bin<=0;
            if(!second_pass)begin first_bin<=0;first_magnitude<=0;end
            else begin second_bin<=0;second_magnitude<=0;end
        end else if(sample_valid || finish_pass)begin
            if(local_peak)begin
                if(!second_pass && middle_magnitude>first_magnitude)begin
                    first_bin<=middle_bin;first_magnitude<=middle_magnitude;
                end else if(second_pass && eligible_second && middle_magnitude>second_magnitude)begin
                    second_bin<=middle_bin;second_magnitude<=middle_magnitude;
                end
            end
            if(sample_valid)begin
                left_magnitude<=middle_magnitude;middle_magnitude<=magnitude;middle_bin<=bin;
            end
        end
    end
endmodule

