`timescale 1ns / 1ps

// Same-clock event queue: key_event -> key_event_fifo -> voice_ctrl_bridge.
// in_event_valid is a WRITE STROBE with no ready/backpressure. Consume every
// asserted cycle, including consecutive events; store all 20 payload bits.
// out_event_valid/ready is a held handshake: pop only at a rising clk edge
// where both are high. No empty-queue bypass; enqueue at n, earliest pop n+1.
// Full + pop + input accepts both events without reporting overflow.
//
// If full without a pop, reject the NEW event, preserve the queued order,
// pulse overflow and latch diagnostics. OFF can be lost in this condition!
// The future supervisor/bridge must handle overflow_sticky by silencing
// voices and coordinating FIFO/upstream state cleanup before resuming.
// Finite capacity cannot guarantee lossless delivery during unbounded stalls.
// Default 128 entries holds a 35-ON + 35-OFF burst from an initially empty FIFO.
//
// fifo_clear is synchronous, overrides push/pop, discards the current input,
// and masks out_event_valid during the clear cycle. It does NOT silence voices
// or clear diagnostics. diag_clear only clears diagnostics; a new rejection
// on that same edge wins (sticky=1, dropped_count=1). Count saturates at 65535.
// Reset clears control/diagnostics; storage need not be reset because empty
// masks its output. Assert rst_n asynchronously, release synchronously.
// All inputs including ready/clear must be synchronous to clk. This is not CDC.
module key_event_fifo #(
    parameter integer DEPTH = 128
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        fifo_clear,
    input  wire        diag_clear,

    input  wire        in_event_valid,
    input  wire        in_event_on,
    input  wire [5:0]  in_event_key_id,
    input  wire [5:0]  in_event_note_sel,
    input  wire [6:0]  in_event_velocity,

    output wire        out_event_valid,
    input  wire        out_event_ready,
    output wire        out_event_on,
    output wire [5:0]  out_event_key_id,
    output wire [5:0]  out_event_note_sel,
    output wire [6:0]  out_event_velocity,

    output wire        fifo_empty,
    output wire        fifo_full,
    output wire [((DEPTH < 2) ? 1 : $clog2(DEPTH + 1))-1:0] fifo_level,
    output reg         overflow,
    output reg         overflow_sticky,
    output reg  [15:0] dropped_count
);

    localparam integer PTR_W = (DEPTH < 2) ? 1 : $clog2(DEPTH);
    localparam integer COUNT_W = (DEPTH < 2) ? 1 : $clog2(DEPTH + 1);
    localparam [PTR_W-1:0] LAST_ADDR = DEPTH - 1;
    localparam [COUNT_W-1:0] CAPACITY = DEPTH;

    // synthesis translate_off
    initial begin
        if (DEPTH < 1 || DEPTH > 65535) begin
            $display("FAIL key_event_fifo DEPTH must be in 1..65535");
            $finish;
        end
    end
    // synthesis translate_on

    reg [19:0] storage [0:DEPTH-1];
    reg [PTR_W-1:0] read_ptr, write_ptr;
    reg [COUNT_W-1:0] used;

    assign fifo_level = used;
    assign fifo_empty = (used == {COUNT_W{1'b0}});
    assign fifo_full = (used == CAPACITY);
    assign out_event_valid = rst_n && !fifo_clear && !fifo_empty;

    // No re-encoding, note subtraction, velocity mapping, or input filtering.
    // Invalid payloads are an upstream error; silently discarding an OFF here
    // would break the transparent queue contract.
    assign {out_event_on, out_event_key_id, out_event_note_sel,
            out_event_velocity} = fifo_empty ? 20'd0 : storage[read_ptr];

    wire pop = out_event_valid && out_event_ready;
    wire push = rst_n && !fifo_clear && in_event_valid && (!fifo_full || pop);
    wire reject_input = rst_n && !fifo_clear && in_event_valid && fifo_full && !pop;

    // Explicit terminal-address wrap supports DEPTH=1 and non-powers of two.
    // With full + pop, the consumer samples the OLD head before this write.
    always @(posedge clk) begin
        if (push)
            storage[write_ptr] <= {in_event_on, in_event_key_id,
                                   in_event_note_sel, in_event_velocity};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr <= {PTR_W{1'b0}};
            write_ptr <= {PTR_W{1'b0}};
            used <= {COUNT_W{1'b0}};
        end else if (fifo_clear) begin
            read_ptr <= {PTR_W{1'b0}};
            write_ptr <= {PTR_W{1'b0}};
            used <= {COUNT_W{1'b0}};
        end else begin
            if (push)
                write_ptr <= (write_ptr == LAST_ADDR) ? {PTR_W{1'b0}} : write_ptr + 1'b1;
            if (pop)
                read_ptr <= (read_ptr == LAST_ADDR) ? {PTR_W{1'b0}} : read_ptr + 1'b1;
            case ({push, pop})
                2'b10: used <= used + 1'b1;
                2'b01: used <= used - 1'b1;
                default: used <= used;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            overflow <= 1'b0;
            overflow_sticky <= 1'b0;
            dropped_count <= 16'd0;
        end else begin
            // This is a per-cycle rejection strobe, so it may stay high on
            // adjacent rejected writes. fifo_clear discards are intentional
            // cancellations and do not count as overflow.
            overflow <= reject_input;
            if (diag_clear) begin
                overflow_sticky <= reject_input;
                dropped_count <= reject_input ? 16'd1 : 16'd0;
            end else if (reject_input) begin
                overflow_sticky <= 1'b1;
                if (dropped_count != 16'hffff)
                    dropped_count <= dropped_count + 16'd1;
            end
        end
    end

endmodule
