`timescale 1ns/1ps
module tb_score_beat;
reg clk=0;always #10 clk=~clk;
reg rst_n=0,ms_tick=0,sample_tick=0,session_valid=1,panic=0,audio_available=1,request=0,is_trigger=0,free_select=0;
reg[31:0]session_id=1;reg[79:0]data=0;
wire done,external_mode,trigger,accent,clear_click;wire[7:0]result;wire[15:0]detail;
hallpad_score_beat dut(.*);
wire beat_pulse;wire[23:0]pcm_out;
audio_effects fx(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.external_mode(external_mode),.external_trigger(trigger),.external_accent(accent),.external_clear(clear_click),.pcm_in(24'sd0),.echo_percent(7'd0),.metro_enable(1'b1),.metro_beats(4'd4),.metro_unit(4'd4),.metro_bpm(bpm),.pcm_out(pcm_out),.beat_pulse(beat_pulse),.beat_accent());
reg[7:0] bpm=120;
integer sounded=0;always @(negedge clk)if(beat_pulse)sounded=sounded+1;
task cycles(input integer n);repeat(n)@(negedge clk);endtask
task control(input bit action,input[31:0]token,input[7:0]expected);begin
 data={40'd0,token,7'd0,action};is_trigger=0;request=1;cycles(1);request=0;
 if(!done || result!=expected)$fatal(1,"control result %d",result);cycles(2);
end endtask
task beat(input[31:0]token,input[15:0]counter,input[7:0]accent_value,input[7:0]expected);begin
 data={accent_value,8'd4,8'd4,8'd0,counter,token};is_trigger=1;request=1;cycles(1);request=0;
 if(!done || result!=expected)$fatal(1,"beat result %d",result);cycles(2);
end endtask
task sample;begin sample_tick=1;cycles(1);sample_tick=0;cycles(5);end endtask
initial begin
 cycles(4);rst_n=1;cycles(3);
 control(1,1,0);beat(1,16'hffff,1,0);cycles(5);
 if(!trigger)$fatal(1,"pending lost between samples");sample();if(sounded!=1)$fatal(1,"first click");
 bpm=180;beat(1,16'hffff,1,0);sample();if(sounded!=1)$fatal(1,"duplicate click");
 beat(1,0,0,0);sample();if(sounded!=2)$fatal(1,"counter wrap");
 beat(1,16'hfffe,1,0);sample();if(sounded!=2)$fatal(1,"old counter");
 beat(1,1,2,3);sample();if(sounded!=2)$fatal(1,"invalid accent");
 beat(1,1,1,0);beat(1,2,0,0);if(dut.dropped_clicks!=1)$fatal(1,"pending replacement count");sample();if(sounded!=3 || fx.click_accent!=0)$fatal(1,"latest pending");
 ms_tick=1;cycles(1000);ms_tick=0;cycles(2);if(trigger || fx.click_env!=0 || !dut.token_valid)$fatal(1,"lease expiry");
 beat(1,3,1,0);sample();if(sounded!=4)$fatal(1,"slow beat resume");
 control(1,2,0);control(0,1,5);beat(1,4,1,5);beat(2,10,1,0);
 panic=1;cycles(2);sample();panic=0;cycles(2);if(sounded!=4 || dut.token_valid || fx.click_env!=0)$fatal(1,"panic clear");
 control(1,3,0);beat(3,0,1,0);control(0,3,0);sample();if(sounded!=4 || !external_mode)$fatal(1,"stop mute");
 control(1,4,0);audio_available=0;cycles(2);control(1,5,5);control(0,4,0);audio_available=1;cycles(2);
 control(1,6,0);session_id=2;cycles(2);if(dut.token_valid)$fatal(1,"session switch");
 control(1,7,0);session_valid=0;cycles(2);if(dut.token_valid)$fatal(1,"session loss");session_valid=1;cycles(2);
 free_select=1;cycles(1);free_select=0;cycles(2);if(external_mode)$fatal(1,"free mode select");sample();if(sounded!=5)$fatal(1,"free mode restart");
 control(1,8,0);
 // Invalid fields must leave pending/counter history unchanged.
 data={8'd1,8'd3,8'd4,8'd0,16'd0,32'd8};is_trigger=1;request=1;cycles(1);request=0;if(result!=3 || detail!=8)$fatal(1,"invalid unit");cycles(2);
 data={8'd1,8'd4,8'd0,8'd0,16'd0,32'd8};request=1;cycles(1);request=0;if(result!=3 || detail!=7)$fatal(1,"invalid beats");cycles(2);
 data={8'd1,8'd4,8'd4,8'd4,16'd0,32'd8};request=1;cycles(1);request=0;if(result!=3 || detail!=6)$fatal(1,"invalid index");cycles(2);
 if(dut.counter_valid || trigger)$fatal(1,"invalid field committed");
 data={8'd1,8'd16,8'd6,8'd0,16'd0,32'd8};request=1;cycles(1);request=0;if(result!=0)$fatal(1,"unit16/meter6 rejected");cycles(2);sample();if(sounded!=6)$fatal(1,"unit16 click");
 $display("PASS: pending/sample boundary, duplicate/old/wrapped counters, validation, latest wins, lease/slow beats, token isolation, PANIC/STOP/audio/session clear, free metronome");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule
