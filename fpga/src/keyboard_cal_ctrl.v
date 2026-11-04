`timescale 1ns / 1ps

// Board calibration UI controller. Button inputs are already synchronized,
// debounced, one-clock pulses in clk's domain. Physical keys are 0..34.
// Restart always wins and cancels acquisition, even when samples have stopped.
// Confirm: enter setup; confirm all keys released; then confirm each indicated
// key is held fully down. Captures use the existing key_calibrate protocol.
// The user, not a guessed Hall threshold, establishes the full-press endpoint.
//
// setup_hold MUST drive bridge recovery: it silences voices, flushes queued
// events, and holds key_event clear throughout setup. cal_clear is a pulse,
// never the held setup level. In PLAY, confirm only requests bridge recovery;
// it preserves endpoints. USE_PRESET=1 instead starts by loading saved endpoints
// automatically. Preset startup drains the pipeline, then each key independently
// requires its own released samples. A held/missing key cannot block peers. Restart
// reloads the saved endpoints; manual endpoint capture remains USE_PRESET=0.
module keyboard_cal_ctrl #(
    parameter integer RELEASE_TH = 800,
    parameter integer RELEASE_DRAIN_CYCLES = 16,
    parameter integer USE_PRESET = 0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire restart_pulse,
    input  wire confirm_pulse,
    input  wire preset_done,
    input  wire preset_error,
    output wire preset_start,

    input  wire [34:0] baseline_valid_mask,
    input  wire [34:0] calibrated_mask,
    input  wire [34:0] cal_armed_mask,
    input  wire [34:0] cal_busy_mask,
    input  wire [34:0] cal_failed_mask,
    input  wire        cal_error,
    input  wire        calibrated_valid,
    input  wire [5:0]  calibrated_key_id,
    input  wire [11:0] key_travel,

    output wire       setup_hold,
    output wire       cal_clear,
    output wire       cal_cmd_valid,
    output wire [1:0] cal_cmd,
    output wire [5:0] cal_key_id,
    output wire       recover_pulse,
    output reg  [2:0] ui_state,
    output reg  [5:0] current_key,
    output wire       calibration_done,
    output wire       controller_error
);

    localparam [3:0] UNCALIBRATED = 4'd0, REST_READY = 4'd1,
                     REST_ISSUE = 4'd2, REST_WAIT = 4'd3,
                     PRESS_READY = 4'd4, PRESS_ISSUE = 4'd5,
                     PRESS_WAIT = 4'd6, RELEASE_WAIT = 4'd7,
                     PLAY = 4'd8, FAILED = 4'd9,
                     PRESET_CLEAR = 4'd10, PRESET_START = 4'd11,
                     PRESET_WAIT = 4'd12;
    localparam [34:0] ALL_KEYS = {35{1'b1}};
    localparam integer DRAIN_W = $clog2(RELEASE_DRAIN_CYCLES + 1);
    localparam [DRAIN_W-1:0] DRAIN_START = RELEASE_DRAIN_CYCLES;
    localparam [11:0] RELEASE_LIMIT = RELEASE_TH;

    // synthesis translate_off
    initial begin
        if (RELEASE_TH < 0 || RELEASE_TH > 4095 ||
            RELEASE_DRAIN_CYCLES < 16 || RELEASE_DRAIN_CYCLES > 65535 ||
            (USE_PRESET != 0 && USE_PRESET != 1)) begin
            $display("FAIL keyboard_cal_ctrl invalid parameters");
            $finish;
        end
    end
    // synthesis translate_on

    reg [3:0] state;
    reg retry_press;
    reg [DRAIN_W-1:0] drain_count;
    reg [34:0] released_seen;
    reg [34:0] released_next;

    // These are combinational strobes so restart blocks sound and commands on
    // its actual receiving edge, and clear cannot arrive one clock too late.
    assign setup_hold = !rst_n || restart_pulse || (state != PLAY);
    assign cal_clear = rst_n && (restart_pulse ||
                       (state == PRESET_CLEAR) ||
                       ((state == UNCALIBRATED) && confirm_pulse));
    assign preset_start = rst_n && !restart_pulse && (state == PRESET_START);
    assign cal_cmd_valid = rst_n && !restart_pulse && !cal_error &&
                           ((state == REST_ISSUE) || (state == PRESS_ISSUE));
    assign cal_cmd = (state == REST_ISSUE) ? 2'b01 : 2'b10;
    assign cal_key_id = current_key;
    assign recover_pulse = rst_n && !restart_pulse && (state == PLAY) && confirm_pulse;
    assign calibration_done = rst_n && !restart_pulse && (state == PLAY);
    assign controller_error = (state == FAILED);

    always @(*) begin
        case (state)
            UNCALIBRATED: ui_state = 3'd0;
            REST_READY: ui_state = 3'd1;
            REST_ISSUE, REST_WAIT, PRESS_ISSUE, PRESS_WAIT,
            PRESET_CLEAR, PRESET_START, PRESET_WAIT: ui_state = 3'd2;
            PRESS_READY: ui_state = 3'd3;
            RELEASE_WAIT: ui_state = 3'd4;
            PLAY: ui_state = 3'd5;
            default: ui_state = 3'd6;
        endcase
    end

    // The latest observed sample must still be released. A new down sample
    // clears its bit, including on the edge that could otherwise enter PLAY.
    always @(*) begin
        released_next = released_seen;
        if (calibrated_valid && calibrated_key_id <= 6'd34)
            released_next[calibrated_key_id] =
                cal_armed_mask[calibrated_key_id] && (key_travel <= RELEASE_LIMIT);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= USE_PRESET ? PRESET_CLEAR : UNCALIBRATED;
            current_key <= 6'd0;
            retry_press <= 1'b0;
            drain_count <= DRAIN_START;
            released_seen <= 35'd0;
        end else if (restart_pulse) begin
            state <= USE_PRESET ? PRESET_CLEAR : REST_READY;
            current_key <= 6'd0;
            retry_press <= 1'b0;
            drain_count <= DRAIN_START;
            released_seen <= 35'd0;
        end else if ((cal_error || (USE_PRESET && preset_error && state == PRESET_WAIT)) &&
                     state != UNCALIBRATED && state != FAILED &&
                     state != PRESET_CLEAR && state != PRESET_START) begin
            // Endpoint-quality failures are handled by cal_failed_mask below.
            // Protocol errors during a press phase retry that selected key;
            // errors elsewhere restart the all-key baseline phase.
            retry_press <= (state == PRESS_READY || state == PRESS_ISSUE || state == PRESS_WAIT);
            state <= FAILED;
            released_seen <= 35'd0;
        end else begin
            case (state)
                PRESET_CLEAR: state <= PRESET_START;
                // Loader clears its previous sticky done on this edge.
                PRESET_START: state <= PRESET_WAIT;
                PRESET_WAIT: if (preset_done) begin
                    if (baseline_valid_mask == ALL_KEYS && calibrated_mask == ALL_KEYS &&
                        cal_busy_mask == 35'd0 && cal_failed_mask == 35'd0) begin
                        state <= RELEASE_WAIT;
                        drain_count <= DRAIN_START;
                        released_seen <= 35'd0;
                    end else begin
                        state <= FAILED;
                        released_seen <= 35'd0;
                    end
                end
                UNCALIBRATED: if (confirm_pulse) begin
                    state <= REST_READY;
                    current_key <= 6'd0;
                end
                REST_READY: if (confirm_pulse) begin
                    current_key <= 6'd0;
                    retry_press <= 1'b0;
                    state <= REST_ISSUE;
                end
                REST_ISSUE: begin
                    // Child consumes the command on THIS edge. Only after
                    // all 35 commands were consumed can REST_WAIT inspect it.
                    if (current_key == 6'd34)
                        state <= REST_WAIT;
                    else
                        current_key <= current_key + 1'b1;
                end
                REST_WAIT: if (cal_busy_mask == 35'd0) begin
                    if (baseline_valid_mask == ALL_KEYS && cal_failed_mask == 35'd0) begin
                        current_key <= 6'd0;
                        retry_press <= 1'b1;
                        state <= PRESS_READY;
                    end else begin
                        retry_press <= 1'b0;
                        state <= FAILED;
                    end
                end
                PRESS_READY: if (confirm_pulse)
                    state <= PRESS_ISSUE;
                PRESS_ISSUE: begin
                    // A separate issue state ensures even CAPTURE_LOG2=0
                    // cannot be mistaken for completion before acceptance.
                    state <= PRESS_WAIT;
                end
                PRESS_WAIT: if (!cal_busy_mask[current_key]) begin
                    if (calibrated_mask[current_key] && !cal_failed_mask[current_key]) begin
                        if (current_key == 6'd34) begin
                            if (calibrated_mask == ALL_KEYS) begin
                                state <= RELEASE_WAIT;
                                drain_count <= DRAIN_START;
                                released_seen <= 35'd0;
                            end else begin
                                retry_press <= 1'b0;
                                state <= FAILED;
                            end
                        end else begin
                            current_key <= current_key + 1'b1;
                            state <= PRESS_READY;
                        end
                    end else begin
                        retry_press <= 1'b1;
                        state <= FAILED;
                    end
                end
                RELEASE_WAIT: begin
                    if (drain_count != 0) begin
                        drain_count <= drain_count - 1'b1;
                        released_seen <= 35'd0;
                    end else begin
                        released_seen <= released_next;
                        if (USE_PRESET || (released_next == ALL_KEYS && cal_armed_mask == ALL_KEYS))
                            state <= PLAY;
                    end
                end
                PLAY: begin end
                FAILED: if (confirm_pulse) begin
                    if (USE_PRESET)
                        state <= PRESET_CLEAR;
                    else if (retry_press)
                        state <= PRESS_READY;
                    else begin
                        current_key <= 6'd0;
                        state <= REST_READY;
                    end
                end
                default: begin
                    state <= FAILED;
                    retry_press <= 1'b0;
                end
            endcase
        end
    end

endmodule
