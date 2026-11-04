`timescale 1ns/1ps

// GC9A01(A), 240x240, four-wire SPI, RGB565 initialization bytecode.
// Reference: Waveshare team, LCD_1IN28.c V1.0, 2020-12-16, InitReg:
// https://github.com/waveshareteam/RP2040-Touch-LCD-1.28/blob/main/c/lib/LCD/LCD_1in28.c
// Reference file SHA256 (downloaded 2026-10-17):
// fc7b5773deb0380fda9f02e2f8ebc4e1baff877461ea31e6b0c3fc14b624113b
// Datasheet: https://files.waveshare.com/wiki/common/GC9A01A.pdf
//
// The Waveshare register values (including analog power/gamma and 0x70) are
// preserved as one coherent panel profile. This is a common starting profile,
// not proof that every third-party GC9A01 module uses the same panel settings.
// Verify orientation, red/blue order, inversion and appearance on the board.
// Adaptations: MADCTL and inversion are parameters; TEON explicitly sends 00
// (vertical-blank-only mode, datasheet p125) instead of omitting its parameter.
// COLMOD=05 selects 16-bit MCU/SPI pixels; unused DPI bits are ignored (p135).
// MADCTL=08 selects BGR and no axis swaps/mirrors (p127). Pixel input remains
// standard RGB565 (R[15:11], G[10:5], B[4:0]), high byte first on the wire.
//
// The caller performs hardware reset before addr=0 and keeps backlight off.
// Kind: 00 command, 01 data, 10 delay in milliseconds, 11 end.
// Delays start AFTER the preceding byte has physically finished transmitting.
// SleepOut waits 120 ms; DisplayOn waits 20 ms, matching the reference demo.
// After end, clear GRAM before enabling the backlight. This ROM does not draw.
// Valid entries are 0..187; every unused address also returns end safely.
//
// Upstream demo permission notice, retained from c/lib/Config/DEV_Config.c:
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
module gc9a01_init_rom #(
    parameter [7:0] MADCTL = 8'h08,
    parameter integer INVERT = 1
) (
    input wire [7:0] addr,
    output reg [1:0] kind,
    output reg [7:0] value
);
    always @* begin
        kind = 2'b11;
        value = 8'h00;
        case (addr)
            8'd0: begin kind = 2'b00; value = 8'hEF; end // Command EF
            8'd1: begin kind = 2'b00; value = 8'hEB; end // Command EB
            8'd2: begin kind = 2'b01; value = 8'h14; end
            8'd3: begin kind = 2'b00; value = 8'hFE; end // Command FE
            8'd4: begin kind = 2'b00; value = 8'hEF; end // Command EF
            8'd5: begin kind = 2'b00; value = 8'hEB; end // Command EB
            8'd6: begin kind = 2'b01; value = 8'h14; end
            8'd7: begin kind = 2'b00; value = 8'h84; end // Command 84
            8'd8: begin kind = 2'b01; value = 8'h40; end
            8'd9: begin kind = 2'b00; value = 8'h85; end // Command 85
            8'd10: begin kind = 2'b01; value = 8'hFF; end
            8'd11: begin kind = 2'b00; value = 8'h86; end // Command 86
            8'd12: begin kind = 2'b01; value = 8'hFF; end
            8'd13: begin kind = 2'b00; value = 8'h87; end // Command 87
            8'd14: begin kind = 2'b01; value = 8'hFF; end
            8'd15: begin kind = 2'b00; value = 8'h88; end // Command 88
            8'd16: begin kind = 2'b01; value = 8'h0A; end
            8'd17: begin kind = 2'b00; value = 8'h89; end // Command 89
            8'd18: begin kind = 2'b01; value = 8'h21; end
            8'd19: begin kind = 2'b00; value = 8'h8A; end // Command 8A
            8'd20: begin kind = 2'b01; value = 8'h00; end
            8'd21: begin kind = 2'b00; value = 8'h8B; end // Command 8B
            8'd22: begin kind = 2'b01; value = 8'h80; end
            8'd23: begin kind = 2'b00; value = 8'h8C; end // Command 8C
            8'd24: begin kind = 2'b01; value = 8'h01; end
            8'd25: begin kind = 2'b00; value = 8'h8D; end // Command 8D
            8'd26: begin kind = 2'b01; value = 8'h01; end
            8'd27: begin kind = 2'b00; value = 8'h8E; end // Command 8E
            8'd28: begin kind = 2'b01; value = 8'hFF; end
            8'd29: begin kind = 2'b00; value = 8'h8F; end // Command 8F
            8'd30: begin kind = 2'b01; value = 8'hFF; end
            8'd31: begin kind = 2'b00; value = 8'hB6; end // Command B6
            8'd32: begin kind = 2'b01; value = 8'h00; end
            8'd33: begin kind = 2'b01; value = 8'h20; end
            8'd34: begin kind = 2'b00; value = 8'h36; end // Command 36
            8'd35: begin kind = 2'b01; value = MADCTL; end // Memory access / BGR / rotation
            8'd36: begin kind = 2'b00; value = 8'h3A; end // COLMOD
            8'd37: begin kind = 2'b01; value = 8'h05; end
            8'd38: begin kind = 2'b00; value = 8'h90; end // Command 90
            8'd39: begin kind = 2'b01; value = 8'h08; end
            8'd40: begin kind = 2'b01; value = 8'h08; end
            8'd41: begin kind = 2'b01; value = 8'h08; end
            8'd42: begin kind = 2'b01; value = 8'h08; end
            8'd43: begin kind = 2'b00; value = 8'hBD; end // Command BD
            8'd44: begin kind = 2'b01; value = 8'h06; end
            8'd45: begin kind = 2'b00; value = 8'hBC; end // Command BC
            8'd46: begin kind = 2'b01; value = 8'h00; end
            8'd47: begin kind = 2'b00; value = 8'hFF; end // Command FF
            8'd48: begin kind = 2'b01; value = 8'h60; end
            8'd49: begin kind = 2'b01; value = 8'h01; end
            8'd50: begin kind = 2'b01; value = 8'h04; end
            8'd51: begin kind = 2'b00; value = 8'hC3; end // Command C3
            8'd52: begin kind = 2'b01; value = 8'h13; end
            8'd53: begin kind = 2'b00; value = 8'hC4; end // Command C4
            8'd54: begin kind = 2'b01; value = 8'h13; end
            8'd55: begin kind = 2'b00; value = 8'hC9; end // Command C9
            8'd56: begin kind = 2'b01; value = 8'h22; end
            8'd57: begin kind = 2'b00; value = 8'hBE; end // Command BE
            8'd58: begin kind = 2'b01; value = 8'h11; end
            8'd59: begin kind = 2'b00; value = 8'hE1; end // Command E1
            8'd60: begin kind = 2'b01; value = 8'h10; end
            8'd61: begin kind = 2'b01; value = 8'h0E; end
            8'd62: begin kind = 2'b00; value = 8'hDF; end // Command DF
            8'd63: begin kind = 2'b01; value = 8'h21; end
            8'd64: begin kind = 2'b01; value = 8'h0C; end
            8'd65: begin kind = 2'b01; value = 8'h02; end
            8'd66: begin kind = 2'b00; value = 8'hF0; end // Command F0
            8'd67: begin kind = 2'b01; value = 8'h45; end
            8'd68: begin kind = 2'b01; value = 8'h09; end
            8'd69: begin kind = 2'b01; value = 8'h08; end
            8'd70: begin kind = 2'b01; value = 8'h08; end
            8'd71: begin kind = 2'b01; value = 8'h26; end
            8'd72: begin kind = 2'b01; value = 8'h2A; end
            8'd73: begin kind = 2'b00; value = 8'hF1; end // Command F1
            8'd74: begin kind = 2'b01; value = 8'h43; end
            8'd75: begin kind = 2'b01; value = 8'h70; end
            8'd76: begin kind = 2'b01; value = 8'h72; end
            8'd77: begin kind = 2'b01; value = 8'h36; end
            8'd78: begin kind = 2'b01; value = 8'h37; end
            8'd79: begin kind = 2'b01; value = 8'h6F; end
            8'd80: begin kind = 2'b00; value = 8'hF2; end // Command F2
            8'd81: begin kind = 2'b01; value = 8'h45; end
            8'd82: begin kind = 2'b01; value = 8'h09; end
            8'd83: begin kind = 2'b01; value = 8'h08; end
            8'd84: begin kind = 2'b01; value = 8'h08; end
            8'd85: begin kind = 2'b01; value = 8'h26; end
            8'd86: begin kind = 2'b01; value = 8'h2A; end
            8'd87: begin kind = 2'b00; value = 8'hF3; end // Command F3
            8'd88: begin kind = 2'b01; value = 8'h43; end
            8'd89: begin kind = 2'b01; value = 8'h70; end
            8'd90: begin kind = 2'b01; value = 8'h72; end
            8'd91: begin kind = 2'b01; value = 8'h36; end
            8'd92: begin kind = 2'b01; value = 8'h37; end
            8'd93: begin kind = 2'b01; value = 8'h6F; end
            8'd94: begin kind = 2'b00; value = 8'hED; end // Command ED
            8'd95: begin kind = 2'b01; value = 8'h1B; end
            8'd96: begin kind = 2'b01; value = 8'h0B; end
            8'd97: begin kind = 2'b00; value = 8'hAE; end // Command AE
            8'd98: begin kind = 2'b01; value = 8'h77; end
            8'd99: begin kind = 2'b00; value = 8'hCD; end // Command CD
            8'd100: begin kind = 2'b01; value = 8'h63; end
            8'd101: begin kind = 2'b00; value = 8'h70; end // Command 70
            8'd102: begin kind = 2'b01; value = 8'h07; end
            8'd103: begin kind = 2'b01; value = 8'h07; end
            8'd104: begin kind = 2'b01; value = 8'h04; end
            8'd105: begin kind = 2'b01; value = 8'h0E; end
            8'd106: begin kind = 2'b01; value = 8'h0F; end
            8'd107: begin kind = 2'b01; value = 8'h09; end
            8'd108: begin kind = 2'b01; value = 8'h07; end
            8'd109: begin kind = 2'b01; value = 8'h08; end
            8'd110: begin kind = 2'b01; value = 8'h03; end
            8'd111: begin kind = 2'b00; value = 8'hE8; end // Command E8
            8'd112: begin kind = 2'b01; value = 8'h34; end
            8'd113: begin kind = 2'b00; value = 8'h62; end // Command 62
            8'd114: begin kind = 2'b01; value = 8'h18; end
            8'd115: begin kind = 2'b01; value = 8'h0D; end
            8'd116: begin kind = 2'b01; value = 8'h71; end
            8'd117: begin kind = 2'b01; value = 8'hED; end
            8'd118: begin kind = 2'b01; value = 8'h70; end
            8'd119: begin kind = 2'b01; value = 8'h70; end
            8'd120: begin kind = 2'b01; value = 8'h18; end
            8'd121: begin kind = 2'b01; value = 8'h0F; end
            8'd122: begin kind = 2'b01; value = 8'h71; end
            8'd123: begin kind = 2'b01; value = 8'hEF; end
            8'd124: begin kind = 2'b01; value = 8'h70; end
            8'd125: begin kind = 2'b01; value = 8'h70; end
            8'd126: begin kind = 2'b00; value = 8'h63; end // Command 63
            8'd127: begin kind = 2'b01; value = 8'h18; end
            8'd128: begin kind = 2'b01; value = 8'h11; end
            8'd129: begin kind = 2'b01; value = 8'h71; end
            8'd130: begin kind = 2'b01; value = 8'hF1; end
            8'd131: begin kind = 2'b01; value = 8'h70; end
            8'd132: begin kind = 2'b01; value = 8'h70; end
            8'd133: begin kind = 2'b01; value = 8'h18; end
            8'd134: begin kind = 2'b01; value = 8'h13; end
            8'd135: begin kind = 2'b01; value = 8'h71; end
            8'd136: begin kind = 2'b01; value = 8'hF3; end
            8'd137: begin kind = 2'b01; value = 8'h70; end
            8'd138: begin kind = 2'b01; value = 8'h70; end
            8'd139: begin kind = 2'b00; value = 8'h64; end // Command 64
            8'd140: begin kind = 2'b01; value = 8'h28; end
            8'd141: begin kind = 2'b01; value = 8'h29; end
            8'd142: begin kind = 2'b01; value = 8'hF1; end
            8'd143: begin kind = 2'b01; value = 8'h01; end
            8'd144: begin kind = 2'b01; value = 8'hF1; end
            8'd145: begin kind = 2'b01; value = 8'h00; end
            8'd146: begin kind = 2'b01; value = 8'h07; end
            8'd147: begin kind = 2'b00; value = 8'h66; end // Command 66
            8'd148: begin kind = 2'b01; value = 8'h3C; end
            8'd149: begin kind = 2'b01; value = 8'h00; end
            8'd150: begin kind = 2'b01; value = 8'hCD; end
            8'd151: begin kind = 2'b01; value = 8'h67; end
            8'd152: begin kind = 2'b01; value = 8'h45; end
            8'd153: begin kind = 2'b01; value = 8'h45; end
            8'd154: begin kind = 2'b01; value = 8'h10; end
            8'd155: begin kind = 2'b01; value = 8'h00; end
            8'd156: begin kind = 2'b01; value = 8'h00; end
            8'd157: begin kind = 2'b01; value = 8'h00; end
            8'd158: begin kind = 2'b00; value = 8'h67; end // Command 67
            8'd159: begin kind = 2'b01; value = 8'h00; end
            8'd160: begin kind = 2'b01; value = 8'h3C; end
            8'd161: begin kind = 2'b01; value = 8'h00; end
            8'd162: begin kind = 2'b01; value = 8'h00; end
            8'd163: begin kind = 2'b01; value = 8'h00; end
            8'd164: begin kind = 2'b01; value = 8'h01; end
            8'd165: begin kind = 2'b01; value = 8'h54; end
            8'd166: begin kind = 2'b01; value = 8'h10; end
            8'd167: begin kind = 2'b01; value = 8'h32; end
            8'd168: begin kind = 2'b01; value = 8'h98; end
            8'd169: begin kind = 2'b00; value = 8'h74; end // Command 74
            8'd170: begin kind = 2'b01; value = 8'h10; end
            8'd171: begin kind = 2'b01; value = 8'h85; end
            8'd172: begin kind = 2'b01; value = 8'h80; end
            8'd173: begin kind = 2'b01; value = 8'h00; end
            8'd174: begin kind = 2'b01; value = 8'h00; end
            8'd175: begin kind = 2'b01; value = 8'h4E; end
            8'd176: begin kind = 2'b01; value = 8'h00; end
            8'd177: begin kind = 2'b00; value = 8'h98; end // Command 98
            8'd178: begin kind = 2'b01; value = 8'h3E; end
            8'd179: begin kind = 2'b01; value = 8'h07; end
            8'd180: begin kind = 2'b00; value = 8'h35; end // TEON; TE output need not be connected
            8'd181: begin kind = 2'b01; value = 8'h00; end
            8'd182: begin kind = 2'b00; value = (INVERT != 0) ? 8'h21 : 8'h20; end // Panel inversion
            8'd183: begin kind = 2'b00; value = 8'h11; end // Sleep Out
            8'd184: begin kind = 2'b10; value = 8'h78; end // Wait 120 ms after byte completion
            8'd185: begin kind = 2'b00; value = 8'h29; end // Display On
            8'd186: begin kind = 2'b10; value = 8'h14; end // Wait 20 ms after byte completion
            8'd187: begin kind = 2'b11; value = 8'h00; end // End
            default: begin kind = 2'b11; value = 8'h00; end
        endcase
    end

endmodule
