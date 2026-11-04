`timescale 1ns / 1ps

// Write-only display transport, SPI mode 0, MSB first, separate D/C pin.
// This is NOT a controller-specific initialization or framebuffer driver.
// All logic runs on clk; LCD_CLK is a registered output, not a logic clock.
//
// Accept a byte on a clk edge with tx_valid && tx_ready. The producer holds
// tx_data/tx_dc/tx_last stable until acceptance. tx_last ends a CS transaction;
// otherwise CS stays low, including any producer stalls between bytes.
// tx_done pulses after all 8 bits AND the final hold interval have finished.
// transaction_done additionally pulses for tx_last. Neither means the panel
// acknowledged anything: this interface has no readback/MISO.
//
// Timing: each SCLK half-period is SCLK_HALF_CYCLES clk periods. First data
// and D/C have at least that much setup before the first rising SCLK. The
// last bit/D/C are held another half-period after the final falling SCLK.
// Between transactions CS stays high for at least one half-period.
// Defaults at 50 MHz: 1 MHz SCLK. Confirm the panel's timing before use.
// Reset aborts an unfinished transfer without a completion pulse. A higher
// layer must reset/reinitialize the panel after an interrupted transaction.
module display_spi_tx #(
    parameter integer SCLK_HALF_CYCLES = 25
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_valid,
    output wire       tx_ready,
    input  wire [7:0] tx_data,
    input  wire       tx_dc,
    input  wire       tx_last,
    output reg        tx_done,
    output reg        transaction_done,
    output reg        LCD_CS,
    output reg        LCD_CLK,
    output reg        LCD_MOSI,
    output reg        LCD_DC
);
    localparam integer CW = (SCLK_HALF_CYCLES < 2) ? 1 : $clog2(SCLK_HALF_CYCLES);
    localparam [CW-1:0] LAST = SCLK_HALF_CYCLES - 1;
    localparam [2:0] IDLE = 3'd0, LOW = 3'd1, HIGH = 3'd2,
                     HOLD = 3'd3, GAP = 3'd4;
    reg [2:0] state;
    reg [CW-1:0] count;
    reg [7:0] shift;
    reg [2:0] bit_index;
    reg last_byte;

    assign tx_ready = rst_n && (state == IDLE);

    // synthesis translate_off
    initial begin
        if (SCLK_HALF_CYCLES < 1)
            $fatal(1, "display_spi_tx requires SCLK_HALF_CYCLES >= 1");
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            count <= 0;
            shift <= 0;
            bit_index <= 0;
            last_byte <= 0;
            tx_done <= 0;
            transaction_done <= 0;
            LCD_CS <= 1;
            LCD_CLK <= 0;
            LCD_MOSI <= 0;
            LCD_DC <= 0;
        end else begin
            tx_done <= 0;
            transaction_done <= 0;
            case (state)
                IDLE: begin
                    if (tx_valid) begin
                        shift <= tx_data;
                        last_byte <= tx_last;
                        LCD_DC <= tx_dc;
                        LCD_MOSI <= tx_data[7];
                        LCD_CS <= 0;
                        bit_index <= 0;
                        count <= 0;
                        state <= LOW;
                    end
                end
                LOW: begin
                    if (count == LAST) begin
                        count <= 0;
                        LCD_CLK <= 1;
                        state <= HIGH;
                    end else count <= count + 1'b1;
                end
                HIGH: begin
                    if (count == LAST) begin
                        count <= 0;
                        LCD_CLK <= 0;
                        if (bit_index == 7) begin
                            // Keep LSB and D/C stable throughout HOLD.
                            state <= HOLD;
                        end else begin
                            shift <= {shift[6:0], 1'b0};
                            LCD_MOSI <= shift[6];
                            bit_index <= bit_index + 1'b1;
                            state <= LOW;
                        end
                    end else count <= count + 1'b1;
                end
                HOLD: begin
                    if (count == LAST) begin
                        count <= 0;
                        tx_done <= 1;
                        if (last_byte) begin
                            LCD_CS <= 1;
                            transaction_done <= 1;
                            state <= GAP;
                        end else state <= IDLE;
                    end else count <= count + 1'b1;
                end
                GAP: begin
                    if (count == LAST) begin
                        count <= 0;
                        state <= IDLE;
                    end else count <= count + 1'b1;
                end
                default: begin
                    state <= IDLE;
                    LCD_CS <= 1;
                    LCD_CLK <= 0;
                    LCD_MOSI <= 0;
                    LCD_DC <= 0;
                    count <= 0;
                end
            endcase
        end
    end

endmodule
