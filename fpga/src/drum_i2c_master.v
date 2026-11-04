`timescale 1ns/1ps
// Register transaction master, 100 kHz by default. Both pins are true open drain.
// START, repeated START, per-byte ACK, last-byte NACK, STOP, stretch timeout,
// and nine-clock stuck-SDA recovery are implemented in the system clock domain.
module drum_i2c_master #(
    parameter integer CLK_HZ=50000000,I2C_HZ=100000,STRETCH_US=200
)(
    input wire clk,rst_n,start,abort,
    input wire [6:0] device_address,
    input wire [7:0] register_address,write_data,
    input wire [3:0] read_count, // zero writes one byte, 1..14 reads a burst
    inout wire scl,sda,
    output reg busy,done,error,
    output reg [3:0] error_code,
    output wire [1:0] bus_lines,
    output reg [111:0] read_data
);
    localparam integer HALF=(CLK_HZ/(I2C_HZ*2)<2)?2:CLK_HZ/(I2C_HZ*2);
    localparam integer TIMEOUT=(CLK_HZ/1000000*STRETCH_US<8)?8:CLK_HZ/1000000*STRETCH_US;
    localparam IDLE=0,BUS_FREE=1,START_HOLD=2,TX_LOW=3,TX_HIGH=4,
        ACK_LOW=5,ACK_HIGH=6,RESTART_LOW=7,RESTART_HIGH=8,
        RX_LOW=9,RX_HIGH=10,MASTER_ACK_LOW=11,MASTER_ACK_HIGH=12,
        STOP_LOW=13,STOP_HIGH=14,STOP_RELEASE=15,RECOVER_LOW=16,RECOVER_HIGH=17;
    reg [4:0] state;
    reg scl_low,sda_low;
    reg [1:0] scl_sync,sda_sync;
    reg [15:0] timer;
    reg [31:0] stretch_count;
    reg [7:0] tx,rx,reg_address,data_write;
    reg [6:0] address;
    reg [3:0] bytes_to_read,byte_index,recovery_count;
    reg [2:0] bit_index;
    reg [1:0] stage;
    reg recover_then_start;
    assign scl=scl_low ? 1'b0:1'bz;
    assign sda=sda_low ? 1'b0:1'bz;
    assign bus_lines={scl_sync[1],sda_sync[1]};
    wire high_phase=state==BUS_FREE || state==TX_HIGH || state==ACK_HIGH ||
        state==RESTART_HIGH || state==RX_HIGH || state==MASTER_ACK_HIGH ||
        state==STOP_HIGH || state==RECOVER_HIGH;
    wire stretched=high_phase && !scl_low && !scl_sync[1];
    wire advance=timer==HALF-1 && !stretched;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin scl_sync<=3;sda_sync<=3;end
        else begin scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;scl_low<=0;sda_low<=0;timer<=0;stretch_count<=0;
            tx<=0;rx<=0;reg_address<=0;data_write<=0;address<=0;
            bytes_to_read<=0;byte_index<=0;bit_index<=0;stage<=0;
            recovery_count<=0;recover_then_start<=0;
            busy<=0;done<=0;error<=0;error_code<=0;read_data<=0;
        end else begin
            done<=0;
            if(abort && busy)begin
                scl_low<=0;sda_low<=0;state<=IDLE;busy<=0;done<=1;error<=1;error_code<=7;
                timer<=0;stretch_count<=0;
            end else if(state==IDLE) begin
                timer<=0;stretch_count<=0;
                if(start) begin
                    busy<=1;error<=0;error_code<=0;read_data<=0;address<=device_address;
                    reg_address<=register_address;data_write<=write_data;
                    bytes_to_read<=read_count;byte_index<=0;stage<=0;
                    recovery_count<=0;recover_then_start<=0;
                    scl_low<=0;sda_low<=0;state<=BUS_FREE;
                end
            end else if(stretched) begin
                timer<=0;
                if(stretch_count>=TIMEOUT-1) begin
                    scl_low<=0;sda_low<=0;state<=IDLE;busy<=0;done<=1;error<=1;error_code<=5;
                    stretch_count<=0;
                end else stretch_count<=stretch_count+1'b1;
            end else begin
                stretch_count<=0;
                if(!advance) timer<=timer+1'b1;
                else begin
                    timer<=0;
                    case(state)
                        BUS_FREE:if(!sda_sync[1]) begin
                            scl_low<=1;sda_low<=0;recovery_count<=0;
                            recover_then_start<=1;state<=RECOVER_LOW;
                        end else begin sda_low<=1;state<=START_HOLD;end
                        START_HOLD:begin
                            scl_low<=1;tx<={address,1'b0};bit_index<=7;
                            sda_low<=!address[6];stage<=0;state<=TX_LOW;
                        end
                        TX_LOW:begin scl_low<=0;state<=TX_HIGH;end
                        TX_HIGH:begin
                            scl_low<=1;
                            if(bit_index==0) begin sda_low<=0;state<=ACK_LOW;end
                            else begin bit_index<=bit_index-1'b1;sda_low<=!tx[bit_index-1'b1];state<=TX_LOW;end
                        end
                        ACK_LOW:begin scl_low<=0;state<=ACK_HIGH;end
                        ACK_HIGH:begin
                            scl_low<=1;
                            if(sda_sync[1]) begin error<=1;error_code<=stage==0?1:stage==1?2:stage==2?3:4;sda_low<=1;state<=STOP_LOW;end
                            else case(stage)
                                0:begin tx<=reg_address;bit_index<=7;sda_low<=!reg_address[7];stage<=1;state<=TX_LOW;end
                                1:if(bytes_to_read!=0) begin sda_low<=0;state<=RESTART_LOW;end
                                  else begin tx<=data_write;bit_index<=7;sda_low<=!data_write[7];stage<=2;state<=TX_LOW;end
                                2:begin sda_low<=1;state<=STOP_LOW;end
                                3:begin sda_low<=0;bit_index<=7;rx<=0;state<=RX_LOW;end
                            endcase
                        end
                        RESTART_LOW:begin scl_low<=0;state<=RESTART_HIGH;end
                        RESTART_HIGH:begin sda_low<=1;state<=START_HOLD;
                            // START_HOLD normally loads address+W. The next state
                            // is overridden below for the repeated START+R.
                            stage<=3;
                        end
                        RX_LOW:begin scl_low<=0;state<=RX_HIGH;end
                        RX_HIGH:begin
                            scl_low<=1;rx<={rx[6:0],sda_sync[1]};
                            if(bit_index==0) begin
                                read_data[byte_index*8 +:8]<={rx[6:0],sda_sync[1]};
                                sda_low<=byte_index+1'b1<bytes_to_read;
                                state<=MASTER_ACK_LOW;
                            end else begin bit_index<=bit_index-1'b1;state<=RX_LOW;end
                        end
                        MASTER_ACK_LOW:begin scl_low<=0;state<=MASTER_ACK_HIGH;end
                        MASTER_ACK_HIGH:begin
                            scl_low<=1;
                            if(byte_index+1'b1>=bytes_to_read) begin sda_low<=1;state<=STOP_LOW;end
                            else begin byte_index<=byte_index+1'b1;bit_index<=7;rx<=0;sda_low<=0;state<=RX_LOW;end
                        end
                        STOP_LOW:begin scl_low<=0;state<=STOP_HIGH;end
                        STOP_HIGH:begin sda_low<=0;state<=STOP_RELEASE;end
                        STOP_RELEASE:begin
                            if(recover_then_start) begin
                                recover_then_start<=0;
                                if(!sda_sync[1]) begin error<=1;error_code<=6;busy<=0;done<=1;state<=IDLE;end
                                else state<=BUS_FREE;
                            end else begin busy<=0;done<=1;state<=IDLE;end
                        end
                        RECOVER_LOW:begin scl_low<=0;state<=RECOVER_HIGH;end
                        RECOVER_HIGH:begin
                            scl_low<=1;
                            if(recovery_count==8) begin sda_low<=1;state<=STOP_LOW;end
                            else begin recovery_count<=recovery_count+1'b1;state<=RECOVER_LOW;end
                        end
                        default:begin state<=IDLE;scl_low<=0;sda_low<=0;busy<=0;done<=1;error<=1;error_code<=7;end
                    endcase
                    if(state==START_HOLD && stage==3) begin
                        tx<={address,1'b1};stage<=3;
                    end
                end
            end
        end
    end
endmodule
