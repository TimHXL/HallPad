`timescale 1ns/1ps
module tb_v7_xy;
reg clk=0;always #10 clk=~clk;reg rst_n=0,tick=0,lock=0;reg[13:0]addr=0;integer div=0,i,lit=0;wire valid,pixel;
always @(negedge clk)begin tick=div==99;if(div==99)div=0;else div=div+1;end
audio_lissajous #(.FRAME_SAMPLES(64)) d(.clk(clk),.rst_n(rst_n),.enable(1'b1),.sample_tick(tick),.peak_bin_x(10'd40),.peak_bin_y(10'd80),.peak_magnitude_x(18'd64),.peak_magnitude_y(18'd32),.read_address(addr),.display_lock(lock),.pixel(pixel),.valid(valid));
initial begin repeat(3)@(negedge clk);rst_n=1;wait(valid);@(negedge clk);lock=1;repeat(3)@(negedge clk);
for(i=0;i<16384;i=i+1)begin addr=14'(i);repeat(2)@(negedge clk);if(pixel)lit=lit+1;end
if(lit<20 || lit>4000)$fatal(1,"invalid XY bitmap %d",lit);
$display("PASS XY publishes non-empty 128x128 bitmap and display lease; lit=%d",lit);$finish;end
initial begin #2000000;$fatal(1,"XY timeout");end
endmodule
