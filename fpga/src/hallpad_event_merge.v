`timescale 1ns/1ps
// Physical pulses have their own queue. A changed snapshot walks every slot;
// accepted ON/OFF pairs are never reduced to a final mask before dispatch.
module hallpad_event_merge #(parameter [209:0] KEY_NOTE_MAP=0)(input wire key_config_valid,input wire [35:0] key_enabled,key_fixed_mode,input wire [251:0] key_fixed_velocity,input wire clk,rst_n,clear,clear_remote,input wire physical_valid,physical_on,input wire [5:0] physical_key,physical_note,input wire [6:0] physical_velocity,input wire remote_valid,output wire remote_ready,input wire remote_snapshot,input wire [5:0] remote_key,input wire remote_on,input wire [6:0] remote_velocity,input wire [35:0] remote_target_mask,input wire [251:0] remote_target_velocity,output reg [34:0] physical_mask,output reg [35:0] remote_mask,output reg out_valid,input wire out_ready,output reg out_on,output reg [5:0] out_key,out_note,output reg [6:0] out_velocity,output wire overflow,output reg light_valid,output reg [5:0] light_key);
    wire pv,pon,pr;
    wire [5:0] pk,pn;
    wire [6:0] pvel;
    key_event_fifo #(.DEPTH(128)) u_physical_queue(.clk(clk),.rst_n(rst_n),.fifo_clear(clear),.diag_clear(clear),.in_event_valid(physical_valid),.in_event_on(physical_on),.in_event_key_id(physical_key),.in_event_note_sel(physical_note),.in_event_velocity(physical_velocity),.out_event_valid(pv),.out_event_ready(pr),.out_event_on(pon),.out_event_key_id(pk),.out_event_note_sel(pn),.out_event_velocity(pvel),.fifo_empty(),.fifo_full(),.fifo_level(),.overflow(),.overflow_sticky(overflow),.dropped_count());
    reg pending,snapshot;
    reg single_on;
    reg [6:0] single_velocity;
    reg [5:0] remote_index;
    reg [35:0] target,merged_gate;
    reg [251:0] velocity;
    reg [215:0] held_note;
    wire custom_keys=(key_config_valid===1'b1);
    wire target_on=(snapshot ? target[remote_index]:single_on) && (!custom_keys || key_enabled[remote_index]);
    wire [6:0] target_velocity=snapshot ? velocity[remote_index*7 +:7]:single_velocity;
    wire slot_ready=!out_valid || out_ready;
    assign pr=slot_ready && !clear && !clear_remote;
    // During a held clear, every remote key is already released. Complete
    // release-only commands immediately so PANIC/hardware recovery cannot
    // block the protocol queue behind an OFF or an empty snapshot.
    wire release_only=remote_snapshot ? remote_target_mask==0:!remote_on;
    assign remote_ready=rst_n && !clear_remote && ((clear && release_only) || (!clear && !pending));
    task emit(input is_on,input [5:0] key,input [5:0] note,input [6:0] vel);begin out_valid<=1;out_on<=is_on;out_key<=key;out_note<=note;out_velocity<=vel;end endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin physical_mask<=0;remote_mask<=0;merged_gate<=0;held_note<=0;pending<=0;snapshot<=0;single_on<=0;single_velocity<=0;remote_index<=0;target<=0;velocity<=0;out_valid<=0;out_on<=0;out_key<=0;out_note<=0;out_velocity<=0;light_valid<=0;light_key<=0;end
        else begin
            light_valid<=0;
            if(out_valid && out_ready) out_valid<=0;
            if(clear) begin physical_mask<=0;remote_mask<=0;merged_gate<=0;pending<=0;out_valid<=0;end
            else if(clear_remote) begin pending<=remote_mask!=0;snapshot<=1;remote_index<=0;target<=0;end
            else begin
                if(remote_valid && remote_ready) begin
                    pending<=!remote_snapshot || remote_target_mask!=remote_mask;
                    snapshot<=remote_snapshot;remote_index<=remote_snapshot ? 0:remote_key;
                    if(remote_snapshot) begin target<=remote_target_mask;velocity<=remote_target_velocity;end
                    else begin single_on<=remote_on;single_velocity<=remote_velocity;end
                end
                if(slot_ready) begin
                    if(pv) begin
                        if(pk<35) begin
                            physical_mask[pk]<=pon && (!custom_keys || key_enabled[pk]);
                            if(pon && (!custom_keys || key_enabled[pk]) && !physical_mask[pk]) begin
                                held_note[pk*6 +:6]<=pn;merged_gate[pk]<=1;emit(1'b1,pk,pn,custom_keys && key_fixed_mode[pk] ? key_fixed_velocity[pk*7 +:7]:pvel);
                            end else if(!pon && !remote_mask[pk] && merged_gate[pk]) begin
                                merged_gate[pk]<=0;emit(1'b0,pk,held_note[pk*6 +:6],7'd0);
                            end
                        end
                    end else if(pending) begin
                        remote_mask[remote_index]<=target_on;
                        if(target_on && !remote_mask[remote_index] && !(remote_index<35 && physical_mask[remote_index])) begin
                            merged_gate[remote_index]<=1;held_note[remote_index*6 +:6]<=(remote_index==35 ? 6'd36:KEY_NOTE_MAP[remote_index*6 +:6]);
                            emit(1'b1,remote_index,(remote_index==35 ? 6'd36:KEY_NOTE_MAP[remote_index*6 +:6]),custom_keys && key_fixed_mode[remote_index] ? key_fixed_velocity[remote_index*7 +:7]:target_velocity);
                            light_valid<=remote_index<35;light_key<=remote_index;
                        end else if(!target_on && remote_mask[remote_index] && !(remote_index<35 && physical_mask[remote_index]) && merged_gate[remote_index]) begin
                            merged_gate[remote_index]<=0;emit(1'b0,remote_index,held_note[remote_index*6 +:6],7'd0);
                        end
                        if(!snapshot || remote_index==35) pending<=0;else remote_index<=remote_index+1'b1;
                    end
                end
            end
        end
    end
endmodule

module hallpad_light_tap(input wire clk,rst_n,clear,input wire physical_valid,input wire [5:0] physical_key,input wire remote_valid,input wire [5:0] remote_key,output wire valid,output wire [5:0] key,output wire overflow);
    wire rv;
    wire [5:0] rk;
    key_event_fifo #(.DEPTH(64)) u_remote_lights(.clk(clk),.rst_n(rst_n),.fifo_clear(clear),.diag_clear(clear),.in_event_valid(remote_valid),.in_event_on(1'b1),.in_event_key_id(remote_key),.in_event_note_sel(6'd1),.in_event_velocity(7'd1),.out_event_valid(rv),.out_event_ready(!physical_valid),.out_event_on(),.out_event_key_id(rk),.out_event_note_sel(),.out_event_velocity(),.fifo_empty(),.fifo_full(),.fifo_level(),.overflow(),.overflow_sticky(overflow),.dropped_count());
    assign valid=!clear && (physical_valid || rv);
    assign key=physical_valid ? physical_key:rk;
endmodule
