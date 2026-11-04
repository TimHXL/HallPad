`timescale 1ns/1ps
// Exact integer arithmetic, one shared restoring divider and synchronous ROM.
// A refresh takes <160 clocks. Input controls are snapshotted once per refresh;
// physical gain stays live. The external 48 kHz sample clock is unchanged.
module hallpad_remote_pitch #(parameter integer NORMALIZED_PHYSICAL=0)(input wire clk,rst_n,sample_tick,enabled,input wire signed [15:0] bend,input wire [6:0] modulation,input wire [11:0] range_cents,input wire [21:0] physical_gain,input wire signed [15:0] physical_bend,input wire [6:0] physical_modulation,output reg [21:0] pitch_gain);
function [23:0] curve(input [7:0] a);begin case(a)
8'd0:curve=24'd165140;
8'd1:curve=24'd167542;
8'd2:curve=24'd169979;
8'd3:curve=24'd172452;
8'd4:curve=24'd174960;
8'd5:curve=24'd177505;
8'd6:curve=24'd180087;
8'd7:curve=24'd182706;
8'd8:curve=24'd185364;
8'd9:curve=24'd188060;
8'd10:curve=24'd190795;
8'd11:curve=24'd193571;
8'd12:curve=24'd196386;
8'd13:curve=24'd199243;
8'd14:curve=24'd202141;
8'd15:curve=24'd205081;
8'd16:curve=24'd208064;
8'd17:curve=24'd211090;
8'd18:curve=24'd214161;
8'd19:curve=24'd217276;
8'd20:curve=24'd220436;
8'd21:curve=24'd223642;
8'd22:curve=24'd226895;
8'd23:curve=24'd230195;
8'd24:curve=24'd233544;
8'd25:curve=24'd236941;
8'd26:curve=24'd240387;
8'd27:curve=24'd243884;
8'd28:curve=24'd247431;
8'd29:curve=24'd251030;
8'd30:curve=24'd254681;
8'd31:curve=24'd258386;
8'd32:curve=24'd262144;
8'd33:curve=24'd265957;
8'd34:curve=24'd269825;
8'd35:curve=24'd273750;
8'd36:curve=24'd277732;
8'd37:curve=24'd281772;
8'd38:curve=24'd285870;
8'd39:curve=24'd290028;
8'd40:curve=24'd294247;
8'd41:curve=24'd298527;
8'd42:curve=24'd302869;
8'd43:curve=24'd307274;
8'd44:curve=24'd311744;
8'd45:curve=24'd316278;
8'd46:curve=24'd320878;
8'd47:curve=24'd325546;
8'd48:curve=24'd330281;
8'd49:curve=24'd335085;
8'd50:curve=24'd339959;
8'd51:curve=24'd344904;
8'd52:curve=24'd349920;
8'd53:curve=24'd355010;
8'd54:curve=24'd360174;
8'd55:curve=24'd365413;
8'd56:curve=24'd370728;
8'd57:curve=24'd376120;
8'd58:curve=24'd381591;
8'd59:curve=24'd387141;
8'd60:curve=24'd392772;
8'd61:curve=24'd398485;
8'd62:curve=24'd404281;
8'd63:curve=24'd410162;
8'd64:curve=24'd416128;
8'd65:curve=24'd422180;
8'd66:curve=24'd428321;
8'd67:curve=24'd434551;
8'd68:curve=24'd440872;
8'd69:curve=24'd447285;
8'd70:curve=24'd453790;
8'd71:curve=24'd460391;
8'd72:curve=24'd467088;
8'd73:curve=24'd473881;
8'd74:curve=24'd480774;
8'd75:curve=24'd487767;
8'd76:curve=24'd494862;
8'd77:curve=24'd502060;
8'd78:curve=24'd509363;
8'd79:curve=24'd516771;
8'd80:curve=24'd524288;
8'd81:curve=24'd531914;
8'd82:curve=24'd539651;
8'd83:curve=24'd547500;
8'd84:curve=24'd555464;
8'd85:curve=24'd563543;
8'd86:curve=24'd571740;
8'd87:curve=24'd580056;
8'd88:curve=24'd588493;
8'd89:curve=24'd597053;
8'd90:curve=24'd605738;
8'd91:curve=24'd614548;
8'd92:curve=24'd623487;
8'd93:curve=24'd632556;
8'd94:curve=24'd641757;
8'd95:curve=24'd651091;
8'd96:curve=24'd660561;
8'd97:curve=24'd670170;
8'd98:curve=24'd679917;
8'd99:curve=24'd689807;
8'd100:curve=24'd699841;
8'd101:curve=24'd710020;
8'd102:curve=24'd720347;
8'd103:curve=24'd730825;
8'd104:curve=24'd741455;
8'd105:curve=24'd752240;
8'd106:curve=24'd763181;
8'd107:curve=24'd774282;
8'd108:curve=24'd785544;
8'd109:curve=24'd796970;
8'd110:curve=24'd808563;
8'd111:curve=24'd820323;
8'd112:curve=24'd832255;
8'd113:curve=24'd844361;
8'd114:curve=24'd856642;
8'd115:curve=24'd869102;
8'd116:curve=24'd881744;
8'd117:curve=24'd894569;
8'd118:curve=24'd907581;
8'd119:curve=24'd920782;
8'd120:curve=24'd934175;
8'd121:curve=24'd947763;
8'd122:curve=24'd961548;
8'd123:curve=24'd975534;
8'd124:curve=24'd989724;
8'd125:curve=24'd1004120;
8'd126:curve=24'd1018725;
8'd127:curve=24'd1033543;
8'd128:curve=24'd1048576;
8'd129:curve=24'd1063828;
8'd130:curve=24'd1079302;
8'd131:curve=24'd1095000;
8'd132:curve=24'd1110928;
8'd133:curve=24'd1127086;
8'd134:curve=24'd1143480;
8'd135:curve=24'd1160113;
8'd136:curve=24'd1176987;
8'd137:curve=24'd1194106;
8'd138:curve=24'd1211475;
8'd139:curve=24'd1229096;
8'd140:curve=24'd1246974;
8'd141:curve=24'd1265112;
8'd142:curve=24'd1283513;
8'd143:curve=24'd1302182;
8'd144:curve=24'd1321123;
8'd145:curve=24'd1340339;
8'd146:curve=24'd1359835;
8'd147:curve=24'd1379614;
8'd148:curve=24'd1399681;
8'd149:curve=24'd1420040;
8'd150:curve=24'd1440695;
8'd151:curve=24'd1461650;
8'd152:curve=24'd1482910;
8'd153:curve=24'd1504480;
8'd154:curve=24'd1526363;
8'd155:curve=24'd1548564;
8'd156:curve=24'd1571089;
8'd157:curve=24'd1593941;
8'd158:curve=24'd1617125;
8'd159:curve=24'd1640647;
8'd160:curve=24'd1664511;
8'd161:curve=24'd1688722;
8'd162:curve=24'd1713285;
8'd163:curve=24'd1738205;
8'd164:curve=24'd1763488;
8'd165:curve=24'd1789138;
8'd166:curve=24'd1815162;
8'd167:curve=24'd1841564;
8'd168:curve=24'd1868350;
8'd169:curve=24'd1895526;
8'd170:curve=24'd1923097;
8'd171:curve=24'd1951069;
8'd172:curve=24'd1979448;
8'd173:curve=24'd2008240;
8'd174:curve=24'd2037450;
8'd175:curve=24'd2067086;
8'd176:curve=24'd2097152;
8'd177:curve=24'd2127656;
8'd178:curve=24'd2158603;
8'd179:curve=24'd2190001;
8'd180:curve=24'd2221855;
8'd181:curve=24'd2254173;
8'd182:curve=24'd2286960;
8'd183:curve=24'd2320225;
8'd184:curve=24'd2353974;
8'd185:curve=24'd2388213;
8'd186:curve=24'd2422950;
8'd187:curve=24'd2458193;
8'd188:curve=24'd2493948;
8'd189:curve=24'd2530223;
8'd190:curve=24'd2567026;
8'd191:curve=24'd2604365;
8'd192:curve=24'd2642246;
8'd193:curve=24'd2680678;
8'd194:curve=24'd2719670;
8'd195:curve=24'd2759228;
8'd196:curve=24'd2799362;
8'd197:curve=24'd2840080;
8'd198:curve=24'd2881390;
8'd199:curve=24'd2923300;
8'd200:curve=24'd2965821;
8'd201:curve=24'd3008960;
8'd202:curve=24'd3052726;
8'd203:curve=24'd3097129;
8'd204:curve=24'd3142178;
8'd205:curve=24'd3187882;
8'd206:curve=24'd3234251;
8'd207:curve=24'd3281294;
8'd208:curve=24'd3329021;
8'd209:curve=24'd3377443;
8'd210:curve=24'd3426569;
8'd211:curve=24'd3476410;
8'd212:curve=24'd3526975;
8'd213:curve=24'd3578276;
8'd214:curve=24'd3630323;
8'd215:curve=24'd3683128;
8'd216:curve=24'd3736700;
8'd217:curve=24'd3791052;
8'd218:curve=24'd3846194;
8'd219:curve=24'd3902138;
8'd220:curve=24'd3958896;
8'd221:curve=24'd4016479;
8'd222:curve=24'd4074900;
8'd223:curve=24'd4134171;
8'd224:curve=24'd4194304;
8'd225:curve=24'd4255312;
8'd226:curve=24'd4317206;
8'd227:curve=24'd4380002;
8'd228:curve=24'd4443710;
8'd229:curve=24'd4508346;
8'd230:curve=24'd4573921;
8'd231:curve=24'd4640450;
8'd232:curve=24'd4707947;
8'd233:curve=24'd4776426;
8'd234:curve=24'd4845900;
8'd235:curve=24'd4916386;
8'd236:curve=24'd4987896;
8'd237:curve=24'd5060447;
8'd238:curve=24'd5134053;
8'd239:curve=24'd5208729;
8'd240:curve=24'd5284492;
8'd241:curve=24'd5361357;
8'd242:curve=24'd5439339;
8'd243:curve=24'd5518456;
8'd244:curve=24'd5598724;
8'd245:curve=24'd5680159;
8'd246:curve=24'd5762779;
8'd247:curve=24'd5846601;
8'd248:curve=24'd5931642;
8'd249:curve=24'd6017919;
8'd250:curve=24'd6105452;
8'd251:curve=24'd6194258;
8'd252:curve=24'd6284355;
8'd253:curve=24'd6375763;
8'd254:curve=24'd6468501;
8'd255:curve=24'd6562588;
default:curve=1048576;endcase end endfunction

(* syn_ramstyle="block_ram" *) reg [23:0] curve_rom[0:255];
integer ri;
initial begin for(ri=0;ri<256;ri=ri+1) curve_rom[ri]=curve(ri[7:0]);end
reg [7:0] rom_address;
reg [23:0] rom_q;
always @(posedge clk) rom_q<=curve_rom[rom_address];
localparam [3:0] START=0,MOD_LOAD=1,DIVIDE=2,MOD_DONE=3,ADDRESS_LOAD=4,ADDRESS_DONE=5,LOW_WAIT=6,LOW_CAPTURE=7,HIGH_WAIT=8,HIGH_CAPTURE=9,WEIGHT_LOAD=10,WEIGHT_DONE=11,BEND_DONE=12;
reg [3:0] state,return_state;
reg [13:0] phase;
reg signed [15:0] triangle;
reg signed [29:0] bend_product;
reg signed [23:0] mod_product;
reg mod_negative,bend_negative;
reg signed [15:0] vibrato_hold;
reg [12:0] offset_cents;
reg [4:0] fraction;
reg [23:0] gain_lo,remote_gain;
reg [28:0] weighted_delta;
reg [31:0] dividend,quotient;
reg [12:0] remainder,divisor;
reg [5:0] bit_index;
wire [13:0] trial={remainder,dividend[31]};
wire take_bit=trial>={1'b0,divisor};
wire [13:0] reduced=trial-{1'b0,divisor};
// Product range has redundant sign bits; explicitly retain the 16-bit cents.
wire signed [15:0] bend_cents=$signed(bend_product[28:13]);
wire [15:0] bend_magnitude=bend_cents[15] ? (~bend_cents+16'd1):bend_cents;
wire [19:0] bend_times3={4'd0,bend_magnitude}+{3'd0,bend_magnitude,1'b0};
wire [19:0] bend_times13={1'd0,bend_magnitude,3'd0}+{2'd0,bend_magnitude,2'd0}+{4'd0,bend_magnitude};
wire signed [17:0] amplified_bend=bend_negative ? -$signed({1'b0,quotient[16:0]}):$signed({1'b0,quotient[16:0]});
wire signed [15:0] vibrato_cents=mod_negative ? -$signed(quotient[15:0]):$signed(quotient[15:0]);
wire signed [18:0] cents=$signed({amplified_bend[17],amplified_bend})+$signed({{3{vibrato_hold[15]}},vibrato_hold});
wire [18:0] unsigned_offset=$unsigned(cents+19'sd3200);
wire [23:0] delta=rom_q-gain_lo;
// App already scales its wire values by 0x70. Physical controls do the
// same once before entering this common 0x05 range / 5 Hz / 50-cent mapper.
wire signed [16:0] total_bend=(enabled ? $signed({bend[15],bend}):17'sd0)+
    (NORMALIZED_PHYSICAL!=0 ? $signed({physical_bend[15],physical_bend}):17'sd0);
wire [7:0] total_modulation=(enabled ? {1'b0,modulation}:8'd0)+
    (NORMALIZED_PHYSICAL!=0 ? {1'b0,physical_modulation}:8'd0);
reg [45:0] combined;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=START;return_state<=START;phase<=0;triangle<=0;bend_product<=0;mod_product<=0;mod_negative<=0;bend_negative<=0;vibrato_hold<=0;offset_cents<=3200;fraction<=0;gain_lo<=1048576;remote_gain<=1048576;weighted_delta<=0;
        dividend<=0;quotient<=0;remainder<=0;divisor<=1;bit_index<=0;rom_address<=128;combined<=46'd1099511627776;pitch_gain<=1048576;
    end else begin
        if(sample_tick) phase<=phase==9599 ? 14'd0:phase+1'b1;
        triangle<=phase<2400 ? $signed({2'd0,phase}):phase<7200 ? 16'sd4800-$signed({2'd0,phase}):$signed({2'd0,phase})-16'sd9600;
        combined<={2'd0,physical_gain}*((enabled || NORMALIZED_PHYSICAL!=0) ? remote_gain:24'd1048576);
        pitch_gain<=combined[45:20]>4194303 ? 22'd4194303:combined[41:20];
        case(state)
            START:begin
                bend_product<=total_bend*$signed({1'b0,range_cents});
                mod_product<=triangle*$signed({1'b0,total_modulation});
                state<=MOD_LOAD;
            end
            MOD_LOAD:begin
                mod_negative<=mod_product[23];
                dividend<=mod_product[23] ? {8'd0,$unsigned(-mod_product)}:{8'd0,$unsigned(mod_product)};
                divisor<=6096;quotient<=0;remainder<=0;bit_index<=0;return_state<=MOD_DONE;state<=DIVIDE;
            end
            DIVIDE:begin
                dividend<={dividend[30:0],1'b0};quotient<={quotient[30:0],take_bit};remainder<=take_bit ? reduced[12:0]:trial[12:0];
                if(bit_index==31) state<=return_state;else bit_index<=bit_index+1'b1;
            end
            MOD_DONE:begin
                // Reuse the existing divider: up x3/2, down x13/10. Only the
                // slide is amplified; vibrato depth/frequency remains unchanged.
                vibrato_hold<=vibrato_cents;bend_negative<=bend_cents[15];
                dividend<=bend_cents[15] ? {12'd0,bend_times13}+32'd5:{12'd0,bend_times3}+32'd1;
                divisor<=bend_cents[15] ? 13'd10:13'd2;
                quotient<=0;remainder<=0;bit_index<=0;return_state<=BEND_DONE;state<=DIVIDE;
            end
            BEND_DONE:begin
                // Extend the low-frequency table for -3120-cent full travel.
                // The existing 22-bit DDS gain ceiling still bounds positive gain.
                offset_cents<=cents < -3200 ? 13'd0:cents > 2450 ? 13'd5650:unsigned_offset[12:0];state<=ADDRESS_LOAD;
            end
            ADDRESS_LOAD:begin dividend<={19'd0,offset_cents};divisor<=25;quotient<=0;remainder<=0;bit_index<=0;return_state<=ADDRESS_DONE;state<=DIVIDE;end
            ADDRESS_DONE:begin rom_address<=quotient[7:0];fraction<=remainder[4:0];state<=LOW_WAIT;end
            LOW_WAIT:state<=LOW_CAPTURE;
            LOW_CAPTURE:begin gain_lo<=rom_q;rom_address<=rom_address+1'b1;state<=HIGH_WAIT;end
            HIGH_WAIT:state<=HIGH_CAPTURE;
            HIGH_CAPTURE:begin weighted_delta<={5'd0,delta}*{24'd0,fraction};state<=WEIGHT_LOAD;end
            WEIGHT_LOAD:begin dividend<={3'd0,weighted_delta};divisor<=25;quotient<=0;remainder<=0;bit_index<=0;return_state<=WEIGHT_DONE;state<=DIVIDE;end
            WEIGHT_DONE:begin remote_gain<=gain_lo+quotient[23:0];state<=START;end
            default:state<=START;
        endcase
    end
end
endmodule
