`timescale 1ns/1ps
module tb_v8_render;
reg clk=0;always #10 clk=~clk;
reg rst=0,offline=0;reg[7:0]ui=1;reg[1:0]screen=0;reg playing=0;reg[4:0]selected=10;
wire[3:0]title_index;wire[4:0]title_row,title_column;reg title_ink=0;reg[7:0]glyph_bytes[0:1071];integer address=0;
initial $readmemh("verification/ui_title.hex",glyph_bytes);
always @(posedge clk)begin
address=16+glyph_bytes[title_index]*66+title_row*3+title_column/8;
if(title_row<22 && title_column<22)title_ink<=1'((glyph_bytes[address]>>(7-title_column%8))&1);else title_ink<=0;
end
wire pv,done;wire[15:0]pixel;integer fd,count=0;
keyboard_menu_renderer #(.ENABLE_PRACTICE(1)) dut(.clk(clk),.rst_n(rst),.init_done(1'b1),.practice_screen(screen),.practice_countdown(2'd0),.drum_config(128'd0),.drum_online(2'd0),.drum_calibrated(2'd0),.drum_cal_state(8'd0),.drum_bus_info(32'd0),.drum_bus_error(16'd0),.drum_inserted(2'd0),.song_selection(5'd0),.song_count(6'd32),.title_revision(8'd1),.title_pending(1'b0),.ascii_title_valid(1'b0),.ascii_title(128'd0),.playback_mode(playing),.bundle_choosing(ui>=8),.bundle_text("TRK00002"),.bundle_skipped(32'd0),.title_valid(1'b1),.title_count(5'd16),.title_index(title_index),.title_row(title_row),.title_column(title_column),.title_ink(title_ink),.offline_active(offline),.offline_state(ui),.offline_error(8'd0),.offline_name("SCALE   "),.offline_result_text({"0       ","1       ","63      ","98      "}),.main_view(3'd2),.menu_level(1'b0),.scope_valid(1'b0),.spectrum_valid(1'b0),.scope_frame(8'd0),.spectrum_frame(8'd0),.scope_y(8'd0),.spectrum_height(8'd0),.selected(selected),.editing(1'b0),.volume_percent(7'd65),.echo_percent(7'd0),.joy_percent(7'd50),.light_brightness(6'd31),.timbre_sel(4'd1),.light_mode(2'd0),.audio_input_mask(2'd1),.language_cn(1'b1),.metro_enable(1'b0),.metro_beats(4'd4),.metro_unit(4'd4),.metro_bpm(8'd120),.draw_ready(1'b1),.pixel_valid(pv),.pixel_rgb565(pixel),.pixel_ready(1'b1),.draw_done(done));
assign done=dut.state==9;
always @(negedge clk)if(rst && pv)begin $fdisplay(fd,"%0d %0d %0d",dut.px,dut.py,pixel);count=count+1;end
 task frame(input[7:0]next_ui,input[1:0]next_screen,input string name);
 begin
  wait(dut.state==0);@(negedge clk);ui=next_ui;screen=next_screen;count=0;fd=$fopen({"verification/v8_",name,"_pixels.txt"},"w");
  wait(dut.state!=0);wait(done);@(negedge clk);$fclose(fd);
  if(count!=39936)$fatal(1,"incomplete frame %s %d",name,count);
  repeat(3)@(negedge clk);
 end endtask
 initial begin
 fd=$fopen("verification/v8_root_pixels.txt","w");repeat(3)@(negedge clk);rst=1;
 wait(done);@(negedge clk);$fclose(fd);repeat(3)@(negedge clk);offline=1;
 frame(1,0,"list");frame(8,0,"track");frame(9,0,"mode");frame(10,0,"notice");
 frame(3,0,"ready");frame(4,2,"run");frame(5,3,"pause");frame(6,0,"result");frame(7,0,"error");
 $display("PASS actual renderer: root Chinese entry and nine offline stages, full 39936-pixel frames, 16-character embedded title");$finish;
 end
 initial begin #100000000;$fatal(1,"render timeout");end
endmodule
