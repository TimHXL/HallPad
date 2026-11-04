`timescale 1ns/1ps
// The response RAM belongs to the encoder from frame acceptance through
// frame_done. Only metadata, one outgoing byte and CRC are copied locally.
module hallpad_frame_encoder(
    input wire clk,rst_n,input wire frame_valid,output wire frame_ready,
    input wire [7:0] message_type,flags,length,
    input wire [15:0] frame_seq,input wire [31:0] session_id,
    output reg [7:0] payload_addr,input wire [7:0] payload_data,
    output reg frame_done,
    output reg [7:0] byte_data,output wire byte_valid,input wire byte_ready
);
    localparam IDLE=0,PREPARE=1,SEND=2,
        RAM_WAIT1=3,RAM_WAIT2=4,RAM_CAPTURE=5;
    reg [2:0] state;
    reg [7:0] kind,flg,size;
    reg [8:0] index;
    reg [15:0] seq,crc;
    reg [31:0] session;
    wire [8:0] body_end=9'd13+{1'b0,size};
    wire [8:0] last_index=9'd14+{1'b0,size};
    assign frame_ready=rst_n && state==IDLE;
    assign byte_valid=rst_n && state==SEND;
    function [15:0] crc_byte(input [15:0] old_crc,input [7:0] value);
        reg [15:0] c;integer j;
        begin
            c=old_crc^{value,8'd0};
            for(j=0;j<8;j=j+1) c=c[15] ? (c<<1)^16'h1021:c<<1;
            crc_byte=c;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;kind<=0;flg<=0;size<=0;index<=0;seq<=0;
            session<=0;crc<=16'hffff;payload_addr<=0;byte_data<=0;frame_done<=0;
        end else begin
            frame_done<=0;
            case(state)
                IDLE:if(frame_valid) begin
                    kind<=message_type;flg<=flags;size<=length;
                    seq<=frame_seq;session<=session_id;index<=0;
                    crc<=16'hffff;payload_addr<=0;state<=PREPARE;
                end
                PREPARE:begin
                    state<=SEND;
                    case(index)
                        0:byte_data<=8'ha5;
                        1:byte_data<=8'h5a;
                        2:byte_data<=8'd1;
                        3:byte_data<=kind;
                        4:byte_data<=flg;
                        5:byte_data<=seq[7:0];
                        6:byte_data<=seq[15:8];
                        7:byte_data<=session[7:0];
                        8:byte_data<=session[15:8];
                        9:byte_data<=session[23:16];
                        10:byte_data<=session[31:24];
                        11:byte_data<=size;
                        12:byte_data<=0;
                        default:if(index<body_end) begin
                            payload_addr<=index[7:0]-8'd13;state<=RAM_WAIT1;
                        end else if(index==body_end) byte_data<=crc[7:0];
                        else byte_data<=crc[15:8];
                    endcase
                end
                // Address changes in PREPARE. Two complete wait edges let
                // a synchronous RAM and its output register settle before
                // RAM_CAPTURE reads the value, including nonblocking updates.
                RAM_WAIT1:state<=RAM_WAIT2;
                RAM_WAIT2:state<=RAM_CAPTURE;
                RAM_CAPTURE:begin byte_data<=payload_data;state<=SEND;end
                SEND:if(byte_ready) begin
                    if(index>=2 && index<body_end) crc<=crc_byte(crc,byte_data);
                    if(index==last_index) begin state<=IDLE;frame_done<=1;end
                    else begin index<=index+1'b1;state<=PREPARE;end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
