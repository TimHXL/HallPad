`timescale 1ns/1ps
module drum_mpu6050 #(
    parameter integer CLK_HZ=50000000,I2C_HZ=100000,SAMPLE_MS=0,STARTUP_MS=300,RETRY_MS=500
)(
    input wire clk,rst_n,ms_tick,enable,clear_faults,slot_abort,
    output wire bus_active,
    input wire [63:0] uptime_us,
    inout wire scl,sda,
    output reg online,
    output reg sample_valid,
    input wire sample_ready,
    output reg [111:0] sample_data,
    output reg [63:0] sample_time,
    output reg [15:0] error_count,
    output reg [31:0] dropped_samples,
    output reg sample_overflow,
    output reg [7:0] diagnostic_code,who_am_i,
    output wire [3:0] diagnostic_phase,
    output wire [6:0] diagnostic_address,
    output wire [1:0] diagnostic_lines,
    output reg trace_valid,output reg [111:0] trace_data
);
    localparam DELAY=0,PROBE=1,PROBE_WAIT=2,WRITE=3,WRITE_WAIT=4,SETTLE=5,POLL=6,READ_WAIT=7;
    reg [3:0] state,config_index;
    reg [15:0] delay_ms;
    reg address_bit;reg [63:0] transaction_time;
    reg start;
    reg [7:0] register_address,write_data;
    reg [3:0] read_count;
    wire done,error,busy;wire [3:0] bus_error_code;
    assign diagnostic_phase=state;
    reg [6:0] last_address;
    assign diagnostic_address=last_address;
    assign bus_active=busy || start;
    wire [111:0] read_data;
    drum_i2c_master #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ)) u_bus(
        .clk(clk),.rst_n(rst_n),.start(start),.abort(slot_abort),.device_address({6'b110100,address_bit}),
        .register_address(register_address),.write_data(write_data),.read_count(read_count),
        .scl(scl),.sda(sda),.busy(busy),.done(done),.error(error),.error_code(bus_error_code),.bus_lines(diagnostic_lines),.read_data(read_data));
    function [15:0] setup_word(input [3:0] index);begin case(index)
        0:setup_word=16'h6b01; // wake, X-gyro PLL
        1:setup_word=16'h1a02; // DLPF 2
        2:setup_word=16'h1904; // 1 kHz / 5 = 200 Hz
        3:setup_word=16'h1b18; // +/-2000 deg/s, 16.4 LSB/(deg/s)
        4:setup_word=16'h1c18; // +/-16 g, 2048 LSB/g
        default:setup_word=16'h6c00;
    endcase end endfunction
    wire [15:0] setting=setup_word(config_index);
    reg [63:0] transaction_begin;
    wire [63:0] transaction_duration=uptime_us-transaction_begin;
    // Trace all completed real transactions, including failures while offline.
    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)begin trace_valid<=0;trace_data<=0;transaction_begin<=0;end
      else begin
        trace_valid<=0;
        if((state==PROBE || state==WRITE || (state==POLL && delay_ms==0)) && enable && !busy)transaction_begin<=uptime_us;
        if(done && (state==PROBE_WAIT || state==WRITE_WAIT || state==READ_WAIT))begin
          trace_valid<=1;
          trace_data<={error_count[7:0],6'd0,diagnostic_lines,transaction_duration[31:0],4'd0,config_index,who_am_i,4'd0,bus_error_code,read_data[7:0],read_count,sample_ready,online,(!error && register_address==8'h75 && read_data[7:0]!=8'h68),error,register_address,1'b0,last_address,4'd0,state};
        end
      end
    end
    task fail_bus;begin
        online<=0;sample_valid<=0;
        if(error_count!=16'hffff) error_count<=error_count+1'b1;
        address_bit<=!address_bit;delay_ms<=RETRY_MS;state<=DELAY;
    end endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=DELAY;delay_ms<=STARTUP_MS;config_index<=0;address_bit<=0;
            start<=0;register_address<=0;write_data<=0;read_count<=0;
            online<=0;sample_valid<=0;sample_data<=0;sample_time<=0;transaction_time<=0;error_count<=0;sample_overflow<=0;dropped_samples<=0;diagnostic_code<=0;who_am_i<=0;last_address<=7'h68;
        end else begin
            start<=0;
            if(clear_faults)begin sample_overflow<=0;dropped_samples<=0;end
            if(sample_valid && sample_ready) sample_valid<=0;
            if(ms_tick && delay_ms!=0) delay_ms<=delay_ms-1'b1;
            case(state)
                DELAY:if(delay_ms==0) state<=PROBE;
                PROBE:if(enable && !busy) begin last_address<={6'b110100,address_bit};start<=1;register_address<=8'h75;read_count<=1;state<=PROBE_WAIT;end
                PROBE_WAIT:if(done) begin
                    if(!error)who_am_i<=read_data[7:0];
                    if(error || read_data[7:0]!=8'h68) begin diagnostic_code<=error ? (8'h10|{4'd0,bus_error_code}):8'h18;fail_bus();end
                    else begin config_index<=0;state<=WRITE;end
                end
                WRITE:if(enable && !busy) begin
                    start<=1;register_address<=setting[15:8];write_data<=setting[7:0];read_count<=0;state<=WRITE_WAIT;
                end
                WRITE_WAIT:if(done) begin
                    if(error)begin diagnostic_code<=8'h20|{4'd0,bus_error_code};fail_bus();end
                    else if(config_index==5) begin delay_ms<=STARTUP_MS;state<=SETTLE;end
                    else begin
                        config_index<=config_index+1'b1;
                        if(config_index==0) begin delay_ms<=10;state<=SETTLE;end else state<=WRITE;
                    end
                end
                SETTLE:if(delay_ms==0) begin
                    if(config_index==5) begin online<=1;diagnostic_code<=0;state<=POLL;end else state<=WRITE;
                end
                POLL:if(enable && delay_ms==0 && !busy) begin
                    transaction_time<=uptime_us;start<=1;register_address<=8'h3b;read_count<=14;delay_ms<=SAMPLE_MS;state<=READ_WAIT;
                end
                READ_WAIT:if(done) begin
                    if(error)begin diagnostic_code<=8'h30|{4'd0,bus_error_code};fail_bus();end
                    else begin
                        if(sample_valid && !sample_ready) begin sample_overflow<=1;dropped_samples<=dropped_samples+1'b1;end
                        else begin sample_data<=read_data;sample_time<=transaction_time;sample_valid<=1;end
                        state<=POLL;
                    end
                end
                default:begin diagnostic_code<=8'h47;fail_bus();end
            endcase
        end
    end
endmodule
