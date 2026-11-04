`timescale 1ns/1ps
module tb_drum_control;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,ms_tick=0,drum_view=0,request=0;
 reg [1:0] inserted=3,online=3,valid=3,pose_fault=0,overflow=0;
 wire [1:0] calibrated,active;
 wire [15:0] progress;
 wire ready,begin_cal,abort_cal;
 wire [95:0] status;
 wire [111:0] r0,r1;
 // az=2048, little-endian byte transport, all gyro channels zero.
 logger_calibration cal(.clk(clk),.rst_n(rst_n),.begin_cal(begin_cal),.abort_cal(abort_cal),
 .online(online&inserted),.valid(valid),.data0(112'h0000000000000000000800000000),
 .data1(112'h0000000000000000000800000000),.calibrated(calibrated),.active(active),.progress(progress),.result0(r0),.result1(r1));
 drum_cal_control ctrl(.*);
 reg hit=0,stick=0;
 reg [31:0] color_settings=32'hff702000;
 reg [47:0] settings={16'd4,16'd2,8'd100,8'd1};
 wire [23:0] rgbL,rgbR;
 drum_hit_lights #(.CHORD_CYCLES(1000)) lights(.*);
 reg [2:0] saved_color;
 integer starts=0;
 always @(posedge clk)if(begin_cal)starts<=starts+1;
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task tick;begin ms_tick=1;cycles(1);ms_tick=0;cycles(300);end endtask
 task ticks(input integer n);repeat(n)tick();endtask
 task strike(input bit right);begin stick=right;hit=1;cycles(1);hit=0;cycles(2);end endtask
 initial begin
  cycles(2);rst_n=1;cycles(2);
  ticks(110);if(starts!=0 || active!=0 || calibrated!=0)$fatal(1,"power-up calibration");
  drum_view=1;ticks(105);
  if(starts!=1 || status[55:48]!=3 || calibrated!=3)$fatal(1,"first-entry calibration %h %d",status,starts);
  drum_view=0;ticks(5);drum_view=1;ticks(110);if(starts!=1)$fatal(1,"re-entry repeated");
  inserted=1;ticks(2);inserted=3;ticks(110);if(starts!=1 || active!=0 || status[55:48]!=4)$fatal(1,"reconnect repeated");
  request=1;cycles(1);request=0;ticks(106);if(starts!=2 || status[55:48]!=3)$fatal(1,"manual retry");
  pose_fault=1;ticks(2);ticks(110);if(starts!=2 || status[63:56]!=3)$fatal(1,"fault repeated");pose_fault=0;
  valid=0;request=1;cycles(1);request=0;ticks(10102);
  if(starts!=3 || active!=0 || status[63:56]!=2)$fatal(1,"timeout did not abort");
  valid=3;ticks(110);if(starts!=3 || calibrated!=0)$fatal(1,"timeout resumed itself");
  request=1;cycles(1);request=0;ticks(106);if(starts!=4 || calibrated!=3)$fatal(1,"timeout retry");
  online=0;request=1;cycles(1);request=0;ticks(5);
  if(status[55:48]!=1 || starts!=4)$fatal(1,"offline retry must wait");
  online=3;ticks(106);if(starts!=5 || calibrated!=3)$fatal(1,"offline retry failed");
  strike(0);strike(1);
  if(lights.colors[0]!=lights.colors[1])$fatal(1,"chord colors differ");
  ticks(2);cycles(5);if(rgbL==0 || rgbR==0 || lights.level[0]!=256)$fatal(1,"attack failed");
  ticks(4);cycles(5);if(rgbL!=0 || rgbR!=0)$fatal(1,"decay failed");
  settings[47:32]=0;strike(0);ticks(2);cycles(5);if(rgbL==0)$fatal(1,"hold did not light");
  ticks(15);if(rgbL==0)$fatal(1,"zero decay did not hold");
  saved_color=lights.current_color;
  color_settings=32'h0000ff01;cycles(5);
  if(rgbL!=24'hff0000 || lights.level[0]!=256)$fatal(1,"live RGB reset envelope");
  strike(1);ticks(2);cycles(5);if(rgbR!=24'hff0000 || lights.current_color!=saved_color)$fatal(1,"custom hit advanced palette");
  color_settings=32'h00000001;cycles(5);if(rgbL!=0 || lights.level[0]!=256)$fatal(1,"black RGB");
  color_settings=32'hffffff00;cycles(5);
  if(rgbL!=lights.palette(lights.indices[0]) || lights.current_color!=saved_color)$fatal(1,"restore cycle");
  settings[15:8]=0;cycles(5);if(rgbL!=0)$fatal(1,"zero brightness");
  settings[15:8]=100;settings[0]=0;cycles(5);if(rgbL!=0 || rgbR!=0)$fatal(1,"disable failed");
  $display("PASS: power-up/first-entry/re-entry/reconnect/fault/timeout/manual calibration; chord/attack/decay/hold/brightness/off/live RGB/black/palette preservation");$finish;
 end
 initial begin #200000000;$fatal(1,"watchdog");end
endmodule
