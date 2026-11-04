`timescale 1ns / 1ps

// TLV320DAC3100 master-clocked, standard I2S, 16 bits/channel,
// exactly 32 BCLK periods per stereo frame. WCLK=0 means left.
// Both channels transmit the same held signed PCM sample.
//
// BCLK/WCLK enter through equal-depth two-flop synchronizers. A falling
// BCLK event is processed two extra clk cycles later, allowing WCLK to settle
// when the external master changes both pins at the same falling edge.
// No FPGA registers are clocked from the external audio pins. At the
// specified ~1.536 MHz BCLK, this leaves >200 ns before the next rising
// BCLK sampling edge. Board-level input/output delays still need signoff.
//
// I2S changes WCLK one bit BEFORE the next channel MSB. At a WCLK edge,
// transmit the previous channel LSB; the following falling edge sends MSB.
// sample_tick is one clk enable at a qualified LEFT WCLK boundary. The
// engine/bridge must use this SAME enable; pcm_in is captured BEFORE the
// engine calculates the new frame, yielding one frame of fixed latency.
// sample_tick continues while muted once external clocks are qualified.
//
// Unmute waits for a left boundary and TWO complete zero stereo frames.
// mute is an immediate digital zero gate and discards any partial frame.
// The codec must also remain analog-muted until audio_ready. Already
// sampled bits cannot be recalled; the interrupted frame is cancelled.
// Clock failure cancels readiness and latches clock_error. Deassert
// monitor_enable to clear the fault and restart qualification. This is
// intentional: restoration of pins alone must not resume the loudspeaker.
module i2s_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer CLOCK_TIMEOUT_CYCLES = CLK_HZ / 1000
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               monitor_enable,
    input  wire               mute,
    input  wire signed [15:0] pcm_in,
    input  wire               AUD_BCLK,
    input  wire               AUD_WCLK,
    output wire               AUD_DIN,
    output wire               sample_tick,
    output wire               audio_ready,
    output reg                clock_good,
    output reg                clock_error
);
    localparam integer TIMEOUT_W = (CLOCK_TIMEOUT_CYCLES < 2) ? 1 : $clog2(CLOCK_TIMEOUT_CYCLES + 1);
    (* syn_async_reg = "true" *) reg bclk_meta, bclk_sync;
    (* syn_async_reg = "true" *) reg wclk_meta, wclk_sync;
    reg bclk_previous;
    reg fall_detected;
    reg fall_pending;
    reg observed_ws;
    reg have_ws;
    reg [5:0] falls_since_ws;
    reg [2:0] qualified_halves;
    reg [TIMEOUT_W-1:0] watchdog;
    reg have_bclk_period;
    reg [4:0] bit_index;
    reg [15:0] frame_sample;
    reg serial_bit;
    reg [1:0] zero_frames;
    reg ready;

    wire ws_changed = (wclk_sync != observed_ws);
    wire half_valid = have_ws && (falls_since_ws == 6'd15);
    wire left_boundary = fall_pending && ws_changed && !wclk_sync && half_valid;
    // Nominal falling-edge interval is 32.552 system clocks. Allow sync
    // quantization/skew and modest jitter, but reject a wrong-rate codec.
    // watchdog is elapsed cycles minus one at the next falling-edge event.
    wire bad_bclk_rate = have_bclk_period && ((watchdog < 27) || (watchdog > 36));
    assign sample_tick = rst_n && monitor_enable && clock_good && !clock_error && !bad_bclk_rate && left_boundary;
    assign audio_ready = rst_n && monitor_enable && clock_good && !clock_error && !mute && ready;
    assign AUD_DIN = (rst_n && monitor_enable && clock_good && !clock_error && !mute) ? serial_bit : 1'b0;

    // synthesis translate_off
    initial begin
        if (CLK_HZ != 50000000 || CLOCK_TIMEOUT_CYCLES < 64) begin
            $display("FAIL i2s_tx requires 50 MHz and CLOCK_TIMEOUT_CYCLES >= 64");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_meta <= 1'b0;
            bclk_sync <= 1'b0;
            wclk_meta <= 1'b0;
            wclk_sync <= 1'b0;
            bclk_previous <= 1'b0;
            fall_detected <= 1'b0;
            fall_pending <= 1'b0;
        end else begin
            bclk_meta <= AUD_BCLK;
            bclk_sync <= bclk_meta;
            wclk_meta <= AUD_WCLK;
            wclk_sync <= wclk_meta;
            bclk_previous <= bclk_sync;
            fall_detected <= bclk_previous && !bclk_sync;
            fall_pending <= fall_detected;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            observed_ws <= 1'b0;
            have_ws <= 1'b0;
            falls_since_ws <= 6'd0;
            qualified_halves <= 3'd0;
            watchdog <= {TIMEOUT_W{1'b0}};
            have_bclk_period <= 1'b0;
            bit_index <= 5'd0;
            frame_sample <= 16'd0;
            serial_bit <= 1'b0;
            zero_frames <= 2'd0;
            ready <= 1'b0;
            clock_good <= 1'b0;
            clock_error <= 1'b0;
        end else if (!monitor_enable) begin
            observed_ws <= wclk_sync;
            have_ws <= 1'b0;
            falls_since_ws <= 6'd0;
            qualified_halves <= 3'd0;
            watchdog <= {TIMEOUT_W{1'b0}};
            have_bclk_period <= 1'b0;
            bit_index <= 5'd0;
            frame_sample <= 16'd0;
            serial_bit <= 1'b0;
            zero_frames <= 2'd0;
            ready <= 1'b0;
            clock_good <= 1'b0;
            clock_error <= 1'b0;
        end else if (clock_error) begin
            clock_good <= 1'b0;
            ready <= 1'b0;
            frame_sample <= 16'd0;
            serial_bit <= 1'b0;
            zero_frames <= 2'd0;
        end else begin
            if (mute || !clock_good) begin
                frame_sample <= 16'd0;
                serial_bit <= 1'b0;
                zero_frames <= 2'd0;
                ready <= 1'b0;
            end

            if (fall_pending) begin
                watchdog <= {TIMEOUT_W{1'b0}};
                have_bclk_period <= 1'b1;
                if (bad_bclk_rate) begin
                    clock_error <= 1'b1;
                    clock_good <= 1'b0;
                    ready <= 1'b0;
                    frame_sample <= 16'd0;
                    serial_bit <= 1'b0;
                    zero_frames <= 2'd0;
                end else if (ws_changed) begin
                    observed_ws <= wclk_sync;
                    have_ws <= 1'b1;
                    falls_since_ws <= 6'd0;
                    bit_index <= 5'd0;
                    if (have_ws && !half_valid) begin
                        clock_error <= 1'b1;
                        clock_good <= 1'b0;
                        ready <= 1'b0;
                        frame_sample <= 16'd0;
                        serial_bit <= 1'b0;
                        zero_frames <= 2'd0;
                    end else begin
                        if (half_valid && qualified_halves < 3'd4) begin
                            qualified_halves <= qualified_halves + 3'd1;
                            if (qualified_halves == 3'd3)
                                clock_good <= 1'b1;
                        end
                        serial_bit <= (!mute && ready && clock_good) ? frame_sample[0] : 1'b0;
                        if (!wclk_sync && half_valid && clock_good && !mute) begin
                            if (zero_frames == 2'd2) begin
                                frame_sample <= pcm_in;
                                ready <= 1'b1;
                            end else begin
                                zero_frames <= zero_frames + 2'd1;
                                frame_sample <= 16'd0;
                                ready <= 1'b0;
                            end
                        end
                    end
                end else if ((have_ws && falls_since_ws >= 6'd15) ||
                             (!have_ws && falls_since_ws >= 6'd31)) begin
                    // Missing WCLK edge, including WCLK stuck with live BCLK.
                    clock_error <= 1'b1;
                    clock_good <= 1'b0;
                    ready <= 1'b0;
                    frame_sample <= 16'd0;
                    serial_bit <= 1'b0;
                    zero_frames <= 2'd0;
                end else begin
                    falls_since_ws <= falls_since_ws + 6'd1;
                    if (bit_index < 5'd15) begin
                        serial_bit <= (!mute && ready && clock_good) ? frame_sample[15 - bit_index] : 1'b0;
                        bit_index <= bit_index + 5'd1;
                    end else begin
                        serial_bit <= 1'b0;
                    end
                end
            end else if (watchdog == CLOCK_TIMEOUT_CYCLES - 1) begin
                clock_error <= 1'b1;
                clock_good <= 1'b0;
                ready <= 1'b0;
                frame_sample <= 16'd0;
                serial_bit <= 1'b0;
                zero_frames <= 2'd0;
            end else begin
                watchdog <= watchdog + 1'b1;
            end
        end
    end

endmodule
