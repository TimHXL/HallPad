`timescale 1ns / 1ps

// Internal detector: key_calibrate -> key_event -> future key_event_fifo.
// Every calibrated_valid clock is consumed; there is NO input backpressure.
// event_valid is a registered write strobe, NOT a held valid/ready interface.
// The sink must accept every asserted cycle, including consecutive cycles.
// One sample produces at most one event. No samples means no ON or OFF.
//
// All state is indexed by physical key_id=0..34. ON latches note_sel=1..35;
// OFF carries that SAME note even if later samples have a changed/absent note.
// Reset/clear requires RELEASE_SAMPLES released samples before a key can play.
// Threshold confirmation counts successive samples of THAT key, not clocks.
// Missing samples leave confirmation counts unchanged.
//
// Velocity measures time from START_TH to the first sample of a confirmed
// PRESS_TH run. Confirmation latency is excluded from velocity. A retreat
// below START_TH cancels the trial. Ages saturate, never wrap or trigger ON.
// Shared clock divider; independent saturating ages only advance while measuring.
// Default tick=100 us at 50 MHz. Thresholds/timing require hardware tuning.
//
// state_clear is a synchronous SETUP reset, not an OFF/panic command. Before
// reset/recalibration the upper controller must silence voices and drain/flush
// queued events, block stale upstream samples, then clear this module. This
// module cannot infer recalibration from missing samples. Do not wire cal_clear
// alone and expect downstream voices to release. Assert rst_n asynchronously;
// deassert synchronously upstream. No board pins or audio tick are used here.
module key_event #(
    parameter integer REQUIRE_RAW_PRESS = 0,
    parameter integer TICK_CYCLES             = 5000,
    parameter integer RELEASE_TH              = 800,
    parameter integer START_TH                = 1200,
    parameter integer PRESS_TH                = 2400,
    parameter integer PRESS_SAMPLES           = 2,
    parameter integer RELEASE_SAMPLES         = 2,
    parameter integer VELOCITY_BIN_TICKS       = 10,
    parameter integer VELOCITY_TIMEOUT_TICKS   = 400
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        state_clear,
    input  wire        calibrated_valid,
    input  wire [5:0]  calibrated_key_id,
    input  wire        calibrated_note_valid,
    input  wire [5:0]  calibrated_note_sel,
    input  wire [11:0] key_travel,
    // Optional synchronous evidence from key_calibrate. It prevents an IIR
    // spike tail from being mistaken for two physical pressed samples.
    input  wire        raw_press_evidence,

    output reg         event_valid,
    output reg         event_on,
    output reg  [5:0]  event_key_id,
    output reg  [5:0]  event_note_sel,
    output reg  [6:0]  event_velocity,
    output reg  [34:0] key_down_mask,
    output reg  [34:0] key_armed_mask,
    output reg  [34:0] measuring_mask,
    output reg         input_error
);

    function integer width_for;
        input integer maximum;
        integer value;
        begin
            value = maximum;
            width_for = 0;
            while (value > 0) begin
                width_for = width_for + 1;
                value = value >> 1;
            end
            if (width_for < 1) width_for = 1;
        end
    endfunction

    localparam integer DIV_W = width_for(TICK_CYCLES - 1);
    localparam integer PRESS_W = width_for(PRESS_SAMPLES - 1);
    localparam integer RELEASE_W = width_for(RELEASE_SAMPLES - 1);
    localparam [DIV_W-1:0] DIV_LAST = TICK_CYCLES - 1;
    localparam [PRESS_W-1:0] PRESS_LAST = PRESS_SAMPLES - 1;
    localparam [RELEASE_W-1:0] RELEASE_LAST = RELEASE_SAMPLES - 1;
    localparam [11:0] RELEASE_LIMIT = RELEASE_TH;
    localparam [11:0] START_LIMIT = START_TH;
    localparam [11:0] PRESS_LIMIT = PRESS_TH;
    localparam [15:0] AGE_LIMIT = VELOCITY_TIMEOUT_TICKS;

    // synthesis translate_off
    initial begin
        if (TICK_CYCLES < 1 ||
            RELEASE_TH < 0 || RELEASE_TH >= START_TH ||
            START_TH >= PRESS_TH || PRESS_TH > 4095 ||
            PRESS_SAMPLES < 1 || PRESS_SAMPLES > 16 ||
            RELEASE_SAMPLES < 1 || RELEASE_SAMPLES > 16 ||
            VELOCITY_BIN_TICKS < 1 || VELOCITY_BIN_TICKS > 2047 ||
            VELOCITY_TIMEOUT_TICKS <= 32 * VELOCITY_BIN_TICKS ||
            VELOCITY_TIMEOUT_TICKS > 65535) begin
            $display("FAIL key_event invalid parameters");
            $finish;
        end
    end
    // synthesis translate_on

    reg [DIV_W-1:0] tick_count;
    wire time_tick = (tick_count == DIV_LAST);
    reg [15:0] age [0:34];
    reg [PRESS_W-1:0] press_count [0:34];
    reg [RELEASE_W-1:0] release_count [0:34];
    reg [6:0] candidate_velocity [0:34];
    reg [5:0] active_note [0:34];
    wire id_ok = (calibrated_key_id <= 6'd34);
    wire note_ok = calibrated_note_valid &&
                   calibrated_note_sel >= 6'd1 && calibrated_note_sel <= 6'd35;

    // Coarse monotonic lookup avoids division and is tunable in tick units.
    // With defaults: <=1/2/4/8/12/16/24/32 ms, then the slowest bucket.
    function [6:0] velocity_for;
        input [15:0] ticks;
        begin
            if      (ticks <=      VELOCITY_BIN_TICKS) velocity_for = 7'd127;
            else if (ticks <=  2 * VELOCITY_BIN_TICKS) velocity_for = 7'd112;
            else if (ticks <=  4 * VELOCITY_BIN_TICKS) velocity_for = 7'd96;
            else if (ticks <=  8 * VELOCITY_BIN_TICKS) velocity_for = 7'd80;
            else if (ticks <= 12 * VELOCITY_BIN_TICKS) velocity_for = 7'd64;
            else if (ticks <= 16 * VELOCITY_BIN_TICKS) velocity_for = 7'd48;
            else if (ticks <= 24 * VELOCITY_BIN_TICKS) velocity_for = 7'd32;
            else if (ticks <= 32 * VELOCITY_BIN_TICKS) velocity_for = 7'd16;
            else                                      velocity_for = 7'd8;
        end
    endfunction

    reg [15:0] sample_age;
    reg [6:0] sample_velocity;
    always @(*) begin
        sample_age = 16'd0;
        if (id_ok) begin
            if (measuring_mask[calibrated_key_id]) begin
                sample_age = age[calibrated_key_id];
                // Include a coincident tick for an existing measurement only.
                if (time_tick && sample_age < AGE_LIMIT)
                    sample_age = sample_age + 16'd1;
            end
        end
        sample_velocity = velocity_for(sample_age);
    end

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_count <= {DIV_W{1'b0}};
            key_down_mask <= 35'd0;
            key_armed_mask <= 35'd0;
            measuring_mask <= 35'd0;
            event_valid <= 1'b0;
            event_on <= 1'b0;
            event_key_id <= 6'd0;
            event_note_sel <= 6'd0;
            event_velocity <= 7'd0;
            input_error <= 1'b0;
            for (k = 0; k < 35; k = k + 1) begin
                age[k] <= 16'd0;
                press_count[k] <= {PRESS_W{1'b0}};
                release_count[k] <= {RELEASE_W{1'b0}};
                candidate_velocity[k] <= 7'd0;
                active_note[k] <= 6'd0;
            end
        end else begin
            event_valid <= 1'b0;
            input_error <= 1'b0;
            if (state_clear) begin
                tick_count <= {DIV_W{1'b0}};
                key_down_mask <= 35'd0;
                key_armed_mask <= 35'd0;
                measuring_mask <= 35'd0;
                event_on <= 1'b0;
                event_key_id <= 6'd0;
                event_note_sel <= 6'd0;
                event_velocity <= 7'd0;
                for (k = 0; k < 35; k = k + 1) begin
                    age[k] <= 16'd0;
                    press_count[k] <= {PRESS_W{1'b0}};
                    release_count[k] <= {RELEASE_W{1'b0}};
                    candidate_velocity[k] <= 7'd0;
                    active_note[k] <= 6'd0;
                end
            end else begin
                if (time_tick) begin
                    tick_count <= {DIV_W{1'b0}};
                    for (k = 0; k < 35; k = k + 1) begin
                        if (measuring_mask[k] && age[k] < AGE_LIMIT)
                            age[k] <= age[k] + 16'd1;
                    end
                end else tick_count <= tick_count + 1'b1;

                if (calibrated_valid) begin
                    if (!id_ok || (calibrated_note_valid && !note_ok))
                        input_error <= 1'b1;
                    if (id_ok) begin
                        if (!key_armed_mask[calibrated_key_id]) begin
                            // Calibration also arms at rest; this local guard
                            // covers resetting the detector independently.
                            if (key_travel <= RELEASE_LIMIT) begin
                                if (release_count[calibrated_key_id] == RELEASE_LAST) begin
                                    key_armed_mask[calibrated_key_id] <= 1'b1;
                                    release_count[calibrated_key_id] <= {RELEASE_W{1'b0}};
                                end else
                                    release_count[calibrated_key_id] <= release_count[calibrated_key_id] + 1'b1;
                            end else release_count[calibrated_key_id] <= {RELEASE_W{1'b0}};
                        end else if (key_down_mask[calibrated_key_id]) begin
                            // Release uses the position and saved ON identity;
                            // a missing or changed current mapping cannot hang it.
                            if (key_travel <= RELEASE_LIMIT) begin
                                if (release_count[calibrated_key_id] == RELEASE_LAST) begin
                                    key_down_mask[calibrated_key_id] <= 1'b0;
                                    release_count[calibrated_key_id] <= {RELEASE_W{1'b0}};
                                    event_valid <= 1'b1;
                                    event_on <= 1'b0;
                                    event_key_id <= calibrated_key_id;
                                    event_note_sel <= active_note[calibrated_key_id];
                                    event_velocity <= 7'd0;
                                end else
                                    release_count[calibrated_key_id] <= release_count[calibrated_key_id] + 1'b1;
                            end else release_count[calibrated_key_id] <= {RELEASE_W{1'b0}};
                        end else if (!note_ok || key_travel < START_LIMIT) begin
                            measuring_mask[calibrated_key_id] <= 1'b0;
                            age[calibrated_key_id] <= 16'd0;
                            press_count[calibrated_key_id] <= {PRESS_W{1'b0}};
                        end else begin
                            if (!measuring_mask[calibrated_key_id]) begin
                                measuring_mask[calibrated_key_id] <= 1'b1;
                                age[calibrated_key_id] <= 16'd0;
                            end
                            if (key_travel >= PRESS_LIMIT && (REQUIRE_RAW_PRESS==0 || raw_press_evidence)) begin
                                if (press_count[calibrated_key_id] == {PRESS_W{1'b0}})
                                    candidate_velocity[calibrated_key_id] <= sample_velocity;
                                if (press_count[calibrated_key_id] == PRESS_LAST) begin
                                    key_down_mask[calibrated_key_id] <= 1'b1;
                                    measuring_mask[calibrated_key_id] <= 1'b0;
                                    age[calibrated_key_id] <= 16'd0;
                                    press_count[calibrated_key_id] <= {PRESS_W{1'b0}};
                                    active_note[calibrated_key_id] <= calibrated_note_sel;
                                    event_valid <= 1'b1;
                                    event_on <= 1'b1;
                                    event_key_id <= calibrated_key_id;
                                    event_note_sel <= calibrated_note_sel;
                                    event_velocity <= (PRESS_SAMPLES == 1) ?
                                        sample_velocity : candidate_velocity[calibrated_key_id];
                                end else
                                    press_count[calibrated_key_id] <= press_count[calibrated_key_id] + 1'b1;
                            end else press_count[calibrated_key_id] <= {PRESS_W{1'b0}};
                        end
                    end
                end
            end
        end
    end

endmodule
