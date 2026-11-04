`timescale 1ns / 1ps

// HallPad V1.0: adc_data_top -> key_channel_map -> key_calibrate/key_event.
// Connect all filtered_* ports directly, using the same clk/rst_n.
// Accept EVERY filtered_valid clock, including consecutive valid clocks.
// Outputs are registered: one extra clk after adc_data_top, no backpressure.
// Key payload holds while key_valid=0; joystick payload holds while
// joystick_valid=0. key_note_valid qualifies note_sel within a key sample.
// Status is delayed independently.
// Assert reset asynchronously; deassert synchronously upstream.
//
// key_id is a ZERO-BASED sensor identity, NOT a note or voice number.
// ADC_PROFILE=1 follows the captured board/F407 hall_map in 5x7 key order:
//   U36/U37 CH0..14 supply columns 1..3 / 4..6; U38 CH8..4 column 7.
//   U38 CH1/CH0 are X/Y. CH2/3 and all other unused inputs are not keys.
// ADC_PROFILE=0 retains the legacy schematic assignment below:
//   U36/chip0 CH0..13 -> key_id  0..13 -> HALL_1_1..7, HALL_2_1..7
//   U37/chip1 CH0..13 -> key_id 14..27 -> HALL_3_1..7, HALL_4_1..7
//   U38/chip2 CH0..6  -> key_id 28..34 -> HALL_5_1..7
//   U38 CH7/CH8 -> joystick X/Y; unused channels/chip3 are rejected.
// Profile 0 follows the old PDF; profile 1 follows the assembled-board capture.
// Sensor row/column labels still need mechanical orientation verification.
// The default musical layout was
// assigned for playing on the 5x7 grid, not inferred from electrical wiring.
// Viewing convention: HALL_1_* is the TOP row, HALL_5_* the BOTTOM row;
// column 1 is LEFT. Verify this orientation against the assembled instrument.
// Sensor columns are mirrored musically to match the F407 assembled board.
// Increasing physical playing columns follows C D E F G A B.
// Sensor column 1..7 now maps B..C within each octave:
//   HALL_1: B6 A6 G6 F6 E6 D6 C6
//   HALL_2: B5 A5 G5 F5 E5 D5 C5
//   HALL_3: B4 A4 G4 F4 E4 D4 C4
//   HALL_4: B3 A3 G3 F3 E3 D3 C3
//   HALL_5: B2 A2 G2 F2 E2 D2 C2
//
// KEY_NOTE_MAP is a compile-time table: key_id k uses bits [6*k +: 6].
// In a concatenation, put key34 on the LEFT and key0 on the RIGHT.
//   1..35: C2..B6 natural notes (20=A4); key_note_valid=1 for this Hall sample.
//   0: unassigned, key_note_valid=0, note_sel=0; retain the Hall sample.
//   36..63: invalid, suppress the note as above AND assert map_error.
// Override this parameter to change key layout; 210'd0 disables all notes
// while retaining Hall samples for calibration/debug.
// Downstream note/event generation must require key_valid && key_note_valid.
// key_valid alone still supplies calibration/debug data before mapping.
// note_sel=0 is reserved for silence, NEVER an ordinary key-release command.
// This module does not detect key presses/releases, calibrate, or allocate voices.
module key_channel_map #(
    parameter [209:0] KEY_NOTE_MAP = {
        // Per-row musical mirror matches F407 Audio_Update; sensor IDs stay fixed.
        6'd1, 6'd2, 6'd3, 6'd4, 6'd5, 6'd6, 6'd7,
        6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13, 6'd14,
        6'd15, 6'd16, 6'd17, 6'd18, 6'd19, 6'd20, 6'd21,
        6'd22, 6'd23, 6'd24, 6'd25, 6'd26, 6'd27, 6'd28,
        6'd29, 6'd30, 6'd31, 6'd32, 6'd33, 6'd34, 6'd35
    },
    parameter integer ADC_PROFILE = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        filtered_valid,
    input  wire [1:0]  filtered_chip,
    input  wire [3:0]  filtered_channel,
    input  wire [11:0] filtered_data,
    input  wire [11:0] filtered_raw_data,
    input  wire        filtered_is_joystick,
    input  wire        filtered_scan_done,
    input  wire [2:0]  filtered_tag_error,

    output reg         key_valid,
    output reg  [5:0]  key_id,
    output reg         key_note_valid,
    output reg  [5:0]  note_sel,
    output reg  [11:0] key_data,
    output reg  [11:0] key_raw_data,

    output reg         joystick_valid,
    output reg         joystick_axis,
    output reg  [11:0] joystick_data,
    output reg  [11:0] joystick_raw_data,

    output reg         mapped_scan_done,
    output reg  [2:0]  mapped_tag_error,
    output reg         map_error
);

    reg       is_hall;
    reg       is_joystick;
    reg       axis;
    reg [5:0] sensor_id;
    reg [5:0] mapped_note;

    always @(*) begin
        is_hall     = 1'b0;
        is_joystick = 1'b0;
        axis        = 1'b0;
        sensor_id   = 6'd0;
        mapped_note = 6'd0;

        if (ADC_PROFILE == 1) begin
            // Firmware/Core/Src/ads7953.c hall_map, ordered by physical row.
            case (filtered_chip)
                2'd0, 2'd1: begin
                    if (filtered_channel >= 4'd10 && filtered_channel <= 4'd14) begin
                        is_hall = 1'b1;
                        sensor_id = (6'd14 - {2'b00, filtered_channel}) * 6'd7;
                    end else if (filtered_channel >= 4'd5 && filtered_channel <= 4'd9) begin
                        is_hall = 1'b1;
                        sensor_id = ({2'b00, filtered_channel} - 6'd5) * 6'd7 + 6'd1;
                    end else if (filtered_channel <= 4'd4) begin
                        is_hall = 1'b1;
                        sensor_id = {2'b00, filtered_channel} * 6'd7 + 6'd2;
                    end
                    if (is_hall && filtered_chip == 2'd1)
                        sensor_id = sensor_id + 6'd3;
                end
                2'd2: begin
                    if (filtered_channel >= 4'd4 && filtered_channel <= 4'd8) begin
                        is_hall = 1'b1;
                        sensor_id = (6'd8 - {2'b00, filtered_channel}) * 6'd7 + 6'd6;
                    end else if (filtered_channel <= 4'd1) begin
                        is_joystick = 1'b1;
                        axis = (filtered_channel == 4'd0); // CH1=X, CH0=Y
                    end
                end
                default: begin end
            endcase
        end else begin
        case (filtered_chip)
            2'd0: if (filtered_channel <= 4'd13) begin
                is_hall   = 1'b1;
                sensor_id = {2'b00, filtered_channel};
            end
            2'd1: if (filtered_channel <= 4'd13) begin
                is_hall   = 1'b1;
                sensor_id = 6'd14 + {2'b00, filtered_channel};
            end
            2'd2: begin
                if (filtered_channel <= 4'd6) begin
                    is_hall   = 1'b1;
                    sensor_id = 6'd28 + {2'b00, filtered_channel};
                end else if (filtered_channel == 4'd7) begin
                    is_joystick = 1'b1;
                    axis        = 1'b0; // ADC_X
                end else if (filtered_channel == 4'd8) begin
                    is_joystick = 1'b1;
                    axis        = 1'b1; // ADC_Y
                end
            end
            default: begin end
        endcase
        end

        // Only legal Hall identities can index the 35-entry constant table.
        if (is_hall)
            mapped_note = KEY_NOTE_MAP[sensor_id * 6 +: 6];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_valid         <= 1'b0;
            key_id            <= 6'd0;
            key_note_valid    <= 1'b0;
            note_sel          <= 6'd0;
            key_data          <= 12'd0;
            key_raw_data      <= 12'd0;
            joystick_valid    <= 1'b0;
            joystick_axis     <= 1'b0;
            joystick_data     <= 12'd0;
            joystick_raw_data <= 12'd0;
            mapped_scan_done  <= 1'b0;
            mapped_tag_error  <= 3'd0;
            map_error         <= 1'b0;
        end else begin
            key_valid      <= 1'b0;
            key_note_valid <= 1'b0;
            joystick_valid <= 1'b0;
            map_error      <= 1'b0;

            // A boundary may have no sample (e.g. discarded U38 CH13).
            // Tag errors may accompany another lane's good sample. Neither
            // status suppresses a valid sample or fabricates a key release.
            mapped_scan_done <= filtered_scan_done;
            mapped_tag_error <= filtered_tag_error;

            if (filtered_valid) begin
                // Address is authoritative; cross-check the filter's type
                // flag so miswired sidebands cannot turn joystick into keys.
                if (is_hall && !filtered_is_joystick) begin
                    key_valid    <= 1'b1;
                    key_id       <= sensor_id;
                    key_data     <= filtered_data;
                    key_raw_data <= filtered_raw_data;
                    if (mapped_note >= 6'd1 && mapped_note <= 6'd35) begin
                        key_note_valid <= 1'b1;
                        note_sel       <= mapped_note;
                    end else begin
                        note_sel  <= 6'd0;
                        // Unassigned (0) is a supported configuration.
                        // Bad notes must not discard valid calibration data.
                        map_error <= (mapped_note != 6'd0);
                    end
                end else if (is_joystick && filtered_is_joystick) begin
                    joystick_valid    <= 1'b1;
                    joystick_axis     <= axis;
                    joystick_data     <= filtered_data;
                    joystick_raw_data <= filtered_raw_data;
                end else begin
                    // Invalid address or inconsistent type. Payloads hold.
                    map_error <= 1'b1;
                end
            end
        end
    end


endmodule
