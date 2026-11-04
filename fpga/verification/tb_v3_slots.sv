`timescale 1ns/1ps
module tb_v3_slots;
reg clk=0;always #10 clk=~clk;
reg rst_n=0;wire launch,abort,led_launch,window;wire [17:0] phase;
drum_slot5ms schedule(clk,rst_n,launch,abort,led_launch,window,phase);
tri1 scl,sda;reg slave_low=0;assign sda=slave_low?1'b0:1'bz;
wire busy,done,error;wire [3:0] error_code;wire [1:0] lines;wire [111:0] data;
drum_i2c_master bus(.clk(clk),.rst_n(rst_n),.start(launch),.abort(abort),.device_address(7'h68),
.register_address(8'h3b),.write_data(8'd0),.read_count(4'd14),.scl(scl),.sda(sda),.busy(busy),.done(done),.error(error),.error_code(error_code),.bus_lines(lines),.read_data(data));
tri1 scl2,sda2;reg hold_clock=1;assign scl2=hold_clock?1'b0:1'bz;
wire busy2,done2,error2;wire [3:0] ec2;
drum_i2c_master #(.STRETCH_US(10000)) stalled(.clk(clk),.rst_n(rst_n),.start(launch),.abort(abort),.device_address(7'h68),
.register_address(8'h3b),.write_data(8'd0),.read_count(4'd14),.scl(scl2),.sda(sda2),.busy(busy2),.done(done2),.error(error2),.error_code(ec2),.bus_lines(),.read_data());
reg [1:0] hit=0;wire serialL,serialR;
drum_strip_lights rgb(.clk(clk),.rst_n(rst_n),.ms_tick(phase%50000==49999),.hit(hit[0]),.stick(1'b0),
.slot_launch(led_launch),.slot_window(window),.settings(48'd0),.color_settings(32'd0),
.force_refresh(2'b00),.effect_config({24'h0000ff,16'd1200,32'd80000,8'd100,8'd1}),.effect_active(1'b1),.serialL(serialL),.serialR(serialR));
integer cycles=0,last_launch=-1,reads=0,aborts=0,frames=0,bits=0;reg was_sending=0;
always @(negedge clk)if(rst_n)begin
 cycles=cycles+1;
 if(rgb.output_ram.commit_ready && !window)$fatal(1,"commit outside window");
 if(launch)begin if(last_launch>=0 && cycles-last_launch!=250000)$fatal(1,"frame period");last_launch=cycles;end
 if(window && (bus.scl_low || bus.sda_low || stalled.scl_low || stalled.sda_low))$fatal(1,"I2C driving in LED slot");
 if(!window && (serialL || serialR || (rgb.output_ram.state==3)))$fatal(1,"LED in MPU slot");
 if(done)begin if(error)$fatal(1,"normal read error %d",error_code);if(phase>=100000)$fatal(1,"late read");reads=reads+1;end
 if(done2 && ec2==7)aborts=aborts+1;
 if((rgb.output_ram.state==3) && !was_sending)bits=0;
 if((rgb.output_ram.state==3) && rgb.output_ram.bit_cycle==32)begin
 if(serialL!==((24'h00ff00 >> (23-bits%24))&1) || serialR!==((24'h00ff00 >> (23-bits%24))&1))$fatal(1,"GRB mismatch");bits=bits+1;end
 if(!(rgb.output_ram.state==3) && was_sending)begin if(bits!=1920)$fatal(1,"not 80 pixels");frames=frames+1;end
 was_sending=(rgb.output_ram.state==3);
end
 task start_seen;begin @(negedge sda);while(!scl)@(negedge sda);end endtask
 task receive_byte(input[7:0]expected,input bit ack);reg[7:0]b;integer i;begin
 b=0;for(i=0;i<8;i=i+1)begin @(posedge scl);#1;b={b[6:0],sda};end
 if(b!==expected)$fatal(1,"TX expected %h got %h",expected,b);
 @(negedge scl);#1;slave_low=ack;@(posedge scl);@(negedge scl);#1;slave_low=0;
 end endtask
 task send_byte(input[7:0]b,input bit expect_ack);integer i;begin
 for(i=7;i>=0;i=i-1)begin slave_low=!b[i];@(posedge scl);@(negedge scl);#1;end
 slave_low=0;@(posedge scl);#1;if(sda!==!expect_ack)$fatal(1,"master ACK mismatch");@(negedge scl);#1;
 end endtask

integer k,j;
initial begin
 repeat(5)@(negedge clk);rst_n=1;hit=3;@(negedge clk);hit=0;
 for(k=0;k<3;k=k+1)begin
 start_seen();receive_byte(8'hd0,1);receive_byte(8'h3b,1);start_seen();receive_byte(8'hd1,1);
 for(j=0;j<14;j=j+1)send_byte(j[7:0],j!=13);
 end
 wait(reads==3 && aborts==3);wait(phase==240000);@(negedge clk);if(frames!=1)$fatal(1,"unchanged static frame repeated %d",frames);if(reads!=3 || aborts!=3)$fatal(1,"counts reads%0d aborts%0d",reads,aborts);
 $display("PASS fixed 250000-clock frames; 14-byte reads; hard deadline abort; no MPU/RGB overlap; 80 GRB pixels per window");$finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
