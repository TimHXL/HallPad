// Debounce helper retained for the rotary encoder.
// The unused old sampling_controls top module was removed.
module sampling_debounce #(
    parameter integer WIDTH = 1,
    parameter integer STABLE_CYCLES = 500000
) (
    input wire clk, rst_n,
    input wire [WIDTH-1:0] pins,
    output reg [WIDTH-1:0] level,
    output reg ready
);
    localparam integer CW = (STABLE_CYCLES < 2) ? 1 : $clog2(STABLE_CYCLES);
    localparam [CW-1:0] LAST = STABLE_CYCLES - 1;
    (* syn_preserve = 1 *) reg [WIDTH-1:0] meta, synced;
    reg [WIDTH-1:0] candidate;
    reg [CW-1:0] count;
    reg [2:0] warmup;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta <= {WIDTH{1'b1}}; synced <= {WIDTH{1'b1}};
            candidate <= {WIDTH{1'b1}}; level <= {WIDTH{1'b1}};
            count <= 0; warmup <= 0; ready <= 0;
        end else begin
            meta <= pins; synced <= meta;
            warmup <= {warmup[1:0], 1'b1};
            if (!warmup[2] || synced != candidate) begin
                candidate <= synced;
                count <= 0;
            end else if (count == LAST) begin
                level <= candidate;
                ready <= 1;
            end else count <= count + 1'b1;
        end
    end
endmodule
