`timescale 1ns/1ps
// Frame-driven, single-clock renderer with independent label/value text runs.
// A common right edge keeps both languages and all numeric widths aligned.
module keyboard_menu_renderer #(parameter integer ENABLE_PRACTICE=0)(
    input wire clk,rst_n,init_done,
    input wire [7:0] song_selection,input wire [8:0] song_count,input wire [7:0] title_revision,
    input wire title_pending,ascii_title_valid,input wire [127:0] ascii_title,
    input wire playback_mode,bundle_choosing,input wire [63:0] bundle_text,input wire [31:0] bundle_skipped,
    input wire title_valid,input wire [5:0] title_count,output reg [4:0] title_index,output reg [4:0] title_row,title_column,input wire title_ink,
    input wire [1:0] practice_screen,practice_countdown,
    input wire [127:0] drum_config,
    input wire [1:0] drum_online,drum_calibrated,
    input wire [7:0] drum_cal_state,
    input wire [31:0] drum_bus_info,input wire [15:0] drum_bus_error,input wire [1:0] drum_inserted,
    input wire [255:0] offline_result_text,
    input wire offline_active,input wire [7:0] offline_state,offline_error,input wire [63:0] offline_name,
    input wire [2:0] main_view,
    input wire lissajous_pixel,lissajous_valid,
    input wire [7:0] lissajous_frame,
    output wire [13:0] lissajous_address,
    output wire lissajous_lock,
    input wire [1:0] menu_level,
    input wire [15:0] response_us,
    input wire response_valid,response_busy,
    input wire [1:0] drum_active,drum_pose_fault,
    input wire scope_valid,spectrum_valid,
    input wire [7:0] scope_frame,spectrum_frame,scope_y,spectrum_height,
    output wire [7:0] scope_address,spectrum_address,
    output wire scope_lock,spectrum_lock,
    input wire [4:0] selected,
    input wire editing,
    input wire [6:0] volume_percent,echo_percent,joy_percent,
    input wire [5:0] light_brightness,
    input wire [3:0] timbre_sel,
    input wire [1:0] light_mode,audio_input_mask,
    input wire language_cn,metro_enable,
    input wire [3:0] metro_beats,metro_unit,
    input wire [7:0] metro_bpm,
    output wire draw_valid,
    input wire draw_ready,
    output wire [7:0] x0,y0,x1,y1,
    output wire fill_mode,
    output wire [15:0] fill_color,
    output wire pixel_valid,
    input wire pixel_ready,
    output wire [15:0] pixel_rgb565,
    input wire draw_done,draw_error
);
    localparam [3:0] IDLE=0,PREPARE=1,DIGITS=2,FORMAT=3,REQUEST=4,
        FETCH=5,ADDRESS=6,GLYPH=7,STREAM=8,DRAIN=9,ROW_DATA=10,ROW_COORDS=11,VALUE_LENGTH=12,VALUE_POSITION=13;
    localparam [15:0] BG=16'h0841,PANEL=16'h10C3,TEXT=16'hDEFB,
        DIM=16'h738E,CYAN=16'h07FF,AMBER=16'hFD20,GRID=16'h10A2,
        GLOW=16'h0352,FILL=16'h016B,EDGE=16'h9FFF,ORANGE=16'hFD20;
    reg [3:0] state;
    reg have_snapshot,snap_scope_valid,snap_spectrum_valid;
    reg [127:0] snap_drum;
    reg [31:0] snap_bus_info;
    reg [7:0] snap_cal_state;reg [15:0] snap_bus_error;reg [1:0] snap_inserted;
    function [7:0] hex_digit(input [3:0] n);begin hex_digit=n<10 ? 8'h30+{4'd0,n}:8'h41+{4'd0,n}-8'd10;end endfunction
    reg [255:0] snap_result_text;reg snap_offline;reg [7:0] snap_offline_state,snap_offline_error;reg [63:0] snap_offline_name;
    reg [1:0] snap_online,snap_calibrated;

    reg [1:0] snap_level;
    reg [15:0] snap_response_us;reg snap_response_valid,snap_response_busy;
    reg [1:0] snap_drum_active,snap_pose_fault;
    reg [1:0] snap_input_mask;
    reg [2:0] snap_view;
    reg [1:0] snap_mode;
    reg snap_lissajous_valid;
    reg [7:0] snap_lissajous_frame;
    wire snap_menu=snap_view==2 || snap_view==3 || snap_view==5;
    wire live_menu=main_view==2 || main_view==3 || main_view==5;
    reg [4:0] snap_selected;
    reg snap_editing,snap_language_cn,snap_metro;
    reg [6:0] snap_volume,snap_echo,snap_joy;
    reg [5:0] snap_brightness;
    reg [3:0] snap_timbre,snap_beats,snap_unit;
    reg [7:0] snap_bpm,snap_scope_frame,snap_spectrum_frame;
    wire [1:0] active_practice=ENABLE_PRACTICE!=0 ? practice_screen:2'd0;
    reg [1:0] snap_practice,snap_countdown;
    reg [7:0] snap_title_revision;reg snap_title_valid,snap_title_pending,snap_ascii_valid;reg [127:0] snap_ascii_title;
    wire changed=title_revision!=snap_title_revision || title_valid!=snap_title_valid || title_pending!=snap_title_pending || ascii_title_valid!=snap_ascii_valid || ascii_title!=snap_ascii_title || title_offset!=snap_title_offset || title_pixel!=snap_title_pixel || bundle_choosing || offline_result_text!=snap_result_text || (main_view==5 && (response_us!=snap_response_us || response_valid!=snap_response_valid || response_busy!=snap_response_busy)) || (main_view==3 && (drum_active!=snap_drum_active || drum_pose_fault!=snap_pose_fault)) || offline_active!=snap_offline || (offline_active && (offline_state!=snap_offline_state || offline_error!=snap_offline_error || offline_name!=snap_offline_name)) || !have_snapshot || (main_view==3 && (drum_bus_info!=snap_bus_info || drum_bus_error!=snap_bus_error || drum_inserted!=snap_inserted || drum_cal_state!=snap_cal_state || drum_config!=snap_drum || drum_online!=snap_online || drum_calibrated!=snap_calibrated)) || active_practice!=snap_practice ||
        (active_practice!=0 && practice_countdown!=snap_countdown) || main_view!=snap_view || menu_level!=snap_level ||
        selected!=snap_selected || editing!=snap_editing || language_cn!=snap_language_cn ||
        volume_percent!=snap_volume || echo_percent!=snap_echo || joy_percent!=snap_joy ||
        audio_input_mask!=snap_input_mask || light_brightness!=snap_brightness || timbre_sel!=snap_timbre || light_mode!=snap_mode ||
        metro_enable!=snap_metro || metro_beats!=snap_beats || metro_unit!=snap_unit || metro_bpm!=snap_bpm ||
        (main_view==0 && (spectrum_frame!=snap_spectrum_frame || spectrum_valid!=snap_spectrum_valid)) ||
        (main_view==1 && (scope_frame!=snap_scope_frame || scope_valid!=snap_scope_valid)) ||
        (main_view==4 && (lissajous_frame!=snap_lissajous_frame || lissajous_valid!=snap_lissajous_valid));
    // Four fixed rows per root page: 1..4, 5..8, then 9.
    // METRO and each stick have child rows; unused root rows stay blank. Selection owns
    // the page in either direction; no hidden scroll offset can drift.
    // Position zero focuses the title and shows the first page.
    wire drum_right=snap_level==2;
    wire [7:0] selected_error=drum_right ? snap_bus_error[15:8]:snap_bus_error[7:0];
    wire [4:0] first_item=snap_view==3 ? (snap_level!=0 ? 5'd1:snap_selected==5 ? 5'd5:5'd1):
        snap_level!=0 ? 5'd1:snap_selected>=9 ? 5'd9:snap_selected>=5 ? 5'd5:5'd1;
    wire [4:0] selected_row=snap_offline ? 5'd0:snap_selected-first_item;
    reg [1:0] prep_row;

    wire [63:0] drum_bank=drum_right ? snap_drum[127:64]:snap_drum[63:0];
    wire [7:0] drum_voice=prep_row==0 ? drum_bank[7:0]:prep_row==1 ? drum_bank[15:8]:drum_bank[23:16];
    // Root IDs 0..8; metronome 9..12. INPUT is edited in its root row.
    wire [4:0] root_item=first_item+{3'd0,prep_row};
    wire [4:0] menu_item=snap_level==1 ? 5'd9+{3'd0,prep_row}:
        root_item<=9 ? root_item-5'd1:5'd31;
    reg [63:0] row_label[0:3],row_value[0:3];
    reg row_value_cn[0:3];
    reg [7:0] row_value_start[0:3];
    reg [63:0] prepared_label,prepared_value;
    reg prepared_value_cn;
    reg [3:0] value_length_q;reg value_cn_q;
    reg [7:0] numeric_value,binary_digits;
    reg [11:0] bcd,adjusted_bcd;
    reg [2:0] digit_count;
    function [3:0] text_length(input [63:0] text);
        integer n;
        begin
            text_length=0;
            for(n=0;n<8;n=n+1)
                if(text[63-n*8 -:8]!=8'd32 && text[63-n*8 -:8]!=0)text_length=n[3:0]+4'd1;
        end
    endfunction
    function [63:0] number_text(input [11:0] digits,input [7:0] value,input percent);
        reg [7:0] h,t,o;
        begin
            h=8'd48+{4'd0,digits[11:8]};t=8'd48+{4'd0,digits[7:4]};o=8'd48+{4'd0,digits[3:0]};
            if(percent)begin
                if(value>=100)number_text={h,t,o,"%","    "};
                else if(value>=10)number_text={t,o,"%","     "};
                else number_text={o,"%","      "};
            end else begin
                if(value>=100)number_text={h,t,o,"     "};
                else if(value>=10)number_text={t,o,"      "};
                else number_text={o,"       "};
            end
        end
    endfunction
    always @*begin
        adjusted_bcd=bcd;
        if(bcd[3:0]>=5)adjusted_bcd[3:0]=bcd[3:0]+4'd3;
        if(bcd[7:4]>=5)adjusted_bcd[7:4]=bcd[7:4]+4'd3;
        if(bcd[11:8]>=5)adjusted_bcd[11:8]=bcd[11:8]+4'd3;
        case(menu_item)
            0:numeric_value={1'b0,snap_volume};2:numeric_value={2'd0,snap_brightness};
            4:numeric_value={1'b0,snap_echo};5:numeric_value={1'b0,snap_joy};
            10:numeric_value={4'd0,snap_beats};11:numeric_value={4'd0,snap_unit};
            12:numeric_value=snap_bpm;default:numeric_value=0;
        endcase
    end
    reg [4:0] response_bit;reg [63:0] response_text;
    always @*begin
        prepared_label="        ";prepared_value="        ";prepared_value_cn=0;
        case(menu_item)
            0:begin prepared_label="VOLUME  ";prepared_value=number_text(bcd,numeric_value,1'b1);end
            1:begin
                prepared_label="SOUND   ";
                case(snap_timbre)
                    1:prepared_value="PIANO   ";2:prepared_value="ORGAN   ";
                    3:prepared_value="BELL    ";4:prepared_value="XYLO    ";
                    5:prepared_value="MARIMBR ";6:prepared_value="EPIANO  ";
                    7:prepared_value="PLUCK   ";8:prepared_value="FLUTE   ";
                    9:prepared_value="BASS    ";11:prepared_value="SNARE   ";
                    13:prepared_value="STRINGS ";14:prepared_value="VIOLIN  ";
                    default:prepared_value="PIANO   ";
                endcase
            end
            2:begin prepared_label="BRIGHT  ";prepared_value=number_text(bcd,numeric_value,1'b0);end
            3:begin prepared_label="LIGHT   ";prepared_value=snap_mode==0 ? "RIPPLE  ":snap_mode==1 ? "SOLID   ":"OFF     ";end
            4:begin prepared_label="REVERB  ";prepared_value=number_text(bcd,numeric_value,1'b1);end
            5:begin prepared_label="JOY     ";prepared_value=number_text(bcd,numeric_value,1'b1);end
            6:begin prepared_label="INPUT   ";prepared_value=snap_input_mask==1 ? "FPGA    ":snap_input_mask==2 ? "EXT IN  ":snap_input_mask==3 ? "DUAL    ":"OFF     ";end
            7:begin prepared_label="METRO   ";prepared_value=">       ";end
            8:begin prepared_label="LANG    ";prepared_value="ENGLISH ";end
            9:begin prepared_label="STATUS  ";prepared_value=snap_metro ? "ON      ":"OFF     ";end
            10:begin prepared_label="BEATS   ";prepared_value=number_text(bcd,numeric_value,1'b0);end
            11:begin prepared_label="VALUE   ";prepared_value=number_text(bcd,numeric_value,1'b0);end
            12:begin prepared_label="TEMPO   ";prepared_value=number_text(bcd,numeric_value,1'b0);end
            default:begin end
        endcase
        if(snap_language_cn)case(menu_item)
            0:prepared_label={8'h80,8'h81,"      "};
            1:begin
                prepared_label={8'h80,8'h84,"      "};prepared_value_cn=1;
                case(snap_timbre)
                    1:prepared_value={8'h93,8'h94,"      "};2:prepared_value={8'h95,8'h94,"      "};
                    3:prepared_value={8'h96,8'h88,"      "};4:prepared_value={8'h97,8'h94,"      "};
                    5:prepared_value={8'h98,8'h99,8'h9a,"     "};6:prepared_value={8'h9b,8'h93,8'h94,"     "};
                    7:prepared_value={8'h9c,8'h9d,"      "};8:prepared_value={8'h9e,8'h9f,"      "};
                    9:prepared_value={8'ha0,8'ha1,"      "};11:prepared_value={8'ha2,8'ha3,"      "};
                    13:prepared_value={8'h9d,8'ha4,"      "};14:prepared_value={8'ha5,8'ha6,8'h94,"     "};
                    default:prepared_value={8'h93,8'h94,"      "};
                endcase
            end
            2:prepared_label={8'h82,8'h83,"      "};
            3:begin
                prepared_label={8'h85,8'h86,"      "};prepared_value_cn=1;
                prepared_value=snap_mode==0 ? {8'ha9,8'haa,"      "}:
                    snap_mode==1 ? {8'hab,8'h82,"      "}:{8'hac,8'had,"      "};
            end
            4:prepared_label={8'hb7,8'hba,"      "};
            5:prepared_label={8'h89,8'h8a,"      "};
            6:begin
                prepared_label={8'hc0,8'hc1,8'hc2,8'hc3,"    "};
                if(snap_input_mask!=1)begin prepared_value_cn=1;
                    prepared_value=snap_input_mask==2 ? {8'hc4,8'hc5,"      "}:
                        snap_input_mask==3 ? {8'hc6,8'hc7,8'hc8,"     "}:{8'hac,8'had,"      "};
                end
            end
            7:prepared_label={8'h8b,8'h8c,8'h8d,"     "};
            8:begin prepared_label={8'h91,8'h92,"      "};prepared_value={8'hb0,8'hb1,"      "};prepared_value_cn=1;end
            9:begin
                prepared_label={8'hbe,8'hbf,"      "};prepared_value_cn=1;
                prepared_value=snap_metro ? {8'hae,8'haf,"      "}:{8'hac,8'had,"      "};
            end
            10:prepared_label={8'h8c,8'h8e,"      "};11:prepared_label={8'h8c,8'h8f,"      "};
            12:prepared_label={8'h90,8'h83,"      "};
            default:begin end
        endcase
        if(snap_view==3)begin
            prepared_value_cn=0;prepared_label="        ";prepared_value="        ";
            if(snap_level==0)begin
                case(root_item)
                  1:begin prepared_label="CALIB   ";prepared_value=snap_cal_state==2 ? "RUNNING ":snap_cal_state==1 ? "WAITING ":snap_cal_state==4 ? "FAILED  ":"PRESS   ";end
                  2,3:begin
                    prepared_label=root_item==2 ? "L STATE ":"R STATE ";
                    prepared_value=!snap_inserted[root_item==3] ? "UNPLUG  ":
                        !snap_online[root_item==3] ? "RETRY   ":snap_drum_active[root_item==3] ? "CAL...  ":
                        snap_pose_fault[root_item==3] ? "RECAL   ":snap_calibrated[root_item==3] ? "READY   ":"UNCAL   ";
                  end
                  4:begin prepared_label="L SOUND ";prepared_value="OPEN >  ";end
                  5:begin prepared_label="R SOUND ";prepared_value="OPEN >  ";end
                  default:begin end
                endcase
                if(snap_language_cn)case(root_item)
                  1:prepared_label={8'hd7,8'hd8,"      "};
                  2:prepared_label={8'hca,8'hc9,8'hbe,8'hbf,"    "};
                  3:prepared_label={8'hcb,8'hc9,8'hbe,8'hbf,"    "};
                  4:prepared_label={8'hca,8'hc9,8'h80,8'h86,"    "};
                  5:prepared_label={8'hcb,8'hc9,8'h80,8'h86,"    "};
                  default:begin end
                endcase
            end else if(prep_row<3)begin
                prepared_label=prep_row==0 ? "SIDE HIT":prep_row==1 ? "DOWN HIT":"UP HIT  ";
                case(drum_voice)
                  255:prepared_value="NONE    ";0:prepared_value="SNARE   ";1:prepared_value="KICK    ";
                  2:prepared_value="HIHAT   ";3:prepared_value="TOM     ";4:prepared_value="CRASH   ";5:prepared_value="RIDE    ";
                  default:prepared_value="?       ";
                endcase
                if(snap_language_cn)begin
                    prepared_label=prep_row==0 ? {8'he0,8'he3,"      "}:prep_row==1 ? {8'he1,8'he3,"      "}:{8'he2,8'he3,"      "};
                    prepared_value_cn=1;
                    case(drum_voice)
                      255:begin prepared_value="NONE    ";prepared_value_cn=0;end
                      0:prepared_value={8'ha2,8'ha3,"      "};1:prepared_value={8'hce,8'ha3,"      "};
                      2:prepared_value={8'hcf,8'hd0,"      "};3:prepared_value={8'hd1,8'ha3,"      "};
                      4:prepared_value={8'hd2,8'hd0,"      "};5:prepared_value={8'hd3,8'hd3,8'hd0,"     "};
                      default:begin prepared_value="?       ";prepared_value_cn=0;end
                    endcase
                end
            end
        end
        if(snap_view==5)begin
            prepared_value_cn=0;
            case(prep_row)
              0:begin prepared_label="TRIGGER ";prepared_value="KEY ON  ";end
              1:begin prepared_label="OUTPUT  ";prepared_value="I2S     ";end
              2:begin prepared_label="TIME    ";prepared_value=snap_response_valid ? response_text:"--      ";end
              3:begin prepared_label="STATE   ";prepared_value=snap_response_busy ? "MEASURE ":snap_response_valid ? "VALID   ":"WAIT KEY";end
            endcase
            if(snap_language_cn)case(prep_row)
              0:prepared_label={8'hdd,8'hde,"      "};
              1:prepared_label={8'hc0,8'hdf,"      "};
              2:prepared_label={8'hdb,8'hdc,"      "};
              3:prepared_label={8'hbe,8'hbf,"      "};
            endcase
        end
        if(snap_view==2 && snap_level==0 && root_item==10)begin
            prepared_label=64'h5d5e01bc20202020;prepared_value=64'h29c1202020202020;prepared_value_cn=1;
        end
    end
    reg [31:0] skipped_binary,skipped_bcd;reg [5:0] skipped_bit;reg [63:0] skipped_text;
    reg [31:0] skipped_adjusted;integer sd;
    always @*begin skipped_adjusted=skipped_bcd;for(sd=0;sd<8;sd=sd+1)if(skipped_bcd[sd*4+:4]>=5)skipped_adjusted[sd*4+:4]=skipped_bcd[sd*4+:4]+4'd3;end
    always @(posedge clk or negedge rst_n)begin
     if(!rst_n)begin skipped_binary<=0;skipped_bcd<=0;skipped_bit<=0;skipped_text<=0;end
     else if(state==PREPARE && prep_row==0)begin skipped_binary<=bundle_skipped;skipped_bcd<=0;skipped_bit<=32;end
     else if(skipped_bit!=0)begin skipped_binary<=skipped_binary<<1;skipped_bcd<={skipped_adjusted[30:0],skipped_binary[31]};skipped_bit<=skipped_bit-1'b1;end
     else skipped_text<={4'h3,skipped_bcd[31:28],4'h3,skipped_bcd[27:24],4'h3,skipped_bcd[23:20],4'h3,skipped_bcd[19:16],4'h3,skipped_bcd[15:12],4'h3,skipped_bcd[11:8],4'h3,skipped_bcd[7:4],4'h3,skipped_bcd[3:0]};
    end
    wire [4:0] title_offset,title_pixel;reg [4:0] snap_title_offset,snap_title_pixel;
    reg title_area,title_area_q;
    hallpad_title_scroll u_title_scroll(.clk(clk),.rst_n(rst_n),.valid(title_valid),.count(title_count),.revision(title_revision),.offset(title_offset),.pixel(title_pixel));
    reg [15:0] response_binary;reg [19:0] response_bcd,response_adjusted;

    integer response_digit;
    always @*begin
        response_adjusted=response_bcd;
        for(response_digit=0;response_digit<5;response_digit=response_digit+1)
            if(response_bcd[response_digit*4+:4]>=5)
                response_adjusted[response_digit*4+:4]=response_bcd[response_digit*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin response_binary<=0;response_bcd<=0;response_bit<=0;response_text<="--      ";end
        else if(state==PREPARE && prep_row==0)begin response_binary<=snap_response_us;response_bcd<=0;response_bit<=16;end
        else if(response_bit!=0)begin
            response_binary<=response_binary<<1;response_bcd<={response_adjusted[18:0],response_binary[15]};response_bit<=response_bit-1'b1;
        end else response_text<={4'h3,response_bcd[19:16],4'h3,response_bcd[15:12],4'h3,response_bcd[11:8],4'h3,response_bcd[7:4],4'h3,response_bcd[3:0]," US"};
    end
    reg [7:0] px,py,window_left,window_right,window_top,window_bottom,previous_wave_y;
    assign x0=window_left;assign x1=window_right;assign y0=window_top;assign y1=window_bottom;
    wire [7:0] lissajous_x=px-8'd56,lissajous_y=py-8'd68;
    assign lissajous_address={lissajous_y[6:0],lissajous_x[6:0]};
    assign lissajous_lock=rst_n && init_done && state!=IDLE && snap_view==4 && !snap_offline && snap_practice==0;
    assign scope_address=px-8'd24;assign spectrum_address=px-8'd24;
    assign scope_lock=rst_n && init_done && state!=IDLE && snap_view==1;
    assign spectrum_lock=rst_n && init_done && state!=IDLE && snap_view==0;
    assign fill_mode=0;assign fill_color=0;
    assign draw_valid=rst_n && init_done && state==REQUEST;
    assign pixel_valid=rst_n && init_done && state==STREAM;
    reg [15:0] pixel_q;
    assign pixel_rgb565=pixel_q;
    wire [15:0] accent=snap_editing ? AMBER:CYAN;
    reg [7:0] character,character_q;
    reg [2:0] font_column,font_row,column_q,row_q;
    reg hanzi,hanzi_q,text_area,text_area_q;
    reg [4:0] han_column,han_row;
    reg [15:0] background,foreground,background_q,foreground_q;
    wire ascii_ink,hanzi_ink;
    wire ink=title_area_q ? title_ink:hanzi_q ? hanzi_ink:ascii_ink;
    menu_font5x7 u_font(.character(character_q),.column(column_q),.row(row_q),.ink(ascii_ink));
    menu_hanzi22 u_hanzi(.clk(clk),.character(character),.column(han_column),.row(han_row),.ink(hanzi_ink));
    // Balanced comparisons cap decoder depth instead of a long priority chain.
    function [3:0] cell20(input [7:0] d);
        begin
            if(d<88)begin if(d<44)cell20=d<22 ? 0:1;else cell20=d<66 ? 2:3;end
            else begin if(d<132)cell20=d<110 ? 4:5;else cell20=d<154 ? 6:7;end
        end
    endfunction
    function [3:0] cell12(input [7:0] d);
        begin
            if(d<96)begin
                if(d<48)begin if(d<24)cell12=d<12 ? 0:1;else cell12=d<36 ? 2:3;end
                else begin if(d<72)cell12=d<60 ? 4:5;else cell12=d<84 ? 6:7;end
            end else begin
                if(d<144)begin if(d<120)cell12=d<108 ? 8:9;else cell12=d<132 ? 10:11;end
                else cell12=d<156 ? 12:13;
            end
        end
    endfunction
    function [3:0] cell6(input [7:0] d);
        begin cell6=cell12({d[6:0],1'b0});end
    endfunction
    function [7:0] value_start(input [3:0] count,input cn);
        reg [7:0] extended_count,span;
        begin extended_count={4'd0,count};span=cn ? (extended_count<<4)+(extended_count<<2)+(extended_count<<1):(extended_count<<3)+(extended_count<<2);value_start=8'd198-span;end
    endfunction
    reg [7:0] menu_value_start_q,menu_dx_q,menu_dy_q;
    reg [63:0] menu_label_q,menu_value_q,menu_run_q;
    reg menu_value_cn_q,menu_cn_q;
    reg [7:0] glyph_dy;
    reg [1:0] row_number;
    reg [7:0] row_top,dx,dy,cell_x,wave_low,wave_high;
    reg [3:0] char_index;
    reg [63:0] run_text;
    reg [111:0] line_text;
    reg run_cn;
    reg [8:0] graph_y,spectrum_top;
    always @*begin
        background=BG;foreground=TEXT;text_area=0;hanzi=0;title_area=0;title_index=0;title_row=0;title_column=0;han_column=0;han_row=0;
        character=" ";font_column=0;font_row=0;
        dx=0;dy=0;cell_x=0;char_index=0;glyph_dy=0;
        run_text=0;line_text=0;run_cn=0;
        graph_y={1'b0,py}-9'd68;
        wave_low=previous_wave_y<scope_y ? previous_wave_y:scope_y;
        wave_high=previous_wave_y>scope_y ? previous_wave_y:scope_y;
        if(px==24)begin wave_low=scope_y;wave_high=scope_y;end
        spectrum_top=9'd196-{1'b0,spectrum_height};
        if(snap_menu)begin
            if(snap_selected!=0 && row_number==selected_row &&
               py>=row_top+1 && py<row_top+31 && px>=38 && px<=201)begin
                background=PANEL;
                if(px<41 && py>=row_top+7 && py<row_top+25)background=accent;
            end
            if(snap_selected==0 && py>=41 && py<=42 && px>=90 && px<=149)background=accent;
        end
        if(py>=24 && py<38 && px>=36 && px<204 && (!snap_language_cn || snap_view==2 || (snap_offline && snap_offline_state==6)))begin
            dx=px-8'd36;dy=py-8'd24;char_index=cell12(dx);
            line_text=(snap_offline && snap_offline_state==6) ? "    RESULT    ":snap_view==0 ? "   SPECTRUM   ":snap_view==1 ? "   WAVEFORM   ":
                snap_view==5 ? " AUDIO DELAY  ":snap_view==4 ? "  LISSAJOUS   ":snap_view==3 ? (snap_level==1 ? " LEFT SOUNDS  ":snap_level==2 ? " RIGHT SOUNDS ":"  DRUMSTICKS  "):snap_level==1 ? "  METRONOME   ":"   HALLPAD    ";
            character=line_text[111-char_index*8 -:8];
            cell_x=dx-({char_index,3'd0}+{char_index,2'd0});font_column=cell_x[3:1];font_row=dy[3:1];
            text_area=1;foreground=snap_view==4 ? ORANGE:CYAN;
        end
        if(snap_language_cn && snap_view!=2 && !(snap_offline && snap_offline_state==6) && py>=19 && py<41 && px>=(snap_view==5 ? 76:snap_view==4 ? 87:98) && px<(snap_view==5 ? 164:snap_view==4 ? 153:142))begin
            dx=px-(snap_view==5 ? 8'd76:snap_view==4 ? 8'd87:8'd98);dy=py-8'd19;char_index=cell20(dx);
            line_text=(snap_offline && snap_offline_state==6) ? "    RESULT    ":snap_view==5 ? {8'h80,8'hbb,8'hdb,8'hdc,80'd0}:snap_view==4 ? {8'hd4,8'hd5,8'hd6,88'd0}:snap_view==0 ? {8'hbb,8'hbc,96'd0}:snap_view==3 ? (snap_level==1 ? {8'hca,8'hc9,96'd0}:snap_level==2 ? {8'hcb,8'hc9,96'd0}:{8'ha3,8'hc9,96'd0}):{8'ha9,8'hbd,96'd0};
            character=line_text[111-char_index*8 -:8];hanzi=1;
            cell_x=dx-({char_index,4'd0}+{char_index,2'd0}+{char_index,1'b0});han_column=cell_x[4:0];han_row=dy[4:0];
            text_area=1;foreground=CYAN;
        end
        if((snap_view<2 || snap_view==4) && py>=48 && py<55 && px>=78 && px<162)begin
            dx=px-8'd78;dy=py-8'd48;char_index=cell6(dx);
            line_text=snap_view==0 ? " 50HZ - 3KHZ  ":"    32 MS     ";
            if(snap_view==4)line_text=" TOP 2 PEAKS  ";
            character=line_text[111-char_index*8 -:8];
            cell_x=dx-({char_index,2'd0}+{char_index,1'b0});font_column=cell_x[2:0];font_row=dy[2:0];
            text_area=1;foreground=DIM;
        end
        if(snap_view<2 && py>=68 && py<=195)begin
            if(px[4:0]==0 && py[4:0]==4)background=GRID;
            if(((snap_view==1 && py==132)||(snap_view==0 && py==195)) && px[2:0]==0)background=GRID;
            if(snap_view==0 && snap_spectrum_valid && spectrum_height!=0)begin
                if({1'b0,py}>=spectrum_top)begin
                    background=py<108 ? 16'h03B2:py<152 ? 16'h0290:FILL;
                    if(px[1:0]==3)background=BG;
                    if({1'b0,py}<=spectrum_top+1)background=EDGE;
                    else if({1'b0,py}<=spectrum_top+3)background=CYAN;
                end
            end else if(snap_view==1 && snap_scope_valid)begin
                if((scope_y<64 && graph_y>=scope_y && graph_y<64) ||
                   (scope_y>64 && graph_y<=scope_y && graph_y>64))background=16'h0107;
                if(graph_y+2>={1'b0,wave_low} && graph_y<={1'b0,wave_high}+2)background=GLOW;
                if(graph_y>={1'b0,wave_low} && graph_y<={1'b0,wave_high})background=CYAN;
            end
        end
        // Borderless XY area, matching the existing graph pages.
        if(snap_view==4 && py>=68 && py<=195 && px>=56 && px<=183)begin
            if((px==120 && py[2:0]==4) || (py==131 && px[2:0]==0))background=GRID;
            if(snap_lissajous_valid && lissajous_pixel)background=ORANGE;
        end
        if((snap_view<2 || snap_view==4) && py>=212 && py<=214)begin
            if(px>=104 && px<112)background=snap_view==0 ? CYAN:PANEL;
            if(px>=116 && px<124)background=snap_view==1 ? CYAN:PANEL;
            if(px>=128 && px<136)background=snap_view==4 ? ORANGE:PANEL;
        end
        if(snap_menu && py>=row_top+5 && py<row_top+27 && px>=42 && px<198 && py<=197)begin
            // Row selection and coordinate subtraction were registered in
            // ROW_DATA/ROW_COORDS. Only glyph selection remains in this stage.
            dy=menu_dy_q;dx=menu_dx_q;run_text=menu_run_q;run_cn=menu_cn_q;
            char_index=run_cn ? cell20(dx):cell12(dx);
            if(char_index<8)begin
                character=run_text[63-char_index*8 -:8];hanzi=run_cn && (character[7] || character<32 || (character>=33 && character<=47) || character==93 || character==94);
                cell_x=run_cn ? dx-({char_index,4'd0}+{char_index,2'd0}+{char_index,1'b0}):
                               dx-({char_index,3'd0}+{char_index,2'd0});
                han_column=cell_x[4:0];han_row=dy[4:0];
                font_column=cell_x[3:1];glyph_dy=dy-8'd3;font_row=glyph_dy[3:1];
                text_area=hanzi || (cell_x<10 && dy>=3 && dy<17);
                foreground=(snap_selected!=0 && row_number==selected_row) ? accent:TEXT;
            end
        end
        if(snap_view==3 && py>=208 && py<215 && px>=78 && px<162)begin
            dx=px-8'd78;dy=py-8'd208;char_index=cell6(dx);
            line_text={"L",hex_digit(snap_bus_info[15:12]),hex_digit(snap_bus_info[11:8]),"/",hex_digit(snap_bus_info[7:4]),hex_digit(snap_bus_info[3:0])," R",hex_digit(snap_bus_info[31:28]),hex_digit(snap_bus_info[27:24]),"/",hex_digit(snap_bus_info[23:20]),hex_digit(snap_bus_info[19:16])," "};
            character=line_text[111-char_index*8 -:8];
            cell_x=dx-({char_index,2'd0}+{char_index,1'b0});font_column=cell_x[2:0];font_row=dy[2:0];
            text_area=1;foreground=DIM;
        end
        if(snap_practice!=0)begin
            background=BG;foreground=CYAN;text_area=0;hanzi=0;
            character=" ";font_column=0;font_row=0;
            if(!snap_language_cn && py>=32 && py<46 && px>=36 && px<204)begin
                dx=px-8'd36;dy=py-8'd32;char_index=cell12(dx);
                line_text="   PRACTICE   ";character=line_text[111-char_index*8 -:8];
                cell_x=dx-({char_index,3'd0}+{char_index,2'd0});
                font_column=cell_x[3:1];font_row=dy[3:1];text_area=1;
            end
            if(py==58 && px>=72 && px<168)background=CYAN;
            if(snap_practice==1)begin
                if(px>=100 && px<140 && py>=84 && py<140)begin
                    dx=px-8'd100;dy=py-8'd84;character=8'd48+{6'd0,snap_countdown};
                    font_column=dx[5:3];font_row=dy[5:3];text_area=1;foreground=TEXT;
                end
                if(py>=164 && py<170)begin
                    if(px>=80 && px<96)background=snap_countdown>=1 ? AMBER:PANEL;
                    if(px>=112 && px<128)background=snap_countdown>=2 ? AMBER:PANEL;
                    if(px>=144 && px<160)background=snap_countdown>=3 ? AMBER:PANEL;
                end
            end else if(!snap_language_cn && py>=96 && py<110 && px>=36 && px<204)begin
                dx=px-8'd36;dy=py-8'd96;char_index=cell12(dx);
                line_text=snap_practice==3 ? "    PAUSED    ":" FOLLOW LIGHTS";
                character=line_text[111-char_index*8 -:8];
                cell_x=dx-({char_index,3'd0}+{char_index,2'd0});
                font_column=cell_x[3:1];font_row=dy[3:1];text_area=1;foreground=TEXT;
            end
            if(!snap_language_cn && py>=184 && py<198 && px>=36 && px<204)begin
                dx=px-8'd36;dy=py-8'd184;char_index=cell12(dx);
                line_text="TAP      HOLD ";character=line_text[111-char_index*8 -:8];
                cell_x=dx-({char_index,3'd0}+{char_index,2'd0});
                font_column=cell_x[3:1];font_row=dy[3:1];text_area=1;
                foreground=px<120 ? CYAN:AMBER;
            end
        end
        if(snap_practice!=0 && snap_language_cn)begin
          if(py>=30 && py<52 && px>=76 && px<164)begin
            dx=px-76;dy=py-30;char_index=cell20(dx);line_text=playback_mode ? {8'h01,8'h02,8'h07,8'h08,80'h20202020202020202020}:{8'he4,8'he5,8'he6,8'he7,80'h20202020202020202020};
            character=line_text[111-char_index*8-:8];hanzi=1;han_column=dx-char_index*22;han_row=dy[4:0];text_area=1;
          end
          if(snap_practice!=1 && py>=94 && py<116 && px>=76 && px<164)begin
            dx=px-76;dy=py-94;char_index=cell20(dx);line_text=snap_practice==3 ? {8'hee,8'hef,96'h202020202020202020202020}:playback_mode ? {8'h07,8'h08,8'hb0,88'h2020202020202020202020}:{8'hec,8'h85,8'hed,8'he7,80'h20202020202020202020};
            character=line_text[111-char_index*8-:8];hanzi=1;han_column=dx-char_index*22;han_row=dy[4:0];text_area=1;
          end
          if(py>=181 && py<203 && px>=32 && px<208)begin
            dx=px-32;dy=py-181;char_index=cell20(dx);line_text={8'hf2,8'hec,8'hee,8'hef,8'h9e,8'hec,8'hf5,8'hff,48'h202020202020};
            character=line_text[111-char_index*8-:8];hanzi=1;han_column=dx-char_index*22;han_row=dy[4:0];text_area=1;
          end
        end
        if(snap_offline)begin
          character=offline_character;hanzi=offline_hanzi;font_column=offline_font_column;font_row=offline_font_row;
          han_column=offline_han_column;han_row=offline_han_row;title_area=offline_title_area;text_area=offline_text_area;
          title_index=offline_title_index;title_row=offline_title_row;title_column=offline_title_column;
          background=offline_background;foreground=offline_foreground;
        end
    end
    wire [7:0] offline_character;wire offline_hanzi,offline_title_area,offline_text_area;
    wire [2:0] offline_font_column,offline_font_row;
    wire [4:0] offline_han_column,offline_han_row,offline_title_row,offline_title_column;
    wire [4:0] offline_title_index;wire [15:0] offline_background,offline_foreground;
    hallpad_offline_layout u_offline_layout(.px(px),.py(py),.ui_state(snap_offline_state),.error_code(snap_offline_error),
      .language_cn(snap_language_cn),.playback(playback_mode),.choosing(bundle_choosing),.selection(song_selection),.song_count(song_count),
      .title_count(title_count),.title_offset(snap_title_offset),.title_pixel(snap_title_pixel),.title_valid(title_valid),.title_pending(title_pending),
      .ascii_title_valid(ascii_title_valid),.ascii_title(ascii_title),.filename(snap_offline_name),.choice_text(bundle_text),
      .result_text(snap_result_text),.skipped_text(skipped_text),.practice_screen(snap_practice),.countdown(snap_countdown),
      .character(offline_character),.hanzi(offline_hanzi),.font_column(offline_font_column),.font_row(offline_font_row),
      .han_column(offline_han_column),.han_row(offline_han_row),.title_area(offline_title_area),.text_area(offline_text_area),
      .title_index(offline_title_index),.title_row(offline_title_row),.title_column(offline_title_column),
      .background(offline_background),.foreground(offline_foreground));
    integer r;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            menu_value_start_q<=198;menu_dx_q<=0;menu_dy_q<=0;menu_label_q<=0;menu_value_q<=0;menu_run_q<=0;menu_value_cn_q<=0;menu_cn_q<=0;
            snap_title_revision<=0;snap_title_valid<=0;snap_title_pending<=0;snap_ascii_valid<=0;snap_ascii_title<=0;state<=IDLE;title_area_q<=0;snap_title_offset<=0;snap_title_pixel<=0;have_snapshot<=0;prep_row<=0;row_number<=0;row_top<=52;
            snap_response_us<=0;snap_response_valid<=0;snap_response_busy<=0;snap_drum_active<=0;snap_pose_fault<=0;snap_view<=2;snap_lissajous_valid<=0;snap_lissajous_frame<=0;snap_level<=0;snap_input_mask<=1;snap_scope_valid<=0;snap_spectrum_valid<=0;
            snap_selected<=0;snap_mode<=0;snap_editing<=0;snap_language_cn<=1;snap_metro<=0;
            snap_volume<=0;snap_echo<=0;snap_joy<=0;snap_brightness<=0;snap_timbre<=0;
            snap_beats<=4;snap_unit<=4;snap_bpm<=120;snap_scope_frame<=0;snap_spectrum_frame<=0;
            snap_result_text<=0;snap_bus_info<=0;snap_offline<=0;snap_offline_state<=0;snap_offline_error<=0;snap_offline_name<=0;snap_bus_error<=0;snap_inserted<=0;snap_cal_state<=0;snap_drum<=0;snap_online<=0;snap_calibrated<=0;snap_practice<=0;snap_countdown<=0;
            bcd<=0;binary_digits<=0;digit_count<=0;value_length_q<=0;value_cn_q<=0;
            px<=24;py<=16;window_left<=24;window_right<=215;window_top<=16;window_bottom<=223;previous_wave_y<=64;
            character_q<=0;column_q<=0;row_q<=0;text_area_q<=0;hanzi_q<=0;
            foreground_q<=0;background_q<=0;pixel_q<=0;
            for(r=0;r<4;r=r+1)begin row_label[r]<=0;row_value[r]<=0;row_value_cn[r]<=0;row_value_start[r]<=198;end
        end else if(!init_done || draw_error)begin
            state<=IDLE;have_snapshot<=0;px<=24;py<=16;
        end else case(state)
            IDLE:if(changed)begin
                snap_title_revision<=title_revision;snap_title_valid<=title_valid;snap_title_pending<=title_pending;snap_ascii_valid<=ascii_title_valid;snap_ascii_title<=ascii_title;
                snap_title_offset<=title_offset;snap_title_pixel<=title_pixel;snap_result_text<=offline_result_text;
                snap_bus_info<=drum_bus_info;snap_offline<=offline_active;snap_offline_state<=offline_state;snap_offline_error<=offline_error;snap_offline_name<=offline_name;snap_bus_error<=drum_bus_error;snap_inserted<=drum_inserted;snap_cal_state<=drum_cal_state;snap_drum<=drum_config;snap_online<=drum_online;snap_calibrated<=drum_calibrated;
                snap_response_us<=response_us;snap_response_valid<=response_valid;snap_response_busy<=response_busy;
                snap_drum_active<=drum_active;snap_pose_fault<=drum_pose_fault;snap_view<=main_view;
                snap_lissajous_valid<=lissajous_valid;snap_lissajous_frame<=lissajous_frame;snap_level<=menu_level;snap_input_mask<=audio_input_mask;
                snap_practice<=active_practice;snap_countdown<=practice_countdown;
                snap_scope_valid<=scope_valid;snap_spectrum_valid<=spectrum_valid;
                snap_scope_frame<=scope_frame;snap_spectrum_frame<=spectrum_frame;
                snap_selected<=selected;snap_mode<=light_mode;snap_editing<=editing;snap_language_cn<=language_cn;
                snap_volume<=volume_percent;snap_echo<=echo_percent;snap_joy<=joy_percent;
                snap_brightness<=light_brightness;snap_timbre<=timbre_sel;
                snap_metro<=metro_enable;snap_beats<=metro_beats;snap_unit<=metro_unit;snap_bpm<=metro_bpm;
                if(offline_active || snap_offline || !have_snapshot || offline_active!=snap_offline || (offline_active && ((offline_state==6)!=(snap_offline_state==6))) || active_practice!=0 || snap_practice!=0 || main_view!=snap_view || menu_level!=snap_level || language_cn!=snap_language_cn)begin
                    window_left<=24;window_right<=215;window_top<=16;window_bottom<=223;py<=16;px<=24;
                end else if(main_view==4)begin
                    window_left<=56;window_right<=183;px<=56;
                    window_top<=68;py<=68;window_bottom<=195;
                end else if(main_view==3)begin window_left<=24;window_right<=215;px<=24;window_top<=41;window_bottom<=223;py<=41;
                end else if(main_view==2 || main_view==5)begin
                    // Same menu: title underline plus all four rows. The static
                    // header/footer need no retransmission; text erasure remains complete.
                    window_left<=24;window_right<=215;px<=24;window_top<=41;window_bottom<=202;py<=41;
                end else begin window_left<=24;window_right<=215;px<=24;window_top<=68;window_bottom<=195;py<=68;end
                prep_row<=0;have_snapshot<=1;state<=(live_menu || offline_active) ? PREPARE:REQUEST;
            end
            PREPARE:begin bcd<=0;binary_digits<=numeric_value;digit_count<=0;state<=DIGITS;end
            DIGITS:begin
                bcd<={adjusted_bcd[10:0],binary_digits[7]};binary_digits<={binary_digits[6:0],1'b0};
                if(digit_count==7)state<=FORMAT;else digit_count<=digit_count+1'b1;
            end
            FORMAT:begin
                row_label[prep_row]<=prepared_label;row_value[prep_row]<=prepared_value;
                row_value_cn[prep_row]<=prepared_value_cn;
                state<=VALUE_LENGTH;
            end
            VALUE_LENGTH:begin
                value_length_q<=text_length(row_value[prep_row]);value_cn_q<=row_value_cn[prep_row];
                state<=VALUE_POSITION;
            end
            VALUE_POSITION:begin
                row_value_start[prep_row]<=value_start(value_length_q,value_cn_q);
                if(prep_row==3)state<=REQUEST;else begin prep_row<=prep_row+1'b1;state<=PREPARE;end
            end
            REQUEST:if(draw_ready)state<=FETCH;
            FETCH:begin
                if(py>=172)begin row_number<=3;row_top<=172;end
                else if(py>=132)begin row_number<=2;row_top<=132;end
                else if(py>=92)begin row_number<=1;row_top<=92;end
                else begin row_number<=0;row_top<=52;end
                // Graph pixels bypass the menu row fetch/mux stages.
                state<=snap_menu && !snap_offline ? ROW_DATA:ADDRESS;
            end
            ROW_DATA:begin
                menu_value_start_q<=row_value_start[row_number];menu_label_q<=row_label[row_number];
                menu_value_q<=row_value[row_number];menu_value_cn_q<=row_value_cn[row_number];state<=ROW_COORDS;
            end
            ROW_COORDS:begin
                menu_dy_q<=py-row_top-8'd5;
                if(px>=menu_value_start_q)begin menu_dx_q<=px-menu_value_start_q;menu_run_q<=menu_value_q;menu_cn_q<=menu_value_cn_q;end
                else begin menu_dx_q<=px-8'd42;menu_run_q<=menu_label_q;menu_cn_q<=snap_language_cn || menu_label_q[63:32]==32'h5d5e01bc;end
                state<=ADDRESS;
            end
            ADDRESS:begin
                title_area_q<=title_area;previous_wave_y<=scope_y;character_q<=character;column_q<=font_column;row_q<=font_row;hanzi_q<=hanzi;
                text_area_q<=text_area;foreground_q<=foreground;background_q<=background;state<=GLYPH;
            end
            GLYPH:begin pixel_q<=(text_area_q && ink) ? foreground_q:background_q;state<=STREAM;end
            STREAM:if(pixel_ready)begin
                if(px==window_right)begin px<=window_left;if(py==window_bottom)state<=DRAIN;else begin py<=py+1'b1;state<=FETCH;end end
                else begin px<=px+1'b1;state<=FETCH;end
            end
            DRAIN:if(draw_done)state<=IDLE;
            default:begin state<=IDLE;have_snapshot<=0;end
        endcase
    end
endmodule

