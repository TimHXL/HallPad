`timescale 1ns/1ps
module tb_hpg3;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,open_file=0,cancel=0,step_valid=0,step_up=1,short_press=0;
 reg [7:0] bytes[0:2601],expected[0:303];integer pos=0,received=0;
 wire raw_ready,data_valid,data_done,playback,choosing,failed,title_valid,title_ink;
 wire [7:0] data_byte,choice_state;wire [31:0] data_size,skipped;wire[63:0]choice_text;wire[4:0]title_count;
 reg [3:0] title_index=0;reg[4:0]title_row=0,title_column=0;
 hallpad_hpg3 d(.clk(clk),.rst_n(rst_n),.open_file(open_file),.cancel(cancel),.step_valid(step_valid),.step_up(step_up),.short_press(short_press),
 .raw_size(32'd2602),.raw_valid(pos<2602),.raw_byte(bytes[pos]),.raw_ready(raw_ready),.raw_done(1'b0),.data_valid(data_valid),.data_byte(data_byte),.data_ready(1'b1),.data_done(data_done),.data_size(data_size),.playback(playback),.choosing(choosing),.failed(failed),.choice_state(choice_state),.choice_text(choice_text),.skipped(skipped),.title_valid(title_valid),.title_count(title_count),.title_index(title_index),.title_row(title_row),.title_column(title_column),.title_ink(title_ink));
 always @(posedge clk)begin
 if(rst_n && raw_ready && pos<2602)pos<=pos+1;
 if(data_valid)begin if(received>=304 || data_byte!==expected[received])$fatal(1,"selected bytes differ at %d",received);received<=received+1;end
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task click;begin @(negedge clk);short_press=1;cycles(1);short_press=0;cycles(4);end endtask
 task step;begin @(negedge clk);step_valid=1;cycles(1);step_valid=0;cycles(4);end endtask
 integer y,x,lit=0,expected_lit;
 initial begin
 $readmemh("verification/legacy_bundle.hex",bytes);$readmemh("verification/legacy_selected.hex",expected);
 cycles(3);rst_n=1;open_file=1;cycles(1);open_file=0;
 wait(choosing || failed);cycles(3);if(failed || title_count!=5 || !title_valid)$fatal(1,"metadata failed");
 step();step();cycles(24);if(choice_text!="TRK00002")$fatal(1,"track ID %h",choice_text);click();step();if(!playback)$fatal(1,"mode failed");click();click();
 wait(data_done || failed);cycles(2);if(failed || received!=304 || data_size!=304)$fatal(1,"payload failed received %d",received);
 for(y=0;y<22;y=y+1)for(x=0;x<22;x=x+1)begin
 title_row=5'(y);title_column=5'(x);cycles(2);
 expected_lit=(bytes[592+y*3+x/8]>>(7-x%8))&1;
 if(title_ink!==1'(expected_lit))$fatal(1,"title transpose x%d y%d",x,y);if(title_ink)lit=lit+1;
 end
 if(lit==0)$fatal(1,"empty title");
 // Corrupt metadata, must reject before exposing a single inner object.
 cancel=1;cycles(1);cancel=0;pos=0;received=0;bytes[100]=bytes[100]^8'd1;open_file=1;cycles(1);open_file=0;
 wait(failed);if(data_valid || title_valid)$fatal(1,"bad metadata exposed");
 $display("PASS HPG3 track2/playback selection, byte-exact nested HPG2, all 484 title pixels, corrupt metadata rejection");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout state%d pos%d",d.state,pos);end
endmodule
