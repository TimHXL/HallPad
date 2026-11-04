`timescale 1ns/1ps
module tb_v7_overlap;
reg clk=0;always #10 clk=~clk;reg rst_n=0,start=0,ms_tick=0;integer div=0;reg[31:0]time_ms=0;
wire req;wire[11:0]idx;reg valid=0;reg[191:0]data=0;wire[34:0]mask;wire[2:0]phase;
hallpad_practice_runner #(.COUNTDOWN_MS(1)) d(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.session_clear(1'b0),.object_clear(1'b0),.binding_fault(1'b0),.panic_latched(1'b0),.practice_allowed(1'b1),.start(start),.pause(1'b0),.resume(1'b0),.stop(1'b0),.auto_play(1'b1),.auto_mask(mask),.upload_id(32'd1),.start_run_id(32'd1),.score_crc(32'd0),.uptime_ms(time_ms),.total_groups(13'd3),.start_speed(16'd1000),.physical_mask(35'd0),.key_enabled({35{1'b1}}),.record_request(req),.record_index(idx),.record_valid(valid),.record_data(data),.phase(phase));
always @(negedge clk)begin
 ms_tick=div==99;if(div==99)begin div=0;time_ms=time_ms+1;end else div=div+1;
 valid=req;if(req)case(idx)
 0:data={16'd0,8'd100,8'd1,64'd1,32'd20,32'd0,32'd0};
 1:data={16'd1,8'd100,8'd2,64'd3,32'd20,32'd20,32'd1};
 2:data={16'd0,8'd100,8'd1,64'd2,32'd20,32'd40,32'd2};
 endcase
 if(phase==1 && d.score_time>=5 && d.score_time<40 && !mask[0])$fatal(1,"held key 0 interrupted at %d",d.score_time);
 if(phase==1 && d.score_time>=25 && d.score_time<60 && !mask[1])$fatal(1,"held key 1 interrupted at %d",d.score_time);
end
initial begin repeat(3)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;wait(phase==3);@(negedge clk);if(mask!=0)$fatal(1,"last note release");$display("PASS overlap: no key-off bubble across adjacent held-mask segments; last note kept to deadline");$finish;end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
