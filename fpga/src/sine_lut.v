module sine_lut (
    input  wire [31:0] phase_acc,
    output reg  signed [15:0] sine_out
);

    // 取32位相位累加器最高4位
    // 4位可以表示0~15，一共16个相位点
    wire [3:0] addr;

    assign addr = phase_acc[31:28];

    always @(*) begin
        case (addr)

            4'd0:  sine_out =  16'sd0;
            4'd1:  sine_out =  16'sd12539;
            4'd2:  sine_out =  16'sd23170;
            4'd3:  sine_out =  16'sd30273;

            4'd4:  sine_out =  16'sd32767;
            4'd5:  sine_out =  16'sd30273;
            4'd6:  sine_out =  16'sd23170;
            4'd7:  sine_out =  16'sd12539;

            4'd8:  sine_out =  16'sd0;
            4'd9:  sine_out = -16'sd12539;
            4'd10: sine_out = -16'sd23170;
            4'd11: sine_out = -16'sd30273;

            4'd12: sine_out = -16'sd32767;
            4'd13: sine_out = -16'sd30273;
            4'd14: sine_out = -16'sd23170;
            4'd15: sine_out = -16'sd12539;

            default: sine_out = 16'sd0;

        endcase
    end


endmodule