`timescale 1ns/1ps
module tb_font_synthfix;
reg clk=0;always #10 clk=~clk;
reg[7:0] character=128;reg[4:0] row=0,column=0;wire ink;
reg[21:0] golden[0:2687];integer i,c;
menu_hanzi22 dut(.clk(clk),.character(character),.column(column),.row(row),.ink(ink));
initial begin
$readmemh("verification/font22_golden.hex",golden);
#1;for(i=0;i<2688;i=i+1)if(dut.bitmap[i]!==golden[i])$fatal(1,"ROM mismatch %d",i);
for(i=0;i<2688;i=i+1)begin
 for(c=0;c<22;c=c+1)begin
 @(negedge clk);character=8'(128+(i>>5));row=5'(i%32);column=5'(c);
 @(posedge clk);#1;if(ink!==golden[i][21-c])$fatal(1,"read mismatch %d/%d",i,c);
 end
end
$display("PASS all2688 ROM rows and59136 serial pixel reads unchanged");$finish;
end
endmodule
