`timescale 1ns/1ps
// One observation in flight. Never backpressures the key/audio paths.
// A render marker identifies the exact key revision, then follows the fixed
// dry path: reverb mix -> effects -> master/64-frame limiter -> I2S capture.
// From engine OUTPUT to I2S capture there are 68 qualified LEFT boundaries.
module keyboard_response_monitor #(
    parameter integer OUTPUT_BOUNDARIES=68
)(
    input wire clk,rst_n,enabled,clear,
    input wire trigger,input wire [5:0] trigger_key,
    input wire accepted,input wire [5:0] accepted_key,
    input wire [7:0] accepted_revision,
    input wire rendered,sample_tick,
    output reg [5:0] probe_key,output reg [7:0] probe_revision,
    output wire probe_armed,
    output reg busy,valid,output reg [15:0] elapsed_us
);
    localparam IDLE=0,ACK=1,RENDER=2,OUTPUT=3;
    reg [1:0] state;
    reg [5:0] sub_us;
    reg [15:0] timer_us;
    reg [6:0] boundaries;
    assign probe_armed=busy && state==RENDER;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=IDLE;busy<=0;valid<=0;elapsed_us<=0;
            probe_key<=0;probe_revision<=0;sub_us<=0;timer_us<=0;boundaries<=0;end
        else if(clear || !enabled)begin state<=IDLE;busy<=0;valid<=0;end
        else begin
            if(busy)begin
                if(sub_us==49)begin sub_us<=0;timer_us<=timer_us+1'b1;end
                else sub_us<=sub_us+1'b1;
            end
            if(busy && ((timer_us==65535) || (trigger && trigger_key==probe_key)))begin
                // A retrigger supersedes the measured revision. Do not publish
                // an old sample as the new attack, or wrap the displayed timer.
                state<=IDLE;busy<=0;valid<=0;
            end else case(state)
                IDLE:if(trigger)begin probe_key<=trigger_key;busy<=1;state<=ACK;
                    valid<=0;timer_us<=0;sub_us<=0;end
                ACK:if(accepted && accepted_key==probe_key)begin probe_revision<=accepted_revision;state<=RENDER;end
                RENDER:if(rendered)begin boundaries<=OUTPUT_BOUNDARIES;state<=OUTPUT;end
                OUTPUT:if(sample_tick)begin
                    if(boundaries==1)begin
                        elapsed_us<=timer_us+(sub_us==49);valid<=1;busy<=0;state<=IDLE;
                    end else boundaries<=boundaries-1'b1;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
