`timescale 1ns/1ps
module tb_v9_mapping;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,fv=0,done=0,mapping=0,busy=0;reg[7:0]kind=0,len=0,addr=0;reg[15:0]seq=0;reg[31:0]sid=0;reg[7:0]mem[0:228];wire[7:0]pa;wire fr,rv,sv;wire[31:0]session;wire[7:0]rt,rl,rd;reg[7:0]cap[0:63];wire[31:0]rev;
 hallpad_protocol_ctrl #(.KEY_NOTE_MAP(210'd15 << 120),.PRACTICE_SUPPORTED(1),.SESSION_TIMEOUT_MS(1000000)) d(.clk(clk),.rst_n(rst),.ms_tick(1'b1),.uptime_ms(32'd0),.cycle_counter(32'h12345678),
 .frame_valid(fv),.frame_ready(fr),.version(8'd1),.message_type(kind),.flags(8'd1),.length(len),.frame_seq(seq),.session_id(sid),.payload_addr(pa),.payload_data(mem[pa]),
 .response_valid(rv),.response_ready(1'b1),.response_done(done),.response_type(rt),.response_length(rl),.response_addr(addr),.response_data(rd),.session_valid(sv),.current_session(session),
 .offline_active(1'b1),.offline_busy(busy),.offline_playback_owner(1'b0),.offline_auto_play(1'b0),.offline_command_valid(1'b0),.offline_mapping_active(mapping),
 .offline_key_enabled({35{1'b1}}),.offline_key_midi({35{7'd61}}),.offline_fixed_mode({35{1'b1}}),.offline_fixed_velocity({35{7'd80}}),.offline_key_timbre({35{4'd3}}),
 .physical_key_mask(35'd0),.remote_key_mask(36'd0),.voice_active(36'd0),.remote_allowed(1'b1),.remote_ready(1'b1),.transport_pause(1'b0),.adc_valid(1'b0),.drum_edit_valid(1'b0),.drum_hit_valid(1'b0),.config_data(64'd0),.config_revision(32'd0),.state_flags(32'd0),.error_bits(32'd0),.parameter_ready(1'b1),.parameter_done(1'b0),.parameter_error(1'b0),.sd_bridge_allowed(1'b0));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task send(input[7:0]k,input integer n);begin wait(fr);@(negedge clk);seq=seq+1;kind=k;len=n;fv=1;cycles(1);fv=0;end endtask
 task response(input[7:0]t);integer j;begin wait(rv);if(rt!=t)$fatal(1,"reply %h expected %h",rt,t);for(j=0;j<rl;j=j+1)begin addr=j;cycles(3);cap[j]=rd;end done=1;cycles(1);done=0;cycles(3);end endtask
 task getkey(input integer expected);begin mem[0]=20;mem[1]=1;send('h24,2);response('h25);if(cap[7]!=expected)$fatal(1,"key read %d expected %d",cap[7],expected);end endtask
 integer i;reg[31:0] before_rev;
 task setkey;begin for(i=0;i<15;i=i+1)mem[i]=0;for(i=0;i<4;i=i+1)mem[i]=255;mem[6]=16;mem[12]=2;mem[14]=65;send('h23,15);response(3);end endtask
 initial begin for(i=0;i<229;i=i+1)mem[i]=0;cycles(3);rst=1;mem[0]=1;mem[1]=1;mem[2]=1;mem[6]=229;send(1,8);response(1);sid=session;
 getkey(60);before_rev=d.effective_revision;
 mapping=1;cycles(10);getkey(61);if(cap[8]!=3 || cap[10]!=1 || cap[11]!=80 || d.effective_revision==before_rev)$fatal(1,"temporary full-map/revision sync");
 send(4,0);response(5);if(!cap[9][6])$fatal(1,"temporary map flag missing");
 setkey();if(cap[1]!=5)$fatal(1,"active mapping write accepted");mapping=0;cycles(120);getkey(60);
 setkey();if(cap[1]!=0)$fatal(1,"browsing local menu rejected key settings");getkey(65);
 send('h60,0);response('h60); // capability query must work even with local UI open
 $display("PASS local-menu settings; temporary full-map MIDI/timbre/fixed/velocity GET_KEYS, status flag + revision, restore readback, protected active map, practice caps query");$finish;end
 initial begin #20000000;$fatal(1,"mapping watchdog state%d",d.state);end
endmodule
