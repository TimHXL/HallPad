`timescale 1ns/1ps
module tb_key_finish;
reg clk=0;always #10 clk=~clk;reg rst_n=0,key_valid=0,cal_cmd_valid=0,cal_clear=0,load_valid=0;
reg[5:0]key_id=0,cal_key_id=0,load_key_id=0;reg[11:0]key_data=0,load_baseline=1000,load_span=1000;reg[1:0]cal_cmd=0;
wire[34:0]calibrated_mask,busy_mask,failed_mask;wire cal_error;
key_calibrate #(.CAPTURE_LOG2(0),.ENABLE_PRESET_LOAD(1))dut(.clk(clk),.rst_n(rst_n),.key_valid(key_valid),.key_id(key_id),.key_data(key_data),.key_raw_data(key_data),.key_note_valid(1'b1),.note_sel(6'd1),.mapped_scan_done(1'b0),.mapped_tag_error(3'd0),.map_error(1'b0),.cal_clear(cal_clear),.cal_cmd_valid(cal_cmd_valid),.cal_cmd(cal_cmd),.cal_key_id(cal_key_id),.load_valid(load_valid),.load_key_id(load_key_id),.load_baseline(load_baseline),.load_span(load_span),.load_decreasing(1'b0),.calibrated_mask(calibrated_mask),.busy_mask(busy_mask),.failed_mask(failed_mask),.cal_error(cal_error));
task cmd(input[1:0]c);begin @(negedge clk);cal_cmd=c;cal_cmd_valid=1;@(negedge clk);cal_cmd_valid=0;end endtask
task sample(input[11:0]d);begin @(negedge clk);key_data=d;key_valid=1;@(negedge clk);key_valid=0;end endtask
initial begin repeat(3)@(negedge clk);rst_n=1;
cmd(1);sample(1000);repeat(2)@(negedge clk);if(dut.baseline[0]!=1000)$fatal(1,"baseline");
cmd(2);sample(2000);repeat(3)@(negedge clk);if(!calibrated_mask[0]||dut.span[0]!=1000||dut.decreasing[0])$fatal(1,"increasing endpoint");
cmd(2);sample(500);repeat(3)@(negedge clk);if(!calibrated_mask[0]||dut.span[0]!=500||!dut.decreasing[0])$fatal(1,"decreasing endpoint");
cmd(2);sample(1050);repeat(3)@(negedge clk);if(calibrated_mask[0]||!failed_mask[0])$fatal(1,"short span");
cmd(2);sample(2000);cal_clear=1;@(negedge clk);cal_clear=0;repeat(3)@(negedge clk);if(calibrated_mask[0]||busy_mask[0])$fatal(1,"clear leaked pending");
load_valid=1;@(negedge clk);load_valid=0;repeat(2)@(negedge clk);if(!calibrated_mask[0]||dut.span[0]!=1000)$fatal(1,"preset");
$display("PASS: capture endpoint pipeline increasing/decreasing/invalid-span/clear cancellation/preset");$finish;end
endmodule
