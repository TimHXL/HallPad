`timescale 1ns / 1ps

// HallPad_V1.0_SCH_2026-09-22.pdf, ADC / Power&Connector pages.
// Three ADS7953SRHBR devices share CS(23), SCLK(24), SDI(25).
// Independent SDO(26): ADC_MISO_1=U36, ADC_MISO_2=U37, ADC_MISO_3=U38.
// ADC_PROFILE=0 retains that old schematic's CH0..13 scan.
// ADC_PROFILE=1 scans CH0..15 for the assembled board captured on 2026-10-15.
// This scanner retains chip/channel identity; filtering and key/axis mapping
// are selected by the SAME profile in the downstream modules.
// REFP=2.5 V, +VA=5 V, +VBD=3.3 V. Select the 0..2*VREF range.
//
// All registers use clk. ADC_SCLK is an output, not an internal clock.
// rst_n: asynchronous assertion; deassert synchronously to clk upstream.
// Release reset after ADC power/reference and the FPGA clock are stable.
// Standalone legacy defaults: clk=50 MHz, SCLK=2.5 MHz, startup wait=1 ms.
// The current keyboard_top overrides the divider to 50 (500 kHz) and profile 1.
// SCLK_HALF_CYCLES must be >=2; recheck external timing if clk changes.
//
// No ready/backpressure: consume a sample on EVERY clk with sample_valid=1.
// Three consecutive valid cycles carry chip 0, 1, 2, unless a tag is bad.
// Raw scan contains 42 samples in profile 0, or 48 samples in profile 1.
// tag_error is a one-clk pulse per lane; bad-tag samples are not emitted.
// scan_done marks the last channel emission, even if some tags were bad.
// It is a scan boundary, NOT a guarantee of 42/48 successfully received samples.
module adc_scan #(
    parameter integer SCLK_HALF_CYCLES = 10,
    parameter integer POWERUP_CYCLES   = 50000,
    // 0: original 2026-09-22 wiring; 1: Tim's running F407 HallPad wiring.
    parameter integer ADC_PROFILE      = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ADC_MISO_1,
    input  wire        ADC_MISO_2,
    input  wire        ADC_MISO_3,
    output reg         ADC_MOSI,
    output reg         ADC_SCLK,
    output reg         ADC_CS,
    output reg         sample_valid,
    output reg  [1:0]  sample_chip,
    output reg  [3:0]  sample_channel,
    output reg  [11:0] sample_data,
    output reg  [2:0]  tag_error,
    output reg         scan_done
);

    localparam integer HALF_W = (SCLK_HALF_CYCLES <= 1) ? 1 :
                                 $clog2(SCLK_HALF_CYCLES);
    localparam integer WAIT_N = (POWERUP_CYCLES < 1) ? 1 : POWERUP_CYCLES;
    localparam integer WAIT_W = (WAIT_N <= 1) ? 1 : $clog2(WAIT_N);

    localparam [2:0] ST_POWERUP = 3'd0,
                     ST_GAP     = 3'd1,
                     ST_RISE    = 3'd2,
                     ST_FALL    = 3'd3,
                     ST_HOLD    = 3'd4,
                     ST_EMIT    = 3'd5;

    // TI ADS7953 datasheet, Tables 5/6/7 and Figure 56:
    // Table 6: DI9..6 is the last channel. 9340 selects 13; 93C0 selects 15.
    // 3C40: enter Auto-2, update settings, restart at CH0, range=2*VREF,
    //       normal power, return channel tags instead of GPIO data.
    // 0000: continue Auto-2, increment normally (do not repeat 3C40).
    localparam [3:0] LAST_CHANNEL = (ADC_PROFILE == 1) ? 4'd15 : 4'd13;
    localparam [15:0] CMD_DEPTH = (ADC_PROFILE == 1) ? 16'h93C0 : 16'h9340;
    localparam [15:0] CMD_START    = 16'h3C40;
    localparam [15:0] CMD_CONTINUE = 16'h0000;

    reg [2:0]        state;
    reg [HALF_W-1:0] half_count;
    reg [WAIT_W-1:0] wait_count;
    reg [3:0]        bit_index;
    reg [15:0]       tx_word;
    reg [15:0]       rx0, rx1, rx2;
    reg [1:0]        startup_frame;
    reg [1:0]        emit_chip;
    reg [2:0]        lane_valid;
    reg [3:0]        expected_channel;

    wire [2:0] tag_match = {
        (rx2[15:12] == expected_channel),
        (rx1[15:12] == expected_channel),
        (rx0[15:12] == expected_channel)
    };

    reg [15:0] emit_word;
    always @(*) begin
        case (emit_chip)
            2'd0:    emit_word = rx0;
            2'd1:    emit_word = rx1;
            default: emit_word = rx2;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_POWERUP;
            half_count       <= 0;
            wait_count       <= 0;
            bit_index        <= 4'd15;
            tx_word          <= 16'd0;
            rx0              <= 16'd0;
            rx1              <= 16'd0;
            rx2              <= 16'd0;
            startup_frame    <= 2'd0;
            emit_chip        <= 2'd0;
            lane_valid       <= 3'd0;
            expected_channel <= 4'd0;
            ADC_MOSI         <= 1'b0;
            ADC_SCLK         <= 1'b0;
            ADC_CS           <= 1'b1;
            sample_valid     <= 1'b0;
            sample_chip      <= 2'd0;
            sample_channel   <= 4'd0;
            sample_data      <= 12'd0;
            tag_error        <= 3'd0;
            scan_done        <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            tag_error    <= 3'd0;
            scan_done    <= 1'b0;

            case (state)
                ST_POWERUP: begin
                    if (wait_count == WAIT_N - 1) begin
                        wait_count <= 0;
                        state      <= ST_GAP;
                    end else
                        wait_count <= wait_count + 1'b1;
                end

                ST_GAP: begin
                    if (half_count == SCLK_HALF_CYCLES - 1) begin
                        half_count <= 0;
                        bit_index  <= 4'd15;
                        rx0        <= 16'd0;
                        rx1        <= 16'd0;
                        rx2        <= 16'd0;
                        case (startup_frame)
                            2'd0: begin
                                tx_word  <= CMD_DEPTH;
                                ADC_MOSI <= CMD_DEPTH[15];
                            end
                            2'd1: begin
                                tx_word  <= CMD_START;
                                ADC_MOSI <= CMD_START[15];
                            end
                            default: begin
                                tx_word  <= CMD_CONTINUE;
                                ADC_MOSI <= CMD_CONTINUE[15];
                            end
                        endcase
                        ADC_CS <= 1'b0;
                        state  <= ST_RISE;
                    end else
                        half_count <= half_count + 1'b1;
                end

                ST_RISE: begin
                    if (half_count == SCLK_HALF_CYCLES - 1) begin
                        half_count <= 0;
                        ADC_SCLK   <= 1'b1;
                        // SDO has settled since CS falling / SCLK falling.
                        rx0 <= {rx0[14:0], ADC_MISO_1};
                        rx1 <= {rx1[14:0], ADC_MISO_2};
                        rx2 <= {rx2[14:0], ADC_MISO_3};
                        state <= ST_FALL;
                    end else
                        half_count <= half_count + 1'b1;
                end

                ST_FALL: begin
                    if (half_count == SCLK_HALF_CYCLES - 1) begin
                        half_count <= 0;
                        ADC_SCLK   <= 1'b0;
                        if (bit_index == 0) begin
                            // Keep CS low after the complete 16th clock.
                            state <= ST_HOLD;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            tx_word   <= {tx_word[14:0], 1'b0};
                            ADC_MOSI  <= tx_word[14];
                            state     <= ST_RISE;
                        end
                    end else
                        half_count <= half_count + 1'b1;
                end

                ST_HOLD: begin
                    if (half_count == SCLK_HALF_CYCLES - 1) begin
                        half_count <= 0;
                        ADC_CS     <= 1'b1;
                        ADC_MOSI   <= 1'b0;
                        // Keep the same frame spacing during initialization.
                        // At 50 MHz / DIV=2, acquisition time is 340 ns.
                        lane_valid <= (startup_frame == 2'd3) ? tag_match : 3'd0;
                        tag_error  <= (startup_frame == 2'd3) ? ~tag_match : 3'd0;
                        emit_chip  <= 2'd0;
                        state      <= ST_EMIT;
                    end else
                        half_count <= half_count + 1'b1;
                end

                ST_EMIT: begin
                    sample_valid   <= lane_valid[emit_chip];
                    sample_chip    <= emit_chip;
                    sample_channel <= emit_word[15:12];
                    sample_data    <= emit_word[11:0];
                    if (emit_chip == 2'd2) begin
                        if (startup_frame != 2'd3) begin
                            // Discard depth, start and one pipeline frame.
                            // First CH0 result is START frame + 2.
                            startup_frame <= startup_frame + 1'b1;
                        end else begin
                            scan_done <= (expected_channel == LAST_CHANNEL);
                            expected_channel <= (expected_channel == LAST_CHANNEL) ?
                                                4'd0 : expected_channel + 1'b1;
                        end
                        state <= ST_GAP;
                    end else
                        emit_chip <= emit_chip + 1'b1;
                end

                default: begin
                    state            <= ST_POWERUP;
                    half_count       <= 0;
                    wait_count       <= 0;
                    startup_frame    <= 0;
                    expected_channel <= 0;
                    ADC_CS           <= 1'b1;
                    ADC_SCLK         <= 1'b0;
                    ADC_MOSI         <= 1'b0;
                end
            endcase
        end
    end

endmodule
