`timescale 1ns/1ps
// WAIT practice uses only debounced physical sensors. Score time is a small
// permille accumulator; no division or sound generation is in this path.
module hallpad_practice_runner #(
    parameter integer COUNTDOWN_MS=3000, LONG_NOTE_MS=500
)(
    input wire clk,rst_n,ms_tick,session_clear,object_clear,binding_fault,
    input wire panic_latched,practice_allowed,
    input wire start,pause,resume,stop,
    input wire auto_play,output wire [34:0] auto_mask,output reg [6:0] auto_velocity,
    input wire [31:0] upload_id,start_run_id,score_crc,uptime_ms,
    input wire [12:0] total_groups,
    input wire [15:0] start_speed,
    input wire [34:0] physical_mask,key_enabled,
    output reg record_request,
    output wire [11:0] record_index,
    input wire record_valid,
    input wire [191:0] record_data,
    output reg [2:0] phase,
    output reg [31:0] run_id,event_counter,correct,wrong,
    output reg [12:0] group_index,
    output wire [31:0] elapsed_ms,
    output wire [34:0] target_mask,guide_mask,
    output wire [34:0] guide_yellow,guide_green,guide_red,
    output wire guide_long,guide_holding,guide_armed,guide_due,
    output wire [1:0] screen,countdown,
    output reg result_valid,
    output reg [31:0] result_serial,
    output reg [383:0] result_packet
);
    localparam LOAD=0,WAIT_RECORD=1,ARM=2,PLAY=3,HOLD=4,FINAL_SCORE=5;
    reg [2:0] stage;
    reg [31:0] started_ms,frozen_elapsed,score_time,hold_time;
    reg [31:0] note_start,note_duration;
    reg [34:0] expected,seen,previous_physical;
    reg [15:0] speed;
    reg [10:0] speed_fraction;
    reg [11:0] countdown_left;
    reg [32:0] score_remaining,score_denominator;
    reg [7:0] final_score;
    reg [31:0] run_upload,run_crc;
    reg [12:0] run_total;
    reg [6:0] note_velocity;reg [34:0] auto_hold;reg [31:0] auto_deadline;
    assign auto_mask=(auto_play===1'b1) && phase==1 && countdown_left==0 ? auto_hold:35'd0;
    wire [34:0] physical=physical_mask & key_enabled;
    wire [34:0] rising=physical & ~previous_physical;
    wire [34:0] seen_now=seen | (rising & expected);
    wire [11:0] speed_sum={1'b0,speed_fraction}+{1'b0,speed[10:0]};
    wire [1:0] score_step=speed_sum>=2000 ? 2:speed_sum>=1000 ? 1:0;
    wire [11:0] speed_remainder=speed_sum-(score_step==2 ? 12'd2000:score_step==1 ? 12'd1000:12'd0);
    wire active=phase==1 && countdown_left==0 && stage!=FINAL_SCORE;
    wire loaded=stage==ARM || stage==PLAY || stage==HOLD;
    wire exact_chord=seen_now==expected;
    // Do not put the speed/hold decision into the carry-in of the
    // 32-bit event counter. Its increment is an independent datapath;
    // the state machine selects the already-computed value.
    (* syn_keep=1 *) wire [31:0] next_event_counter=event_counter+32'd1;
    // Remaining hold distance depends only on registered times. For a step
    // in 0..2, the late speed result needs only a two-bit comparison; it
    // never traverses hold addition followed by a full-width comparison.
    (* syn_keep=1 *) wire [32:0] hold_gap={1'b0,note_duration}-{1'b0,hold_time};
    wire hold_complete=hold_gap[32] || ((~|hold_gap[31:2]) && hold_gap[1:0]<=score_step);
    wire [32:0] hold_next={1'b0,hold_time}+{31'd0,score_step};
    wire [5:0] wrong_edges=popcount(rising & ~expected);
    wire [32:0] wrong_next={1'b0,wrong}+{27'd0,wrong_edges};
    assign elapsed_ms=(phase==1 || phase==2) ? uptime_ms-started_ms:frozen_elapsed;
    assign record_index=group_index[11:0];
    assign target_mask=active && loaded ? expected:35'd0;
    assign guide_mask=target_mask;
    assign guide_long=note_duration>=LONG_NOTE_MS;
    assign guide_holding=active && stage==HOLD;
    assign guide_armed=active && (stage==PLAY || stage==HOLD);
    assign guide_due=score_time>=note_start;
    assign screen=phase==2 ? 2'd3:phase==1 ? (countdown_left!=0 ? 2'd1:2'd2):2'd0;
    assign countdown=countdown_left>2000 ? 2'd3:countdown_left>1000 ? 2'd2:countdown_left!=0 ? 2'd1:2'd0;
    // A five-input truth table fits directly in a LUT; balanced partial
    // sums avoid a 35-deep, full-width accumulator and its carry chains.
    function [2:0] count5(input [4:0] bits);
        begin case(bits)
            0:count5=0;
            1,2,4,8,16:count5=1;
            3,5,6,9,10,12,17,18,20,24:count5=2;
            7,11,13,14,19,21,22,25,26,28:count5=3;
            15,23,27,29,30:count5=4;
            default:count5=5;
        endcase end
    endfunction
    function [5:0] popcount(input [34:0] bits);
        reg [3:0] ab,cd,ef;
        reg [4:0] abcd,efg;
        reg [6:0] total_count;
        begin
            ab={1'b0,count5(bits[4:0])}+{1'b0,count5(bits[9:5])};
            cd={1'b0,count5(bits[14:10])}+{1'b0,count5(bits[19:15])};
            ef={1'b0,count5(bits[24:20])}+{1'b0,count5(bits[29:25])};
            abcd={1'b0,ab}+{1'b0,cd};
            efg={1'b0,ef}+{2'b0,count5(bits[34:30])};
            total_count={2'b0,abcd}+{2'b0,efg};
            popcount=total_count[5:0];
        end
    endfunction
    reg [34:0] yellow,green,wrong_lit;
    reg hold_feedback,hold_passed;
    reg [34:0] hold_feedback_mask;
    reg [31:0] light_deadline [0:34];
    reg [5:0] light_scan;
    reg [7:0] green_left;
    reg [4:0] blink_left;
    wire [34:0] hit_mask=active && stage==PLAY && score_time>=note_start ? rising & expected:35'd0;

    assign guide_yellow=yellow;
    assign guide_green=blink_left!=0 ? 35'd0:green;
    assign guide_red=(phase==1 || phase==2) ? wrong_lit:35'd0;
    integer light_i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin yellow<=0;green<=0;wrong_lit<=0;light_scan<=0;green_left<=0;blink_left<=0;end
        else if(session_clear || object_clear || binding_fault || start || stop)begin
            yellow<=0;green<=0;wrong_lit<=0;light_scan<=0;green_left<=0;blink_left<=0;
        end else begin
            wrong_lit<=(wrong_lit | (active && loaded ? rising & ~expected:35'd0)) & physical;
            light_scan<=light_scan==6'd34 ? 6'd0:light_scan+1'b1;
            if(ms_tick)begin
                if(blink_left!=0)blink_left<=blink_left-1'b1;
                if(green_left!=0)begin
                    green_left<=green_left-1'b1;
                    if(green_left==1)green<=0;
                end
            end
            if(hold_feedback)begin
                yellow<=yellow & ~hold_feedback_mask;
                green<=hold_passed ? hold_feedback_mask:35'd0;
                green_left<=hold_passed ? 100:0;blink_left<=0;
            end
            if(|hit_mask)begin
                // Each new hit clears the previous green feedback. A repeated
                // short note inserts a 20ms dark gap before its new green pulse.
                green<=note_duration<LONG_NOTE_MS ? hit_mask:35'd0;
                green_left<=note_duration<LONG_NOTE_MS ? 100:0;
                blink_left<=note_duration<LONG_NOTE_MS && |(green & hit_mask) ? 20:0;
                yellow<=(yellow & ~hit_mask) |
                    (note_duration>=LONG_NOTE_MS ? hit_mask:35'd0);
                for(light_i=0;light_i<35;light_i=light_i+1)
                    if(hit_mask[light_i])light_deadline[light_i]<=note_start+note_duration;
            end
        end
    end
    task complete_group(input passed);
        begin
            if(passed)correct<=correct+1'b1;seen<=0;hold_time<=0;
            event_counter<=next_event_counter;
            if(group_index+1'b1>=run_total)begin
                group_index<=run_total;expected<=0;stage<=FINAL_SCORE;
                frozen_elapsed<=uptime_ms-started_ms;
                // At natural WAIT completion correct == total; missed == 0.
                score_remaining<=({1'b0,correct}<<6)+({1'b0,correct}<<5)+({1'b0,correct}<<2)+(passed ? 33'd100:33'd0);
                score_denominator<={20'd0,run_total}+wrong_next;
                final_score<=0;
            end else begin group_index<=group_index+1'b1;expected<=0;stage<=LOAD;end
        end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            note_velocity<=100;auto_hold<=0;auto_deadline<=0;auto_velocity<=100;hold_feedback<=0;hold_passed<=0;hold_feedback_mask<=0;
            phase<=0;stage<=LOAD;run_id<=0;event_counter<=0;correct<=0;wrong<=0;group_index<=0;
            started_ms<=0;frozen_elapsed<=0;score_time<=0;hold_time<=0;note_start<=0;note_duration<=1;
            expected<=0;seen<=0;previous_physical<=0;speed<=1000;speed_fraction<=0;countdown_left<=0;
            record_request<=0;result_valid<=0;result_serial<=0;result_packet<=0;
            score_remaining<=0;score_denominator<=1;final_score<=0;run_upload<=0;run_crc<=0;run_total<=0;
        end else begin
            hold_feedback<=0;
            if(score_time>=auto_deadline || session_clear || object_clear || binding_fault || stop || start)auto_hold<=0;
            previous_physical<=physical;record_request<=0;
            if(session_clear)begin
                phase<=0;run_id<=0;expected<=0;seen<=0;countdown_left<=0;stage<=LOAD;
                group_index<=0;correct<=0;wrong<=0;result_valid<=0;event_counter<=0;result_serial<=0;
            end else if(object_clear)begin
                phase<=0;run_id<=0;expected<=0;seen<=0;countdown_left<=0;stage<=LOAD;
                group_index<=0;correct<=0;wrong<=0;frozen_elapsed<=0;event_counter<=next_event_counter;
            end else if(binding_fault)begin
                if(phase!=5)event_counter<=next_event_counter;
                phase<=5;expected<=0;seen<=0;countdown_left<=0;frozen_elapsed<=elapsed_ms;
            end else if(start)begin
                phase<=1;run_id<=start_run_id;event_counter<=next_event_counter;
                group_index<=0;correct<=0;wrong<=0;seen<=0;expected<=0;hold_time<=0;score_time<=0;
                started_ms<=uptime_ms;frozen_elapsed<=0;speed<=start_speed;speed_fraction<=0;
                countdown_left<=COUNTDOWN_MS;stage<=LOAD;
                run_upload<=upload_id;run_crc<=score_crc;run_total<=total_groups;
            end else if(stop && (phase==1 || phase==2))begin
                phase<=1;expected<=0;seen<=0;countdown_left<=0;frozen_elapsed<=elapsed_ms;stage<=FINAL_SCORE;
                run_total<=group_index+((countdown_left==0 && loaded && score_time>=note_start) ? 13'd1:13'd0);
                score_remaining<=({1'b0,correct}<<6)+({1'b0,correct}<<5)+({1'b0,correct}<<2);
                score_denominator<={20'd0,group_index}+{1'b0,wrong}+((countdown_left==0 && loaded && score_time>=note_start) ? 33'd1:33'd0);final_score<=0;
                event_counter<=next_event_counter;
            end else if((pause || panic_latched || !practice_allowed) && phase==1 && stage!=FINAL_SCORE)begin
                phase<=2;seen<=0;hold_time<=0;
                // A load crossing PAUSE is discarded and explicitly reloaded.
                stage<=LOAD;expected<=0;event_counter<=next_event_counter;
            end else if(resume && phase==2)begin
                phase<=1;seen<=0;hold_time<=0;stage<=LOAD;expected<=0;
                event_counter<=next_event_counter;
            end else if(phase==3)begin
                if(ms_tick)begin
                    speed_fraction<=speed_remainder[10:0];
                    score_time<=score_time+{30'd0,score_step};
                end
            end else if(phase==1)begin
                if(countdown_left!=0)begin
                    if(ms_tick)begin
                        countdown_left<=countdown_left-1'b1;
                        if(countdown_left==1)event_counter<=next_event_counter;
                    end
                end else begin
                    if(ms_tick && stage!=FINAL_SCORE)begin
                        speed_fraction<=speed_remainder[10:0];
                        if(score_time>32'hffffffff-{30'd0,score_step})begin
                            phase<=5;expected<=0;frozen_elapsed<=elapsed_ms;event_counter<=next_event_counter;
                        end else score_time<=score_time+{30'd0,score_step};
                    end
                    if(auto_play!==1'b1 && loaded && wrong_edges!=0)begin
                        if(wrong_next[32])begin phase<=5;expected<=0;frozen_elapsed<=elapsed_ms;end
                        else wrong<=wrong_next[31:0];
                        event_counter<=next_event_counter;
                    end
                    case(stage)
                        LOAD:begin record_request<=1;stage<=WAIT_RECORD;end
                        WAIT_RECORD:if(record_valid)begin
                            note_velocity<=record_data[174:168];expected<=record_data[130:96];note_start<=record_data[63:32];
                            note_duration<=record_data[95:64];seen<=0;hold_time<=0;stage<=ARM;
                            event_counter<=next_event_counter;
                        end
                        ARM:if(auto_play===1'b1)begin
                            if(score_time>=note_start)begin
                                auto_velocity<=note_velocity;auto_hold<=expected;auto_deadline<=note_start+note_duration;
                                if(group_index+1'b1>=run_total)stage<=PLAY;
                                else begin correct<=correct+1'b1;group_index<=group_index+1'b1;stage<=LOAD;event_counter<=next_event_counter;end
                            end
                        end else if((physical & expected)==0)begin seen<=0;stage<=PLAY;end
                        PLAY:if(auto_play===1'b1)begin
                            if(score_time>=note_start && score_time-note_start>=note_duration)complete_group(1'b1);
                        end else if(score_time>=note_start)begin
                            seen<=seen_now;
                            if(exact_chord)begin
                                if(note_duration<LONG_NOTE_MS)complete_group(1'b1);
                                else if(physical==expected)begin hold_time<=0;stage<=HOLD;end
                                else begin
                                    hold_feedback<=1;hold_passed<=0;hold_feedback_mask<=expected;
                                    complete_group(1'b0);
                                end
                            end
                        end
                        HOLD:begin
                            if((physical & expected)!=expected)begin
                                hold_feedback<=1;hold_passed<=0;hold_feedback_mask<=expected;
                                complete_group(1'b0);
                            end
                            else if(physical!=expected)hold_time<=0;
                            else if(ms_tick)begin
                                if(hold_complete && physical==expected)begin
                                    hold_feedback<=1;hold_passed<=1;hold_feedback_mask<=expected;
                                    complete_group(1'b1);
                                end
                                else hold_time<=hold_next[31:0];
                            end
                        end
                        FINAL_SCORE:begin
                            if(score_denominator!=0 && score_remaining>=score_denominator && final_score<100)begin
                                score_remaining<=score_remaining-score_denominator;final_score<=final_score+1'b1;
                            end else begin
                                phase<=3;event_counter<=next_event_counter;result_valid<=1;result_serial<=result_serial+1'b1;
                                result_packet<={32'd1,run_crc,16'd0,8'd0,final_score,frozen_elapsed,
                                    32'd0,32'd0,wrong,({19'd0,run_total}-correct),correct,{19'd0,run_total},run_id,run_upload};
                            end
                        end
                        default:stage<=LOAD;
                    endcase
                end
            end
        end
    end
endmodule
