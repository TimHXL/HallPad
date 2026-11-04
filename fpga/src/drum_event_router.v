`timescale 1ns/1ps
// Real hits have priority over the backpressured simulated request. BLE event
// congestion never blocks sound: telemetry drops set a sticky diagnostic.
module drum_event_router(
    input wire clk,rst_n,enabled,
    input wire [31:0] uptime_ms,
    input wire [127:0] drum_config,
    input wire real_valid,real_stick,
    input wire [1:0] real_direction,
    input wire [6:0] real_velocity,
    input wire [31:0] real_time,
    input wire sim_valid,sim_stick,
    input wire [1:0] sim_direction,
    input wire [6:0] sim_velocity,
    output wire sim_ready,real_ready,
    output wire event_valid,
    output wire light_hit,light_stick,
    output wire [2:0] event_voice,
    output wire [6:0] event_velocity,
    input wire event_ready,
    input wire session_valid,
    input wire [31:0] session_id,
    output wire telemetry_valid,
    input wire telemetry_ready,
    output reg [95:0] telemetry_data,
    output reg telemetry_overflow,
    output reg [63:0] hit_counts
);
    // Input handshake consumes each hit once. Capture before doing arithmetic.
    localparam INPUT=0,MAP=1,MULTIPLY=2,DIVIDE=3,OUTPUT=4;
    reg [2:0] state;
    reg selected_stick,real_selected;
    reg [1:0] selected_direction;
    reg [6:0] selected_velocity;
    reg [31:0] selected_time,event_session;
    reg event_session_valid;
    reg [63:0] selected_config;
    reg [7:0] selected_voice;
    reg [6:0] strength,scaled_velocity;
    reg [13:0] numerator,quotient;
    reg [7:0] remainder;
    reg [3:0] divide_left;
    wire [8:0] division_trial={remainder,numerator[13]};
    wire division_bit=division_trial>=9'd127;
    wire [8:0] division_remainder=division_bit ? division_trial-9'd127:division_trial;
    assign real_ready=enabled && state==INPUT;
    assign sim_ready=enabled && state==INPUT && !real_valid;
    assign event_valid=enabled && state==OUTPUT && selected_direction<3 &&
                       selected_voice<6 && scaled_velocity!=0;
    assign event_voice=selected_voice[2:0];
    assign event_velocity=scaled_velocity;
    wire accepted=event_valid && event_ready;
    assign light_hit=accepted;assign light_stick=selected_stick;
    wire [31:0] next_count=(selected_stick ? hit_counts[63:32]:hit_counts[31:0])+1'b1;
    wire [95:0] record={next_count,(real_selected ? 8'd0:8'd1),1'b0,event_velocity,6'd0,selected_direction,7'd0,selected_stick,selected_time};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=INPUT;selected_stick<=0;real_selected<=0;selected_direction<=0;
            selected_velocity<=0;selected_time<=0;selected_config<=0;selected_voice<=255;
            strength<=0;scaled_velocity<=0;numerator<=0;
            quotient<=0;remainder<=0;divide_left<=0;event_session<=0;event_session_valid<=0;
        end else if(!enabled)begin state<=INPUT;scaled_velocity<=0;end
        else case(state)
            INPUT:if(real_valid || sim_valid)begin
                real_selected<=real_valid;
                selected_stick<=real_valid ? real_stick:sim_stick;
                selected_direction<=real_valid ? real_direction:sim_direction;
                selected_velocity<=real_valid ? real_velocity:sim_velocity;
                selected_time<=real_valid ? real_time:uptime_ms;
                selected_config<=(real_valid ? real_stick:sim_stick) ? drum_config[127:64]:drum_config[63:0];
                event_session<=session_id;event_session_valid<=session_valid;
                state<=MAP;
            end
            MAP:begin
                selected_voice<=selected_config[selected_direction*8+:8];
                strength<=selected_config[30:24];state<=MULTIPLY;
            end
            MULTIPLY:begin
                // Capture rounded numerator; no combinational divide in valid/CE.
                numerator<=selected_velocity*strength+14'd63;
                quotient<=0;remainder<=0;divide_left<=14;state<=DIVIDE;
            end
            DIVIDE:begin
                numerator<={numerator[12:0],1'b0};
                remainder<=division_remainder[7:0];
                quotient<={quotient[12:0],division_bit};
                if(divide_left==1)begin
                    scaled_velocity<={quotient[5:0],division_bit};state<=OUTPUT;
                end else divide_left<=divide_left-1'b1;
            end
            OUTPUT:if(selected_direction>=3 || selected_voice>=6 || scaled_velocity==0 || event_ready)state<=INPUT;
            default:state<=INPUT;
        endcase
    end
    (* syn_ramstyle="block_ram" *) reg [95:0] queue[0:15];
    reg [3:0] write_pointer,read_pointer;
    reg [4:0] count;
    reg output_valid;
    reg [31:0] remembered_session;
    wire clear_queue=!session_valid || session_id!=remembered_session;
    assign telemetry_valid=output_valid && !clear_queue;
    wire pop=telemetry_valid && telemetry_ready;
    wire same_event_session=event_session_valid && event_session==session_id;
    wire push=accepted && same_event_session && !clear_queue && (count<16 || pop);
    always @(posedge clk) begin
        if(push) queue[write_pointer]<=record;
        telemetry_data<=queue[read_pointer];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            write_pointer<=0;read_pointer<=0;count<=0;output_valid<=0;
            remembered_session<=0;telemetry_overflow<=0;hit_counts<=0;
        end else begin
            remembered_session<=session_id;
            if(accepted) begin if(selected_stick)hit_counts[63:32]<=next_count;else hit_counts[31:0]<=next_count;end
            if(clear_queue) begin write_pointer<=0;read_pointer<=0;count<=0;output_valid<=0;end
            else begin
                if(push) write_pointer<=write_pointer+1'b1;
                if(pop) begin read_pointer<=read_pointer+1'b1;output_valid<=0;end
                else if(!output_valid && count!=0) output_valid<=1;
                case({push,pop})
                    2'b10:count<=count+1'b1;
                    2'b01:count<=count-1'b1;
                    default:count<=count;
                endcase
                if(accepted && same_event_session && !push) telemetry_overflow<=1;
            end
        end
    end
endmodule
