`timescale 1ns/1ps
module tb_v5_wave;
reg clk=0;always #10 clk=~clk;
reg rst=0,hit=0,stick=0;integer div=0;wire ms=div==9999;
always @(posedge clk)if(!rst)div<=0;else div<=ms?0:div+1;
reg[17:0] phase=0;always @(posedge clk)if(!rst)phase<=0;else phase<=phase==249999?0:phase+1'b1;
reg[87:0] config_data={24'hff7020,16'd1200,32'd80000,8'd100,8'd0};
wire l,r;
drum_strip_lights dut(.clk(clk),.rst_n(rst),.ms_tick(ms),.hit(hit),.stick(stick),.force_refresh(2'd0),.slot_launch(phase==102500),.slot_window(phase>=100000),.settings(48'd0),.color_settings(32'd0),.effect_config(config_data),.effect_active(1'b1),.serialL(l),.serialR(r));
integer arrivals[0:79];integer i,epoch=0;reg[31:0] start_ms;
always @(negedge clk)if(rst && dut.state==4 && dut.new_arrival && !dut.right_pixel)begin
 arrivals[dut.local_pixel]=arrivals[dut.local_pixel]+1;
 if(epoch==2 && dut.local_pixel==79 && dut.arrival_ms!=395)$fatal(1,"200 speed arrival %d",dut.arrival_ms);
end
task strike;begin @(negedge clk);hit=1;@(negedge clk);hit=0;end endtask
task until_ms(input integer target);begin wait(dut.now_ms>=target);@(negedge clk);end endtask
initial begin
 for(i=0;i<80;i=i+1)arrivals[i]=0;
 repeat(3)@(negedge clk);rst=1;repeat(200)@(negedge clk);strike();
 until_ms(150);config_data[47:16]=200000;config_data[63:48]=200;
 until_ms(200);stick=1;strike();stick=0;
 until_ms(1100);
 for(i=0;i<80;i=i+1)if(arrivals[i]!=1)$fatal(1,"setting replayed/missed pixel%0d count%0d",i,arrivals[i]);
 if(dut.speedL!=80000 || dut.decayL!=1200 || dut.envelope.parameters[0]!={18'd80000,13'd1200})$fatal(1,"old wave parameters changed");
 if(dut.speedR!=200000 || dut.decayR!=200 || dut.envelope.parameters[80]!={18'd200000,13'd200})$fatal(1,"right wave params not independent");
 epoch=2;strike();start_ms=dut.now_ms;
 until_ms(start_ms+450);
 for(i=0;i<80;i=i+1)if(arrivals[i]!=2)$fatal(1,"new wave pixel%0d count%0d",i,arrivals[i]);
 if(dut.envelope.parameters[79]!={18'd200000,13'd200})$fatal(1,"new wave params not latched");
 config_data[47:16]=40000;config_data[63:48]=5000;
 until_ms(start_ms+700);
 for(i=0;i<80;i=i+1)if(arrivals[i]!=2)$fatal(1,"parameter edit relit old wave");
 if(dut.envelope.parameters[79]!={18'd200000,13'd200})$fatal(1,"pixel decay not retained");
 $display("PASS per-hit speed/decay, per-pixel retention, no edit relight, 200LED/s pixel79=395ms");$finish;
end
initial begin #450000000;$fatal(1,"watchdog");end
endmodule
