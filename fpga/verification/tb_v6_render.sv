`timescale 1ns/1ps
module tb_v6_render;
reg clk=0;always #10 clk=~clk;
reg rst=0,offline=0;wire pv,done;wire[15:0]pixel;integer fd,count=0;
keyboard_menu_renderer dut(.clk(clk),.rst_n(rst),.init_done(1'b1),.practice_screen(2'd0),.practice_countdown(2'd0),.drum_config(128'd0),.drum_online(2'd0),.drum_calibrated(2'd0),.drum_cal_state(8'd0),.drum_bus_info(32'd0),.drum_bus_error(16'd0),.drum_inserted(2'd0),.offline_active(offline),.offline_state(8'd6),.offline_error(8'd0),.offline_name("SCALE   "),.offline_result_text({"0       ","1       ","63      ","98      "}),.main_view(2'd2),.menu_level(1'b0),.scope_valid(1'b0),.spectrum_valid(1'b0),.scope_frame(8'd0),.spectrum_frame(8'd0),.scope_y(8'd0),.spectrum_height(8'd0),.selected(5'd0),.editing(1'b0),.volume_percent(7'd65),.echo_percent(7'd0),.joy_percent(7'd50),.light_brightness(6'd31),.timbre_sel(4'd1),.light_mode(2'd0),.audio_input_mask(2'd1),.language_cn(1'b1),.metro_enable(1'b0),.metro_beats(4'd4),.metro_unit(4'd4),.metro_bpm(8'd120),.draw_ready(1'b1),.pixel_valid(pv),.pixel_rgb565(pixel),.pixel_ready(1'b1),.draw_done(done));
assign done=dut.state==9;
always @(negedge clk)if(rst && pv)begin $fdisplay(fd,"%0d %0d %0d",dut.px,dut.py,pixel);count=count+1;end
initial begin
fd=$fopen("verification/render_cn_pixels.txt","w");repeat(3)@(negedge clk);rst=1;
wait(done);@(negedge clk);$fclose(fd);if(count!=39936)$fatal(1,"frame incomplete %d",count);
@(negedge clk);offline=1;count=0;fd=$fopen("verification/render_result_pixels.txt","w");
wait(dut.state!=0);wait(done);@(negedge clk);$fclose(fd);
if(count!=39936 || dut.row_label[1]!="CORRECT " || dut.row_value[0]!="98      " || dut.row_value_start[0]!=174)$fatal(1,"result layout");
$display("PASS 22x22 CN and result full frames; compact decimal text, right edge positions");$finish;
end
initial begin #30000000;$fatal(1,"watchdog");end
endmodule
