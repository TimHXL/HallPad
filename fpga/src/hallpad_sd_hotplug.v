`timescale 1ns/1ps
// No physical card-detect pin: probe sector0 once/sec while the reader is idle.
// Failures invalidate catalog immediately, then periodically restart SPI init.
module hallpad_sd_hotplug #(parameter integer POLL_MS=1000,RESET_MS=200)(
 input wire clk,rst_n,ms_tick,can_probe,card_ready,card_done,card_error,catalog_failed,mounted,
 output wire probe_due,output reg probe,probing,reset_card,missing);
 reg [15:0] elapsed;reg retrying;
 assign probe_due=elapsed>=POLL_MS;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin probe<=0;probing<=0;reset_card<=0;missing<=0;elapsed<=0;retrying<=0;end
  else begin
   probe<=0;
   if(reset_card)begin
    if(ms_tick)begin if(elapsed==RESET_MS-1)begin reset_card<=0;elapsed<=0;retrying<=0;end else elapsed<=elapsed+1'b1;end
   end else if(card_error || (catalog_failed && !retrying))begin
    reset_card<=1;missing<=1;probing<=0;elapsed<=0;retrying<=1;
   end else begin
    if(mounted && card_ready)missing<=0;
    if(probing && card_done)begin probing<=0;elapsed<=0;end
    if(ms_tick && !probing && elapsed<POLL_MS)elapsed<=elapsed+1'b1;
    if(!probing && elapsed>=POLL_MS && can_probe && card_ready)begin probe<=1;probing<=1;elapsed<=0;end
   end
  end
 end
endmodule
