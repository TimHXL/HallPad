`timescale 1ns/1ps
// Four damped 7/8 feedback combs, with independent reflection times and two
// all-pass diffusers. Wet normalization is 6 dB stronger than the old network.
// The original dry attack is preserved by the additive, smoothly slewed mixer.
module music_reverb(input wire clk,rst_n,sample_tick,
    input wire signed [23:0] pcm_in,output wire signed [23:0] pcm_out);
    wire signed [23:0] c0,c1,c2,c3,scattered;
    reg signed [24:0] pair0,pair1;
    reg signed [25:0] sum;
    reg signed [23:0] combined;
    reg [1:0] state;
    music_room_comb #(.DELAY(1151)) c_0(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(pcm_in),.pcm_out(c0));
    music_room_comb #(.DELAY(1373)) c_1(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(pcm_in),.pcm_out(c1));
    music_room_comb #(.DELAY(1699)) c_2(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(pcm_in),.pcm_out(c2));
    music_room_comb #(.DELAY(1907)) c_3(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(pcm_in),.pcm_out(c3));
    music_allpass #(.DELAY(193),.RAM_BITS(8)) a_0(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(combined),.pcm_out(scattered));
    music_allpass #(.DELAY(347),.RAM_BITS(9)) a_1(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.pcm_in(scattered),.pcm_out(pcm_out));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin pair0<=0;pair1<=0;sum<=0;combined<=0;state<=0;end
        else if(sample_tick)begin
            pair0<=$signed({c0[23],c0})+$signed({c1[23],c1});
            pair1<=$signed({c2[23],c2})+$signed({c3[23],c3});state<=1;
        end else case(state)
            1:begin sum<=$signed({pair0[24],pair0})+$signed({pair1[24],pair1});state<=2;end
            2:begin combined<=(sum>>>1)>8388607 ? 24'sd8388607:(sum>>>1)< -8388608 ? -24'sd8388608:sum[24:1];state<=0;end
            default:state<=0;
        endcase
    end
endmodule

module music_room_comb #(parameter integer DELAY=1151)(
    input wire clk,rst_n,sample_tick,input wire signed [23:0] pcm_in,
    output reg signed [23:0] pcm_out);
    (* syn_ramstyle="block_ram" *) reg signed [23:0] memory[0:2047];
    reg clearing;reg [10:0] clear_pointer,pointer;
    reg [2:0] state;
    reg signed [23:0] delayed,damped,dry;
    reg signed [24:0] damp_sum;
    reg signed [27:0] feedback_product;
    reg signed [25:0] feedback,write_value;
    wire signed [24:0] damped_full=damp_sum[24] ? -((-damp_sum)>>>1):damp_sum>>>1;
    wire signed [27:0] feedback_full=feedback_product[27] ? -((-feedback_product)>>>3):feedback_product>>>3;
    function signed [23:0] clip24(input signed [25:0] value);
        begin clip24=value>8388607 ? 24'sd8388607:value< -8388608 ? -24'sd8388608:value[23:0];end
    endfunction
    always @(posedge clk)begin
        if(rst_n && clearing)memory[clear_pointer]<=0;
        else if(rst_n && state==6)memory[pointer]<=clip24(write_value);
        if(rst_n && !clearing && sample_tick && state==0)delayed<=memory[pointer];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            clearing<=1;clear_pointer<=0;pointer<=0;state<=0;
            damped<=0;dry<=0;damp_sum<=0;feedback_product<=0;feedback<=0;write_value<=0;pcm_out<=0;
        end else if(clearing)begin
            if(clear_pointer==2047)begin clearing<=0;clear_pointer<=0;end else clear_pointer<=clear_pointer+1'b1;
        end else if(sample_tick && state==0)begin dry<=pcm_in;state<=1;end
        else case(state)
            1:begin damp_sum<=$signed({delayed[23],delayed})+$signed({damped[23],damped});state<=2;end
            2:begin damped<=damped_full[23:0];state<=3;end
            3:begin feedback_product<=damped*4'sd7;state<=4;end
            4:begin feedback<=feedback_full[25:0];state<=5;end
            5:begin write_value<=($signed({{2{dry[23]}},dry})>>>1)+feedback;state<=6;end
            6:begin pcm_out<=delayed;pointer<=pointer==DELAY-1 ? 11'd0:pointer+1'b1;state<=0;end
            default:state<=0;
        endcase
    end
endmodule

// Unity-magnitude all-pass: y=z-x/2; write=x+y/2. Wide delay words keep
// intermediate diffusion peaks without chopping their waveform.
module music_allpass #(parameter integer DELAY=223,RAM_BITS=8)(
    input wire clk,rst_n,sample_tick,input wire signed [23:0] pcm_in,
    output reg signed [23:0] pcm_out);
    (* syn_ramstyle="block_ram" *) reg signed [25:0] memory[0:(1<<RAM_BITS)-1];
    reg clearing;
    reg [RAM_BITS-1:0] clear_pointer,pointer;
    reg [2:0] state;
    reg signed [23:0] dry;
    reg signed [25:0] delayed,allpass_value;
    reg signed [26:0] write_value;
    function signed [23:0] clip24(input signed [25:0] v);
        begin clip24=v>26'sd8388607 ? 24'sd8388607 : v< -26'sd8388608 ? -24'sd8388608 : v[23:0];end
    endfunction
    always @(posedge clk)begin
        if(rst_n && clearing)memory[clear_pointer]<=0;
        else if(rst_n && state==3)memory[pointer]<=write_value[25:0];
        if(rst_n && !clearing && sample_tick && state==0)delayed<=memory[pointer];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            clearing<=1;clear_pointer<=0;pointer<=0;state<=0;
            dry<=0;allpass_value<=0;write_value<=0;pcm_out<=0;
        end else if(clearing)begin
            if(&clear_pointer)begin clearing<=0;clear_pointer<=0;end
            else clear_pointer<=clear_pointer+1'b1;
        end else if(sample_tick && state==0)begin dry<=pcm_in;state<=1;end
        else case(state)
            1:begin allpass_value<=delayed-($signed({{2{dry[23]}},dry})>>>1);state<=2;end
            2:begin write_value<=$signed({{3{dry[23]}},dry})+($signed({allpass_value[25],allpass_value})>>>1);state<=3;end
            3:begin pcm_out<=clip24(allpass_value);pointer<=pointer==DELAY-1 ? {RAM_BITS{1'b0}} : pointer+1'b1;state<=0;end
            default:state<=0;
        endcase
    end
endmodule
