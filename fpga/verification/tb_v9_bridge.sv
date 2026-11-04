`timescale 1ns/1ps
module tb_v9_bridge;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,session=1,allowed=0,valid=0;reg[7:0]len=0;reg[7:0]p[0:228];wire[7:0]pa,code;wire ready,done,locked,remount,rr,wr;wire[383:0]reply;wire[31:0]lba;
 reg br=1,bd=0,rv=0;reg[8:0]ra=0,wa=0;reg[7:0]rb=0;wire[7:0]wb;
 reg [7:0] disk[0:511];integer state=0,counter=0,writes=0;
 hallpad_sd_bridge d(.clk(clk),.rst_n(rst),.session_valid(session),.allowed(allowed),.command_valid(valid),.command_length(len),.command_ready(ready),.command_done(done),.command_code(code),.reply(reply),.payload_addr(pa),.payload_data(p[pa]),.locked(locked),.remount(remount),.block_ready(br),.block_done(bd),.block_error(1'b0),.read_request(rr),.write_request(wr),.block_lba(lba),.read_valid(rv),.read_address(ra),.read_byte(rb),.write_address(wa),.write_byte(wb));
 always @(negedge clk)begin rv=0;bd=0;case(state)
 0:if(rr || wr)begin if(!locked || lba!=32'd2345)$fatal(1,"ownership/LBA");br=0;counter=0;state=rr ? 1:3;wa=0;end
 1:begin rv=1;ra=counter;rb=disk[counter];if(counter==511)state=2;else counter=counter+1;end
 2:begin bd=1;br=1;state=0;end
 3:state=4;
 4:begin disk[counter]=wb;if(counter==511)begin state=2;writes=writes+1;end else begin counter=counter+1;wa=counter;state=3;end end
 endcase end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task command(input integer n,input[7:0]expected);begin wait(ready);@(negedge clk);len=n;valid=1;cycles(1);valid=0;wait(done);cycles(1);if(code!=expected || reply[15:8]!=expected)$fatal(1,"command %d code %d expected %d",p[0],code,expected);cycles(2);end endtask
 integer i,o,n;
 initial begin for(i=0;i<512;i=i+1)disk[i]=i^8'h5a;for(i=0;i<229;i=i+1)p[i]=0;cycles(3);rst=1;
 p[0]=0;command(1,5);allowed=1;command(1,0);if(!locked)$fatal;
 p[0]=2;p[1]=41;p[2]=9;command(5,0);
 for(o=0;o<512;o=o+32)begin p[0]=5;p[1]=o;p[2]=o>>8;command(3,0);for(i=0;i<32;i=i+1)if(reply[32+i*8+:8]!==8'((o+i)^8'h5a))$fatal(1,"readback %d",o+i);end
 p[0]=3;p[1]=200;p[2]=1;command(200,3); // overflowing stage rejected before RAM writes
 for(o=0;o<512;o=o+192)begin n=512-o>192 ? 192:512-o;p[0]=3;p[1]=o;p[2]=o>>8;for(i=0;i<n;i=i+1)p[i+3]=(o+i)*3;command(n+3,0);end
 p[0]=4;p[1]=41;p[2]=9;p[3]=0;p[4]=0;command(5,0);if(writes!=1)$fatal;
 for(i=0;i<512;i=i+1)if(disk[i]!==8'(i*3))$fatal(1,"write %d %h",i,disk[i]);
 p[0]=1;command(1,0);if(locked)$fatal;p[0]=0;command(1,0);session=0;cycles(3);if(locked)$fatal(1,"disconnect did not release card");
 $display("PASS SD bridge: lock exclusion, read slices, stage bounds, 512-byte SPI write, unlock/remount/disconnect");$finish;end
 initial begin #2000000;$fatal(1,"bridge watchdog %d",d.state);end
endmodule
