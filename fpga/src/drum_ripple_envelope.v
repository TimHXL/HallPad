`timescale 1ns / 1ps

// Runtime width/decay for the persistent palette scheduler.
// width: milli-cells; speed: milli-cells/s; decay_ms: exponential time constant.
// A reached pixel stays bright for width/speed seconds, then its highlight
// decays towards a 22% retained color, exactly as in the register-only worker.
// The 160-pixel worker uses synchronous RAM instead of a wide
// register read mux and a broadcast write bus. Only the visible highlights and
// per-pixel validity/tick flags remain local flops. No derived clocks/dividers.
// One sweep is 480 clocks/ms; ms_tick spacing must be >=481 clocks.
module drum_ripple_envelope (
    input wire clk, rst_n, ms_tick,
    input wire [159:0] arrivals,
    input wire [7:0] arrival_index,
    input wire [17:0] speed,
    input wire [11:0] width,
    input wire [12:0] decay_ms,
    output wire [1439:0] intensities
);
    localparam [1:0] IDLE=0, READ=1, UPDATE=2, WRITE=3;
    localparam [8:0] RETAINED=9'd56;
    localparam [7:0] HIGHLIGHT=8'd200;
    localparam [43:0] INITIAL_STATE={1'b1,22'd0,HIGHLIGHT,13'd0};
    reg [1:0] state;
    reg [7:0] index;
    reg [30:0] parameters_q;
    reg parameters_valid_q;
    wire [17:0] tick_speed=parameters_valid_q ? parameters_q[30:13]:18'd80000;
    wire [12:0] tick_decay=parameters_valid_q ? parameters_q[12:0]:13'd1200;
    reg [21:0] tick_width_limit;
    wire [17:0] bounded_speed = speed < 40000 ? 18'd40000 : speed > 200000 ? 18'd200000 : speed;
    wire [11:0] bounded_width = width < 300 ? 12'd300 : width > 3000 ? 12'd3000 : width;
    wire [12:0] bounded_decay = decay_ms < 200 ? 13'd200 : decay_ms > 5000 ? 13'd5000 : decay_ms;
    wire [21:0] width_limit = ({10'd0,bounded_width} << 10) -
                             ({10'd0,bounded_width} << 4) -
                             ({10'd0,bounded_width} << 3);

    (* syn_ramstyle="block_ram" *) reg [43:0] pixel_state[0:255];
    reg [43:0] state_q;
    // Parameters belong to the wave that reached each pixel, never live UI settings.
    (* syn_ramstyle="block_ram" *) reg [30:0] parameters[0:255];


    wire [159:0] parameters_valid;
    reg initialized_q;
    wire [159:0] initialized, pending_tick;
    // RAM contents need no reset or initialization file: reset/arrival clears
    // only the local validity flag, selecting the explicit default word.
    wire [43:0] read_state=initialized_q ? state_q:INITIAL_STATE;
    wire holding_q=read_state[43];
    wire [21:0] hold_q=read_state[42:21];
    wire [7:0] highlight_q=read_state[20:13];
    wire [12:0] fraction_q=read_state[12:0];
    reg result_holding;
    reg [21:0] result_hold;
    reg [7:0] result_highlight;
    reg [12:0] result_fraction;
    wire [22:0] hold_sum = {1'b0,hold_q} + {5'd0,tick_speed};
    wire [13:0] fade_sum = {1'b0,fraction_q} + {6'd0,highlight_q};
    wire [13:0] fade_remainder = fade_sum - {1'b0,tick_decay};
    wire write_pixel=rst_n && !ms_tick && state==WRITE &&
                     pending_tick[index] && !arrivals[index];
    // Read on READ, calculate on UPDATE, write on WRITE: the synchronous RAM
    // adds no sweep cycles. An arrival on any stage cancels the stale result.
    always @(posedge clk) begin
        if(state==READ)begin state_q<=pixel_state[index];parameters_q<=parameters[index];end
        if(|arrivals) parameters[arrival_index]<={bounded_speed,bounded_decay};
        if(write_pixel) pixel_state[index]<=
            {result_holding,result_hold,result_highlight,result_fraction};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; index<=0; parameters_valid_q<=0;
            tick_width_limit<=1000000; initialized_q<=0;
            result_holding<=0; result_hold<=0;
            result_highlight<=0; result_fraction<=0;
        end else if (ms_tick) begin
            state<=READ; index<=0;
            tick_width_limit<=width_limit;
        end else case (state)
            IDLE: begin end
            READ: begin parameters_valid_q<=parameters_valid[index];initialized_q<=initialized[index]; state<=UPDATE; end
            UPDATE: begin
                result_holding<=holding_q; result_hold<=hold_q;
                result_highlight<=highlight_q; result_fraction<=fraction_q;
                if (holding_q) begin
                    if (hold_sum >= {1'b0,tick_width_limit}) begin
                        result_holding<=0; result_hold<=0;
                    end else result_hold<=hold_sum[21:0];
                end else if (highlight_q != 0) begin
                    // Fractional error diffusion retains the previous exact
                    // exponential decay, including a live tau reduction.
                    if (fraction_q >= tick_decay) result_fraction<=0;
                    else if (fade_sum >= {1'b0,tick_decay}) begin
                        result_highlight<=highlight_q-1'b1;
                        result_fraction<=fade_remainder[12:0];
                    end else result_fraction<=fade_sum[12:0];
                end
                state<=WRITE;
            end
            WRITE: begin
                if (index==159) state<=IDLE;
                else begin index<=index+1'b1; state<=READ; end
            end
            default: state<=IDLE;
        endcase
    end

    genvar led;
    generate for (led=0; led<160; led=led+1) begin:g_pixel
        reg valid, tick_pending,has_parameters;
        reg [7:0] visible_highlight;
        // Compare the constant LED address locally; don't distribute the RAM
        // word across a register bank. Arrival always wins over worker writes.
        wire selected_write=!ms_tick && state==WRITE && index==led && tick_pending;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                valid<=0; tick_pending<=0;has_parameters<=0; visible_highlight<=HIGHLIGHT;
            end else begin
                if (ms_tick) tick_pending<=!arrivals[led];
                else if (arrivals[led]) tick_pending<=0;
                else if (state==WRITE && index==led) tick_pending<=0;
                if (arrivals[led]) begin
                    valid<=0;has_parameters<=1; visible_highlight<=HIGHLIGHT;
                end else if (selected_write) begin
                    valid<=1; visible_highlight<=result_highlight;
                end
            end
        end
        assign parameters_valid[led]=has_parameters;
        assign initialized[led]=valid;
        assign pending_tick[led]=tick_pending;
        assign intensities[led*9 +:9]=RETAINED+{1'b0,visible_highlight};
    end endgenerate
endmodule
