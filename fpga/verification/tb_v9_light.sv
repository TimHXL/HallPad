`timescale 1ns/1ps
module tb_v9_light;
 reg clk=0;always #10 clk=~clk;reg rst=0,active=1,long_note=0,holding=0;reg[34:0]mask=0,yellow=0,green=0,red=0;wire[839:0]pixels;wire update;
 keyboard_light_runtime #(.USE_PRACTICE_GUIDE(1),.USE_PALETTE_SOURCE(1),.USE_RIPPLE_ENVELOPE(1)) d(.clk(clk),.rst_n(rst),.ripple_pixels(840'd0),.solid_rgb(24'd0),.palette_indices(105'd0),.practice_active(active),.practice_long(long_note),.practice_holding(holding),.practice_mask(mask),.practice_yellow(yellow),.practice_green(green),.practice_red(red),.ripple_intensities(315'd0),.brightness(6'd0),.light_mode(2'd2),.pixels_rgb(pixels),.frame_update(update));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task frame;begin cycles(230);end endtask
 initial begin cycles(3);rst=1;mask=35'd1<<20;frame();if(pixels[20*24+:24]!=24'h000808)$fatal(1,"local follow target not visible");
 long_note=1;frame();if(pixels[20*24+:24]!=24'h080400)$fatal(1,"long note amber");
 yellow=mask;frame();if(pixels[20*24+:24]!=24'h080800)$fatal(1,"held-too-short yellow");yellow=0;green=mask;frame();if(pixels[20*24+:24]!=24'h000800)$fatal(1,"passed green");
 green=0;mask=35'd1<<14;long_note=0;frame();if(pixels[14*24+:24]!=24'h000808 || pixels[20*24+:24]!=0)$fatal(1,"auto held mask light transfer");
 mask=0;frame();if(pixels!=0)$fatal(1,"release light");$display("PASS LED output: follow targets, long amber, incomplete yellow, complete green, auto held-mask, release; global mode OFF/brightness0 still guide visible");$finish;end
endmodule
