`timescale 1ns/1ps
// Pending insertion requests and running collection are independent per side.
module drum_cal_control(
 input wire clk,rst_n,ms_tick,drum_view,request,
 input wire [1:0] inserted,online,calibrated,active,pose_fault,overflow,
 input wire [15:0] progress,
 output wire ready,output reg [1:0] cal_mask,
 output reg begin_cal,abort_cal,output wire [95:0] status
);
 reg [1:0] pending,previous_inserted,candidate;
 reg running;reg [6:0] stable_ms;reg [13:0] elapsed_ms;
 reg [7:0] state,reason;reg [15:0] attempt;
 wire [1:0] removed=previous_inserted & ~inserted;
 wire [1:0] available=pending & inserted & online;
 wire [1:0] live_mask=cal_mask & inserted;
 wire connected=(online & live_mask)==live_mask;
 assign ready=!running && !begin_cal && !abort_cal;
 assign status={attempt,6'd0,overflow,6'd0,pose_fault,reason,state,progress,
                6'd0,active,6'd0,calibrated,6'd0,online,6'd0,inserted};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin pending<=3;previous_inserted<=0;candidate<=0;running<=0;
   stable_ms<=0;elapsed_ms<=0;state<=1;reason<=0;attempt<=0;
   cal_mask<=0;begin_cal<=0;abort_cal<=0;end
  else begin
   previous_inserted<=inserted;begin_cal<=0;abort_cal<=0;
   // Removing one stick does not cancel collection or readiness of the other.
   pending<=pending | removed;
   if(request && ready)begin pending<=3;candidate<=0;stable_ms<=0;state<=1;reason<=0;end
   else if(running)begin
    cal_mask<=live_mask;
    if(live_mask==0 || (elapsed_ms>2 && (calibrated & live_mask)==live_mask && (active & live_mask)==0))begin
     running<=0;state<=3;reason<=0;
    end else if(ms_tick && connected)begin
     if(elapsed_ms==9999)begin running<=0;abort_cal<=1;state<=4;reason<=2;end
     else elapsed_ms<=elapsed_ms+1'b1;
    end
   end else if(available!=0)begin
    if(candidate!=available)begin candidate<=available;stable_ms<=0;end
    else if(ms_tick)begin
     if(stable_ms==99)begin
      cal_mask<=available;pending<=(pending | removed) & ~available;
      begin_cal<=1;running<=1;state<=2;reason<=0;stable_ms<=0;elapsed_ms<=0;attempt<=attempt+1'b1;
     end else stable_ms<=stable_ms+1'b1;
    end
   end else begin
    candidate<=0;stable_ms<=0;
    if(|(pose_fault & inserted))begin state<=4;reason<=3;end
    else if(|calibrated)begin state<=3;reason<=0;end
    else if(state!=4)begin state<=1;reason<=0;end
   end
  end
 end
endmodule
