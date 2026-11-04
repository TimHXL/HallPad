`timescale 1ns/1ps
module tb_slot_driver;
reg clk=0;always #10 clk=~clk;
reg rst_n=0;wire online,sample_valid;wire[111:0]sample_data,trace_data;wire trace_valid;
wire[7:0]diagnostic_code;wire[6:0]diagnostic_address;tri1 scl,sda;
reg[63:0]uptime_us=0;integer usdiv=0;always @(posedge clk)begin if(usdiv==49)begin uptime_us<=uptime_us+1;usdiv<=0;end else usdiv<=usdiv+1;end
wire launch,slot_abort,rgb_launch,window;wire [17:0] phase;
drum_slot5ms schedule(clk,rst_n,launch,slot_abort,rgb_launch,window,phase);
wire ms_tick=phase%50000==49999;
integer cycle_no=0,last_sample=-1;
always @(posedge clk)begin cycle_no<=cycle_no+1;if(dut.start && dut.read_count==14)begin
 if(last_sample>=0 && cycle_no-last_sample!=250000)$fatal(1,"sample interval not exactly 5 ms");last_sample<=cycle_no;end end
drum_mpu6050 #(.STARTUP_MS(2),.RETRY_MS(2)) dut(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.enable(launch),.slot_abort(slot_abort),.clear_faults(1'b0),.uptime_us(uptime_us),.scl(scl),.sda(sda),.online(online),.sample_valid(sample_valid),.sample_ready(1'b1),.sample_data(sample_data),.trace_valid(trace_valid),.trace_data(trace_data),.diagnostic_code(diagnostic_code),.diagnostic_address(diagnostic_address));
integer writes=0,reads=0;reg saw_error_trace=0;
always @(posedge clk)begin
 if(trace_valid && trace_data[24])saw_error_trace<=1;
 if(dut.start && dut.read_count==0)begin
 case(writes)
 0:if({dut.register_address,dut.write_data}!=16'h6b01)$fatal;
 1:if({dut.register_address,dut.write_data}!=16'h1a02)$fatal;
 2:if({dut.register_address,dut.write_data}!=16'h1904)$fatal;
 3:if({dut.register_address,dut.write_data}!=16'h1b18)$fatal;
 4:if({dut.register_address,dut.write_data}!=16'h1c18)$fatal;
 5:if({dut.register_address,dut.write_data}!=16'h6c00)$fatal;
 endcase
 writes<=writes+1;
 end
 if(dut.start && dut.read_count==14)reads<=reads+1;
end
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 wait(online);if(writes!=6)$fatal(1,"HP initialization sequence");
 wait(sample_valid);if(sample_data[7:0]!=8'h34)$fatal(1,"sample forwarding");
 wait(!online);if(diagnostic_code!=8'h31)$fatal(1,"sample error code");
 wait(diagnostic_address==7'h69);if(!saw_error_trace)$fatal(1,"trace not captured");
 $display("PASS: HP six-register initialization, online, sample forwarding, immediate offline, address retry and error trace");$finish;
end
initial begin #100000000;$fatal(1,"watchdog");end
endmodule
// Scripted transaction responder isolates the MPU scheduling FSM from the
// physical bus; tb_i2c_link independently tests the real HP bus master.
module drum_i2c_master #(parameter CLK_HZ=50000000,I2C_HZ=100000)(input clk,rst_n,start,abort,input[6:0]device_address,input[7:0]register_address,write_data,input[3:0]read_count,inout scl,sda,output reg busy,done,error,output reg[3:0]error_code,output[1:0]bus_lines,output reg[111:0]read_data);
assign bus_lines=2'b11;
integer delay_count=0,samples=0;reg fail_request;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin busy<=0;done<=0;error<=0;error_code<=0;read_data<=0;delay_count<=0;samples<=0;fail_request<=0;end
 else begin
 done<=0;
 if(abort && busy)begin busy<=0;done<=1;error<=1;error_code<=7;end
 else if(start && !busy)begin
 busy<=1;delay_count<=3;error<=0;error_code<=0;
 fail_request<=read_count==14 && samples!=0;
 if(read_count==1)read_data<=112'h68;else read_data<=112'h34;
 if(read_count==14)samples<=samples+1;
 end else if(busy)begin
 if(delay_count==0)begin busy<=0;done<=1;error<=fail_request;error_code<=fail_request?1:0;end
 else delay_count<=delay_count-1;
 end
 end
end
endmodule
