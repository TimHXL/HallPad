`timescale 1ns/1ps
module tb_v7_runner;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,start=0,pause=0,resume=0,stop=0,auto_play=1;
 reg [31:0] uptime_ms=0;reg [34:0]physical_mask=0;
 wire request;wire [11:0] index;reg valid=0;reg[191:0]record_data=0;
 wire[2:0]phase;wire[34:0]mask;wire[6:0]velocity;wire result_valid;wire[383:0]result_packet;
 hallpad_practice_runner #(.COUNTDOWN_MS(3)) d(.clk(clk),.rst_n(rst_n),.ms_tick(1'b1),.session_clear(1'b0),.object_clear(1'b0),.binding_fault(1'b0),.panic_latched(1'b0),.practice_allowed(1'b1),.start(start),.pause(pause),.resume(resume),.stop(stop),.auto_play(auto_play),.auto_mask(mask),.auto_velocity(velocity),.upload_id(32'd1),.start_run_id(32'd1),.score_crc(32'd0),.uptime_ms(uptime_ms),.total_groups(13'd2),.start_speed(16'd1000),.physical_mask(physical_mask),.key_enabled({35{1'b1}}),.record_request(request),.record_index(index),.record_valid(valid),.record_data(record_data),.phase(phase),.result_valid(result_valid),.result_packet(result_packet));
 always @(negedge clk)begin
  uptime_ms<=uptime_ms+1;valid<=request;
  if(request)record_data<=index==0 ? {16'd0,8'd100,8'd1,64'd1,32'd20,32'd0,32'd0}:{16'd0,8'd90,8'd1,64'd2,32'd20,32'd50,32'd1};
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
 cycles(3);rst_n=1;start=1;cycles(1);start=0;
 wait(mask==1);cycles(2);pause=1;cycles(1);pause=0;cycles(2);
 if(mask!=0 || phase!=2)$fatal(1,"pause did not release");resume=1;cycles(1);resume=0;
 wait(mask==2);if(velocity!=90)$fatal(1,"velocity");
 wait(phase==3);cycles(2);if(mask!=0 || !result_valid)$fatal(1,"natural release/result");
 // Following practice: interrupt before touching any key. Count only begun group.
 auto_play=0;start=1;cycles(1);start=0;wait(d.stage==3 && d.countdown_left==0);cycles(2);
 stop=1;cycles(1);stop=0;wait(phase==3);cycles(2);
 if(result_packet[95:64]!=1 || result_packet[159:128]!=1 || result_packet[295:288]!=0)$fatal(1,"partial result wrong %h",result_packet);
 $display("PASS playback timing/velocity/pause/release/natural finish; mid-practice stop publishes partial score");$finish;
 end
 initial begin #1000000;$fatal(1,"runner timeout phase%d stage%d",phase,d.stage);end
endmodule
