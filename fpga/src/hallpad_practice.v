`timescale 1ns/1ps
// HallBeat PracticeWire v1: 4096 x 24-byte records, sequential prefix upload,
// CRC32/record/binding validation before READY. RAM is never reset or used as
// an active song while receiving. Upload/validation and playback share one
// synchronous RAM port because their ownership phases never overlap.
module hallpad_practice #(
    parameter integer MAX_GROUPS=4096, COUNTDOWN_MS=3000
)(
    input wire clk,rst_n,ms_tick,session_valid,
    input wire [31:0] session_id,uptime_ms,
    input wire panic_latched,practice_allowed,
    input wire auto_play,output wire [34:0] auto_mask,output wire [6:0] auto_velocity,
    input wire [34:0] physical_mask,key_enabled,
    input wire [244:0] key_midi,
    input wire command_valid,
    output wire command_ready,
    input wire [7:0] command_type,command_length,
    output reg [7:0] payload_addr,
    input wire [7:0] payload_data,
    output reg command_done,
    output reg [7:0] command_code,response_type,response_length,
    output wire [383:0] response_packet,
    output wire notification_valid,
    input wire notification_take,
    output wire [7:0] notification_type,
    output wire [383:0] notification_packet,
    output wire [34:0] guide_mask,guide_yellow,guide_green,guide_red,
    output wire guide_long,guide_holding,guide_armed,guide_due,
    output wire local_result_valid,output wire [383:0] local_result_packet,output wire [2:0] local_run_phase,
    output wire [1:0] screen,countdown
);
    localparam integer MAX_BYTES=MAX_GROUPS*24;
    localparam integer ADDRESS_BITS=$clog2(MAX_BYTES);
    localparam [31:0] BYTE_CAPACITY=MAX_BYTES, GROUP_CAPACITY=MAX_GROUPS;
    localparam IDLE=0,HEADER_WAIT1=1,HEADER_WAIT2=2,HEADER_CAPTURE=3,DECODE=4,
        BIND_INIT=5,BIND_BYTE=6,BIND_CHECK=7,BEGIN_APPLY=8,COMMIT_INIT=9,
        SCAN_WAIT1=10,SCAN_WAIT2=11,SCAN_BYTE=12,SCAN_RECORD=13,
        DATA_WAIT1=14,DATA_WAIT2=15,DATA_BYTE=16,CONTROL_APPLY=17;
    reg [4:0] state,bind_return;
    reg [7:0] request_type,request_length,header_count,byte_index;
    reg [223:0] header;
    reg [31:0] known_session,upload_id,highest_upload_id,cancelled_id;
    reg object_exists,receiving,ready,binding_invalid;
    reg [12:0] groups;
    reg [31:0] total_bytes,received_bytes,expected_crc,binding_crc,song_duration;
    // Every accepted BEGIN field already lives in the object bank. Rebuild
    // its exact request for idempotency; do not store a second 224-bit copy.
    wire [223:0] begin_metadata={16'd1,16'd24,song_duration,binding_crc,
        expected_crc,total_bytes,19'd0,groups,upload_id};
    reg [31:0] upload_crc,scan_crc,previous_start,maximum_end;
    reg [34:0] bound_enabled,bind_enabled;
    reg [244:0] bound_midi,bind_midi;
    reg [31:0] bind_crc_work;
    reg [6:0] bind_index;
    reg [31:0] bind_expected;
    reg duplicate_data;
    reg [191:0] record_buffer;
    reg [12:0] scan_index;
    reg [4:0] record_byte;
    reg [ADDRESS_BITS-1:0] address_a;
    wire [2:0] phase;
    assign local_run_phase=phase;
    wire session_clear=!session_valid || known_session!=session_id;
    wire bound_diff,bind_diff;
    hallpad_binding_diff u_bound_diff(.a({bound_enabled,bound_midi}),.b({key_enabled,key_midi}),.different(bound_diff));
    hallpad_binding_diff u_bind_diff(.a({bind_enabled,bind_midi}),.b({key_enabled,key_midi}),.different(bind_diff));
    wire binding_changed=object_exists && bound_diff;
    wire binding_bad=binding_changed || binding_invalid;
    wire write_byte=state==DATA_BYTE && !duplicate_data && !session_clear && !binding_bad;
    (* syn_ramstyle="block_ram" *) reg [7:0] score_memory[0:MAX_BYTES-1];
    reg [7:0] memory_a;
    wire [7:0] memory_b=memory_a;
    reg [ADDRESS_BITS-1:0] address_b;
    wire [ADDRESS_BITS-1:0] memory_address=phase==1 ? address_b:address_a;
    always @(posedge clk)begin
        // GW5AST DPB does not implement READ_FIRST (WRITE_MODE=2'b10).
        // Explicit same-port bypass infers supported WRITE_FIRST (2'b01).
        // Upload ignores this readback; duplicate/CRC reads occur after writes.
        if(write_byte)begin
            score_memory[address_a]<=payload_data;
            memory_a<=payload_data;
        end else memory_a<=score_memory[memory_address];
    end
    function [31:0] crc32_byte(input [31:0] crc,input [7:0] value);
        reg [31:0] c;integer n;
        begin c=crc^{24'd0,value};for(n=0;n<8;n=n+1)c=c[0] ? (c>>1)^32'hedb88320:c>>1;crc32_byte=c;end
    endfunction
    wire [7:0] bind_byte=bind_index[0] ? {1'b0,bind_midi[6:0]}:{7'd0,bind_enabled[0]};
    // One byte CRC datapath is shared by three mutually exclusive FSM states.
    wire [31:0] crc_input=state==BIND_BYTE ? bind_crc_work:state==SCAN_BYTE ? scan_crc:upload_crc;
    wire [7:0] crc_byte=state==BIND_BYTE ? bind_byte:state==SCAN_BYTE ? memory_a:payload_data;
    wire [31:0] crc_next=crc32_byte(crc_input,crc_byte);
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
        begin
            ab={1'b0,count5(bits[4:0])}+{1'b0,count5(bits[9:5])};
            cd={1'b0,count5(bits[14:10])}+{1'b0,count5(bits[19:15])};
            ef={1'b0,count5(bits[24:20])}+{1'b0,count5(bits[29:25])};
            abcd={1'b0,ab}+{1'b0,cd};
            efg={1'b0,ef}+{2'b0,count5(bits[34:30])};
            popcount={1'b0,abcd}+{1'b0,efg};
        end
    endfunction
    wire [32:0] data_end={1'b0,header[63:32]}+{25'd0,request_length}-33'd8;
    wire [32:0] record_end={1'b0,record_buffer[63:32]}+{1'b0,record_buffer[95:64]};
    wire [31:0] next_max_end=record_end[31:0]>maximum_end ? record_end[31:0]:maximum_end;
    wire [5:0] record_count=popcount(record_buffer[130:96]);
    wire bad_record=record_buffer[31:0]!={19'd0,scan_index} ||
        (scan_index!=0 && record_buffer[63:32]<=previous_start) ||
        record_buffer[95:64]==0 || record_end>33'd86400000 ||
        record_buffer[159:131]!=0 || record_buffer[130:96]==0 ||
        (record_buffer[130:96] & ~bound_enabled)!=0 ||
        record_buffer[167:160]!={2'd0,record_count} ||
        record_buffer[175:168]==0 || record_buffer[175:168]>127 ||
        record_buffer[191:176]!=(record_count>1 ? 16'd1:16'd0);
    reg object_clear,run_start,run_pause,run_resume,run_stop;
    // DECODE has already checked upload/run identity, action/mode and all
    // reserved bytes. Speed is the only variable START field left to compare.
    reg [15:0] last_start_speed;
    wire [31:0] run_id,event_counter,correct,wrong,elapsed_ms,result_serial;
    wire [12:0] group_index;
    wire [34:0] target_mask;
    wire result_valid,record_request,record_valid;
    wire [11:0] playback_index;
    wire [191:0] playback_record;
    wire allowed=practice_allowed===1'b1;
    wire [383:0] result_packet;
    assign local_result_valid=result_valid;assign local_result_packet=result_packet;
    hallpad_practice_runner #(.COUNTDOWN_MS(COUNTDOWN_MS)) u_runner(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.session_clear(session_clear),
        .object_clear(object_clear),.binding_fault(binding_bad),
        .panic_latched(panic_latched),.practice_allowed(allowed),
        .auto_play(auto_play),.auto_mask(auto_mask),.auto_velocity(auto_velocity),.start(run_start),.pause(run_pause),.resume(run_resume),.stop(run_stop),
        .upload_id(upload_id),.start_run_id(header[63:32]),.score_crc(expected_crc),.uptime_ms(uptime_ms),
        .total_groups(groups),.start_speed(last_start_speed),.physical_mask(physical_mask),.key_enabled(key_enabled),
        .record_request(record_request),.record_index(playback_index),.record_valid(record_valid),.record_data(playback_record),
        .phase(phase),.run_id(run_id),.event_counter(event_counter),.correct(correct),.wrong(wrong),.group_index(group_index),
        .elapsed_ms(elapsed_ms),.target_mask(target_mask),.guide_mask(guide_mask),.guide_yellow(guide_yellow),.guide_green(guide_green),.guide_red(guide_red),
        .guide_long(guide_long),.guide_holding(guide_holding),.guide_armed(guide_armed),.guide_due(guide_due),
        .screen(screen),.countdown(countdown),.result_valid(result_valid),.result_serial(result_serial),.result_packet(result_packet));
    wire [383:0] status_packet={expected_crc,29'd0,target_mask,elapsed_ms,wrong,correct,
        19'd0,groups,19'd0,group_index,16'd0,8'd0,5'd0,phase,event_counter,run_id,upload_id};
    // The protocol controller takes an atomic snapshot on command_done. Avoid
    // storing a second 48-byte copy here before that same snapshot register.
    assign response_packet=response_type==8'h60 ?
        {256'd0,16'd24,16'd192,BYTE_CAPACITY,GROUP_CAPACITY,16'd1,16'd1}:
        response_type==8'h68 ? status_packet:response_type==8'h69 ? result_packet:384'd0;
    reg [31:0] notified_event,notified_result,last_notification_ms;
    wire status_due=event_counter!=notified_event || ((phase==1 || phase==2) && uptime_ms-last_notification_ms>=500);
    assign notification_valid=!session_clear && object_exists && !receiving && (ready || binding_bad) &&
        (status_due || (result_valid && result_serial!=notified_result));
    assign notification_type=status_due ? 8'h68:8'h69;
    assign notification_packet=status_due ? status_packet:result_packet;
    assign command_ready=state==IDLE && !session_clear;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin notified_event<=0;notified_result<=0;last_notification_ms<=0;end
        else if(session_clear)begin notified_event<=0;notified_result<=0;last_notification_ms<=uptime_ms;end
        else if(notification_valid && notification_take)begin
            if(status_due)begin notified_event<=event_counter;last_notification_ms<=uptime_ms;end
            else notified_result<=result_serial;
        end
    end
    // Shared synchronous read port; each record takes 72 clocks. Invalid
    // old loads are discarded on pause, object replacement and session changes.
    reg [1:0] load_state;
    reg [4:0] load_byte;
    reg [191:0] load_buffer;
    reg load_valid;
    wire [16:0] playback_base=({5'd0,playback_index}<<4)+({5'd0,playback_index}<<3);
    assign record_valid=load_valid;
    assign playback_record=load_buffer;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin load_state<=0;load_byte<=0;load_buffer<=0;load_valid<=0;address_b<=0;end
        else begin
            load_valid<=0;
            if(session_clear || object_clear || binding_bad || phase!=1 || run_pause || run_stop || panic_latched)load_state<=0;
            else case(load_state)
                0:if(record_request && ready)begin address_b<=playback_base[ADDRESS_BITS-1:0];load_byte<=0;load_buffer<=0;load_state<=1;end
                1:load_state<=2;
                2:load_state<=3;
                3:begin
                    load_buffer<={memory_b,load_buffer[191:8]};
                    if(load_byte==23)begin load_valid<=1;load_state<=0;end
                    else begin load_byte<=load_byte+1'b1;address_b<=address_b+1'b1;load_state<=1;end
                end
            endcase
        end
    end
    task answer(input [7:0] code);
        begin command_code<=code;command_done<=1;state<=IDLE;end
    endtask
    task begin_binding(input [31:0] expected,input [4:0] next_state);
        begin bind_expected<=expected;bind_return<=next_state;state<=BIND_INIT;end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;bind_return<=0;request_type<=0;request_length<=0;header_count<=0;byte_index<=0;header<=0;
            known_session<=0;upload_id<=0;highest_upload_id<=0;cancelled_id<=0;object_exists<=0;receiving<=0;ready<=0;binding_invalid<=0;
            groups<=0;total_bytes<=0;received_bytes<=0;expected_crc<=0;binding_crc<=0;song_duration<=0;
            upload_crc<=32'hffffffff;scan_crc<=0;previous_start<=0;maximum_end<=0;
            bound_enabled<=0;bound_midi<=0;bind_enabled<=0;bind_midi<=0;
            bind_crc_work<=0;bind_index<=0;bind_expected<=0;duplicate_data<=0;record_buffer<=0;scan_index<=0;record_byte<=0;address_a<=0;
            object_clear<=0;run_start<=0;run_pause<=0;run_resume<=0;run_stop<=0;last_start_speed<=0;
            payload_addr<=0;command_done<=0;command_code<=0;response_type<=0;response_length<=0;
        end else begin
            command_done<=0;object_clear<=0;run_start<=0;run_pause<=0;run_resume<=0;run_stop<=0;
            if(binding_changed)begin ready<=0;binding_invalid<=1;end
            if(session_clear)begin
                known_session<=session_id;object_exists<=0;receiving<=0;ready<=0;binding_invalid<=0;upload_id<=0;highest_upload_id<=0;cancelled_id<=0;
                received_bytes<=0;groups<=0;last_start_speed<=0;state<=IDLE;
                if(state!=IDLE)begin command_done<=1;command_code<=9;end
            end else case(state)
                IDLE:if(command_valid)begin
                    request_type<=command_type;request_length<=command_length;header<=0;byte_index<=0;payload_addr<=0;
                    response_type<=0;response_length<=0;command_code<=0;
                    if((command_type==8'h60 && command_length!=0) ||
                       (command_type==8'h61 && command_length!=28) ||
                       (command_type==8'h62 && (command_length<9 || command_length>200)) ||
                       (command_type==8'h63 && command_length!=12) ||
                       (command_type==8'h64 && command_length!=20) ||
                       ((command_type==8'h65 || command_type==8'h66) && command_length!=8) ||
                       (command_type==8'h67 && command_length!=4))answer(2);
                    else if(command_type==8'h60)state<=DECODE;
                    else begin header_count<=command_type==8'h62 ? 8'd8:command_length;state<=HEADER_WAIT1;end
                end
                HEADER_WAIT1:state<=HEADER_WAIT2;
                HEADER_WAIT2:state<=HEADER_CAPTURE;
                HEADER_CAPTURE:begin
                    // All five legal header sizes use fixed byte shifts;
                    // no 28-way variable byte write decoder is needed.
                    case(header_count)
                        4:header[31:0]<={payload_data,header[31:8]};
                        8:header[63:0]<={payload_data,header[63:8]};
                        12:header[95:0]<={payload_data,header[95:8]};
                        20:header[159:0]<={payload_data,header[159:8]};
                        default:header<={payload_data,header[223:8]};
                    endcase
                    if(byte_index+1'b1==header_count)state<=DECODE;
                    else begin byte_index<=byte_index+1'b1;payload_addr<=payload_addr+1'b1;state<=HEADER_WAIT1;end
                end
                DECODE:case(request_type)
                    8'h60:begin
                        response_type<=8'h60;response_length<=16;
                        answer(0);
                    end
                    8'h61:begin
                        if(phase==1 || phase==2)answer(5);
                        else if(header[31:0]==0 || header[63:32]==0 || header[63:32]>MAX_GROUPS ||
                            header[95:64]!=header[63:32]*24 || header[95:64]>MAX_BYTES ||
                            header[191:160]==0 || header[191:160]>86400000)answer(3);
                        else if(header[207:192]!=24 || header[223:208]!=1)answer(7);
                        else if(object_exists && header[31:0]==upload_id && header!=begin_metadata)answer(11);
                        else if(header[31:0]<=highest_upload_id && (!object_exists || header[31:0]!=upload_id))answer(11);
                        else begin_binding(header[159:128],BEGIN_APPLY);
                    end
                    8'h62:begin
                        if(!object_exists || header[31:0]!=upload_id)answer(3);
                        else if(binding_bad)answer(8);
                        else if(phase==1 || phase==2)answer(5);
                        else if(data_end>{1'b0,total_bytes} || header[63:32]>received_bytes ||
                            (header[63:32]<received_bytes && data_end>{1'b0,received_bytes}))answer(3);
                        else if(header[63:32]==received_bytes && !receiving)answer(5);
                        else begin
                            duplicate_data<=header[63:32]<received_bytes;byte_index<=8;payload_addr<=8;
                            address_a<=header[32 +:ADDRESS_BITS];state<=DATA_WAIT1;
                        end
                    end
                    8'h63:begin
                        if(!object_exists || header[31:0]!=upload_id)answer(3);
                        else if(binding_bad)answer(8);
                        else if(phase==1 || phase==2)answer(5);
                        else if(header[63:32]!=total_bytes || header[95:64]!=expected_crc || received_bytes!=total_bytes ||
                            (upload_crc^32'hffffffff)!=expected_crc)answer(10);
                        else if(ready)begin_binding(binding_crc,BEGIN_APPLY);
                        else begin_binding(binding_crc,COMMIT_INIT);
                    end
                    8'h64:begin
                        if(!object_exists || header[31:0]!=upload_id)answer(3);
                        else if(binding_bad)answer(8);
                        else if(!ready)answer(5);
                        else if(header[63:32]==0 || header[71:64]>3 || header[79:72]!=0 || header[159:96]!=0)answer(3);
                        else if(header[71:64]==0)begin
                            if(header[95:80]<500 || header[95:80]>2000)answer(3);
                            else begin_binding(binding_crc,CONTROL_APPLY);
                        end else state<=CONTROL_APPLY;
                    end
                    8'h65:begin
                        if(!object_exists || header[31:0]!=upload_id || header[63:32]!=run_id)answer(3);
                        else if(!ready && !binding_bad)answer(5);
                        else begin response_type<=8'h68;response_length<=48;answer(0);end
                    end
                    8'h66:begin
                        if(!result_valid || header[63:0]!=result_packet[63:0])answer(5);
                        else begin response_type<=8'h69;response_length<=48;answer(0);end
                    end
                    8'h67:begin
                        if(object_exists && header[31:0]==upload_id)begin
                            cancelled_id<=upload_id;object_exists<=0;receiving<=0;ready<=0;binding_invalid<=0;object_clear<=1;answer(0);
                        end else if(header[31:0]!=0 && header[31:0]==cancelled_id)answer(0);
                        else answer(3);
                    end
                    default:answer(1);
                endcase
                BIND_INIT:begin
                    bind_enabled<=key_enabled;bind_midi<=key_midi;
                    bind_index<=0;bind_crc_work<=32'hffffffff;state<=BIND_BYTE;
                end
                BIND_BYTE:begin
                    bind_crc_work<=crc_next;
                    // 35 complete rotations restore the exact snapshot before BIND_CHECK.
                    // This same bank supplies CRC bytes, the final race check
                    // and the accepted object binding; no duplicate shift bank.
                    if(bind_index[0])begin
                        bind_enabled<={bind_enabled[0],bind_enabled[34:1]};
                        bind_midi<={bind_midi[6:0],bind_midi[244:7]};
                    end
                    if(bind_index==69)state<=BIND_CHECK;else bind_index<=bind_index+1'b1;
                end
                BIND_CHECK:begin
                    if(bind_diff || (bind_crc_work^32'hffffffff)!=bind_expected)answer(8);
                    else state<=bind_return;
                end
                BEGIN_APPLY:begin
                    if(request_type==8'h61 && (!object_exists || header[31:0]!=upload_id))begin
                        object_exists<=1;receiving<=1;ready<=0;binding_invalid<=0;object_clear<=1;
                        upload_id<=header[31:0];highest_upload_id<=header[31:0];groups<=header[44:32];
                        total_bytes<=header[95:64];expected_crc<=header[127:96];binding_crc<=header[159:128];
                        song_duration<=header[191:160];received_bytes<=0;upload_crc<=32'hffffffff;
                        bound_enabled<=bind_enabled;bound_midi<=bind_midi;last_start_speed<=0;
                    end
                    answer(0);
                end
                DATA_WAIT1:state<=DATA_WAIT2;
                DATA_WAIT2:state<=DATA_BYTE;
                DATA_BYTE:begin
                    if(binding_bad)answer(8);
                    else if(duplicate_data && memory_a!=payload_data)answer(10);
                    else begin
                        if(!duplicate_data)upload_crc<=crc_next;
                        if(byte_index+1'b1==request_length)begin
                            if(!duplicate_data)received_bytes<=data_end[31:0];answer(0);
                        end else begin byte_index<=byte_index+1'b1;payload_addr<=payload_addr+1'b1;address_a<=address_a+1'b1;state<=DATA_WAIT1;end
                    end
                end
                COMMIT_INIT:begin
                    ready<=0;address_a<=0;scan_index<=0;record_byte<=0;record_buffer<=0;
                    scan_crc<=32'hffffffff;previous_start<=0;maximum_end<=0;state<=SCAN_WAIT1;
                end
                SCAN_WAIT1:state<=SCAN_WAIT2;
                SCAN_WAIT2:state<=SCAN_BYTE;
                SCAN_BYTE:begin
                    record_buffer<={memory_a,record_buffer[191:8]};scan_crc<=crc_next;
                    if(record_byte==23)state<=SCAN_RECORD;
                    else begin record_byte<=record_byte+1'b1;address_a<=address_a+1'b1;state<=SCAN_WAIT1;end
                end
                SCAN_RECORD:begin
                    if(binding_bad)answer(8);
                    else if(bad_record)answer(10);
                    else if(scan_index+1'b1==groups)begin
                        if(next_max_end!=song_duration || (scan_crc^32'hffffffff)!=expected_crc)answer(10);
                        else begin ready<=1;receiving<=0;answer(0);end
                    end else begin
                        scan_index<=scan_index+1'b1;previous_start<=record_buffer[63:32];maximum_end<=next_max_end;
                        address_a<=address_a+1'b1;record_byte<=0;record_buffer<=0;state<=SCAN_WAIT1;
                    end
                end
                CONTROL_APPLY:begin
                    if(binding_bad)answer(8);
                    else if(header[71:64]==0)begin
                        if(header[63:32]==run_id && run_id!=0)begin
                            if(header[95:80]==last_start_speed)answer(0);else answer(11);
                        end else if(header[63:32]<run_id)answer(11);
                        else if(phase!=0 && phase!=3 && phase!=4)answer(5);
                        else if(panic_latched || !allowed)answer(5);
                        else begin last_start_speed<=header[95:80];run_start<=1;answer(0);end
                    end else if(header[63:32]!=run_id)answer(3);
                    else case(header[71:64])
                        1:if(phase!=1 && phase!=2)answer(5);else begin run_pause<=phase==1;answer(0);end
                        2:if((phase!=1 && phase!=2) || panic_latched || !allowed)answer(5);else begin run_resume<=phase==2;answer(0);end
                        3:if(phase!=1 && phase!=2 && phase!=4)answer(5);else begin run_stop<=phase!=4;answer(0);end
                        default:answer(3);
                    endcase
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule

// Combinational, bounded-fan-in binding comparison. Keep the XOR layer
// separate from the reductions so this cannot become a 280-cell carry test.
module hallpad_binding_diff(input wire [279:0] a,b,output wire different);
    wire [279:0] bit_diff;
    (* syn_keep=1 *) wire [139:0] pair_diff;
    (* syn_keep=1 *) wire [34:0] byte_diff;
    (* syn_keep=1 *) wire [6:0] group_diff;
    assign bit_diff=a^b;
    genvar j;
    generate for(j=0;j<140;j=j+1)begin:g_pair
        assign pair_diff[j]=|bit_diff[j*2+:2];
    end
    for(j=0;j<35;j=j+1)begin:g_byte
        assign byte_diff[j]=|pair_diff[j*4+:4];
    end
    for(j=0;j<7;j=j+1)begin:g_group
        assign group_diff[j]=|byte_diff[j*5+:5];
    end endgenerate
    assign different=|group_diff;
endmodule
