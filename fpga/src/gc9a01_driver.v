`timescale 1ns / 1ps

// GC9A01 240x240, four-wire SPI, RGB565 (high byte first).
// clk-domain ready/valid interface; no frame RAM or generated logic clocks.
// After reset: panel reset, vendor init, full black clear, then init_done.
// The caller supplies inclusive windows and either a solid color or exactly
// one pixel per pixel_valid && pixel_ready. Pixel order: X first, then Y.
// Requests and pixels may stall indefinitely; no pixel is consumed twice.
// No readback: init_done means the write sequence finished, not panel ACK.
module gc9a01_driver #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SCLK_HALF_CYCLES = 5,
    parameter integer RESET_LOW_MS = 100,
    parameter integer RESET_RELEASE_MS = 120,
    parameter [7:0] MADCTL = 8'h08,
    parameter integer INVERT = 1,
    parameter integer BL_ACTIVE_HIGH = 1
) (
    input wire clk, rst_n,
    input wire backlight_en,
    input wire draw_valid,
    output wire draw_ready,
    input wire [7:0] x0, y0, x1, y1,
    input wire fill_mode,
    input wire [15:0] fill_color,
    input wire pixel_valid,
    output wire pixel_ready,
    input wire [15:0] pixel_rgb565,
    output reg init_done,
    output wire busy,
    output reg draw_done,
    output reg draw_error,
    output wire LCD_CS, LCD_CLK, LCD_MOSI, LCD_DC,
    output reg LCD_RES,
    output wire LCD_BLK
);
    // Integer division rounds up so requested delays are never shortened.
    localparam integer CYCLES_PER_MS = CLK_HZ / 1000 + ((CLK_HZ % 1000) != 0);
    localparam integer MW = (CYCLES_PER_MS < 2) ? 1 : $clog2(CYCLES_PER_MS);
    localparam [MW-1:0] MS_LAST = CYCLES_PER_MS - 1;
    localparam [3:0] RESET_LOW = 0, RESET_RELEASE = 1, INIT = 2,
                     INIT_SEND = 3, INIT_DRAIN = 4, DELAY = 5,
                     IDLE = 6, WINDOW = 7, PIXEL_LOAD = 8,
                     PIXEL_HIGH = 9, PIXEL_LOW = 10, DRAW_DRAIN = 11;
    reg [3:0] state;
    reg [MW-1:0] ms_count;
    reg [7:0] ms_left;
    reg [7:0] rom_addr;
    wire [1:0] rom_kind;
    wire [7:0] rom_value;
    reg [3:0] window_index;
    reg [7:0] left_x, top_y, right_x, bottom_y, cursor_x, cursor_y;
    reg solid, clearing;
    reg [15:0] pixel;
    wire final_pixel = (cursor_x == right_x) && (cursor_y == bottom_y);

    reg tx_valid, tx_dc, tx_last;
    reg [7:0] tx_data;
    wire tx_ready, tx_done, transaction_done;

    assign draw_ready = rst_n && init_done && (state == IDLE);
    assign pixel_ready = rst_n && (state == PIXEL_LOAD);
    assign busy = !draw_ready;
    wire light_on = rst_n && init_done && backlight_en;
    assign LCD_BLK = (BL_ACTIVE_HIGH != 0) ? light_on : !light_on;

    gc9a01_init_rom #(.MADCTL(MADCTL), .INVERT(INVERT)) u_init (
        .addr(rom_addr), .kind(rom_kind), .value(rom_value)
    );
    display_spi_tx #(.SCLK_HALF_CYCLES(SCLK_HALF_CYCLES)) u_spi (
        .clk(clk), .rst_n(rst_n), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .tx_data(tx_data), .tx_dc(tx_dc), .tx_last(tx_last),
        .tx_done(tx_done), .transaction_done(transaction_done),
        .LCD_CS(LCD_CS), .LCD_CLK(LCD_CLK), .LCD_MOSI(LCD_MOSI), .LCD_DC(LCD_DC)
    );

    // One address command and its parameters share CS. RAMWR and the whole
    // pixel window share CS, including any producer pauses between pixels.
    always @* begin
        tx_valid = 0;
        tx_data = 0;
        tx_dc = 0;
        tx_last = 0;
        case (state)
            INIT_SEND: begin
                tx_valid = 1;
                tx_data = rom_value;
                tx_dc = rom_kind[0];
                tx_last = 1;
            end
            WINDOW: begin
                tx_valid = 1;
                tx_dc = (window_index != 0 && window_index != 5 && window_index != 10);
                tx_last = (window_index == 4 || window_index == 9);
                case (window_index)
                    0: tx_data = 8'h2A;
                    2: tx_data = left_x;
                    4: tx_data = right_x;
                    5: tx_data = 8'h2B;
                    7: tx_data = top_y;
                    9: tx_data = bottom_y;
                    10: tx_data = 8'h2C;
                    default: tx_data = 0;
                endcase
            end
            PIXEL_HIGH: begin
                tx_valid = 1;
                tx_dc = 1;
                tx_data = pixel[15:8];
            end
            PIXEL_LOW: begin
                tx_valid = 1;
                tx_dc = 1;
                tx_data = pixel[7:0];
                tx_last = final_pixel;
            end
            default: begin end
        endcase
    end

    // synthesis translate_off
    initial begin
        if (CLK_HZ < 1 || RESET_LOW_MS < 1 || RESET_LOW_MS > 255 ||
            RESET_RELEASE_MS < 1 || RESET_RELEASE_MS > 255 ||
            (INVERT != 0 && INVERT != 1) ||
            (BL_ACTIVE_HIGH != 0 && BL_ACTIVE_HIGH != 1))
            $fatal(1, "gc9a01_driver invalid parameter");
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RESET_LOW;
            ms_count <= 0;
            ms_left <= RESET_LOW_MS;
            rom_addr <= 0;
            window_index <= 0;
            left_x <= 0; top_y <= 0; right_x <= 0; bottom_y <= 0;
            cursor_x <= 0; cursor_y <= 0;
            solid <= 1;
            clearing <= 1;
            pixel <= 0;
            init_done <= 0;
            draw_done <= 0;
            draw_error <= 0;
            LCD_RES <= 0;
        end else begin
            draw_done <= 0;
            draw_error <= 0;
            case (state)
                RESET_LOW, RESET_RELEASE, DELAY: begin
                    if (ms_count == MS_LAST) begin
                        ms_count <= 0;
                        if (ms_left <= 1) begin
                            if (state == RESET_LOW) begin
                                LCD_RES <= 1;
                                ms_left <= RESET_RELEASE_MS;
                                state <= RESET_RELEASE;
                            end else state <= INIT;
                        end else ms_left <= ms_left - 1'b1;
                    end else ms_count <= ms_count + 1'b1;
                end
                INIT: begin
                    case (rom_kind)
                        2'b00, 2'b01: state <= INIT_SEND;
                        2'b10: begin
                            rom_addr <= rom_addr + 1'b1;
                            ms_count <= 0;
                            ms_left <= rom_value;
                            if (rom_value != 0) state <= DELAY;
                        end
                        default: begin
                            // Clear controller RAM before making it visible.
                            left_x <= 0; top_y <= 0;
                            right_x <= 239; bottom_y <= 239;
                            cursor_x <= 0; cursor_y <= 0;
                            solid <= 1;
                            pixel <= 0;
                            clearing <= 1;
                            window_index <= 0;
                            state <= WINDOW;
                        end
                    endcase
                end
                INIT_SEND: if (tx_ready) state <= INIT_DRAIN;
                INIT_DRAIN: if (tx_done) begin
                    rom_addr <= rom_addr + 1'b1;
                    state <= INIT;
                end
                IDLE: begin
                    if (draw_valid) begin
                        if (x0 > x1 || y0 > y1 || x1 > 239 || y1 > 239) begin
                            draw_error <= 1;
                        end else begin
                            left_x <= x0; top_y <= y0; right_x <= x1; bottom_y <= y1;
                            cursor_x <= x0; cursor_y <= y0;
                            solid <= fill_mode;
                            pixel <= fill_color;
                            clearing <= 0;
                            window_index <= 0;
                            state <= WINDOW;
                        end
                    end
                end
                WINDOW: if (tx_ready) begin
                    if (window_index == 10)
                        state <= solid ? PIXEL_HIGH : PIXEL_LOAD;
                    else window_index <= window_index + 1'b1;
                end
                PIXEL_LOAD: if (pixel_valid) begin
                    pixel <= pixel_rgb565;
                    state <= PIXEL_HIGH;
                end
                PIXEL_HIGH: if (tx_ready) state <= PIXEL_LOW;
                PIXEL_LOW: if (tx_ready) begin
                    if (final_pixel) state <= DRAW_DRAIN;
                    else begin
                        if (cursor_x == right_x) begin
                            cursor_x <= left_x;
                            cursor_y <= cursor_y + 1'b1;
                        end else cursor_x <= cursor_x + 1'b1;
                        state <= solid ? PIXEL_HIGH : PIXEL_LOAD;
                    end
                end
                DRAW_DRAIN: if (tx_done && transaction_done) begin
                    if (clearing) init_done <= 1;
                    else draw_done <= 1;
                    state <= IDLE;
                end
                default: begin
                    // Recover both panel and transport coherently via rst_n;
                    // this fallback keeps the panel dark pending re-init.
                    state <= RESET_LOW;
                    ms_count <= 0;
                    ms_left <= RESET_LOW_MS;
                    rom_addr <= 0;
                    LCD_RES <= 0;
                    init_done <= 0;
                end
            endcase
        end
    end

endmodule
