`timescale 1ns/1ps
module tb_menu_pipeline;
reg  clk=0;
reg  rst_n=0;
reg  init_done=0;
reg [1:0] practice_screen=0;
reg [1:0] practice_countdown=0;
reg [127:0] drum_config=0;
reg [1:0] drum_online=0;
reg [1:0] drum_calibrated=0;
reg [7:0] drum_cal_state=0;
reg [31:0] drum_bus_info=0;
reg [15:0] drum_bus_error=0;
reg [1:0] drum_inserted=0;
reg  offline_active=0;
reg [7:0] offline_state=0;
reg [7:0] offline_error=0;
reg [63:0] offline_name=0;
reg [1:0] main_view=0;
reg  menu_level=0;
reg  scope_valid=0;
reg  spectrum_valid=0;
reg [7:0] scope_frame=0;
reg [7:0] spectrum_frame=0;
reg [7:0] scope_y=0;
reg [7:0] spectrum_height=0;
reg [4:0] selected=0;
reg  editing=0;
reg [6:0] volume_percent=0;
reg [6:0] echo_percent=0;
reg [6:0] joy_percent=0;
reg [5:0] light_brightness=0;
reg [3:0] timbre_sel=0;
reg [1:0] light_mode=0;
reg [1:0] audio_input_mask=0;
reg  language_cn=0;
reg  metro_enable=0;
reg [3:0] metro_beats=0;
reg [3:0] metro_unit=0;
reg [7:0] metro_bpm=0;
reg  draw_ready=0;
reg  pixel_ready=0;
reg  draw_done=0;
reg  draw_error=0;
always #10 clk=~clk;
keyboard_menu_renderer dut(.drum_bus_info(drum_bus_info),.clk(clk),.rst_n(rst_n),.init_done(init_done),.practice_screen(practice_screen),.practice_countdown(practice_countdown),.drum_config(drum_config),.drum_online(drum_online),.drum_calibrated(drum_calibrated),.drum_cal_state(drum_cal_state),.drum_bus_error(drum_bus_error),.drum_inserted(drum_inserted),.offline_active(offline_active),.offline_state(offline_state),.offline_error(offline_error),.offline_name(offline_name),.main_view(main_view),.menu_level(menu_level),.scope_valid(scope_valid),.spectrum_valid(spectrum_valid),.scope_frame(scope_frame),.spectrum_frame(spectrum_frame),.scope_y(scope_y),.spectrum_height(spectrum_height),.selected(selected),.editing(editing),.volume_percent(volume_percent),.echo_percent(echo_percent),.joy_percent(joy_percent),.light_brightness(light_brightness),.timbre_sel(timbre_sel),.light_mode(light_mode),.audio_input_mask(audio_input_mask),.language_cn(language_cn),.metro_enable(metro_enable),.metro_beats(metro_beats),.metro_unit(metro_unit),.metro_bpm(metro_bpm),.draw_ready(draw_ready),.pixel_ready(pixel_ready),.draw_done(draw_done),.draw_error(draw_error));
keyboard_menu_renderer_before refdut(.clk(clk),.rst_n(rst_n),.init_done(init_done),.practice_screen(practice_screen),.practice_countdown(practice_countdown),.drum_config(drum_config),.drum_online(drum_online),.drum_calibrated(drum_calibrated),.drum_cal_state(drum_cal_state),.drum_bus_error(drum_bus_error),.drum_inserted(drum_inserted),.offline_active(offline_active),.offline_state(offline_state),.offline_error(offline_error),.offline_name(offline_name),.main_view(main_view),.menu_level(menu_level),.scope_valid(scope_valid),.spectrum_valid(spectrum_valid),.scope_frame(scope_frame),.spectrum_frame(spectrum_frame),.scope_y(scope_y),.spectrum_height(spectrum_height),.selected(selected),.editing(editing),.volume_percent(volume_percent),.echo_percent(echo_percent),.joy_percent(joy_percent),.light_brightness(light_brightness),.timbre_sel(timbre_sel),.light_mode(light_mode),.audio_input_mask(audio_input_mask),.language_cn(language_cn),.metro_enable(metro_enable),.metro_beats(metro_beats),.metro_unit(metro_unit),.metro_bpm(metro_bpm),.draw_ready(draw_ready),.pixel_ready(pixel_ready),.draw_done(draw_done),.draw_error(draw_error));
integer v,l,c,k,i;
initial begin
init_done=1;draw_ready=0;
for(v=0;v<4;v=v+1)for(l=0;l<2;l=l+1)for(c=0;c<2;c=c+1)for(k=0;k<11;k=k+1)begin
 rst_n=0;repeat(3)@(negedge clk); main_view=2'(v);menu_level=1'(l);language_cn=1'(c);selected=5'(k);
 volume_percent=100;metro_bpm=137;timbre_sel=4'(k);drum_inserted=3;drum_online=3;drum_cal_state=3;drum_calibrated=3;drum_config=128'h006400a0007f0201006400a0007f0201;
 offline_active=(v==3 && k>7);offline_state=8'(k);offline_name="QJZG    ";
 rst_n=1;wait(dut.state==4);@(negedge clk);
 if(v>=2)for(i=0;i<4;i=i+1)begin
 if(dut.row_label[i]!==refdut.row_label[i] || dut.row_value[i]!==refdut.row_value[i] || dut.row_value_cn[i]!==refdut.row_value_cn[i] || dut.row_value_start[i]!==refdut.row_value_start[i])$fatal(1,"menu mismatch v%0d l%0d c%0d k%0d row%0d",v,l,c,k,i);
 end
end
$display("PASS: 176 menu snapshots match original text, language and alignment");$finish;end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
