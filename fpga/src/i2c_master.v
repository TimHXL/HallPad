// Single-master, write-only I2C: START, address+W, register, data, STOP.
// All pins are open drain. External pull-ups to the correct IOVDD are required.
// start is accepted only while idle and error=0. done pulses for either outcome;
// error is sticky until rst_n=0. No automatic retry or stuck-bus clock pulses.
// error_code: 1/2/3=NACK address/register/data, 4=bus busy, 5=SCL timeout,
//             6=SDA conflict or STOP did not release the bus.
module i2c_master #(
    parameter integer CLK_HZ = 50000000,
    parameter integer I2C_HZ = 100000,
    parameter integer TIMEOUT_CYCLES = 50000
) (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [6:0] device_addr,
    input wire [7:0] register_addr,
    input wire [7:0] write_data,
    inout wire scl,
    inout wire sda,
    output reg busy,
    output reg done,
    output reg error,
    output reg [3:0] error_code
);
    localparam integer HALF_CYCLES_RAW = CLK_HZ / (2 * I2C_HZ);
    localparam integer HALF_CYCLES = HALF_CYCLES_RAW < 4 ? 4 : HALF_CYCLES_RAW;
    localparam integer LIMIT = TIMEOUT_CYCLES < 8 ? 8 : TIMEOUT_CYCLES;
    localparam [3:0] IDLE=0, BUS_FREE=1, START_HOLD=2, BIT_LOW=3,
        BIT_RISE=4, BIT_HIGH=5, STOP_LOW=6, STOP_RISE=7,
        STOP_HIGH=8, STOP_FREE=9, LOCKED=10;
    reg [3:0] state;
    reg scl_low, sda_low;
    (* syn_async_reg = "true" *) reg scl_meta, scl_sync, sda_meta, sda_sync;
    localparam integer PHASE_W=$clog2(HALF_CYCLES+1),WAIT_W=$clog2(LIMIT+1);
    reg [PHASE_W-1:0] phase_count;
    reg [WAIT_W-1:0] wait_count;
    reg [23:0] shift;
    reg [2:0] bit_index;
    reg [1:0] byte_index;
    reg ack_phase;
    reg [3:0] pending_error;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_meta<=1'b1; scl_sync<=1'b1;
            sda_meta<=1'b1; sda_sync<=1'b1;
        end else begin
            scl_meta<=scl; scl_sync<=scl_meta;
            sda_meta<=sda; sda_sync<=sda_meta;
        end
    end

    task fail_now;
        input [3:0] code;
        begin
            scl_low<=0; sda_low<=0; busy<=0; done<=1;
            error<=1; error_code<=code; state<=LOCKED;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; scl_low<=0; sda_low<=0;
            busy<=0; done<=0; error<=0; error_code<=0;
            phase_count<=0; wait_count<=0; shift<=0;
            bit_index<=7; byte_index<=0; ack_phase<=0; pending_error<=0;
        end else begin
            done<=0;
            case (state)
                IDLE: if (start) begin
                    shift<={device_addr,1'b0,register_addr,write_data};
                    busy<=1; phase_count<=0; wait_count<=0;
                    bit_index<=7; byte_index<=0; ack_phase<=0;
                    pending_error<=0; state<=BUS_FREE;
                end
                BUS_FREE: begin
                    if (scl_sync && sda_sync) begin
                        if (phase_count==HALF_CYCLES-1) begin
                            sda_low<=1; phase_count<=0; wait_count<=0;
                            state<=START_HOLD;
                        end else phase_count<=phase_count+1'b1;
                    end else phase_count<=0;
                    if (wait_count==LIMIT-1) fail_now(4);
                    else wait_count<=wait_count+1'b1;
                end
                START_HOLD: begin
                    if (phase_count==HALF_CYCLES-1) begin
                        scl_low<=1; sda_low<=!shift[23];
                        phase_count<=0; state<=BIT_LOW;
                    end else phase_count<=phase_count+1'b1;
                end
                BIT_LOW: begin
                    if (phase_count==HALF_CYCLES-1) begin
                        scl_low<=0; phase_count<=0; wait_count<=0;
                        state<=BIT_RISE;
                    end else phase_count<=phase_count+1'b1;
                end
                BIT_RISE: begin
                    if (scl_sync) begin
                        phase_count<=0; wait_count<=0; state<=BIT_HIGH;
                    end else if (wait_count==LIMIT-1) fail_now(5);
                    else wait_count<=wait_count+1'b1;
                end
                BIT_HIGH: begin
                    // Hold the high phase from the observed rise, including stretching.
                    if (!scl_sync) begin
                        phase_count<=0;
                        if (wait_count==LIMIT-1) fail_now(5);
                        else wait_count<=wait_count+1'b1;
                    end else if (phase_count==HALF_CYCLES-1) begin
                        phase_count<=0; wait_count<=0; scl_low<=1;
                        if (ack_phase) begin
                            ack_phase<=0;
                            if (sda_sync) begin
                                pending_error<={2'b00,byte_index}+1'b1;
                                sda_low<=1; state<=STOP_LOW;
                            end else if (byte_index==2) begin
                                sda_low<=1; state<=STOP_LOW;
                            end else begin
                                byte_index<=byte_index+1'b1; bit_index<=7;
                                sda_low<=!shift[23]; state<=BIT_LOW;
                            end
                        end else if (shift[23] && !sda_sync) begin
                            pending_error<=6; sda_low<=1; state<=STOP_LOW;
                        end else begin
                            shift<={shift[22:0],1'b0}; state<=BIT_LOW;
                            if (bit_index==0) begin
                                ack_phase<=1; sda_low<=0;
                            end else begin
                                bit_index<=bit_index-1'b1; sda_low<=!shift[22];
                            end
                        end
                    end else phase_count<=phase_count+1'b1;
                end
                STOP_LOW: begin
                    if (phase_count==HALF_CYCLES-1) begin
                        scl_low<=0; phase_count<=0; wait_count<=0; state<=STOP_RISE;
                    end else phase_count<=phase_count+1'b1;
                end
                STOP_RISE: begin
                    if (scl_sync) begin
                        phase_count<=0; wait_count<=0; state<=STOP_HIGH;
                    end else if (wait_count==LIMIT-1) fail_now(5);
                    else wait_count<=wait_count+1'b1;
                end
                STOP_HIGH: begin
                    if (phase_count==HALF_CYCLES-1) begin
                        sda_low<=0; phase_count<=0; wait_count<=0; state<=STOP_FREE;
                    end else phase_count<=phase_count+1'b1;
                end
                STOP_FREE: begin
                    if (scl_sync && sda_sync) begin
                        if (phase_count==HALF_CYCLES-1) begin
                            busy<=0; done<=1;
                            if (pending_error!=0) begin
                                error<=1; error_code<=pending_error; state<=LOCKED;
                            end else state<=IDLE;
                        end else phase_count<=phase_count+1'b1;
                    end else phase_count<=0;
                    if (wait_count==LIMIT-1) fail_now(6);
                    else wait_count<=wait_count+1'b1;
                end
                LOCKED: begin scl_low<=0; sda_low<=0; busy<=0; end
                default: fail_now(6);
            endcase
        end
    end

endmodule
