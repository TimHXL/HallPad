`timescale 1ns/1ps
module tb_v7_delay;
reg clk=0;always #10 clk=~clk;reg rst_n=0,enabled=1,clear=0,trigger=0,accepted=0,rendered=0,tick=0;
wire busy,valid,armed;wire[15:0]us;integer cycles_from_trigger=0,count=0;
keyboard_response_monitor #(.OUTPUT_BOUNDARIES(3)) d(.clk(clk),.rst_n(rst_n),.enabled(enabled),.clear(clear),.trigger(trigger),.trigger_key(6'd5),.accepted(accepted),.accepted_key(6'd5),.accepted_revision(8'd2),.rendered(rendered),.sample_tick(tick),.probe_armed(armed),.busy(busy),.valid(valid),.elapsed_us(us));
always @(negedge clk)if(busy)cycles_from_trigger=cycles_from_trigger+1;
task clocks(input integer n);repeat(n)@(negedge clk);endtask
initial begin
clocks(3);rst_n=1;trigger=1;clocks(1);trigger=0;accepted=1;clocks(1);accepted=0;clocks(98);
if(!armed)$fatal(1,"render marker not armed");rendered=1;clocks(1);rendered=0;
repeat(3)begin clocks(50);tick=1;clocks(1);tick=0;end
if(!valid || busy || us<4 || us>6)$fatal(1,"timer %d",us);
trigger=1;clocks(1);trigger=0;clocks(3);trigger=1;clocks(1);trigger=0;clocks(1);if(busy || valid)$fatal(1,"retrigger stale result");
trigger=1;clocks(1);trigger=0;enabled=0;clocks(1);if(busy || valid)$fatal(1,"disabled retained measurement");
$display("PASS internal delay event/revision/render/boundary counter; retrigger/disable invalidation (does not validate physical output or constant68)");$finish;
end
endmodule
