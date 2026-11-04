`timescale 1ns/1ps
// One arithmetic unit shared by both IMUs. Multiply is registered; restoring
// sqrt/divide advance one digit per clock instead of inferring parallel dividers.
module drum_math(
    input wire clk,rst_n,start,
    input wire [1:0] operation, // 0: signed 32x32; 1: unsigned sqrt64; 2: u64/u32
    input wire [63:0] operand_a,
    input wire [31:0] operand_b,
    output reg busy,done,
    output reg [63:0] result
);
    reg [1:0] op;
    reg [6:0] count;
    reg [63:0] work;
    reg [33:0] remainder;
    reg [31:0] root,divisor;
    reg signed [63:0] product;
    wire [33:0] sqrt_rem={remainder[31:0],work[63:62]};
    wire [33:0] sqrt_trial={root,2'b01};
    wire [33:0] divide_rem={1'b0,remainder[31:0],work[63]};
    wire [33:0] divide_trial={2'b0,divisor};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;result<=0;op<=0;count<=0;
            work<=0;remainder<=0;root<=0;divisor<=0;product<=0;
        end else begin
            done<=0;
            if(start && !busy) begin
                busy<=1;op<=operation;count<=0;
                work<=operand_a;remainder<=0;root<=0;divisor<=operand_b;
                product<=$signed(operand_a[31:0])*$signed(operand_b);
            end else if(busy) begin
                case(op)
                    0:begin result<=product;busy<=0;done<=1;end
                    1:begin
                        work<={work[61:0],2'b0};
                        if(sqrt_rem>=sqrt_trial) begin
                            remainder<=sqrt_rem-sqrt_trial;
                            root<={root[30:0],1'b1};
                        end else begin remainder<=sqrt_rem;root<={root[30:0],1'b0};end
                        if(count==31) begin
                            result<={32'd0,root[30:0],sqrt_rem>=sqrt_trial};
                            busy<=0;done<=1;
                        end else count<=count+1'b1;
                    end
                    default:begin
                        if(divide_rem>=divide_trial) begin
                            remainder<=divide_rem-divide_trial;
                            work<={work[62:0],1'b1};
                        end else begin remainder<=divide_rem;work<={work[62:0],1'b0};end
                        if(count==63 || divisor==0) begin
                            result<=divisor==0 ? 64'd0:{work[62:0],divide_rem>=divide_trial};
                            busy<=0;done<=1;
                        end else count<=count+1'b1;
                    end
                endcase
            end
        end
    end
endmodule
