`timescale 1ns / 1ps

// 35 Hall inputs and two joystick axes. Select ADC_PROFILE consistently in
// the scanner, this filter and key_channel_map. Profile 1 uses U38 CH1/CH0
// for X/Y; profile 0 retains the old schematic's U38 CH7/CH8 mapping.
// Connect sample_*, scan_done and tag_error directly to adc_scan, with the
// same clk/rst_n. Consume EVERY valid clk; no ready/backpressure is needed.
// Each retained sample produces one registered output (three clks after the
// scanner's output). Identity, raw value and filtered value stay together.
// scan_done/tag_error are independently delayed, including on invalid cycles.
//
// IIR: y += round((x - y) / 2^SHIFT), with independent Q12.8 state per input.
// SHIFT is an elaboration parameter in 0..8; 0 gives unity gain / no smoothing.
// Defaults: Hall alpha=1/4, joystick alpha=1/16. Tune on the actual board.
// First sample after reset seeds its own state, so startup does not ramp from 0.
// bypass is synchronous to clk: output raw AND track raw in that channel's
// state, so re-enabling filtering continues from the last bypassed sample.
// Deassert rst_n synchronously upstream, as for adc_scan.
//
// Grounded/unused channels are dropped. ADC chip/channel identity is preserved;
// key calibration, press/release hysteresis and note mapping belong downstream.
module adc_data_filter #(
    parameter integer HALL_IIR_SHIFT     = 2,
    parameter integer JOYSTICK_IIR_SHIFT = 4,
    parameter integer ADC_PROFILE = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire        sample_valid,
    input  wire [1:0]  sample_chip,
    input  wire [3:0]  sample_channel,
    input  wire [11:0] sample_data,
    input  wire        scan_done,
    input  wire [2:0]  tag_error,
    output reg         filtered_valid,
    output reg  [1:0]  filtered_chip,
    output reg  [3:0]  filtered_channel,
    output reg  [11:0] filtered_data,
    output reg  [11:0] filtered_raw_data,
    output reg         filtered_is_joystick,
    output reg         filtered_scan_done,
    output reg  [2:0]  filtered_tag_error
);

    localparam integer SENSOR_COUNT = 37;

    // Profile 0: U36=0..13, U37=14..27, U38=28..36.
    // Profile 1: U36=0..14, U37=15..29, U38 Hall=30..34, X/Y=35/36.
    // These are storage addresses, not physical-key or note numbers.
    (* syn_ramstyle="distributed_ram" *) reg [19:0] history [0:SENSOR_COUNT-1];
    reg [SENSOR_COUNT-1:0] initialized;
    reg       is_sensor;
    reg       is_joystick;
    reg [5:0] channel_index;

    always @(*) begin
        is_sensor    = 1'b0;
        is_joystick  = 1'b0;
        channel_index = 6'd0;
        if (ADC_PROFILE == 1) begin
            // F407 profile: retain 30 Hall channels on U36/U37, five Hall
            // channels on U38, then X/Y. Other ADC inputs are diagnostics.
            case (sample_chip)
                2'd0: if (sample_channel <= 4'd14) begin
                    is_sensor = 1'b1;
                    channel_index = {2'b00, sample_channel};
                end
                2'd1: if (sample_channel <= 4'd14) begin
                    is_sensor = 1'b1;
                    channel_index = 6'd15 + {2'b00, sample_channel};
                end
                2'd2: begin
                    if (sample_channel >= 4'd4 && sample_channel <= 4'd8) begin
                        is_sensor = 1'b1;
                        channel_index = 6'd30 + {2'b00, sample_channel} - 6'd4;
                    end else if (sample_channel <= 4'd1) begin
                        is_sensor = 1'b1;
                        is_joystick = 1'b1;
                        channel_index = (sample_channel == 4'd1) ? 6'd35 : 6'd36;
                    end
                end
                default: begin end
            endcase
        end else begin
        case (sample_chip)
            2'd0: if (sample_channel <= 4'd13) begin
                is_sensor = 1'b1;
                channel_index = {2'b00, sample_channel};
            end
            2'd1: if (sample_channel <= 4'd13) begin
                is_sensor = 1'b1;
                channel_index = 6'd14 + {2'b00, sample_channel};
            end
            2'd2: if (sample_channel <= 4'd8) begin
                is_sensor = 1'b1;
                is_joystick = (sample_channel >= 4'd7);
                channel_index = 6'd28 + {2'b00, sample_channel};
            end
            default: begin end
        endcase
        end
    end

    // Register the channel decode separately from the 20-bit IIR feedback.
    // Throughput remains one sample per clk, including repeated channels.
    // Keep raw data, bypass and independent scan/tag status on the same stage.
    reg queued_valid,queued_bypass,queued_sensor,queued_joystick;
    reg [5:0] queued_index;
    reg [1:0] queued_chip;
    reg [3:0] queued_channel;
    reg [11:0] queued_data;
    reg queued_scan_done;
    reg [2:0] queued_tag_error;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            queued_valid<=0;queued_bypass<=0;queued_sensor<=0;queued_joystick<=0;
            queued_index<=0;queued_chip<=0;queued_channel<=0;queued_data<=0;
            queued_scan_done<=0;queued_tag_error<=0;
        end else begin
            queued_valid<=sample_valid;queued_bypass<=bypass;
            queued_sensor<=is_sensor;queued_joystick<=is_joystick;queued_index<=channel_index;
            queued_chip<=sample_chip;queued_channel<=sample_channel;queued_data<=sample_data;
            queued_scan_done<=scan_done;queued_tag_error<=tag_error;
        end
    end

    // Signed floor plus a tie bit is exactly symmetric round-to-nearest,
    // ties away from zero. This removes the absolute-value/negation carry chains.
    reg signed [20:0] delta,shifted_delta;
    reg round_up;
    reg [19:0] next_history;
    localparam [20:0] HALL_LOW_MASK=(21'd1 << (HALL_IIR_SHIFT>0 ? HALL_IIR_SHIFT-1:0))-1;
    localparam [20:0] JOY_LOW_MASK=(21'd1 << (JOYSTICK_IIR_SHIFT>0 ? JOYSTICK_IIR_SHIFT-1:0))-1;
    always @*begin
        delta=0;shifted_delta=0;round_up=0;next_history={queued_data,8'd0};
        if(queued_valid && queued_sensor && initialized[queued_index] && !queued_bypass)begin
            delta=$signed({1'b0,queued_data,8'd0})-$signed({1'b0,history[queued_index]});
            if(queued_joystick)begin
                shifted_delta=delta>>>JOYSTICK_IIR_SHIFT;
                if(JOYSTICK_IIR_SHIFT>0)
                    round_up=((delta>>(JOYSTICK_IIR_SHIFT>0 ? JOYSTICK_IIR_SHIFT-1:0))&1) &&
                        (!delta[20] || (delta&JOY_LOW_MASK)!=0);
            end else begin
                shifted_delta=delta>>>HALL_IIR_SHIFT;
                if(HALL_IIR_SHIFT>0)
                    round_up=((delta>>(HALL_IIR_SHIFT>0 ? HALL_IIR_SHIFT-1:0))&1) &&
                        (!delta[20] || (delta&HALL_LOW_MASK)!=0);
            end
            next_history=history[queued_index]+shifted_delta[19:0]+{{19{1'b0}},round_up};
        end
    end
    // Valid bits own reset semantics: unread history never reaches a result.
    // Avoiding a reset mux on every word permits distributed-memory inference.
    always @(posedge clk)if(rst_n && queued_valid && queued_sensor)
        history[queued_index]<=next_history;

    // Separate the 12-bit output rounding carry from the IIR feedback.
    // History still commits every clk, so repeated-channel samples need no stall.
    reg result_valid,result_is_joystick,result_scan_done;
    reg [1:0] result_chip;
    reg [3:0] result_channel;
    reg [11:0] result_raw_data;
    reg [19:0] result_history;
    reg [2:0] result_tag_error;
    wire [20:0] result_rounded={1'b0,result_history}+21'd128;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            initialized          <= {SENSOR_COUNT{1'b0}};
            result_valid       <= 1'b0;
            result_chip        <= 2'd0;
            result_channel     <= 4'd0;
            result_history     <= 20'd0;
            result_raw_data    <= 12'd0;
            result_is_joystick <= 1'b0;
            result_scan_done   <= 1'b0;
            result_tag_error   <= 3'd0;
        end else begin
            result_valid     <= 1'b0;
            // Do not gate these with queued_valid or queued_sensor: queued_scan_done
            // normally coincides with a discarded U38 CH13 sample, and can
            // also arrive when that ADC lane has a bad tag and no sample.
            result_scan_done <= queued_scan_done;
            result_tag_error <= queued_tag_error;

            if (queued_valid && queued_sensor) begin
                initialized[queued_index] <= 1'b1;
                result_valid             <= 1'b1;
                result_chip              <= queued_chip;
                result_channel           <= queued_channel;
                result_history           <= next_history;
                result_raw_data          <= queued_data;
                result_is_joystick       <= queued_joystick;
            end
            // Data/identity hold when invalid; only result_valid qualifies
            // them. Consecutive accesses to the same channel are supported.
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            filtered_valid<=0;filtered_chip<=0;filtered_channel<=0;
            filtered_data<=0;filtered_raw_data<=0;filtered_is_joystick<=0;
            filtered_scan_done<=0;filtered_tag_error<=0;
        end else begin
            filtered_valid<=result_valid;
            filtered_scan_done<=result_scan_done;filtered_tag_error<=result_tag_error;
            if(result_valid)begin
                filtered_chip<=result_chip;filtered_channel<=result_channel;
                filtered_data<=result_rounded[19:8];filtered_raw_data<=result_raw_data;
                filtered_is_joystick<=result_is_joystick;
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (HALL_IIR_SHIFT < 0 || HALL_IIR_SHIFT > 8 ||
            JOYSTICK_IIR_SHIFT < 0 || JOYSTICK_IIR_SHIFT > 8) begin
            $display("ERROR adc_data_filter: IIR shifts must be in 0..8");
            $finish;
        end
    end
    // synthesis translate_on

endmodule
