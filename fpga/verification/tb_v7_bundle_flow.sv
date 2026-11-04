`timescale 1ns/1ps
module tb_v7_bundle_flow;
 reg [7:0] last_ui=0;always @(negedge clk)if(ui!=last_ui)begin $display("ui=%d err=%h front=%d play=%b pos=%d cmd=%h size=%d t=%t",ui,error,front.state,playback,pos,ct,front_size,$time);last_ui=ui;end
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,enter=0,short_press=0,long_press=0,step_valid=0,step_up=1;
 integer pos=0,divider=0;reg ms_tick=0;reg[31:0]now_ms=0;
 wire raw_cancel;wire active,open_file,cancel,raw_ready,front_valid,front_ready,front_done,playback,choosing,failed;
 wire[7:0]front_byte,front_state;wire[31:0]front_size;
 reg[7:0]bytes[0:2601];
 wire mapping,result_valid;wire[34:0]enabled,fixed_mask,auto_mask;wire[244:0]midi,velocity;wire[139:0]timbre;
 wire[383:0]result_packet;wire[255:0]text;wire[7:0]ui,error;
 wire cv,cr,cd;wire[7:0]ct,cl,pa,pd,cc;wire[2:0]phase;
 hallpad_hpg3 front(.clk(clk),.rst_n(rst_n),.open_file(open_file),.cancel(cancel),.step_valid(step_valid),.step_up(step_up),.short_press(short_press),.raw_size(32'd2602),.raw_valid(active && pos<2602),.raw_byte(bytes[pos]),.raw_ready(raw_ready),.raw_cancel(raw_cancel),.raw_done(1'b0),.data_valid(front_valid),.data_byte(front_byte),.data_ready(front_ready),.data_done(front_done),.data_size(front_size),.playback(playback),.choosing(choosing),.failed(failed),.choice_state(front_state),.title_index(4'd0),.title_row(5'd0),.title_column(5'd0));
 always @(posedge clk)if(open_file)pos<=0;else if(raw_ready && active && pos<2602)pos<=pos+1;
 always @(negedge clk)begin ms_tick=divider==99;if(divider==99)begin divider=0;now_ms=now_ms+1;end else divider=divider+1;end
 hallpad_offline_ctrl ctrl(.clk(clk),.rst_n(rst_n),.enter(enter),.step_valid(1'b0),.step_up(1'b1),.short_press(short_press && !choosing),.long_press(long_press),.keys_released(auto_mask==0),.result_valid(result_valid),.result_packet(result_packet),.mapping_active(mapping),.map_enabled(enabled),.map_fixed(fixed_mask),.map_midi(midi),.map_velocity(velocity),.map_timbre(timbre),.result_text(text),.active(active),.ui_state(ui),.ui_error(error),.mounted(1'b1),.card_failed(failed),.card_error(failed ? 8'he5:8'd0),.song_count(6'd1),.open_file(open_file),.file_size(front_size),.file_valid(front_valid),.file_byte(front_byte),.file_ready(front_ready),.file_done(front_done),.file_cancel(cancel),.command_valid(cv),.command_ready(cr),.command_type(ct),.command_length(cl),.payload_addr(pa),.payload_data(pd),.command_done(cd),.command_code(cc),.run_phase(phase));
 hallpad_practice #(.COUNTDOWN_MS(3)) practice(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.session_valid(active),.session_id(32'd1),.uptime_ms(now_ms),.panic_latched(1'b0),.practice_allowed(1'b1),.auto_play(playback),.auto_mask(auto_mask),.physical_mask(35'd0),.key_enabled(enabled),.key_midi(midi),.command_valid(cv),.command_ready(cr),.command_type(ct),.command_length(cl),.payload_addr(pa),.payload_data(pd),.command_done(cd),.command_code(cc),.notification_take(1'b1),.local_result_valid(result_valid),.local_result_packet(result_packet),.local_run_phase(phase));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task click;begin @(negedge clk);short_press=1;cycles(1);short_press=0;cycles(5);end endtask
 task back;begin @(negedge clk);long_press=1;cycles(1);long_press=0;cycles(5);end endtask
 initial begin
 $readmemh("verification/bundle.hex",bytes);cycles(3);rst_n=1;enter=1;cycles(1);enter=0;cycles(5);click();wait(choosing);cycles(3);click();step_valid=1;cycles(1);step_valid=0;cycles(3);click();click();wait(ui==3 || ui==7);if(ui==7)$fatal(1,"load %h",error);
 if(!mapping || !playback)$fatal(1,"map/playback");click();wait(auto_mask!=0);click();wait(ui==5);if(auto_mask!=0)$fatal(1,"pause mask");click();wait(ui==6 || ui==7);cycles(3);if(ui==7 || mapping || auto_mask!=0)$fatal(1,"finish restore");
 // Mid-run long press must remain on result screen and restore map.
 click();wait(choosing);cycles(3);click();step_valid=1;cycles(1);step_valid=0;cycles(3);click();click();wait(ui==3);click();wait(auto_mask!=0);back();wait(ui==6 || ui==7);cycles(3);if(ui==7 || mapping)$fatal(1,"stop result/restore");back();wait(ui==1);
 // Cancel while held at track selection: no draining deadlock.
 click();wait(choosing);cycles(3);back();wait(ui==7);back();cycles(5);
 $display("PASS full HPG3 frontend -> existing HPG2 CRC/shared RAM -> playback/pause/resume/finish/stop-result/map restore; cancel track selection");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout ui%d phase%d ctrl%d front%d cc%h pos%d",ui,phase,ctrl.state,front.state,cc,pos);end
endmodule
