`timescale 1ns/1ps
// Exclusive, session-bound block transport. FAT32 transactions live in the phone.
// SPI requests occur only after an entire CRC-checked HallPad frame is retained.
module hallpad_sd_bridge(input wire clk,rst_n,session_valid,allowed,
 input wire command_valid, input wire [7:0] command_length,
 output wire command_ready,output reg command_done,output reg [7:0] command_code,
 output reg [383:0] reply, output reg [7:0] payload_addr,input wire [7:0] payload_data,
 output reg locked,output reg remount,
 input wire block_ready,block_done,block_error,
 output reg read_request,write_request,output reg [31:0] block_lba,
 input wire read_valid,input wire [8:0] read_address,input wire [7:0] read_byte,
 input wire [8:0] write_address,output wire [7:0] write_byte);
 localparam IDLE=0,P1=1,P2=2,CAP=3,CHECK=4,STAGE=5,REQUEST=6,WAIT_BLOCK=7,SLICE1=8,SLICE2=9,SLICE3=10,FINISH=11;
 reg [3:0] state;reg [7:0] op,len,index;reg [31:0] argument;reg [15:0] offset;
 reg [9:0] staged;reg [5:0] count;reg [8:0] address;reg [7:0] q;reg read_loaded;
 (* syn_ramstyle="block_ram" *) reg [7:0] bytes[0:511];
 wire [8:0] ram_read_address=(state==SLICE1 || state==SLICE2 || state==SLICE3) ? address:write_address;
 assign write_byte=q;
 always @(posedge clk)begin
  q<=bytes[ram_read_address];
  if(locked && read_valid)bytes[read_address]<=read_byte;
  else if(state==CAP && locked && op==3 && index>=3)bytes[offset[8:0]+index-3]<=payload_data;
 end
 assign command_ready=state==IDLE;
 task finish(input [7:0] code);begin command_code<=code;state<=FINISH;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;command_done<=0;command_code<=0;reply<=0;payload_addr<=0;locked<=0;remount<=0;read_request<=0;write_request<=0;block_lba<=0;op<=0;len<=0;index<=0;argument<=0;offset<=0;staged<=0;count<=0;address<=0;read_loaded<=0;end
  else begin
   command_done<=0;remount<=0;read_request<=0;write_request<=0;
   // Let an in-flight SD write finish before releasing card ownership.
   if(!session_valid && locked && state==IDLE)begin locked<=0;remount<=1;staged<=0;read_loaded<=0;end
   case(state)
    IDLE:if(command_valid)begin len<=command_length;index<=0;payload_addr<=0;argument<=0;offset<=0;reply<=0;command_code<=0;state<=P1;end
    P1:state<=P2;
    P2:state<=CAP;
    CAP:begin
     if(index==0)begin op<=payload_data;end
     else if((op==2 || op==4) && index<=4)argument[(index-1)*8+:8]<=payload_data;
     else if((op==3 || op==5) && index<=2)offset[(index-1)*8+:8]<=payload_data;
     if(index+1==len || len==0)state<=CHECK;
     // Validate stage range BEFORE any stage data reaches RAM.
     else if(op==3 && index==2 && ({payload_data,offset[7:0]}+{8'd0,len}-3>512 || ({payload_data,offset[7:0]}!=0 && {payload_data,offset[7:0]}!=staged)))finish(3);
     else begin index<=index+1'b1;payload_addr<=index+1'b1;state<=P1;end
    end
    CHECK:begin
     reply[7:0]<=op;
     if(!session_valid)finish(9);
     else if(op==0 && len==1)begin
      if(locked)finish(0);else if(!allowed || !block_ready)finish(5);
      else begin locked<=1;staged<=0;read_loaded<=0;finish(0);end
     end else if(!locked)finish(5);
     else if(op==1 && len==1)begin locked<=0;remount<=1;staged<=0;read_loaded<=0;finish(0);end
     else if((op==2 || op==4) && len==5)begin
      if(op==4 && staged!=512)finish(3);
      else begin block_lba<=argument;if(op==2)begin staged<=0;read_loaded<=0;end state<=REQUEST;end
     end else if(op==3 && len>3)begin staged<=offset+len-3;read_loaded<=0;finish(0);end
     else if(op==5 && len==3 && offset<=480 && read_loaded)begin count<=0;address<=offset[8:0];state<=SLICE1;end
     else finish(3);
    end
    REQUEST:if(block_error)finish(10);else if(block_ready)begin read_request<=op==2;write_request<=op==4;state<=WAIT_BLOCK;end
    WAIT_BLOCK:if(block_error)finish(10);else if(block_done)begin if(op==2)read_loaded<=1;else staged<=0;finish(0);end
    SLICE1:state<=SLICE2;
    SLICE2:state<=SLICE3;
    SLICE3:begin reply[32+count*8+:8]<=q;if(count==31)finish(0);else begin count<=count+1'b1;address<=address+1'b1;state<=SLICE1;end end
    FINISH:begin reply[15:8]<=command_code;reply[31:16]<=staged;command_done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
