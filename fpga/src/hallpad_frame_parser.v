`timescale 1ns/1ps
// One raw-byte ring serves framing, CRC and the handed-off payload. Bit 8
// remembers a >=500 ms gap before this byte, even behind complete queued
// frames. The port is synchronous; no full payload is copied into registers.
module hallpad_frame_parser(
    input wire clk,rst_n,ms_tick,flush,
    input wire [7:0] byte_data,input wire byte_valid,output wire byte_ready,
    output reg frame_valid,input wire frame_ready,
    output reg [7:0] version,message_type,flags,
    output reg [15:0] frame_seq,output reg [31:0] session_id,
    output reg [7:0] length,
    input wire [7:0] payload_addr,output reg [7:0] payload_data,
    input wire payload_release,
    output reg crc_error,length_error,timeout_error
);
    localparam READ_NEED=0,READ_WAIT=1,CONSUME=2,HOLD=3,OWNED=4;
    reg [2:0] state;
    (* syn_ramstyle="block_ram" *) reg [8:0] mem[0:255];
    reg [7:0] rd,wr,index;
    reg [8:0] used,total;
    reg [15:0] crc;
    reg [7:0] crc_low;
    reg [8:0] idle_ms;
    reg idle_expired;
    reg pending_valid,owned,flush_pending;
    reg [8:0] ram_word;
    wire [7:0] ram_data=ram_word[7:0];
    reg payload_read_valid;
    wire [7:0] read_address=owned ? rd+8'd13+payload_addr : rd+index;
    wire read_enable=owned ? payload_addr<length : used>{1'b0,index};
    wire push=byte_valid && byte_ready;

    // Both reads use this single port. A raw frame remains counted in used
    // until its owner releases it, so later writes cannot overwrite it.
    always @(posedge clk) begin
        if(push) mem[wr]<={idle_expired,byte_data};
        if(read_enable) ram_word<=mem[read_address];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) payload_read_valid<=0;
        else payload_read_valid<=owned && payload_addr<length;
    end
    always @* begin
        payload_data=payload_read_valid ? ram_data : 8'd0;
        // Masking flush here also prevents a same-edge descriptor transfer
        // when the upstream FIFO has just reported an overflow/framing error.
        frame_valid=pending_valid && !flush && !flush_pending;
    end
    assign byte_ready=rst_n && !flush && !flush_pending && used<9'd256;

    function [15:0] crc_byte(input [15:0] old_crc,input [7:0] value);
        reg [15:0] c;integer j;
        begin
            c=old_crc^{value,8'd0};
            for(j=0;j<8;j=j+1) c=c[15] ? (c<<1)^16'h1021:c<<1;
            crc_byte=c;
        end
    endfunction

    wire waiting=state==READ_NEED && used!=0 && used<={1'b0,index};
    // The deadline can pass while another frame is owned or while the RAM
    // reader is busy. Remember it until input/empty/flush starts a new age;
    // entering READ_NEED must not require one more millisecond tick.
    wire expired=waiting && !byte_valid &&
        (idle_expired || (ms_tick && idle_ms==9'd499));
    // Input may resume before a slow consumer reaches the partial frame.
    // Its queued boundary tag survives the new input resetting idle_expired.
    // At index zero the tag is allowed: this byte starts a fresh candidate.
    wire crossed_gap=state==CONSUME && index!=0 && ram_word[8];
    wire bad_header=state==CONSUME &&
        ((index==0 && ram_data!=8'ha5) ||
         (index==1 && ram_data!=8'h5a) ||
         (index==12 && (ram_data!=0 || length>8'd229)));
    wire bad_crc=state==CONSUME && index>=13 &&
        {1'b0,index}==total-1'b1 && {ram_data,crc_low}!=crc;
    reg [8:0] discard;
    always @* begin
        discard=0;
        if(!owned && (expired || crossed_gap || bad_header || bad_crc)) discard=1;
        else if(owned && payload_release && !flush && !flush_pending)
            discard=total;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=READ_NEED;rd<=0;wr<=0;used<=0;index<=0;total<=0;
            crc<=16'hffff;crc_low<=0;idle_ms<=0;idle_expired<=0;
            pending_valid<=0;owned<=0;flush_pending<=0;
            version<=0;message_type<=0;flags<=0;frame_seq<=0;
            session_id<=0;length<=0;
            crc_error<=0;length_error<=0;timeout_error<=0;
        end else begin
            crc_error<=0;length_error<=0;timeout_error<=0;
            if(flush && !owned) begin
                rd<=0;wr<=0;used<=0;state<=READ_NEED;index<=0;total<=0;
                pending_valid<=0;flush_pending<=0;idle_ms<=0;idle_expired<=0;
                crc<=16'hffff;crc_low<=0;
            end else begin
                if(push) wr<=wr+1'b1;
                if(discard!=0) rd<=rd+discard[7:0];
                used<=used+{8'd0,push}-discard;
                if(push || used==0)begin idle_ms<=0;idle_expired<=0;end
                // Interbyte age follows input traffic, including while a
                // previous descriptor/payload is held by its consumer. A RAM
                // ownership transition must not restart a partial next frame's
                // 500 ms interval. Only actual input or an empty ring does.
                else if(ms_tick)begin
                    if(idle_ms<499)idle_ms<=idle_ms+1'b1;
                    else idle_expired<=1;
                end

                if(owned) begin
                    // Keep the descriptor and RAM bytes stable across flush.
                    // The deferred flush drops any following queued bytes only
                    // after the protocol has finished reading this payload.
                    if(flush) flush_pending<=1;
                    if(payload_release) begin
                        owned<=0;pending_valid<=0;state<=READ_NEED;index<=0;
                        total<=0;crc<=16'hffff;crc_low<=0;
                        if(flush || flush_pending) begin
                            rd<=0;wr<=0;used<=0;flush_pending<=0;idle_ms<=0;idle_expired<=0;
                        end
                    end
                end else if(expired) begin
                    state<=READ_NEED;index<=0;crc<=16'hffff;
                    timeout_error<=1;
                end else case(state)
                    READ_NEED:if(used>{1'b0,index}) state<=READ_WAIT;
                    READ_WAIT:state<=CONSUME;
                    CONSUME:begin
                        if(crossed_gap) begin
                            timeout_error<=1;state<=READ_NEED;index<=0;crc<=16'hffff;
                        end else if(bad_header) begin
                            if(index==12) length_error<=1;
                            state<=READ_NEED;index<=0;crc<=16'hffff;
                        end else if(index==0 || index==1) begin
                            index<=index+1'b1;state<=READ_NEED;
                            if(index==1) crc<=16'hffff;
                        end else if(index<=12) begin
                            crc<=crc_byte(crc,ram_data);
                            case(index)
                                2:version<=ram_data;
                                3:message_type<=ram_data;
                                4:flags<=ram_data;
                                5:frame_seq[7:0]<=ram_data;
                                6:frame_seq[15:8]<=ram_data;
                                7:session_id[7:0]<=ram_data;
                                8:session_id[15:8]<=ram_data;
                                9:session_id[23:16]<=ram_data;
                                10:session_id[31:24]<=ram_data;
                                11:length<=ram_data;
                                12:total<=9'd15+{1'b0,length};
                            endcase
                            index<=index+1'b1;state<=READ_NEED;
                        end else if({1'b0,index}<total-2'd2) begin
                            crc<=crc_byte(crc,ram_data);
                            index<=index+1'b1;state<=READ_NEED;
                        end else if({1'b0,index}==total-2'd2) begin
                            crc_low<=ram_data;index<=index+1'b1;state<=READ_NEED;
                        end else if(bad_crc) begin
                            crc_error<=1;state<=READ_NEED;index<=0;crc<=16'hffff;
                        end else begin
                            pending_valid<=1;state<=HOLD;
                        end
                    end
                    HOLD:if(frame_valid && frame_ready) begin
                        pending_valid<=0;owned<=1;state<=OWNED;
                    end
                    default:begin state<=READ_NEED;index<=0;crc<=16'hffff;end
                endcase
            end
        end
    end
endmodule
