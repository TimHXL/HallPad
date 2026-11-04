`timescale 1ns/1ps
// Linear 1 ms envelope. 128 gain steps; repeated subtraction is bounded to
// 130 clocks/key/ms, so every pass completes within 4550 clocks at 50 MHz.
// Zero duration bypasses the corresponding user stage; built-in timbre ADSR stays.
module hallpad_key_envelope(input wire clk,rst_n,ms_tick,input wire [35:0] gates,input wire [12:0] attack_ms,input wire [13:0] release_ms,output wire [323:0] gains,output wire [35:0] extended_gates);
reg [7:0] level[0:35];reg [14:0] residue[0:35];reg [35:0] previous;
reg [5:0] index;reg active;reg direction;reg [14:0] work;reg [13:0] duration;reg [7:0] value;reg step;
integer k;genvar g;
generate for(g=0;g<36;g=g+1)begin:gen_output
assign gains[g*9 +:9]=(gates[g] && attack_ms==0) || (!gates[g] && release_ms==0) ? 9'd256:{level[g],1'b0};
assign extended_gates[g]=gates[g] || (release_ms!=0 && level[g]!=0);
end endgenerate
always @(posedge clk or negedge rst_n)begin
if(!rst_n)begin previous<=0;index<=0;active<=0;direction<=0;work<=0;duration<=0;value<=0;step<=0;for(k=0;k<36;k=k+1)begin level[k]<=0;residue[k]<=0;end end
else begin
if(!active)begin if(ms_tick)begin active<=1;index<=0;step<=0;end end
else if(!step)begin
 direction<=gates[index];duration<=gates[index]?{1'b0,attack_ms}:release_ms;
 value<=gates[index] && !previous[index] ? 0:level[index];
 work<=((gates[index]!=previous[index]) ? 15'd0:residue[index])+15'd128;
 previous[index]<=gates[index];step<=1;
end else if(duration==0)begin level[index]<=direction?128:0;residue[index]<=0;step<=0;if(index==35)active<=0;else index<=index+1'b1;end
else if(work>=duration && (direction ? value<128:value!=0))begin work<=work-{1'b0,duration};value<=direction?value+1'b1:value-1'b1;end
else begin level[index]<=value;residue[index]<=(direction && value==128) || (!direction && value==0) ? 0:work;step<=0;if(index==35)active<=0;else index<=index+1'b1;end
// Preserve release tails even when an instantaneous-attack note lasts <1 ms.
for(k=0;k<36;k=k+1)begin
    if(gates[k] && attack_ms==0)begin level[k]<=128;residue[k]<=0;end
end
end
end
endmodule
