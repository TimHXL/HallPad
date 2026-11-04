`timescale 1ns/1ps
// SDHC/SDXC SPI block writer. Requires initialized, block-addressed card.
// Input block is held stable from request until done. Timeout/error latches.
module logger_sd_spi #(parameter integer POWER_WAIT_CYCLES=5000000)(input wire clk,rst_n,input wire miso,
 output wire sck,mosi,output reg cs_n,ready,error,
 input wire request,read_request,input wire [31:0] lba,
 output reg read_valid,output reg [8:0] read_address,output reg [7:0] read_byte,
 output reg [8:0] data_address,input wire [7:0] data_byte,
 output reg done,output reg [7:0] error_code,
 output reg [7:0] debug_cmd,debug_r1);
 reg start;reg [7:0] tx;wire [7:0] rx;wire busy,byte_done;
 reg [7:0] half_cycles;
 logger_spi_byte spi(clk,rst_n,start,tx,half_cycles,miso,sck,mosi,busy,byte_done,rx);
 reg [5:0] state,after_command;
 reg [5:0] command;
 reg [31:0] argument,delay_count,timeout;
 reg [2:0] command_byte;
 reg [7:0] clocks,retries;
 reg [2:0] extra;
 reg [31:0] response;
 localparam BOOT=0,CLOCKS=1,COMMAND=2,RESP=3,EXTRA=4,CMD0_DONE=5,CMD8_DONE=6,CMD55_DONE=7,ACMD41_DONE=8,CMD58_DONE=9,IDLE=10,WRITE_RESPONSE=11,TOKEN=12,DATA_PREP=13,DATA_SEND=14,CRC1=15,CRC2=16,ACCEPT=17,WAIT_BUSY=18,RELEASE=19,FAILED=20,READ_RESPONSE=21,READ_TOKEN=22,READ_DATA=23,READ_CRC1=24,READ_CRC2=25,STATUS_R1=26,STATUS_R2=27,READ_FINISH=28,CMD_GAP=29,CMD_SELECT=30,CMD_READY=31;
 reg [5:0] resume;
 reg waiting;
 function [7:0] command_crc(input [5:0] c,input [31:0] a);
  reg [39:0] bits;reg [6:0] crc;reg mix;integer i;
  begin bits={2'b01,c,a};crc=0;for(i=39;i>=0;i=i-1)begin mix=bits[i]^crc[6];crc=crc<<1;if(mix)crc=crc^7'h09;end command_crc={crc,1'b1};end
 endfunction
 task fail;input [7:0] code;begin error<=1;error_code<=code;ready<=0;cs_n<=1;state<=FAILED;end endtask
 task send;input [7:0] value;input [5:0] target;begin tx<=value;start<=1;waiting<=1;resume<=target;end endtask
 task cmd;input [5:0] number;input [31:0] arg;input [5:0] target;begin command<=number;debug_cmd<={2'd0,number};debug_r1<=255;argument<=arg;command_byte<=0;after_command<=target;cs_n<=1;state<=CMD_GAP;timeout<=0;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=BOOT;start<=0;tx<=255;half_cycles<=125;cs_n<=1;ready<=0;error<=0;done<=0;read_valid<=0;read_address<=0;read_byte<=0;error_code<=0;debug_cmd<=0;debug_r1<=255;delay_count<=0;clocks<=0;retries<=0;waiting<=0;resume<=0;data_address<=0;command<=0;argument<=0;command_byte<=0;after_command<=0;timeout<=0;extra<=0;response<=0;end
  else begin
   start<=0;done<=0;read_valid<=0;
   if(waiting)begin if(byte_done)begin waiting<=0;state<=resume;end end
   else case(state)
    BOOT:if(delay_count==POWER_WAIT_CYCLES-1)begin state<=CLOCKS;delay_count<=0;end else delay_count<=delay_count+1'b1;
    CLOCKS:if(clocks==10)cmd(0,0,CMD0_DONE);else begin clocks<=clocks+1'b1;send(255,CLOCKS);end
    CMD_GAP:send(255,CMD_SELECT);
    CMD_SELECT:begin cs_n<=0;send(255,CMD_READY);end
    CMD_READY:if(rx==255)begin state<=COMMAND;timeout<=0;end else if(timeout==65535)fail(8'h10);else begin timeout<=timeout+1'b1;send(255,CMD_READY);end
    COMMAND:begin
     if(command_byte==6)begin state<=RESP;timeout<=0;end
     else begin
      command_byte<=command_byte+1'b1;
      case(command_byte)
       0:send({2'b01,command},COMMAND);
       1:send(argument[31:24],COMMAND);2:send(argument[23:16],COMMAND);
       3:send(argument[15:8],COMMAND);4:send(argument[7:0],COMMAND);
       5:send(command_crc(command,argument),COMMAND);
      endcase
     end
    end
    RESP:begin
     // First poll is unconditional: rx still contains the command CRC.
     if(timeout!=0 && !rx[7])begin debug_r1<=rx;state<=after_command;end
     else if(timeout==65535)fail(8'h01);
     else begin timeout<=timeout+1'b1;send(255,RESP);end
    end
    CMD0_DONE:if(rx!=1)fail(8'h02);else cmd(8,32'h1aa,CMD8_DONE);
    CMD8_DONE:if(rx!=1)fail(8'h03);else begin extra<=0;response<=0;send(255,EXTRA);end
    EXTRA:begin
     response<={response[23:0],rx};
     if(extra==3)begin
      if(command==8)begin if({response[23:0],rx}!=32'h1aa)fail(8'h04);else cmd(55,0,CMD55_DONE);end
      else if(!response[22])fail(8'h05); // OCR bit30 after three bytes shifted
      else begin half_cycles<=5;cs_n<=1;send(255,IDLE);end
     end else begin extra<=extra+1'b1;send(255,EXTRA);end
    end
    CMD55_DONE:if(rx>1)fail(8'h06);else cmd(41,32'h40000000,ACMD41_DONE);
    ACMD41_DONE:if(rx==0)cmd(58,0,CMD58_DONE);else if(rx!=1 || retries==255)fail(8'h07);else begin retries<=retries+1'b1;delay_count<=0;state<=CMD58_DONE;end
    CMD58_DONE:begin
     if(command==41)begin if(delay_count==499999)cmd(55,0,CMD55_DONE);else delay_count<=delay_count+1'b1;end
     else if(rx!=0)fail(8'h08);else begin extra<=0;response<=0;send(255,EXTRA);end
    end
    IDLE:begin ready<=1;if(request)begin ready<=0;cmd(24,lba,WRITE_RESPONSE);end else if(read_request)begin ready<=0;cmd(17,lba,READ_RESPONSE);end end
    WRITE_RESPONSE:if(rx!=0)fail(8'h09);else send(255,TOKEN);
    TOKEN:begin data_address<=0;send(8'hfe,DATA_PREP);end
    DATA_PREP:state<=DATA_SEND;
    DATA_SEND:begin if(data_address==511)send(data_byte,CRC1);else begin data_address<=data_address+1'b1;send(data_byte,DATA_PREP);end end
    CRC1:send(255,CRC2);
    CRC2:begin timeout<=0;send(255,ACCEPT);end
    ACCEPT:if(rx==255 && timeout<65535)begin timeout<=timeout+1'b1;send(255,ACCEPT);end else if((rx & 8'h1f)!=5)fail(8'h0a);else begin timeout<=0;send(255,WAIT_BUSY);end
    WAIT_BUSY:if(rx==255)cmd(13,0,STATUS_R1); else if(timeout==1000000)fail(8'h0b);else begin timeout<=timeout+1'b1;send(255,WAIT_BUSY);end
    STATUS_R1:if(rx!=0)fail(8'h0e);else send(255,STATUS_R2);
    STATUS_R2:if(rx!=0)fail(8'h0f);else begin cs_n<=1;send(255,RELEASE);end
    READ_RESPONSE:if(rx!=0)fail(8'h0c);else begin timeout<=0;send(255,READ_TOKEN);end
    READ_TOKEN:if(rx==8'hfe)begin read_address<=0;send(255,READ_DATA);end else if(timeout==100000)fail(8'h0d);else begin timeout<=timeout+1'b1;send(255,READ_TOKEN);end
    READ_DATA:begin read_valid<=1;read_byte<=rx;if(read_address==511)send(255,READ_CRC1);else begin send(255,READ_CRC2);end end
    READ_CRC2:begin read_address<=read_address+1'b1;state<=READ_DATA;end
    READ_CRC1:send(255,READ_FINISH);
    READ_FINISH:begin cs_n<=1;send(255,RELEASE);end
    RELEASE:begin done<=1;ready<=1;state<=IDLE;end
    FAILED:begin cs_n<=1;ready<=0;end
    default:fail(8'hff);
   endcase
  end
 end
endmodule
