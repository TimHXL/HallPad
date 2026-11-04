`timescale 1ns/1ps
module tb_i2c_link;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,start=0;reg[6:0] device_address=7'h68;reg[7:0] register_address=8'h75,write_data=8'h01;reg[3:0]read_count=1;
 tri1 scl,sda;reg slave_low=0,stretch=0;assign sda=slave_low?1'b0:1'bz;assign scl=stretch?1'b0:1'bz;
 wire busy,done,error;wire[3:0]error_code;wire[1:0]bus_lines;wire[111:0]read_data;
 drum_i2c_master dut(.*);
 task launch;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
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
 initial begin
 repeat(4)@(negedge clk);rst_n=1;
 fork begin launch();wait(done);if(error||read_data[7:0]!=8'h68)$fatal(1,"WHO read");end
 begin start_seen();receive_byte(8'hd0,1);receive_byte(8'h75,1);start_seen();receive_byte(8'hd1,1);send_byte(8'h68,0);end join
 repeat(10)@(negedge clk);read_count=2;register_address=8'h3b;
 fork begin launch();wait(done);if(error||read_data[15:0]!=16'h3412)$fatal(1,"burst read");end
 begin start_seen();receive_byte(8'hd0,1);receive_byte(8'h3b,1);start_seen();receive_byte(8'hd1,1);send_byte(8'h12,1);send_byte(8'h34,0);end join
 repeat(10)@(negedge clk);read_count=0;register_address=8'h6b;
 fork begin launch();wait(done);if(error)$fatal(1,"write");end
 begin start_seen();receive_byte(8'hd0,1);receive_byte(8'h6b,1);receive_byte(8'h01,1);end join
 repeat(10)@(negedge clk);
 fork begin launch();wait(done);if(!error||error_code!=1)$fatal(1,"address NACK");end begin start_seen();receive_byte(8'hd0,0);end join
 repeat(10)@(negedge clk);
 fork begin launch();wait(done);if(!error||error_code!=2)$fatal(1,"register NACK");end begin start_seen();receive_byte(8'hd0,1);receive_byte(8'h6b,0);end join
 repeat(10)@(negedge clk);read_count=1;
 fork begin launch();wait(done);if(!error||error_code!=4)$fatal(1,"read address NACK");end begin start_seen();receive_byte(8'hd0,1);receive_byte(8'h6b,1);start_seen();receive_byte(8'hd1,0);end join
 repeat(10)@(negedge clk);read_count=0;
 fork begin launch();wait(done);if(!error||error_code!=3)$fatal(1,"write data NACK");end begin start_seen();receive_byte(8'hd0,1);receive_byte(8'h6b,1);receive_byte(8'h01,0);end join
 repeat(10)@(negedge clk);stretch=1;launch();wait(done);if(error_code!=5)$fatal(1,"stretch timeout");stretch=0;
 repeat(10)@(negedge clk);slave_low=1;launch();wait(done);if(error_code!=6)$fatal(1,"stuck SDA");slave_low=0;
 $display("PASS: I2C WHO, repeated START, burst ACK/NACK, write, four NACK stages, stretch timeout and stuck-SDA recovery failure");$finish;
 end
 initial begin #10000000;$fatal(1,"watchdog");end
endmodule
