// HallPad speaker path. TI SLAS671C sections 6.3.10.14, 6.3.11 and register map.
// Source: https://www.ti.com/lit/ds/symlink/tlv320dac3100.pdf
// Analog routing matches HallPad_F407_UART/Firmware/Core/Src/audio.c.
// MCLK=12.5 MHz; PLL P=R=1,J=7,D=8643 ->98.30375 MHz.
// NDAC=4,MDAC=4,DOSR=128 ->47999.8779297 Hz; DAC_CLK/16 ->32 BCLK/frame.
// PRB_P1 RC=8 <= MDAC*DOSR/32=16. DAC_CLK24.5759375 MHz has headroom
// below49.152 MHz. Codec is BCLK/WCLK MASTER; FPGA must receive both clocks.
// FPGA-only keeps digital 0 dB, analog -12 dB and ClassD +6 dB.
// AUX uses the existing master-volume target at the common analog control.
// Dual input adds 6 dB attenuation and uses full FPGA volume before the limiter.
// Per-input gains/mix-ratio parameters are intentionally not introduced.
// configured means register writes ACKed and settling delay elapsed; it is not
// analog output/readback verification. No hardware clock-lock readback exists here.
module tlv320dac3100_init #(
    parameter [7:0] DIGITAL_VOLUME=8'h00,
    parameter integer CLK_HZ=50000000,I2C_HZ=100000,
    RESET_HOLD_CYCLES=5000000,RESET_RELEASE_CYCLES=250000,
    SOFT_RESET_CYCLES=250000,PLL_SETTLE_CYCLES=1000000,
    ANALOG_SETTLE_CYCLES=5000000,I2C_TIMEOUT_CYCLES=50000,
    RETRY_DELAY_CYCLES=CLK_HZ/2
)(
    input wire clk,rst_n,restart,play_enable,audio_clock_good,hard_fault,
    input wire [1:0] audio_input_mask,
    input wire mute_all,
    input wire [6:0] volume_percent,
    input wire route_valid,
    input wire [1:0] route_target_mask,
    output wire route_ready,
    output reg route_done,route_error,
    inout wire scl,sda,
    output reg codec_reset_n,configured,playing,error,
    output reg [3:0] error_code
);
    localparam [3:0] RESET_HOLD=0,RESET_RELEASE=1,ISSUE=2,WAIT_WRITE=3,
        SETTLE=4,RUN=5,RUNTIME_ISSUE=6,RUNTIME_WAIT=7,FAILED=8;
    reg [3:0] state,runtime_index;
    reg [5:0] index;
    reg [31:0] delay_count,delay_limit;
    reg request,dac_unmuted,speaker_unmuted;
    reg runtime_dac_target,runtime_speaker_target,runtime_speaker_written,runtime_command;
    reg [1:0] applied_mask,runtime_mask;
    reg [6:0] applied_attenuation,runtime_attenuation;
    reg [7:0] reg_addr,reg_data;
    wire i2c_busy,i2c_done,i2c_error;
    wire [3:0] i2c_error_code;
    wire master_rst_n=rst_n && !restart && !error && !hard_fault;
    wire [1:0] next_mask=route_valid && route_ready ? route_target_mask:audio_input_mask;
    wire desired_dac=play_enable && audio_clock_good && next_mask[0] && !mute_all && volume_percent!=0;
    // Analog AIN bypass does not depend on Hall calibration or the synth engine.
    wire desired_speaker=!mute_all && volume_percent!=0 && (next_mask[1] || desired_dac);
    // Half-dB codec steps approximate the existing linear master-volume target.
    // No additional attenuation when DAC and AIN share the mixer.
    wire [6:0] desired_attenuation=next_mask[1] ?
        volume_attenuation(volume_percent):7'd0;
    assign route_ready=rst_n && configured && state==RUN && !error && !route_done;
    i2c_master #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ),.TIMEOUT_CYCLES(I2C_TIMEOUT_CYCLES)) bus_writer(
        .clk(clk),.rst_n(master_rst_n),.start(request),.device_addr(7'h18),
        .register_addr(reg_addr),.write_data(reg_data),.scl(scl),.sda(sda),
        .busy(i2c_busy),.done(i2c_done),.error(i2c_error),.error_code(i2c_error_code));
    function [6:0] volume_attenuation(input [6:0] percent);
        begin case(percent)
            7'd1: volume_attenuation=7'd80;
            7'd2: volume_attenuation=7'd68;
            7'd3: volume_attenuation=7'd61;
            7'd4: volume_attenuation=7'd56;
            7'd5: volume_attenuation=7'd52;
            7'd6: volume_attenuation=7'd49;
            7'd7: volume_attenuation=7'd46;
            7'd8: volume_attenuation=7'd44;
            7'd9: volume_attenuation=7'd42;
            7'd10: volume_attenuation=7'd40;
            7'd11: volume_attenuation=7'd38;
            7'd12: volume_attenuation=7'd37;
            7'd13: volume_attenuation=7'd35;
            7'd14: volume_attenuation=7'd34;
            7'd15: volume_attenuation=7'd33;
            7'd16: volume_attenuation=7'd32;
            7'd17: volume_attenuation=7'd31;
            7'd18: volume_attenuation=7'd30;
            7'd19: volume_attenuation=7'd29;
            7'd20: volume_attenuation=7'd28;
            7'd21: volume_attenuation=7'd27;
            7'd22: volume_attenuation=7'd26;
            7'd23: volume_attenuation=7'd26;
            7'd24: volume_attenuation=7'd25;
            7'd25: volume_attenuation=7'd24;
            7'd26: volume_attenuation=7'd23;
            7'd27: volume_attenuation=7'd23;
            7'd28: volume_attenuation=7'd22;
            7'd29: volume_attenuation=7'd22;
            7'd30: volume_attenuation=7'd21;
            7'd31: volume_attenuation=7'd20;
            7'd32: volume_attenuation=7'd20;
            7'd33: volume_attenuation=7'd19;
            7'd34: volume_attenuation=7'd19;
            7'd35: volume_attenuation=7'd18;
            7'd36: volume_attenuation=7'd18;
            7'd37: volume_attenuation=7'd17;
            7'd38: volume_attenuation=7'd17;
            7'd39: volume_attenuation=7'd16;
            7'd40: volume_attenuation=7'd16;
            7'd41: volume_attenuation=7'd15;
            7'd42: volume_attenuation=7'd15;
            7'd43: volume_attenuation=7'd15;
            7'd44: volume_attenuation=7'd14;
            7'd45: volume_attenuation=7'd14;
            7'd46: volume_attenuation=7'd13;
            7'd47: volume_attenuation=7'd13;
            7'd48: volume_attenuation=7'd13;
            7'd49: volume_attenuation=7'd12;
            7'd50: volume_attenuation=7'd12;
            7'd51: volume_attenuation=7'd12;
            7'd52: volume_attenuation=7'd11;
            7'd53: volume_attenuation=7'd11;
            7'd54: volume_attenuation=7'd11;
            7'd55: volume_attenuation=7'd10;
            7'd56: volume_attenuation=7'd10;
            7'd57: volume_attenuation=7'd10;
            7'd58: volume_attenuation=7'd9;
            7'd59: volume_attenuation=7'd9;
            7'd60: volume_attenuation=7'd9;
            7'd61: volume_attenuation=7'd9;
            7'd62: volume_attenuation=7'd8;
            7'd63: volume_attenuation=7'd8;
            7'd64: volume_attenuation=7'd8;
            7'd65: volume_attenuation=7'd7;
            7'd66: volume_attenuation=7'd7;
            7'd67: volume_attenuation=7'd7;
            7'd68: volume_attenuation=7'd7;
            7'd69: volume_attenuation=7'd6;
            7'd70: volume_attenuation=7'd6;
            7'd71: volume_attenuation=7'd6;
            7'd72: volume_attenuation=7'd6;
            7'd73: volume_attenuation=7'd5;
            7'd74: volume_attenuation=7'd5;
            7'd75: volume_attenuation=7'd5;
            7'd76: volume_attenuation=7'd5;
            7'd77: volume_attenuation=7'd5;
            7'd78: volume_attenuation=7'd4;
            7'd79: volume_attenuation=7'd4;
            7'd80: volume_attenuation=7'd4;
            7'd81: volume_attenuation=7'd4;
            7'd82: volume_attenuation=7'd3;
            7'd83: volume_attenuation=7'd3;
            7'd84: volume_attenuation=7'd3;
            7'd85: volume_attenuation=7'd3;
            7'd86: volume_attenuation=7'd3;
            7'd87: volume_attenuation=7'd2;
            7'd88: volume_attenuation=7'd2;
            7'd89: volume_attenuation=7'd2;
            7'd90: volume_attenuation=7'd2;
            7'd91: volume_attenuation=7'd2;
            7'd92: volume_attenuation=7'd1;
            7'd93: volume_attenuation=7'd1;
            7'd94: volume_attenuation=7'd1;
            7'd95: volume_attenuation=7'd1;
            7'd96: volume_attenuation=7'd1;
            7'd97: volume_attenuation=7'd1;
            7'd98: volume_attenuation=7'd0;
            7'd99: volume_attenuation=7'd0;
            7'd100: volume_attenuation=7'd0;
            default:volume_attenuation=7'd80;
        endcase end
    endfunction
    function [15:0] init_word;
        input [5:0] i;
        begin
            case(i)
                0: init_word=16'h0000; // page0
                1: init_word=16'h0101; // software reset; wait5ms
                2: init_word=16'h0403; // PLL input MCLK; codec clock PLL
                3: init_word=16'h0511; // PLLoff, P1/R1
                4: init_word=16'h0607; // J7
                5: init_word=16'h0721; // D8643 high; next write must be R8
                6: init_word=16'h08C3; // D8643 low
                7: init_word=16'h0591; // PLLon; wait20ms before clock dividers
                8: init_word=16'h0B84; // NDAC4, on
                9: init_word=16'h0C84; // MDAC4, on
               10: init_word=16'h0D00; // DOSR MSB; next write must be R14
               11: init_word=16'h0E80; // DOSR128
               12: init_word=16'h1B0C; // I2S16, BCLK/WCLK output
               13: init_word=16'h1C00; // zero additional data offset
               14: init_word=16'h1D00; // normal BCLK, sourceDAC_CLK
               15: init_word=16'h1E90; // BCLK divider16, on
               16: init_word=16'h3C01; // PRB_P1
               17: init_word=16'h400C; // digital mute both channels
               18: init_word={8'h41,DIGITAL_VOLUME}; // left default 0dB
               19: init_word={8'h42,DIGITAL_VOLUME}; // right default 0dB
               20: init_word=16'h3FD4; // both DACs powered, L/R routing
               21: init_word=16'h0001; // page1
               22: init_word=16'h1F14; // common-mode1.65V; HPs remain off
               23: init_word=16'h2340; // left DAC routed to output mixer
               24: init_word=16'h2680; // speaker analog attenuation 0dB for both single and mixed sources
               25: init_word=16'h2A00; // ClassD muted, minimum6dB driver gain
               26: init_word=16'h2086; // ClassD power; wait100ms
               27: init_word=16'h2A00; // remain muted until runtime route is installed
               28: init_word=16'h0000; // leave page0 for runtime mute writes
              default: init_word=16'h400C;
            endcase
        end
    endfunction


    function [15:0] runtime_word(input [3:0] i);
        begin case(i)
            0:runtime_word=16'h0001;
            1:runtime_word=16'h2a00; // mute Class-D before changing the mixer
            2:runtime_word={8'h23,1'b0,runtime_mask[0],{2{runtime_mask[1]}},4'b0000};
            3:runtime_word={8'h26,1'b1,runtime_attenuation};
            4:runtime_word=16'h0000;
            5:runtime_word={8'h40,runtime_dac_target ? 8'h00:8'h0c};
            6:runtime_word=16'h0001;
            7:runtime_word={8'h2a,(runtime_speaker_target && !mute_all && volume_percent!=0) ? 8'h04:8'h00};
            default:runtime_word=16'h0000; // restore page 0 for every transaction
        endcase end
    endfunction
    task start_runtime(input command_request);
        begin
            runtime_mask<=next_mask;runtime_dac_target<=desired_dac;
            runtime_speaker_target<=desired_speaker;runtime_attenuation<=desired_attenuation;
            runtime_command<=command_request;runtime_index<=0;state<=RUNTIME_ISSUE;
        end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=RESET_HOLD;index<=0;delay_count<=0;delay_limit<=0;
            request<=0;reg_addr<=0;reg_data<=0;dac_unmuted<=0;speaker_unmuted<=0;
            codec_reset_n<=0;configured<=0;playing<=0;error<=0;error_code<=0;
            runtime_index<=0;runtime_mask<=1;applied_mask<=1;
            runtime_dac_target<=0;runtime_speaker_target<=0;runtime_speaker_written<=0;
            runtime_attenuation<=24;applied_attenuation<=24;runtime_command<=0;
            route_done<=0;route_error<=0;
        end else if(restart)begin
            state<=RESET_HOLD;index<=0;delay_count<=0;delay_limit<=0;
            request<=0;reg_addr<=0;reg_data<=0;dac_unmuted<=0;speaker_unmuted<=0;
            codec_reset_n<=0;configured<=0;playing<=0;error<=0;error_code<=0;
            runtime_index<=0;runtime_mask<=1;applied_mask<=1;
            runtime_dac_target<=0;runtime_speaker_target<=0;runtime_speaker_written<=0;
            runtime_attenuation<=24;applied_attenuation<=24;runtime_command<=0;
            route_done<=0;route_error<=0;
        end else if((hard_fault || i2c_error) && state!=FAILED)begin
            // Any partial routing is made inaudible immediately by RESET.
            // The config owner keeps its old word; retry restores that word.
            state<=FAILED;codec_reset_n<=0;configured<=0;playing<=0;
            delay_count<=0;request<=0;dac_unmuted<=0;speaker_unmuted<=0;error<=1;
            if(!error)error_code<=hard_fault ? 4'h8:i2c_error_code;
            route_done<=runtime_command;route_error<=runtime_command;runtime_command<=0;
        end else begin
            request<=0;route_done<=0;route_error<=0;
            playing<=configured && speaker_unmuted && !mute_all && volume_percent!=0 && state==RUN;
            case(state)
                RESET_HOLD:if(delay_count>=RESET_HOLD_CYCLES-1)begin codec_reset_n<=1;delay_count<=0;state<=RESET_RELEASE;end else delay_count<=delay_count+1'b1;
                RESET_RELEASE:if(delay_count>=RESET_RELEASE_CYCLES-1)begin delay_count<=0;index<=0;state<=ISSUE;end else delay_count<=delay_count+1'b1;
                ISSUE:if(!i2c_busy)begin {reg_addr,reg_data}<=init_word(index);request<=1;state<=WAIT_WRITE;end
                WAIT_WRITE:if(i2c_done)begin
                    if(index==28)begin configured<=1;state<=RUN;end
                    else begin
                        index<=index+1'b1;delay_count<=0;
                        if(index==1)begin delay_limit<=SOFT_RESET_CYCLES;state<=SETTLE;end
                        else if(index==7)begin delay_limit<=PLL_SETTLE_CYCLES;state<=SETTLE;end
                        else if(index==26)begin delay_limit<=ANALOG_SETTLE_CYCLES;state<=SETTLE;end
                        else state<=ISSUE;
                    end
                end
                SETTLE:if(delay_count>=delay_limit-1)begin delay_count<=0;state<=ISSUE;end else delay_count<=delay_count+1'b1;
                RUN:if(!route_done)begin
                    if(route_valid && route_ready)start_runtime(1'b1);
                    else if(audio_input_mask!=applied_mask || desired_dac!=dac_unmuted || desired_speaker!=speaker_unmuted || desired_attenuation!=applied_attenuation)start_runtime(1'b0);
                end
                RUNTIME_ISSUE:if(!i2c_busy)begin
                    {reg_addr,reg_data}<=runtime_word(runtime_index);
                    if(runtime_index==7)runtime_speaker_written<=runtime_speaker_target && !mute_all && volume_percent!=0;
                    request<=1;state<=RUNTIME_WAIT;
                end
                RUNTIME_WAIT:if(i2c_done)begin
                    if(runtime_index==1)speaker_unmuted<=0;
                    if(runtime_index==8)begin
                        applied_mask<=runtime_mask;applied_attenuation<=runtime_attenuation;
                        dac_unmuted<=runtime_dac_target;speaker_unmuted<=runtime_speaker_written;
                        route_done<=runtime_command;runtime_command<=0;state<=RUN;
                    end else begin runtime_index<=runtime_index+1'b1;state<=RUNTIME_ISSUE;end
                end
                FAILED:begin
                    codec_reset_n<=0;configured<=0;playing<=0;request<=0;
                    if(delay_count>=RETRY_DELAY_CYCLES-1)begin
                        state<=RESET_HOLD;index<=0;delay_count<=0;delay_limit<=0;
                        reg_addr<=0;reg_data<=0;dac_unmuted<=0;speaker_unmuted<=0;
                        applied_mask<=1;applied_attenuation<=24;runtime_command<=0;
                        error<=0;error_code<=0;
                    end else delay_count<=delay_count+1'b1;
                end
                default:begin state<=FAILED;codec_reset_n<=0;configured<=0;playing<=0;error<=1;error_code<=4'hf;end
            endcase
        end
    end
endmodule
