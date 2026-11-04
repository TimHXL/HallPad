`timescale 1ns/1ps
// HPG3 is a directory of validated HPG2 objects sharing title glyphs.
// Only the selected object is forwarded to the existing loader/score RAM.
module hallpad_hpg3(
 input wire clk,rst_n,open_file,cancel,step_valid,step_up,short_press,
 input wire preview_only,output reg preview_mode,output reg [127:0] ascii_title,output reg ascii_title_valid,
 input wire [31:0] raw_size,input wire raw_valid,input wire [7:0] raw_byte,output wire raw_ready,output wire raw_cancel,input wire raw_done,
 output wire data_valid,output wire [7:0] data_byte,input wire data_ready,output wire data_done,output reg [31:0] data_size,
 output reg playback,output wire choosing,output reg failed,output wire [7:0] choice_state,output wire [63:0] choice_text,
 output reg [31:0] skipped,output reg title_valid,output reg [5:0] title_count,
 input wire [4:0] title_index,input wire [4:0] title_row,title_column,output wire title_ink
);
 localparam IDLE=0,HEAD=1,META=2,TRACK=3,MODE=4,WARN=5,SKIP=6,REPLAY=7,PASS=8,DONE=9,BAD=10;
 integer ti;
 reg [3:0] state;reg [511:0] head;reg [31:0] position,remaining,meta_end;
 reg [5:0] hi;reg [8:0] track_sel,tracks;reg [5:0] glyphs;
 reg [31:0] crc;reg [23:0] glyph_word;
 (* syn_ramstyle="block_ram" *) reg [97:0] directory[0:513];
 reg [127:0] descriptor;
 // Keep the full offset, 17-bit valid size, skip count and track ID.
 // Preserve rejection of nonzero flags and oversized encoded lengths.
 wire [127:0] descriptor_next={raw_byte,descriptor[127:8]};
 wire [97:0] directory_word={|descriptor_next[127:112] || |descriptor_next[63:49],
                             descriptor_next[111:64],descriptor_next[48:32],
                             descriptor_next[31:0]};
 wire [511:0] head_next={raw_byte,head[511:8]};
 reg [4:0] title_map[0:31];
 (* syn_ramstyle="block_ram" *) reg [21:0] glyph_ram[0:1023];
 reg [21:0] row_q;reg [4:0] column_q;reg pixel_valid;
 wire [31:0] mi=position-64;
 reg [31:0] directory_end,glyph_begin;
 reg [4:0] glyph_id,glyph_row;reg [1:0] glyph_byte;
 wire [9:0] selected={track_sel,playback};
 reg [97:0] selected_descriptor;
 always @(posedge clk)selected_descriptor<=directory[selected];
 wire [31:0] selected_offset=selected_descriptor[31:0],selected_size={15'd0,selected_descriptor[48:32]};
 function [31:0] crc_byte(input [31:0] c,input [7:0] b);
 integer j;reg [31:0] t;begin t=c^{24'd0,b};for(j=0;j<8;j=j+1)t=t[0]?(t>>1)^32'hedb88320:t>>1;crc_byte=t;end endfunction
 always @(posedge clk)begin
  row_q<=glyph_ram[{title_map[title_index],5'd0}+{4'd0,title_row}];column_q<=title_column;
  pixel_valid<=title_valid && title_index<title_count && title_row<22 && title_column<22;
  if(state==META && raw_valid && raw_ready && position>=directory_end && position<glyph_begin)title_map[(position-directory_end)&31]<=raw_byte[4:0];
  if(state==META && raw_valid && raw_ready && position<directory_end && mi[3:0]==15)directory[mi[13:4]]<=directory_word;
  if(state==META && raw_valid && raw_ready && position>=glyph_begin && glyph_byte==2)
   glyph_ram[{glyph_id[4:0],glyph_row}]<={glyph_word[15:0],raw_byte[7:2]};
 end
 assign title_ink=pixel_valid && column_q<22 ? row_q[21-column_q]:1'b0;
 assign choosing=!preview_mode && (state==TRACK || state==MODE || state==WARN);
 assign choice_state=state==TRACK ? 8'd8:state==MODE ? 8'd9:8'd10;
 reg [15:0] track_binary,track_last;reg [19:0] track_bcd,track_adjusted;reg [4:0] track_bits;integer td;
 always @*begin track_adjusted=track_bcd;for(td=0;td<5;td=td+1)if(track_bcd[td*4+:4]>=5)track_adjusted[td*4+:4]=track_bcd[td*4+:4]+4'd3;end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin track_binary<=0;track_last<=16'hffff;track_bcd<=0;track_bits<=0;end
  else if(selected_descriptor[96:81]!=track_last)begin track_last<=selected_descriptor[96:81];track_binary<=selected_descriptor[96:81];track_bcd<=0;track_bits<=16;end
  else if(track_bits!=0)begin track_bcd<={track_adjusted[18:0],track_binary[15]};track_binary<=track_binary<<1;track_bits<=track_bits-1'b1;end
 end
 assign choice_text=state==TRACK ? (selected_descriptor[96:81]==16'hffff ? "ALL     ":{"TRK",4'h3,track_bcd[19:16],4'h3,track_bcd[15:12],4'h3,track_bcd[11:8],4'h3,track_bcd[7:4],4'h3,track_bcd[3:0]}):state==MODE ? (playback ? "PLAY    ":"PRACTICE"):"NOTICE  ";
 assign raw_cancel=state==DONE || state==BAD;
 assign raw_ready=state==HEAD || state==META || (state==SKIP && position<meta_end) || (state==PASS && (remaining==0 || data_ready)) || state==DONE;
 assign data_valid=!preview_mode && (state==REPLAY || (state==PASS && remaining!=0 && raw_valid));
 assign data_byte=state==REPLAY ? head[7:0]:raw_byte;
 assign data_done=!preview_mode && ((state==PASS && raw_valid && raw_ready && remaining==1) || (cancel && state!=IDLE));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin directory_end<=576;glyph_begin<=592;preview_mode<=0;ascii_title<=0;ascii_title_valid<=0;state<=IDLE;head<=0;position<=0;remaining<=0;meta_end<=0;hi<=0;track_sel<=0;tracks<=0;glyphs<=0;crc<=0;glyph_word<=0;descriptor<=0;glyph_id<=0;glyph_row<=0;glyph_byte<=0;data_size<=0;playback<=0;failed<=0;skipped<=0;title_valid<=0;title_count<=0;end
  else if(open_file)begin preview_mode<=preview_only===1'b1;ascii_title<=0;ascii_title_valid<=0;state<=HEAD;head<=0;position<=0;hi<=0;failed<=0;playback<=0;title_valid<=0;skipped<=0;data_size<=raw_size;end
  else if(cancel)begin state<=IDLE;title_valid<=0;ascii_title_valid<=0;failed<=0;end
  else begin
   if(raw_done && state!=DONE && state!=IDLE && state!=TRACK && state!=MODE && state!=WARN && state!=REPLAY)begin state<=BAD;failed<=1;end
   case(state)
    HEAD:if(raw_valid)begin
     head<=head_next;position<=position+1;
     if(hi==63)begin
      hi<=0;
      if(head_next[31:0]==32'h33475048)begin
       if((head_next[47:32]!=3 && head_next[47:32]!=4) ||
          (head_next[47:32]==3 && (head_next[71:64]==0 || head_next[71:64]>16 || head_next[79:72]>16 || head_next[87:80]>16 || head_next[63:48]!=592+head_next[87:80]*66)) ||
          (head_next[47:32]==4 && (head_next[143:128]==0 || head_next[143:128]>257 || head_next[79:72]>32 || head_next[87:80]>32 || head_next[95:88]!=1 || head_next[63:48]!=96+head_next[143:128]*32+head_next[87:80]*66)) || head_next[63:48]>=raw_size)begin state<=BAD;failed<=1;end
       else begin
        tracks<=head_next[47:32]==3 ? {4'd0,head_next[68:64]}:head_next[136:128];
        directory_end<=head_next[47:32]==3 ? 576:64+head_next[143:128]*32;
        glyph_begin<=head_next[47:32]==3 ? 592:96+head_next[143:128]*32;
        title_count<=head_next[77:72];glyphs<=head_next[85:80];meta_end<={16'd0,head_next[63:48]};crc<=32'hffffffff;glyph_id<=0;glyph_row<=0;glyph_byte<=0;descriptor<=0;state<=META;
       end
      end else begin
       data_size<=raw_size;remaining<=raw_size-64;
       if(head_next[31:0]==32'h32475048 || head_next[31:0]==32'h31475048)begin
        ascii_title_valid<=|head_next[319:192];
        for(ti=0;ti<16;ti=ti+1)ascii_title[127-ti*8-:8]<=head_next[192+ti*8+:8]==0 ? 8'd32:head_next[192+ti*8+:8];
       end
       state<=preview_mode ? DONE:REPLAY;
      end
     end else hi<=hi+1'b1;
    end
    META:if(raw_valid)begin
     crc<=crc_byte(crc,raw_byte);position<=position+1;
     if(position<directory_end)descriptor<=descriptor_next;
     else if(position<glyph_begin)begin if(raw_byte>=glyphs && position-directory_end<title_count)begin failed<=1;state<=BAD;end end
     else begin
      glyph_word<={glyph_word[15:0],raw_byte};
      if(glyph_byte==2)begin glyph_byte<=0;if(glyph_row==21)begin glyph_row<=0;glyph_id<=glyph_id+1'b1;end else glyph_row<=glyph_row+1'b1;end
      else glyph_byte<=glyph_byte+1'b1;
     end
     if(position+1==meta_end)begin
      if((crc_byte(crc,raw_byte)^32'hffffffff)!=head[127:96] || failed)begin state<=BAD;failed<=1;end
      else begin title_valid<=title_count!=0;track_sel<=0;state<=preview_mode ? DONE:TRACK;end
     end
    end
    TRACK:begin
     if(step_valid)track_sel<=step_up ? (track_sel+1>=tracks ? 9'd0:track_sel+1'b1):(track_sel==0 ? tracks-1'b1:track_sel-1'b1);
     else if(short_press)state<=MODE;
    end
    MODE:begin
     if(step_valid)playback<=~playback;
     else if(short_press)begin skipped<=selected_descriptor[80:49];state<=WARN;end
    end
    WARN:if(short_press)begin
     if(selected_size<208 || selected_size>98512 || selected_offset<meta_end || {1'b0,selected_offset}+{1'b0,selected_size}>{1'b0,raw_size} || selected_descriptor[97])begin failed<=1;state<=BAD;end
     else begin data_size<=selected_size;remaining<=selected_size;meta_end<=selected_offset;state<=SKIP;end
    end
    SKIP:if(position==meta_end)state<=PASS;else if(raw_valid)position<=position+1'b1;
    REPLAY:if(data_ready)begin head<={8'd0,head[511:8]}; if(hi==63)begin hi<=0;state<=PASS;end else hi<=hi+1'b1;end
    PASS:if(raw_valid && raw_ready)begin if(remaining==1)begin remaining<=0;state<=DONE;end else if(remaining!=0)remaining<=remaining-1'b1;end
    default:begin end
   endcase
  end
 end
endmodule
