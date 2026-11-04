`timescale 1ns/1ps
module tb_v7_cal;
reg clk=0;always #10 clk=~clk;reg rst_n=0,request=0;reg[1:0]inserted=0,online=0;
wire ready,begin_cal,abort_cal;wire[1:0]cal_mask,calibrated,active;wire[15:0]progress;wire[111:0]r0,r1;
wire[111:0]data={64'd0,16'h0008,32'd0};integer attempts=0;
always @(posedge clk)if(begin_cal)attempts<=attempts+1;
drum_cal_control d(.clk(clk),.rst_n(rst_n),.ms_tick(1'b1),.drum_view(1'b0),.request(request),.inserted(inserted),.online(online),.calibrated(calibrated),.active(active),.pose_fault(2'd0),.overflow(2'd0),.progress(progress),.ready(ready),.cal_mask(cal_mask),.begin_cal(begin_cal),.abort_cal(abort_cal));
logger_calibration log(.clk(clk),.rst_n(rst_n),.begin_cal(begin_cal),.abort_cal(abort_cal),.inserted(inserted),.cal_mask(cal_mask),.online(online),.valid(2'b11),.data0(data),.data1(data),.calibrated(calibrated),.active(active),.progress(progress),.result0(r0),.result1(r1));
task cycles(input integer n);repeat(n)@(negedge clk);endtask
reg[111:0]saved;
initial begin
cycles(3);rst_n=1;cycles(120);if(attempts!=0)$fatal(1,"unplug calibration");inserted=1;online=1;
wait(calibrated==1 && ready);cycles(3);saved=r0;if(attempts!=1)$fatal(1,"single side boot");
inserted=3;online=3;wait(active==2);cycles(20);if(calibrated[0]!=1 || r0!=saved)$fatal(1,"other side invalidated");
online=1;cycles(100);if(active!=2 || !calibrated[0] || abort_cal)$fatal(1,"transient aborted calibration");online=3;wait(calibrated==3 && ready);cycles(3);
online=1;cycles(30);online=3;cycles(130);if(attempts!=2 || calibrated!=3)$fatal(1,"short failure recalibrated");
inserted=1;online=1;cycles(120);if(calibrated!=1 || r0!=saved)$fatal(1,"unplug cleared other");inserted=3;online=3;wait(calibrated==3 && ready);cycles(3);if(attempts!=3)$fatal(1,"replug");
request=1;cycles(1);request=0;wait(active==3);wait(calibrated==3 && ready);cycles(3);if(attempts!=4)$fatal(1,"manual both");
$display("PASS independent single-stick boot, second-stick collection, transient pause, retained other reference, unplug/replug, manual dual calibration");$finish;
end
initial begin #1000000;$fatal(1,"cal timeout state%d",d.state);end
endmodule
