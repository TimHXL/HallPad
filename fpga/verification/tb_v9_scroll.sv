`timescale 1ns/1ps
module tb_v9_scroll;
 reg clk=0;always #10 clk=~clk;reg rst=0,valid=1;reg[5:0]count=32;reg[7:0]revision=1;wire[4:0]offset,pixel;
 hallpad_title_scroll d(clk,rst,valid,count,revision,offset,pixel);
 initial begin repeat(3)@(negedge clk);rst=1;@(negedge clk);repeat(50000000)@(negedge clk);
 if(offset!=1 || pixel!=11 || d.phase!=0)$fatal(1,"not exactly 33 pixels/sec offset%d pixel%d phase%d",offset,pixel,d.phase);
 revision=2;@(negedge clk);if(offset!=0 || pixel!=0)$fatal(1,"title change reset");count=8;repeat(10)@(negedge clk);if(pixel || offset || d.phase)$fatal(1,"short title moved");
 $display("PASS exact 33px/sec over 50 million clocks; no character stepping; title change reset and short title stationary");$finish;end
endmodule
