`timescale 1ns/1ps
module tb_kick_compare;
reg clk=0;always #10 clk=~clk;
reg rst=0,event_valid=0;reg [2:0] voice=1;wire tick=divider==1041;integer divider=0;
always @(posedge clk)if(!rst)divider<=0;else if(tick)divider<=0;else divider<=divider+1;
wire signed [23:0] pcm,oldpcm;wire pv,opv,ready,oldready,overrun,oldoverrun;
drum_synth dut(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(event_valid),.event_voice(voice),.event_velocity(7'd127),.event_ready(),.pcm_wide(pcm),.pcm_valid(pv),.overrun(overrun),.ready(ready));
drum_synth_old old(.clk(clk),.rst_n(rst),.sample_tick(tick),.event_valid(event_valid),.event_voice(voice),.event_velocity(7'd127),.event_ready(),.pcm_wide(oldpcm),.pcm_valid(opv),.overrun(oldoverrun),.ready(oldready));
integer count=0,newfile,oldfile,i,differences=0;
always @(negedge clk)if(rst)begin
 if(overrun || oldoverrun)$fatal(1,"audio frame overrun");
 if(pv && opv)begin
 count=count+1;
 if(voice==1)begin $fdisplay(newfile,"%0d",pcm);$fdisplay(oldfile,"%0d",oldpcm);if(pcm!=oldpcm)differences=differences+1;end
 else if(pcm!==oldpcm)$fatal(1,"non-kick voice %0d changed",voice);
 end
end
task restart(input integer v);begin
rst=0;voice=v;event_valid=0;repeat(5)@(negedge clk);rst=1;wait(ready && oldready);@(negedge clk);event_valid=1;@(negedge clk);event_valid=0;count=0;
end endtask
initial begin
newfile=$fopen("kick_new_pcm.txt","w");oldfile=$fopen("kick_old_pcm.txt","w");
restart(1);wait(count>=31200);@(negedge clk);if(differences<100)$fatal(1,"kick unchanged");
for(i=0;i<6;i=i+1)if(i!=1)begin restart(i);wait(count>=960);@(negedge clk);end
$fclose(newfile);$fclose(oldfile);$display("PASS changed kick, other five voices bit-identical, no audio frame overrun");$finish;
end
initial begin #1000000000;$fatal(1,"timeout");end
endmodule
