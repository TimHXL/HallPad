`timescale 1ns/1ps
module tb_drum80;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,ms_tick=0,hit=0,stick=0,effect_active=1;
 reg [47:0] settings={16'd1200,16'd40,8'd100,8'd1};
 reg [31:0] color_settings=32'hff702000;
 reg [71:0] effect_config={24'h0000ff,16'd200,16'd30000,8'd100,8'd0};
 wire [1919:0] pixelsL,pixelsR;
 drum_strip_lights #(.CHORD_CYCLES(1000)) dut(.*);
 wire serialL,serialR;
 genvar g;generate for(g=0;g<80;g=g+1)begin:monitor
  assign pixelsL[g*24+:24]=dut.output_ram.frame_black ? 24'd0:dut.output_ram.frame_legacy ? dut.output_ram.frame_legacyL:dut.output_ram.memL[{dut.output_ram.active_bank,7'(g)}];
  assign pixelsR[g*24+:24]=dut.output_ram.frame_black ? 24'd0:dut.output_ram.frame_legacy ? dut.output_ram.frame_legacyR:dut.output_ram.memR[{dut.output_ram.active_bank,7'(g)}];
 end endgenerate
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task tick;begin ms_tick=1;cycles(1);ms_tick=0;cycles(11000);end endtask
 task ticks(input integer n);repeat(n)tick();endtask
 task strike(input bit r);begin stick=r;hit=1;cycles(1);hit=0;cycles(3);end endtask
 function [23:0] lp(input integer i);lp=pixelsL[i*24+:24];endfunction
 function [23:0] rp(input integer i);rp=pixelsR[i*24+:24];endfunction
 integer i,j;time t0;reg [23:0] grb;reg [2:0] old_color;
 initial begin
  cycles(3);rst_n=1;cycles(280000);if(pixelsL!=0 || pixelsR!=0)$fatal(1,"water lights without hit");
  strike(0);strike(1);cycles(280000);
  if(lp(0)==0 || rp(0)==0 || lp(1)!=0 || rp(1)!=0 || dut.colorL!=dut.colorR)$fatal(1,"bottom/chord");
  ticks(33);if(lp(1)!=0)$fatal(1,"pixel1 arrived early");tick();cycles(280000);if(lp(1)==0 || lp(2)!=0)$fatal(1,"speed/ceil arrival");
  old_color=dut.colorL;cycles(1001);strike(0);cycles(280000);
  if(lp(1)==0 || lp(0)==0 || dut.colorL==old_color || rp(1)==0)$fatal(1,"retrigger isolation/palette");
  ticks(34);cycles(280000);if(lp(1)==0 || lp(1)==rp(1))$fatal(1,"new wave must recolor reached pixel");
  ticks(2600);cycles(280000);if(lp(79)==0 || lp(0)==0)$fatal(1,"top propagation/fade");
  ticks(200);cycles(280000);if(lp(0)==0)$fatal(1,"retained floor missing");
  effect_config[31:16]=500;cycles(280000);strike(0);cycles(280000);
  ticks(1999);if(lp(1)==0)$fatal(1,"minimum speed early");tick();cycles(280000);if(lp(1)==0)$fatal(1,"minimum speed late");
  effect_config[7:0]=1;effect_config[71:48]=24'h0000ff;cycles(280000);
  for(i=0;i<80;i=i+1)if(lp(i)!=24'hff0000 || rp(i)!=24'hff0000)$fatal(1,"solid80 pixel%d",i);
  // Allow the in-flight frame to finish, then decode an entire 80-pixel GRB frame.
  wait(!dut.output_ram.sending);@(posedge serialL);
  for(i=0;i<80;i=i+1)begin
   grb=0;
   for(j=0;j<24;j=j+1)begin
    if(i!=0 || j!=0)@(posedge serialL);
    t0=$time;@(negedge serialL);grb={grb[22:0],($time-t0)>600};
   end
   if(grb!=24'h00ff00)$fatal(1,"GRB serializer pixel%d got%h",i,grb);
  end
  effect_config[15:8]=0;cycles(280000);if(pixelsL!=0 || pixelsR!=0)$fatal(1,"brightness0");
  effect_config[15:8]=100;effect_config[7:0]=2;cycles(280000);if(pixelsL!=0 || pixelsR!=0)$fatal(1,"off");
  effect_config[7:0]=0;cycles(280000);if(pixelsL!=0 || pixelsR!=0)$fatal(1,"mode resurrected wave");
  $display("PASS: 80 pixels each; bottom-to-top, speed 500/30000, chord color, retrigger/isolation, fade, solid80, brightness/off, no resurrection, 80-pixel GRB serialization");$finish;
 end
 initial begin #2000000000;$fatal(1,"watchdog");end
endmodule
