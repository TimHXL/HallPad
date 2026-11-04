module amplitude_scaler (

    input  wire signed [15:0] sine_in,
    input  wire        [6:0]  velocity,

    output wire signed [15:0] audio_out

);

    //==================================================
    // Velocity扩展成8-bit signed正数
    //
    // velocity范围：
    // 0 ~ 127
    //
    // 最高位补0，保证不会被解释成负数
    //==================================================
    wire signed [7:0] velocity_signed;

    assign velocity_signed =
        {1'b0, velocity};


    //==================================================
    // 16 bit × 8 bit = 24 bit
    //==================================================
    wire signed [23:0] product;

    assign product =
        sine_in * velocity_signed;


    //==================================================
    // 除以128，也就是右移7位
    //
    // product >>> 7 的有效结果需要17 bit：
    //
    // scaled[16]    = 符号扩展位
    // scaled[15:0]  = 实际16-bit音频
    //
    // 由于velocity最大只有127/128，
    // 输出幅度一定不会超过原16-bit输入范围，
    // 因此最高的第17位只是冗余符号位。
    //==================================================
    wire signed [16:0] scaled;

    assign scaled =
        product[23:7];


    // 显式取低16位，避免隐式17→16截断Warning
    assign audio_out =
        scaled[15:0];



endmodule