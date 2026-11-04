`timescale 1ns/1ps
// Side-chain only: the monitor never stalls, rescales, or clocks the audio path.
// 48kHz -> anti-alias FIR /8 -> 6kHz -> 2048-point rolling Hann FFT.
// A 256-sample hop updates analysis every 42.67ms without losing resolution.
// Scope is independently triggered; two display banks stay immutable while read.
module audio_visualizer(input wire clk,rst_n,sample_tick,
    input wire signed [15:0] pcm_in,
    input wire [7:0] scope_address,spectrum_address,
    input wire scope_lock,spectrum_lock,
    output wire [7:0] scope_y,spectrum_height,
    output wire scope_valid,spectrum_valid,analysis_overrun,
    output wire [7:0] scope_frame,spectrum_frame,
    output wire [9:0] peak_bin_x,peak_bin_y,
    output wire [17:0] peak_magnitude_x,peak_magnitude_y);
    wire filtered_valid;wire signed [15:0] filtered;
    audio_monitor_filter filter(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(pcm_in),
        .pcm_out(filtered),.out_valid(filtered_valid),.overrun(analysis_overrun));
    audio_monitor_scope scope(.clk(clk),.rst_n(rst_n),.sample_valid(filtered_valid),.pcm_in(filtered),
        .read_address(scope_address),.display_lock(scope_lock),.sample_y(scope_y),.valid(scope_valid),.frame_id(scope_frame));
    audio_monitor_fft fft(.clk(clk),.rst_n(rst_n),.sample_valid(filtered_valid),.pcm_in(filtered),
        .read_address(spectrum_address),.display_lock(spectrum_lock),.height(spectrum_height),.valid(spectrum_valid),.frame_id(spectrum_frame),
        .peak_bin_x(peak_bin_x),.peak_bin_y(peak_bin_y),.peak_magnitude_x(peak_magnitude_x),.peak_magnitude_y(peak_magnitude_y),.peaks_update());
endmodule

module audio_monitor_filter(input wire clk,rst_n,sample_tick,
    input wire signed [15:0] pcm_in,output reg signed [15:0] pcm_out,
    output reg out_valid,overrun);
    (* syn_ramstyle="block_ram" *) reg signed [15:0] history[0:127];
    reg clearing;reg [6:0] clear_pointer,write_pointer,read_pointer,tap;
    reg [2:0] decimate;
    reg [1:0] state;
    reg signed [15:0] sample_q;
    wire signed [15:0] coefficient;
    reg signed [31:0] product;
    reg signed [39:0] accumulator;
    wire signed [39:0] total=accumulator+$signed({{8{product[31]}},product});
    wire signed [39:0] scaled=total>>>16;
    audio_monitor_coefficient coefficients(.address(tap),.value(coefficient));
    always @(posedge clk)begin
        if(rst_n && (clearing || sample_tick))history[clearing ? clear_pointer:write_pointer]<=clearing ? 16'sd0:pcm_in;
        if(rst_n && state==1)sample_q<=history[read_pointer];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            clearing<=1;clear_pointer<=0;write_pointer<=0;read_pointer<=0;tap<=0;
            decimate<=0;state<=0;product<=0;accumulator<=0;pcm_out<=0;out_valid<=0;overrun<=0;
        end else begin
            out_valid<=0;
            if(clearing)begin
                if(clear_pointer==127)begin clearing<=0;clear_pointer<=0;end else clear_pointer<=clear_pointer+1'b1;
            end else begin
                if(sample_tick)begin
                    write_pointer<=write_pointer+1'b1;decimate<=decimate+1'b1;
                    if(decimate==7)begin
                        if(state!=0)overrun<=1;
                        else begin read_pointer<=write_pointer;tap<=0;accumulator<=0;state<=1;end
                    end
                end
                case(state)
                    1:state<=2;
                    2:begin product<=sample_q*coefficient;state<=3;end
                    3:begin
                        if(tap==127)begin
                            pcm_out<=scaled>32767 ? 16'sd32767:scaled< -32768 ? -16'sd32768:scaled[15:0];
                            out_valid<=1;state<=0;
                        end else begin accumulator<=total;tap<=tap+1'b1;read_pointer<=read_pointer-1'b1;state<=1;end
                    end
                    default:begin end
                endcase
            end
        end
    end
endmodule

module audio_monitor_scope(input wire clk,rst_n,sample_valid,
    input wire signed [15:0] pcm_in,input wire [7:0] read_address,
    input wire display_lock,output reg [7:0] sample_y,output reg valid,output reg [7:0] frame_id);
    (* syn_ramstyle="block_ram" *) reg [7:0] samples[0:511];
    reg write_bank,front_bank,read_bank,lock_d,capturing;
    reg [7:0] pointer;
    reg [8:0] timeout;
    reg signed [15:0] previous;
    wire trigger=(previous<0 && pcm_in>=0) || timeout==511;
    wire leased_bank=(display_lock && !lock_d) ? front_bank:read_bank;
    wire writable=!(display_lock && valid && leased_bank==write_bank);
    wire signed [16:0] y=17'sd64-($signed({pcm_in[15],pcm_in})>>>9);
    wire [7:0] bounded_y=y<0 ? 8'd0:y>127 ? 8'd127:y[7:0];
    always @(posedge clk)begin
        if(rst_n && sample_valid && writable && (capturing || trigger))
            samples[{write_bank,(capturing ? pointer:8'd0)}]<=bounded_y;
        if(rst_n && valid)sample_y<=samples[{read_bank,read_address}];else sample_y<=64;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            write_bank<=0;front_bank<=0;read_bank<=0;lock_d<=0;capturing<=0;
            pointer<=0;timeout<=0;previous<=0;valid<=0;frame_id<=0;
        end else begin
            lock_d<=display_lock;
            if(display_lock && !lock_d)read_bank<=front_bank;
            if(sample_valid)begin
                previous<=pcm_in;
                if(writable)begin
                    if(capturing)begin
                        if(pointer==191)begin
                            front_bank<=write_bank;write_bank<=!write_bank;valid<=1;frame_id<=frame_id+1'b1;capturing<=0;pointer<=0;timeout<=0;
                        end else pointer<=pointer+1'b1;
                    end else if(trigger)begin capturing<=1;pointer<=1;timeout<=0;end
                    else timeout<=timeout+1'b1;
                end else begin capturing<=0;pointer<=0;timeout<=0;end
            end
        end
    end
endmodule

// Radix-2 DIT, bit-reversed acquisition, one shared multiplier for window and
// all complex rotations. Each stage divides by two; 18-bit words retain guard
// bits. Acquisition runs in a separate rolling RAM even during transforms.
// Display backpressure discards an obsolete completed graph, never PCM samples.
module audio_monitor_fft(input wire clk,rst_n,sample_valid,
    input wire signed [15:0] pcm_in,input wire [7:0] read_address,
    input wire display_lock,output reg [7:0] height,output reg valid,output reg [7:0] frame_id,
    output reg [9:0] peak_bin_x,peak_bin_y,
    output reg [17:0] peak_magnitude_x,peak_magnitude_y,output reg peaks_update);
    localparam [4:0] PEAK_BEGIN=6,PEAK_FINISH=7,PEAK_SWITCH=21,
        CAPTURE=0,COPY_READ=1,COPY_LATCH=2,WINDOW_SET=3,WINDOW_MUL=4,WINDOW_WRITE=5,
        READ_A=8,LATCH_A=9,READ_B=10,LATCH_B=11,M0=12,M1=13,M2=14,M3=15,M4=16,M5=17,
        ROTATE=18,WRITE_A=19,WRITE_B=20,SCAN_SETUP=24,SCAN_READ=25,SCAN_ACC=26,SCAN_STORE=27,PUBLISH=28,SCAN_ABSOLUTE=29,SCAN_MAGNITUDE=30;
    reg [4:0] state;
    (* syn_ramstyle="block_ram" *) reg signed [15:0] history[0:2047];
    reg clearing,frame_pending,discard_frame;
    reg [10:0] clear_pointer,write_pointer,capture_base;
    reg [7:0] hop_count;
    reg signed [15:0] history_sample;
    reg [10:0] input_index,half_length,j,twiddle_step,twiddle;
    wire [10:0] history_address=capture_base+input_index;
    // Clear only this RAM, once after reset. No reset mux on individual words.
    always @(posedge clk)begin
        if(rst_n && (clearing || sample_valid))history[clearing ? clear_pointer:write_pointer]<=clearing ? 16'sd0:pcm_in;
        if(rst_n && state==COPY_READ)history_sample<=history[history_address];
    end
    (* syn_ramstyle="block_ram" *) reg [35:0] data[0:2047];
    (* syn_ramstyle="block_ram" *) reg [7:0] columns[0:511];
    reg [35:0] read_word,a_word,b_word;
    reg [11:0] group_base;
    reg signed [15:0] input_sample,cosine_q,sine_q;
    wire [10:0] trig_phase=state<8 ? input_index:twiddle;
    wire [10:0] cosine_phase=trig_phase+11'd512;
    wire signed [15:0] sine_value,cosine_value;
    reg signed [15:0] trig_sine_q,trig_cosine_q;
    always @(posedge clk)begin trig_sine_q<=sine_value;trig_cosine_q<=cosine_value;end
    audio_monitor_sine sine_rom(.phase(trig_phase),.value(sine_value));
    audio_monitor_sine cosine_rom(.phase(cosine_phase),.value(cosine_value));
    wire signed [16:0] window_difference=17'sd32767-$signed({trig_cosine_q[15],trig_cosine_q});
    reg signed [18:0] operand_a;
    reg signed [16:0] operand_b;
    reg signed [35:0] multiplier,p0,p1,p2,p3;
    reg signed [19:0] rotated_re,rotated_im;
    wire signed [36:0] rotation_re_sum=$signed({p0[35],p0})+$signed({p1[35],p1});
    wire signed [36:0] rotation_im_sum=$signed({p2[35],p2})-$signed({p3[35],p3});
    wire signed [17:0] ar=a_word[35:18],ai=a_word[17:0],br=b_word[35:18],bi=b_word[17:0];
    wire signed [20:0] plus_re=$signed({{3{ar[17]}},ar})+$signed({rotated_re[19],rotated_re});
    wire signed [20:0] plus_im=$signed({{3{ai[17]}},ai})+$signed({rotated_im[19],rotated_im});
    wire signed [20:0] minus_re=$signed({{3{ar[17]}},ar})-$signed({rotated_re[19],rotated_re});
    wire signed [20:0] minus_im=$signed({{3{ai[17]}},ai})-$signed({rotated_im[19],rotated_im});
    wire [10:0] address_a=group_base[10:0]+j,address_b=address_a+half_length;
    wire [17:0] windowed=multiplier[32:15];
    function [10:0] reverse_bits(input [10:0] v);
        integer n;begin for(n=0;n<11;n=n+1)reverse_bits[n]=v[10-n];end
    endfunction
    reg peak_scan,peak_second;
    wire [9:0] selected_bin_x,selected_bin_y;
    wire [17:0] selected_magnitude_x,selected_magnitude_y;
    reg [7:0] column;
    reg [10:0] scan_bin,scan_end;
    wire [10:0] column_low,column_high;
    audio_monitor_band bands(.address(column),.low_bin(column_low),.high_bin(column_high));
    reg [17:0] peak,abs_re_q,abs_im_q,magnitude_q;
    wire signed [17:0] scan_re=read_word[35:18],scan_im=read_word[17:0];
    wire [17:0] abs_re=scan_re[17] ? -scan_re:scan_re,abs_im=scan_im[17] ? -scan_im:scan_im;
    wire [17:0] magnitude=abs_re_q>abs_im_q ? abs_re_q+(abs_im_q>>1):abs_im_q+(abs_re_q>>1);
    wire [17:0] next_peak=magnitude_q>peak ? magnitude_q:peak;
    audio_monitor_peaks pick_peaks(
        .clk(clk),.rst_n(rst_n),.start_pass(state==PEAK_BEGIN),.second_pass(peak_second),
        .sample_valid(peak_scan && state==SCAN_ACC),.finish_pass(state==PEAK_FINISH),
        .bin(scan_bin[9:0]),.magnitude(magnitude_q),
        .first_bin(selected_bin_x),.second_bin(selected_bin_y),
        .first_magnitude(selected_magnitude_x),.second_magnitude(selected_magnitude_y));
    reg write_bank,front_bank,read_bank,lock_d;
    wire leased_bank=(display_lock && !lock_d) ? front_bank:read_bank;
    wire writable=!(display_lock && valid && leased_bank==write_bank);
    function [7:0] level(input [17:0] v);
        integer n,exponent,fraction,result;
        begin
            exponent=0;
            for(n=0;n<18;n=n+1)if(v[n])exponent=n;
            fraction=exponent>=3 ? (v>>(exponent-3))&7:0;
            result=(exponent-3)*12+(fraction*3)/2;
            level=v<8 ? 8'd0:result>127 ? 8'd127:result<0 ? 8'd0:result[7:0];
        end
    endfunction
    // One physical write port and one synchronous read port. Address/data
    // selection is outside the RAM template so inference cannot create three
    // independent write ports and fall back to distributed RAM.
    wire fft_write_enable=state==WINDOW_WRITE || state==WRITE_A || state==WRITE_B;
    wire [10:0] fft_write_address=state==WINDOW_WRITE ? reverse_bits(input_index):state==WRITE_A ? address_a:address_b;
    wire [35:0] fft_write_data=state==WINDOW_WRITE ? {windowed,18'd0}:state==WRITE_A ? {plus_re[18:1],plus_im[18:1]}:{minus_re[18:1],minus_im[18:1]};
    wire fft_read_enable=state==READ_A || state==READ_B || state==SCAN_READ;
    wire [10:0] fft_read_address=state==READ_A ? address_a:state==READ_B ? address_b:scan_bin;
    always @(posedge clk)begin
        multiplier<=operand_a*operand_b;
        if(rst_n)begin
            if(fft_write_enable)data[fft_write_address]<=fft_write_data;
            if(fft_read_enable)read_word<=data[fft_read_address];
            if(state==SCAN_STORE && writable)columns[{write_bank,column}]<=level(peak);
        end
        if(rst_n && valid)height<=columns[{read_bank,read_address}];else height<=0;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=CAPTURE;input_index<=0;half_length<=1;j<=0;twiddle_step<=1024;twiddle<=0;group_base<=0;
            input_sample<=0;cosine_q<=0;sine_q<=0;operand_a<=0;operand_b<=0;
            a_word<=0;b_word<=0;p0<=0;p1<=0;p2<=0;p3<=0;rotated_re<=0;rotated_im<=0;
            column<=0;scan_bin<=0;scan_end<=0;peak<=0;abs_re_q<=0;abs_im_q<=0;magnitude_q<=0;
            peak_scan<=0;peak_second<=0;peak_bin_x<=0;peak_bin_y<=0;peak_magnitude_x<=0;peak_magnitude_y<=0;peaks_update<=0;
            write_bank<=0;front_bank<=0;read_bank<=0;lock_d<=0;valid<=0;frame_id<=0;
            clearing<=1;clear_pointer<=0;write_pointer<=0;capture_base<=0;hop_count<=0;frame_pending<=0;discard_frame<=0;
        end else begin
            peaks_update<=0;
            lock_d<=display_lock;
            if(display_lock && !lock_d)read_bank<=front_bank;
            if(clearing)begin
                if(clear_pointer==2047)clearing<=0;else clear_pointer<=clear_pointer+1'b1;
            end else begin
                if(sample_valid)begin
                    write_pointer<=write_pointer+1'b1;hop_count<=hop_count+1'b1;
                    if(hop_count==255)frame_pending<=1;
                end
                case(state)
                CAPTURE:if(frame_pending)begin
                    capture_base<=write_pointer+{10'd0,sample_valid};input_index<=0;
                    frame_pending<=sample_valid && hop_count==255;state<=COPY_READ;
                end
                COPY_READ:state<=COPY_LATCH;
                COPY_LATCH:begin input_sample<=history_sample;state<=WINDOW_SET;end
                WINDOW_SET:begin operand_a<=input_sample;operand_b<=window_difference>>>1;state<=WINDOW_MUL;end
                WINDOW_MUL:state<=WINDOW_WRITE;
                WINDOW_WRITE:begin
                    if(input_index==2047)begin half_length<=1;j<=0;group_base<=0;twiddle_step<=1024;twiddle<=0;state<=READ_A;end
                    else begin input_index<=input_index+1'b1;state<=COPY_READ;end
                end
                READ_A:state<=LATCH_A;
                LATCH_A:begin a_word<=read_word;cosine_q<=trig_cosine_q;sine_q<=trig_sine_q;state<=READ_B;end
                READ_B:state<=LATCH_B;
                LATCH_B:begin b_word<=read_word;state<=M0;end
                M0:begin operand_a<=br;operand_b<=cosine_q;state<=M1;end
                M1:begin operand_a<=bi;operand_b<=sine_q;state<=M2;end
                M2:begin p0<=multiplier;operand_a<=bi;operand_b<=cosine_q;state<=M3;end
                M3:begin p1<=multiplier;operand_a<=br;operand_b<=sine_q;state<=M4;end
                M4:begin p2<=multiplier;state<=M5;end
                M5:begin p3<=multiplier;state<=ROTATE;end
                ROTATE:begin
                    rotated_re<=rotation_re_sum[34:15];
                    rotated_im<=rotation_im_sum[34:15];state<=WRITE_A;
                end
                WRITE_A:state<=WRITE_B;
                WRITE_B:begin
                    if(j+1<half_length)begin j<=j+1'b1;twiddle<=twiddle+twiddle_step;state<=READ_A;end
                    else if(group_base+({1'b0,half_length}<<1)<2048)begin
                        group_base<=group_base+({1'b0,half_length}<<1);j<=0;twiddle<=0;state<=READ_A;
                    end else if(half_length==1024)begin peak_scan<=1;peak_second<=0;state<=PEAK_BEGIN;end
                    else begin half_length<=half_length<<1;twiddle_step<=twiddle_step>>1;j<=0;twiddle<=0;group_base<=0;state<=READ_A;end
                end
                PEAK_BEGIN:begin scan_bin<=16;state<=SCAN_READ;end
                PEAK_FINISH:state<=PEAK_SWITCH;
                PEAK_SWITCH:begin
                    if(!peak_second)begin peak_second<=1;state<=PEAK_BEGIN;end
                    else begin
                        peak_bin_x<=selected_bin_x;peak_bin_y<=selected_bin_y;
                        peak_magnitude_x<=selected_magnitude_x;peak_magnitude_y<=selected_magnitude_y;peaks_update<=1;
                        peak_scan<=0;column<=0;state<=SCAN_SETUP;
                    end
                end
                SCAN_SETUP:begin scan_bin<=column_low;scan_end<=column_high;peak<=0;if(column==0)discard_frame<=0;state<=SCAN_READ;end
                SCAN_READ:state<=SCAN_ABSOLUTE;
                SCAN_ABSOLUTE:begin abs_re_q<=abs_re;abs_im_q<=abs_im;state<=SCAN_MAGNITUDE;end
                SCAN_MAGNITUDE:begin magnitude_q<=magnitude;state<=SCAN_ACC;end
                SCAN_ACC:begin
                    if(peak_scan)begin
                        if(scan_bin==1023)state<=PEAK_FINISH;
                        else begin scan_bin<=scan_bin+1'b1;state<=SCAN_READ;end
                    end else begin
                        peak<=next_peak;
                        if(scan_bin==scan_end)state<=SCAN_STORE;else begin scan_bin<=scan_bin+1'b1;state<=SCAN_READ;end
                    end
                end
                SCAN_STORE:begin
                    if(!writable)discard_frame<=1;
                    if(column==191)state<=PUBLISH;else begin column<=column+1'b1;state<=SCAN_SETUP;end
                end
                PUBLISH:begin
                    if(!discard_frame && writable)begin
                        front_bank<=write_bank;write_bank<=!write_bank;valid<=1;frame_id<=frame_id+1'b1;
                    end
                    state<=CAPTURE;
                end
                default:state<=CAPTURE;
                endcase
            end
        end
    end
endmodule
