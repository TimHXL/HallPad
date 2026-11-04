`timescale 1ns/1ps
// Fixed 80 pixels per stick. One shared iterative arithmetic worker builds
// complete frames; no parallel per-pixel divider or per-pixel timer bank.
module drum_strip_lights #(parameter integer CHORD_CYCLES=1000000)(
 input wire slot_launch,slot_window,
 input wire [1:0] force_refresh,
 input wire clk,rst_n,ms_tick,hit,stick,
 input wire [47:0] settings,input wire [31:0] color_settings,
 input wire [87:0] effect_config,input wire effect_active,
 output wire serialL,serialR
);
 function [23:0] palette(input [2:0] i);begin case(i)
 0:palette=24'h2070ff;1:palette=24'h20ffc0;2:palette=24'h80ff20;3:palette=24'hffc020;
 4:palette=24'hff5020;5:palette=24'hff2070;6:palette=24'hc020ff;7:palette=24'h6020c0;
 endcase end endfunction
 wire [23:0] legacyL,legacyR;
 drum_hit_lights #(.CHORD_CYCLES(CHORD_CYCLES)) legacy(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),
  .hit(hit && !effect_active),.stick(stick),.settings({settings[47:1],settings[0] && !effect_active}),.color_settings(color_settings),.rgbL(legacyL),.rgbR(legacyR));
 reg [31:0] now_ms,startL,startR;
 reg [17:0] speedL,speedR,frame_speedL,frame_speedR;
 reg [12:0] decayL,decayR,frame_decayL,frame_decayR;
 reg [1:0] waves;
 reg [2:0] colorL,colorR,current_color;
 localparam integer CW=CHORD_CYCLES<2 ? 1:$clog2(CHORD_CYCLES);
 localparam [CW-1:0] CHORD_LAST=CHORD_CYCLES-1;
 reg [CW-1:0] chord_count;reg chord_active;
 reg [7:0] previous_mode;reg previous_active;
 reg [15:0] clear_epoch;
 wire mode_change=previous_mode!=effect_config[7:0] || previous_active!=effect_active;
 wire water_hit=hit && effect_active && effect_config[7:0]==0 && !mode_change;
 wire new_group=water_hit && (!chord_active || chord_count==CHORD_LAST);
 wire [2:0] press_color=new_group ? current_color+3'd1:current_color;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin speedL<=80000;speedR<=80000;decayL<=1200;decayR<=1200;now_ms<=0;startL<=0;startR<=0;waves<=0;colorL<=0;colorR<=0;current_color<=0;
   chord_count<=0;chord_active<=0;previous_mode<=0;previous_active<=1;clear_epoch<=1;end
  else begin
   previous_mode<=effect_config[7:0];previous_active<=effect_active;
   if(ms_tick)now_ms<=now_ms+1'b1;
   if(waves[0] && now_ms-startL>32'd163000)waves[0]<=0;
   if(waves[1] && now_ms-startR>32'd163000)waves[1]<=0;
   if(mode_change)begin waves<=0;clear_epoch<=clear_epoch+1'b1;end
   else if(water_hit)begin
    if(stick)begin speedR<=effect_config[33:16];decayR<=effect_config[60:48];startR<=now_ms;waves[1]<=1;colorR<=press_color;end
    else begin speedL<=effect_config[33:16];decayL<=effect_config[60:48];startL<=now_ms;waves[0]<=1;colorL<=press_color;end
   end
   if(new_group)begin current_color<=press_color;chord_active<=1;chord_count<=0;end
   else if(chord_active)begin if(chord_count==CHORD_LAST)chord_active<=0;else chord_count<=chord_count+1'b1;end
  end
 end
 localparam SNAP=0,PREP=1,DIVIDE=2,ARRIVAL=3,AGE=4,FADE=5,SHADE=6,BRIGHT=7,WRITE=8,COMMIT=9,HREAD=10,HWAIT=11,HINIT=12,BRIGHT_DIV=13;
 reg [3:0] state;reg [3:0] div_return;
 reg [7:0] pixel; // 0..79 left, 80..159 right
 wire right_pixel=pixel>=80;
 wire [6:0] local_pixel=right_pixel ? pixel[6:0]-7'd80:pixel[6:0];
 reg [87:0] frame_config;reg frame_active;reg [15:0] frame_epoch;
 reg [31:0] elapsedL,elapsedR,arrival_ms,frame_now;
 // Per-pixel arrival history; shared synchronous RAM, no parallel timers.
 (* syn_ramstyle="block_ram" *) reg [50:0] history[0:159];
 reg [50:0] history_q;
 reg [1:0] frame_waves;reg [2:0] frame_colorL,frame_colorR;
 wire [31:0] elapsed=right_pixel ? elapsedR:elapsedL;
 wire [31:0] age=elapsed-arrival_ms;
 wire current_arrived=frame_waves[right_pixel] && elapsed>=arrival_ms;
 wire history_valid=history_q[50:35]==frame_epoch;
 wire [31:0] pixel_age=current_arrived ? age:frame_now-history_q[34:3];
 always @(posedge clk)begin
  // Read only in the dedicated prefetch phase. Writing never requests old
  // RAM output, allowing the device-supported no-change/write mode.
  if(state==HREAD)history_q<=history[pixel];
  if(state==HINIT)history[pixel]<=51'd0;
  else if(state==AGE && current_arrived)
   history[pixel]<={frame_epoch,frame_now-elapsed+arrival_ms,right_pixel ? frame_colorR:frame_colorL};
 end

 reg [23:0] source_rgb,envelope_rgb,scaled_rgb;
 reg [47:0] brightness_products;
 reg [8:0] intensity;
 reg [26:0] numerator,quotient;
 reg [17:0] remainder,divisor;
 reg [5:0] bits_left;
 wire [18:0] trial={remainder,numerator[26]};
 wire take_bit=trial>={1'b0,divisor};
 wire [18:0] rem_next=take_bit ? trial-{1'b0,divisor}:trial;
 wire [26:0] quotient_next={quotient[25:0],take_bit};


 function [7:0] envelope_byte(input [7:0] c,input [8:0] level);
 reg [16:0] p;begin p=c*level;envelope_byte=p[15:8];end endfunction
 function [7:0] brightness_quotient(input [15:0] p);
 reg [15:0] q;begin q=p/16'd100;brightness_quotient=q[7:0];end endfunction
 function [15:0] brightness_product(input [7:0] c,input [7:0] level);
 begin brightness_product=c*level;end endfunction
 task divide(input [26:0] n,input [17:0] d,input [3:0] target);begin
  numerator<=n;quotient<=0;remainder<=0;divisor<=d;bits_left<=27;div_return<=target;state<=DIVIDE;end endtask
 reg [159:0] pixel_arrivals;
 wire [1439:0] persistent_levels;
 wire new_arrival=current_arrived && (!history_valid || history_q[34:3]!=(frame_now-elapsed+arrival_ms) || history_q[2:0]!=(right_pixel ? frame_colorR:frame_colorL));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)pixel_arrivals<=0;
  else begin pixel_arrivals<=0;if(state==AGE && new_arrival)pixel_arrivals[pixel]<=1;end
 end
 drum_ripple_envelope envelope(.clk(clk),.rst_n(rst_n && !mode_change),.ms_tick(ms_tick),.arrivals(pixel_arrivals),
  .arrival_index(pixel),.speed(right_pixel ? frame_speedR:frame_speedL),.width(12'd1000),.decay_ms(right_pixel ? frame_decayR:frame_decayL),.intensities(persistent_levels));
 wire commit_ready;
 wire frame_current=frame_config==effect_config && frame_active==effect_active && frame_epoch==clear_epoch && !mode_change;
 drum_strip_rgb_ram output_ram(.force_refresh(force_refresh),.slot_launch(slot_launch),.slot_window(slot_window),.clk(clk),.rst_n(rst_n),.write_valid(state==WRITE),.write_right(right_pixel),
  .write_index(local_pixel),.write_rgb(scaled_rgb),.commit_valid(state==COMMIT && frame_current),.commit_ready(commit_ready),
  .legacy_mode(!effect_active),.force_black(effect_active && (effect_config[7:0]==2 || effect_config[15:8]==0)),
  .legacyL(legacyL),.legacyR(legacyR),.serialL(serialL),.serialR(serialR));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=HINIT;div_return<=0;pixel<=0;
   frame_speedL<=80000;frame_speedR<=80000;frame_decayL<=1200;frame_decayR<=1200;frame_config<=0;frame_active<=0;frame_epoch<=0;elapsedL<=0;elapsedR<=0;arrival_ms<=0;frame_now<=0;frame_waves<=0;frame_colorL<=0;frame_colorR<=0;
   source_rgb<=0;envelope_rgb<=0;scaled_rgb<=0;brightness_products<=0;intensity<=0;numerator<=0;quotient<=0;remainder<=0;divisor<=1;bits_left<=0;end
  else case(state)
   HINIT:if(pixel==159)begin pixel<=0;state<=SNAP;end else pixel<=pixel+1'b1;
   HREAD:state<=HWAIT;
   HWAIT:state<=PREP;
   SNAP:begin frame_speedL<=speedL;frame_speedR<=speedR;frame_decayL<=decayL;frame_decayR<=decayR;frame_config<=effect_config;frame_active<=effect_active;frame_epoch<=clear_epoch;
    frame_now<=now_ms;elapsedL<=now_ms-startL;elapsedR<=now_ms-startR;frame_waves<=waves;frame_colorL<=colorL;frame_colorR<=colorR;
    pixel<=0;state<=HREAD;end
   PREP:begin
    if(!frame_active || frame_config[7:0]==2 || frame_config[15:8]==0)begin intensity<=0;source_rgb<=0;state<=SHADE;end
    else if(frame_config[7:0]==1)begin intensity<=256;source_rgb<={frame_config[71:64],frame_config[79:72],frame_config[87:80]};state<=SHADE;end
    else begin source_rgb<=palette(right_pixel ? frame_colorR:frame_colorL);
     divide({20'd0,local_pixel}*27'd1000000,(right_pixel ? frame_speedR:frame_speedL),ARRIVAL);end
   end
   DIVIDE:begin
    numerator<={numerator[25:0],1'b0};quotient<=quotient_next;remainder<=rem_next[17:0];
    if(bits_left==1)state<=div_return;else bits_left<=bits_left-1'b1;
   end
   ARRIVAL:begin arrival_ms<={5'd0,quotient}+(remainder!=0 ? 32'd1:32'd0);state<=AGE;end
   AGE:begin
    source_rgb<=palette(current_arrived ? (right_pixel ? frame_colorR:frame_colorL):history_q[2:0]);
    intensity<=(!current_arrived && !history_valid) ? 9'd0:new_arrival ? 9'd256:persistent_levels[pixel*9+:9];
    state<=SHADE;
   end
   FADE:begin intensity<=9'd256-{1'b0,quotient[7:0]};state<=SHADE;end
   SHADE:begin envelope_rgb<={envelope_byte(source_rgb[23:16],intensity),envelope_byte(source_rgb[15:8],intensity),envelope_byte(source_rgb[7:0],intensity)};state<=BRIGHT;end
   BRIGHT:begin brightness_products<={brightness_product(envelope_rgb[23:16],frame_config[15:8]),brightness_product(envelope_rgb[15:8],frame_config[15:8]),brightness_product(envelope_rgb[7:0],frame_config[15:8])};state<=BRIGHT_DIV;end
   BRIGHT_DIV:begin scaled_rgb<={brightness_quotient(brightness_products[47:32]),brightness_quotient(brightness_products[31:16]),brightness_quotient(brightness_products[15:0])};state<=WRITE;end
   WRITE:begin
    if(pixel==159)state<=COMMIT;
    else begin pixel<=pixel+1'b1;state<=HREAD;end
   end
   COMMIT:if(!frame_current || commit_ready)state<=SNAP;
   default:state<=SNAP;
  endcase
 end
endmodule
