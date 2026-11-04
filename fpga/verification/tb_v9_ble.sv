`timescale 1ns/1ps
module tb_v9_ble;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,fv=0,done=0;reg [7:0] kind=0,len=0,flags=1,addr=0;reg[15:0]seq=0;reg[31:0]sid=0,uptime=0;
 reg [7:0] mem[0:228];wire[7:0]pa;wire fr,rv,sv,remote_valid;wire[31:0]session;wire[7:0]rt,rl,rd;reg [7:0] capture[0:63];integer div=0;
 always @(posedge clk)if(div==99)begin div<=0;uptime<=uptime+1;end else div<=div+1;
 hallpad_protocol_ctrl #(.PRACTICE_SUPPORTED(1),.SESSION_TIMEOUT_MS(50)) dut(.clk(clk),.rst_n(rst_n),.ms_tick(div==99),.uptime_ms(uptime),.cycle_counter(32'h12345678),
 .frame_valid(fv),.frame_ready(fr),.version(8'd1),.message_type(kind),.flags(flags),.length(len),.frame_seq(seq),.session_id(sid),.payload_addr(pa),.payload_data(mem[pa]),
 .response_valid(rv),.response_ready(1'b1),.response_done(done),.response_type(rt),.response_length(rl),.response_addr(addr),.response_data(rd),
 .session_valid(sv),.current_session(session),.offline_busy(1'b1),.offline_playback_owner(1'b1),.offline_active(1'b1),.offline_auto_play(1'b1),.offline_command_valid(1'b0),.offline_mapping_active(1'b0),
 .physical_key_mask(35'd0),.remote_key_mask(36'h123),.voice_active(36'h123),.remote_allowed(1'b1),.remote_ready(1'b0),.remote_valid(remote_valid),
 .transport_pause(1'b0),.adc_valid(1'b0),.drum_edit_valid(1'b0),.drum_hit_valid(1'b0),.config_data(64'd0),.config_revision(32'd0),
 .state_flags(32'd0),.error_bits(32'd0),.parameter_ready(1'b1),.parameter_done(1'b0),.parameter_error(1'b0),.sd_bridge_allowed(1'b0));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task send(input[7:0]k,input integer n,input[7:0]f);begin wait(fr);@(negedge clk);$display("send %h seq%d ms%d",k,seq,uptime);seq=seq+1;kind=k;len=n;flags=f;fv=1;cycles(1);fv=0;end endtask
 task response(input[7:0]expected);integer j;begin wait(rv);$display("reply %h seq%d ms%d",rt,seq,uptime);if(rt!=expected)$fatal(1,"reply type %h expected %h",rt,expected);for(j=0;j<rl;j=j+1)begin addr=j;cycles(3);capture[j]=rd;end done=1;cycles(1);done=0;cycles(2);end endtask
 integer i;
 always @(posedge clk)if(rst_n && remote_valid)$fatal(1,"BLE frame touched exclusive playback note port");
 initial begin
 for(i=0;i<229;i=i+1)mem[i]=0;cycles(3);rst_n=1;
 mem[0]=1;mem[1]=1;mem[2]=8'h34;mem[3]=8'h12;mem[6]=229;send(1,8,1);response(1);sid=session;
 for(i=0;i<229;i=i+1)mem[i]=0;
 // This is the previous deadlock: remote_ready stays low for whole playback.
 for(i=0;i<60;i=i+1)begin
 mem[0]=i;mem[1]=0;send('h13,45,0);cycles(500);if(!fr)$fatal(1,"empty snapshot blocked heartbeat at %d state %d req %h target %h",i,dut.state,dut.req_type,dut.remote_target_mask);
 mem[0]=0;send(2,4,1);response(2);if(!sv)$fatal(1,"session dropped during playback");
 end
 // Reliable release and competing note both return promptly.
 mem[0]=0;send('h11,1,1);response(3);if(capture[1]!=0)$fatal(1,"release failed");
 mem[0]=3;mem[1]=1;mem[2]=100;send('h10,3,1);response(3);if(capture[1]!=5)$fatal(1,"competing note not rejected");
 send(4,0,1);response(5);send(6,0,1);response(7);
 // New phone connection during playback also responds; local run owns score session.
 sid=0;mem[0]=1;mem[1]=1;mem[2]=8'h99;mem[3]=8'h35;mem[6]=229;send(1,8,1);response(1);
 $display("PASS BLE during offline playback: HELLO/reconnect, 60 snapshots + heartbeats, status/caps, release ACK, conflicting note rejection; remote_ready=0 throughout");$finish;
 end
 initial begin #20000000;$fatal(1,"BLE watchdog state %d",dut.state);end
endmodule
