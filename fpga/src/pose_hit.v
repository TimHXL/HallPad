`timescale 1ns/1ps
// Fast detector: half-weight IIR, 50% release hysteresis, one hit per excursion.
// Four processing clocks preserve the existing timing pipeline. Cooldown is in ms.
module pose_hit #(
 parameter integer PHYSICAL_RIGHT=0,
 parameter signed [31:0] UP_X=-900,UP_Z=-490,SIDE_X=-490,SIDE_Z=900,
 parameter integer THRESHOLD_RAW=8200,QUIET_SAMPLES=25,
 parameter integer COOLDOWN_SAMPLES=100,REQUIRE_NEUTRAL=0
)(input wire clk,rst_n,clear,enabled,valid,neutral,quiet,
 input wire signed [31:0] wx,wy,wz,
 input wire ms_tick,input wire [15:0] threshold,cooldown_ms,
 output reg hit,output reg [1:0] direction,output reg [6:0] velocity,
 output reg armed,output reg [1:0] phase);
 reg signed [31:0] fx,fz;
 wire signed [31:0] nx=fx+((wx-fx)>>>1),nz=fz+((wz-fz)>>>1);
 reg signed [63:0] ux,uz,sx,sz,up_score,side_score;
 reg [63:0] au,ascore;
 reg up_positive,side_positive;
 reg [3:0] pipe_valid,pipe_neutral;
 reg [15:0] cooldown;
 // 160 maps exactly to the legacy raw threshold 8200. Projection Q10.
 wire [31:0] threshold_product=threshold*32'd205;
 wire [63:0] threshold_score={32'd0,threshold_product}<<8;
 wire [1:0] chosen=(au>=ascore) ? (up_positive?2'd0:2'd1):(side_positive?2'd2:2'd3);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   fx<=0;fz<=0;ux<=0;uz<=0;sx<=0;sz<=0;up_score<=0;side_score<=0;
   au<=0;ascore<=0;up_positive<=0;side_positive<=0;
   pipe_valid<=0;pipe_neutral<=0;
   hit<=0;direction<=0;velocity<=100;armed<=0;phase<=0;cooldown<=0;
  end
  else begin
   hit<=0;
   if(ms_tick && cooldown!=0) cooldown<=cooldown-1'b1;
   if(clear || !enabled)begin
    fx<=0;fz<=0;pipe_valid<=0;pipe_neutral<=0;
    armed<=0;phase<=0;cooldown<=0;
   end
   else begin
    pipe_valid<={pipe_valid[2:0],valid};
    pipe_neutral<={pipe_neutral[2:0],neutral};

    if(valid)begin fx<=nx;fz<=nz;end
    if(pipe_valid[0])begin
     ux<=$signed(fx)*UP_X;uz<=$signed(fz)*UP_Z;
     sx<=$signed(fx)*SIDE_X;sz<=$signed(fz)*SIDE_Z;
    end
    if(pipe_valid[1])begin up_score<=ux+uz;side_score<=sx+sz;end
    if(pipe_valid[2])begin
     au<=up_score[63] ? -up_score:up_score;
     ascore<=side_score[63] ? -side_score:side_score;
     up_positive<=!up_score[63];side_positive<=!side_score[63];
    end
    if(pipe_valid[3])begin
    // One hit per excursion. Release is tracked even during cooldown.
    // Crossing during cooldown is consumed, never deferred until time expires.
    if(au<=(threshold_score>>1) && ascore<=(threshold_score>>1))begin
     armed<=!REQUIRE_NEUTRAL || pipe_neutral[3];
     phase<=(!REQUIRE_NEUTRAL || pipe_neutral[3])?1:0;
    end else if(armed && (au>threshold_score || ascore>threshold_score))begin
     armed<=0;phase<=2;
     if(cooldown==0 && (chosen<2 || (!PHYSICAL_RIGHT && chosen==2) || (PHYSICAL_RIGHT && chosen==3)))begin
      hit<=1;direction<=chosen;velocity<=100;cooldown<=cooldown_ms;
     end
    end
    end
   end
  end
 end
endmodule
