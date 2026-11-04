// Full-scan freshness guard: stale samples must never sustain a stuck voice.
// Two complete 35-key scans qualify recovery. Four incomplete scans mute;
// no complete scan for TIMEOUT_CYCLES resets the scanner/filter/map for 16 clocks.
// Isolated tag failures are tolerated. This module is NOT reset by restart.
module adc_stream_guard #(parameter integer TIMEOUT_CYCLES=500000)(
    input wire clk,rst_n,key_valid,scan_done,
    input wire [5:0] key_id,
    output reg fault,restart
);
    localparam integer CW=(TIMEOUT_CYCLES<2)?1:$clog2(TIMEOUT_CYCLES);
    reg [CW-1:0] age;
    reg [34:0] seen;
    reg [2:0] bad_scans;
    reg good_scan;
    reg [3:0] reset_count;
    wire [34:0] current_key=(key_valid && key_id<35) ? (35'b1<<key_id):35'd0;
    wire complete=scan_done && (&(seen|current_key));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            age<=0;seen<=0;bad_scans<=0;good_scan<=0;reset_count<=0;fault<=1;restart<=0;
        end else if(restart)begin
            age<=0;seen<=0;bad_scans<=0;good_scan<=0;
            if(reset_count==15)begin restart<=0;reset_count<=0;end
            else reset_count<=reset_count+1'b1;
        end else begin
            seen<=scan_done ? 35'd0:seen|current_key;
            if(complete)begin
                age<=0;bad_scans<=0;good_scan<=1;
                if(good_scan)fault<=0;
            end else begin
                if(scan_done)begin
                    good_scan<=0;
                    if(bad_scans<4)bad_scans<=bad_scans+1'b1;
                    if(bad_scans>=3)fault<=1;
                end
                if(age==TIMEOUT_CYCLES-1)begin
                    age<=0;fault<=1;restart<=1;reset_count<=0;good_scan<=0;
                end else age<=age+1'b1;
            end
        end
    end
endmodule
