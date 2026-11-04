`timescale 1ns/1ps
// SPI mode 0, one byte, MSB first. Chip-select is owned by the block controller.
module logger_spi_byte(input wire clk,rst_n,start,input wire [7:0] tx,
 input wire [7:0] half_cycles,input wire miso,
 output reg sck,mosi,busy,done,output reg [7:0] rx);
 reg [7:0] count,shift;
 reg [2:0] bit_index;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sck<=0;mosi<=1;busy<=0;done<=0;rx<=0;count<=0;shift<=0;bit_index<=0;end
  else begin
   done<=0;
   if(!busy)begin
    sck<=0;
    if(start)begin busy<=1;shift<=tx;mosi<=tx[7];rx<=0;count<=0;bit_index<=7;end
   end else if(count==half_cycles-1)begin
    count<=0;
    if(!sck)begin sck<=1;rx<={rx[6:0],miso};end
    else begin
     sck<=0;
     if(bit_index==0)begin busy<=0;done<=1;mosi<=1;end
     else begin bit_index<=bit_index-1'b1;shift<={shift[6:0],1'b1};mosi<=shift[6];end
    end
   end else count<=count+1'b1;
  end
 end
endmodule
