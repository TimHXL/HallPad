`timescale 1ns/1ps
module tb_v5_cal;
reg clk=0;always #10 clk=~clk;
reg rst=0,request=0,view=0;reg[1:0] inserted=0,online=0,valid=3,overflow=0;
wire begin_cal,abort_cal,ready;wire[1:0]mask,cal,active;wire[15:0]progress;wire[111:0]r0,r1;wire[95:0]status;
wire[111:0] data={64'd0,16'h0008,32'd0}; // Z=2048, big-endian sensor words
integer attempts=0;
always @(posedge clk)if(begin_cal)attempts<=attempts+1;
drum_cal_control ctrl(.clk(clk),.rst_n(rst),.ms_tick(1'b1),.drum_view(view),.request(request),.inserted(inserted),.online(online),.calibrated(cal),.active(active),.pose_fault(2'd0),.overflow(overflow),.progress(progress),.ready(ready),.cal_mask(mask),.begin_cal(begin_cal),.abort_cal(abort_cal),.status(status));
logger_calibration log(.clk(clk),.rst_n(rst),.begin_cal(begin_cal),.abort_cal(abort_cal),.inserted(inserted),.cal_mask(mask),.online(online),.valid(valid),.data0(data),.data1(data),.calibrated(cal),.active(active),.progress(progress),.result0(r0),.result1(r1));
task cycles(input integer n);repeat(n)@(negedge clk);endtask
reg[111:0] old0,old1;
initial begin
 cycles(3);rst=1;cycles(120);if(attempts!=0)$fatal(1,"cal before plugs");
 inserted=3;online=3;wait(active==3);cycles(40);online=0;cycles(50);
 if(active!=3 || abort_cal)$fatal(1,"cal aborted on transient");
 online=3;wait(cal==3 && ready);cycles(3);old0=r0;old1=r1;
 if(attempts!=1 || view)$fatal(1,"boot auto not independent of view");
 online=0;overflow=3;cycles(200);if(cal!=3 || r0!=old0 || r1!=old1 || status[55:48]!=3)$fatal(1,"lost reference on transport/overflow");
 online=3;view=1;cycles(150);view=0;cycles(150);if(attempts!=1)$fatal(1,"page triggered calibration");
 inserted=2;online=2;cycles(3);if(cal!=2 || r1!=old1 || mask!=1)$fatal(1,"unplug affected other side");
 cycles(150);if(attempts!=1)$fatal(1,"cal while unplugged");inserted=3;online=3;
 wait(cal==3 && ready);cycles(3);if(attempts!=2 || r1!=old1)$fatal(1,"replug did not calibrate only removed side");
 request=1;cycles(1);request=0;wait(active==3);wait(cal==3 && ready);cycles(3);if(attempts!=3)$fatal(1,"manual failed");
 $display("PASS boot waiting/auto, collecting+ready transport pause, page no-op, single-side unplug/replug, manual both");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule
