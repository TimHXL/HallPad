`timescale 1ns/1ps
// Two banks per strip in synchronous RAM. The builder writes the inactive
// bank; a complete bank is swapped only between WS2812 frames. Parallel L/R
// readers prefetch the following pixel while the current 24 bits are sent.
module drum_strip_rgb_ram_reference(
 input wire slot_launch,slot_window,
 input wire [1:0] force_refresh,
 input wire clk,rst_n,write_valid,write_right,
 input wire [6:0] write_index,input wire [23:0] write_rgb,
 input wire commit_valid,output wire commit_ready,
 input wire legacy_mode,force_black,input wire [23:0] legacyL,legacyR,
 output reg serialL,serialR
);
 (* syn_ramstyle="block_ram" *) reg [23:0] memL[0:255];
 (* syn_ramstyle="block_ram" *) reg [23:0] memR[0:255];
 reg active_bank,have_frame;
 (* syn_ramstyle="block_ram" *) reg [23:0] lastL[0:127],lastR[0:127];
 reg [23:0] refL,refR;
 reg [1:0] valid_sent,dirty,send_mask,refresh_pending;
 reg [6:0] scan_index;
 reg [6:0] read_index,pixel_index;
 reg [23:0] readL,readR,shiftL,shiftR,frame_legacyL,frame_legacyR;
 reg frame_legacy,frame_black;
 reg [2:0] state;
 localparam GAP=0,WAIT1=1,WAIT2=2,SEND=3,SCAN_READ=4,SCAN_COMPARE=5,READY=6;
 reg [13:0] gap_count;
 reg [5:0] bit_cycle;
 reg [4:0] bits_left;
 wire sending=state==SEND;
 wire [7:0] write_address={!active_bank,write_index};
 wire scanning=state==SCAN_READ || state==SCAN_COMPARE;
 wire [7:0] read_address=scanning ? {!active_bank,scan_index}:{active_bank,read_index};
 wire [1:0] requested=dirty | refresh_pending | force_refresh | ~valid_sent;
 assign commit_ready=state==READY && commit_valid && slot_launch && slot_window;
 always @(posedge clk)begin
  if(write_valid)begin
   if(write_right)memR[write_address]<=write_rgb;else memL[write_address]<=write_rgb;
  end
  readL<=memL[read_address];readR<=memR[read_address];
  refL<=lastL[scan_index];refR<=lastR[scan_index];
  if(state==WAIT2)begin
   if(send_mask[0])lastL[0]<=nextL;
   if(send_mask[1])lastR[0]<=nextR;
  end else if(state==SEND && bit_cycle==63 && bits_left==0 && pixel_index<79)begin
   if(send_mask[0])lastL[pixel_index+1'b1]<=nextL;
   if(send_mask[1])lastR[pixel_index+1'b1]<=nextR;
  end
 end
 function [23:0] grb(input [23:0] rgb);begin grb={rgb[15:8],rgb[23:16],rgb[7:0]};end endfunction
 wire [23:0] nextL=frame_black ? 24'd0:frame_legacy ? frame_legacyL:readL;
 wire [23:0] nextR=frame_black ? 24'd0:frame_legacy ? frame_legacyR:readR;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   valid_sent<=0;dirty<=0;send_mask<=0;refresh_pending<=0;scan_index<=0;
   active_bank<=0;have_frame<=0;read_index<=0;pixel_index<=0;shiftL<=0;shiftR<=0;
   frame_legacyL<=0;frame_legacyR<=0;frame_legacy<=0;frame_black<=1;state<=GAP;
   gap_count<=0;bit_cycle<=0;bits_left<=23;serialL<=0;serialR<=0;
  end else begin
   refresh_pending<=refresh_pending | force_refresh;
   if(!slot_window && (state==WAIT1 || state==WAIT2 || state==SEND))begin
    state<=GAP;gap_count<=0;serialL<=0;serialR<=0;valid_sent<=valid_sent & ~send_mask;
   end else if((scanning || state==READY) && !commit_valid)begin
    state<=GAP;serialL<=0;serialR<=0;
   end else case(state)
   GAP:begin
    serialL<=0;serialR<=0;
    if(gap_count!=14999)gap_count<=gap_count+1'b1;
    if(gap_count==14999 && commit_valid)begin
     frame_legacy<=legacy_mode;frame_legacyL<=legacyL;frame_legacyR<=legacyR;
     frame_black<=force_black;dirty<=~valid_sent;scan_index<=0;state<=SCAN_READ;
    end
   end
   SCAN_READ:state<=SCAN_COMPARE;
   SCAN_COMPARE:begin
    if(nextL!=refL)dirty[0]<=1;
    if(nextR!=refR)dirty[1]<=1;
    if(scan_index==79)state<=READY;
    else begin scan_index<=scan_index+1'b1;state<=SCAN_READ;end
   end
   READY:if(commit_ready)begin
    active_bank<=!active_bank;have_frame<=1;send_mask<=requested;
    refresh_pending<=0;
    if(requested!=0)begin
     read_index<=0;pixel_index<=0;state<=WAIT1;gap_count<=0;
    end else state<=GAP;
   end
   WAIT1:state<=WAIT2;
   WAIT2:begin
    shiftL<=grb(nextL);shiftR<=grb(nextR);read_index<=1;
    bits_left<=23;bit_cycle<=0;serialL<=send_mask[0];serialR<=send_mask[1];state<=SEND;
   end
   SEND:begin
    if(bit_cycle==63)begin
     bit_cycle<=0;
     if(bits_left!=0)begin
      shiftL<={shiftL[22:0],1'b0};shiftR<={shiftR[22:0],1'b0};bits_left<=bits_left-1'b1;serialL<=send_mask[0];serialR<=send_mask[1];
     end else if(pixel_index<79)begin
      shiftL<=grb(nextL);shiftR<=grb(nextR);pixel_index<=pixel_index+1'b1;
      if(pixel_index<78)read_index<=pixel_index+7'd2;
      bits_left<=23;serialL<=send_mask[0];serialR<=send_mask[1];
     end else begin state<=GAP;gap_count<=0;serialL<=0;serialR<=0;valid_sent<=valid_sent | send_mask;end
    end else begin
     bit_cycle<=bit_cycle+1'b1;
     if(bit_cycle==(shiftL[23] ? 6'd43:6'd15))serialL<=0;
     if(bit_cycle==(shiftR[23] ? 6'd43:6'd15))serialR<=0;
    end
   end
   default:begin state<=GAP;serialL<=0;serialR<=0;gap_count<=0;end
  endcase
  end
 end
endmodule
