`timescale 1ns/1ps
// Local UI + file-to-PracticeWire adapter; reuses the ONE existing score RAM.
module hallpad_offline_ctrl(
 input wire clk,rst_n,enter,step_valid,step_up,short_press,long_press,
 input wire keys_released,result_valid,input wire [383:0] result_packet,
 output reg mapping_active,output reg [34:0] map_enabled,map_fixed,
 output reg [244:0] map_midi,map_velocity,output reg [139:0] map_timbre,
 output reg [255:0] result_text,
 output reg active,output reg [7:0] selection,output wire [7:0] ui_state,ui_error,
 input wire mounted,card_failed,input wire [7:0] card_error,input wire [8:0] song_count,
 output reg open_file,input wire [31:0] file_size,
 input wire file_valid,input wire [7:0] file_byte,output wire file_ready,input wire file_done,output wire file_cancel,
 output wire command_valid,input wire command_ready,
 output reg [7:0] command_type,command_length,input wire [7:0] payload_addr,output wire [7:0] payload_data,
 input wire command_done,input wire [7:0] command_code,input wire [2:0] run_phase
);
 localparam LIST=0,HEADER=1,CHECK=2,SEND=3,WAIT_CMD=4,RECORD=5,READY=6,RUN=7,PAUSED=8,FINISHED=9,ERROR=10,DRAIN=11,SETTLE=12,MAP_READ=13,MAP_APPLY=14;
 reg [3:0] state,after_command;
 // Playback uses the first 24 bytes. Check the reserved tail in place.
 reg [191:0] header;
 reg header_reserved_nonzero;
 reg [7:0] map_byte_index;reg [31:0] map_crc,map_expected_crc;reg map_bad;
 reg result_latched,formatting;reg [1:0] format_index;reg [5:0] format_bit;
 reg [31:0] format_binary,format_bcd;reg [127:0] result_counts;
 reg [31:0] adjusted;
 integer digit;
 function [31:0] crc_byte(input [31:0] c,input [7:0] b);
  integer j;reg [31:0] t;begin t=c^{24'd0,b};for(j=0;j<8;j=j+1)t=t[0]?(t>>1)^32'hedb88320:t>>1;crc_byte=t;end
 endfunction
 function [63:0] decimal_text(input [31:0] bcd);
  integer j,n;reg leading;begin leading=1;n=0;decimal_text=64'h2020202020202020;
   for(j=7;j>=0;j=j-1)begin
    if(!leading || bcd[j*4+:4]!=0 || j==0)begin
     decimal_text[63-n*8-:8]=8'd48+{4'd0,bcd[j*4+:4]};n=n+1;leading=0;
    end
   end
  end
 endfunction
 always @*begin adjusted=format_bcd;for(digit=0;digit<8;digit=digit+1)if(format_bcd[digit*4+:4]>=5)adjusted[digit*4+:4]=format_bcd[digit*4+:4]+4'd3;end
 reg [255:0] packet;
 reg [5:0] byte_index;
 reg [12:0] record_index;
 reg [31:0] upload_id,run_id;
 reg [7:0] error;
 reg [5:0] settle;reg file_finished,back_pending;
 wire [31:0] groups=header[95:64],duration_ms=header[127:96],score_crc=header[159:128],binding_crc=header[191:160];
 assign command_valid=active && state==SEND;
 assign payload_data=payload_addr<32 ? packet[payload_addr[4:0]*8+:8]:8'd0;
 assign file_ready=active && (state==HEADER || state==MAP_READ || state==RECORD || state==DRAIN);
 assign file_cancel=state==DRAIN || !active;
 assign ui_error=card_failed ? card_error:error;
 assign ui_state=!mounted ? (card_failed ? 8'd7:8'd0):state==LIST ? 8'd1:
   ((state==SEND || state==WAIT_CMD) && command_type==8'h64) ? (run_phase==2 ? 8'd5:8'd4):state==READY ? 8'd3:state==RUN ? 8'd4:state==PAUSED ? 8'd5:state==FINISHED ? 8'd6:state==ERROR ? 8'd7:8'd2;
 task command(input [7:0] kind,input [7:0] size,input [255:0] data,input [3:0] target);
 begin command_type<=kind;command_length<=size;packet<=data;after_command<=target;state<=SEND;end endtask
 task control(input [7:0] action,input [3:0] target);
 begin command(8'h64,20,{96'd0,64'd0,16'd1000,8'd0,action,run_id,upload_id},target);end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin mapping_active<=0;map_enabled<=0;map_fixed<=0;map_midi<=0;map_velocity<=0;map_timbre<=0;map_byte_index<=0;map_crc<=0;map_expected_crc<=0;map_bad<=0;result_text<=0;result_latched<=0;formatting<=0;format_index<=0;format_bit<=0;format_binary<=0;format_bcd<=0;result_counts<=0;active<=0;selection<=0;state<=LIST;after_command<=0;header<=0;header_reserved_nonzero<=0;packet<=0;byte_index<=0;
   record_index<=0;upload_id<=0;run_id<=0;error<=0;settle<=0;file_finished<=0;back_pending<=0;open_file<=0;command_type<=0;command_length<=0;end
  else begin
   open_file<=0;
   if((!active || state==LIST || state==ERROR || state==DRAIN || state==FINISHED) && keys_released)mapping_active<=0;
   if(state==RUN && result_valid && run_phase==3 && !result_latched)begin
    result_latched<=1;formatting<=1;format_index<=0;format_bit<=0;format_bcd<=0;
    format_binary<={24'd0,result_packet[295:288]};
    result_counts<={result_packet[191:160]>99999999 ? 32'd99999999:result_packet[191:160],result_packet[159:128],result_packet[127:96],24'd0,result_packet[295:288]};
   end else if(formatting)begin
    if(format_bit==32)begin
     result_text[format_index*64+:64]<=decimal_text(format_bcd);
     if(format_index==3)formatting<=0;
     else begin format_index<=format_index+1'b1;format_bit<=0;format_bcd<=0;format_binary<=result_counts[(format_index+1'b1)*32+:32];end
    end else begin format_bcd<={adjusted[30:0],format_binary[31]};format_binary<={format_binary[30:0],1'b0};format_bit<=format_bit+1'b1;end
   end
   if(file_done)file_finished<=1;
   if(long_press && (state==SEND || state==WAIT_CMD))back_pending<=1;
   if(!active)begin
    back_pending<=0;
    if(enter)begin active<=1;state<=LIST;selection<=0;error<=0;end
   end else if(card_failed && state!=SEND && state!=WAIT_CMD && state!=ERROR)begin
    error<=card_error;if(state==RUN || state==PAUSED)control(3,ERROR);else state<=ERROR;
   end
   else if(state==ERROR && error==8'he6 && mounted && !card_failed)begin state<=LIST;selection<=0;error<=0;end
   else if(long_press && state!=SEND && state!=WAIT_CMD)begin
    if(state==RUN || state==PAUSED)control(3,RUN);
    else if(state==HEADER || state==CHECK || state==MAP_READ || state==MAP_APPLY || state==RECORD || state==SETTLE)state<=DRAIN;
    else if(state==ERROR && card_failed)active<=0;
    else if(state==READY || state==FINISHED || state==ERROR)begin state<=LIST;error<=0;end
    else if(state==LIST)active<=0;
   end else case(state)
    LIST:begin
     if(step_valid && song_count!=0)begin
      if(step_up)selection<={1'b0,selection}+1>=song_count ? 8'd0:selection+1'b1;
      else selection<=selection==0 ? song_count[7:0]-5'd1:selection-1'b1;
     end
     if(short_press && mounted && song_count!=0 && keys_released && !mapping_active)begin upload_id<=upload_id+1'b1;run_id<=0;
      result_latched<=0;formatting<=0;result_text<=0;open_file<=1;file_finished<=0;header<=0;header_reserved_nonzero<=0;byte_index<=0;record_index<=0;error<=0;settle<=0;state<=SETTLE;end
    end
    SETTLE:if(file_done && card_error!=0)begin error<=card_error;state<=ERROR;end
     else if(settle==31)state<=HEADER;else settle<=settle+1'b1;
    HEADER:if(file_valid)begin
     if(byte_index<24)header<={file_byte,header[191:8]};
     if(byte_index>=56 && file_byte!=0)header_reserved_nonzero<=1;
     if(byte_index==63)begin byte_index<=0;state<=CHECK;end else byte_index<=byte_index+1'b1;end
    CHECK:begin
     if(!((header[31:0]==32'h31475048 && header[47:32]==1 && header[63:48]==64) || (header[31:0]==32'h32475048 && header[47:32]==2 && header[63:48]==208)) || groups==0 || groups>4096 ||
        file_size!={16'd0,header[63:48]}+groups*24 || duration_ms==0 || duration_ms>86400000 || header_reserved_nonzero)begin error<=8'he1;state<=DRAIN;end
     else if(header[47:32]==2)begin map_byte_index<=0;map_crc<=32'hffffffff;map_expected_crc<=0;map_bad<=0;state<=MAP_READ;end
     else command(8'h61,28,{32'd0,16'd1,16'd24,duration_ms,binding_crc,score_crc,groups*32'd24,groups,upload_id},RECORD);
    end
    MAP_READ:if(file_valid)begin
     if(map_byte_index<4)map_expected_crc<={file_byte,map_expected_crc[31:8]};
     else begin
      map_crc<=crc_byte(map_crc,file_byte);
      case(map_byte_index[1:0])
       0:begin map_enabled<={file_byte[0],map_enabled[34:1]};map_fixed<={file_byte[1],map_fixed[34:1]};if(file_byte>3)map_bad<=1;end
       1:begin map_midi<={file_byte[6:0],map_midi[244:7]};if(file_byte>127)map_bad<=1;end
       2:begin map_timbre<={file_byte[3:0],map_timbre[139:4]};if(!(file_byte==0 || (file_byte>=1 && file_byte<=9) || file_byte==11 || file_byte==13 || file_byte==14))map_bad<=1;end
       3:begin map_velocity<={file_byte[6:0],map_velocity[244:7]};if(file_byte==0 || file_byte>127)map_bad<=1;end
      endcase
     end
     if(map_byte_index==143)begin settle<=0;state<=MAP_APPLY;end else map_byte_index<=map_byte_index+1'b1;
    end
    MAP_APPLY:begin
     if(map_bad || (map_crc^32'hffffffff)!=map_expected_crc)begin error<=8'he4;state<=DRAIN;end
     else if(keys_released)begin
      mapping_active<=1;
      if(settle==15)command(8'h61,28,{32'd0,16'd1,16'd24,duration_ms,binding_crc,score_crc,groups*32'd24,groups,upload_id},RECORD);
      else settle<=settle+1'b1;
     end
    end
    RECORD:if(file_valid)begin
     packet[255:64]<={file_byte,packet[255:72]};
     if(byte_index==23)begin
      packet[63:0]<={19'd0,record_index}*64'd24<<32 | {32'd0,upload_id};
      byte_index<=0;record_index<=record_index+1'b1;command_type<=8'h62;command_length<=32;state<=SEND;
      after_command<=record_index+1==groups ? READY:RECORD;
     end else byte_index<=byte_index+1'b1;
    end
    SEND:if(command_ready)state<=WAIT_CMD;
    WAIT_CMD:if(command_done)begin
     if(back_pending || long_press)begin
      back_pending<=0;
      if(run_phase==1 || run_phase==2)control(3,RUN);
      else if(file_finished)state<=LIST;
      else state<=DRAIN;
     end else if(command_code!=0)begin error<=command_code;state<=command_type==8'h61 || command_type==8'h62 ? DRAIN:ERROR;end
     else if(command_type==8'h62 && after_command==READY)
      command(8'h63,12,{160'd0,score_crc,groups*32'd24,upload_id},READY);
     else state<=after_command;
    end
    FINISHED:if(short_press && keys_released && !mapping_active)begin
     upload_id<=upload_id+1'b1;run_id<=0;result_latched<=0;result_text<=0;open_file<=1;file_finished<=0;header<=0;header_reserved_nonzero<=0;byte_index<=0;record_index<=0;error<=0;settle<=0;state<=SETTLE;end
    READY:if(short_press)begin
     run_id<=run_id+1'b1;
     command(8'h64,20,{96'd0,64'd0,16'd1000,16'd0,run_id+32'd1,upload_id},RUN);
    end
    RUN:begin
     if(run_phase==3 && result_latched && !formatting)state<=FINISHED;else if(run_phase==5)begin error<=8'he2;state<=ERROR;end
     else if(run_phase==2)state<=PAUSED;
     else if(short_press)control(1,PAUSED);
    end
    PAUSED:if(short_press)control(2,RUN);
    ERROR:if(short_press)begin state<=LIST;error<=0;end
    DRAIN:if(file_finished || file_done || (!file_valid && card_error!=0))begin state<=ERROR;if(error==0)error<=8'he3;end
    default:state<=LIST;
   endcase
  end
 end
endmodule
