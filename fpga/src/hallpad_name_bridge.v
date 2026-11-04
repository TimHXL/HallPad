`timescale 1ns/1ps
// RC3526A AT+NAME bridge for HallBeat home-page rename. Only the exact
// AT+NAME=<1..16 ASCII letters/digits/_/-> CRLF and AT+NAME? CRLF are accepted.
// Actual module UART OK / NAME replies are required; there is no local name
// cache or pretend success. AT+NAME omits the disposable flag, so the module
// owns persistence. Normal boots perform no AT writes. CMD_FLAG=0 is the
// documented module default used by this raw UART project.
// A small ingress frame-length tracker excludes ALL binary frame bytes,
// including CRC-failing frames, from the text recognizer. No payload copy.
module hallpad_name_bridge #(parameter integer REPLY_TIMEOUT_MS=1000,QUIET_MS=20)(
 input wire clk,rst_n,ms_tick,input wire [7:0] rx_data,input wire rx_valid,rx_error,
 input wire stream_drained,output wire busy,tx_own,filter_rx,
 output reg [7:0] tx_data,output wire tx_valid,input wire tx_ready
);
 localparam IDLE=0,DRAIN=1,QUIET=2,COMMAND=3,REPLY=4,OUTPUT=5,FINISH=6;
 reg [2:0] state;
 reg [10:0] age;
 reg [8:0] idle_age,body_remaining;
 reg [3:0] header_index;
 reg sync_a5;
 reg [7:0] body_size;
 wire outside_frame=body_remaining==0 && header_index==0 && !sync_a5;
 reg [3:0] parse_index;
 reg invalid_name,query;
 reg [4:0] name_length;
 reg [127:0] name_bytes;
 reg [5:0] tx_index;
 reg [1:0] result; // 0=ERROR, 1=OK, 2=actual module NAME
 reg [39:0] line_head;
 reg [5:0] line_length;
 reg [3:0] name_state;
 reg [4:0] reported_length;
 reg [127:0] reported_name;
 reg got_name;
 wire valid_char=(rx_data>="A" && rx_data<="Z") ||
                 (rx_data>="a" && rx_data<="z") ||
                 (rx_data>="0" && rx_data<="9") || rx_data=="_" || rx_data=="-";
 assign busy=state!=IDLE;
 assign tx_own=state>=QUIET;
 assign filter_rx=state==QUIET || state==COMMAND || state==REPLY;
 assign tx_valid=state==COMMAND || state==OUTPUT;
 function [7:0] prefix(input [2:0] i);begin case(i)
  0:prefix="A";1:prefix="T";2:prefix="+";3:prefix="N";
  4:prefix="A";5:prefix="M";6:prefix="E";default:prefix="=";
 endcase end endfunction
 always @* begin
  tx_data=0;
  if(state==COMMAND)begin
   if(tx_index<7)tx_data=prefix(tx_index[2:0]);
   else if(tx_index==7)tx_data=query ? "?":"=";
   else if(!query && tx_index<8+{1'b0,name_length})tx_data=name_bytes[(tx_index-8)*8 +:8];
   else tx_data=tx_index==(query ? 8:8+{1'b0,name_length}) ? 8'd13:8'd10;
  end else if(result==2)begin
   case(tx_index)
    0:tx_data="+";1:tx_data="N";2:tx_data="A";3:tx_data="M";4:tx_data="E";5:tx_data="=";
    default:if(tx_index<6+{1'b0,reported_length})tx_data=reported_name[(tx_index-6)*8 +:8];
      else tx_data=tx_index==6+{1'b0,reported_length} ? 8'd13:8'd10;
   endcase
  end else if(result==1)begin
   case(tx_index)0:tx_data="O";1:tx_data="K";2:tx_data=13;default:tx_data=10;endcase
  end else begin
   case(tx_index)0:tx_data="E";1:tx_data="R";2:tx_data="R";3:tx_data="O";4:tx_data="R";5:tx_data=13;default:tx_data=10;endcase
  end
 end
 // Physical ingress tracking remains independent of parser ownership and CRC
 // resynchronization. Text hidden in a rejected frame is never executable.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin idle_age<=0;body_remaining<=0;header_index<=0;sync_a5<=0;body_size<=0;end
  else begin
   if(rx_valid)idle_age<=0;else if(ms_tick && idle_age<500)idle_age<=idle_age+1'b1;
   if(rx_error || (!rx_valid && ms_tick && idle_age>=499))begin body_remaining<=0;header_index<=0;sync_a5<=0;end
   else if(rx_valid)begin
    if(body_remaining!=0)body_remaining<=body_remaining-1'b1;
    else if(header_index!=0)begin
     if(header_index==11)body_size<=rx_data;
     if(header_index==12)begin body_remaining<={1'b0,body_size}+9'd2;header_index<=0;end
     else header_index<=header_index+1'b1;
    end else if(sync_a5)begin sync_a5<=rx_data==8'ha5;if(rx_data==8'h5a)begin header_index<=2;sync_a5<=0;end end
    else if(rx_data==8'ha5)sync_a5<=1;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;age<=0;parse_index<=0;invalid_name<=0;query<=0;name_length<=0;name_bytes<=0;
   tx_index<=0;result<=0;line_head<=0;line_length<=0;name_state<=0;
   reported_length<=0;reported_name<=0;got_name<=0;
  end else begin
   if(ms_tick && age<2047)age<=age+1'b1;
   case(state)
    IDLE:begin
     age<=0;
     if(rx_error || idle_age>=499)parse_index<=0;
     if(rx_valid)begin
      if(!outside_frame || rx_data==8'ha5)parse_index<=0;
      else if(parse_index==0)begin if(rx_data=="A")parse_index<=1;end
      else if(parse_index<7)begin
       if(rx_data==prefix(parse_index[2:0]))parse_index<=parse_index+1'b1;
       else parse_index<=rx_data=="A" ? 4'd1:4'd0;
      end else if(parse_index==7)begin
       query<=rx_data=="?";invalid_name<=0;name_length<=0;name_bytes<=0;
       parse_index<=rx_data=="=" ? 4'd8:rx_data=="?" ? 4'd9:4'd0;
      end else if(parse_index==8)begin
       if(rx_data==13)begin if(name_length==0)invalid_name<=1;parse_index<=10;end
       else if(!valid_char || name_length==16)invalid_name<=1;
       else begin name_bytes[name_length*8 +:8]<=rx_data;name_length<=name_length+1'b1;end
      end else if(parse_index==9)begin
       if(rx_data==13)parse_index<=10;else begin invalid_name<=1;parse_index<=8;end
      end else if(parse_index==10)begin
       parse_index<=0;
       if(rx_data==10)begin state<=DRAIN;result<=0;age<=0;tx_index<=0;end
      end
     end
    end
    DRAIN:begin
     if(stream_drained)begin state<=QUIET;age<=0;end
     // Do not interrupt a stuck binary transmission merely to send an error.
     else if(age>=2000)begin state<=IDLE;parse_index<=0;end
    end
    QUIET:if(age>=QUIET_MS)begin
     tx_index<=0;age<=0;
     state<=invalid_name ? OUTPUT:COMMAND;
    end
    COMMAND:if(tx_ready)begin
     if(tx_index==(query ? 9:9+{1'b0,name_length}))begin
      state<=REPLY;age<=0;line_length<=0;line_head<=0;name_state<=0;
      got_name<=0;reported_length<=0;reported_name<=0;
     end else tx_index<=tx_index+1'b1;
    end
    REPLY:begin
     if(age>=REPLY_TIMEOUT_MS)begin result<=0;tx_index<=0;state<=OUTPUT;end
     else if(query && got_name && idle_age>=QUIET_MS)begin result<=2;tx_index<=0;state<=OUTPUT;end
     if(rx_error)begin result<=0;tx_index<=0;state<=OUTPUT;end
     else if(rx_valid)begin
      if(rx_data==10)begin
       if((line_length==5 && line_head==40'h524f525245) ||
          (line_length==4 && line_head[31:0]==32'h4c494146) ||
          (line_length==4 && line_head[31:0]==32'h59535542))begin result<=0;tx_index<=0;state<=OUTPUT;end
       else if(line_length==2 && line_head[15:0]==16'h4b4f)begin
        if(!query || got_name)begin result<=query ? 2:1;tx_index<=0;state<=OUTPUT;end
       end else if(query && name_state==6 && reported_length!=0)got_name<=1;
       line_length<=0;line_head<=0;name_state<=0;
      end else if(rx_data!=13)begin
       if(line_length<5)line_head[line_length*8 +:8]<=rx_data;
       if(line_length<63)line_length<=line_length+1'b1;
       case(name_state)
        0:if(rx_data=="+")name_state<=1;else if(rx_data=="N")name_state<=2;else name_state<=7;
        1:if(rx_data=="N")name_state<=2;else name_state<=7;
        2:if(rx_data=="A")name_state<=3;else name_state<=7;
        3:if(rx_data=="M")name_state<=4;else name_state<=7;
        4:if(rx_data=="E")name_state<=5;else name_state<=7;
        5:if(rx_data=="=" || rx_data==":")begin name_state<=6;reported_length<=0;end
          else if(rx_data!=" ")name_state<=7;
        6:if(rx_data==" " && reported_length==0)begin end
          else if(valid_char && reported_length<16)begin reported_name[reported_length*8 +:8]<=rx_data;reported_length<=reported_length+1'b1;end
          else name_state<=7;
        default:begin end
       endcase
      end
     end
    end
    OUTPUT:if(tx_ready)begin
     if(tx_index==(result==2 ? 7+{1'b0,reported_length}:result==1 ? 3:6))state<=FINISH;
     else tx_index<=tx_index+1'b1;
    end
    FINISH:if(tx_ready)begin state<=IDLE;parse_index<=0;age<=0;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
