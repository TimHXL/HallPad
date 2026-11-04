`timescale 1ns/1ps
module tb_v9_hotplug;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,present=0;wire reset_card,missing,probe,probing,due;
 reg ready=0,done=0,error=0,read_valid=0;reg[8:0]read_address=0;reg[7:0]read_byte=0;
 wire request,idle,mounted,failed;wire[31:0]lba;wire[8:0]count;wire[63:0]name;reg[7:0]selection=0;
 reg[7:0]bytes[0:7679];integer div=0,driver=0,index=0,page=0,waited=0;integer probes=0,resets=0;
 wire tick=div==9;always @(posedge clk)div<=tick ? 0:div+1;
 hallpad_sd_hotplug #(.POLL_MS(10),.RESET_MS(2)) hot(.clk(clk),.rst_n(rst),.ms_tick(tick),.can_probe(idle),.card_ready(ready),.card_done(done),.card_error(error),.catalog_failed(failed),.mounted(mounted),.probe(probe),.probing(probing),.reset_card(reset_card),.missing(missing),.probe_due(due));
 hallpad_sd_catalog cat(.clk(clk),.rst_n(rst && !reset_card),.block_ready(ready && !probing),.block_done(done),.block_error(error),.block_request(request),.block_lba(lba),.read_valid(read_valid && !probing),.read_address(read_address),.read_byte(read_byte),.open_file(1'b0),.selection(selection),.file_idle(idle),.mounted(mounted),.failed(failed),.song_count(count),.song_name(name),.data_ready(1'b1),.cancel(1'b0));
 `include "bundle_sd_fixture_map.svh"
 always @(posedge clk)begin
 done<=0;read_valid<=0;
 if(!rst || reset_card)begin ready<=0;error<=0;driver<=0;waited<=0;end
 else case(driver)
 0:if(waited==4)begin if(present)begin ready<=1;driver<=1;end else error<=1;end else waited<=waited+1;
 1:if(probe || request)begin ready<=0;index<=0;if(probe)probes<=probes+1;page<=page_for(probing ? 0:lba);driver<=2;end
 2:if(!present)begin error<=1;driver<=4;end else begin
  if(page<0)$fatal(1,"unknown sector");read_valid<=1;read_address<=index;read_byte<=bytes[page*512+index];
  if(index==511)driver<=3;else index<=index+1;
 end
 3:begin done<=1;ready<=1;driver<=1;end
 endcase end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 initial begin $readmemh("verification/bundle_sd_fixture.hex",bytes);cycles(3);rst=1;wait(missing);cycles(100);if(count!=0 || mounted)$fatal(1,"absent catalog");
 present=1;wait(mounted && !missing);cycles(3);if(count!=5)$fatal(1,"late insert count %d",count);
 present=0;wait(missing && reset_card);cycles(2);if(count!=0 || mounted || name!=64'h2020202020202020)$fatal(1,"stale catalog after removal");
 present=1;wait(mounted && !missing);cycles(5);if(count!=5)$fatal(1,"reinsert count");
 $display("PASS SD hotplug: boot without card, late insertion, idle probe detects removal, immediate catalog clear, reinsert/remount without global reset");$finish;end
 initial begin #10000000;$fatal(1,"hotplug watchdog driver%d count%d mounted%b missing%b",driver,count,mounted,missing);end
endmodule
