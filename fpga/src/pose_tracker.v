`timescale 1ns/1ps
// Q4.28 quaternion, one sequential arithmetic unit per stick. Reference frame
// is the sensor orientation at calibration. All math clocked at board 50 MHz.
// dt is measured at acquisition; no angle resets on a hit or on axial rotation.
module pose_tracker(
 input wire clk,rst_n,clear,online,calibrated,sample_valid,
 input wire [111:0] sample_data,cal_result,input wire [31:0] sample_ms,
 output wire sample_ready,output reg vector_valid,
 output reg signed [31:0] wx,wy,wz,output reg neutral,quiet,
 output reg fault,output reg [127:0] attitude);
 localparam signed [31:0] ONE=268435456;
 localparam IDLE=0,MATRIX=1,MATRIX_SAVE=2,GRAV=3,GRAV_SAVE=4,
 CROSS=5,CROSS_SAVE=6,STEP=7,STEP_SAVE=8,DERIV=9,DERIV_SAVE=10,
 NORM=11,NORM_SAVE=12,ROOT_SAVE=13,DIV=14,DIV_SAVE=15,
 WORLD=16,WORLD_SAVE=17,WAIT=31;
 reg [4:0] state,ret;reg [3:0] ix;reg had_cal,have_time;
 reg signed [31:0] q[0:3],qn[0:3],m[0:8],g[0:2],a[0:2],w[0:2],cor[0:2],step[0:2];
 reg signed [31:0] terms[0:8],tmp,accum,operand_x,operand_y;
 reg [63:0] norm_sum;reg [31:0] norm_q,last_ms;reg [3:0] dt;reg calm;
 wire [31:0] sample_interval=sample_ms-last_ms;
 wire [10:0] integration_factor=dt*11'd143;
 reg math_start;reg [1:0] op;reg [63:0] ma;reg [31:0] mb;
 wire done;wire [63:0] result;wire signed [31:0] rq=result[59:28];
 drum_math math(.clk(clk),.rst_n(rst_n),.start(math_start),.operation(op),.operand_a(ma),.operand_b(mb),.busy(),.done(done),.result(result));
 assign sample_ready=state==IDLE;
 function signed [31:0] word(input [111:0] d,input integer n);begin word={{16{d[n*16+7]}},d[n*16+:8],d[n*16+8+:8]};end endfunction
 function [31:0] ab(input signed [31:0] x);begin ab=x[31]?-x:x;end endfunction
 task mul(input signed [31:0] x,y,input [4:0] ns);begin ma<={32'd0,x};mb<=y;op<=0;math_start<=1;ret<=ns;state<=WAIT;end endtask
 // Rotation matrix is row-major, mapping sensor vectors into initial frame.
 always @*begin
  operand_x=0;operand_y=0;
  case(state)
   MATRIX:case(ix)
    0:begin operand_x=q[1];operand_y=q[1];end
    1:begin operand_x=q[2];operand_y=q[2];end
    2:begin operand_x=q[3];operand_y=q[3];end
    3:begin operand_x=q[1];operand_y=q[2];end
    4:begin operand_x=q[1];operand_y=q[3];end
    5:begin operand_x=q[2];operand_y=q[3];end
    6:begin operand_x=q[0];operand_y=q[1];end
    7:begin operand_x=q[0];operand_y=q[2];end
    default:begin operand_x=q[0];operand_y=q[3];end
   endcase
   GRAV:begin operand_x=m[(ix%3)*3+ix/3];operand_y=$signed(cal_result[(ix%3)*16+:16])<<<17;end
   CROSS:case(ix)
    0:begin operand_x=a[1]<<<17;operand_y=g[2];end
    1:begin operand_x=a[2]<<<17;operand_y=g[1];end
    2:begin operand_x=a[2]<<<17;operand_y=g[0];end
    3:begin operand_x=a[0]<<<17;operand_y=g[2];end
    4:begin operand_x=a[0]<<<17;operand_y=g[1];end
    default:begin operand_x=a[1]<<<17;operand_y=g[0];end
   endcase
   DERIV:case(ix)
    0:begin operand_x=q[1];operand_y=step[0];end
    1:begin operand_x=q[2];operand_y=step[1];end
    2:begin operand_x=q[3];operand_y=step[2];end
    3:begin operand_x=q[0];operand_y=step[0];end
    4:begin operand_x=q[2];operand_y=step[2];end
    5:begin operand_x=q[3];operand_y=step[1];end
    6:begin operand_x=q[0];operand_y=step[1];end
    7:begin operand_x=q[1];operand_y=step[2];end
    8:begin operand_x=q[3];operand_y=step[0];end
    9:begin operand_x=q[0];operand_y=step[2];end
    10:begin operand_x=q[1];operand_y=step[1];end
    default:begin operand_x=q[2];operand_y=step[0];end
   endcase
   WORLD:begin operand_x=m[ix];operand_y=(ix%3==1)?32'sd0:w[ix%3];end
  endcase
 end
 wire negterm=ix<3 || ix==5 || ix==7 || ix==11;
 wire signed [31:0] derivterm=negterm ? -rq:rq;
 integer j;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;ret<=0;ix<=0;math_start<=0;op<=0;ma<=0;mb<=0;
   had_cal<=0;have_time<=0;last_ms<=0;dt<=2;vector_valid<=0;wx<=0;wy<=0;wz<=0;neutral<=0;quiet<=0;fault<=0;attitude<=128'd268435456;
   tmp<=0;accum<=0;norm_sum<=0;norm_q<=0;calm<=0;
   for(j=0;j<4;j=j+1)begin q[j]<=j==0?ONE:0;qn[j]<=0;end
   for(j=0;j<9;j=j+1)begin m[j]<=0;terms[j]<=0;end
   for(j=0;j<3;j=j+1)begin a[j]<=0;w[j]<=0;g[j]<=0;cor[j]<=0;step[j]<=0;end
  end else begin
   math_start<=0;vector_valid<=0;
    if(!online)have_time<=0;
   if(clear || !calibrated)begin state<=IDLE;had_cal<=0;have_time<=0;neutral<=0;quiet<=0;fault<=0;end
   else if(fault)begin state<=IDLE;end
   else if(!had_cal)begin
    had_cal<=1;state<=IDLE;have_time<=0;fault<=0;attitude<=128'd268435456;
    for(j=0;j<4;j=j+1)q[j]<=j==0?ONE:0;
   end else case(state)
    IDLE:if(sample_valid && online)begin
     last_ms<=sample_ms;dt<=sample_interval[3:0];
     for(j=0;j<3;j=j+1)begin a[j]<=word(sample_data,j);w[j]<=word(sample_data,j+4)-$signed(cal_result[(j+3)*16+:16]);end
     calm<=ab(word(sample_data,4)-$signed(cal_result[63:48]))<328 && ab(word(sample_data,5)-$signed(cal_result[79:64]))<328 && ab(word(sample_data,6)-$signed(cal_result[95:80]))<328;
     ix<=0;accum<=0;
     if(!have_time)begin have_time<=1;state<=IDLE;end
     // Missing samples are not calibration faults. Keep attitude and rebase time;
     // discard the first sample after a gap instead of integrating unobserved motion.
     else if(sample_ms-last_ms>10 || sample_ms==last_ms)begin state<=IDLE;end
     else state<=MATRIX;
    end
    MATRIX:mul(operand_x,operand_y,MATRIX_SAVE);
    MATRIX_SAVE:begin
     terms[ix]<=rq;
     if(ix==8)begin
      m[0]<=ONE-((terms[1]+terms[2])<<<1);m[1]<=(terms[3]-rq)<<<1;m[2]<=(terms[4]+terms[7])<<<1;
      m[3]<=(terms[3]+rq)<<<1;m[4]<=ONE-((terms[0]+terms[2])<<<1);m[5]<=(terms[5]-terms[6])<<<1;
      m[6]<=(terms[4]-terms[7])<<<1;m[7]<=(terms[5]+terms[6])<<<1;m[8]<=ONE-((terms[0]+terms[1])<<<1);
      ix<=0;accum<=0;state<=GRAV;
     end else begin ix<=ix+1'b1;state<=MATRIX;end
    end
    GRAV:mul(operand_x,operand_y,GRAV_SAVE);
    GRAV_SAVE:begin
     if(ix%3==2)begin g[ix/3]<=accum+rq;accum<=0;end else accum<=accum+rq;
     if(ix==8)begin ix<=0;state<=CROSS;end else begin ix<=ix+1'b1;state<=GRAV;end
    end
    CROSS:mul(operand_x,operand_y,CROSS_SAVE);
    CROSS_SAVE:begin
     if(!ix[0])tmp<=rq;
     else cor[ix>>1]<=(calm && ab(a[0])<2458 && ab(a[1])<2458 && ab(a[2])<2458) ? (tmp-rq)>>>8:0; // half-step gravity gain ~2 / s at rest
     if(ix==5)begin ix<=0;state<=STEP;end else begin ix<=ix+1'b1;state<=CROSS;end
    end
    STEP:mul(w[ix],$signed({21'd0,integration_factor}),STEP_SAVE);
    STEP_SAVE:begin
     step[ix]<=$signed(result[31:0])+cor[ix];
     if(ix==2)begin ix<=0;accum<=0;state<=DERIV;end else begin ix<=ix+1'b1;state<=STEP;end
    end
    DERIV:mul(operand_x,operand_y,DERIV_SAVE);
    DERIV_SAVE:begin
     case(ix)
      2:begin qn[0]<=q[0]+accum+derivterm;accum<=0;end
      5:begin qn[1]<=q[1]+accum+derivterm;accum<=0;end
      8:begin qn[2]<=q[2]+accum+derivterm;accum<=0;end
      11:begin qn[3]<=q[3]+accum+derivterm;accum<=0;end
      default:accum<=accum+derivterm;
     endcase
     if(ix==11)begin ix<=0;norm_sum<=0;state<=NORM;end else begin ix<=ix+1'b1;state<=DERIV;end
    end
    NORM:mul(qn[ix],qn[ix],NORM_SAVE);
    NORM_SAVE:begin
     norm_sum<=norm_sum+result;
     if(ix==3)begin op<=1;ma<=norm_sum+result;math_start<=1;ret<=ROOT_SAVE;state<=WAIT;end
     else begin ix<=ix+1'b1;state<=NORM;end
    end
    ROOT_SAVE:if(result==0)begin fault<=1;had_cal<=0;state<=IDLE;end else begin norm_q<=result[31:0];ix<=0;state<=DIV;end
    DIV:begin op<=2;ma<={4'd0,ab(qn[ix]),28'd0};mb<=norm_q;math_start<=1;ret<=DIV_SAVE;state<=WAIT;end
    DIV_SAVE:begin
     q[ix]<=qn[ix][31] ? -$signed(result[31:0]):$signed(result[31:0]);
     attitude[ix*32+:32]<=qn[ix][31] ? -$signed(result[31:0]):$signed(result[31:0]);
     if(ix==3)begin ix<=0;accum<=0;state<=WORLD;end else begin ix<=ix+1'b1;state<=DIV;end
    end
    // Preserve full gyro for attitude, remove sensor-Y axial roll only from hit vector.
    // Use pre-update matrix: reference vector lag is one 5 ms sample.
    WORLD:mul(operand_x,operand_y,WORLD_SAVE);
    WORLD_SAVE:begin
     if(ix%3==2)begin
      case(ix/3)0:wx<=accum+rq;1:wy<=accum+rq;2:wz<=accum+rq;endcase
      accum<=0;
     end else accum<=accum+rq;
     if(ix==8)begin
      neutral<=m[4]>32'sd232471924; // body Y stays within 30 deg; roll around Y is unrestricted
      quiet<=ab(w[0])<1640 && ab(w[2])<1640;vector_valid<=1;state<=IDLE;
     end else begin ix<=ix+1'b1;state<=WORLD;end
    end
    WAIT:if(done)state<=ret;
    default:begin fault<=1;state<=IDLE;had_cal<=0;end
   endcase
  end
 end
endmodule
