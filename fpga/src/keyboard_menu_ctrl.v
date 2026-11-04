`timescale 1ns/1ps
// Six top-level views: spectrum, waveform, XY, Hallpad, response, drums. Header focus is a real menu position (selected=0).
// Long press always goes to the immediate parent; no release short-press follows it.
module keyboard_menu_ctrl #(
    parameter integer DEFAULT_VOLUME=50,DEFAULT_BRIGHTNESS=10,
    AUDIO_ROUTE_HANDSHAKE=0,ROUTE_TIMEOUT_CYCLES=25000000
)(
    input wire clk,rst_n,step_valid,step_up,short_press,long_press,
    output reg [2:0] main_view,
    output reg [1:0] menu_level,
    output reg [4:0] selected,
    output reg editing,
    output wire [6:0] volume_percent,
    output wire [5:0] light_brightness,
    output wire [3:0] timbre_sel,
    output wire [1:0] light_mode,
    output wire [1:0] audio_input_mask,
    output wire [6:0] echo_percent,joy_percent,
    output wire language_cn,metro_enable,
    output wire [3:0] metro_beats,metro_unit,
    output wire [7:0] metro_bpm,
    input wire [127:0] drum_config,
    output wire drum_edit_valid,
    output wire drum_cal_request,offline_enter,
    input wire drum_edit_ready,
    output wire drum_edit_stick,drum_edit_up,
    output wire [1:0] drum_edit_direction,
    input wire remote_commit,
    input wire [63:0] remote_config,
    output wire remote_ready,
    output reg remote_done,remote_error,
    output wire route_valid,
    output wire [1:0] route_target_mask,
    input wire route_ready,route_done,route_error,
    output reg route_cancel,
    output wire [63:0] config_data,
    output reg [31:0] config_revision,
    output reg changed
);
    // Keep the existing HALLPAD/drum IDs; insert XY between waveform/HALLPAD.
    function [2:0] next_view(input [2:0] v);
        begin case(v) 0:next_view=1;1:next_view=4;4:next_view=2;2:next_view=5;5:next_view=3;default:next_view=0;endcase end
    endfunction
    function [2:0] previous_view(input [2:0] v);
        begin case(v) 0:previous_view=3;3:previous_view=5;5:previous_view=2;2:previous_view=4;4:previous_view=1;default:previous_view=0;endcase end
    endfunction
    assign offline_enter=short_press && !long_press && main_view==2 && menu_level==0 && selected==10;
    assign drum_cal_request=short_press && !long_press && main_view==3 && menu_level==0 && selected==1;
    reg [2:0] drum_parent;
    reg [3:0] drum_steps[0:15];
    reg [3:0] drum_wr,drum_rd;
    reg [4:0] drum_count;
    wire drum_pop=drum_edit_valid && (drum_edit_ready===1'b1);
    wire drum_push=step_valid && !short_press && !long_press && main_view==3 && editing &&
        menu_level!=0 && selected>=1 && selected<=3 && (drum_count<16 || drum_pop);
    wire [4:0] drum_slot=selected-5'd1;
    assign drum_edit_valid=drum_count!=0;
    assign {drum_edit_stick,drum_edit_direction,drum_edit_up}=drum_steps[drum_rd];
    always @(posedge clk)if(drum_push)drum_steps[drum_wr]<={menu_level==2,drum_slot[1:0],step_up};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin drum_wr<=0;drum_rd<=0;drum_count<=0;end
        else begin
            if(drum_push)drum_wr<=drum_wr+1'b1;
            if(drum_pop)drum_rd<=drum_rd+1'b1;
            case({drum_push,drum_pop})
                2'b10:drum_count<=drum_count+1'b1;
                2'b01:drum_count<=drum_count-1'b1;
                default:drum_count<=drum_count;
            endcase
        end
    end
    // One owner for both local and remote runtime settings.
    // [53:52] audio input enables: bit0 FPGA, bit1 AUX; 00 is App mute-both.
    // [51:44] bpm, [43:40] unit, [39:36] beats, [35] metro, [34] CN,
    // [33:27] joystick, [26] wet enable, [25:19] remembered wet mix,
    // [18:17] light mode, [16:11] brightness, [10:7] timbre, [6:0] volume.
    reg [63:0] config_word,config_next,pending_config;
    reg config_busy,route_issued,pending_remote;
    reg [31:0] route_wait;
    assign route_valid=config_busy && !route_issued;
    assign route_target_mask=pending_config[53:52];
    localparam [6:0] INITIAL_VOLUME=DEFAULT_VOLUME;
    localparam [5:0] INITIAL_BRIGHTNESS=DEFAULT_BRIGHTNESS;
    assign config_data=config_word;
    assign volume_percent=config_word[6:0];
    assign timbre_sel=config_word[10:7];
    assign light_brightness=config_word[16:11];
    assign light_mode=config_word[18:17];
    assign echo_percent=config_word[26] ? config_word[25:19]:7'd0;
    assign joy_percent=config_word[33:27];
    assign language_cn=config_word[34];
    assign metro_enable=config_word[35];
    assign metro_beats=config_word[39:36];
    assign metro_unit=config_word[43:40];
    assign metro_bpm=config_word[51:44];
    assign audio_input_mask=config_word[53:52];
    assign remote_ready=!config_busy && !(long_press || short_press || step_valid);
    function [6:0] adjust_percent(input [6:0] v,input up);
        begin adjust_percent=up ? (v>=95 ? 7'd100:v+7'd5):(v<=5 ? 7'd0:v-7'd5);end
    endfunction
    function [3:0] next_sound(input [3:0] v,input up);
        begin
            if(up)case(v)
                9:next_sound=11;11:next_sound=13;13:next_sound=14;14:next_sound=1;
                default:next_sound=v+1'b1;
            endcase
            else case(v)
                1:next_sound=14;11:next_sound=9;13:next_sound=11;14:next_sound=13;
                default:next_sound=v-1'b1;
            endcase
        end
    endfunction
    always @* begin
        config_next=config_word;
        if(step_valid && !short_press && !long_press && main_view==2 && editing) begin
            if(menu_level==1) case(selected)
                1:config_next[35]=step_up;
                2:if(step_up) begin if(metro_beats<12) config_next[39:36]=metro_beats+1'b1;end else if(metro_beats>1) config_next[39:36]=metro_beats-1'b1;
                3:config_next[43:40]=step_up ? (metro_unit==2 ? 4'd4:metro_unit==4 ? 4'd8:4'd2):(metro_unit==2 ? 4'd8:metro_unit==4 ? 4'd2:4'd4);
                4:if(step_up) begin if(metro_bpm<240) config_next[51:44]=metro_bpm+1'b1;end else if(metro_bpm>30) config_next[51:44]=metro_bpm-1'b1;
                default:config_next=config_word;
            endcase
            else if(menu_level==0) case(selected)
                1:config_next[6:0]=adjust_percent(volume_percent,step_up);
                2:config_next[10:7]=next_sound(timbre_sel,step_up);
                3:if(step_up) begin if(light_brightness<32) config_next[16:11]=light_brightness+1'b1;end else if(light_brightness!=0) config_next[16:11]=light_brightness-1'b1;
                4:config_next[18:17]=step_up ? (light_mode==2 ? 2'd0:light_mode+1'b1):(light_mode==0 ? 2'd2:light_mode-1'b1);
                5:begin config_next[25:19]=adjust_percent(echo_percent,step_up);config_next[26]=config_next[25:19]!=0;end
                6:config_next[33:27]=adjust_percent(joy_percent,step_up);
                // Same in-place editing as LIGHT. App-only 00 enters the
                // three audible modes at FPGA going up, DUAL going down.
                7:config_next[53:52]=step_up ?
                    (audio_input_mask==3 ? 2'd1:audio_input_mask+1'b1):
                    (audio_input_mask<=1 ? 2'd3:audio_input_mask-1'b1);
                9:config_next[34]=!language_cn;
                default:config_next=config_word;
            endcase
        end else if(remote_commit && remote_ready) config_next=remote_config;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            config_word<={10'd0,2'b01,8'd120,4'd4,4'd4,1'b0,1'b1,7'd0,1'b0,7'd0,2'd0,INITIAL_BRIGHTNESS,4'd1,INITIAL_VOLUME};
            config_revision<=0;pending_config<=0;config_busy<=0;route_issued<=0;
            pending_remote<=0;route_wait<=0;remote_done<=0;remote_error<=0;route_cancel<=0;
        end else begin
            remote_done<=0;remote_error<=0;route_cancel<=0;
            if(config_busy) begin
                route_wait<=route_wait+1'b1;
                if(route_error || route_wait>=ROUTE_TIMEOUT_CYCLES-1) begin
                    config_busy<=0;route_issued<=0;
                    remote_done<=pending_remote;remote_error<=pending_remote;
                    route_cancel<=route_wait>=ROUTE_TIMEOUT_CYCLES-1;
                end else if(route_issued && route_done) begin
                    config_word<=pending_config;config_revision<=config_revision+1'b1;
                    config_busy<=0;route_issued<=0;remote_done<=pending_remote;
                end else if(route_valid && route_ready) route_issued<=1;
            end else if(AUDIO_ROUTE_HANDSHAKE!=0 && config_next[53:52]!=config_word[53:52]) begin
                // Reserve the entire settings transaction until every codec
                // write ACKs. Failure discards both source and other edits.
                pending_config<=config_next;pending_remote<=remote_commit && remote_ready;
                config_busy<=1;route_issued<=0;route_wait<=0;
            end else begin
                config_word<=config_next;
                if(config_next!=config_word) config_revision<=config_revision+1'b1;
                remote_done<=remote_commit && remote_ready;
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            main_view<=2;menu_level<=0;selected<=0;editing<=0;drum_parent<=2;
            changed<=0;
        end else begin
            changed<=remote_commit && remote_ready && config_next!=config_word;
            if(long_press)begin
                changed<=1;
                if(editing)editing<=0;
                else if(main_view==3 && menu_level!=0)begin selected<={2'd0,drum_parent};menu_level<=0;end
                else if(main_view==3 && selected!=0)selected<=0;
                else if(main_view!=2)begin
                    main_view<=previous_view(main_view);
                    selected<=0;menu_level<=0;
                end else if(menu_level!=0)begin menu_level<=0;selected<=8;end
                else if(selected!=0)selected<=0;
                else begin main_view<=4;selected<=0;end
            end else if(short_press)begin
                changed<=1;
                if(main_view==3 && menu_level==0 && selected==1)editing<=0;
                else if(main_view==3 && menu_level==0 && selected!=0)begin
                    drum_parent<=selected[2:0];menu_level<=(selected==3 || selected==5) ? 2:1;selected<=1;editing<=0;
                end
                else if(main_view==3 && menu_level!=0 && selected==0)begin selected<={2'd0,drum_parent};menu_level<=0;end
                else if(main_view==3 && selected!=0)editing<=!editing;
                else if(main_view!=2)begin main_view<=next_view(main_view);selected<=0;menu_level<=0;end
                else if(selected==0)begin
                    if(menu_level!=0)begin menu_level<=0;selected<=8;end
                    else begin main_view<=5;selected<=0;end
                end else if(menu_level==0 && selected==8)begin menu_level<=1;selected<=1;editing<=0;end
                else if(menu_level==0 && selected==10)editing<=0;
                else editing<=!editing;
            end else if(step_valid)begin
                changed<=1;
                if(main_view==3)begin
                    if(!editing)begin
                        if(step_up)selected<=selected==(menu_level==0 ? 5:3) ? 5'd0:selected+1'b1;
                        else selected<=selected==0 ? (menu_level==0 ? 5'd5:5'd3):selected-1'b1;
                    end
                end else if(main_view!=2)begin
                    main_view<=step_up ? next_view(main_view):previous_view(main_view);
                    selected<=0;menu_level<=0;editing<=0;
                end else if(!editing)begin
                    if(step_up)selected<=selected==(menu_level==1 ? 4:10) ? 5'd0:selected+1'b1;
                    else selected<=selected==0 ? (menu_level==1 ? 5'd4:5'd10):selected-1'b1;
                end else if((menu_level==1 && (selected<1 || selected>4)) || (menu_level==0 && (selected<1 || selected>9 || selected==8))) editing<=0;
            end
        end
    end
endmodule
