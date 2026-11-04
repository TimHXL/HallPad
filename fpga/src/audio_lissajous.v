`timescale 1ns/1ps
// Two strongest FFT components -> phase-continuous XY -> mono double buffer.
// One shared sine lookup and a six-cycle shift/add scaler; no DSP multiplier.
// FFT bin k at Fs/8 and N=2048 advances a 14-bit phase by exactly k at Fs.
module audio_lissajous #(
    parameter integer FRAME_SAMPLES=1024
)(
    input wire clk,rst_n,enable,sample_tick,
    input wire [9:0] peak_bin_x,peak_bin_y,
    input wire [17:0] peak_magnitude_x,peak_magnitude_y,
    input wire [13:0] read_address,
    input wire display_lock,
    output reg pixel,valid,
    output reg [7:0] frame_id
);
    localparam [3:0] WAIT_BANK=0,CLEAR=1,CAPTURE=2,SET_LINE=3,LINE=4,PUBLISH=5,
        SCALE=6,LOOK_X=7,MUL_X=8,STORE_X=9,LOOK_Y=10,MUL_Y=11,STORE_Y=12;
    reg [3:0] state;
    (* syn_ramstyle="block_ram" *) reg bitmap[0:32767];
    reg write_bank,front_bank,read_bank,lock_d;
    reg [13:0] clear_address;
    reg [$clog2(FRAME_SAMPLES)-1:0] sample_count;
    reg [9:0] frame_bin_x,frame_bin_y;
    reg [17:0] magnitude_x,magnitude_y;
    reg [5:0] amplitude_x,amplitude_y;
    reg [13:0] phase_x,phase_y;
    wire [10:0] sine_phase=state==LOOK_Y ? phase_y[13:3]:phase_x[13:3];
    wire signed [15:0] sine_value;
    audio_monitor_sine sine_rom(.phase(sine_phase),.value(sine_value));
    reg signed [13:0] scale_sum,scale_term;
    reg [5:0] scale_factor;
    reg [2:0] scale_count;
    wire signed [13:0] coordinate_delta=scale_sum>>>7;
    wire signed [13:0] mapped_x=14'sd64+coordinate_delta;
    wire signed [13:0] mapped_y=14'sd63-coordinate_delta;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin phase_x<=0;phase_y<=0;end
        else if(enable && sample_tick)begin
            phase_x<=phase_x+{4'd0,frame_bin_x};
            phase_y<=phase_y+{4'd0,frame_bin_y};
        end
    end

    reg have_previous;
    reg [6:0] previous_x,previous_y,pen_x,pen_y,target_x,target_y;
    reg [7:0] delta_x,delta_y;
    reg step_x_positive,step_y_positive;
    reg signed [9:0] error;
    wire signed [10:0] twice_error=$signed({error[9],error})<<<1;
    wire move_x=twice_error>=-$signed({3'd0,delta_y});
    wire move_y=twice_error<=$signed({3'd0,delta_x});
    wire signed [10:0] next_error=$signed({error[9],error})-
        (move_x ? $signed({3'd0,delta_y}):11'sd0)+
        (move_y ? $signed({3'd0,delta_x}):11'sd0);
    wire [7:0] distance_x=target_x>=pen_x ? {1'b0,target_x}-{1'b0,pen_x}:{1'b0,pen_x}-{1'b0,target_x};
    wire [7:0] distance_y=target_y>=pen_y ? {1'b0,target_y}-{1'b0,pen_y}:{1'b0,pen_y}-{1'b0,target_y};
    wire leased_bank=(display_lock && !lock_d) ? front_bank:read_bank;
    wire writable=!(display_lock && valid && leased_bank==write_bank);
    wire bitmap_write=enable && (state==CLEAR || state==LINE);
    wire [14:0] bitmap_address={write_bank,(state==CLEAR ? clear_address:{pen_y,pen_x})};
    always @(posedge clk)begin
        if(rst_n && bitmap_write)bitmap[bitmap_address]<=state==LINE;
        if(rst_n && valid)pixel<=bitmap[{read_bank,read_address}];else pixel<=0;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=WAIT_BANK;write_bank<=0;front_bank<=0;read_bank<=0;lock_d<=0;
            clear_address<=0;sample_count<=0;have_previous<=0;
            frame_bin_x<=0;frame_bin_y<=0;magnitude_x<=0;magnitude_y<=0;amplitude_x<=0;amplitude_y<=0;
            scale_sum<=0;scale_term<=0;scale_factor<=0;scale_count<=0;
            previous_x<=0;previous_y<=0;pen_x<=0;pen_y<=0;target_x<=0;target_y<=0;
            delta_x<=0;delta_y<=0;step_x_positive<=0;step_y_positive<=0;error<=0;
            valid<=0;frame_id<=0;
        end else begin
            lock_d<=display_lock;
            if(display_lock && !lock_d)read_bank<=front_bank;
            if(!enable)begin state<=WAIT_BANK;have_previous<=0;end
            else case(state)
                WAIT_BANK:if(writable)begin
                    // The FFT publishes both bins and amplitudes atomically.
                    frame_bin_x<=peak_bin_x;frame_bin_y<=peak_bin_y;
                    magnitude_x<=peak_magnitude_x;magnitude_y<=peak_magnitude_y;
                    clear_address<=0;sample_count<=0;have_previous<=0;state<=SCALE;
                end
                SCALE:begin
                    // Common power-of-two gain preserves relative peak strength.
                    // Serial normalization avoids a wide priority/barrel shifter.
                    if(magnitude_x>63)begin magnitude_x<=magnitude_x>>1;magnitude_y<=magnitude_y>>1;end
                    else if(magnitude_x!=0 && magnitude_x<32)begin magnitude_x<=magnitude_x<<1;magnitude_y<=magnitude_y<<1;end
                    else begin amplitude_x<=magnitude_x[5:0];amplitude_y<=magnitude_y[5:0];state<=CLEAR;end
                end
                CLEAR:if(clear_address==16383)state<=CAPTURE;
                    else clear_address<=clear_address+1'b1;
                CAPTURE:if(sample_tick)state<=LOOK_X;
                LOOK_X,LOOK_Y:begin
                    scale_sum<=0;scale_term<={{6{sine_value[15]}},sine_value[15:8]};
                    scale_factor<=state==LOOK_X ? amplitude_x:amplitude_y;scale_count<=0;
                    state<=state==LOOK_X ? MUL_X:MUL_Y;
                end
                MUL_X,MUL_Y:begin
                    if(scale_factor[0])scale_sum<=scale_sum+scale_term;
                    scale_term<=scale_term<<<1;scale_factor<=scale_factor>>1;
                    if(scale_count==5)state<=state==MUL_X ? STORE_X:STORE_Y;
                    else scale_count<=scale_count+1'b1;
                end
                STORE_X:begin target_x<=mapped_x[6:0];state<=LOOK_Y;end
                STORE_Y:begin
                    target_y<=mapped_y[6:0];
                    pen_x<=have_previous ? previous_x:target_x;
                    pen_y<=have_previous ? previous_y:mapped_y[6:0];state<=SET_LINE;
                end
                SET_LINE:begin
                    delta_x<=distance_x;delta_y<=distance_y;
                    step_x_positive<=pen_x<target_x;step_y_positive<=pen_y<target_y;
                    error<=$signed({2'd0,distance_x})-$signed({2'd0,distance_y});state<=LINE;
                end
                LINE:begin
                    if(pen_x==target_x && pen_y==target_y)begin
                        previous_x<=target_x;previous_y<=target_y;have_previous<=1;
                        if(sample_count==FRAME_SAMPLES-1)state<=PUBLISH;
                        else begin sample_count<=sample_count+1'b1;state<=CAPTURE;end
                    end else begin
                        if(move_x)pen_x<=step_x_positive ? pen_x+1'b1:pen_x-1'b1;
                        if(move_y)pen_y<=step_y_positive ? pen_y+1'b1:pen_y-1'b1;
                        error<=next_error[9:0];
                    end
                end
                PUBLISH:begin
                    front_bank<=write_bank;write_bank<=!write_bank;
                    valid<=1;frame_id<=frame_id+1'b1;state<=WAIT_BANK;
                end
                default:state<=WAIT_BANK;
            endcase
        end
    end
endmodule

