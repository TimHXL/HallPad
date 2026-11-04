`timescale 1ns/1ps
module tb_v3_roll;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sv=0;reg[111:0] data=0;reg[31:0] ms=100;
 wire ready,vv,fault;wire signed[31:0] wx,wy,wz;wire[127:0] attitude;
 pose_tracker dut(.clk(clk),.rst_n(rst_n),.clear(1'b0),.online(1'b1),.calibrated(1'b1),.sample_valid(sv),.sample_data(data),.cal_result(112'd0),.sample_ms(ms),.sample_ready(ready),.vector_valid(vv),.wx(wx),.wy(wy),.wz(wz),.neutral(),.quiet(),.fault(fault),.attitude(attitude));
 task sample(input integer x,y,z);begin
  wait(ready);@(negedge clk);
  data[79:64]={8'(x),8'(x>>8)};data[95:80]={8'(y),8'(y>>8)};data[111:96]={8'(z),8'(z>>8)};
  sv=1;@(negedge clk);sv=0;wait(vv);@(negedge clk);ms=ms+5;
  if(fault)$fatal(1,"pose fault");
 end endtask
 integer i;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  // Tilt the stick first. Axial Y then projects onto calibrated X/Z in old code.
  for(i=0;i<30;i=i+1)sample(16400,0,0);
  for(i=0;i<30;i=i+1)begin sample(0,16400,0);if(wx!=0 || wz!=0)$fatal(1,"axial roll leaked into hit %d %d",wx,wz);end
  if(attitude[95:64]==0)$fatal(1,"axial gyro no longer integrates attitude");
  sample(8200,0,0);if(wx==0 && wz==0)$fatal(1,"transverse hit lost");
  $display("PASS: tilted axial roll suppressed, full attitude integration retained, transverse motion retained");$finish;
 end
 initial begin #10000000;$fatal(1,"watchdog");end
endmodule
