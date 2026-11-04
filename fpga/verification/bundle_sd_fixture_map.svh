function automatic integer page_for(input [31:0] lba);
 begin case(lba)
32'd0:page_for=0;
32'd2048:page_for=1;
32'd2080:page_for=2;
32'd2680:page_for=3;
32'd2682:page_for=4;
32'd2683:page_for=5;
32'd2685:page_for=6;
32'd2687:page_for=7;
32'd2689:page_for=8;
32'd2690:page_for=9;
32'd2691:page_for=10;
32'd2692:page_for=11;
32'd2693:page_for=12;
32'd2694:page_for=13;
32'd2695:page_for=14;
default:page_for=-1;endcase end
endfunction
