`timescale 1ns / 1ps

// Internal 35-key calibration, after key_channel_map; same clk/rst_n.
// No ready: every valid cycle is consumed, including repeated same-key inputs.
// Explicit two-point calibration or optional imported two-point endpoints.
// For manual capture, hold the key at its endpoint and let
// the upstream filter settle BEFORE requesting capture. Normal operation never
// adapts the baseline. ADC direction/range are measured, not assumed from wiring.
//
// cal_cmd_valid: 00 invalidate key, 01 capture rest, 10 capture full press.
// 11, key_id > 34, or press without a rest baseline: cal_error, no command.
// A command wins over a SAME-key sample and cancels that key's pipeline data;
// other keys continue. cal_clear wins globally; rst_n also clears diagnostics.
// Each capture takes the NEXT 2**CAPTURE_LOG2 valid samples of its key.
// Missing samples do not advance capture. Observe busy_mask; abort/retry with
// another command if acquisition stops. There is deliberately no guessed timeout.
//
// calibrated_mask means both endpoints passed validation. armed_mask additionally
// requires a subsequent released sample. Manual capture uses ARM_DELTA.
// Imported presets allow up to 3*span/16 (18.75% travel), below RELEASE_TH=800
// (19.5%), to tolerate power-cycle Hall offset drift. Endpoints never adapt.
// That first released sample may itself be output. Recalibration is a setup
// operation: the future event/voice controller must release active voices first.
// Cancellation here is NOT an OFF event. No ON/OFF or velocity is generated here.
//
// travel = floor(clamp(directional_delta, 0, span) * 4095 / span).
// 16 registered stages (lookup, delta, capture, 12 divider steps, output): input accepted at
// edge n appears after edge n+15. Throughput is one sample per clock.
// Sidebands have the SAME delay independently of valid and survive cal_clear.
// Payload holds on invalid output; calibrated_note_valid is low then.
// Assert reset asynchronously; deassert synchronously upstream.
module key_calibrate #(
    parameter integer CAPTURE_LOG2 = 5,   // 0..8: 1..256 samples per endpoint
    parameter integer CHECK_CAPTURE_SPREAD = 1, // 0 removes per-key min/max hardware
    parameter integer MAX_SPREAD   = 16,  // 0..4095 ADC counts, peak-to-peak
    parameter integer MIN_SPAN     = 128, // 1..4095 ADC counts
    parameter integer ARM_DELTA    = 8,   // 0..MIN_SPAN-1 ADC counts
    parameter integer ENABLE_PRESET_LOAD = 0 // leave 0 for legacy capture-only use
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_valid,
    input  wire [5:0]  key_id,
    input  wire        key_note_valid,
    input  wire [5:0]  note_sel,
    input  wire [11:0] key_data,
    input  wire [11:0] key_raw_data,
    input  wire        mapped_scan_done,
    input  wire [2:0]  mapped_tag_error,
    input  wire        map_error,

    input  wire        cal_clear,
    input  wire        cal_cmd_valid,
    input  wire [1:0]  cal_cmd,
    input  wire [5:0]  cal_key_id,

    // Synchronous endpoint import; consumes every load_valid edge, no ready.
    // Priority: reset/clear > same-key load > command > sample.
    // A rejected load invalidates that addressed key, cancels stale pipeline
    // words, and pulses cal_error. Other keys continue normally.
    input  wire        load_valid,
    input  wire [5:0]  load_key_id,
    input  wire [11:0] load_baseline,
    input  wire [11:0] load_span,
    input  wire        load_decreasing,

    output reg         calibrated_valid,
    output reg  [5:0]  calibrated_key_id,
    output reg         calibrated_note_valid,
    output reg  [5:0]  calibrated_note_sel,
    output reg  [11:0] key_travel,
    // Synchronous raw corroboration: actual unfiltered position >=25% span.
    // Delayed with the SAME key/travel payload; no extra divider or latency.
    output reg         raw_press_evidence,
    output reg  [11:0] calibrated_data,
    output reg  [11:0] calibrated_raw_data,
    output wire        calibrated_scan_done,
    output wire [2:0]  calibrated_tag_error,
    output wire        calibrated_map_error,

    output reg  [34:0] baseline_valid_mask,
    output reg  [34:0] calibrated_mask,
    output reg  [34:0] armed_mask,
    output reg  [34:0] busy_mask,
    output reg  [34:0] failed_mask,
    output reg         cal_error
);

    localparam integer COUNT_W = (CAPTURE_LOG2 < 1) ? 1 : CAPTURE_LOG2;
    localparam integer SUM_W = 12 + CAPTURE_LOG2;
    localparam [COUNT_W-1:0] LAST_COUNT = (1 << CAPTURE_LOG2) - 1;
    localparam [11:0] SPREAD_LIMIT = MAX_SPREAD;
    localparam [11:0] SPAN_LIMIT = MIN_SPAN;
    localparam [11:0] ARM_LIMIT = ARM_DELTA;

    // Parameters are checked in simulation rather than silently truncated.
    // synthesis translate_off
    initial begin
        if (CAPTURE_LOG2 < 0 || CAPTURE_LOG2 > 8 ||
            MAX_SPREAD < 0 || MAX_SPREAD > 4095 ||
            MIN_SPAN < 1 || MIN_SPAN > 4095 ||
            ARM_DELTA < 0 || ARM_DELTA >= MIN_SPAN ||
            (ENABLE_PRESET_LOAD != 0 && ENABLE_PRESET_LOAD != 1)) begin
            $display("FAIL key_calibrate invalid parameters");
            $finish;
        end
    end
    // synthesis translate_on

    reg [11:0] baseline [0:34];
    reg [11:0] span [0:34];
    reg [34:0] decreasing;
    reg [34:0] capture_press;
    reg [COUNT_W-1:0] count [0:34];
    reg [SUM_W-1:0] sum [0:34];
    reg [11:0] minimum [0:34];
    reg [11:0] maximum [0:34];

    wire load_request = (ENABLE_PRESET_LOAD != 0) && load_valid;
    wire load_addressed = load_request && load_key_id <= 6'd34;
    wire [12:0] load_end_up = {1'b0, load_baseline} + {1'b0, load_span};
    wire load_ok = load_addressed && load_span >= SPAN_LIMIT &&
                   (load_decreasing ? (load_baseline >= load_span) : !load_end_up[12]);
    wire same_key_load = load_addressed && load_key_id == key_id;
    reg command_ok;
    always @(*) begin
        command_ok = 1'b0;
        if (cal_cmd_valid && cal_key_id <= 6'd34 &&
            !(load_addressed && load_key_id == cal_key_id)) begin
            case (cal_cmd)
                2'b00, 2'b01: command_ok = 1'b1;
                2'b10: command_ok = baseline_valid_mask[cal_key_id];
                default: begin end
            endcase
        end
    end
    wire same_key_command = command_ok && (cal_key_id == key_id);
    wire note_ok = key_note_valid && note_sel >= 6'd1 && note_sel <= 6'd35;

    // Snapshot endpoint lookup before arithmetic; throughput remains one sample/clk.
    reg valid0, valid1;
    reg [36:0] payload0, payload1;
    reg [11:0] baseline0, span0, span1, delta, raw_delta;
    reg decreasing0;
    wire cancel0 = (command_ok && cal_key_id == payload0[36:31]) || (load_addressed && load_key_id == payload0[36:31]);
    wire cancel1 = (command_ok && cal_key_id == payload1[36:31]) || (load_addressed && load_key_id == payload1[36:31]);
    wire [11:0] sample_span = span1;
    wire sample_eligible = valid1 && !cal_clear && !cancel1 && (armed_mask[payload1[36:31]] || delta <= ARM_LIMIT || ((ENABLE_PRESET_LOAD != 0) && delta <= ((span1 >> 3) + (span1 >> 4))));
    wire [11:0] delta_left=decreasing0 ? baseline0:payload0[23:12];
    wire [11:0] delta_right=decreasing0 ? payload0[23:12]:baseline0;
    wire [11:0] raw_left=decreasing0 ? baseline0:payload0[11:0];
    wire [11:0] raw_right=decreasing0 ? payload0[11:0]:baseline0;
    wire [12:0] delta_difference={1'b0,delta_left}-{1'b0,delta_right};
    wire [12:0] raw_difference={1'b0,raw_left}-{1'b0,raw_right};
    wire [23:0] numerator = {delta, 12'd0} - {12'd0, delta};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid0 <= 0; valid1 <= 0;
            payload0 <= 0; payload1 <= 0;
            baseline0 <= 0; span0 <= 1; span1 <= 1;
            decreasing0 <= 0; delta <= 0; raw_delta <= 0;
        end else begin
            valid0 <= 0;
            if (key_valid && key_id <= 34 && !cal_clear && !same_key_command && !same_key_load) begin
                valid0 <= calibrated_mask[key_id] && !busy_mask[key_id];
                baseline0 <= baseline[key_id];
                span0 <= span[key_id];
                decreasing0 <= decreasing[key_id];
                payload0 <= {key_id, note_ok, note_ok ? note_sel : 6'd0, key_data, key_raw_data};
            end
            valid1 <= valid0 && !cal_clear && !cancel0;
            if (valid0 && !cal_clear && !cancel0) begin
                span1 <= span0;
                payload1 <= payload0;
                delta<=delta_difference[12] ? 12'd0:delta_difference[11:0];
                raw_delta<=raw_difference[12] ? 12'd0:raw_difference[11:0];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cal_error <= 0;
        else begin
            cal_error <= 0;
            if (!cal_clear) begin
                if (cal_cmd_valid && !command_ok && !(load_addressed && load_key_id == cal_key_id)) cal_error <= 1;
                if (load_request && !load_ok) cal_error <= 1;
                if (key_valid && (key_id > 34 || (key_note_valid && !note_ok))) cal_error <= 1;
            end
        end
    end

    // Keep capture arithmetic local to each state bank. The former shared
    // 35-way lookup -> mean -> span -> write-enable path failed 50 MHz.
    // No pipeline latency or capture/command priority is changed.
    genvar k;
    generate for (k = 0; k < 35; k = k + 1) begin : gen_capture
        wire [SUM_W-1:0] next_sum = sum[k] + {{CAPTURE_LOG2{1'b0}}, key_data};
        wire [COUNT_W-1:0] next_count = count[k] + 1'b1;
        wire [11:0] next_min = key_data < minimum[k] ? key_data : minimum[k];
        wire [11:0] next_max = key_data > maximum[k] ? key_data : maximum[k];
        wire [11:0] mean = next_sum[SUM_W-1:CAPTURE_LOG2];
        // One signed difference supplies direction and absolute span.
        reg finish_pending;reg [11:0] finish_mean,finish_baseline;
        wire [12:0] endpoint_difference={1'b0,finish_mean}-{1'b0,finish_baseline};
        wire capture_decreasing=endpoint_difference[12];
        wire [11:0] measured_span=capture_decreasing ? (~endpoint_difference[11:0]+12'd1):endpoint_difference[11:0];
        wire capture_last = count[k] == LAST_COUNT;
        wire capture_spread_bad = CHECK_CAPTURE_SPREAD != 0 && (next_max - next_min) > SPREAD_LIMIT;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                finish_pending<=0;finish_mean<=0;finish_baseline<=0;
                baseline_valid_mask[k] <= 0; calibrated_mask[k] <= 0;
                armed_mask[k] <= 0; busy_mask[k] <= 0; failed_mask[k] <= 0;
                decreasing[k] <= 0; capture_press[k] <= 0;
                baseline[k] <= 0; span[k] <= 0; count[k] <= 0; sum[k] <= 0;
                minimum[k] <= 12'hfff; maximum[k] <= 0;
            end else if (cal_clear) begin
                finish_pending<=0;
                baseline_valid_mask[k] <= 0; calibrated_mask[k] <= 0;
                armed_mask[k] <= 0; busy_mask[k] <= 0; failed_mask[k] <= 0;
            end else begin
                finish_pending<=0;
                if(finish_pending && !(command_ok && cal_key_id==k) && !(load_addressed && load_key_id==k))begin
                    busy_mask[k]<=0;
                    if(measured_span<SPAN_LIMIT)failed_mask[k]<=1;
                    else begin span[k]<=measured_span;decreasing[k]<=capture_decreasing;calibrated_mask[k]<=1;end
                end
                if (command_ok && cal_key_id == k) begin
                    calibrated_mask[k] <= 1'b0;
                    armed_mask[k] <= 1'b0;
                    failed_mask[k] <= 1'b0;
                    busy_mask[k] <= (cal_cmd != 2'b00);
                    capture_press[k] <= (cal_cmd == 2'b10);
                    count[k] <= {COUNT_W{1'b0}};
                    sum[k] <= {SUM_W{1'b0}};
                    minimum[k] <= 12'hfff;
                    maximum[k] <= 12'd0;
                    if (cal_cmd != 2'b10) baseline_valid_mask[k] <= 1'b0;
                end

                if (load_addressed && load_key_id == k) begin
                    baseline_valid_mask[k] <= load_ok;
                    calibrated_mask[k] <= load_ok;
                    armed_mask[k] <= 1'b0;
                    busy_mask[k] <= 1'b0;
                    failed_mask[k] <= !load_ok;
                    capture_press[k] <= 1'b0;
                    count[k] <= {COUNT_W{1'b0}};
                    sum[k] <= {SUM_W{1'b0}};
                    minimum[k] <= 12'hfff;
                    maximum[k] <= 12'd0;
                    if (load_ok) begin
                        baseline[k] <= load_baseline;
                        span[k] <= load_span;
                        decreasing[k] <= load_decreasing;
                    end
                end

                if (key_valid && key_id == k && !same_key_command && !same_key_load) begin
                    if (busy_mask[k] && !finish_pending) begin
                        sum[k] <= next_sum;
                        if(CHECK_CAPTURE_SPREAD != 0)begin
                            minimum[k] <= next_min;maximum[k] <= next_max;
                        end
                        count[k] <= next_count;
                        if (capture_last) begin
                            busy_mask[k] <= 1'b0;
                            if (capture_spread_bad) begin
                                failed_mask[k] <= 1'b1;
                            end else if (!capture_press[k]) begin
                                baseline[k] <= mean;
                                baseline_valid_mask[k] <= 1'b1;
                            end else begin
                                // Register the captured endpoints before subtract/abs/check.
                                finish_mean<=mean;finish_baseline<=baseline[k];finish_pending<=1;busy_mask[k]<=1;
                            end
                        end
                    end
                end
                if (sample_eligible && payload1[36:31] == k && !(command_ok && cal_key_id == k) && !(load_addressed && load_key_id == k)) armed_mask[k] <= 1'b1;
            end
        end
    end endgenerate

    // Restoring division: for delta < span, the upper 12 bits of numerator
    // are already less than span; only the lower 12 quotient bits are needed.
    // Each stage is one 13-bit comparison/subtraction, accepting one clk/sample.
    reg [12:0] pipe_valid;
    reg [12:0] raw_evidence_pipe;
    wire sample_raw_pressed = {raw_delta,2'b00}>={2'b00,sample_span};
    reg [11:0] remainder [0:12];
    reg [11:0] quotient [0:12];
    reg [11:0] divisor [0:12];
    reg [12:0] saturated;
    // {key_id, note_valid, note_sel, filtered_data, raw_data}
    reg [36:0] payload [0:12];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid[0] <= 1'b0;raw_evidence_pipe[0]<=0;
            remainder[0] <= 12'd0;
            quotient[0] <= 12'd0;
            divisor[0] <= 12'd1;
            saturated[0] <= 1'b0;
            payload[0] <= 37'd0;
        end else begin
            pipe_valid[0] <= sample_eligible && !cal_clear;
            raw_evidence_pipe[0]<=sample_raw_pressed;
            if (sample_eligible && !cal_clear) begin
                remainder[0] <= numerator[23:12];
                quotient[0] <= numerator[11:0];
                divisor[0] <= sample_span;
                saturated[0] <= (delta >= sample_span);
                payload[0] <= payload1;
            end
        end
    end

    genvar g;
    generate for (g = 0; g < 12; g = g + 1) begin : gen_divide
        wire [12:0] trial = {remainder[g], quotient[g][11]};
        // A single subtractor supplies both remainder and unsigned borrow.
        wire [13:0] difference={1'b0,trial}-{2'b0,divisor[g]};
        wire subtract=!difference[13];
        wire [12:0] reduced=difference[12:0];
        wire cancel = (command_ok && (cal_key_id == payload[g][36:31])) ||
                      (load_addressed && (load_key_id == payload[g][36:31]));
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                pipe_valid[g+1] <= 1'b0;raw_evidence_pipe[g+1]<=0;
                remainder[g+1] <= 12'd0;
                quotient[g+1] <= 12'd0;
                divisor[g+1] <= 12'd1;
                saturated[g+1] <= 1'b0;
                payload[g+1] <= 37'd0;
            end else begin
                pipe_valid[g+1] <= pipe_valid[g] && !cal_clear && !cancel;
                raw_evidence_pipe[g+1]<=raw_evidence_pipe[g];
                remainder[g+1] <= subtract ? reduced[11:0] : trial[11:0];
                quotient[g+1] <= {quotient[g][10:0], subtract};
                divisor[g+1] <= divisor[g];
                saturated[g+1] <= saturated[g];
                payload[g+1] <= payload[g];
            end
        end
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calibrated_valid <= 1'b0;
            calibrated_key_id <= 6'd0;
            calibrated_note_valid <= 1'b0;
            calibrated_note_sel <= 6'd0;
            key_travel <= 12'd0;raw_press_evidence<=0;
            calibrated_data <= 12'd0;
            calibrated_raw_data <= 12'd0;
        end else begin
            calibrated_valid <= 1'b0;
            calibrated_note_valid <= 1'b0;raw_press_evidence<=0;
            if (pipe_valid[12] && !cal_clear &&
                !(command_ok && cal_key_id == payload[12][36:31]) &&
                !(load_addressed && load_key_id == payload[12][36:31])) begin
                calibrated_valid <= 1'b1;
                {calibrated_key_id, calibrated_note_valid, calibrated_note_sel,
                 calibrated_data, calibrated_raw_data} <= payload[12];
                key_travel <= saturated[12] ? 12'hfff : quotient[12];
                raw_press_evidence<=raw_evidence_pipe[12];
            end
        end
    end

    reg [4:0] status_pipe [0:15];
    integer s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < 16; s = s + 1) status_pipe[s] <= 5'd0;
        end else begin
            status_pipe[0] <= {mapped_scan_done, mapped_tag_error, map_error};
            for (s = 1; s < 16; s = s + 1) status_pipe[s] <= status_pipe[s-1];
        end
    end
    assign {calibrated_scan_done, calibrated_tag_error, calibrated_map_error} = status_pipe[15];

endmodule
