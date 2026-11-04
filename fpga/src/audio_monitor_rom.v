// Monitor ROMs only; no recorded audio or synthesizer waveform changes.
module audio_monitor_coefficient(input wire [6:0] address,output reg signed [15:0] value);
    always @* case(address)
        7'd0:value=16'sd0;
        7'd1:value=16'sd0;
        7'd2:value=16'sd0;
        7'd3:value=16'sd1;
        7'd4:value=16'sd1;
        7'd5:value=16'sd1;
        7'd6:value=16'sd0;
        7'd7:value=-16'sd1;
        7'd8:value=-16'sd4;
        7'd9:value=-16'sd6;
        7'd10:value=-16'sd9;
        7'd11:value=-16'sd12;
        7'd12:value=-16'sd13;
        7'd13:value=-16'sd13;
        7'd14:value=-16'sd10;
        7'd15:value=-16'sd4;
        7'd16:value=16'sd5;
        7'd17:value=16'sd16;
        7'd18:value=16'sd30;
        7'd19:value=16'sd43;
        7'd20:value=16'sd54;
        7'd21:value=16'sd61;
        7'd22:value=16'sd61;
        7'd23:value=16'sd52;
        7'd24:value=16'sd33;
        7'd25:value=16'sd3;
        7'd26:value=-16'sd34;
        7'd27:value=-16'sd77;
        7'd28:value=-16'sd121;
        7'd29:value=-16'sd159;
        7'd30:value=-16'sd185;
        7'd31:value=-16'sd193;
        7'd32:value=-16'sd177;
        7'd33:value=-16'sd134;
        7'd34:value=-16'sd64;
        7'd35:value=16'sd30;
        7'd36:value=16'sd141;
        7'd37:value=16'sd258;
        7'd38:value=16'sd366;
        7'd39:value=16'sd450;
        7'd40:value=16'sd494;
        7'd41:value=16'sd484;
        7'd42:value=16'sd412;
        7'd43:value=16'sd272;
        7'd44:value=16'sd71;
        7'd45:value=-16'sd180;
        7'd46:value=-16'sd460;
        7'd47:value=-16'sd740;
        7'd48:value=-16'sd986;
        7'd49:value=-16'sd1161;
        7'd50:value=-16'sd1229;
        7'd51:value=-16'sd1158;
        7'd52:value=-16'sd924;
        7'd53:value=-16'sd516;
        7'd54:value=16'sd66;
        7'd55:value=16'sd804;
        7'd56:value=16'sd1667;
        7'd57:value=16'sd2612;
        7'd58:value=16'sd3583;
        7'd59:value=16'sd4521;
        7'd60:value=16'sd5363;
        7'd61:value=16'sd6052;
        7'd62:value=16'sd6541;
        7'd63:value=16'sd6790;
        7'd64:value=16'sd6790;
        7'd65:value=16'sd6541;
        7'd66:value=16'sd6052;
        7'd67:value=16'sd5363;
        7'd68:value=16'sd4521;
        7'd69:value=16'sd3583;
        7'd70:value=16'sd2612;
        7'd71:value=16'sd1667;
        7'd72:value=16'sd804;
        7'd73:value=16'sd66;
        7'd74:value=-16'sd516;
        7'd75:value=-16'sd924;
        7'd76:value=-16'sd1158;
        7'd77:value=-16'sd1229;
        7'd78:value=-16'sd1161;
        7'd79:value=-16'sd986;
        7'd80:value=-16'sd740;
        7'd81:value=-16'sd460;
        7'd82:value=-16'sd180;
        7'd83:value=16'sd71;
        7'd84:value=16'sd272;
        7'd85:value=16'sd412;
        7'd86:value=16'sd484;
        7'd87:value=16'sd494;
        7'd88:value=16'sd450;
        7'd89:value=16'sd366;
        7'd90:value=16'sd258;
        7'd91:value=16'sd141;
        7'd92:value=16'sd30;
        7'd93:value=-16'sd64;
        7'd94:value=-16'sd134;
        7'd95:value=-16'sd177;
        7'd96:value=-16'sd193;
        7'd97:value=-16'sd185;
        7'd98:value=-16'sd159;
        7'd99:value=-16'sd121;
        7'd100:value=-16'sd77;
        7'd101:value=-16'sd34;
        7'd102:value=16'sd3;
        7'd103:value=16'sd33;
        7'd104:value=16'sd52;
        7'd105:value=16'sd61;
        7'd106:value=16'sd61;
        7'd107:value=16'sd54;
        7'd108:value=16'sd43;
        7'd109:value=16'sd30;
        7'd110:value=16'sd16;
        7'd111:value=16'sd5;
        7'd112:value=-16'sd4;
        7'd113:value=-16'sd10;
        7'd114:value=-16'sd13;
        7'd115:value=-16'sd13;
        7'd116:value=-16'sd12;
        7'd117:value=-16'sd9;
        7'd118:value=-16'sd6;
        7'd119:value=-16'sd4;
        7'd120:value=-16'sd1;
        7'd121:value=16'sd0;
        7'd122:value=16'sd1;
        7'd123:value=16'sd1;
        7'd124:value=16'sd1;
        7'd125:value=16'sd0;
        7'd126:value=16'sd0;
        7'd127:value=16'sd0;
        default:value=0;
    endcase
endmodule

