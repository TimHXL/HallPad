`timescale 1ns/1ps
// Reads only current selection metadata; never sends a practice command or applies keys.
// Queue OPEN while preview drains. Rotation may skip stale preview results.
module hallpad_title_preview(
 input wire clk,rst_n,active,mounted,catalog_idle,catalog_done,
 input wire [7:0] ui_state,input wire [7:0] selection,input wire [8:0] song_count,
 input wire short_press,long_press,
 output reg preview_open,output reg preview_active,output reg loader_short,
 output wire title_current,output reg [7:0] revision
);
 reg cached,pending,was_list,launching;reg [7:0] cached_selection;
 wire list=active && ui_state==1;
 assign title_current=!list || (cached && cached_selection==selection);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin preview_open<=0;preview_active<=0;loader_short<=0;cached<=0;pending<=0;was_list<=0;launching<=0;cached_selection<=0;revision<=0;end
  else begin
   preview_open<=0;loader_short<=0;was_list<=list;
   if(!active || long_press)begin preview_active<=0;cached<=0;pending<=0;launching<=0;end
   else begin
    if(list && !was_list)cached<=0;
    if(preview_active && catalog_done)begin preview_active<=0;cached<=1;revision<=revision+1'b1;end
    if(!list)begin
     pending<=0;launching<=0;
     if(short_press && !preview_active)loader_short<=1;
    end else if((short_press || pending) && !launching)begin
     if(!preview_active && catalog_idle)begin loader_short<=1;pending<=0;cached<=0;launching<=1;end
     else pending<=1;
    end else if(!launching && mounted && song_count!=0 && catalog_idle && !preview_active && (!cached || cached_selection!=selection || !was_list))begin
     preview_active<=1;preview_open<=1;cached_selection<=selection;cached<=0;
    end
   end
  end
 end
endmodule
