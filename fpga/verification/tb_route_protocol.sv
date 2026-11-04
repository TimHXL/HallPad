`timescale 1ns/1ps
module tb_route_protocol;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,frame_valid=0,response_done=0;
 reg [7:0] message_type=0,flags=1,length=0,response_addr=0;
 reg [15:0] frame_seq=0;
 reg [31:0] session_id=0;
 reg [7:0] payload[0:228];
 wire [7:0] payload_addr,payload_data=payload[payload_addr];
 wire frame_ready,response_valid,drum_cal_request,session_valid;
 wire [31:0] current_session;
 wire [7:0] response_type,response_data,response_length;
 wire [255:0] extended_config;
 wire [47:0] drum_light_config;wire [31:0] drum_color_config;wire [87:0] drum_effect_config;wire drum_effect_active;
 reg drum_cal_ready=1;
 reg [95:0] drum_cal_status=96'h123402010304807f02030303;
 hallpad_protocol_ctrl #(.SESSION_TIMEOUT_MS(1000000)) dut(.clk(clk),.rst_n(rst_n),.ms_tick(1'b1),
 .extended_config(extended_config),.drum_cal_status(drum_cal_status),.drum_cal_ready(drum_cal_ready),.drum_cal_request(drum_cal_request),.drum_light_config(drum_light_config),.drum_color_config(drum_color_config),.drum_effect_config(drum_effect_config),.drum_effect_active(drum_effect_active),.key_enabled(ken),.key_fixed_mode(kfixed),.key_midi(kmidi),.key_fixed_velocity(kvelocity),.key_timbre(ktimbre),.physical_key_mask(physical),.remote_key_mask(36'd0),.voice_active(36'd0),.offline_active(local_owner),.offline_command_valid(1'b0),
 .frame_valid(frame_valid),.frame_ready(frame_ready),.version(8'd1),.message_type(message_type),.flags(flags),.length(length),
 .frame_seq(frame_seq),.session_id(session_id),.payload_addr(payload_addr),.payload_data(payload_data),
 .response_valid(response_valid),.response_ready(1'b1),.response_type(response_type),.response_length(response_length),
 .response_addr(response_addr),.response_data(response_data),.response_done(response_done),
 .transport_pause(1'b0),.config_data(64'd0),.config_revision(32'd0),.session_valid(session_valid),.current_session(current_session),
 .drum_edit_valid(1'b0),.drum_hit_valid(1'b0),.adc_valid(1'b0),.parameter_ready(1'b1),.parameter_done(1'b0),.parameter_error(1'b0),
 .state_flags(32'd0),.error_bits(32'd0),.uptime_ms(32'd0),.cycle_counter(32'h12345678));
 wire [255:0] ref_extended_config;
 wire [0:0] ref_drum_cal_request;
 wire [47:0] ref_drum_light_config;
 wire [31:0] ref_drum_color_config;
 wire [87:0] ref_drum_effect_config;
 wire [0:0] ref_drum_effect_active;
 wire [0:0] ref_frame_ready;
 wire [0:0] ref_response_valid;
 wire [7:0] ref_response_type;
 wire [7:0] ref_response_length;
 wire [7:0] ref_response_data;
 wire [0:0] ref_session_valid;
 wire [31:0] ref_current_session;
 wire [7:0] ref_payload_addr;
 wire [35:0] ref_ken;
 wire [35:0] ref_kfixed;
 wire [251:0] ref_kmidi;
 wire [251:0] ref_kvelocity;
 wire [143:0] ref_ktimbre;
 hallpad_protocol_ctrl_reference #(.SESSION_TIMEOUT_MS(1000000)) refdut(.clk(clk),.rst_n(rst_n),.ms_tick(1'b1),
 .extended_config(ref_extended_config),.drum_cal_status(drum_cal_status),.drum_cal_ready(drum_cal_ready),.drum_cal_request(ref_drum_cal_request),.drum_light_config(ref_drum_light_config),.drum_color_config(ref_drum_color_config),.drum_effect_config(ref_drum_effect_config),.drum_effect_active(ref_drum_effect_active),.key_enabled(ref_ken),.key_fixed_mode(ref_kfixed),.key_midi(ref_kmidi),.key_fixed_velocity(ref_kvelocity),.key_timbre(ref_ktimbre),.physical_key_mask(physical),.remote_key_mask(36'd0),.voice_active(36'd0),.offline_active(local_owner),.offline_command_valid(1'b0),
 .frame_valid(frame_valid),.frame_ready(ref_frame_ready),.version(8'd1),.message_type(message_type),.flags(flags),.length(length),
 .frame_seq(frame_seq),.session_id(session_id),.payload_addr(ref_payload_addr),.payload_data(payload[ref_payload_addr]),
 .response_valid(ref_response_valid),.response_ready(1'b1),.response_type(ref_response_type),.response_length(ref_response_length),
 .response_addr(response_addr),.response_data(ref_response_data),.response_done(response_done),
 .transport_pause(1'b0),.config_data(64'd0),.config_revision(32'd0),.session_valid(ref_session_valid),.current_session(ref_current_session),
 .drum_edit_valid(1'b0),.drum_hit_valid(1'b0),.adc_valid(1'b0),.parameter_ready(1'b1),.parameter_done(1'b0),.parameter_error(1'b0),
 .state_flags(32'd0),.error_bits(32'd0),.uptime_ms(32'd0),.cycle_counter(32'h12345678));
 always @(negedge clk)if(rst_n)begin
 if(dut.key_revision!==refdut.key_revision)$fatal(1,"key revision mismatch");
 if(extended_config!==ref_extended_config)$fatal(1,"protocol mismatch extended_config");
 if(drum_cal_request!==ref_drum_cal_request)$fatal(1,"protocol mismatch drum_cal_request");
 if(drum_light_config!==ref_drum_light_config)$fatal(1,"protocol mismatch drum_light_config");
 if(drum_color_config!==ref_drum_color_config)$fatal(1,"protocol mismatch drum_color_config");
 if(drum_effect_config!==ref_drum_effect_config)$fatal(1,"protocol mismatch drum_effect_config");
 if(drum_effect_active!==ref_drum_effect_active)$fatal(1,"protocol mismatch drum_effect_active");
 if(frame_ready!==ref_frame_ready)$fatal(1,"protocol mismatch frame_ready");
 if(response_valid!==ref_response_valid)$fatal(1,"protocol mismatch response_valid");
 if(response_type!==ref_response_type)$fatal(1,"protocol mismatch response_type");
 if(response_length!==ref_response_length)$fatal(1,"protocol mismatch response_length");
 if(response_data!==ref_response_data)$fatal(1,"protocol mismatch response_data");
 if(session_valid!==ref_session_valid)$fatal(1,"protocol mismatch session_valid");
 if(current_session!==ref_current_session)$fatal(1,"protocol mismatch current_session");
 if(payload_addr!==ref_payload_addr)$fatal(1,"protocol mismatch payload_addr");
 if(ken!==ref_ken)$fatal(1,"protocol mismatch ken");
 if(kfixed!==ref_kfixed)$fatal(1,"protocol mismatch kfixed");
 if(kmidi!==ref_kmidi)$fatal(1,"protocol mismatch kmidi");
 if(kvelocity!==ref_kvelocity)$fatal(1,"protocol mismatch kvelocity");
 if(ktimbre!==ref_ktimbre)$fatal(1,"protocol mismatch ktimbre");
 end

 wire [35:0] ken,kfixed;wire [251:0] kmidi,kvelocity;wire [143:0] ktimbre;
 reg [34:0] physical=0;reg local_owner=0;
 integer requests=0;
 always @(posedge clk)if(drum_cal_request)requests<=requests+1;
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task send(input [7:0] kind,input [7:0] n,input bit newseq);
 begin
  cycles(110);while(!frame_ready)cycles(1);
  if(newseq)frame_seq=frame_seq+1'b1;
  message_type=kind;length=n;frame_valid=1;cycles(1);frame_valid=0;
  while(!response_valid)cycles(1);
 end endtask
 task finish;begin response_done=1;cycles(1);response_done=0;cycles(3);end endtask
 task ack(input [7:0] code);
 begin if(response_type!=3)$fatal(1,"expected ACK got %h",response_type);
  response_addr=1;cycles(2);if(response_data!=code)$fatal(1,"ACK code got %h expected %h",response_data,code);finish();end endtask
 integer i;
 initial begin
  for(i=0;i<229;i=i+1)payload[i]=0;
  cycles(2);rst_n=1;cycles(3);
  if(extended_config[127:96]!=400)$fatal(1,"default sound release is not 400ms");
  payload[0]=1;payload[1]=1;payload[2]=8'h42;payload[6]=229;
  send(1,8,1);if(response_type!=1)$fatal(1,"HELLO failed type=%h hdr=%h ack=%d len=%d session=%h",response_type,dut.req_header,dut.ack_code,dut.req_length,session_id);finish();session_id=current_session;

  for(i=0;i<229;i=i+1)payload[i]=0;
  payload[0]=255;payload[1]=255;payload[2]=255;payload[3]=255;
  payload[4]=255;payload[5]=255;payload[6]=255;payload[7]=255;payload[8]=15;
  payload[12]=31;payload[14]=1;payload[15]=72;payload[16]=14;payload[18]=1;payload[19]=127;
  send('h23,20,1);ack(0);
  if(ken!={36{1'b1}} || kfixed!={36{1'b1}})$fatal(1,"key flags");
  for(i=0;i<36;i=i+1)if(kmidi[i*7+:7]!=72 || ktimbre[i*4+:4]!=14 || kvelocity[i*7+:7]!=127)$fatal(1,"key fields %d",i);
  send('h23,20,0);ack(0);
  payload[0]=0;payload[1]=16;send('h24,2,1);if(response_type!='h25 || response_length!=166)$fatal(1,"key GET");
  for(i=0;i<166;i=i+1)begin response_addr=8'(i);cycles(2);end finish();
  payload[0]=255;payload[1]=255;
  payload[4]=0;payload[5]=0;payload[6]=0;payload[7]=0;payload[8]=8;
  payload[12]=1;payload[14]=0;send('h23,15,1);ack(0);if(ken[35] || !ken[34])$fatal(1,"hidden key mask");
  payload[4]=16;payload[8]=0;physical=35'd16;send('h23,15,1);ack(4);if(!ken[4])$fatal(1,"busy modified key");physical=0;
  payload[12]=16;payload[14]=0;send('h23,15,1);ack(3);
  local_owner=1;payload[12]=1;send('h23,15,1);ack(5);local_owner=0;

  payload[0]=3;send('h77,1,1);ack(0);if(requests!=1)$fatal(1,"calibration not issued");
  send('h77,1,0);ack(0);if(requests!=1)$fatal(1,"duplicate restarted calibration");
  drum_cal_ready=0;send('h77,1,1);ack(5);if(requests!=1)$fatal(1,"busy request issued");drum_cal_ready=1;
  payload[0]=1;send('h77,1,1);ack(3);
  send('h78,0,1);if(response_type!='h79 || response_length!=12)$fatal(1,"cal query header");
  for(i=0;i<12;i=i+1)begin response_addr=8'(i);cycles(2);if(response_data!=drum_cal_status[i*8+:8])$fatal(1,"cal query byte %d",i);end finish();
  payload[0]=1;payload[1]=100;payload[2]=1;payload[3]=0;payload[4]=0;payload[5]=0;
  send('h7a,6,1);ack(0);if(drum_light_config!=48'h000000016401)$fatal(1,"light config");
  payload[1]=101;send('h7a,6,1);ack(3);if(drum_light_config!=48'h000000016401)$fatal(1,"invalid config changed state");
  send('h7b,0,1);if(response_type!='h7c || response_length!=6)$fatal(1,"light query header");
  for(i=0;i<6;i=i+1)begin response_addr=8'(i);cycles(2);if(response_data!=drum_light_config[i*8+:8])$fatal(1,"light byte %d",i);end finish();
  payload[0]=1;payload[1]=255;payload[2]=0;payload[3]=0;
  send('h7d,4,1);ack(0);if(drum_color_config!=32'h0000ff01)$fatal(1,"RGB set");
  payload[0]=2;send('h7d,4,1);ack(3);if(drum_color_config!=32'h0000ff01)$fatal(1,"invalid RGB mode committed");
  send('h7d,3,1);ack(2);
  send('h7e,0,1);if(response_type!='h7f || response_length!=4)$fatal(1,"RGB query header");
  for(i=0;i<4;i=i+1)begin response_addr=8'(i);cycles(2);if(response_data!=drum_color_config[i*8+:8])$fatal(1,"RGB byte order");end finish();
  send('h06,0,1);if(response_type!='h07)$fatal(1,"CAPS type");response_addr=8;cycles(2);
  if(!response_data[0])$fatal(1,"RGB capability missing");finish();
  if(drum_effect_config[47:16]!=80000)$fatal(1,"default speed");
  payload[0]=0;payload[1]=100;payload[6]=8'hb0;payload[7]=4;payload[8]=255;payload[9]=0;payload[10]=0;
  for(i=40000;i<=200000;i=i+20000)begin
   {payload[5],payload[4],payload[3],payload[2]}=32'(i);
   send('h83,11,1);ack(0);if(drum_effect_config[47:16]!=i)$fatal(1,"speed set");
  end
  {payload[5],payload[4],payload[3],payload[2]}=32'd39999;send('h83,11,1);ack(3);
  {payload[5],payload[4],payload[3],payload[2]}=32'd200001;send('h83,11,1);ack(3);
  send('h84,0,1);if(response_type!='h85 || response_length!=11)$fatal(1,"effect query");
  for(i=0;i<11;i=i+1)begin response_addr=8'(i);cycles(2);if(response_data!=drum_effect_config[i*8+:8])$fatal(1,"effect readback");end finish();
  payload[2]=8'h40;payload[3]=8'h9c;payload[4]=8'hb0;payload[5]=4;payload[6]=255;payload[7]=0;payload[8]=0;
  send('h83,9,1);ack(0);if(drum_effect_config[47:16]!=40000 || drum_effect_config[63:48]!=1200)$fatal(1,"legacy conversion");
  payload[0]=1;payload[1]=0;payload[2]=0;payload[3]=0;send('h7d,4,1);ack(0);if(drum_effect_active)$fatal(1,"legacy selection");
  send('h06,0,1);response_addr=8;cycles(2);if(!response_data[1] || !response_data[2])$fatal(1,"mode/u32 capability bits25/26");finish();
  $display("PASS: HELLO, calibration request/cache dedup/busy/invalid mask/status, light set/validation/readback, RGB and 80-mode set/validation/readback/legacy/capability");$finish;
 end
 initial begin #10000000;$fatal(1,"protocol watchdog");end
endmodule
