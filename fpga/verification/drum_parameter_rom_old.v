`timescale 1ns/1ps
// HallBeat voices: snare, kick, closed hat, mid tom, crash, ride.
// Exact modal coefficients selected from HallDrum11; no sampled recordings.
module drum_parameter_rom_old(input wire clk,input wire [5:0] address,output reg [31:0] increment,output reg [23:0] initial_envelope,output reg [15:0] decay);
    always @(posedge clk) case(address)
        6'd0:begin increment<=32'd17269348;initial_envelope<=24'd691200;decay<=16'd34;end
        6'd1:begin increment<=32'd25053976;initial_envelope<=24'd793600;decay<=16'd43;end
        6'd2:begin increment<=32'd36954614;initial_envelope<=24'd230400;decay<=16'd63;end
        6'd3:begin increment<=32'd49839516;initial_envelope<=24'd153600;decay<=16'd79;end
        6'd4:begin increment<=32'd75609320;initial_envelope<=24'd76800;decay<=16'd105;end
        6'd5:begin increment<=32'd100842253;initial_envelope<=24'd51200;decay<=16'd135;end
        6'd6:begin increment<=32'd0;initial_envelope<=24'd1100800;decay<=16'd34;end
        6'd7:begin increment<=32'd5100274;initial_envelope<=24'd1587200;decay<=16'd36;end
        6'd8:begin increment<=32'd6531929;initial_envelope<=24'd332800;decay<=16'd59;end
        6'd9:begin increment<=32'd10111069;initial_envelope<=24'd204800;decay<=16'd86;end
        6'd10:begin increment<=32'd16732477;initial_envelope<=24'd89600;decay<=16'd118;end
        6'd11:begin increment<=32'd27827809;initial_envelope<=24'd38400;decay<=16'd209;end
        6'd12:begin increment<=32'd45634028;initial_envelope<=24'd20480;decay<=16'd314;end
        6'd13:begin increment<=32'd0;initial_envelope<=24'd409600;decay<=16'd376;end
        6'd14:begin increment<=32'd545818761;initial_envelope<=24'd102400;decay<=16'd94;end
        6'd15:begin increment<=32'd652029723;initial_envelope<=24'd115200;decay<=16'd94;end
        6'd16:begin increment<=32'd774883683;initial_envelope<=24'd102400;decay<=16'd94;end
        6'd17:begin increment<=32'd913306900;initial_envelope<=24'd128000;decay<=16'd94;end
        6'd18:begin increment<=32'd1086268812;initial_envelope<=24'd115200;decay<=16'd94;end
        6'd19:begin increment<=32'd1259857073;initial_envelope<=24'd89600;decay<=16'd94;end
        6'd20:begin increment<=32'd0;initial_envelope<=24'd972800;decay<=16'd73;end
        6'd21:begin increment<=32'd10737418;initial_envelope<=24'd1254400;decay<=16'd13;end
        6'd22:begin increment<=32'd13153337;initial_envelope<=24'd460800;decay<=16'd24;end
        6'd23:begin increment<=32'd16732477;initial_envelope<=24'd256000;decay<=16'd31;end
        6'd24:begin increment<=32'd23890756;initial_envelope<=24'd153600;decay<=16'd39;end
        6'd25:begin increment<=32'd31943819;initial_envelope<=24'd89600;decay<=16'd52;end
        6'd26:begin increment<=32'd46618291;initial_envelope<=24'd46080;decay<=16'd79;end
        6'd27:begin increment<=32'd0;initial_envelope<=24'd204800;decay<=16'd171;end
        6'd28:begin increment<=32'd324180552;initial_envelope<=24'd179200;decay<=16'd4;end
        6'd29:begin increment<=32'd481483730;initial_envelope<=24'd166400;decay<=16'd3;end
        6'd30:begin increment<=32'd660977571;initial_envelope<=24'd230400;decay<=16'd3;end
        6'd31:begin increment<=32'd711085523;initial_envelope<=24'd204800;decay<=16'd3;end
        6'd32:begin increment<=32'd766204270;initial_envelope<=24'd179200;decay<=16'd4;end
        6'd33:begin increment<=32'd1082689673;initial_envelope<=24'd128000;decay<=16'd5;end
        6'd34:begin increment<=32'd0;initial_envelope<=24'd1075200;decay<=16'd4;end
        6'd35:begin increment<=32'd247944883;initial_envelope<=24'd140800;decay<=16'd12;end
        6'd36:begin increment<=32'd359077162;initial_envelope<=24'd192000;decay<=16'd13;end
        6'd37:begin increment<=32'd546445110;initial_envelope<=24'd166400;decay<=16'd15;end
        6'd38:begin increment<=32'd717349017;initial_envelope<=24'd230400;decay<=16'd19;end
        6'd39:begin increment<=32'd904627487;initial_envelope<=24'd256000;decay<=16'd21;end
        6'd40:begin increment<=32'd980415764;initial_envelope<=24'd179200;decay<=16'd24;end
        6'd41:begin increment<=32'd0;initial_envelope<=24'd614400;decay<=16'd24;end
        default:begin increment<=0;initial_envelope<=0;decay<=1;end
    endcase
endmodule
