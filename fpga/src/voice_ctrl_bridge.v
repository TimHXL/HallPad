`timescale 1ns/1ps
// One persistent slot per physical key. No search, stealing, or sample-tick
// waits on the event input. An ON revision preserves short/retriggered notes
// until the audio lane observes that key, independently of NOTE_OFF timing.
module voice_ctrl_bridge #(
    parameter integer VOICE_COUNT=36,RECOVERY_CYCLES=16
)(
    input wire clk,rst_n,
    input wire event_valid,event_on,
    input wire [5:0] event_key_id,event_note_sel,
    input wire [6:0] event_velocity,
    output wire event_ready,
    input wire fifo_overflow_sticky,recover_request,
    input wire mute_request,
    output reg [VOICE_COUNT*6-1:0] voice_note,
    output reg [VOICE_COUNT*7-1:0] voice_velocity,
    output reg [VOICE_COUNT*8-1:0] voice_revision,
    output reg [VOICE_COUNT-1:0] voice_gate,
    output wire recovery_active,engine_rst_n,fifo_clear,event_state_clear,fifo_diag_clear,
    output reg input_error,event_ignored,overflow_fault
);
    localparam integer CW=RECOVERY_CYCLES<2 ? 1 : $clog2(RECOVERY_CYCLES);
    reg [CW-1:0] recovery_count;
    reg recover_hold;
    wire payload_ok=event_key_id<VOICE_COUNT && event_note_sel>=1 && event_note_sel<=36 &&
        (!event_on || event_velocity!=0);
    assign recovery_active=!rst_n || recover_hold || recover_request || fifo_overflow_sticky;
    wire mute_active=(mute_request===1'b1);
    assign engine_rst_n=rst_n && !recovery_active && !mute_active;
    assign fifo_clear=recovery_active || mute_active;assign event_state_clear=recovery_active;
    // The overflow cause must clear after the bridge has latched the fault.
    // Otherwise recovery_active keeps the FIFO empty but its sticky overflow
    // keeps recovery_active asserted forever. overflow_fault preserves diagnosis.
    assign fifo_diag_clear=rst_n && (recover_request || fifo_overflow_sticky);
    assign event_ready=rst_n && !recovery_active && !mute_active;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin recover_hold<=1;recovery_count<=RECOVERY_CYCLES-1;overflow_fault<=0;end
        else begin
            if(recover_request)overflow_fault<=0;else if(fifo_overflow_sticky)overflow_fault<=1;
            if(recover_request || fifo_overflow_sticky)begin recover_hold<=1;recovery_count<=RECOVERY_CYCLES-1;end
            else if(recover_hold)begin
                if(recovery_count==0)recover_hold<=0;else recovery_count<=recovery_count-1'b1;
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            voice_note<=0;voice_velocity<=0;voice_revision<=0;voice_gate<=0;input_error<=0;event_ignored<=0;
        end else begin
            input_error<=0;event_ignored<=0;
            if(recovery_active || mute_active)begin voice_note<=0;voice_velocity<=0;voice_revision<=0;voice_gate<=0;end
            else if(event_valid && event_ready)begin
                if(!payload_ok)begin input_error<=1;event_ignored<=1;end
                else if(event_on)begin
                    voice_note[event_key_id*6 +:6]<=event_note_sel;
                    voice_velocity[event_key_id*7 +:7]<=event_velocity;
                    voice_revision[event_key_id*8 +:8]<=voice_revision[event_key_id*8 +:8]+8'd1;
                    voice_gate[event_key_id]<=1;
                end else if(voice_note[event_key_id*6 +:6]==event_note_sel)voice_gate[event_key_id]<=0;
                else begin input_error<=1;event_ignored<=1;end
            end
        end
    end
endmodule
