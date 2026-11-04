`timescale 1ns / 1ps

// A/B and the active-low switch are synchronized and debounced before use.
// Positive quadrature: {A,B} = 00 -> 01 -> 11 -> 10 -> 00.
// REVERSE changes reported direction, not the decoder's residual accounting.
// A complete detent emits one pulse; reversing cancels incomplete movement.
// A switch already held at reset must first be released to arm press events.
module rotary_encoder #(
    parameter integer AB_STABLE_CYCLES = 5000,
    parameter integer SW_STABLE_CYCLES = 500000,
    parameter integer EDGES_PER_STEP = 4,
    parameter integer REVERSE = 0,
    parameter integer LONG_PRESS_CYCLES = 100000000
) (
    input wire clk, rst_n,
    input wire enc_a, enc_b, enc_sw_n,
    output reg step_valid,
    output reg step_up,
    output reg short_press,
    output reg long_press,
    output reg [15:0] invalid_count
);
    wire [1:0] ab;
    wire sw_n, ab_ready, sw_ready;
    sampling_debounce #(.WIDTH(2), .STABLE_CYCLES(AB_STABLE_CYCLES)) u_ab (
        .clk(clk), .rst_n(rst_n), .pins({enc_a, enc_b}),
        .level(ab), .ready(ab_ready)
    );
    sampling_debounce #(.STABLE_CYCLES(SW_STABLE_CYCLES)) u_sw (
        .clk(clk), .rst_n(rst_n), .pins(enc_sw_n),
        .level(sw_n), .ready(sw_ready)
    );

    localparam integer HW = (LONG_PRESS_CYCLES < 2) ? 1 : $clog2(LONG_PRESS_CYCLES);
    localparam [HW-1:0] HOLD_LAST = LONG_PRESS_CYCLES - 1;
    localparam signed [3:0] STEP_LIMIT = EDGES_PER_STEP;
    localparam signed [3:0] NEGATIVE_LIMIT = -EDGES_PER_STEP;
    reg have_ab, have_sw, sw_armed, press_active, long_sent;
    reg [1:0] previous_ab;
    reg signed [3:0] residual, edge_delta;
    wire signed [3:0] next_residual = residual + edge_delta;
    reg [HW-1:0] hold_count;

    always @* begin
        edge_delta = 4'sd0;
        case ({previous_ab, ab})
            4'b0001, 4'b0111, 4'b1110, 4'b1000: edge_delta = 4'sd1;
            4'b0010, 4'b1011, 4'b1101, 4'b0100: edge_delta = -4'sd1;
            default: begin end
        endcase
    end

    // synthesis translate_off
    initial begin
        if (AB_STABLE_CYCLES < 1 || SW_STABLE_CYCLES < 1 ||
            LONG_PRESS_CYCLES < 1 || (REVERSE != 0 && REVERSE != 1) ||
            (EDGES_PER_STEP != 1 && EDGES_PER_STEP != 2 && EDGES_PER_STEP != 4))
            $fatal(1, "rotary_encoder invalid parameter");
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_ab <= 0; have_sw <= 0; sw_armed <= 0;
            press_active <= 0; long_sent <= 0;
            previous_ab <= 0; residual <= 0; hold_count <= 0;
            step_valid <= 0; step_up <= 0;
            short_press <= 0; long_press <= 0; invalid_count <= 0;
        end else begin
            step_valid <= 0;
            short_press <= 0;
            long_press <= 0;

            if (ab_ready) begin
                have_ab <= 1;
                previous_ab <= ab;
                if (have_ab && ab != previous_ab) begin
                    if (edge_delta == 0) begin
                        residual <= 0;
                        if (invalid_count != 16'hffff)
                            invalid_count <= invalid_count + 1'b1;
                    end else if (next_residual >= STEP_LIMIT) begin
                        residual <= 0;
                        step_valid <= 1;
                        step_up <= (REVERSE == 0);
                    end else if (next_residual <= NEGATIVE_LIMIT) begin
                        residual <= 0;
                        step_valid <= 1;
                        step_up <= (REVERSE != 0);
                    end else residual <= next_residual;
                end
            end

            if (sw_ready) begin
                if (!have_sw) begin
                    have_sw <= 1;
                    sw_armed <= sw_n;
                end else if (!sw_armed) begin
                    if (sw_n) sw_armed <= 1;
                end else if (sw_n) begin
                    if (press_active && !long_sent) begin
                        // A release exactly at the threshold is a long press.
                        if (hold_count == HOLD_LAST) long_press <= 1;
                        else short_press <= 1;
                    end
                    press_active <= 0;
                    hold_count <= 0;
                    long_sent <= 0;
                end else if (!press_active) begin
                    press_active <= 1;
                    hold_count <= 0;
                    long_sent <= 0;
                end else if (!long_sent) begin
                    if (hold_count == HOLD_LAST) begin
                        long_press <= 1;
                        long_sent <= 1;
                    end else hold_count <= hold_count + 1'b1;
                end
            end
        end
    end

endmodule
