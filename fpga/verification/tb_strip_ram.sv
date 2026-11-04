`timescale 1ns/1ps
module tb_strip_ram;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,write_valid=0,write_right=0,commit_valid=0;
 reg [6:0] write_index=0;reg [23:0] write_rgb=0;
 wire commit_ready,serialL,serialR;
 drum_strip_rgb_ram dut(.clk(clk),.rst_n(rst_n),.write_valid(write_valid),.write_right(write_right),.write_index(write_index),.write_rgb(write_rgb),.commit_valid(commit_valid),.commit_ready(commit_ready),.legacy_mode(1'b0),.force_black(1'b0),.legacyL(24'd0),.legacyR(24'd0),.serialL(serialL),.serialR(serialR));
 function [23:0] pattern(input integer i,input bit right_side);begin pattern=right_side ? {8'(79-i),8'(i^8'h33),8'(i^8'hcc)}:{8'(i),8'(i^8'h55),8'(i^8'haa)};end endfunction
 function [23:0] grb(input [23:0] c);grb={c[15:8],c[23:16],c[7:0]};endfunction
 task fill(input bit solid);integer i;begin
  for(i=0;i<160;i=i+1)begin @(negedge clk);write_valid=1;write_right=i>=80;write_index=7'(i%80);write_rgb=solid ? (i>=80 ? 24'h102030:24'habcdef):pattern(i%80,i>=80);end
  @(negedge clk);write_valid=0;
 end endtask
 task commit;begin @(negedge clk);commit_valid=1;wait(commit_ready);@(posedge clk);@(negedge clk);commit_valid=0;end endtask
 integer i,j;time t0,previous_rise;reg bL,bR;reg [23:0] wL,wR;
 task decode(input bit solid);begin
  @(posedge serialL);previous_rise=$time;
  for(i=0;i<80;i=i+1)begin
   wL=0;wR=0;
   for(j=0;j<24;j=j+1)begin
    if(i!=0 || j!=0)begin @(posedge serialL);if($time-previous_rise!=1280)$fatal(1,"inter-bit gap");previous_rise=$time;end
    t0=$time;
    fork
     begin @(negedge serialL);if($time-t0!=320 && $time-t0!=880)$fatal(1,"L pulse");bL=$time-t0==880;end
     begin @(negedge serialR);if($time-t0!=320 && $time-t0!=880)$fatal(1,"R pulse");bR=$time-t0==880;end
    join
    wL={wL[22:0],bL};wR={wR[22:0],bR};
   end
   if(wL!=grb(solid ? 24'habcdef:pattern(i,0)) || wR!=grb(solid ? 24'h102030:pattern(i,1)))$fatal(1,"pixel%0d L%h R%h",i,wL,wR);
  end
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;fill(0);commit();
  fork decode(0);begin wait(dut.sending);fill(1);commit();end join
  decode(1);
  $display("PASS: dual synchronous RAM, all80 unique L/R pixels, exact GRB pulses/no gaps, inactive-bank writes, atomic swap");$finish;
 end
 initial begin #20000000;$fatal(1,"watchdog");end
endmodule
