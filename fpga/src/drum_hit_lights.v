`timescale 1ns/1ps
// Independent 8-color palette. Same fixed 20 ms chord grouping as keyboard.
// Speed = 1..1000 ms attack; decay = 0 hold, otherwise 1..5000 ms fade.
// Repeated subtraction updates envelope in at most 256 clocks per ms tick.
module drum_hit_lights #(parameter integer CHORD_CYCLES=1000000)(
 input wire clk,rst_n,ms_tick,hit,stick,
 input wire [47:0] settings,
 input wire [31:0] color_settings,
 output reg [23:0] rgbL,rgbR
);
 function [23:0] palette(input [2:0] i);
 begin case(i)
  0:palette=24'h2070FF;1:palette=24'h20FFC0;
  2:palette=24'h80FF20;3:palette=24'hFFC020;
  4:palette=24'hFF5020;5:palette=24'hFF2070;
  6:palette=24'hC020FF;7:palette=24'h6020C0;
 endcase end endfunction
 reg [2:0] current_color;
 reg chord_active;
 localparam integer CHORD_W=CHORD_CYCLES<2 ? 1:$clog2(CHORD_CYCLES);
 localparam [CHORD_W-1:0] CHORD_LAST=CHORD_CYCLES-1;
 reg [CHORD_W-1:0] chord_count;
 wire new_hit=hit && settings[0];
 wire start_group=new_hit && color_settings[7:0]==0 && (!chord_active || chord_count==CHORD_LAST);
 wire [2:0] press_color=start_group ? current_color+3'd1:current_color;
 reg [2:0] indices[0:1];
 wire [23:0] custom_rgb={color_settings[15:8],color_settings[23:16],color_settings[31:24]};
 wire [23:0] colors[0:1];
 assign colors[0]=color_settings[0] ? custom_rgb:palette(indices[0]);
 assign colors[1]=color_settings[0] ? custom_rgb:palette(indices[1]);
 reg [8:0] level[0:1];
 reg rising[0:1];
 reg [16:0] budget[0:1];
 wire [15:0] attack_ms=settings[31:16];
 wire [15:0] decay_ms=settings[47:32];
 reg [23:0] envelope[0:1];
 reg [47:0] brightness_products[0:1];
 function [7:0] envelope_byte(input [7:0] c,input [8:0] l);
 reg [16:0] p;begin p=c*l;envelope_byte=p[15:8];end endfunction
 // Separate 8x8 multiplication from constant division: one extra clk,
 // avoiding the brightness-config -> multiply -> divide -> RGB long path.
 function [15:0] brightness_product(input [7:0] c,input [7:0] b);
 begin brightness_product=c*b;end endfunction
 function [7:0] brightness_quotient(input [15:0] p);
 reg [15:0] q;begin q=p/16'd100;brightness_quotient=q[7:0];end endfunction
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin current_color<=0;chord_active<=0;chord_count<=0;rgbL<=0;rgbR<=0;
   for(i=0;i<2;i=i+1)begin indices[i]<=0;level[i]<=0;rising[i]<=0;budget[i]<=0;envelope[i]<=0;brightness_products[i]<=0;end
  end else begin
   if(start_group)begin current_color<=press_color;chord_active<=1;chord_count<=0;end
   else if(chord_active)begin
    if(chord_count==CHORD_LAST)chord_active<=0;else chord_count<=chord_count+1'b1;
   end
   for(i=0;i<2;i=i+1)begin
    if(!settings[0])begin level[i]<=0;budget[i]<=0;rising[i]<=0;end
    else if(new_hit && stick==i[0])begin if(!color_settings[0])indices[i]<=press_color;level[i]<=0;rising[i]<=1;budget[i]<=0;end
    else if(ms_tick)begin
     if(rising[i] || (decay_ms!=0 && level[i]!=0))budget[i]<=budget[i]+17'd256;
     else budget[i]<=0;
    end else if(rising[i] && budget[i]>={1'b0,attack_ms})begin
     if(level[i]==255)begin level[i]<=256;rising[i]<=0;budget[i]<=0;end
     else begin level[i]<=level[i]+1'b1;budget[i]<=budget[i]-{1'b0,attack_ms};end
    end else if(!rising[i] && decay_ms!=0 && level[i]!=0 && budget[i]>={1'b0,decay_ms})begin
     level[i]<=level[i]-1'b1;budget[i]<=budget[i]-{1'b0,decay_ms};
    end
    envelope[i]<={envelope_byte(colors[i][23:16],level[i]),envelope_byte(colors[i][15:8],level[i]),envelope_byte(colors[i][7:0],level[i])};
    brightness_products[i]<={brightness_product(envelope[i][23:16],settings[15:8]),brightness_product(envelope[i][15:8],settings[15:8]),brightness_product(envelope[i][7:0],settings[15:8])};
   end
   rgbL<=settings[0] ? {brightness_quotient(brightness_products[0][47:32]),brightness_quotient(brightness_products[0][31:16]),brightness_quotient(brightness_products[0][15:0])}:24'd0;
   rgbR<=settings[0] ? {brightness_quotient(brightness_products[1][47:32]),brightness_quotient(brightness_products[1][31:16]),brightness_quotient(brightness_products[1][15:0])}:24'd0;
  end
 end
endmodule
