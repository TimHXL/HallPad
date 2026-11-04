`timescale 1ns/1ps
// HallPad_Pose_Drums_SDLog production adapter. The keyboard owns codec/LCD.
// Physical L is DRUM1 by default. App directions are side/down/up = 0/1/2.
// Raw pose directions are normalized once before routing or telemetry.
module drumsticks_top #(
    parameter integer CLK_HZ=50000000,I2C_HZ=100000,
    MPU_STARTUP_MS=300,MPU_RETRY_MS=500,SWAP_STICKS=1
)(
    input wire read_launch,slot_abort,
    input wire clk,rst_n,audio_rst_n,audio_enabled,ms_tick,sample_tick,
    input wire [31:0] uptime_ms,
    input wire drum_view,cal_request,
    input wire [1:0] inserted,
    output wire cal_ready,light_hit,light_stick,
    output wire [95:0] cal_status,
    inout wire stick0_scl,stick0_sda,stick1_scl,stick1_sda,
    input wire [127:0] drum_config,
    input wire sim_valid,sim_stick,
    input wire [1:0] sim_direction,
    input wire [6:0] sim_velocity,
    output wire sim_ready,
    input wire session_valid,
    input wire [31:0] session_id,
    output wire telemetry_valid,
    input wire telemetry_ready,
    output wire [95:0] telemetry_data,
    output wire signed [23:0] pcm_wide,
    output wire pcm_valid,ready,frame_overrun,
    output wire [1:0] online,calibrated,
    output wire [15:0] bus_error,output wire [31:0] bus_info,
    output wire diagnostic_error
);
    wire [1:0] raw_online,raw_valid,raw_ready,raw_overflow;
    wire begin_cal,abort_cal;
    wire sensor_rst_n=rst_n;
    wire [111:0] raw0,raw1;
    wire [7:0] who0,who1;wire [6:0] addr0,addr1;
    assign bus_info=SWAP_STICKS ? {1'b0,addr0,who0,1'b0,addr1,who1}:{1'b0,addr1,who1,1'b0,addr0,who0};
    wire [7:0] diag0,diag1;reg [7:0] last0,last1;
    assign bus_error=SWAP_STICKS ? {last0,last1}:{last1,last0};
    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin last0<=0;last1<=0;end
      else begin
        if(begin_cal)begin last0<=0;last1<=0;end
        else begin if(diag0!=0)last0<=diag0;if(diag1!=0)last1<=diag1;end
      end
    end
    wire [1:0] raw_overflow_logical=SWAP_STICKS ? {raw_overflow[0],raw_overflow[1]}:raw_overflow;
    
    // Timestamp only: no retained GAO trace banks in the production build.
    reg [5:0] diag_us_div;
    reg [31:0] diag_uptime_us;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin diag_us_div<=0;diag_uptime_us<=0;end
        else if(diag_us_div==49)begin diag_us_div<=0;diag_uptime_us<=diag_uptime_us+1'b1;end
        else diag_us_div<=diag_us_div+1'b1;
    end
    drum_mpu6050 #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ),.STARTUP_MS(MPU_STARTUP_MS),.RETRY_MS(MPU_RETRY_MS)) u_sensor0(
        .clk(clk),.rst_n(sensor_rst_n),.ms_tick(ms_tick),.enable(read_launch),.slot_abort(slot_abort),.clear_faults(begin_cal),.uptime_us({32'd0,diag_uptime_us}),
        .scl(stick0_scl),.sda(stick0_sda),.online(raw_online[0]),.diagnostic_code(diag0),.who_am_i(who0),.diagnostic_address(addr0),
        .sample_valid(raw_valid[0]),.sample_ready(raw_ready[0]),.sample_data(raw0),.sample_overflow(raw_overflow[0]),.bus_active(),.trace_valid(),.trace_data());
    drum_mpu6050 #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ),.STARTUP_MS(MPU_STARTUP_MS),.RETRY_MS(MPU_RETRY_MS)) u_sensor1(
        .clk(clk),.rst_n(sensor_rst_n),.ms_tick(ms_tick),.enable(read_launch),.slot_abort(slot_abort),.clear_faults(begin_cal),.uptime_us({32'd0,diag_uptime_us}),
        .scl(stick1_scl),.sda(stick1_sda),.online(raw_online[1]),.diagnostic_code(diag1),.who_am_i(who1),.diagnostic_address(addr1),
        .sample_valid(raw_valid[1]),.sample_ready(raw_ready[1]),.sample_data(raw1),.sample_overflow(raw_overflow[1]),.bus_active(),.trace_valid(),.trace_data());
    assign online=SWAP_STICKS ? {raw_online[0],raw_online[1]}:raw_online;
    wire [1:0] valid=SWAP_STICKS ? {raw_valid[0],raw_valid[1]}:raw_valid;
    wire [111:0] dataL=SWAP_STICKS ? raw1:raw0,dataR=SWAP_STICKS ? raw0:raw1;
    wire [1:0] sample_ready,active,vector_valid,neutral,quiet,pose_fault;
    wire [111:0] calL,calR;
    assign raw_ready=SWAP_STICKS ? {sample_ready[0],sample_ready[1]}:sample_ready;

    // Boot/replug automatic calibration; transient transport errors retain reference.
    wire [1:0] cal_mask;
    wire [15:0] cal_progress;
    drum_cal_control u_cal_control(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),
        .drum_view(drum_view),.request(cal_request),.inserted(inserted),.online(online),
        .calibrated(calibrated),.active(active),.progress(cal_progress),
        .pose_fault(pose_fault),.overflow(raw_overflow_logical),.ready(cal_ready),
        .cal_mask(cal_mask),.begin_cal(begin_cal),.abort_cal(abort_cal),.status(cal_status));
    logger_calibration u_calibration(.clk(clk),.rst_n(rst_n),.begin_cal(begin_cal),.abort_cal(abort_cal),.inserted(inserted),.cal_mask(cal_mask),.online(online),
        .valid(valid&sample_ready),.data0(dataL),.data1(dataR),.calibrated(calibrated),
        .active(active),.progress(cal_progress),.result0(calL),.result1(calR));
    wire signed [31:0] xL,yL,zL,xR,yR,zR;
    pose_tracker u_poseL(.clk(clk),.rst_n(rst_n),.clear(begin_cal && cal_mask[0]),.online(online[0]),.calibrated(calibrated[0]),
        .sample_valid(valid[0]),.sample_data(dataL),.cal_result(calL),.sample_ms(uptime_ms),.sample_ready(sample_ready[0]),
        .vector_valid(vector_valid[0]),.wx(xL),.wy(yL),.wz(zL),.neutral(neutral[0]),.quiet(quiet[0]),.fault(pose_fault[0]),.attitude());
    pose_tracker u_poseR(.clk(clk),.rst_n(rst_n),.clear(begin_cal && cal_mask[1]),.online(online[1]),.calibrated(calibrated[1]),
        .sample_valid(valid[1]),.sample_data(dataR),.cal_result(calR),.sample_ms(uptime_ms),.sample_ready(sample_ready[1]),
        .vector_valid(vector_valid[1]),.wx(xR),.wy(yR),.wz(zR),.neutral(neutral[1]),.quiet(quiet[1]),.fault(pose_fault[1]),.attitude());
    wire [1:0] physical_enabled=inserted & online & calibrated & ~active & ~pose_fault &
        ~(cal_mask & {2{begin_cal}});
    wire [1:0] hits,dirL,dirR;
    wire [6:0] velL,velR;
    pose_hit #(.QUIET_SAMPLES(10),.UP_X(SWAP_STICKS?-900:-994),.UP_Z(SWAP_STICKS?-490:-246),
        .SIDE_X(SWAP_STICKS?-490:-246),.SIDE_Z(SWAP_STICKS?900:994)) u_hitL(
        .clk(clk),.rst_n(rst_n),.clear(begin_cal && cal_mask[0]),.enabled(physical_enabled[0] && audio_enabled),
        .ms_tick(ms_tick),.threshold(drum_config[47:32]),.cooldown_ms(drum_config[63:48]),
        .valid(vector_valid[0]),.neutral(neutral[0]),.quiet(quiet[0]),.wx(xL),.wy(yL),.wz(zL),
        .hit(hits[0]),.direction(dirL),.velocity(velL),.armed(),.phase());
    pose_hit #(.QUIET_SAMPLES(10),.PHYSICAL_RIGHT(1),.UP_X(SWAP_STICKS?-994:-900),.UP_Z(SWAP_STICKS?-246:-490),
        .SIDE_X(SWAP_STICKS?-246:-490),.SIDE_Z(SWAP_STICKS?994:900)) u_hitR(
        .clk(clk),.rst_n(rst_n),.clear(begin_cal && cal_mask[1]),.enabled(physical_enabled[1] && audio_enabled),
        .ms_tick(ms_tick),.threshold(drum_config[111:96]),.cooldown_ms(drum_config[127:112]),
        .valid(vector_valid[1]),.neutral(neutral[1]),.quiet(quiet[1]),.wx(xR),.wy(yR),.wz(zR),
        .hit(hits[1]),.direction(dirR),.velocity(velR),.armed(),.phase());

    // App direction IDs: 0 side, 1 down, 2 up. Raw pose IDs are
    // 0 up, 1 down, 2 outward-left, 3 outward-right.
    function [1:0] app_direction(input [1:0] raw);
        begin app_direction=raw==0 ? 2'd2:raw==1 ? 2'd1:2'd0;end
    endfunction
    // Hold both simultaneous hits until the existing sound/telemetry router
    // accepts them. BLE congestion cannot backpressure the sound synthesis.
    reg [1:0] pending;
    reg [1:0] directionL,directionR;
    reg [6:0] velocityL,velocityR;
    reg [31:0] timeL,timeR;
    reg event_overflow;
    wire event_valid,event_ready,real_ready;
    wire [2:0] event_voice;
    wire [6:0] event_velocity;
    wire [1:0] eligible=pending & physical_enabled;
    wire real_valid=|eligible;
    wire selected_stick=!eligible[0];
    wire take=real_valid && real_ready;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending<=0;directionL<=0;directionR<=0;velocityL<=0;velocityR<=0;timeL<=0;timeR<=0;event_overflow<=0;
        end else if(!audio_enabled) pending<=0;
        else begin
            pending<=pending & physical_enabled;
            if(begin_cal)event_overflow<=0;
            if(take) pending[selected_stick]<=0;
            if(hits[0] && physical_enabled[0]) begin
                if(pending[0] && !(take && !selected_stick)) event_overflow<=1;
                else begin pending[0]<=1;directionL<=app_direction(dirL);velocityL<=velL;timeL<=uptime_ms;end
            end
            if(hits[1] && physical_enabled[1]) begin
                if(pending[1] && !(take && selected_stick)) event_overflow<=1;
                else begin pending[1]<=1;directionR<=app_direction(dirR);velocityR<=velR;timeR<=uptime_ms;end
            end
        end
    end
    wire telemetry_overflow;
    drum_event_router u_events(.clk(clk),.rst_n(rst_n),.enabled(audio_enabled),.uptime_ms(uptime_ms),.drum_config(drum_config),
        .real_valid(real_valid),.real_stick(selected_stick),.real_direction(selected_stick?directionR:directionL),
        .real_velocity(selected_stick?velocityR:velocityL),.real_time(selected_stick?timeR:timeL),
        .sim_valid(sim_valid),.sim_stick(sim_stick),.sim_direction(sim_direction),.sim_velocity(sim_velocity),.sim_ready(sim_ready),.real_ready(real_ready),
        .event_valid(event_valid),.light_hit(light_hit),.light_stick(light_stick),.event_voice(event_voice),.event_velocity(event_velocity),.event_ready(event_ready),
        .session_valid(session_valid),.session_id(session_id),.telemetry_valid(telemetry_valid),.telemetry_ready(telemetry_ready),
        .telemetry_data(telemetry_data),.telemetry_overflow(telemetry_overflow),.hit_counts());
    drum_synth u_synth(.clk(clk),.rst_n(audio_rst_n),.sample_tick(sample_tick),
        .event_valid(event_valid),.event_voice(event_voice),.event_velocity(event_velocity),.event_ready(event_ready),
        .pcm_wide(pcm_wide),.pcm_valid(pcm_valid),.overrun(frame_overrun),.ready(ready));
    assign diagnostic_error=(|pose_fault) || (|raw_overflow) || telemetry_overflow || event_overflow;
endmodule
