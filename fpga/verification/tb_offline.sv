`timescale 1ns/1ps
module tb_offline;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,ms_tick=0;reg [31:0] uptime_ms=0;
 integer divider=0;
 always @(negedge clk)begin
  ms_tick=divider==299;if(divider==299)begin divider=0;uptime_ms=uptime_ms+1;end else divider=divider+1;
 end
 reg enter=0,step_valid=0,step_up=1,short_press=0,long_press=0;
 wire active;wire [4:0] selection;wire [7:0] ui_state,ui_error;
 wire mounted,failed;wire [7:0] error_code;wire [5:0] song_count;wire [63:0] song_name;
 wire block_request;wire [31:0] block_lba,file_size;
 reg block_ready=1,block_done=0,read_valid=0;reg [8:0] read_address=0;reg [7:0] read_byte=0;
 wire open_file,data_valid,data_ready,file_done,cancel;wire [7:0] data_byte;
 hallpad_sd_catalog catalog(.clk(clk),.rst_n(rst_n),.block_ready(block_ready),.block_done(block_done),.block_error(1'b0),
 .block_request(block_request),.block_lba(block_lba),.read_valid(read_valid),.read_address(read_address),.read_byte(read_byte),
 .open_file(open_file),.selection(selection),.mounted(mounted),.failed(failed),.error_code(error_code),.song_count(song_count),.song_name(song_name),
 .file_size(file_size),.data_valid(data_valid),.data_byte(data_byte),.data_ready(data_ready),.file_done(file_done),.cancel(cancel));
 wire command_valid,command_ready,command_done;wire [7:0] command_type,command_length,payload_addr,payload_data,command_code;wire [2:0] run_phase;
 hallpad_offline_ctrl ctrl(.clk(clk),.rst_n(rst_n),.enter(enter),.step_valid(step_valid),.step_up(step_up),.short_press(short_press),.long_press(long_press),
 .active(active),.selection(selection),.ui_state(ui_state),.ui_error(ui_error),.mounted(mounted),.card_failed(failed),.card_error(error_code),.song_count(song_count),
 .open_file(open_file),.file_size(file_size),.file_valid(data_valid),.file_byte(data_byte),.file_ready(data_ready),.file_done(file_done),.file_cancel(cancel),
 .command_valid(command_valid),.command_ready(command_ready),.command_type(command_type),.command_length(command_length),.payload_addr(payload_addr),.payload_data(payload_data),
 .command_done(command_done),.command_code(command_code),.run_phase(run_phase));
 reg [34:0] physical=0;
 reg ble_frame=0;wire ble_frame_ready;wire [7:0] ble_payload_addr;
 wire [7:0] ble_payload=64'h00e5000012340101 >> (ble_payload_addr*8);
 wire [34:0] guide,yellow,green;wire due,armed;
 hallpad_protocol_ctrl #(.SESSION_TIMEOUT_MS(50),.PRACTICE_SUPPORTED(1),.KEY_NOTE_MAP({6'd1,6'd2,6'd3,6'd4,6'd5,6'd6,6'd7,6'd8,6'd9,6'd10,6'd11,6'd12,6'd13,6'd14,6'd15,6'd16,6'd17,6'd18,6'd19,6'd20,6'd21,6'd22,6'd23,6'd24,6'd25,6'd26,6'd27,6'd28,6'd29,6'd30,6'd31,6'd32,6'd33,6'd34,6'd35})) protocol(
 .clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.uptime_ms(uptime_ms),.cycle_counter(32'd0),
 .offline_active(active),.offline_command_valid(command_valid),.offline_command_ready(command_ready),.offline_command_type(command_type),.offline_command_length(command_length),
 .offline_payload_addr(payload_addr),.offline_payload_data(payload_data),.offline_command_done(command_done),.offline_command_code(command_code),.offline_run_phase(run_phase),
 .frame_valid(ble_frame),.frame_ready(ble_frame_ready),.version(8'd1),.message_type(8'd1),.flags(8'd1),.length(8'd8),.frame_seq(16'd1),.session_id(32'd0),.payload_addr(ble_payload_addr),.payload_data(ble_payload),.transport_pause(1'b0),.drum_edit_valid(1'b0),.drum_hit_valid(1'b0),.adc_valid(1'b0),.config_data(64'd0),.config_revision(32'd0),
 .parameter_ready(1'b1),.parameter_done(1'b0),.parameter_error(1'b0),.remote_allowed(1'b1),.physical_key_mask(physical),
 .practice_guide_due(due),.practice_guide_armed(armed),.practice_guide_mask(guide),.practice_yellow(yellow),.practice_green(green),.response_done(1'b1),.response_ready(1'b1));
 `include "sd_fixture_map.svh"
 reg [7:0] bytes[0:8191];integer page=0,address=0;reg busy=0,finish_pending=0;
 initial $readmemh("verification/sd_fixture.hex",bytes);
 always @(posedge clk)begin
  read_valid<=0;block_done<=0;
  if(block_request && block_ready)begin
   page=page_for(block_lba);if(page<0)$fatal(1,"unexpected LBA %d",block_lba);
   busy<=1;block_ready<=0;address=0;
  end else if(busy)begin
   read_valid<=1;read_address<=9'(address);read_byte<=bytes[page*512+address];
   if(address==511)begin busy<=0;finish_pending<=1;end else address=address+1;
  end else if(finish_pending)begin block_done<=1;block_ready<=1;finish_pending<=0;end
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task short;begin @(negedge clk);short_press=1;cycles(1);short_press=0;cycles(4);end endtask
 task back;begin @(negedge clk);long_press=1;cycles(1);long_press=0;cycles(20);end endtask
 task ticks(input integer n);repeat(n)begin @(posedge ms_tick);@(negedge ms_tick);end endtask
 initial begin
  cycles(3);rst_n=1;wait(mounted || failed);cycles(3);
  if(failed || song_count!=3 || song_name!="SCALE   ")$fatal(1,"catalog failure %h count%d name%h",error_code,song_count,song_name);
  $display("catalog ready t=%t",$time);enter=1;cycles(1);enter=0;cycles(5);short();
  wait(ui_state==3 || ui_state==7);cycles(5);
  if(ui_state!=3)$fatal(1,"load failed %h cmd%h ctrl%d",ui_error,command_type,ctrl.state);
  $display("loaded t=%t",$time);short();wait(run_phase==1);wait(guide!=0 && due && armed);cycles(5);
  if(protocol.session_valid || guide!=(35'd1<<20))$fatal(1,"offline guide without BLE");
  $display("running t=%t",$time);wait(ble_frame_ready);ble_frame=1;cycles(1);ble_frame=0;wait(protocol.session_valid);ticks(60);
  if(protocol.session_valid || run_phase!=1 || guide!=(35'd1<<20))$fatal(1,"BLE disconnect stopped local practice");
  physical=guide;cycles(5);physical=0;ticks(3);
  wait(guide==(35'd1<<19) && due && armed);cycles(3);physical=guide;ticks(20);
  if((green & (35'd1<<19))!=0 || (yellow & (35'd1<<19))==0)$fatal(1,"long note green=%h yellow=%h",green,yellow);
  physical=0;wait(guide==(35'd1<<18));cycles(5);
  $display("early-release advanced t=%t",$time);short();wait(ui_state==5 && run_phase==2);cycles(20);$display("paused t=%t",$time);short();wait(ui_state==4 && run_phase==1);cycles(20);$display("resumed t=%t",$time);back();wait(ui_state==1);cycles(20);$display("back list t=%t",$time);
  step_valid=1;cycles(1);step_valid=0;cycles(4);$display("loading error fixture selection=%d t=%t",selection,$time);short();wait(ui_state==7);if(ui_error==0)$fatal(1,"bad CRC accepted");
  back();step_valid=1;cycles(1);step_valid=0;cycles(4);$display("loading error fixture selection=%d t=%t",selection,$time);short();wait(ui_state==7);if(ui_error!=8)$fatal(1,"bad binding accepted %h",ui_error);
  back();back();if(active)$fatal(1,"local page did not exit");
  $display("PASS: FAT32 MBR, fragmented root/file, shared RAM load/CRC/binding, standalone LED follow/early release/pause/resume/stop, no BLE session");$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog state%d ui%d err%h cat%d cmd%h",ctrl.state,ui_state,ui_error,catalog.state,command_type);end
endmodule
