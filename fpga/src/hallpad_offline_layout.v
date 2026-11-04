`timescale 1ns/1ps
// Purpose-built offline screens: info is plain text; bordered elements are real actions/selectors.
module hallpad_offline_layout(
 input wire [7:0] px,py,ui_state,error_code,input wire language_cn,playback,choosing,
 input wire [7:0] selection,input wire [5:0] title_count,input wire [8:0] song_count,
 input wire [4:0] title_offset,title_pixel,input wire title_valid,title_pending,ascii_title_valid,
 input wire [127:0] ascii_title,input wire [63:0] filename,choice_text,
 input wire [255:0] result_text,input wire [63:0] skipped_text,input wire [1:0] practice_screen,countdown,
 output reg [7:0] character,output reg hanzi,output reg [2:0] font_column,font_row,
 output reg [4:0] han_column,han_row,output reg title_area,text_area,
 output reg [4:0] title_index,output reg [4:0] title_row,title_column,
 output reg [15:0] background,foreground
);
 localparam BG=16'h0841,TEXT=16'he71c,CYAN=16'h07ff,DIM=16'h738e,PANEL=16'h10a2,AMBER=16'hfd20;
 reg [127:0] text_line;reg line_cn;reg [7:0] origin_x,origin_y,dx,dy;reg [4:0] index;reg big_digit;
 reg action,selector;reg [7:0] action_y;
 wire [8:0] position={1'b0,selection}+9'd1;
 function [7:0] hundreds(input [8:0] n);begin hundreds=48+n/100;end endfunction
 function [7:0] tens(input [8:0] n);begin tens=48+(n/10)%10;end endfunction
 function [7:0] ones(input [8:0] n);begin ones=48+n%10;end endfunction
 function [3:0] first_digit(input [63:0] digits);
 integer n;reg found;begin found=0;first_digit=7;for(n=0;n<7;n=n+1)if(!found && digits[63-n*8-:8]!=8'd48)begin first_digit=n[3:0];found=1;end end endfunction
 function [63:0] trim_number(input [63:0] digits);begin trim_number=digits << {first_digit(digits),3'd0};end endfunction
 function is_hanzi(input [7:0] c);begin case(c)
8'h01,8'h02,8'h03,8'h04,8'h05,8'h06,8'h07,8'h08,8'h09,8'h0a,8'h0b,8'h0c,8'h0d,8'h0e,8'h0f,8'h10,8'h11,8'h12,8'h13,8'h14,8'h15,8'h16,8'h17,8'h18,8'h19,8'h1a,8'h1b,8'h1c,8'h1d,8'h1e,8'h1f,8'h21,8'h22,8'h23,8'h24,8'h25,8'h26,8'h27,8'h28,8'h29,8'h2a,8'h2b,8'h2c,8'h2d,8'h2e,8'h2f,8'h3a,8'h3b,8'h3c,8'h3d,8'h3e,8'h3f,8'h40,8'h5b,8'h5c,8'h5d,8'h5e,8'h80,8'h81,8'h82,8'h83,8'h84,8'h85,8'h86,8'h87,8'h88,8'h89,8'h8a,8'h8b,8'h8c,8'h8d,8'h8e,8'h8f,8'h90,8'h91,8'h92,8'h93,8'h94,8'h95,8'h96,8'h97,8'h98,8'h99,8'h9a,8'h9b,8'h9c,8'h9d,8'h9e,8'h9f,8'ha0,8'ha1,8'ha2,8'ha3,8'ha4,8'ha5,8'ha6,8'ha9,8'haa,8'hab,8'hac,8'had,8'hae,8'haf,8'hb0,8'hb1,8'hb2,8'hb3,8'hb4,8'hb5,8'hb6,8'hb7,8'hbb,8'hbc,8'hbd,8'hbe,8'hbf,8'hc0,8'hc1,8'hc2,8'hc3,8'hc4,8'hc5,8'hc6,8'hc8,8'hc9,8'hca,8'hcb,8'hcc,8'hcd,8'hce,8'hcf,8'hd0,8'hd1,8'hd2,8'hd3,8'hd4,8'hd5,8'hd6,8'hd7,8'hd8,8'hd9,8'hda,8'hdb,8'hdc,8'hdd,8'hde,8'hdf,8'he0,8'he1,8'he2,8'he3,8'he4,8'he5,8'he6,8'he7,8'he8,8'he9,8'hea,8'heb,8'hec,8'hed,8'hee,8'hef,8'hf0,8'hf1,8'hf2,8'hf3,8'hf4,8'hf5,8'hf6,8'hf7,8'hf8,8'hf9,8'hfa,8'hfb,8'hfc,8'hfd,8'hfe,8'hff:is_hanzi=1;default:is_hanzi=0;endcase end endfunction
 always @*begin
 background=BG;foreground=TEXT;character=32;hanzi=0;font_column=0;font_row=0;han_column=0;han_row=0;
 title_area=0;text_area=0;title_index=0;title_row=0;title_column=0;
 text_line=0;line_cn=language_cn;origin_x=76;origin_y=20;dx=0;dy=0;index=0;big_digit=0;action=0;selector=0;action_y=140;
 // Header: 4-5 glyphs fit fully within the circular display's upper span.
 if(py>=20 && py<42)begin
  origin_x=76;text_area=1;foreground=CYAN;
  case(ui_state)
   6:text_line=(language_cn ? 128'he6e7f5f6202020202020202020202020:{"RESULT",80'h20202020202020202020});
   8:text_line=(language_cn ? 128'hb4b5800b202020202020202020202020:{"TRACK",88'h2020202020202020202020});
   9:text_line=(language_cn ? 128'hb4b5c2c3202020202020202020202020:{"MODE",96'h202020202020202020202020});
   10:text_line=(language_cn ? 128'haee9a615202020202020202020202020:{"NOTICE",80'h20202020202020202020});
   default:text_line=(language_cn ? 128'h5d5e01bc202020202020202020202020:{"OFFLINE",72'h202020202020202020});endcase
 end
 if(ui_state==6)begin
  if(py>=52 && py<74)begin
   origin_y=52;origin_x=32;
   if(title_pending)begin origin_x=76;text_area=1;foreground=DIM;text_line=(language_cn ? 128'h1a1b012a202020202020202020202020:{"READING",72'h202020202020202020});end
   else if(title_valid)begin
    if(px>=32 && px<208)begin
     dx=px-32+title_pixel;index=dx/8'd22;title_index=title_offset+index;
     if({1'b0,title_offset}+{1'b0,index}>=title_count)title_index=title_index-title_count[4:0];
     title_row=py-52;title_column=dx-index*22;title_area=title_count>8 || index<title_count;text_area=title_area;
    end
   end else begin
    text_area=1;line_cn=0;origin_x=24;
    text_line=ascii_title_valid ? ascii_title:{filename,64'h2020202020202020};
   end
  end
  if(!playback && py>=84 && py<194)begin
   text_area=1;origin_x=42;line_cn=language_cn;
   if(py<106)begin origin_y=84;text_line=(language_cn ? 128'hf7f82020202020202020202020202020:{"SCORE",88'h2020202020202020202020});end
   else if(py>=112 && py<134)begin origin_y=112;text_line=(language_cn ? 128'hcdf92020202020202020202020202020:{"CORRECT",72'h202020202020202020});end
   else if(py>=140 && py<162)begin origin_y=140;text_line=(language_cn ? 128'hfaed2020202020202020202020202020:{"MISSED",80'h20202020202020202020});end
   else if(py>=168 && py<190)begin origin_y=168;text_line=(language_cn ? 128'hfb802020202020202020202020202020:{"WRONG",88'h2020202020202020202020});end
   else text_area=0;
   if(px>=102 && text_area)begin
    line_cn=0;origin_x=102;
    case(origin_y)84:text_line={result_text[63:0],64'h2020202020202020};112:text_line={result_text[127:64],64'h2020202020202020};140:text_line={result_text[191:128],64'h2020202020202020};default:text_line={result_text[255:192],64'h2020202020202020};endcase
   end
  end else if(playback && py>=110 && py<132)begin origin_y=110;origin_x=76;text_area=1;text_line=(language_cn ? 128'h0708fcfd202020202020202020202020:{"FINISHED",64'h2020202020202020});end
 end else begin
  // Selected filename fallback only for legacy/malformed files without a title.
  if(!(ui_state==1 && song_count==0) && py>=58 && py<80)begin
   origin_y=58;origin_x=32;
   if(title_pending)begin origin_x=76;text_area=1;foreground=DIM;text_line=(language_cn ? 128'h1a1b012a202020202020202020202020:{"READING",72'h202020202020202020});end
   else if(title_valid)begin
    if(px>=32 && px<208)begin
     dx=px-32+title_pixel;index=dx/8'd22;title_index=title_offset+index;
     if({1'b0,title_offset}+{1'b0,index}>=title_count)title_index=title_index-title_count[4:0];
     title_row=py-58;title_column=dx-index*22;title_area=title_count>8 || index<title_count;text_area=title_area;
    end
   end else begin
    text_area=1;line_cn=0;origin_x=24;
    text_line=ascii_title_valid ? ascii_title:{filename,64'h2020202020202020};
   end
  end
  case(ui_state)
   0,2:if(py>=108 && py<130)begin origin_x=65;origin_y=108;text_area=1;text_line=(language_cn ? 128'h01020304b02020202020202020202020:{"LOADING",72'h202020202020202020});end
   1:begin
    if(song_count!=0 && py>=94 && py<108)begin origin_x=66;origin_y=94;line_cn=0;text_area=1;text_line={hundreds(position),tens(position),ones(position)," / ",hundreds(song_count),tens(song_count),ones(song_count),56'h20202020202020};foreground=DIM;end
    if(song_count!=0)begin
     action=1;action_y=138;
     if(py>=144 && py<166)begin origin_x=76;origin_y=144;text_area=1;text_line=(language_cn ? 128'h5cae0102202020202020202020202020:{"OPEN",96'h202020202020202020202020});end
    end else if(py>=102 && py<124)begin origin_x=65;origin_y=102;text_area=1;text_line=(language_cn ? 128'h0e2b2c01022020202020202020202020:{"NO SONG",72'h202020202020202020});end
   end
   8:begin
    selector=1;
    if(py>=108 && py<130)begin
     origin_y=108;origin_x=54;text_area=1;text_line=language_cn ? {8'h80,8'h0b,trim_number({24'h303030,choice_text[39:0]}),48'h202020202020}:{choice_text,64'h2020202020202020};
     if(choice_text=="ALL     ")begin origin_x=76;text_line=(language_cn ? 128'h0cc5800b202020202020202020202020:{"ALL",104'h20202020202020202020202020});end
    end
   end
   9:begin
    if(px>=44 && px<196 && py>=100 && py<132)begin
     if(!playback)background=PANEL;
     if(py>=105 && py<127)begin origin_x=76;origin_y=105;text_area=1;text_line=(language_cn ? 128'he4e5090a202020202020202020202020:{"PRACTICE",64'h2020202020202020});foreground=!playback ? CYAN:DIM;end
    end
    if(px>=44 && px<196 && py>=142 && py<174)begin
     if(playback)background=PANEL;
     if(py>=147 && py<169)begin origin_x=76;origin_y=147;text_area=1;text_line=(language_cn ? 128'h3c3d0708202020202020202020202020:{"PLAYBACK",64'h2020202020202020});foreground=playback ? CYAN:DIM;end
    end
   end
   10:begin
    if(py>=96 && py<118)begin origin_x=76;origin_y=96;text_area=1;text_line=(language_cn ? 128'h11128014202020202020202020202020:{"SKIPPED",72'h202020202020202020});foreground=AMBER;end
    if(py>=124 && py<138)begin origin_x=8'd120-((8'd8-{4'd0,first_digit(skipped_text)})*8'd6);origin_y=124;text_area=1;line_cn=0;text_line={trim_number(skipped_text),64'h2020202020202020};end
    action=1;action_y=151;
    if(py>=157 && py<179)begin origin_x=76;origin_y=157;text_area=1;text_line=(language_cn ? 128'hf9160304202020202020202020202020:{"CONFIRM",72'h202020202020202020});end
   end
   3:begin
    if(py>=96 && py<118)begin origin_x=65;origin_y=96;text_area=1;text_line=playback ? (language_cn ? 128'h07081005062020202020202020202020:{"READY",88'h2020202020202020202020}):(language_cn ? 128'h090a1005062020202020202020202020:{"READY",88'h2020202020202020202020});end
    action=1;action_y=138;
    if(py>=144 && py<166)begin origin_x=76;origin_y=144;text_area=1;text_line=playback ? (language_cn ? 128'haee90708202020202020202020202020:{"PLAY",96'h202020202020202020202020}):(language_cn ? 128'haee9090a202020202020202020202020:{"START",88'h2020202020202020202020});end
   end
   4,5:begin
    if(practice_screen==1)begin
     if(py>=108 && py<164 && px>=100 && px<140)begin character=48+{6'd0,countdown};font_column=(px-100)>>3;font_row=(py-108)>>3;text_area=1;big_digit=1;end
    end else begin
     if(py>=96 && py<118)begin origin_x=76;origin_y=96;text_area=1;text_line=ui_state==5 ? (language_cn ? 128'h10eeef20202020202020202020202020:{"PAUSED",80'h20202020202020202020}):playback ? (language_cn ? 128'h3c3d0708202020202020202020202020:{"PLAYING",72'h202020202020202020}):(language_cn ? 128'hec85ede7202020202020202020202020:{"FOLLOW",80'h20202020202020202020});end
     action=1;action_y=140;
     if(py>=146 && py<168)begin origin_x=98;origin_y=146;text_area=1;text_line=ui_state==5 ? (language_cn ? 128'hf0f12020202020202020202020202020:{"RESUME",80'h20202020202020202020}):(language_cn ? 128'heeef2020202020202020202020202020:{"PAUSE",88'h2020202020202020202020});end
    end
   end
   7:begin
    if(py>=100 && py<122)begin origin_x=76;origin_y=100;text_area=1;foreground=AMBER;text_line=error_code==8'he3 ? (language_cn ? 128'h101b2d20202020202020202020202020:{"CANCELED",64'h2020202020202020}):(language_cn ? 128'h1a1b1c1d202020202020202020202020:{"ERROR",88'h2020202020202020202020});end
    action=1;action_y=140;
    if(py>=146 && py<168)begin origin_x=76;origin_y=146;text_area=1;text_line=(language_cn ? 128'hf4870102202020202020202020202020:{"BACK",96'h202020202020202020202020});end
   end
   default:begin end
  endcase
 end
 // Bottom instructions are not menu rows and have no selection decoration.
 if(py>=200 && py<222)begin
  origin_x=32;origin_y=200;text_area=1;foreground=DIM;
  if(ui_state==1 || ui_state==8 || ui_state==9)text_line=(language_cn ? 128'hb2b3b4b5f2ecf9162020202020202020:{"TURN / OK",56'h20202020202020});
  else if(ui_state==6)text_line=(language_cn ? 128'hf2ec2ee69eecf4872020202020202020:{"REPLAY / BACK",24'h202020});
  else begin origin_x=76;text_line=(ui_state==4 || ui_state==5) ? (language_cn ? 128'h9eecf5ff202020202020202020202020:{"HOLD STOP",56'h20202020202020}):(language_cn ? 128'h9eecf487202020202020202020202020:{"HOLD BACK",56'h20202020202020});end
 end
 if(action && px>=52 && px<188 && py>=action_y && py<action_y+34)begin
  background=PANEL;if(px==52 || px==187 || py==action_y || py==action_y+33)background=CYAN;
 end
 if(selector && px>=44 && px<196 && py>=101 && py<137)begin background=PANEL;if(px==44 || px==195 || py==101 || py==136)background=CYAN;end
 // Character lookup. Chinese cells are exactly22 pixels; ASCII uses12x14.
 if(text_area && !title_area && !big_digit)begin
  if(px<origin_x || py<origin_y)text_area=0;
  else begin
   dx=px-origin_x;dy=py-origin_y;
   index=line_cn ? dx/8'd22:dx/8'd12;
   if(index>=16 || (line_cn ? dy>=22:dy>=14))text_area=0;
   else begin
    character=text_line[127-index*8-:8];hanzi=line_cn && is_hanzi(character);
    han_column=dx-index*22;han_row=dy[4:0];
    font_column=line_cn ? ((dx-index*22)>>1):((dx-index*12)>>1);font_row=dy[3:1];
    if(!hanzi && (line_cn ? (dx-index*22>=10 || dy>=14):(dx-index*12>=10)))text_area=0;
   end
  end
 end
 end
endmodule
