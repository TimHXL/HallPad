`timescale 1ns/1ps
module tb_v9_max;
 `include "v9_max_sizes.svh"
 reg clk=0;always #10 clk=~clk;
 reg rst=0,open=0,step=0,short_press=0;reg[7:0]bytes[0:SIZE-1],expected[0:SELECTED_SIZE-1];integer pos=0,received=0;
 wire rr,dv,done,choosing,failed,title_valid;wire[7:0] db;wire[63:0]choice;wire[5:0]tc;reg[4:0]ti=31;
 hallpad_hpg3 d(.clk(clk),.rst_n(rst),.open_file(open),.cancel(1'b0),.step_valid(step),.step_up(1'b0),.short_press(short_press),.preview_only(1'b0),
 .raw_size(SIZE),.raw_valid(pos<SIZE),.raw_byte(bytes[pos]),.raw_ready(rr),.raw_done(1'b0),.data_valid(dv),.data_byte(db),.data_ready(1'b1),.data_done(done),.choosing(choosing),.failed(failed),.choice_text(choice),.title_valid(title_valid),.title_count(tc),.title_index(ti),.title_row(5'd0),.title_column(5'd0));
 always @(posedge clk)begin if(rst && rr && pos<SIZE)pos<=pos+1;if(dv)begin if(received>=SELECTED_SIZE || db!==expected[received])$fatal(1,"nested bytes at %d",received);received<=received+1;end end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task click;begin short_press=1;cycles(1);short_press=0;cycles(6);end endtask
 initial begin $readmemh("verification/v9_max.hex",bytes);$readmemh("verification/v9_max_selected.hex",expected);cycles(3);rst=1;open=1;cycles(1);open=0;wait(choosing || failed);cycles(6);
 if(failed || tc!=32 || !title_valid || d.tracks!=257)$fatal(1,"max metadata");
 step=1;cycles(1);step=0;cycles(30);if(choice!="TRK00255")$fatal(1,"last track %h sel%d",choice,d.track_sel);click();step=1;cycles(1);step=0;cycles(6);click();click();wait(done || failed);cycles(3);if(failed || received!=SELECTED_SIZE)$fatal(1,"selected stream %d",received);
 $display("PASS HPG3 v4: 257 choices, 32-character/glyph title, wrap to original track255, selected nested bytes exact");$finish;end
 initial begin #20000000;$fatal(1,"max fixture watchdog");end
endmodule