module audio_monitor_sine(input wire [10:0] phase,output reg signed [15:0] value);
    wire [9:0] address=phase[9] ? 10'd512-{1'b0,phase[8:0]}:{1'b0,phase[8:0]};
    reg [15:0] magnitude;
    always @*begin
        case(address)
            10'd0:magnitude=16'd0;
            10'd1:magnitude=16'd101;
            10'd2:magnitude=16'd201;
            10'd3:magnitude=16'd302;
            10'd4:magnitude=16'd402;
            10'd5:magnitude=16'd503;
            10'd6:magnitude=16'd603;
            10'd7:magnitude=16'd704;
            10'd8:magnitude=16'd804;
            10'd9:magnitude=16'd905;
            10'd10:magnitude=16'd1005;
            10'd11:magnitude=16'd1106;
            10'd12:magnitude=16'd1206;
            10'd13:magnitude=16'd1307;
            10'd14:magnitude=16'd1407;
            10'd15:magnitude=16'd1507;
            10'd16:magnitude=16'd1608;
            10'd17:magnitude=16'd1708;
            10'd18:magnitude=16'd1809;
            10'd19:magnitude=16'd1909;
            10'd20:magnitude=16'd2009;
            10'd21:magnitude=16'd2110;
            10'd22:magnitude=16'd2210;
            10'd23:magnitude=16'd2310;
            10'd24:magnitude=16'd2410;
            10'd25:magnitude=16'd2511;
            10'd26:magnitude=16'd2611;
            10'd27:magnitude=16'd2711;
            10'd28:magnitude=16'd2811;
            10'd29:magnitude=16'd2911;
            10'd30:magnitude=16'd3012;
            10'd31:magnitude=16'd3112;
            10'd32:magnitude=16'd3212;
            10'd33:magnitude=16'd3312;
            10'd34:magnitude=16'd3412;
            10'd35:magnitude=16'd3512;
            10'd36:magnitude=16'd3612;
            10'd37:magnitude=16'd3712;
            10'd38:magnitude=16'd3811;
            10'd39:magnitude=16'd3911;
            10'd40:magnitude=16'd4011;
            10'd41:magnitude=16'd4111;
            10'd42:magnitude=16'd4210;
            10'd43:magnitude=16'd4310;
            10'd44:magnitude=16'd4410;
            10'd45:magnitude=16'd4509;
            10'd46:magnitude=16'd4609;
            10'd47:magnitude=16'd4708;
            10'd48:magnitude=16'd4808;
            10'd49:magnitude=16'd4907;
            10'd50:magnitude=16'd5007;
            10'd51:magnitude=16'd5106;
            10'd52:magnitude=16'd5205;
            10'd53:magnitude=16'd5305;
            10'd54:magnitude=16'd5404;
            10'd55:magnitude=16'd5503;
            10'd56:magnitude=16'd5602;
            10'd57:magnitude=16'd5701;
            10'd58:magnitude=16'd5800;
            10'd59:magnitude=16'd5899;
            10'd60:magnitude=16'd5998;
            10'd61:magnitude=16'd6096;
            10'd62:magnitude=16'd6195;
            10'd63:magnitude=16'd6294;
            10'd64:magnitude=16'd6393;
            10'd65:magnitude=16'd6491;
            10'd66:magnitude=16'd6590;
            10'd67:magnitude=16'd6688;
            10'd68:magnitude=16'd6786;
            10'd69:magnitude=16'd6885;
            10'd70:magnitude=16'd6983;
            10'd71:magnitude=16'd7081;
            10'd72:magnitude=16'd7179;
            10'd73:magnitude=16'd7277;
            10'd74:magnitude=16'd7375;
            10'd75:magnitude=16'd7473;
            10'd76:magnitude=16'd7571;
            10'd77:magnitude=16'd7669;
            10'd78:magnitude=16'd7767;
            10'd79:magnitude=16'd7864;
            10'd80:magnitude=16'd7962;
            10'd81:magnitude=16'd8059;
            10'd82:magnitude=16'd8157;
            10'd83:magnitude=16'd8254;
            10'd84:magnitude=16'd8351;
            10'd85:magnitude=16'd8448;
            10'd86:magnitude=16'd8545;
            10'd87:magnitude=16'd8642;
            10'd88:magnitude=16'd8739;
            10'd89:magnitude=16'd8836;
            10'd90:magnitude=16'd8933;
            10'd91:magnitude=16'd9030;
            10'd92:magnitude=16'd9126;
            10'd93:magnitude=16'd9223;
            10'd94:magnitude=16'd9319;
            10'd95:magnitude=16'd9416;
            10'd96:magnitude=16'd9512;
            10'd97:magnitude=16'd9608;
            10'd98:magnitude=16'd9704;
            10'd99:magnitude=16'd9800;
            10'd100:magnitude=16'd9896;
            10'd101:magnitude=16'd9992;
            10'd102:magnitude=16'd10087;
            10'd103:magnitude=16'd10183;
            10'd104:magnitude=16'd10278;
            10'd105:magnitude=16'd10374;
            10'd106:magnitude=16'd10469;
            10'd107:magnitude=16'd10564;
            10'd108:magnitude=16'd10659;
            10'd109:magnitude=16'd10754;
            10'd110:magnitude=16'd10849;
            10'd111:magnitude=16'd10944;
            10'd112:magnitude=16'd11039;
            10'd113:magnitude=16'd11133;
            10'd114:magnitude=16'd11228;
            10'd115:magnitude=16'd11322;
            10'd116:magnitude=16'd11417;
            10'd117:magnitude=16'd11511;
            10'd118:magnitude=16'd11605;
            10'd119:magnitude=16'd11699;
            10'd120:magnitude=16'd11793;
            10'd121:magnitude=16'd11886;
            10'd122:magnitude=16'd11980;
            10'd123:magnitude=16'd12074;
            10'd124:magnitude=16'd12167;
            10'd125:magnitude=16'd12260;
            10'd126:magnitude=16'd12353;
            10'd127:magnitude=16'd12446;
            10'd128:magnitude=16'd12539;
            10'd129:magnitude=16'd12632;
            10'd130:magnitude=16'd12725;
            10'd131:magnitude=16'd12817;
            10'd132:magnitude=16'd12910;
            10'd133:magnitude=16'd13002;
            10'd134:magnitude=16'd13094;
            10'd135:magnitude=16'd13187;
            10'd136:magnitude=16'd13279;
            10'd137:magnitude=16'd13370;
            10'd138:magnitude=16'd13462;
            10'd139:magnitude=16'd13554;
            10'd140:magnitude=16'd13645;
            10'd141:magnitude=16'd13736;
            10'd142:magnitude=16'd13828;
            10'd143:magnitude=16'd13919;
            10'd144:magnitude=16'd14010;
            10'd145:magnitude=16'd14101;
            10'd146:magnitude=16'd14191;
            10'd147:magnitude=16'd14282;
            10'd148:magnitude=16'd14372;
            10'd149:magnitude=16'd14462;
            10'd150:magnitude=16'd14553;
            10'd151:magnitude=16'd14643;
            10'd152:magnitude=16'd14732;
            10'd153:magnitude=16'd14822;
            10'd154:magnitude=16'd14912;
            10'd155:magnitude=16'd15001;
            10'd156:magnitude=16'd15090;
            10'd157:magnitude=16'd15180;
            10'd158:magnitude=16'd15269;
            10'd159:magnitude=16'd15358;
            10'd160:magnitude=16'd15446;
            10'd161:magnitude=16'd15535;
            10'd162:magnitude=16'd15623;
            10'd163:magnitude=16'd15712;
            10'd164:magnitude=16'd15800;
            10'd165:magnitude=16'd15888;
            10'd166:magnitude=16'd15976;
            10'd167:magnitude=16'd16063;
            10'd168:magnitude=16'd16151;
            10'd169:magnitude=16'd16238;
            10'd170:magnitude=16'd16325;
            10'd171:magnitude=16'd16413;
            10'd172:magnitude=16'd16499;
            10'd173:magnitude=16'd16586;
            10'd174:magnitude=16'd16673;
            10'd175:magnitude=16'd16759;
            10'd176:magnitude=16'd16846;
            10'd177:magnitude=16'd16932;
            10'd178:magnitude=16'd17018;
            10'd179:magnitude=16'd17104;
            10'd180:magnitude=16'd17189;
            10'd181:magnitude=16'd17275;
            10'd182:magnitude=16'd17360;
            10'd183:magnitude=16'd17445;
            10'd184:magnitude=16'd17530;
            10'd185:magnitude=16'd17615;
            10'd186:magnitude=16'd17700;
            10'd187:magnitude=16'd17784;
            10'd188:magnitude=16'd17869;
            10'd189:magnitude=16'd17953;
            10'd190:magnitude=16'd18037;
            10'd191:magnitude=16'd18121;
            10'd192:magnitude=16'd18204;
            10'd193:magnitude=16'd18288;
            10'd194:magnitude=16'd18371;
            10'd195:magnitude=16'd18454;
            10'd196:magnitude=16'd18537;
            10'd197:magnitude=16'd18620;
            10'd198:magnitude=16'd18703;
            10'd199:magnitude=16'd18785;
            10'd200:magnitude=16'd18868;
            10'd201:magnitude=16'd18950;
            10'd202:magnitude=16'd19032;
            10'd203:magnitude=16'd19113;
            10'd204:magnitude=16'd19195;
            10'd205:magnitude=16'd19276;
            10'd206:magnitude=16'd19357;
            10'd207:magnitude=16'd19438;
            10'd208:magnitude=16'd19519;
            10'd209:magnitude=16'd19600;
            10'd210:magnitude=16'd19680;
            10'd211:magnitude=16'd19761;
            10'd212:magnitude=16'd19841;
            10'd213:magnitude=16'd19921;
            10'd214:magnitude=16'd20000;
            10'd215:magnitude=16'd20080;
            10'd216:magnitude=16'd20159;
            10'd217:magnitude=16'd20238;
            10'd218:magnitude=16'd20317;
            10'd219:magnitude=16'd20396;
            10'd220:magnitude=16'd20475;
            10'd221:magnitude=16'd20553;
            10'd222:magnitude=16'd20631;
            10'd223:magnitude=16'd20709;
            10'd224:magnitude=16'd20787;
            10'd225:magnitude=16'd20865;
            10'd226:magnitude=16'd20942;
            10'd227:magnitude=16'd21019;
            10'd228:magnitude=16'd21096;
            10'd229:magnitude=16'd21173;
            10'd230:magnitude=16'd21250;
            10'd231:magnitude=16'd21326;
            10'd232:magnitude=16'd21403;
            10'd233:magnitude=16'd21479;
            10'd234:magnitude=16'd21554;
            10'd235:magnitude=16'd21630;
            10'd236:magnitude=16'd21705;
            10'd237:magnitude=16'd21781;
            10'd238:magnitude=16'd21856;
            10'd239:magnitude=16'd21930;
            10'd240:magnitude=16'd22005;
            10'd241:magnitude=16'd22079;
            10'd242:magnitude=16'd22154;
            10'd243:magnitude=16'd22227;
            10'd244:magnitude=16'd22301;
            10'd245:magnitude=16'd22375;
            10'd246:magnitude=16'd22448;
            10'd247:magnitude=16'd22521;
            10'd248:magnitude=16'd22594;
            10'd249:magnitude=16'd22667;
            10'd250:magnitude=16'd22739;
            10'd251:magnitude=16'd22812;
            10'd252:magnitude=16'd22884;
            10'd253:magnitude=16'd22956;
            10'd254:magnitude=16'd23027;
            10'd255:magnitude=16'd23099;
            10'd256:magnitude=16'd23170;
            10'd257:magnitude=16'd23241;
            10'd258:magnitude=16'd23311;
            10'd259:magnitude=16'd23382;
            10'd260:magnitude=16'd23452;
            10'd261:magnitude=16'd23522;
            10'd262:magnitude=16'd23592;
            10'd263:magnitude=16'd23662;
            10'd264:magnitude=16'd23731;
            10'd265:magnitude=16'd23801;
            10'd266:magnitude=16'd23870;
            10'd267:magnitude=16'd23938;
            10'd268:magnitude=16'd24007;
            10'd269:magnitude=16'd24075;
            10'd270:magnitude=16'd24143;
            10'd271:magnitude=16'd24211;
            10'd272:magnitude=16'd24279;
            10'd273:magnitude=16'd24346;
            10'd274:magnitude=16'd24413;
            10'd275:magnitude=16'd24480;
            10'd276:magnitude=16'd24547;
            10'd277:magnitude=16'd24613;
            10'd278:magnitude=16'd24680;
            10'd279:magnitude=16'd24746;
            10'd280:magnitude=16'd24811;
            10'd281:magnitude=16'd24877;
            10'd282:magnitude=16'd24942;
            10'd283:magnitude=16'd25007;
            10'd284:magnitude=16'd25072;
            10'd285:magnitude=16'd25137;
            10'd286:magnitude=16'd25201;
            10'd287:magnitude=16'd25265;
            10'd288:magnitude=16'd25329;
            10'd289:magnitude=16'd25393;
            10'd290:magnitude=16'd25456;
            10'd291:magnitude=16'd25519;
            10'd292:magnitude=16'd25582;
            10'd293:magnitude=16'd25645;
            10'd294:magnitude=16'd25708;
            10'd295:magnitude=16'd25770;
            10'd296:magnitude=16'd25832;
            10'd297:magnitude=16'd25893;
            10'd298:magnitude=16'd25955;
            10'd299:magnitude=16'd26016;
            10'd300:magnitude=16'd26077;
            10'd301:magnitude=16'd26138;
            10'd302:magnitude=16'd26198;
            10'd303:magnitude=16'd26259;
            10'd304:magnitude=16'd26319;
            10'd305:magnitude=16'd26378;
            10'd306:magnitude=16'd26438;
            10'd307:magnitude=16'd26497;
            10'd308:magnitude=16'd26556;
            10'd309:magnitude=16'd26615;
            10'd310:magnitude=16'd26674;
            10'd311:magnitude=16'd26732;
            10'd312:magnitude=16'd26790;
            10'd313:magnitude=16'd26848;
            10'd314:magnitude=16'd26905;
            10'd315:magnitude=16'd26962;
            10'd316:magnitude=16'd27019;
            10'd317:magnitude=16'd27076;
            10'd318:magnitude=16'd27133;
            10'd319:magnitude=16'd27189;
            10'd320:magnitude=16'd27245;
            10'd321:magnitude=16'd27300;
            10'd322:magnitude=16'd27356;
            10'd323:magnitude=16'd27411;
            10'd324:magnitude=16'd27466;
            10'd325:magnitude=16'd27521;
            10'd326:magnitude=16'd27575;
            10'd327:magnitude=16'd27629;
            10'd328:magnitude=16'd27683;
            10'd329:magnitude=16'd27737;
            10'd330:magnitude=16'd27790;
            10'd331:magnitude=16'd27843;
            10'd332:magnitude=16'd27896;
            10'd333:magnitude=16'd27949;
            10'd334:magnitude=16'd28001;
            10'd335:magnitude=16'd28053;
            10'd336:magnitude=16'd28105;
            10'd337:magnitude=16'd28157;
            10'd338:magnitude=16'd28208;
            10'd339:magnitude=16'd28259;
            10'd340:magnitude=16'd28310;
            10'd341:magnitude=16'd28360;
            10'd342:magnitude=16'd28411;
            10'd343:magnitude=16'd28460;
            10'd344:magnitude=16'd28510;
            10'd345:magnitude=16'd28560;
            10'd346:magnitude=16'd28609;
            10'd347:magnitude=16'd28658;
            10'd348:magnitude=16'd28706;
            10'd349:magnitude=16'd28755;
            10'd350:magnitude=16'd28803;
            10'd351:magnitude=16'd28850;
            10'd352:magnitude=16'd28898;
            10'd353:magnitude=16'd28945;
            10'd354:magnitude=16'd28992;
            10'd355:magnitude=16'd29039;
            10'd356:magnitude=16'd29085;
            10'd357:magnitude=16'd29131;
            10'd358:magnitude=16'd29177;
            10'd359:magnitude=16'd29223;
            10'd360:magnitude=16'd29268;
            10'd361:magnitude=16'd29313;
            10'd362:magnitude=16'd29358;
            10'd363:magnitude=16'd29403;
            10'd364:magnitude=16'd29447;
            10'd365:magnitude=16'd29491;
            10'd366:magnitude=16'd29534;
            10'd367:magnitude=16'd29578;
            10'd368:magnitude=16'd29621;
            10'd369:magnitude=16'd29664;
            10'd370:magnitude=16'd29706;
            10'd371:magnitude=16'd29749;
            10'd372:magnitude=16'd29791;
            10'd373:magnitude=16'd29832;
            10'd374:magnitude=16'd29874;
            10'd375:magnitude=16'd29915;
            10'd376:magnitude=16'd29956;
            10'd377:magnitude=16'd29997;
            10'd378:magnitude=16'd30037;
            10'd379:magnitude=16'd30077;
            10'd380:magnitude=16'd30117;
            10'd381:magnitude=16'd30156;
            10'd382:magnitude=16'd30195;
            10'd383:magnitude=16'd30234;
            10'd384:magnitude=16'd30273;
            10'd385:magnitude=16'd30311;
            10'd386:magnitude=16'd30349;
            10'd387:magnitude=16'd30387;
            10'd388:magnitude=16'd30424;
            10'd389:magnitude=16'd30462;
            10'd390:magnitude=16'd30498;
            10'd391:magnitude=16'd30535;
            10'd392:magnitude=16'd30571;
            10'd393:magnitude=16'd30607;
            10'd394:magnitude=16'd30643;
            10'd395:magnitude=16'd30679;
            10'd396:magnitude=16'd30714;
            10'd397:magnitude=16'd30749;
            10'd398:magnitude=16'd30783;
            10'd399:magnitude=16'd30818;
            10'd400:magnitude=16'd30852;
            10'd401:magnitude=16'd30885;
            10'd402:magnitude=16'd30919;
            10'd403:magnitude=16'd30952;
            10'd404:magnitude=16'd30985;
            10'd405:magnitude=16'd31017;
            10'd406:magnitude=16'd31050;
            10'd407:magnitude=16'd31082;
            10'd408:magnitude=16'd31113;
            10'd409:magnitude=16'd31145;
            10'd410:magnitude=16'd31176;
            10'd411:magnitude=16'd31206;
            10'd412:magnitude=16'd31237;
            10'd413:magnitude=16'd31267;
            10'd414:magnitude=16'd31297;
            10'd415:magnitude=16'd31327;
            10'd416:magnitude=16'd31356;
            10'd417:magnitude=16'd31385;
            10'd418:magnitude=16'd31414;
            10'd419:magnitude=16'd31442;
            10'd420:magnitude=16'd31470;
            10'd421:magnitude=16'd31498;
            10'd422:magnitude=16'd31526;
            10'd423:magnitude=16'd31553;
            10'd424:magnitude=16'd31580;
            10'd425:magnitude=16'd31607;
            10'd426:magnitude=16'd31633;
            10'd427:magnitude=16'd31659;
            10'd428:magnitude=16'd31685;
            10'd429:magnitude=16'd31710;
            10'd430:magnitude=16'd31736;
            10'd431:magnitude=16'd31760;
            10'd432:magnitude=16'd31785;
            10'd433:magnitude=16'd31809;
            10'd434:magnitude=16'd31833;
            10'd435:magnitude=16'd31857;
            10'd436:magnitude=16'd31880;
            10'd437:magnitude=16'd31903;
            10'd438:magnitude=16'd31926;
            10'd439:magnitude=16'd31949;
            10'd440:magnitude=16'd31971;
            10'd441:magnitude=16'd31993;
            10'd442:magnitude=16'd32014;
            10'd443:magnitude=16'd32036;
            10'd444:magnitude=16'd32057;
            10'd445:magnitude=16'd32077;
            10'd446:magnitude=16'd32098;
            10'd447:magnitude=16'd32118;
            10'd448:magnitude=16'd32137;
            10'd449:magnitude=16'd32157;
            10'd450:magnitude=16'd32176;
            10'd451:magnitude=16'd32195;
            10'd452:magnitude=16'd32213;
            10'd453:magnitude=16'd32232;
            10'd454:magnitude=16'd32250;
            10'd455:magnitude=16'd32267;
            10'd456:magnitude=16'd32285;
            10'd457:magnitude=16'd32302;
            10'd458:magnitude=16'd32318;
            10'd459:magnitude=16'd32335;
            10'd460:magnitude=16'd32351;
            10'd461:magnitude=16'd32367;
            10'd462:magnitude=16'd32382;
            10'd463:magnitude=16'd32397;
            10'd464:magnitude=16'd32412;
            10'd465:magnitude=16'd32427;
            10'd466:magnitude=16'd32441;
            10'd467:magnitude=16'd32455;
            10'd468:magnitude=16'd32469;
            10'd469:magnitude=16'd32482;
            10'd470:magnitude=16'd32495;
            10'd471:magnitude=16'd32508;
            10'd472:magnitude=16'd32521;
            10'd473:magnitude=16'd32533;
            10'd474:magnitude=16'd32545;
            10'd475:magnitude=16'd32556;
            10'd476:magnitude=16'd32567;
            10'd477:magnitude=16'd32578;
            10'd478:magnitude=16'd32589;
            10'd479:magnitude=16'd32599;
            10'd480:magnitude=16'd32609;
            10'd481:magnitude=16'd32619;
            10'd482:magnitude=16'd32628;
            10'd483:magnitude=16'd32637;
            10'd484:magnitude=16'd32646;
            10'd485:magnitude=16'd32655;
            10'd486:magnitude=16'd32663;
            10'd487:magnitude=16'd32671;
            10'd488:magnitude=16'd32678;
            10'd489:magnitude=16'd32685;
            10'd490:magnitude=16'd32692;
            10'd491:magnitude=16'd32699;
            10'd492:magnitude=16'd32705;
            10'd493:magnitude=16'd32711;
            10'd494:magnitude=16'd32717;
            10'd495:magnitude=16'd32722;
            10'd496:magnitude=16'd32728;
            10'd497:magnitude=16'd32732;
            10'd498:magnitude=16'd32737;
            10'd499:magnitude=16'd32741;
            10'd500:magnitude=16'd32745;
            10'd501:magnitude=16'd32748;
            10'd502:magnitude=16'd32752;
            10'd503:magnitude=16'd32755;
            10'd504:magnitude=16'd32757;
            10'd505:magnitude=16'd32759;
            10'd506:magnitude=16'd32761;
            10'd507:magnitude=16'd32763;
            10'd508:magnitude=16'd32765;
            10'd509:magnitude=16'd32766;
            10'd510:magnitude=16'd32766;
            10'd511:magnitude=16'd32767;
            10'd512:magnitude=16'd32767;
            default:magnitude=0;
        endcase
        value=phase[10] ? -$signed(magnitude):$signed(magnitude);
    end
endmodule

module audio_monitor_band(input wire [7:0] address,output reg [10:0] low_bin,high_bin);
    always @*case(address)
        8'd0:begin low_bin=11'd17;high_bin=11'd17;end
        8'd1:begin low_bin=11'd17;high_bin=11'd17;end
        8'd2:begin low_bin=11'd17;high_bin=11'd18;end
        8'd3:begin low_bin=11'd18;high_bin=11'd18;end
        8'd4:begin low_bin=11'd18;high_bin=11'd19;end
        8'd5:begin low_bin=11'd19;high_bin=11'd19;end
        8'd6:begin low_bin=11'd19;high_bin=11'd19;end
        8'd7:begin low_bin=11'd19;high_bin=11'd20;end
        8'd8:begin low_bin=11'd20;high_bin=11'd20;end
        8'd9:begin low_bin=11'd20;high_bin=11'd21;end
        8'd10:begin low_bin=11'd21;high_bin=11'd21;end
        8'd11:begin low_bin=11'd21;high_bin=11'd22;end
        8'd12:begin low_bin=11'd22;high_bin=11'd22;end
        8'd13:begin low_bin=11'd22;high_bin=11'd23;end
        8'd14:begin low_bin=11'd23;high_bin=11'd23;end
        8'd15:begin low_bin=11'd23;high_bin=11'd24;end
        8'd16:begin low_bin=11'd24;high_bin=11'd24;end
        8'd17:begin low_bin=11'd24;high_bin=11'd25;end
        8'd18:begin low_bin=11'd25;high_bin=11'd25;end
        8'd19:begin low_bin=11'd25;high_bin=11'd26;end
        8'd20:begin low_bin=11'd26;high_bin=11'd26;end
        8'd21:begin low_bin=11'd26;high_bin=11'd27;end
        8'd22:begin low_bin=11'd27;high_bin=11'd27;end
        8'd23:begin low_bin=11'd27;high_bin=11'd28;end
        8'd24:begin low_bin=11'd28;high_bin=11'd29;end
        8'd25:begin low_bin=11'd29;high_bin=11'd29;end
        8'd26:begin low_bin=11'd29;high_bin=11'd30;end
        8'd27:begin low_bin=11'd30;high_bin=11'd30;end
        8'd28:begin low_bin=11'd30;high_bin=11'd31;end
        8'd29:begin low_bin=11'd31;high_bin=11'd32;end
        8'd30:begin low_bin=11'd32;high_bin=11'd32;end
        8'd31:begin low_bin=11'd32;high_bin=11'd33;end
        8'd32:begin low_bin=11'd33;high_bin=11'd34;end
        8'd33:begin low_bin=11'd34;high_bin=11'd35;end
        8'd34:begin low_bin=11'd35;high_bin=11'd35;end
        8'd35:begin low_bin=11'd35;high_bin=11'd36;end
        8'd36:begin low_bin=11'd36;high_bin=11'd37;end
        8'd37:begin low_bin=11'd37;high_bin=11'd38;end
        8'd38:begin low_bin=11'd38;high_bin=11'd39;end
        8'd39:begin low_bin=11'd39;high_bin=11'd39;end
        8'd40:begin low_bin=11'd39;high_bin=11'd40;end
        8'd41:begin low_bin=11'd40;high_bin=11'd41;end
        8'd42:begin low_bin=11'd41;high_bin=11'd42;end
        8'd43:begin low_bin=11'd42;high_bin=11'd43;end
        8'd44:begin low_bin=11'd43;high_bin=11'd44;end
        8'd45:begin low_bin=11'd44;high_bin=11'd45;end
        8'd46:begin low_bin=11'd45;high_bin=11'd46;end
        8'd47:begin low_bin=11'd46;high_bin=11'd47;end
        8'd48:begin low_bin=11'd47;high_bin=11'd48;end
        8'd49:begin low_bin=11'd48;high_bin=11'd49;end
        8'd50:begin low_bin=11'd49;high_bin=11'd50;end
        8'd51:begin low_bin=11'd50;high_bin=11'd51;end
        8'd52:begin low_bin=11'd51;high_bin=11'd52;end
        8'd53:begin low_bin=11'd52;high_bin=11'd53;end
        8'd54:begin low_bin=11'd53;high_bin=11'd54;end
        8'd55:begin low_bin=11'd54;high_bin=11'd56;end
        8'd56:begin low_bin=11'd56;high_bin=11'd57;end
        8'd57:begin low_bin=11'd57;high_bin=11'd58;end
        8'd58:begin low_bin=11'd58;high_bin=11'd59;end
        8'd59:begin low_bin=11'd59;high_bin=11'd61;end
        8'd60:begin low_bin=11'd61;high_bin=11'd62;end
        8'd61:begin low_bin=11'd62;high_bin=11'd63;end
        8'd62:begin low_bin=11'd63;high_bin=11'd65;end
        8'd63:begin low_bin=11'd65;high_bin=11'd66;end
        8'd64:begin low_bin=11'd66;high_bin=11'd68;end
        8'd65:begin low_bin=11'd68;high_bin=11'd69;end
        8'd66:begin low_bin=11'd69;high_bin=11'd71;end
        8'd67:begin low_bin=11'd71;high_bin=11'd72;end
        8'd68:begin low_bin=11'd72;high_bin=11'd74;end
        8'd69:begin low_bin=11'd74;high_bin=11'd76;end
        8'd70:begin low_bin=11'd76;high_bin=11'd77;end
        8'd71:begin low_bin=11'd77;high_bin=11'd79;end
        8'd72:begin low_bin=11'd79;high_bin=11'd81;end
        8'd73:begin low_bin=11'd81;high_bin=11'd82;end
        8'd74:begin low_bin=11'd82;high_bin=11'd84;end
        8'd75:begin low_bin=11'd84;high_bin=11'd86;end
        8'd76:begin low_bin=11'd86;high_bin=11'd88;end
        8'd77:begin low_bin=11'd88;high_bin=11'd90;end
        8'd78:begin low_bin=11'd90;high_bin=11'd92;end
        8'd79:begin low_bin=11'd92;high_bin=11'd94;end
        8'd80:begin low_bin=11'd94;high_bin=11'd96;end
        8'd81:begin low_bin=11'd96;high_bin=11'd98;end
        8'd82:begin low_bin=11'd98;high_bin=11'd100;end
        8'd83:begin low_bin=11'd100;high_bin=11'd102;end
        8'd84:begin low_bin=11'd102;high_bin=11'd104;end
        8'd85:begin low_bin=11'd104;high_bin=11'd107;end
        8'd86:begin low_bin=11'd107;high_bin=11'd109;end
        8'd87:begin low_bin=11'd109;high_bin=11'd111;end
        8'd88:begin low_bin=11'd111;high_bin=11'd114;end
        8'd89:begin low_bin=11'd114;high_bin=11'd116;end
        8'd90:begin low_bin=11'd116;high_bin=11'd118;end
        8'd91:begin low_bin=11'd118;high_bin=11'd121;end
        8'd92:begin low_bin=11'd121;high_bin=11'd124;end
        8'd93:begin low_bin=11'd124;high_bin=11'd126;end
        8'd94:begin low_bin=11'd126;high_bin=11'd129;end
        8'd95:begin low_bin=11'd129;high_bin=11'd132;end
        8'd96:begin low_bin=11'd132;high_bin=11'd135;end
        8'd97:begin low_bin=11'd135;high_bin=11'd138;end
        8'd98:begin low_bin=11'd138;high_bin=11'd140;end
        8'd99:begin low_bin=11'd140;high_bin=11'd144;end
        8'd100:begin low_bin=11'd144;high_bin=11'd147;end
        8'd101:begin low_bin=11'd147;high_bin=11'd150;end
        8'd102:begin low_bin=11'd150;high_bin=11'd153;end
        8'd103:begin low_bin=11'd153;high_bin=11'd157;end
        8'd104:begin low_bin=11'd157;high_bin=11'd160;end
        8'd105:begin low_bin=11'd160;high_bin=11'd164;end
        8'd106:begin low_bin=11'd164;high_bin=11'd167;end
        8'd107:begin low_bin=11'd167;high_bin=11'd171;end
        8'd108:begin low_bin=11'd171;high_bin=11'd175;end
        8'd109:begin low_bin=11'd175;high_bin=11'd178;end
        8'd110:begin low_bin=11'd178;high_bin=11'd182;end
        8'd111:begin low_bin=11'd182;high_bin=11'd186;end
        8'd112:begin low_bin=11'd186;high_bin=11'd190;end
        8'd113:begin low_bin=11'd190;high_bin=11'd194;end
        8'd114:begin low_bin=11'd194;high_bin=11'd199;end
        8'd115:begin low_bin=11'd199;high_bin=11'd203;end
        8'd116:begin low_bin=11'd203;high_bin=11'd207;end
        8'd117:begin low_bin=11'd207;high_bin=11'd212;end
        8'd118:begin low_bin=11'd212;high_bin=11'd216;end
        8'd119:begin low_bin=11'd216;high_bin=11'd221;end
        8'd120:begin low_bin=11'd221;high_bin=11'd226;end
        8'd121:begin low_bin=11'd226;high_bin=11'd230;end
        8'd122:begin low_bin=11'd230;high_bin=11'd235;end
        8'd123:begin low_bin=11'd235;high_bin=11'd241;end
        8'd124:begin low_bin=11'd241;high_bin=11'd246;end
        8'd125:begin low_bin=11'd246;high_bin=11'd251;end
        8'd126:begin low_bin=11'd251;high_bin=11'd257;end
        8'd127:begin low_bin=11'd257;high_bin=11'd262;end
        8'd128:begin low_bin=11'd262;high_bin=11'd268;end
        8'd129:begin low_bin=11'd268;high_bin=11'd274;end
        8'd130:begin low_bin=11'd274;high_bin=11'd280;end
        8'd131:begin low_bin=11'd280;high_bin=11'd286;end
        8'd132:begin low_bin=11'd286;high_bin=11'd292;end
        8'd133:begin low_bin=11'd292;high_bin=11'd298;end
        8'd134:begin low_bin=11'd298;high_bin=11'd305;end
        8'd135:begin low_bin=11'd305;high_bin=11'd311;end
        8'd136:begin low_bin=11'd311;high_bin=11'd318;end
        8'd137:begin low_bin=11'd318;high_bin=11'd325;end
        8'd138:begin low_bin=11'd325;high_bin=11'd332;end
        8'd139:begin low_bin=11'd332;high_bin=11'd339;end
        8'd140:begin low_bin=11'd339;high_bin=11'd347;end
        8'd141:begin low_bin=11'd347;high_bin=11'd354;end
        8'd142:begin low_bin=11'd354;high_bin=11'd362;end
        8'd143:begin low_bin=11'd362;high_bin=11'd370;end
        8'd144:begin low_bin=11'd370;high_bin=11'd378;end
        8'd145:begin low_bin=11'd378;high_bin=11'd386;end
        8'd146:begin low_bin=11'd386;high_bin=11'd394;end
        8'd147:begin low_bin=11'd394;high_bin=11'd403;end
        8'd148:begin low_bin=11'd403;high_bin=11'd411;end
        8'd149:begin low_bin=11'd411;high_bin=11'd420;end
        8'd150:begin low_bin=11'd420;high_bin=11'd429;end
        8'd151:begin low_bin=11'd429;high_bin=11'd439;end
        8'd152:begin low_bin=11'd439;high_bin=11'd448;end
        8'd153:begin low_bin=11'd448;high_bin=11'd458;end
        8'd154:begin low_bin=11'd458;high_bin=11'd468;end
        8'd155:begin low_bin=11'd468;high_bin=11'd478;end
        8'd156:begin low_bin=11'd478;high_bin=11'd489;end
        8'd157:begin low_bin=11'd489;high_bin=11'd499;end
        8'd158:begin low_bin=11'd499;high_bin=11'd510;end
        8'd159:begin low_bin=11'd510;high_bin=11'd521;end
        8'd160:begin low_bin=11'd521;high_bin=11'd532;end
        8'd161:begin low_bin=11'd532;high_bin=11'd544;end
        8'd162:begin low_bin=11'd544;high_bin=11'd556;end
        8'd163:begin low_bin=11'd556;high_bin=11'd568;end
        8'd164:begin low_bin=11'd568;high_bin=11'd580;end
        8'd165:begin low_bin=11'd580;high_bin=11'd592;end
        8'd166:begin low_bin=11'd592;high_bin=11'd605;end
        8'd167:begin low_bin=11'd605;high_bin=11'd618;end
        8'd168:begin low_bin=11'd618;high_bin=11'd632;end
        8'd169:begin low_bin=11'd632;high_bin=11'd646;end
        8'd170:begin low_bin=11'd646;high_bin=11'd660;end
        8'd171:begin low_bin=11'd660;high_bin=11'd674;end
        8'd172:begin low_bin=11'd674;high_bin=11'd688;end
        8'd173:begin low_bin=11'd688;high_bin=11'd703;end
        8'd174:begin low_bin=11'd703;high_bin=11'd719;end
        8'd175:begin low_bin=11'd719;high_bin=11'd734;end
        8'd176:begin low_bin=11'd734;high_bin=11'd750;end
        8'd177:begin low_bin=11'd750;high_bin=11'd767;end
        8'd178:begin low_bin=11'd767;high_bin=11'd783;end
        8'd179:begin low_bin=11'd783;high_bin=11'd800;end
        8'd180:begin low_bin=11'd800;high_bin=11'd817;end
        8'd181:begin low_bin=11'd817;high_bin=11'd835;end
        8'd182:begin low_bin=11'd835;high_bin=11'd853;end
        8'd183:begin low_bin=11'd853;high_bin=11'd872;end
        8'd184:begin low_bin=11'd872;high_bin=11'd890;end
        8'd185:begin low_bin=11'd890;high_bin=11'd910;end
        8'd186:begin low_bin=11'd910;high_bin=11'd930;end
        8'd187:begin low_bin=11'd930;high_bin=11'd950;end
        8'd188:begin low_bin=11'd950;high_bin=11'd970;end
        8'd189:begin low_bin=11'd970;high_bin=11'd991;end
        8'd190:begin low_bin=11'd991;high_bin=11'd1012;end
        8'd191:begin low_bin=11'd1012;high_bin=11'd1023;end
        default:begin low_bin=0;high_bin=0;end
    endcase
endmodule
