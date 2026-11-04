`timescale 1ns / 1ps

// Persistent color-change ripples for the 35-key, 5-row by 7-column keyboard.
// key_id = row * 7 + column; LED n occupies pixels_rgb[24*n +: 24] as RRGGBB.
// The board's existing serial LED transmitter handles RGB-to-GRB conversion.
//
// Each enabled NOTE_ON changes its center immediately and schedules an outward
// wave. Ring = ceil(sqrt(dr*dr + dc*dc)), 0..8. Existing waves keep progressing:
// a new press never restarts the shared STEP_CYCLES clock. A pixel keeps earlier
// pending arrivals, then takes the new wave's color; older arrivals at or after
// the new arrival are discarded so stale colors cannot overwrite the new wave.
//
// NOTE_ON events in a fixed CHORD_CYCLES window share one palette color, so keys
// scanned a few clocks apart form one multi-center chord ripple. The first ON
// opens the window and advances the palette; later ONs do not extend it. An ON
// exactly CHORD_CYCLES clocks after the first starts a new group. CHORD_CYCLES=1
// gives every ON a new color. The default window is 20 ms at 50 MHz.
//
// The first wave after idle gets a full STEP_CYCLES interval before ring 1.
// Waves added while running use the existing phase: their first ring is due
// on the next shared tick (1..STEP_CYCLES clocks later), then one ring per tick.
// A tick consumes old arrivals before scheduling a simultaneous new NOTE_ON;
// a new center wins over an old arrival on that clock. NOTE_OFF/invalid IDs do
// nothing. enable=0 blocks NEW events but lets accepted waves finish at the
// same cadence. Audio/ADC recovery must not erase partial waves and leave
// permanent islands of old color. Only rst_n resets the animation state.
// Reset restores INITIAL_COLOR on every pixel.
module keyboard_ripple #(
    parameter [7:0] BRIGHTNESS = 8'd32,
    parameter [2:0] INITIAL_COLOR = 3'd0,
    parameter integer STEP_CYCLES = 3500000,
    parameter integer CHORD_CYCLES = 1000000,
    parameter integer RUNTIME_SPEED = 0
) (
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire event_valid,
    input wire event_on,
    input wire [5:0] event_key_id,
    output wire [839:0] pixels_rgb,
    output wire [104:0] palette_indices,
    // Optional App control: speed is milli-cells/second, ms_tick is 1 kHz.
    // Legacy callers leave RUNTIME_SPEED=0 for exact STEP_CYCLES timing.
    input wire ms_tick,
    input wire [14:0] speed,
    output wire [34:0] arrivals
);
    function integer counter_width;
        input integer cycles;
        integer remaining;
        begin
            remaining = cycles - 1;
            counter_width = 0;
            while (remaining > 0) begin
                counter_width = counter_width + 1;
                remaining = remaining >> 1;
            end
            if (counter_width < 1) counter_width = 1;
        end
    endfunction

    localparam integer COUNT_WIDTH = counter_width(STEP_CYCLES);
    localparam [COUNT_WIDTH-1:0] STEP_LAST = STEP_CYCLES - 1;
    localparam integer CHORD_COUNT_WIDTH = counter_width(CHORD_CYCLES);
    localparam [CHORD_COUNT_WIDTH-1:0] CHORD_LAST = CHORD_CYCLES - 1;

    // This function is evaluated only for constant palette entries. Thus the
    // multiplier/divider are folded at elaboration rather than built in RTL.
    // Floor division gives BRIGHTNESS=0 fully off and 255 the exact full color.
    function [7:0] scale_channel;
        input [7:0] channel;
        reg [15:0] product;
        begin
            product = channel * BRIGHTNESS;
            scale_channel = product / 16'd255;
        end
    endfunction

    localparam [23:0] COLOR_BLUE   = {8'd0, 8'd0, scale_channel(8'd255)};
    localparam [23:0] COLOR_CYAN   = {8'd0, scale_channel(8'd255), scale_channel(8'd255)};
    localparam [23:0] COLOR_GREEN  = {8'd0, scale_channel(8'd255), 8'd0};
    localparam [23:0] COLOR_YELLOW = {scale_channel(8'd255), scale_channel(8'd255), 8'd0};
    localparam [23:0] COLOR_ORANGE = {scale_channel(8'd255), scale_channel(8'd128), 8'd0};
    localparam [23:0] COLOR_RED    = {scale_channel(8'd255), 8'd0, 8'd0};
    localparam [23:0] COLOR_PURPLE = {scale_channel(8'd128), 8'd0, scale_channel(8'd255)};
    localparam [23:0] COLOR_PINK   = {scale_channel(8'd255), 8'd0, scale_channel(8'd128)};

    function [23:0] palette_rgb;
        input [2:0] color_index;
        begin
            case (color_index)
                3'd0: palette_rgb = COLOR_BLUE;   // 0000FF before scaling.
                3'd1: palette_rgb = COLOR_CYAN;   // 00FFFF.
                3'd2: palette_rgb = COLOR_GREEN;  // 00FF00.
                3'd3: palette_rgb = COLOR_YELLOW; // FFFF00.
                3'd4: palette_rgb = COLOR_ORANGE; // FF8000.
                3'd5: palette_rgb = COLOR_RED;    // FF0000.
                3'd6: palette_rgb = COLOR_PURPLE; // 8000FF.
                3'd7: palette_rgb = COLOR_PINK;   // FF0080.
                default: palette_rgb = COLOR_BLUE;
            endcase
        end
    endfunction

    // Build one constant, 35-entry ring lookup for a fixed destination LED.
    // All row/column division and distance arithmetic run at elaboration.
    // Across the 35 LEDs this is 4900 constant bits, not 35 run-time dividers
    // or square-root units. Synthesis may optimize the symmetric lookup logic.
    function [139:0] rings_for_led;
        input integer led_index;
        integer center;
        integer dr;
        integer dc;
        integer distance_squared;
        integer radius;
        integer ring;
        begin
            rings_for_led = 140'd0;
            for (center = 0; center < 35; center = center + 1) begin
                dr = (center / 7) - (led_index / 7);
                dc = (center % 7) - (led_index % 7);
                distance_squared = dr * dr + dc * dc;
                ring = 0;
                for (radius = 0; radius < 8; radius = radius + 1) begin
                    if (distance_squared > radius * radius) ring = ring + 1;
                end
                rings_for_led[center*4 +: 4] = ring[3:0];
            end
        end
    endfunction

    // synthesis translate_off
    initial begin
        if (STEP_CYCLES < 1) begin
            $display("FAIL keyboard_ripple STEP_CYCLES must be at least 1");
            $finish;
        end
        if (CHORD_CYCLES < 1) begin
            $display("FAIL keyboard_ripple CHORD_CYCLES must be at least 1");
            $finish;
        end
    end
    // synthesis translate_on

    reg [2:0] current_color;
    reg wave_active;
    reg [3:0] drain_remaining;
    reg [COUNT_WIDTH-1:0] step_count;
    reg chord_active;
    reg [CHORD_COUNT_WIDTH-1:0] chord_count;
    reg [19:0] speed_phase;
    wire [14:0] bounded_speed = speed < 15'd500 ? 15'd500 :
                               speed > 15'd30000 ? 15'd30000 : speed;
    wire [20:0] speed_sum = {1'b0,speed_phase} + {6'd0,bounded_speed};
    wire [20:0] speed_remainder = speed_sum - 21'd1000000;

    wire new_press = enable && event_valid && event_on && (event_key_id < 6'd35);
    wire [2:0] next_color = current_color + 3'd1;
    wire start_chord = new_press &&
                       (!chord_active || (chord_count == CHORD_LAST));
    wire [2:0] press_color = start_chord ? next_color : current_color;
    wire step_due = wave_active && (RUNTIME_SPEED != 0 ?
                    (ms_tick && speed_sum >= 21'd1000000) :
                    (step_count == STEP_LAST));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_color <= INITIAL_COLOR;
            wave_active <= 1'b0;
            drain_remaining <= 4'd0;
            step_count <= {COUNT_WIDTH{1'b0}};
            chord_active <= 1'b0;
            chord_count <= {CHORD_COUNT_WIDTH{1'b0}};
            speed_phase <= 20'd0;
        end else begin
            if (start_chord) begin
                current_color <= next_color;
                chord_active <= 1'b1;
                chord_count <= {CHORD_COUNT_WIDTH{1'b0}};
            end else if (chord_active) begin
                if (chord_count == CHORD_LAST) begin
                    chord_active <= 1'b0;
                end else begin
                    chord_count <= chord_count + 1'b1;
                end
            end

            // Keep one phase while any scheduled arrivals remain. New events
            // extend the drain period without postponing the next ring tick.
            // Fractional integration avoids run-time division and keeps phase
            // during live edits or rapid notes. Idle starts from zero phase.
            if (RUNTIME_SPEED != 0 && wave_active && ms_tick) begin
                speed_phase <= step_due ? speed_remainder[19:0] : speed_sum[19:0];
            end else if (!wave_active) begin
                speed_phase <= 20'd0;
            end
            if (RUNTIME_SPEED == 0 && wave_active && !step_due) begin
                step_count <= step_count + 1'b1;
            end else begin
                step_count <= {COUNT_WIDTH{1'b0}};
            end
            if (new_press) begin
                wave_active <= 1'b1;
                drain_remaining <= 4'd8;
            end else if (step_due) begin
                if (drain_remaining == 4'd1) begin
                    wave_active <= 1'b0;
                    drain_remaining <= 4'd0;
                end else begin
                    drain_remaining <= drain_remaining - 1'b1;
                end
            end
        end
    end

    genvar led;
    generate
        for (led = 0; led < 35; led = led + 1) begin : g_pixel
            localparam [139:0] RINGS = rings_for_led(led);
            localparam [5:0] KEY_ID = led;
            reg [2:0] color_index;
            reg [7:0] pending_valid;
            reg [23:0] pending_colors;
            reg [7:0] next_pending_valid;
            reg [23:0] next_pending_colors;
            integer bucket;
            wire [3:0] distance_ring = RINGS[event_key_id*4 +: 4];

            assign pixels_rgb[led*24 +: 24] = palette_rgb(color_index);
            assign palette_indices[led*3 +:3]=color_index;
            // Same edge as the color write. A fresh arrival cancels a fade
            // worker that may have read this pixel's previous state.
            assign arrivals[led] = (new_press && event_key_id == KEY_ID) ||
                                   (step_due && pending_valid[0]);

            // Bucket n arrives after n+1 shared ticks. Shift old entries first,
            // so an ON coincident with a tick schedules against the new phase.
            // All eight comparisons below have constant bucket indices after
            // elaboration; no dynamic distance arithmetic is implemented.
            always @(*) begin
                next_pending_valid = pending_valid;
                next_pending_colors = pending_colors;
                if (step_due) begin
                    next_pending_valid = {1'b0, pending_valid[7:1]};
                    next_pending_colors = {3'd0, pending_colors[23:3]};
                end
                if (new_press) begin
                    if (event_key_id == KEY_ID) begin
                        next_pending_valid = 8'd0;
                        next_pending_colors = 24'd0;
                    end else begin
                        for (bucket = 0; bucket < 8; bucket = bucket + 1) begin
                            if (distance_ring == bucket + 1) begin
                                next_pending_valid[bucket] = 1'b1;
                                next_pending_colors[bucket*3 +: 3] = press_color;
                            end else if (distance_ring < bucket + 1) begin
                                next_pending_valid[bucket] = 1'b0;
                                next_pending_colors[bucket*3 +: 3] = 3'd0;
                            end
                        end
                    end
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    color_index <= INITIAL_COLOR;
                    pending_valid <= 8'd0;
                    pending_colors <= 24'd0;
                end else begin
                    pending_valid <= next_pending_valid;
                    pending_colors <= next_pending_colors;
                    if (new_press && (event_key_id == KEY_ID)) begin
                        color_index <= press_color;
                    end else if (step_due && pending_valid[0]) begin
                        color_index <= pending_colors[2:0];
                    end
                end
            end
        end
    endgenerate

endmodule
