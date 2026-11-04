`timescale 1ns/1ps
module tb_fast_hit;
reg clk=0;always #10 clk=~clk;
reg rst=0,enabled=1,valid=0;reg signed [31:0] x=0,y=0,z=0;
integer div=0,ms=0,hits=0,rhits=0,last=-100;wire tick=div==9;
always @(posedge clk)begin if(div==9)begin div<=0;ms<=ms+1;end else div<=div+1;end
wire hit,rhit;wire [1:0] direction;wire armed;
pose_hit #(.UP_X(1024),.UP_Z(0),.SIDE_X(0),.SIDE_Z(1024)) dut(.clk(clk),.rst_n(rst),.clear(1'b0),.enabled(enabled),.valid(valid),.neutral(1'b0),.quiet(1'b0),.wx(x),.wy(y),.wz(z),.ms_tick(tick),.threshold(16'd160),.cooldown_ms(16'd20),.hit(hit),.direction(direction),.velocity(),.armed(armed),.phase());
pose_hit #(.PHYSICAL_RIGHT(1),.UP_X(1024),.UP_Z(0),.SIDE_X(0),.SIDE_Z(1024)) right(.clk(clk),.rst_n(rst),.clear(1'b0),.enabled(enabled),.valid(valid),.neutral(1'b0),.quiet(1'b0),.wx(x),.wy(y),.wz(z),.ms_tick(tick),.threshold(16'd160),.cooldown_ms(16'd20),.hit(rhit),.direction(),.velocity(),.armed(),.phase());
always @(negedge clk)begin if(hit)begin if(ms-last<20)$fatal(1,"minimum interval");last=ms;hits=hits+1;end if(rhit)rhits=rhits+1;end
task sample(input integer a,b);begin x=a;z=b;valid=1;@(negedge clk);valid=0;repeat(49)@(negedge clk);end endtask
task zero(input integer n);repeat(n)sample(0,0);endtask
task resetter;begin rst=0;repeat(5)@(negedge clk);rst=1;hits=0;rhits=0;last=-100;zero(1);end endtask
integer before_hits;
initial begin
repeat(3)@(negedge clk);resetter();
sample(40000,0);if(hits!=1 || rhits!=1)$fatal(1,"first fast simultaneous hit");
repeat(12)sample(40000,0);if(hits!=1)$fatal(1,"held excursion repeats");
zero(4);sample(40000,0);if(hits!=2)$fatal(1,"retrigger without quiet");
// Chatter above release cannot rearm.
repeat(12)begin sample(9000,0);sample(7000,0);end
if(hits!=2)$fatal(1,"threshold chatter");
resetter();sample(0,-40000);if(hits!=0 || dut.cooldown!=0)$fatal(1,"unsupported direction consumed cooldown");
zero(4);sample(40000,0);if(hits!=1)$fatal(1,"valid hit after invalid direction");
// Cross during cooldown, then hold beyond expiry: no delayed hit.
resetter();sample(20000,0);zero(2);sample(40000,0);before_hits=hits;
repeat(10)sample(40000,0);if(hits!=before_hits)$fatal(1,"deferred cooldown hit");
zero(4);sample(40000,0);if(hits!=before_hits+1)$fatal(1,"new excursion after cooldown");
enabled=0;sample(40000,0);enabled=1;sample(40000,0);if(armed)$fatal(1,"enable without release");
resetter();repeat(10)begin sample(20000,0);zero(3);end
if(hits!=10)$fatal(1,"20 ms train missed hits: %0d",hits);
$display("PASS 20-ms train, fast rearm, dual sticks, held stroke, chatter, invalid side, cooldown no deferred hit, enable release");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
