`timescale 1ns/1ps
module tb_route_dirty;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,wv=0,wr=0,cv=0;reg[6:0] wi=0;reg[23:0] rgb=0;reg[1:0] refresh=0;
 reg[17:0] phase=0;always @(posedge clk)if(!rst_n)phase<=0;else phase<=phase==249999?0:phase+1'b1;
 wire window=phase>=100000,launch=phase==102500,ready,l,r;
 drum_strip_rgb_ram dut(.clk(clk),.rst_n(rst_n),.slot_launch(launch),.slot_window(window),.force_refresh(refresh),.write_valid(wv),.write_right(wr),.write_index(wi),.write_rgb(rgb),.commit_valid(cv),.commit_ready(ready),.legacy_mode(1'b0),.force_black(1'b0),.legacyL(24'd0),.legacyR(24'd0),.serialL(l),.serialR(r));
 wire refready,refl,refr; drum_strip_rgb_ram_reference refdut(.clk(clk),.rst_n(rst_n),.slot_launch(launch),.slot_window(window),.force_refresh(refresh),.write_valid(wv),.write_right(wr),.write_index(wi),.write_rgb(rgb),.commit_valid(cv),.commit_ready(refready),.legacy_mode(1'b0),.force_black(1'b0),.legacyL(24'd0),.legacyR(24'd0),.serialL(refl),.serialR(refr));
 always @(negedge clk)if(rst_n && {ready,l,r}!=={refready,refl,refr})$fatal(1,"sender cycle mismatch");
 reg pattern=0;integer lc=0,rc=0;
 always @(posedge l)begin lc=lc+1;if(!window)$fatal(1,"L outside RGB slot");end
 always @(posedge r)begin rc=rc+1;if(!window)$fatal(1,"R outside RGB slot");end
 task frame(input[23:0] leftc,rightc,input integer el,er);
 integer i,sl,sr;begin
  sl=lc;sr=rc;
  for(i=0;i<160;i=i+1)begin @(negedge clk);wv=1;wr=i>=80;wi=7'(i%80);rgb=(wr?rightc:leftc) ^ (pattern ? 24'(i*123457):24'd0);end
  @(negedge clk);wv=0;cv=1;wait(ready);@(posedge clk);@(negedge clk);cv=0;
  wait(dut.state==0);repeat(3)@(negedge clk);
  if(lc-sl!=el || rc-sr!=er)$fatal(1,"pulses L=%0d R=%0d expected %0d/%0d",lc-sl,rc-sr,el,er);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  frame(0,0,1920,1920);frame(0,0,0,0);
  frame('hff0000,0,1920,0);frame('hff0000,0,0,0);
  frame('hff0000,'h112233,0,1920);
  refresh=1;@(negedge clk);refresh=0;frame('hff0000,'h112233,1920,0);
  frame('hff0000,'h112233,0,0);
  pattern=1;frame('h112233,'habcdef,1920,1920);frame('h112233,'habcdef,0,0);
  pattern=0;frame(0,0,1920,1920);frame(0,0,0,0);
  $display("PASS cycle-exact reference equivalence, unique80 pixels, dirty: initial black, unchanged suppression, independent strips, refresh, strict slots");$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
