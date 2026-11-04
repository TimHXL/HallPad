`timescale 1ns/1ps
module tb_v9_catalog;
 reg clk=0;always #10 clk=~clk;reg rst=0,open=0;wire mounted,failed,idle,request,dv,fd;wire[31:0]lba,size;wire[8:0]count;wire[63:0]name;wire[7:0]db;
 reg ready=1,done=0,rv=0;reg[8:0]ra=0;reg[7:0]rb=0;reg[7:0]bytes[0:9727];integer state=0,page=0,index=0,received=0;
 hallpad_sd_catalog d(.clk(clk),.rst_n(rst),.block_ready(ready),.block_done(done),.block_error(1'b0),.block_request(request),.block_lba(lba),.read_valid(rv),.read_address(ra),.read_byte(rb),.open_file(open),.selection(8'd255),.file_idle(idle),.mounted(mounted),.failed(failed),.song_count(count),.song_name(name),.file_size(size),.data_valid(dv),.data_byte(db),.data_ready(1'b1),.file_done(fd),.cancel(1'b0));
 `include "v9_catalog_map.svh"
 always @(posedge clk)begin rv<=0;done<=0;case(state)
 0:if(request)begin page<=page_for(lba);index<=0;ready<=0;state<=1;end
 1:begin if(page<0)$fatal;rv<=1;ra<=index;rb<=bytes[page*512+index];if(index==511)state<=2;else index<=index+1;end
 2:begin ready<=1;done<=1;state<=0;end
 endcase
 if(dv)begin if(db!==bytes[page_for(648)*512+received])$fatal(1,"last file data %d",received);received<=received+1;end
 end
 initial begin $readmemh("verification/v9_catalog.hex",bytes);repeat(3)@(negedge clk);rst=1;wait(mounted || failed);repeat(5)@(negedge clk);if(failed || count!=256 || name!="S0000255")$fatal(1,"count %d last name %h",count,name);open=1;@(negedge clk);open=0;wait(fd);repeat(3)@(negedge clk);if(received!=232 || size!=232)$fatal(1,"last file %d size%d",received,size);
 $display("PASS FPGA FAT32 catalog: 256 files across 16 root clusters, count256 preserved, select/open last file255, bytes exact");$finish;end
 initial begin #10000000;$fatal(1,"catalog watchdog");end
endmodule
