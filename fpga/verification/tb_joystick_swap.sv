`timescale 1ns/1ps
module tb_joystick_swap;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0,joy_valid=0,joy_axis=0;
 reg [11:0] joy_data=0;
 wire signed [15:0] bend;wire [6:0] modulation;wire center_ready;
 joystick_pitch_bend dut(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.joy_percent(7'd100),.joy_valid(joy_valid),.joy_axis(joy_axis),.joy_data(joy_data),.bend(bend),.modulation(modulation),.center_ready(center_ready));
 task settle(input [11:0] x,input [11:0] y);integer i;begin
  for(i=0;i<4096;i=i+1)begin @(negedge clk);sample_tick=(i%64)==0;joy_valid=1;joy_axis=i[0];joy_data=i[0] ? y:x;end
  @(negedge clk);sample_tick=0;
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  settle(5,1390);if(modulation!=127 || bend!=0)$fatal(1,"low X mod %d bend%d",modulation,bend);
  settle(2538,1390);if(modulation!=32 || bend!=0)$fatal(1,"high X mod %d",modulation);
  settle(1245,122);if(bend!=8191 || modulation!=0)$fatal(1,"Y up changed %d",bend);
  settle(1245,2606);if(bend!=-8191 || modulation!=0)$fatal(1,"Y down changed %d",bend);
  $display("PASS: left/right depth exchanged; Y pitch up/down unchanged");$finish;
 end
endmodule
