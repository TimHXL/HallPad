`timescale 1ns/1ps
// Fractional bit timers stay in the system clock domain. No UART clock is made.
module hallpad_uart_rx #(parameter integer CLK_HZ=50000000,BAUD=115200)(input wire clk,rst_n,rx,output reg [7:0] data,output reg valid,framing_error);
    localparam integer TW=CLK_HZ<2 ? 1:$clog2(CLK_HZ+1);
    (* syn_preserve=1,syn_async_reg="true" *) reg [1:0] sync_rx;
    reg [2:0] state;
    reg [2:0] bit_index;
    reg [7:0] shift;
    reg [TW-1:0] remaining;
    localparam [TW-1:0] CLOCK_COUNT=CLK_HZ[TW-1:0],BAUD_COUNT=BAUD[TW-1:0];
    wire [TW:0] next_remaining={1'b0,remaining}+{1'b0,CLOCK_COUNT}-{1'b0,BAUD_COUNT};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) sync_rx<=2'b11;
        else sync_rx<={sync_rx[0],rx};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=0;bit_index<=0;shift<=0;remaining<=0;data<=0;valid<=0;framing_error<=0;end
        else begin
            valid<=0;framing_error<=0;
            case(state)
                0:if(sync_rx[1]==1'b0) begin remaining<=CLOCK_COUNT>>1;state<=1;end
                4:if(sync_rx[1]==1'b1) state<=0;
                default:if(remaining>BAUD) remaining<=remaining-BAUD_COUNT;
                else begin
                    remaining<=next_remaining[TW-1:0];
                    case(state)
                        1:if(sync_rx[1]==1'b0) begin bit_index<=0;state<=2;end else state<=0;
                        2:begin shift[bit_index]<=sync_rx[1];if(bit_index==7) state<=3;else bit_index<=bit_index+1'b1;end
                        3:if(sync_rx[1]==1'b1) begin data<=shift;valid<=1;state<=0;end
                          else begin framing_error<=1;state<=4;end
                        default:state<=0;
                    endcase
                end
            endcase
        end
    end
endmodule

module hallpad_uart_tx #(parameter integer CLK_HZ=50000000,BAUD=115200)(input wire clk,rst_n,input wire [7:0] data,input wire valid,output wire ready,output wire tx);
    localparam integer TW=CLK_HZ<2 ? 1:$clog2(CLK_HZ+1);
    reg [9:0] shift;
    reg [3:0] bits_left;
    reg [TW-1:0] remaining;
    localparam [TW-1:0] CLOCK_COUNT=CLK_HZ[TW-1:0],BAUD_COUNT=BAUD[TW-1:0];
    wire [TW:0] next_remaining={1'b0,remaining}+{1'b0,CLOCK_COUNT}-{1'b0,BAUD_COUNT};
    assign ready=bits_left==0;
    assign tx=ready ? 1'b1:shift[0];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin shift<=10'h3ff;bits_left<=0;remaining<=0;end
        else if(ready) begin
            if(valid) begin shift<={1'b1,data,1'b0};bits_left<=10;remaining<=CLOCK_COUNT;end
        end else if(remaining>BAUD) remaining<=remaining-BAUD_COUNT;
        else begin remaining<=next_remaining[TW-1:0];shift<={1'b1,shift[9:1]};bits_left<=bits_left-1'b1;end
    end
endmodule

module hallpad_byte_fifo #(parameter integer DEPTH=2048)(input wire clk,rst_n,clear,input wire [7:0] in_data,input wire in_valid,output wire in_ready,output wire [7:0] out_data,output wire out_valid,input wire out_ready,output reg overflow,output reg [31:0] overflow_count);
    localparam integer AW=DEPTH<2 ? 1:$clog2(DEPTH);
    localparam integer CW=DEPTH<2 ? 1:$clog2(DEPTH+1);
    localparam [AW-1:0] LAST_ADDRESS=DEPTH-1;
    localparam [CW-1:0] CAPACITY=DEPTH;
    // One visible head plus at most DEPTH-1 tail bytes. Keeping DEPTH RAM
    // addresses leaves one unused tail address, even when the FIFO is full.
    // A simultaneous tail read/write therefore never uses the same address.
    (* syn_ramstyle="block_ram" *) reg [7:0] mem[0:DEPTH-1];
    reg [AW-1:0] rd,wr;
    reg [CW-1:0] used;
    wire [AW:0] next_rd={1'b0,rd}+1'b1,next_wr={1'b0,wr}+1'b1;
    reg [7:0] ram_head,direct_head;
    reg head_is_ram;
    assign out_valid=rst_n && !clear && used!=0;
    assign out_data=out_valid ? (head_is_ram ? ram_head:direct_head):8'd0;
    wire pop=out_valid && out_ready;
    assign in_ready=rst_n && !clear && (used<CAPACITY || pop);
    wire push=in_valid && in_ready;
    // Empty enqueue and replacement of the sole head bypass RAM. Otherwise a
    // consumed head prefetches its successor synchronously on that same edge;
    // ram_head becomes the next visible byte without an output-valid bubble.
    wire read_tail=pop && used>1;
    wire direct_push=push && (used==0 || (pop && used==1));
    wire write_tail=push && !direct_push;
    // Separate unreset RAM output: no asynchronous memory reads, reset muxes,
    // or input-data bypass assignments on the inferred BSRAM read register.
    always @(posedge clk) begin
        if(write_tail) mem[wr]<=in_data;
        if(read_tail) ram_head<=mem[rd];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rd<=0;wr<=0;used<=0;direct_head<=0;head_is_ram<=0;overflow<=0;overflow_count<=0;end
        else begin
            overflow<=in_valid && !in_ready && !clear;
            if(in_valid && !in_ready && !clear && overflow_count!=32'hffffffff) overflow_count<=overflow_count+1'b1;
            // Clear flushes data but, as before, preserves overflow_count.
            if(clear) begin rd<=0;wr<=0;used<=0;direct_head<=0;head_is_ram<=0;end
            else begin
                if(read_tail) begin
                    rd<=rd==LAST_ADDRESS ? {AW{1'b0}}:next_rd[AW-1:0];
                    head_is_ram<=1;
                end
                if(direct_push) begin direct_head<=in_data;head_is_ram<=0;end
                if(write_tail) wr<=wr==LAST_ADDRESS ? {AW{1'b0}}:next_wr[AW-1:0];
                case({push,pop}) 2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:used<=used;endcase
            end
        end
    end
    // synthesis translate_off
    initial begin
        if(DEPTH<1) begin $display("ERROR hallpad_byte_fifo: DEPTH must be positive");$finish;end
    end
    // synthesis translate_on
endmodule

module hallpad_module_manager #(parameter integer CLK_HZ=50000000,POWERUP_MS=2000)(input wire clk,rst_n,output reg transparent_ready);
    localparam integer WAIT_CYCLES=(CLK_HZ/1000)*POWERUP_MS;
    localparam integer CW=WAIT_CYCLES<2 ? 1:$clog2(WAIT_CYCLES+1);
    reg [CW-1:0] elapsed;
    // Provision AT settings once with the documented host procedure. Normal
    // boots never rewrite module Flash or interleave AT text with binary frames.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin elapsed<=0;transparent_ready<=POWERUP_MS==0;end
        else if(!transparent_ready) begin
            if(elapsed>=WAIT_CYCLES-1) transparent_ready<=1;
            else elapsed<=elapsed+1'b1;
        end
    end
endmodule
