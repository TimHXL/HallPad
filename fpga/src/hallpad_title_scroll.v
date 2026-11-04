`timescale 1ns/1ps
module hallpad_title_scroll(input wire clk,rst_n,valid,input wire [5:0] count,input wire [7:0] revision,output reg [4:0] offset,pixel);
 reg [25:0] phase;reg [7:0] last_revision;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;offset<=0;pixel<=0;last_revision<=0;end
  else if(!valid || count<=8 || last_revision!=revision)begin phase<=0;offset<=0;pixel<=0;last_revision<=revision;end
  else if(phase>=26'd49999967)begin
   phase<=phase+26'd33-26'd50000000;
   if(pixel==21)begin pixel<=0;offset<={1'b0,offset}+1>=count ? 5'd0:offset+1'b1;end
   else pixel<=pixel+1'b1;
  end else phase<=phase+26'd33;
 end
endmodule
