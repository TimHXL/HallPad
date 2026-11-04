`timescale 1ns/1ps
// HallPad raw wire profile v1, P0. All command effects follow complete CRC
// validation. Reliable replies retain the exact request and response bytes in
// two small synchronous RAMs; retransmissions never reapply a transaction.
module hallpad_protocol_ctrl #(parameter [209:0] KEY_NOTE_MAP=0,parameter [63:0] DEVICE_ID=0,parameter integer SCORE_BEAT_SUPPORTED=0,DRUMSTICKS_SUPPORTED=1,REMOTE_KEYS_SUPPORTED=1,AUDIO_MIX_SUPPORTED=0,PRACTICE_SUPPORTED=0,SESSION_TIMEOUT_MS=3000,REMOTE_TIMEOUT_MS=1000,CACHE_MS=5000,STATUS_PERIOD_MS=1000)(input wire clk,rst_n,ms_tick,
 input wire sd_bridge_allowed,sd_block_ready,sd_block_done,sd_block_error,
 output wire sd_locked,sd_remount,sd_bridge_read,sd_bridge_write,output wire [31:0] sd_bridge_lba,
 input wire sd_read_valid,input wire [8:0] sd_read_address,input wire [7:0] sd_read_byte,
 input wire [8:0] sd_write_address,output wire [7:0] sd_write_byte,
 input wire score_sample_tick,score_audio_available,
 output wire score_external_mode,score_trigger,score_accent,score_clear,
output wire [34:0] practice_guide_mask,practice_yellow,practice_green,practice_red,output wire practice_guide_long,practice_guide_holding,practice_guide_armed,practice_guide_due,output wire [1:0] practice_screen,practice_countdown,output reg [127:0] drum_config,input wire offline_auto_play,output wire [34:0] offline_auto_mask,output wire [6:0] offline_auto_velocity,input wire offline_busy,offline_playback_owner,input wire [34:0] offline_fixed_mode,input wire [244:0] offline_fixed_velocity,input wire [139:0] offline_key_timbre,input wire offline_mapping_active,input wire [34:0] offline_key_enabled,input wire [244:0] offline_key_midi,output wire offline_result_valid,output wire [383:0] offline_result_packet,input wire offline_active,offline_command_valid,output wire offline_command_ready,input wire [7:0] offline_command_type,offline_command_length,output wire [7:0] offline_payload_addr,input wire [7:0] offline_payload_data,output wire offline_command_done,output wire [7:0] offline_command_code,output wire [2:0] offline_run_phase,input wire [95:0] drum_cal_status,input wire drum_cal_ready,output reg drum_cal_request,output reg [47:0] drum_light_config,output reg [31:0] drum_color_config,output reg [87:0] drum_effect_config,output reg drum_effect_active,input wire drum_edit_valid,drum_edit_stick,drum_edit_up,input wire [1:0] drum_edit_direction,output wire drum_edit_ready,input wire drum_allowed,output wire drum_sim_valid,input wire drum_sim_ready,output reg drum_sim_stick,output reg [1:0] drum_sim_direction,output reg [6:0] drum_sim_velocity,input wire drum_hit_valid,output wire drum_hit_ready,input wire [95:0] drum_hit_data,input wire transport_pause,output wire transport_idle,input wire adc_valid,input wire [5:0] adc_key,input wire [11:0] adc_value,output reg [255:0] extended_config,output reg signed [15:0] remote_bend,output reg [6:0] remote_modulation,input wire [31:0] uptime_ms,cycle_counter,input wire frame_valid,output wire frame_ready,input wire [7:0] version,message_type,flags,length,input wire [15:0] frame_seq,input wire [31:0] session_id,output wire [7:0] payload_addr,input wire [7:0] payload_data,output reg payload_release,output wire response_valid,input wire response_ready,output reg [7:0] response_type,response_flags,response_length,output reg [15:0] response_seq,output reg [31:0] response_session,input wire [7:0] response_addr,output reg [7:0] response_data,input wire response_done,input wire [63:0] config_data,input wire [31:0] config_revision,output wire [35:0] key_enabled,key_fixed_mode,output wire [251:0] key_midi,key_fixed_velocity,output wire [143:0] key_timbre,input wire parameter_ready,parameter_done,parameter_error,output wire parameter_commit,output wire [63:0] parameter_data,input wire remote_allowed,output wire remote_valid,input wire remote_ready,output reg remote_snapshot,output reg [5:0] remote_key,output reg remote_on,output reg [6:0] remote_velocity,output reg [35:0] remote_target_mask,output reg [251:0] remote_target_velocity,output reg clear_remote,panic_latched,input wire [34:0] physical_key_mask,input wire [35:0] remote_key_mask,voice_active,input wire [31:0] state_flags,error_bits,input wire [7:0] audio_source,input wire [15:0] active_timbre,output reg session_valid,output reg [31:0] current_session,output reg session_error);
    reg protocol_tick;
    always @(posedge clk or negedge rst_n)if(!rst_n)protocol_tick<=0;else protocol_tick<=ms_tick;
    localparam IDLE=0,DISPATCH=1,LOOKUP=2,COMPARE_WAIT=3,COMPARE=4,EXECUTE=5,PARAM_LOAD=6,PARAM_CHECK=8,COMMIT=9,COMMIT_DONE=10,GET_PARAM=11,SNAPSHOT_CHECK=12,REMOTE_ISSUE=13,PREPARE=14,STORE=15,SEND=16,REPLAY_WAIT=17,REPLAY=18,CONVERT=19,READ_WAIT1=20,READ_WAIT2=21,READ_CAPTURE=22,PARAM_DECODE=23,GET_DECODE=24,SNAPSHOT_DECODE=25,REPLY_WRITE=26,REPLY_DONE=27,GET_ADVANCE=28,STORE_COMMIT=29,WAIT_DONE=30,REPLAY_COMMIT=31;
    reg [50:0] state_bits;
    // Debug-only numeric view keeps the simulation probes readable. No
    // binary state encoder is present in the synthesized datapath.
    // synthesis translate_off
    reg [5:0] state;
    integer debug_state_index;
    always @* begin
        state=0;
        for(debug_state_index=0;debug_state_index<51;debug_state_index=debug_state_index+1)
            if(state_bits[debug_state_index])state=debug_state_index;
    end
    // synthesis translate_on
    localparam DRUM_ISSUE=43;




    localparam ADC_HEADER=39,ADC_RECORD=40,ADC_NEXT=41;
    // Eight u32 words: bend range (cents), remote enable, attack/release (ms),
    // RRGGBB, ripple speed (500..30000 milli-cells/s), fixed width=1000,
    // decay (ms). Shadowed with
    // normal parameters; failed batches never change either bank.
    reg [255:0] extended_shadow;
    // Transaction-local word differences: no 256-bit compare on commit paths.
    reg [7:0] extended_dirty;
    wire extended_changed=|extended_dirty;
    reg [31:0] performance_age;
    reg [11:0] adc_values[0:34];
    reg [34:0] adc_seen;
    reg [11:0] adc_snapshot[0:34];
    reg [2:0] subscriptions;
    reg [15:0] status_interval,adc_interval,adc_frame;
    reg [31:0] last_adc_ms,last_activity_ms;
    reg [34:0] last_activity_mask;
    integer ai,snapshot_index;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin adc_seen<=0;for(ai=0;ai<35;ai=ai+1) adc_values[ai]<=0;end
        else if(adc_valid && adc_key<35) begin adc_values[adc_key]<=adc_value;adc_seen[adc_key]<=1'b1;end
    end
    reg [7:0] req_type,req_flags,req_length,req_version;
    reg [15:0] req_seq;
    reg [31:0] req_session;
    // Parser retains the raw frame until payload_release. The request working
    // set is a ten-byte header and a single six-byte SET or two-byte GET record.
    reg [111:0] req_header;
    reg [31:0] key_revision;reg offline_map_seen;
    // An internal revision write reaches effective_revision in two clocks.
    // Carry that write strobe instead of comparing a 32-bit live counter on
    // every reply/commit enable. Same two-clock coherency contract.
    reg [1:0] key_revision_pending;
    // Break the revision -> sum -> compare -> commit -> menu revision loop.
    // A bank change invalidates the sampled sum for one cycle. Revision
    // consumers wait locally; byte RAM, parser and TX work never use this
    // epoch comparison as a global state-machine clock enable.
    localparam ACK_REPLY=42;
    reg [7:0] ack_code;
    reg [15:0] ack_detail;
    // Two-stage carry-select sum. Preserve the arithmetic register boundary:
    // a live menu revision must not feed a 32-bit carry chain and then the
    // protocol/commit decode in one clock. Epochs travel with their sum.
    (* syn_preserve=1 *) reg [31:0] effective_revision;
    (* syn_preserve=1 *) reg [31:0] revision_config_sample;
    (* syn_preserve=1 *) reg [31:0] revision_config_stage;
    (* syn_preserve=1 *) reg [8:0] revision_sum0,revision_sum1,revision_sum2,revision_sum3;
    (* syn_preserve=1 *) reg [7:0] revision_plus1,revision_plus2,revision_plus3;
    wire revision_carry1=revision_sum0[8];
    wire revision_carry2=revision_sum1[8] || ((&revision_sum1[7:0]) && revision_carry1);
    wire revision_carry3=revision_sum2[8] || ((&revision_sum2[7:0]) && revision_carry2);
    // Keep byte comparisons explicit; do not infer another wide subtractor.
    (* syn_keep=1 *) wire [3:0] revision_epoch_equal;
    genvar revision_byte;
    generate for(revision_byte=0;revision_byte<4;revision_byte=revision_byte+1) begin:g_revision_epoch
        assign revision_epoch_equal[revision_byte]=
            revision_config_sample[revision_byte*8+:8]==config_revision[revision_byte*8+:8];
    end endgenerate
    wire revision_current=(&revision_epoch_equal) && !(|key_revision_pending);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            effective_revision<=0;revision_config_sample<=0;
            revision_config_stage<=0;
            revision_sum0<=0;revision_sum1<=0;revision_sum2<=0;revision_sum3<=0;
            revision_plus1<=1;revision_plus2<=1;revision_plus3<=1;
        end else begin
            revision_sum0<={1'b0,config_revision[7:0]}+{1'b0,key_revision[7:0]};
            revision_sum1<={1'b0,config_revision[15:8]}+{1'b0,key_revision[15:8]};
            revision_sum2<={1'b0,config_revision[23:16]}+{1'b0,key_revision[23:16]};
            revision_sum3<={1'b0,config_revision[31:24]}+{1'b0,key_revision[31:24]};
            revision_plus1<=config_revision[15:8]+key_revision[15:8]+8'd1;
            revision_plus2<=config_revision[23:16]+key_revision[23:16]+8'd1;
            revision_plus3<=config_revision[31:24]+key_revision[31:24]+8'd1;
            revision_config_stage<=config_revision;
            effective_revision<={revision_carry3 ? revision_plus3:revision_sum3[7:0],
                                 revision_carry2 ? revision_plus2:revision_sum2[7:0],
                                 revision_carry1 ? revision_plus1:revision_sum1[7:0],revision_sum0[7:0]};
            revision_config_sample<=revision_config_stage;
        end
    end
    reg [63:0] key_mask;
    reg [15:0] key_fields;
    reg [55:0] key_values;
    reg [3:0] key_field;
    reg [7:0] key_offset,key_start,key_count;
    localparam KEY_VALIDATE=32,KEY_FIELD_LOAD=33,KEY_FIELD=34,KEY_COMMIT=35,KEY_DONE=36,KEY_GET=37,KEY_GET_NEXT=38;
    integer ki;
    function [6:0] natural_midi(input [5:0] n);begin case((n-1)%7)
        0:natural_midi=36+((n-1)/7)*12;1:natural_midi=38+((n-1)/7)*12;2:natural_midi=40+((n-1)/7)*12;3:natural_midi=41+((n-1)/7)*12;4:natural_midi=43+((n-1)/7)*12;5:natural_midi=45+((n-1)/7)*12;default:natural_midi=47+((n-1)/7)*12;endcase end endfunction
    wire [15:0] key_expected_length_full=16'd14+{7'd0,req_header[96]}+{7'd0,req_header[97]}+{6'd0,req_header[98],1'b0}+{7'd0,req_header[99]}+{7'd0,req_header[100]}+{7'd0,req_header[101]}+(req_header[102] ? 8'd3:8'd0);
    wire [7:0] key_expected_length=key_expected_length_full[7:0];
    wire [15:0] key_response_bytes=16'd6+times_ten(req_header[15:8]);
    wire [8:0] key_next_offset={1'b0,key_offset}+(key_field==2 ? 9'd2:9'd1);
    reg [5:0] count,item_index;
    wire [8:0] key_read_index={1'b0,key_start}+{3'd0,item_index};
    wire [19:0] key_get_bank[0:4];
    genvar get_bank,get_slot;
    generate for(get_bank=0;get_bank<5;get_bank=get_bank+1)begin:g_key_get_bank
        wire [19:0] words[0:7];
        assign words[0]=20'd0;
        for(get_slot=0;get_slot<7;get_slot=get_slot+1)begin:g_slot
            localparam integer KEY=get_bank*7+get_slot;
            wire selected=(key_read_index==KEY);
            wire [19:0] value=offline_mapping_active ? {offline_fixed_velocity[KEY*7+:7],offline_fixed_mode[KEY],offline_key_timbre[KEY*4+:4],offline_key_midi[KEY*7+:7],offline_key_enabled[KEY]}:{key_fixed_velocity[KEY*7+:7],key_fixed_mode[KEY],
                key_timbre[KEY*4+:4],key_midi[KEY*7+:7],key_enabled[KEY]};
            assign words[get_slot+1]=words[get_slot] | (value & {20{selected}});
        end
        assign key_get_bank[get_bank]=words[7];
    end endgenerate
    wire [19:0] hidden_get_word=key_read_index==35 ? {key_fixed_velocity[245+:7],key_fixed_mode[35],key_timbre[140+:4],key_midi[245+:7],key_enabled[35]}:20'd0;
    wire [19:0] key_get_word=hidden_get_word|key_get_bank[0]|key_get_bank[1]|key_get_bank[2]|key_get_bank[3]|key_get_bank[4];
    wire [15:0] key_reply_offset=16'd6+times_ten({2'd0,item_index});
    wire [8:0] parameter_record_offset=9'd5+{2'd0,item_index,1'b0}+{1'd0,item_index,2'd0};
    reg request_owned;
    localparam READ_HEADER=0,READ_RECORD=1,READ_BYTE=2;
    reg [1:0] read_kind;
    reg [3:0] read_index,read_count;
    reg [50:0] read_return;
    reg [47:0] read_record;
    reg [7:0] fetched_byte;
    reg [7:0] cache_index;
    wire [15:0] selected_get_id=read_record[15:0];
    wire [7:0] selected_snapshot=fetched_byte;
    wire selected_snapshot_on=remote_target_mask[item_index];
    wire [7:0] set_count=req_header[39:32],get_count=req_header[7:0];
    wire [10:0] set_request_bytes=11'd5+{2'd0,set_count,1'b0}+{1'd0,set_count,2'd0};
    wire [8:0] get_request_bytes=9'd1+{get_count,1'b0};
    wire [10:0] get_response_bytes=11'd5+{2'd0,get_count,1'b0}+{1'd0,get_count,2'd0};
    // The largest fixed reply is the 40-byte atomic status snapshot. GET
    // records are streamed directly to the byte RAM instead of copied whole.
    // Validate a request first; build its wide reply on a separate clock.
    localparam BUILD_FIXED_REPLY=46;
    reg [2:0] fixed_reply_kind;
    reg [383:0] reply_packet;
    reg [5:0] reply_index,reply_count;
    reg [50:0] reply_return;
    reg [7:0] reply_base;
    reg reply_write_enable;
    reg [7:0] reply_write_addr,reply_write_data;
    (* syn_ramstyle="block_ram" *) reg [7:0] reply_memory[0:255];
    wire [7:0] reply_read_address=(state_bits[SEND] || state_bits[WAIT_DONE]) ? response_addr:cache_index;
    always @(posedge clk) begin
        if(reply_write_enable) reply_memory[reply_write_addr]<=reply_write_data;
        response_data<=reply_memory[reply_read_address];
    end
    integer packet_slot;
    function [15:0] times_ten(input [7:0] value);begin
        times_ten={5'd0,value,3'd0}+{7'd0,value,1'b0};
    end endfunction
    reg [63:0] shadow;
    reg [31:0] base_revision,expected_revision;
    reg commit_config_changed;
    reg [15:0] item_id;
    reg [22:0] seen_parameters;
    reg [31:0] item_value;
    reg [15:0] convert_remaining;
    reg [15:0] convert_divisor;
    reg [7:0] convert_result;
    reg [3:0] convert_bits;
    reg [31:0] lfsr,boot_id,last_status_ms;
    reg boot_valid;
    reg [63:0] hello_request;
    reg [15:0] hello_seq,peer_max_payload,async_seq;
    reg [15:0] session_age,remote_age;
    reg remote_lease_valid;
    reg counter_valid;
    reg [15:0] state_counter;
    reg [7:0] error_age;
    reg cache_enable;
    reg [3:0] lookup_index,cache_slot,replace_slot;
    reg [15:0] cache_valid;
    reg [7:0] cached_type[0:15],cached_flags[0:15],cached_length[0:15];
    reg [7:0] cached_response_type[0:15],cached_response_flags[0:15],cached_response_length[0:15];
    reg [15:0] cached_seq[0:15];
    reg [31:0] cached_time[0:15];
    (* syn_ramstyle="block_ram" *) reg [7:0] request_memory[0:4095];
    (* syn_ramstyle="block_ram" *) reg [7:0] response_memory[0:4095];
    reg [7:0] request_byte,response_byte;
    wire [11:0] cache_address={cache_slot,cache_index};
    always @(posedge clk) begin
        // WRITE_FIRST byte-wide cache RAMs. Both source read pipelines have
        // settled before STORE_COMMIT writes either cache memory.
        if(state_bits[STORE_COMMIT] && cache_index<req_length) begin
            request_memory[cache_address]<=fetched_byte;request_byte<=fetched_byte;
        end else request_byte<=request_memory[cache_address];
        if(state_bits[STORE_COMMIT] && cache_index<response_length) begin
            response_memory[cache_address]<=response_data;response_byte<=response_data;
        end else response_byte<=response_memory[cache_address];
    end
    wire session_expiring=protocol_tick && session_valid && session_age>=SESSION_TIMEOUT_MS-1 && !state_bits[50];
    wire remote_expiring=protocol_tick && remote_lease_valid && remote_age>=REMOTE_TIMEOUT_MS-1;
    reg [3:0] session_equal_q;
    genvar sb;
    generate for(sb=0;sb<4;sb=sb+1)begin:g_session_equal
        always @(posedge clk or negedge rst_n)if(!rst_n)session_equal_q[sb]<=0;
        else session_equal_q[sb]<=current_session[sb*8+:8]==req_session[sb*8+:8];
    end endgenerate
    wire request_session_match=&session_equal_q;
    localparam SESSION_CHECK=7;
    localparam BEAT_ISSUE=47,BEAT_WAIT=48;
    reg beat_request,beat_free_pulse,beat_free_dirty;
    wire beat_done;wire [7:0] beat_result;wire [15:0] beat_detail;
    wire beat_gate=session_valid && !session_expiring && request_session_match;
    hallpad_score_beat u_score_beat(.clk(clk),.rst_n(rst_n),.ms_tick(protocol_tick),
      .sample_tick(score_sample_tick),.session_valid(session_valid && !session_expiring),
      .session_id(current_session),.panic(panic_latched),.audio_available(score_audio_available),
      .request(beat_request && beat_gate),.is_trigger(req_type==8'h47),.data(req_header[79:0]),
      .free_select(beat_free_pulse),.done(beat_done),.result(beat_result),.detail(beat_detail),
      .external_mode(score_external_mode),.trigger(score_trigger),.accent(score_accent),.clear_click(score_clear));

    wire same_revision=base_revision==effective_revision;
    wire expected_ok=expected_revision==32'hffffffff || expected_revision==effective_revision;
    assign parameter_commit=revision_current && state_bits[COMMIT] && !session_expiring && session_valid && request_session_match && parameter_ready && same_revision && expected_ok;
    assign parameter_data=shadow;
    assign remote_valid=state_bits[REMOTE_ISSUE] && !offline_playback_owner && !session_expiring && !remote_expiring && session_valid && request_session_match && (remote_allowed || (remote_snapshot ? remote_target_mask==0:!remote_on));
    wire paused=transport_pause===1'b1;
    wire [63:0] selected_drum_config=(req_header[0] ? drum_config[127:64]:drum_config[63:0]);
    assign drum_sim_valid=state_bits[DRUM_ISSUE] && session_valid && request_session_match && !session_expiring && !panic_latched && (drum_allowed===1'b1);


    assign transport_idle=state_bits[IDLE];
    // synthesis translate_off
    always @(posedge clk)if(rst_n && !$onehot(state_bits))$fatal(1,"protocol state is not one-hot");
    // synthesis translate_on
    reg [1:0] drum_dirty;
    wire local_drum_request=(drum_edit_valid===1'b1) && DRUMSTICKS_SUPPORTED!=0;
    assign drum_edit_ready=state_bits[IDLE] && !frame_valid && !paused && !session_expiring && revision_current;
    wire [6:0] local_voice_offset=(drum_edit_stick ? 7'd64:7'd0)+{2'd0,drum_edit_direction,3'd0};
    wire [7:0] local_old_voice=drum_config[local_voice_offset +:8];
    wire [7:0] local_new_voice=drum_edit_up ? (local_old_voice==255 ? 8'd0:local_old_voice>=5 ? 8'd255:local_old_voice+1'b1):
        (local_old_voice==255 ? 8'd5:local_old_voice==0 ? 8'd255:local_old_voice-1'b1);
    wire drum_local_take=local_drum_request && drum_edit_ready && drum_edit_direction<3;
    wire drum_notify_take=state_bits[IDLE] && !frame_valid && !paused && session_valid && !session_expiring &&
        !local_drum_request && revision_current && (|drum_dirty) && !(drum_hit_valid===1'b1);
    wire notify_stick=!drum_dirty[0];
    wire [63:0] notify_config=notify_stick ? drum_config[127:64]:drum_config[63:0];
    assign drum_hit_ready=state_bits[IDLE] && !frame_valid && !drum_local_take && !paused && session_valid && !session_expiring && DRUMSTICKS_SUPPORTED!=0;
    assign frame_ready=state_bits[IDLE] && !session_expiring && !paused;
    assign response_valid=state_bits[SEND];
    wire [31:0] cache_age=uptime_ms-cached_time[lookup_index];
    wire [15:0] counter_delta=req_header[15:0]-state_counter;
    wire [15:0] volume_permille=times_ten({1'b0,config_data[6:0]});
    wire [31:0] new_boot=(req_header[47:16]^cycle_counter^32'h7f4a7c15);
    reg [31:0] next_session;
    always @* begin
        next_session=lfsr^req_header[47:16]^cycle_counter;
        if(next_session==0 || next_session==current_session) next_session=current_session+32'h9e3779b9;
        if(next_session==0) next_session=1;
    end
    function sound_ok(input [31:0] v);begin sound_ok=(v>=1 && v<=9) || v==11 || v==13 || v==14;end endfunction
    // Only the explicitly listed IDs are writable/readable. A bitmap preserves
    // duplicate rejection without storing and scanning 37 full-width IDs.
    function [22:0] parameter_flag(input [15:0] pid);begin case(pid)
        16'h0001:parameter_flag=14'h0001;16'h0002:parameter_flag=14'h0002;
        16'h0003:parameter_flag=14'h0004;16'h0040:parameter_flag=14'h0008;
        16'h0041:parameter_flag=14'h0010;16'h0042:parameter_flag=14'h0020;
        16'h0050:parameter_flag=14'h0040;16'h0051:parameter_flag=14'h0080;
        16'h0052:parameter_flag=14'h0100;16'h0053:parameter_flag=14'h0200;
        16'h0060:parameter_flag=14'h0400;16'h0061:parameter_flag=14'h0800;
        16'h0070:parameter_flag=14'h1000;16'h0080:parameter_flag=14'h2000;
        16'h0005:parameter_flag=22'h004000;16'h0071:parameter_flag=22'h008000;
        16'h0013:parameter_flag=22'h010000;16'h0021:parameter_flag=22'h020000;
        16'h0062:parameter_flag=22'h040000;16'h0063:parameter_flag=22'h080000;
        16'h0064:parameter_flag=22'h100000;16'h0065:parameter_flag=22'h200000;
        16'h0090:parameter_flag=AUDIO_MIX_SUPPORTED!=0 ? 23'h400000:23'd0;
        default:parameter_flag=0;
    endcase end endfunction
    function supported_param(input [15:0] pid);begin supported_param=|parameter_flag(pid);end endfunction
    wire [22:0] item_flag=parameter_flag(item_id);
    function [31:0] read_param(input [15:0] pid,input [63:0] cfg,input [7:0] source);
    reg [15:0] brightness_scaled;begin
        // All 64 possible brightness field values fit in sixteen bits.
        brightness_scaled={cfg[16:11],10'd0}-{5'd0,cfg[16:11],5'd0}+{7'd0,cfg[16:11],3'd0}+16'd16;
        case(pid)
        16'h0001:read_param={16'd0,times_ten({1'b0,cfg[6:0]})};
        16'h0002:read_param={28'd0,cfg[10:7]};16'h0003:read_param={24'd0,source};
        16'h0040:read_param={31'd0,cfg[26]};16'h0041:read_param=0;16'h0042:read_param={16'd0,times_ten({1'b0,cfg[25:19]})};
        16'h0050:read_param={31'd0,cfg[35]};16'h0051:read_param={16'd0,times_ten(cfg[51:44])};
        16'h0052:read_param={28'd0,cfg[39:36]};16'h0053:read_param={28'd0,cfg[43:40]};
        16'h0060:read_param={30'd0,cfg[18:17]};16'h0061:read_param={21'd0,brightness_scaled[15:5]};
        16'h0090:read_param={30'd0,cfg[53:52]};
        16'h0070:read_param={16'd0,times_ten({1'b0,cfg[33:27]})};16'h0080:read_param={31'd0,cfg[34]};default:read_param=0;
    endcase end endfunction
    function [31:0] read_extended(input [15:0] pid,input [255:0] ext);begin case(pid)
        5:read_extended=ext[31:0];16'h71:read_extended=ext[63:32];
        16'h13:read_extended=ext[95:64];16'h21:read_extended=ext[127:96];
        16'h62:read_extended=ext[159:128];16'h63:read_extended=ext[191:160];
        16'h64:read_extended=ext[223:192];16'h65:read_extended=ext[255:224];
        default:read_extended=0;endcase end endfunction
    function is_extended_parameter(input [15:0] pid);begin case(pid)
        16'h0005,16'h0071,16'h0013,16'h0021,16'h0062,16'h0063,16'h0064,16'h0065:is_extended_parameter=1;
        default:is_extended_parameter=0;endcase end endfunction
    wire [31:0] selected_get_value=is_extended_parameter(selected_get_id) ? read_extended(selected_get_id,extended_shadow):read_param(selected_get_id,shadow,audio_source);
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
    localparam PRACTICE_START=44,PRACTICE_WAIT=45;
    reg [7:0] normal_payload_addr;
    wire [7:0] practice_payload_addr,practice_code,practice_reply_type,practice_reply_length,practice_notify_type;
    wire [383:0] practice_reply_packet,practice_notify_packet;
    wire practice_ready,practice_done,practice_notify_valid;
    wire practice_notify_take=!offline_active && state_bits[IDLE] && !frame_valid && !paused && session_valid && !session_expiring &&
        !(DRUMSTICKS_SUPPORTED!=0 && drum_hit_valid===1'b1) && !drum_local_take && !drum_notify_take && practice_notify_valid;
    assign offline_payload_addr=practice_payload_addr;
    assign offline_command_ready=practice_ready && offline_active;
    assign offline_command_done=practice_done && offline_active;
    assign offline_command_code=practice_code;
    localparam SD_START=49,SD_WAIT=50;
    wire sd_cmd_ready,sd_cmd_done;wire [7:0] sd_cmd_code,sd_payload_addr;wire [383:0] sd_reply;
    hallpad_sd_bridge u_sd_bridge(.clk(clk),.rst_n(rst_n),.session_valid(session_valid && !session_expiring),.allowed(sd_bridge_allowed),
     .command_valid(state_bits[SD_START] && session_valid && request_session_match && !session_expiring),.command_length(req_length),
     .command_ready(sd_cmd_ready),.command_done(sd_cmd_done),.command_code(sd_cmd_code),.reply(sd_reply),.payload_addr(sd_payload_addr),.payload_data(payload_data),
     .locked(sd_locked),.remount(sd_remount),.block_ready(sd_block_ready),.block_done(sd_block_done),.block_error(sd_block_error),
     .read_request(sd_bridge_read),.write_request(sd_bridge_write),.block_lba(sd_bridge_lba),.read_valid(sd_read_valid),.read_address(sd_read_address),.read_byte(sd_read_byte),.write_address(sd_write_address),.write_byte(sd_write_byte));
    assign payload_addr=(state_bits[SD_START] || state_bits[SD_WAIT]) ? sd_payload_addr:(state_bits[PRACTICE_START] || state_bits[PRACTICE_WAIT]) ? practice_payload_addr:normal_payload_addr;
    generate if(PRACTICE_SUPPORTED!=0)begin:g_practice
        assign offline_result_valid=practice_result_valid;
        assign offline_result_packet=practice_result_packet;
        wire practice_result_valid;wire [383:0] practice_result_packet;
        hallpad_practice u_practice(.auto_play(offline_active && offline_auto_play),.auto_mask(offline_auto_mask),.auto_velocity(offline_auto_velocity),.local_result_valid(practice_result_valid),.local_result_packet(practice_result_packet),
            .clk(clk),.rst_n(rst_n),.ms_tick(protocol_tick),.session_valid(offline_active || (session_valid && !session_expiring)),
            .session_id(offline_active ? 32'h4c4f434c:current_session),.uptime_ms(uptime_ms),.panic_latched(panic_latched),.practice_allowed(remote_allowed),
            .physical_mask(physical_key_mask),.key_enabled(offline_mapping_active ? offline_key_enabled:key_enabled[34:0]),.key_midi(offline_mapping_active ? offline_key_midi:key_midi[244:0]),
            .command_valid(offline_active ? offline_command_valid:(state_bits[PRACTICE_START] && session_valid && !session_expiring && request_session_match)),
            .command_ready(practice_ready),.command_type(offline_active ? offline_command_type:req_type),.command_length(offline_active ? offline_command_length:req_length),
            .payload_addr(practice_payload_addr),.payload_data(offline_active ? offline_payload_data:payload_data),.command_done(practice_done),
            .command_code(practice_code),.response_type(practice_reply_type),.response_length(practice_reply_length),.response_packet(practice_reply_packet),
            .notification_valid(practice_notify_valid),.notification_take(offline_active || practice_notify_take),
            .notification_type(practice_notify_type),.notification_packet(practice_notify_packet),
            .guide_mask(practice_guide_mask),.guide_yellow(practice_yellow),.guide_green(practice_green),.guide_red(practice_red),.guide_long(practice_guide_long),.guide_holding(practice_guide_holding),
            .guide_armed(practice_guide_armed),.guide_due(practice_guide_due),.screen(practice_screen),.countdown(practice_countdown),.local_run_phase(offline_run_phase));
    end else begin:g_no_practice
        assign offline_auto_mask=0;assign offline_auto_velocity=0;assign offline_result_valid=0;assign offline_result_packet=0;assign offline_run_phase=0;
        assign practice_payload_addr=0;assign practice_ready=0;assign practice_done=0;assign practice_code=7;
        assign practice_reply_type=0;assign practice_reply_length=0;assign practice_reply_packet=0;
        assign practice_notify_valid=0;assign practice_notify_type=0;assign practice_notify_packet=0;
        assign practice_guide_mask=0;assign practice_yellow=0;assign practice_green=0;assign practice_red=0;assign practice_guide_long=0;assign practice_guide_holding=0;
        assign practice_guide_armed=0;assign practice_guide_due=0;assign practice_screen=0;assign practice_countdown=0;
    end endgenerate

    task release_request;begin
        if(request_owned) begin payload_release<=1;request_owned<=0;end
    end endtask
    task finish_request;begin release_request();state_bits<=(51'd1<<IDLE);end endtask
    // Address changes on an edge; two explicit wait states let a synchronous
    // parser RAM read settle before capture, including nonblocking assignments.
    task start_read(input [7:0] address,input [3:0] amount,input [1:0] kind,input [5:0] return_to);begin
        normal_payload_addr<=address+{4'd0,amount}-8'd1;read_index<=0;read_count<=amount;read_kind<=kind;
        read_return<=(51'd1<<return_to);read_record<=0;state_bits<=(51'd1<<READ_WAIT1);
    end endtask
    task write_reply(input [383:0] packet,input [5:0] amount,input [7:0] address,input [5:0] return_to);begin
        reply_packet<=packet;reply_count<=amount;reply_index<=0;
        reply_base<=address;reply_return<=(51'd1<<return_to);state_bits<=(51'd1<<REPLY_WRITE);
    end endtask
    task next_parameter;begin if(item_index==count-1'b1) state_bits<=(51'd1<<COMMIT);else begin item_index<=item_index+1'b1;state_bits<=(51'd1<<PARAM_LOAD);end end endtask
    task live;begin if(!session_expiring) begin session_age<=0;if(session_valid && request_session_match) session_valid<=1;end end endtask
    task ack(input [7:0] code,input [15:0] detail);begin
        if(code!=0 && error_age<100) finish_request();
        else begin
            if(code!=0) error_age<=0;
            // One small reply state owns revision waiting. Do not broadcast
            // revision_current to every byte-transfer and configuration flop.
            ack_code<=code;ack_detail<=detail;state_bits<=(51'd1<<ACK_REPLY);
        end
    end endtask
    task status_reply;begin
        fixed_reply_kind<=0;state_bits<=(51'd1<<BUILD_FIXED_REPLY);
    end endtask
    task hello_reply(input [31:0] sid,input [31:0] boot);begin
        response_type<=1;response_flags<=2;response_length<=24;response_session<=sid;reply_packet<=0;
        reply_packet[7:0]<=0;reply_packet[15:8]<=1;reply_packet[47:16]<=req_header[47:16];
        reply_packet[111:48]<=DEVICE_ID;reply_packet[143:112]<=boot;
        reply_packet[159:144]<=16'd229;reply_packet[175:160]<=16'd250;
        reply_packet[191:176]<=REMOTE_TIMEOUT_MS;reply_count<=24;reply_index<=0;reply_base<=0;reply_return<=(51'd1<<PREPARE);state_bits<=(51'd1<<REPLY_WRITE);
    end endtask
    wire key_commit_apply=state_bits[KEY_COMMIT] && !offline_busy && !offline_mapping_active && revision_current && session_valid &&
        request_session_match && !session_expiring && expected_ok && same_revision && parameter_ready &&
        !(|(key_mask[35:0] & ({1'b0,physical_key_mask}|remote_key_mask|(voice_active & 36'h7ffffffff))));
    localparam [215:0] EXTENDED_KEY_NOTE_MAP={6'd0,KEY_NOTE_MAP};
    genvar config_key;
    generate for(config_key=0;config_key<36;config_key=config_key+1)begin:g_key_config
        localparam [6:0] DEFAULT_NOTE=config_key==35 ? 7'd60:natural_midi(EXTENDED_KEY_NOTE_MAP[config_key*6+:6]);
        reg en,fixed;reg [6:0] midi,velocity;reg [3:0] timbre;
        wire selected=key_commit_apply && key_mask[config_key];
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin en<=1;fixed<=0;midi<=DEFAULT_NOTE;velocity<=100;timbre<=0;end
            else if(selected)begin
                if(key_fields[0])en<=key_values[0];
                if(key_fields[1])midi<=key_values[14:8];
                if(key_fields[2])timbre<=key_values[31:16]==16'hffff ? 4'd0:key_values[19:16];
                if(key_fields[3])fixed<=key_values[32];
                if(key_fields[4])velocity<=key_values[46:40];
            end
        end
        assign key_enabled[config_key]=en;assign key_fixed_mode[config_key]=fixed;
        assign key_midi[config_key*7+:7]=midi;assign key_fixed_velocity[config_key*7+:7]=velocity;
        assign key_timbre[config_key*4+:4]=timbre;
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            beat_request<=0;beat_free_pulse<=0;beat_free_dirty<=0;
            extended_config<={32'd1200,32'd1000,32'd5000,32'h0000dc78,32'd400,32'd0,32'd1,32'd200};
            extended_shadow<=0;extended_dirty<=0;performance_age<=0;remote_bend<=0;remote_modulation<=0;
            subscriptions<=1;status_interval<=STATUS_PERIOD_MS;adc_interval<=100;adc_frame<=0;
            last_adc_ms<=0;last_activity_ms<=0;last_activity_mask<=0;
            for(snapshot_index=0;snapshot_index<35;snapshot_index=snapshot_index+1) adc_snapshot[snapshot_index]<=0;
            ack_code<=0;ack_detail<=0;
            key_revision<=0;offline_map_seen<=0;key_revision_pending<=0;key_mask<=0;key_fields<=0;key_values<=0;key_field<=0;key_offset<=0;key_start<=0;key_count<=0;

            drum_effect_config<={24'hff7020,16'd1200,32'd80000,8'd10,8'd0};drum_effect_active<=1;drum_color_config<=32'hff702000;drum_cal_request<=0;drum_light_config<={16'd1200,16'd40,8'd10,8'd1};
            drum_dirty<=0;drum_config<={64'h008200a07f050403,64'h008200a07f020100};drum_sim_stick<=0;drum_sim_direction<=0;drum_sim_velocity<=0;
            state_bits<=(51'd1<<IDLE);req_type<=0;req_flags<=0;req_length<=0;req_version<=0;req_seq<=0;req_session<=0;req_header<=0;request_owned<=0;normal_payload_addr<=0;payload_release<=0;read_kind<=0;read_index<=0;read_count<=0;read_return<=0;read_record<=0;fetched_byte<=0;
            shadow<=0;base_revision<=0;commit_config_changed<=0;expected_revision<=0;count<=0;item_index<=0;seen_parameters<=0;item_id<=0;item_value<=0;convert_remaining<=0;convert_divisor<=0;convert_result<=0;convert_bits<=0;
            lfsr<=32'h8d12e5a7;boot_id<=0;boot_valid<=0;last_status_ms<=0;hello_request<=0;hello_seq<=0;peer_max_payload<=229;async_seq<=0;
            session_age<=0;remote_age<=0;remote_lease_valid<=0;counter_valid<=0;state_counter<=0;error_age<=100;
            cache_enable<=0;lookup_index<=0;cache_slot<=0;replace_slot<=0;cache_index<=0;cache_valid<=0;
            fixed_reply_kind<=0;response_type<=0;response_flags<=0;response_length<=0;response_seq<=0;response_session<=0;reply_packet<=0;reply_index<=0;reply_count<=0;reply_return<=0;reply_base<=0;reply_write_enable<=0;reply_write_addr<=0;reply_write_data<=0;
            remote_snapshot<=0;remote_key<=0;remote_on<=0;remote_velocity<=0;remote_target_mask<=0;remote_target_velocity<=0;
            clear_remote<=0;panic_latched<=0;session_valid<=0;current_session<=0;session_error<=0;
        end else begin
            beat_request<=0;beat_free_pulse<=0;
            drum_cal_request<=0;
            key_revision_pending<={key_revision_pending[0],1'b0};
            if(offline_map_seen!=offline_mapping_active)begin
             offline_map_seen<=offline_mapping_active;key_revision<=key_revision+1'b1;key_revision_pending[0]<=1;
            end
            lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};clear_remote<=0;session_error<=0;payload_release<=0;reply_write_enable<=0;
            if(protocol_tick) begin
                if(performance_age<REMOTE_TIMEOUT_MS) performance_age<=performance_age+1'b1;else begin remote_bend<=0;remote_modulation<=0;end
                if(error_age<100) error_age<=error_age+1'b1;
                if(session_valid) begin
                    if(session_age>=SESSION_TIMEOUT_MS-1 && !state_bits[50]) begin session_valid<=0;clear_remote<=1;cache_valid<=0;counter_valid<=0;remote_lease_valid<=0;end
                    else session_age<=session_age+1'b1;
                end
                if(remote_lease_valid) begin
                    if(remote_age>=REMOTE_TIMEOUT_MS-1) begin clear_remote<=1;remote_lease_valid<=0;end
                    else remote_age<=remote_age+1'b1;
                end
            end
            // A HELLO crossing the old session's expiry retries this FSM edge
            // after invalidation. Already committed replies remain unchanged.
            if(session_expiring && request_owned && req_type==1 && !state_bits[SEND] && !state_bits[WAIT_DONE]) begin
                state_bits<=state_bits;
            end else case(1'b1) /* synthesis parallel_case */
                state_bits[IDLE]:if(frame_valid && frame_ready) begin
                    req_type<=message_type;req_flags<=flags;req_length<=length;req_version<=version;req_seq<=frame_seq;req_session<=session_id;req_header<=0;request_owned<=1;
                    response_seq<=frame_seq;response_session<=session_id;response_flags<=2;cache_enable<=0;
                    if(length==0) state_bits<=(51'd1<<SESSION_CHECK);else start_read(0,length<14 ? length[3:0]:4'd14,READ_HEADER,SESSION_CHECK);
                end else if(drum_local_take)begin
                    drum_config[local_voice_offset +:8]<=local_new_voice;
                    begin key_revision<=key_revision+1'b1;key_revision_pending[0]<=1;end drum_dirty[drum_edit_stick]<=1;
                end else if(drum_hit_ready && (drum_hit_valid===1'b1)) begin
                    response_seq<=async_seq;async_seq<=async_seq+1'b1;response_session<=current_session;response_flags<=0;cache_enable<=0;
                    response_type<=8'h75;response_length<=12;
                    write_reply({224'd0,drum_hit_data},12,0,PREPARE);
                end else if(drum_notify_take)begin
                    response_seq<=async_seq;async_seq<=async_seq+1'b1;response_session<=current_session;
                    response_flags<=0;cache_enable<=0;response_type<=8'h74;response_length<=9;
                    drum_dirty[notify_stick]<=0;
                    write_reply({312'd0,notify_config,7'd0,notify_stick},9,0,PREPARE);
                end else if(practice_notify_take)begin
                    response_seq<=async_seq;async_seq<=async_seq+1'b1;response_session<=current_session;response_flags<=0;cache_enable<=0;
                    response_type<=practice_notify_type;response_length<=48;
                    write_reply(practice_notify_packet,48,0,PREPARE);
                end else if(!paused && revision_current && session_valid && !session_expiring && subscriptions[0] && uptime_ms-last_status_ms>=status_interval) begin
                    response_seq<=async_seq;async_seq<=async_seq+1'b1;response_session<=current_session;response_flags<=0;cache_enable<=0;
                    last_status_ms<=uptime_ms;status_reply();
                end else if(!paused && session_valid && !session_expiring && subscriptions[2] && physical_key_mask!=last_activity_mask && uptime_ms-last_activity_ms>=10) begin
                    response_seq<=async_seq;async_seq<=async_seq+1'b1;response_session<=current_session;response_flags<=0;cache_enable<=0;
                    response_type<=8'h43;response_length<=20;last_activity_ms<=uptime_ms;last_activity_mask<=physical_key_mask;
                    write_reply({160'd0,64'd0,29'd0,physical_key_mask,uptime_ms},20,0,PREPARE);
                end else if(!paused && session_valid && !session_expiring && subscriptions[1] && (&adc_seen) && uptime_ms-last_adc_ms>=adc_interval) begin
                    response_seq<=async_seq;async_seq<=async_seq+1'b1;response_session<=current_session;response_flags<=0;cache_enable<=0;
                    response_type<=8'h41;response_length<=79;last_adc_ms<=uptime_ms;adc_frame<=adc_frame+1'b1;
                    for(snapshot_index=0;snapshot_index<35;snapshot_index=snapshot_index+1) adc_snapshot[snapshot_index]<=adc_values[snapshot_index];
                    write_reply({248'd0,8'd35,8'd0,8'd0,uptime_ms,adc_frame},9,0,ADC_HEADER);
                end
                state_bits[SESSION_CHECK]:state_bits<=(51'd1<<DISPATCH);
                state_bits[DISPATCH]:if(req_type==3 || req_flags[1]) finish_request();
                else if(req_flags[7:2]!=0) ack(5,16'd1);
                else if(req_version!=1) ack(7,16'd1);
                else if(req_type==1) begin
                    if(req_session!=0) ack(9,0);
                    else if(req_length!=8) ack(2,8);
                    else if(req_header[7:0]>1 || req_header[15:8]<1 || req_header[7:0]>req_header[15:8]) ack(7,1);
                    else if(req_header[63:48]<64) ack(3,64);
                    else if(session_valid && req_header[47:16]==hello_request[47:16]) begin
                        if(req_seq!=hello_seq || req_header[63:0]!=hello_request) ack(11,0);
                        else begin live();hello_reply(current_session,boot_id);end
                    end else begin
                        subscriptions<=1;status_interval<=STATUS_PERIOD_MS;adc_interval<=100;remote_bend<=0;remote_modulation<=0;last_adc_ms<=uptime_ms;last_activity_mask<=~physical_key_mask;
                        current_session<=next_session;session_valid<=1;session_age<=0;remote_lease_valid<=0;clear_remote<=1;counter_valid<=0;cache_valid<=0;replace_slot<=0;
                        hello_request<=req_header[63:0];hello_seq<=req_seq;peer_max_payload<=req_header[63:48]>229 ? 16'd229:req_header[63:48];last_status_ms<=uptime_ms;
                        if(!boot_valid) begin boot_id<=new_boot==0 ? 32'd1:new_boot;boot_valid<=1;end
                        hello_reply(next_session,boot_valid ? boot_id:(new_boot==0 ? 32'd1:new_boot));
                    end
                end else if(!session_valid || !request_session_match || session_expiring) begin session_error<=1;ack(9,0);end
                else if(req_type==8'h10 || req_type==8'h13 || req_type==8'h47 || (req_type==2 && !req_flags[0])) state_bits<=(51'd1<<EXECUTE);
                else begin cache_enable<=1;lookup_index<=0;state_bits<=(51'd1<<LOOKUP);end
                state_bits[LOOKUP]:if(cache_valid[lookup_index] && cached_type[lookup_index]==req_type && cached_seq[lookup_index]==req_seq && cache_age<(req_type==8'h90 ? 32'd32000:CACHE_MS)) begin
                    cache_slot<=lookup_index;cache_index<=0;
                    if(cached_flags[lookup_index]!=req_flags || cached_length[lookup_index]!=req_length) begin cache_enable<=0;ack(11,0);end
                    else if(req_length==0) begin
                        response_type<=cached_response_type[lookup_index];response_flags<=cached_response_flags[lookup_index];response_length<=cached_response_length[lookup_index];
                        if(cached_response_length[lookup_index]==0) begin live();release_request();state_bits<=(51'd1<<SEND);end else state_bits<=(51'd1<<REPLAY_WAIT);
                    end else state_bits<=(51'd1<<COMPARE_WAIT);
                end else if(lookup_index==15) state_bits<=(51'd1<<EXECUTE);else lookup_index<=lookup_index+1'b1;
                state_bits[COMPARE_WAIT]:start_read(cache_index,1,READ_BYTE,COMPARE);
                state_bits[COMPARE]:if(request_byte!=fetched_byte) begin cache_enable<=0;ack(11,0);end
                else if(cache_index==req_length-1'b1) begin
                    cache_index<=0;response_type<=cached_response_type[cache_slot];response_flags<=cached_response_flags[cache_slot];response_length<=cached_response_length[cache_slot];
                    if(cached_response_length[cache_slot]==0) begin live();release_request();state_bits<=(51'd1<<SEND);end else state_bits<=(51'd1<<REPLAY_WAIT);
                end else begin cache_index<=cache_index+1'b1;state_bits<=(51'd1<<COMPARE_WAIT);end
                state_bits[REPLAY_WAIT]:state_bits<=(51'd1<<REPLAY);
                state_bits[REPLAY]:write_reply({312'd0,response_byte},1,cache_index,REPLAY_COMMIT);
                state_bits[REPLAY_COMMIT]:begin
                    if(cache_index==response_length-1'b1) begin
                        release_request();
                        if(response_flags[2]) begin if(error_age<100) finish_request();else begin error_age<=0;state_bits<=(51'd1<<SEND);end end
                        else begin live();state_bits<=(51'd1<<SEND);end
                    end else begin cache_index<=cache_index+1'b1;state_bits<=(51'd1<<REPLAY_WAIT);end
                end
                state_bits[BUILD_FIXED_REPLY]:begin
                    // The request header stays owned throughout this state. Revision
                    // replies wait for coherent data just as in EXECUTE.
                    case(fixed_reply_kind)
                        3'd0:if(revision_current) begin
        response_type<=8'h05;response_length<=40;reply_packet<=0;
        reply_packet[31:0]<=uptime_ms;reply_packet[63:32]<=effective_revision;
        reply_packet[95:64]<=state_flags | (offline_mapping_active ? 32'h4000:32'd0) | {31'd0,panic_latched};reply_packet[103:96]<={2'd0,popcount(voice_active)};
        reply_packet[111:104]<=audio_source;reply_packet[127:112]<={12'd0,config_data[10:7]};
        reply_packet[143:128]<=volume_permille;reply_packet[207:144]<={29'd0,physical_key_mask};
        reply_packet[271:208]<={28'd0,remote_key_mask};reply_packet[303:272]<=error_bits;
        reply_packet[319:304]<=active_timbre;reply_count<=40;reply_index<=0;reply_base<=0;reply_return<=(51'd1<<PREPARE);state_bits<=(51'd1<<REPLY_WRITE);

                        end
                        3'd1:begin
response_type<=2;response_length<=8;reply_packet<=0;reply_packet[31:0]<=req_header[31:0];reply_packet[63:32]<=uptime_ms;reply_count<=8;reply_index<=0;reply_base<=0;reply_return<=(51'd1<<PREPARE);state_bits<=(51'd1<<REPLY_WRITE);
                        end
                        3'd2:if(revision_current) begin
live();response_type<=7;response_length<=22;reply_packet<=0;
                        reply_packet[7:0]<=35;reply_packet[15:8]<=5;reply_packet[23:16]<=7;reply_packet[31:24]<=12;reply_packet[39:32]<=36;
                        reply_packet[103:40]<=(SCORE_BEAT_SUPPORTED!=0 ? (64'd1<<27):64'd0) | (REMOTE_KEYS_SUPPORTED!=0 ? 64'h10de5:64'h10de4) | (DRUMSTICKS_SUPPORTED!=0 ? 64'h7c80000:64'd0) | (AUDIO_MIX_SUPPORTED!=0 ? 64'h101000:64'd0) | (PRACTICE_SUPPORTED!=0 ? 64'h40000:64'd0);reply_packet[135:104]<=effective_revision;
                        reply_packet[151:136]<=16'd229;reply_packet[159:152]<=12;reply_packet[167:160]<=32;reply_packet[175:168]<=0;reply_count<=22;reply_index<=0;reply_base<=0;reply_return<=(51'd1<<PREPARE);state_bits<=(51'd1<<REPLY_WRITE);
                        end
                        3'd3:begin
response_type<=8'h40;response_length<=5;
                        write_reply({280'd0,8'd0,(req_header[7:0]==3 ? 16'd0:req_header[31:16]<100 ? 16'd100:req_header[31:16]),req_header[15:0]},5,0,PREPARE);
                        end
                        3'd4:if(revision_current) begin
shadow<=config_data;extended_shadow<=extended_config;extended_dirty<=0;count<=req_header[5:0];item_index<=0;response_type<=8'h22;response_length<=get_response_bytes[7:0];reply_packet<=0;reply_packet[31:0]<=effective_revision;reply_packet[39:32]<=req_header[7:0];reply_count<=5;reply_index<=0;reply_base<=0;reply_return<=(51'd1<<GET_PARAM);state_bits<=(51'd1<<REPLY_WRITE);
                        end
                        3'd5:if(revision_current) begin
live();key_start<=req_header[7:0];key_count<=req_header[15:8];item_index<=0;response_type<=8'h25;response_length<=key_response_bytes[7:0];write_reply({272'd0,req_header[15:0],effective_revision},6,0,KEY_GET);
                        end
                        default:finish_request();
                    endcase
                end
                state_bits[EXECUTE]:if(!session_valid || !request_session_match || session_expiring) begin cache_enable<=0;ack(9,0);end
                else case(req_type)
                    8'h46,8'h47:begin
                        if(SCORE_BEAT_SUPPORTED==0)ack(7,27);
                        else if(req_length!=(req_type==8'h46 ? 5:10))ack(2,req_type==8'h46 ? 5:10);
                        else if((req_type==8'h46 && req_flags!=1) || (req_type==8'h47 && req_flags!=0))ack(5,1);
                        else state_bits<=(51'd1<<BEAT_ISSUE);
                    end
                    8'h02:if(req_length!=4) ack(2,4);else begin
                        live();performance_age<=0;if(!req_flags[0]) finish_request();else begin fixed_reply_kind<=3'd1;state_bits<=(51'd1<<BUILD_FIXED_REPLY);end
                    end
                    8'h04:if(revision_current) begin if(req_length!=0) ack(2,0);else begin live();status_reply();end end
                    8'h06:if(revision_current) begin if(req_length!=0) ack(2,0);else begin
                        fixed_reply_kind<=3'd2;state_bits<=(51'd1<<BUILD_FIXED_REPLY);
                    end
                    end
                    8'h10:if(req_length!=3) ack(2,3);
                    else if(REMOTE_KEYS_SUPPORTED==0) ack(7,0);
                    else if(req_header[7:0]>=36) ack(3,{8'd0,req_header[7:0]});
                    else if(req_header[15:8]==2) ack(7,1);
                    else if(req_header[15:8]>1 || (req_header[15:8]==0 && req_header[23:16]!=0) || (req_header[15:8]==1 && (req_header[23:16]==0 || req_header[23:16]>127))) ack(3,{8'd0,req_header[7:0]});
                    else begin remote_snapshot<=0;remote_key<=req_header[5:0];remote_on<=req_header[8];remote_velocity<=req_header[22:16];state_bits<=(51'd1<<REMOTE_ISSUE);end
                    8'h11:if(req_length!=1) ack(2,1);else if(req_header[7:0]==1) ack(7,1);else if(req_header[7:0]!=0) ack(3,0);
                    else begin remote_snapshot<=1;remote_target_mask<=0;remote_target_velocity<=0;state_bits<=(51'd1<<REMOTE_ISSUE);end
                    8'h12:if(req_length!=3) ack(2,3);
                    else if(req_header[7:0]==1 && ($signed(req_header[23:8]) < -8192 || $signed(req_header[23:8]) > 8191)) ack(3,1);
                    else if(req_header[7:0]==2 && req_header[23:8]>127) ack(3,2);
                    else if(req_header[7:0]!=1 && req_header[7:0]!=2) ack(7,{8'd0,req_header[7:0]});
                    else if(!remote_allowed || panic_latched || !extended_config[32]) ack(5,2);
                    else begin
                        live();performance_age<=0;
                        if(req_header[7:0]==1) remote_bend<=req_header[23:8];else remote_modulation<=req_header[14:8];
                        if(req_flags[0]) ack(0,0);else finish_request();
                    end
                    8'h40:if(req_length!=5) ack(2,5);
                    else if(req_header[7:0]!=0 && req_header[7:0]!=1 && req_header[7:0]!=3) ack(7,{8'd0,req_header[7:0]});
                    else if(req_header[15:8]>1 || req_header[39:32]!=0 || (req_header[7:0]==1 && req_header[15:8]==1 && peer_max_payload<79)) ack(3,0);
                    else begin
                        live();
                        case(req_header[7:0])
                            0:begin subscriptions[0]<=req_header[8];status_interval<=req_header[31:16]<100 ? 16'd100:req_header[31:16];end
                            1:begin subscriptions[1]<=req_header[8];adc_interval<=req_header[31:16]<100 ? 16'd100:req_header[31:16];last_adc_ms<=uptime_ms;end
                            3:begin subscriptions[2]<=req_header[8];last_activity_mask<=~physical_key_mask;end
                        endcase
                        fixed_reply_kind<=3'd3;state_bits<=(51'd1<<BUILD_FIXED_REPLY);
                    end
                    8'h13:if((req_length!=45 && req_length!=46)) ack(2,45);else if(REMOTE_KEYS_SUPPORTED==0) ack(7,0);
                    else if((req_header[79:52]!=0 || (req_length==45 && req_header[51]))) ack(3,36);
                    else if(counter_valid && (counter_delta==0 || counter_delta[15])) begin if(req_flags[0])ack(0,0);else finish_request();end
                    else begin remote_snapshot<=1;remote_target_mask<=req_header[51:16];remote_target_velocity<=0;item_index<=0;state_bits<=(51'd1<<SNAPSHOT_CHECK);end
                    8'h14:if(req_length!=1) ack(2,1);else if(req_header[7:0]>1) ack(3,0);else if(!req_flags[0]) ack(5,1);
                    else begin live();panic_latched<=req_header[0];if(req_header[0]) begin clear_remote<=1;remote_lease_valid<=0;end ack(0,0);end
                    8'h20:if(revision_current) begin if(req_length<11 || req_header[39:32]==0 || req_header[39:32]>37 || req_length!=set_request_bytes) ack(2,0);
                    else if(req_header[31:0]!=32'hffffffff && req_header[31:0]!=effective_revision) ack(8,0);
                    else begin beat_free_dirty<=0;shadow<=config_data;extended_shadow<=extended_config;extended_dirty<=0;base_revision<=effective_revision;expected_revision<=req_header[31:0];count<=req_header[37:32];item_index<=0;seen_parameters<=0;state_bits<=(51'd1<<PARAM_LOAD);end
                    end
                    8'h21:if(revision_current) begin if(req_length<3 || req_header[7:0]==0 || req_header[7:0]>37 || req_length!=get_request_bytes) ack(2,0);
                    else if(get_response_bytes>peer_max_payload) ack(2,peer_max_payload);
                    else begin fixed_reply_kind<=3'd4;state_bits<=(51'd1<<BUILD_FIXED_REPLY);end
                    end
                    8'h23:if(offline_busy || offline_mapping_active)ack(5,3);else if(revision_current) begin if(req_length<14 || req_length!=key_expected_length) ack(2,14);
                    else if(req_header[95:32]==0 || req_header[95:68]!=0 || req_header[111:96]==0 || req_header[111:103]!=0) ack(3,0);
                    else if(req_header[102]) ack(7,64);
                    else if(req_header[31:0]!=32'hffffffff && req_header[31:0]!=effective_revision) ack(8,0);
                    else begin key_mask<=req_header[95:32];key_fields<=req_header[111:96];expected_revision<=req_header[31:0];base_revision<=effective_revision;key_values<=0;key_field<=0;key_offset<=14;state_bits<=(51'd1<<KEY_FIELD_LOAD);end
                    end
                    8'h24:if(revision_current) begin if(req_length!=2 || req_header[15:8]==0 || req_header[15:8]>16 || {1'b0,req_header[7:0]}+{1'b0,req_header[15:8]}>36) ack(3,0);
                    else if(6+times_ten(req_header[15:8])>peer_max_payload) ack(2,peer_max_payload);
                    else begin fixed_reply_kind<=3'd5;state_bits<=(51'd1<<BUILD_FIXED_REPLY);end
                    end
                    8'h60:if(PRACTICE_SUPPORTED==0)ack(7,0);else if(req_length!=0)ack(2,0);else begin live();response_type<=8'h60;response_length<=16;write_reply({256'd0,16'd24,16'd192,32'd98304,32'd4096,16'd1,16'd1},16,0,PREPARE);end
                    8'h90:if(!req_flags[0] || req_length==0)ack(2,1);else state_bits<=(51'd1<<SD_START);
                    8'h61,8'h62,8'h63,8'h64,8'h65,8'h66,8'h67:
                        if(PRACTICE_SUPPORTED==0)ack(7,{8'd0,req_type});
                        else if(offline_active)ack(5,3);
                        else if(!req_flags[0])ack(5,1);else state_bits<=(51'd1<<PRACTICE_START);
                    8'h72:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=9) ack(2,9);
                    else if(!req_flags[0]) ack(5,1);
                    else if(req_header[7:0]>1 || (req_header[15:8]>5 && req_header[15:8]!=255) || (req_header[23:16]>5 && req_header[23:16]!=255) || (req_header[31:24]>5 && req_header[31:24]!=255) ||
                        req_header[39:32]>127 || req_header[55:40]<30 || req_header[55:40]>1600 ||
                        req_header[71:56]<20 || req_header[71:56]>500) ack(3,0);
                    else if(revision_current) begin
                        if(req_header[0]) drum_config[127:64]<=req_header[71:8];else drum_config[63:0]<=req_header[71:8];begin key_revision<=key_revision+1'b1;key_revision_pending[0]<=1;end live();ack(0,0);
                    end
                    8'h73:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=1) ack(2,1);else if(req_header[7:0]>1) ack(3,0);
                    else begin live();response_type<=8'h74;response_length<=9;
                        write_reply({248'd0,selected_drum_config,req_header[7:0]},9,0,PREPARE);
                    end
                    8'h77:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=1) ack(2,1);
                    else if(!req_flags[0]) ack(5,1);
                    else if(req_header[7:0]!=3) ack(3,0);
                    else if(!drum_cal_ready) ack(5,2);
                    else begin live();drum_cal_request<=1;ack(0,0);end
                    8'h78:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=0) ack(2,0);
                    else begin live();response_type<=8'h79;response_length<=12;
                        write_reply({160'd0,drum_cal_status},12,0,PREPARE);end
                    8'h7a:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=6) ack(2,6);
                    else if(!req_flags[0]) ack(5,1);
                    else if(req_header[7:0]>1 || req_header[15:8]>100 ||
                        req_header[31:16]<1 || req_header[31:16]>1000 || req_header[47:32]>5000) ack(3,0);
                    else begin live();drum_light_config<=req_header[47:0];drum_effect_active<=0;ack(0,0);end
                    8'h83:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=11 && req_length!=9) ack(2,11);
                    else if(!req_flags[0]) ack(5,1);
                    else if(req_header[7:0]>2) ack(3,0);
                    else if(req_header[15:8]>100) ack(3,1);
                    else if((req_length==11 && (req_header[47:16]<40000 || req_header[47:16]>200000)) ||
                            (req_length==9 && (req_header[31:16]<40000 || req_header[31:16]>65535))) ack(3,2);
                    else if((req_length==11 && (req_header[63:48]<200 || req_header[63:48]>5000)) ||
                            (req_length==9 && (req_header[47:32]<200 || req_header[47:32]>5000))) ack(3,4);
                    else begin live();
                        drum_effect_config<=req_length==11 ? req_header[87:0]:{req_header[71:32],16'd0,req_header[31:0]};
                        drum_effect_active<=1;ack(0,0);end
                    8'h84:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=0) ack(2,0);
                    else begin live();response_type<=8'h85;response_length<=11;
                        write_reply({296'd0,drum_effect_config},11,0,PREPARE);end
                    8'h7d:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=4) ack(2,4);
                    else if(!req_flags[0]) ack(5,1);
                    else if(req_header[7:0]>1) ack(3,0);
                    else begin live();drum_color_config<=req_header[31:0];drum_effect_active<=0;ack(0,0);end
                    8'h7e:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=0) ack(2,0);
                    else begin live();response_type<=8'h7f;response_length<=4;
                        write_reply({352'd0,drum_color_config},4,0,PREPARE);end
                    8'h7b:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=0) ack(2,0);
                    else begin live();response_type<=8'h7c;response_length<=6;
                        write_reply({208'd0,drum_light_config},6,0,PREPARE);end
                    8'h76:if(DRUMSTICKS_SUPPORTED==0) ack(7,0);
                    else if(req_length!=3) ack(2,3);else if(!req_flags[0]) ack(5,1);
                    else if(req_header[7:0]>1 || req_header[15:8]>2 || req_header[23:16]==0 || req_header[23:16]>127) ack(3,0);
                    else if(panic_latched || !(drum_allowed===1'b1)) ack(5,2);
                    else begin drum_sim_stick<=req_header[0];drum_sim_direction<=req_header[9:8];drum_sim_velocity<=req_header[22:16];state_bits<=(51'd1<<DRUM_ISSUE);end
                    8'h08,8'h26,8'h28,8'h30,8'h50,8'h51,8'h52,8'h53:ack(7,{8'd0,req_type});
                    default:ack(1,{8'd0,req_type});
                endcase
                state_bits[KEY_FIELD_LOAD]:if(key_field==7) state_bits<=(51'd1<<KEY_VALIDATE);
                else if(!key_fields[key_field]) key_field<=key_field+1'b1;
                else start_read(key_offset,key_field==2 ? 2:1,READ_RECORD,KEY_FIELD);
                state_bits[KEY_FIELD]:begin
                    case(key_field)
                        0:key_values[7:0]<=read_record[7:0];1:key_values[15:8]<=read_record[7:0];2:key_values[31:16]<=read_record[15:0];
                        3:key_values[39:32]<=read_record[7:0];4:key_values[47:40]<=read_record[7:0];5:key_values[55:48]<=read_record[7:0];
                    endcase
                    key_offset<=key_next_offset[7:0];key_field<=key_field+1'b1;state_bits<=(51'd1<<KEY_FIELD_LOAD);
                end
                state_bits[KEY_VALIDATE]:if((key_fields[0] && key_values[7:0]>1) || (key_fields[1] && key_values[15:8]>127) || (key_fields[2] && key_values[31:16]!=16'hffff && !sound_ok({16'd0,key_values[31:16]})) || (key_fields[3] && key_values[39:32]>1) || (key_fields[4] && (key_values[47:40]==0 || key_values[47:40]>127))) ack(3,0);
                else if(key_fields[5] && key_values[55:48]!=0) ack(7,32);
                else state_bits<=(51'd1<<KEY_COMMIT);
                state_bits[KEY_COMMIT]:if(offline_busy || offline_mapping_active)ack(5,3);else if(revision_current) begin if(!session_valid || !request_session_match || session_expiring) begin cache_enable<=0;ack(9,0);end
                else if(!expected_ok) ack(8,0);
                else if(!same_revision || !parameter_ready || |(key_mask[35:0] & ({1'b0,physical_key_mask}|remote_key_mask| (voice_active & 36'h7ffffffff)))) ack(4,100);
                else begin
                    key_revision<=key_revision+1'b1;key_revision_pending[0]<=1;state_bits<=(51'd1<<KEY_DONE);
                end
                end
                state_bits[KEY_DONE]:begin live();ack(0,0);end
                state_bits[KEY_GET]:begin
                    reply_packet<=0;reply_packet[7:0]<={7'd0,key_get_word[0]};
                    reply_packet[15:8]<={1'b0,key_get_word[7:1]};
                    reply_packet[31:16]<=key_get_word[11:8]==0 ? 16'hffff:{12'd0,key_get_word[11:8]};
                    reply_packet[39:32]<={7'd0,key_get_word[12]};
                    reply_packet[47:40]<={1'b0,key_get_word[19:13]};
                    reply_count<=10;reply_index<=0;reply_base<=key_reply_offset[7:0];reply_return<=(51'd1<<KEY_GET_NEXT);state_bits<=(51'd1<<REPLY_WRITE);
                end
                state_bits[KEY_GET_NEXT]:if(item_index+1>=key_count) state_bits<=(51'd1<<PREPARE);else begin item_index<=item_index+1'b1;state_bits<=(51'd1<<KEY_GET);end
                state_bits[PARAM_LOAD]:start_read(parameter_record_offset[7:0],6,READ_RECORD,PARAM_DECODE);
                state_bits[BEAT_ISSUE]:begin beat_request<=1;state_bits<=(51'd1<<BEAT_WAIT);end
                state_bits[BEAT_WAIT]:if(!beat_gate)begin cache_enable<=0;ack(9,0);end
                    else if(beat_done)begin
                        if(beat_result!=0)ack(beat_result,beat_detail);
                        else begin live();if(req_type==8'h47)finish_request();else ack(0,0);end
                    end
                state_bits[PARAM_DECODE]:begin if(read_record[15:0]==16'h0050)beat_free_dirty<=1;item_id<=read_record[15:0];item_value<=read_record[47:16];state_bits<=(51'd1<<PARAM_CHECK);end
                state_bits[PARAM_CHECK]:begin
                    seen_parameters<=seen_parameters | item_flag;
                    if(item_flag==0) ack(7,item_id);
                    else if((seen_parameters & item_flag)!=0) ack(3,item_id);
                    else if(item_id==16'h0003 && item_value!=audio_source) ack(7,item_id);
                    else if(item_id==16'h0090 && item_value>3) ack(3,item_id);
                    else if((item_id==5 && item_value>2400) || (item_id==16'h71 && item_value>1) || (item_id==16'h13 && item_value>5000) || (item_id==16'h21 && item_value>10000) || (item_id==16'h62 && item_value>24'hffffff) || (item_id==16'h63 && (item_value<500 || item_value>30000)) || (item_id==16'h64 && item_value!=1000) || (item_id==16'h65 && (item_value<200 || item_value>5000))) ack(3,item_id);
                    else if(item_value[31] || ((item_id==1 || item_id==16'h0042 || item_id==16'h0061 || item_id==16'h0070) && item_value>1000) || (item_id==2 && !sound_ok(item_value)) || ((item_id==16'h0040 || item_id==16'h0050 || item_id==16'h0080) && item_value>1) || (item_id==16'h0041 && item_value!=0) || (item_id==16'h0051 && (item_value<300 || item_value>2400)) || (item_id==16'h0052 && (item_value<1 || item_value>12)) || (item_id==16'h0053 && item_value!=2 && item_value!=4 && item_value!=8) || (item_id==16'h0060 && item_value>2)) ack(3,item_id);
                    else if(item_id==1 || item_id==16'h0042 || item_id==16'h0070 || item_id==16'h0051 || item_id==16'h0061) begin
                        // MSB-first shift/subtract division: at most eight
                        // quotient bits, then one completion clock. Values
                        // and rounding match the original integer formulas.
                        convert_result<=0;
                        convert_divisor<=item_id==16'h0061 ? 16'd32000:16'd1280;
                        convert_bits<=item_id==16'h0061 ? 4'd6:4'd8;
                        if(item_id==16'h0061) convert_remaining<={1'b0,item_value[9:0],5'd0}+16'd500;
                        else if(item_id==16'h0051) convert_remaining<={4'd0,item_value[11:0]};
                        else convert_remaining<={6'd0,item_value[9:0]}+16'd5;
                        state_bits<=(51'd1<<CONVERT);
                    end else begin
                        case(item_id)
                            5:begin extended_shadow[31:0]<=item_value;extended_dirty[0]<=item_value!=extended_config[31:0];end 16'h71:begin extended_shadow[63:32]<=item_value;extended_dirty[1]<=item_value!=extended_config[63:32];end
                            16'h13:begin extended_shadow[95:64]<=item_value;extended_dirty[2]<=item_value!=extended_config[95:64];end 16'h21:begin extended_shadow[127:96]<=item_value;extended_dirty[3]<=item_value!=extended_config[127:96];end
                            16'h62:begin extended_shadow[159:128]<=item_value;extended_dirty[4]<=item_value!=extended_config[159:128];end 16'h63:begin extended_shadow[191:160]<=item_value;extended_dirty[5]<=item_value!=extended_config[191:160];end
                            16'h64:begin extended_shadow[223:192]<=item_value;extended_dirty[6]<=item_value!=extended_config[223:192];end 16'h65:begin extended_shadow[255:224]<=item_value;extended_dirty[7]<=item_value!=extended_config[255:224];end
                            2:shadow[10:7]<=item_value[3:0];16'h0040:shadow[26]<=item_value[0];
                            16'h0050:shadow[35]<=item_value[0];16'h0052:shadow[39:36]<=item_value[3:0];16'h0053:shadow[43:40]<=item_value[3:0];
                            16'h0090:shadow[53:52]<=item_value[1:0];
                            16'h0060:shadow[18:17]<=item_value[1:0];16'h0080:shadow[34]<=item_value[0];default:shadow<=shadow;
                        endcase
                        next_parameter();
                    end
                end
                state_bits[CONVERT]:if(convert_bits!=0) begin
                    if(convert_remaining>=convert_divisor) convert_remaining<=convert_remaining-convert_divisor;
                    convert_result<={convert_result[6:0],convert_remaining>=convert_divisor};
                    convert_divisor<=convert_divisor>>1;convert_bits<=convert_bits-1'b1;
                end
                else if(item_id==16'h0051 && convert_remaining!=0) ack(3,item_id);
                else begin
                    case(item_id)
                        1:shadow[6:0]<=convert_result[6:0];16'h0042:shadow[25:19]<=convert_result[6:0];
                        16'h0070:shadow[33:27]<=convert_result[6:0];16'h0051:shadow[51:44]<=convert_result;
                        16'h0061:shadow[16:11]<=convert_result[5:0];default:shadow<=shadow;
                    endcase
                    next_parameter();
                end
                state_bits[COMMIT]:if(revision_current) begin if(!session_valid || !request_session_match || session_expiring) begin cache_enable<=0;ack(9,0);end
                else if(!expected_ok) ack(8,0);else if(!same_revision || !parameter_ready) ack(4,100);else begin
                    commit_config_changed<=shadow!=config_data;
                    if(AUDIO_MIX_SUPPORTED==0) begin extended_config<=extended_shadow;if(extended_changed && shadow==config_data) begin key_revision<=key_revision+1'b1;key_revision_pending[0]<=1;end end
                    state_bits<=(51'd1<<COMMIT_DONE);end
                end
                state_bits[COMMIT_DONE]:if(AUDIO_MIX_SUPPORTED==0 || parameter_done) begin
                    if(AUDIO_MIX_SUPPORTED!=0 && parameter_error) ack(5,16'h0090);
                    else begin
                        if(AUDIO_MIX_SUPPORTED!=0) begin
                            extended_config<=extended_shadow;
                            if(extended_changed && !commit_config_changed) begin key_revision<=key_revision+1'b1;key_revision_pending[0]<=1;end 
                        end
                        if(beat_free_dirty)beat_free_pulse<=1;
                        live();ack(0,0);
                    end
                end
                state_bits[ACK_REPLY]:if(revision_current) begin
                    response_type<=8'h03;response_flags<=ack_code==0 ? 8'h02:8'h06;response_length<=8;
                    write_reply({256'd0,ack_detail,effective_revision,ack_code,req_type},8,0,PREPARE);
                end
                state_bits[ADC_HEADER]:begin item_index<=0;state_bits<=(51'd1<<ADC_RECORD);end
                state_bits[ADC_RECORD]:write_reply({304'd0,4'd0,adc_snapshot[item_index]},2,8'd9+{1'b0,item_index,1'b0},ADC_NEXT);
                state_bits[ADC_NEXT]:if(item_index==34) state_bits<=(51'd1<<PREPARE);else begin item_index<=item_index+1'b1;state_bits<=(51'd1<<ADC_RECORD);end
                state_bits[GET_PARAM]:start_read(8'd1+{1'd0,item_index,1'b0},2,READ_RECORD,GET_DECODE);
                state_bits[GET_DECODE]:if(!supported_param(selected_get_id)) ack(7,selected_get_id);
                else write_reply({272'd0,selected_get_value,selected_get_id},6,parameter_record_offset[7:0],GET_ADVANCE);
                state_bits[GET_ADVANCE]:if(item_index==count-1'b1) begin live();state_bits<=(51'd1<<PREPARE);end
                else begin item_index<=item_index+1'b1;state_bits<=(51'd1<<GET_PARAM);end
                state_bits[SNAPSHOT_CHECK]:start_read(8'd10+{2'd0,item_index},1,READ_BYTE,SNAPSHOT_DECODE);
                state_bits[SNAPSHOT_DECODE]:if((selected_snapshot_on && (selected_snapshot==0 || selected_snapshot>127)) || (!selected_snapshot_on && selected_snapshot!=0)) ack(3,{10'd0,item_index});
                else begin
                    for(packet_slot=0;packet_slot<36;packet_slot=packet_slot+1)
                        if(item_index==packet_slot) remote_target_velocity[packet_slot*7 +:7]<=selected_snapshot[6:0];
                    if(item_index==(req_length==46 ? 35:34)) state_bits<=(51'd1<<REMOTE_ISSUE);else begin item_index<=item_index+1'b1;state_bits<=(51'd1<<SNAPSHOT_CHECK);end
                end
                state_bits[REMOTE_ISSUE]:if(!session_valid || !request_session_match || session_expiring) begin cache_enable<=0;ack(9,0);end
                else if(offline_playback_owner)begin
                    // BLE snapshots must not wait on the SD player's exclusive note port.
                    // Empty/release frames are acknowledged without touching local notes.
                    live();remote_age<=0;remote_lease_valid<=0;
                    if(req_type==8'h13)begin counter_valid<=1;state_counter<=req_header[15:0];end
                    if(remote_snapshot ? remote_target_mask==0:!remote_on)begin
                     if(req_type==8'h11 || req_flags[0])ack(0,0);else finish_request();
                    end else if(req_flags[0])ack(5,3);else finish_request();
                end
                else if(!remote_allowed && (remote_snapshot ? remote_target_mask!=0:remote_on)) ack(5,2);
                else if(remote_ready && !remote_expiring && !session_expiring) begin
                    live();clear_remote<=0;remote_age<=0;remote_lease_valid<=1;
                    if(req_type==8'h13) begin counter_valid<=1;state_counter<=req_header[15:0];end
                    if(req_type==8'h11 || req_flags[0]) ack(0,0);else finish_request();
                end
                state_bits[DRUM_ISSUE]:if(!session_valid || current_session!=req_session || session_expiring) begin cache_enable<=0;ack(9,0);end
                else if(panic_latched || !(drum_allowed===1'b1)) ack(5,2);
                else if(drum_sim_ready) begin live();ack(0,0);end
                state_bits[SD_START]:if(sd_cmd_ready)state_bits<=(51'd1<<SD_WAIT);
                state_bits[SD_WAIT]:if(sd_cmd_done)begin
                 live();response_type<=8'h91;response_length<=36;write_reply(sd_reply,36,0,PREPARE);
                end
                state_bits[PRACTICE_START]:if(!session_valid || !request_session_match || session_expiring)ack(9,0);
                else if(practice_ready)state_bits<=(51'd1<<PRACTICE_WAIT);
                state_bits[PRACTICE_WAIT]:if(!session_valid || !request_session_match || session_expiring)ack(9,0);
                else if(practice_done)begin
                    live();
                    if(practice_code!=0 || practice_reply_length==0)ack(practice_code,0);
                    else begin
                        response_type<=practice_reply_type;response_length<=practice_reply_length;
                        write_reply(practice_reply_packet,practice_reply_length[5:0],0,PREPARE);
                    end
                end
                state_bits[PREPARE]:if(cache_enable && session_valid && request_session_match && !session_expiring) begin
                    cache_slot<=replace_slot;cache_index<=0;cache_valid[replace_slot]<=0;
                    cached_type[replace_slot]<=req_type;cached_flags[replace_slot]<=req_flags;cached_length[replace_slot]<=req_length;cached_seq[replace_slot]<=req_seq;cached_time[replace_slot]<=uptime_ms;
                    cached_response_type[replace_slot]<=response_type;cached_response_flags[replace_slot]<=response_flags;cached_response_length[replace_slot]<=response_length;
                    if(req_length==0 && response_length==0) begin cache_valid[replace_slot]<=1;replace_slot<=replace_slot+1'b1;release_request();state_bits<=(51'd1<<SEND);end else state_bits<=(51'd1<<STORE);
                end else begin release_request();state_bits<=(51'd1<<SEND);end
                state_bits[STORE]:start_read(cache_index,1,READ_BYTE,STORE_COMMIT);
                state_bits[STORE_COMMIT]:if(cache_index+1>=req_length && cache_index+1>=response_length) begin
                    if(session_valid && request_session_match && !session_expiring) cache_valid[cache_slot]<=1;
                    replace_slot<=replace_slot+1'b1;release_request();state_bits<=(51'd1<<SEND);
                end else begin cache_index<=cache_index+1'b1;state_bits<=(51'd1<<STORE);end
                state_bits[SEND]:if(response_ready) begin if(response_done) finish_request();else state_bits<=(51'd1<<WAIT_DONE);end
                state_bits[WAIT_DONE]:if(response_done) finish_request();
                state_bits[READ_WAIT1]:state_bits<=(51'd1<<READ_WAIT2);
                state_bits[READ_WAIT2]:state_bits<=(51'd1<<READ_CAPTURE);
                state_bits[READ_CAPTURE]:begin
                    case(read_kind)
                        READ_HEADER:req_header<={req_header[103:0],payload_data};
                        READ_RECORD:read_record<={read_record[39:0],payload_data};
                        default:fetched_byte<=payload_data;
                    endcase
                    if(read_index+1>=read_count) state_bits<=read_return;
                    else begin read_index<=read_index+1'b1;normal_payload_addr<=normal_payload_addr-1'b1;state_bits<=(51'd1<<READ_WAIT1);end
                end
                state_bits[REPLY_WRITE]:begin
                    reply_write_enable<=1;reply_write_addr<=reply_base+{2'd0,reply_index};
                    // Little-endian serializer: fixed byte tap replaces the
                    // 48-to-1 byte mux and its index fanout across the packet.
                    reply_write_data<=reply_packet[7:0];
                    reply_packet<={8'd0,reply_packet[383:8]};
                    if(reply_index+1>=reply_count) state_bits<=(51'd1<<REPLY_DONE);else reply_index<=reply_index+1'b1;
                end
                state_bits[REPLY_DONE]:state_bits<=reply_return;
                default:finish_request();
            endcase
            if(clear_remote || panic_latched || !extended_config[32] || session_expiring) begin remote_bend<=0;remote_modulation<=0;end
            if(session_expiring) begin
                session_valid<=0;clear_remote<=1;cache_valid<=0;counter_valid<=0;remote_lease_valid<=0;
            end else if(remote_expiring) begin clear_remote<=1;remote_lease_valid<=0;end
        end
    end
endmodule

// Same 50 MHz domain as parser and audio; one pending click, latest wins.
module hallpad_score_beat(input wire clk,rst_n,ms_tick,sample_tick,
 input wire session_valid,input wire[31:0]session_id,input wire panic,audio_available,
 input wire request,is_trigger,input wire[79:0]data,input wire free_select,
 output reg done,output reg[7:0]result,output reg[15:0]detail,
 output reg external_mode,output wire trigger,accent,output reg clear_click);
 reg token_valid,counter_valid,pending,pending_accent,lease_valid;
 reg[31:0]token,last_session;
 reg[15:0]counter;
 reg[9:0]age;
 (* syn_preserve=1 *) reg[31:0] dropped_clicks;
 (* syn_keep=1 *) wire[31:0] diagnostic_drops=dropped_clicks;
 wire[31:0] incoming_token=is_trigger ? data[31:0]:data[39:8];
 wire[15:0] delta=data[47:32]-counter;
 wire new_counter=!counter_valid || (delta!=0 && !delta[15]);
 wire permit=session_valid && !panic && audio_available && session_id==last_session;
 assign trigger=pending && permit && external_mode;
 assign accent=pending_accent;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   done<=0;result<=0;detail<=0;external_mode<=0;clear_click<=0;
   token_valid<=0;counter_valid<=0;pending<=0;pending_accent<=0;lease_valid<=0;
   token<=0;counter<=0;age<=0;last_session<=0;dropped_clicks<=0;
  end else begin
   done<=0;clear_click<=0;
   if(sample_tick)pending<=0;
   if(ms_tick && lease_valid)begin
    if(age>=999)begin lease_valid<=0;pending<=0;clear_click<=1;end
    else age<=age+1'b1;
   end
   if(request)begin
    done<=1;result<=0;detail<=0;
    if(!is_trigger)begin
     if(data[7:0]>1)begin result<=3;detail<=0;end
     else if(incoming_token==0)begin result<=3;detail<=1;end
     else if(data[7:0]==0)begin
      if(token_valid && incoming_token!=token)begin result<=5;detail<=1;end
      else begin token_valid<=0;counter_valid<=0;pending<=0;lease_valid<=0;external_mode<=1;clear_click<=1;end
     end else if(!permit)begin result<=5;detail<=0;end
     else begin
      token<=incoming_token;token_valid<=1;counter_valid<=0;pending<=0;
      lease_valid<=0;age<=0;external_mode<=1;clear_click<=1;
     end
    end else begin
     // Validate every field before committing counters or generating sound.
     if(data[63:56]<1 || data[63:56]>12)begin result<=3;detail<=7;end
     else if(data[55:48]>=data[63:56])begin result<=3;detail<=6;end
     else if(data[71:64]!=2 && data[71:64]!=4 && data[71:64]!=8 && data[71:64]!=16)begin result<=3;detail<=8;end
     else if(data[79:72]>1)begin result<=3;detail<=9;end
     else if(!permit || !token_valid || !external_mode || incoming_token!=token)begin result<=5;detail<=0;end
     else if(new_counter)begin
      counter<=data[47:32];counter_valid<=1;age<=0;lease_valid<=1;clear_click<=0;
      if(pending && !sample_tick)dropped_clicks<=dropped_clicks+1'b1;
      pending<=1;pending_accent<=data[72];
     end
    end
   end
   // Explicit parameter 0x50 selection returns to the stored free metronome.
   if(free_select)begin external_mode<=0;token_valid<=0;counter_valid<=0;pending<=0;lease_valid<=0;clear_click<=1;end
   // Session replacement and hard faults win over commands and pending audio.
   if(!session_valid || session_id!=last_session || panic || !audio_available)begin
    last_session<=session_id;token_valid<=0;counter_valid<=0;pending<=0;lease_valid<=0;
    if(external_mode || pending)clear_click<=1;
   end
  end
 end
endmodule
