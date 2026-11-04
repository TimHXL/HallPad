`timescale 1ns/1ps
module tb_drum_protocol;
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
 wire [47:0] drum_light_config;wire [31:0] drum_color_config;wire [71:0] drum_effect_config;wire drum_effect_active;
 reg drum_cal_ready=1;
 reg [95:0] drum_cal_status=96'h123402010304807f02030303;
 hallpad_protocol_ctrl #(.SESSION_TIMEOUT_MS(1000000)) dut(.clk(clk),.rst_n(rst_n),.ms_tick(1'b1),
 .extended_config(extended_config),.drum_cal_status(drum_cal_status),.drum_cal_ready(drum_cal_ready),.drum_cal_request(drum_cal_request),.drum_light_config(drum_light_config),.drum_color_config(drum_color_config),.drum_effect_config(drum_effect_config),.drum_effect_active(drum_effect_active),.offline_active(1'b0),.offline_command_valid(1'b0),
 .frame_valid(frame_valid),.frame_ready(frame_ready),.version(8'd1),.message_type(message_type),.flags(flags),.length(length),
 .frame_seq(frame_seq),.session_id(session_id),.payload_addr(payload_addr),.payload_data(payload_data),
 .response_valid(response_valid),.response_ready(1'b1),.response_type(response_type),.response_length(response_length),
 .response_addr(response_addr),.response_data(response_data),.response_done(response_done),
 .transport_pause(1'b0),.config_data(64'd0),.config_revision(32'd0),.session_valid(session_valid),.current_session(current_session),
 .drum_edit_valid(1'b0),.drum_hit_valid(1'b0),.adc_valid(1'b0),.parameter_ready(1'b1),.parameter_done(1'b0),.parameter_error(1'b0),
 .state_flags(32'd0),.error_bits(32'd0),.uptime_ms(32'd0),.cycle_counter(32'h12345678));
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
  payload[0]=1;payload[1]=100;payload[2]=8'h88;payload[3]=8'h13;payload[4]=8'hb0;payload[5]=4;payload[6]=255;payload[7]=0;payload[8]=0;
  send('h83,9,1);ack(0);if(!drum_effect_active || drum_effect_config!=72'h0000ff04b013886401)$fatal(1,"effect config");
  payload[0]=3;send('h83,9,1);ack(3);if(drum_effect_config[7:0]!=1)$fatal(1,"invalid effect modified");
  payload[0]=0;payload[1]=101;send('h83,9,1);ack(3);
  payload[1]=100;payload[2]=0;payload[3]=0;send('h83,9,1);ack(3);
  send('h83,8,1);ack(2);
  send('h84,0,1);if(response_type!='h85 || response_length!=9)$fatal(1,"effect query");
  for(i=0;i<9;i=i+1)begin response_addr=8'(i);cycles(2);if(response_data!=drum_effect_config[i*8+:8])$fatal(1,"effect readback");end finish();
  payload[0]=1;payload[1]=0;payload[2]=0;payload[3]=0;send('h7d,4,1);ack(0);if(drum_effect_active)$fatal(1,"legacy selection");
  send('h06,0,1);response_addr=8;cycles(2);if(!response_data[1])$fatal(1,"mode capability bit25");finish();
  $display("PASS: HELLO, calibration request/cache dedup/busy/invalid mask/status, light set/validation/readback, RGB and 80-mode set/validation/readback/legacy/capability");$finish;
 end
 initial begin #2000000;$fatal(1,"protocol watchdog");end
endmodule
