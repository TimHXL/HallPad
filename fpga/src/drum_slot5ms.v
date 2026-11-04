`timescale 1ns/1ps
// 250000 clocks = 5 ms at 50 MHz. Never stretch the frame.
module drum_slot5ms(input wire clk,rst_n,output wire read_launch,abort_bus,rgb_launch,rgb_window,
 output reg [17:0] phase);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)phase<=0;else if(phase==249999)phase<=0;else phase<=phase+1'b1;end
 assign read_launch=phase==100; // 2 us guard after frame boundary
 assign abort_bus=phase==99998; // release bus before 2 ms boundary
 assign rgb_window=phase>=100000;
 assign rgb_launch=phase==102500; // 50 us guard within the LED window
endmodule
