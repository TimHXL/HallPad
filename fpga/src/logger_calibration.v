`timescale 1ns/1ps
// Mean gyro bias and stationary acceleration reference, never subtracts gravity
// from the raw log. Two independent streams; reset accumulation on motion.
module logger_calibration(input wire clk,rst_n,begin_cal,abort_cal,
 input wire [1:0] inserted,cal_mask,online,valid,input wire [111:0] data0,data1,
 output reg [1:0] calibrated,active,output reg [15:0] progress,
 output reg [111:0] result0,result1);
 reg signed [31:0] sums[0:11];reg [8:0] counts[0:1];
 reg signed [15:0] amin[0:5],amax[0:5];
 integer i,j;reg [111:0] sample;reg signed [15:0] v[0:5];reg still;
 reg signed [31:0] magnitude;
 function signed [15:0] word(input [111:0] d,input integer n);
 begin word={d[n*16+:8],d[n*16+8+:8]};end endfunction
 function [15:0] calibration_average(input signed [31:0] accumulated,input signed [15:0] sample_value);
  reg signed [31:0] total;
  begin total=accumulated+{{16{sample_value[15]}},sample_value};calibration_average=total[23:8];end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin calibrated<=0;active<=0;progress<=0;result0<=0;result1<=0;for(i=0;i<12;i=i+1)sums[i]<=0;for(i=0;i<2;i=i+1)counts[i]<=0;for(i=0;i<6;i=i+1)begin amin[i]<=32767;amax[i]<=-32768;end end
  else begin
   for(i=0;i<2;i=i+1)begin
    if(!inserted[i])begin active[i]<=0; if(i==0)result0<=0;else result1<=0;calibrated[i]<=0;counts[i]<=0;progress[i*8+:8]<=0;for(j=0;j<6;j=j+1)sums[i*6+j]<=0;for(j=0;j<3;j=j+1)begin amin[i*3+j]<=32767;amax[i*3+j]<=-32768;end end
    else if(begin_cal && cal_mask[i])begin
     calibrated[i]<=0;active[i]<=1;counts[i]<=0;progress[i*8+:8]<=0;
     for(j=0;j<6;j=j+1)sums[i*6+j]<=0;
     for(j=0;j<3;j=j+1)begin amin[i*3+j]<=32767;amax[i*3+j]<=-32768;end
    end
    else if(abort_cal && cal_mask[i])begin active[i]<=0;calibrated[i]<=0;progress[i*8+:8]<=0;end
    else if(active[i] && online[i] && valid[i])begin
     sample=i==0 ? data0:data1;
     v[0]=word(sample,0);v[1]=word(sample,1);v[2]=word(sample,2);
     v[3]=word(sample,4);v[4]=word(sample,5);v[5]=word(sample,6);
     magnitude=v[0]*v[0]+v[1]*v[1]+v[2]*v[2];
     still=(magnitude>2683044 && magnitude<6041764);
     for(j=3;j<6;j=j+1)if(v[j]>328 || v[j]<-328)still=0;
     for(j=0;j<3;j=j+1)if(counts[i]!=0 && (v[j]-amin[i*3+j]>205 || amax[i*3+j]-v[j]>205))still=0;
     if(!still)begin counts[i]<=0;progress[i*8+:8]<=0;for(j=0;j<6;j=j+1)sums[i*6+j]<=0;for(j=0;j<3;j=j+1)begin amin[i*3+j]<=32767;amax[i*3+j]<=-32768;end end
     else begin
      for(j=0;j<6;j=j+1)sums[i*6+j]<=sums[i*6+j]+v[j];
      for(j=0;j<3;j=j+1)begin if(v[j]<amin[i*3+j])amin[i*3+j]<=v[j];if(v[j]>amax[i*3+j])amax[i*3+j]<=v[j];end
      if(counts[i]==255)begin
       active[i]<=0;calibrated[i]<=1;progress[i*8+:8]<=255;
       for(j=0;j<6;j=j+1)begin
        if(i==0)result0[j*16+:16]<=calibration_average(sums[i*6+j],v[j]);
        else result1[j*16+:16]<=calibration_average(sums[i*6+j],v[j]);
       end
       if(i==0)result0[111:96]<=256;else result1[111:96]<=256;
      end else begin counts[i]<=counts[i]+1'b1;progress[i*8+:8]<=counts[i][7:0];end
     end
    end
   end
  end
 end
endmodule
