`timescale 1ns/1ps
// Read-only FAT32 root catalog and fragmented file byte stream.
// 512-byte sectors, SDHC block addressing. Only root *.HPG regular files.
module hallpad_sd_catalog(
 input wire clk,rst_n,
 input wire block_ready,block_done,block_error,
 output reg block_request,output reg [31:0] block_lba,
 input wire read_valid,input wire [8:0] read_address,input wire [7:0] read_byte,
 input wire open_file,input wire [7:0] selection,
 output wire file_idle,output reg mounted,failed,output reg [7:0] error_code,
 output reg [8:0] song_count,output wire [63:0] song_name,
 output reg [31:0] file_size,
 output reg data_valid,output reg [7:0] data_byte,input wire data_ready,
 output reg file_done,input wire cancel
);
 localparam BOOT=0,READ_REQ=1,READ_WAIT=2,GW1=3,GW2=4,
 CHECK0=5,MBR_TYPE=6,MBR_LBA=7,BOOT_BPS=8,BOOT_GEOM=9,
 BOOT_FAT=10,BOOT_ROOT=11,BOOT_TOTAL=12,BOOT_FLAGS=13,BOOT_SIG=14,GEOMETRY=15,
 DIR_START=16,DIR_WORD=17,DIR_PARSE=18,DIR_NEXT=19,CHAIN_WORD=20,CHAIN_CHECK=21,
 LIST=22,FILE_START=23,FILE_ADDR=24,FILE_WAIT=25,FILE_CAPTURE=26,FILE_OUT=27,DEAD=31,LAYOUT_ROOT=32,LAYOUT_FAT16=33,GEOM_SUB=34,GEOM_SHIFT=35,GEOM_FLAGS=36,GEOM_CHECK=37,GEOM_ADDR=38,GEOM_DATA=39;
 reg [5:0] state,after_read,after_word;
 (* syn_ramstyle="block_ram" *) reg [7:0] sector[0:511];
 reg [8:0] mem_addr;reg [7:0] mem_data;
 always @(posedge clk)begin
  if(read_valid)sector[read_address]<=read_byte;
  mem_data<=sector[mem_addr];
 end
 reg [1:0] word_byte;reg [31:0] word_value;
 reg [31:0] volume_lba,total_sectors,fat_sectors,fat_lba,data_lba,root_cluster,cluster,max_cluster,remaining;
 reg [15:0] reserved,ext_flags;
 reg [7:0] fats,spc;
 reg [3:0] spc_shift;
 reg [6:0] cluster_sector;
 reg [8:0] offset,dir_offset;
 reg [2:0] dir_word;
 reg [255:0] entry;
 reg directory_chain;
 reg [12:0] directory_sectors;
 (* syn_ramstyle="block_ram" *) reg [63:0] names[0:255];
 (* syn_ramstyle="block_ram" *) reg [31:0] clusters[0:255],sizes[0:255];
 reg [31:0] selected_size,selected_cluster;reg [63:0] selected_name;
 always @(posedge clk)begin selected_size<=sizes[selection];selected_cluster<=clusters[selection];selected_name<=names[selection];end

 assign file_idle=state==LIST;
 assign song_name=selection<song_count ? selected_name:64'h2020202020202020;
 wire [31:0] partition_data=({24'd0,fats}==2 ? (fat_sectors<<1):fat_sectors)+{16'd0,reserved};
 reg [31:0] partition_data_q,data_sectors_q,cluster_count_q;
 reg [32:0] volume_end_q;
 reg geometry_bad_q;
 wire [32:0] volume_end={1'b0,volume_lba}+{1'b0,total_sectors};
 wire [27:0] next_cluster=word_value[27:0];
 function [31:0] cluster_lba(input [31:0] c);begin cluster_lba=data_lba+((c-2)<<spc_shift);end endfunction
 task fail(input [7:0] code);begin failed<=1;error_code<=code;mounted<=0;data_valid<=0;state<=DEAD;end endtask
 task load_sector(input [31:0] lba,input [5:0] target);begin block_lba<=lba;after_read<=target;state<=READ_REQ;end endtask
 task get_word(input [8:0] a,input [5:0] target);begin mem_addr<=a;word_byte<=0;word_value<=0;after_word<=target;state<=GW1;end endtask
 task chain;begin load_sector(fat_lba+(cluster>>7),CHAIN_WORD);end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=BOOT;after_read<=0;after_word<=0;block_request<=0;block_lba<=0;mounted<=0;failed<=0;error_code<=0;
   song_count<=0;file_size<=0;data_valid<=0;data_byte<=0;file_done<=0;mem_addr<=0;word_byte<=0;word_value<=0;
   volume_lba<=0;total_sectors<=0;fat_sectors<=0;fat_lba<=0;data_lba<=0;root_cluster<=0;cluster<=0;max_cluster<=0;remaining<=0;
   partition_data_q<=0;data_sectors_q<=0;cluster_count_q<=0;volume_end_q<=0;geometry_bad_q<=0;
   reserved<=0;ext_flags<=0;fats<=0;spc<=0;spc_shift<=0;cluster_sector<=0;offset<=0;dir_offset<=0;dir_word<=0;entry<=0;directory_chain<=1;directory_sectors<=0;
  end else begin
   block_request<=0;file_done<=0;
   if(block_error && state!=DEAD)fail(1);
   else case(state)
    BOOT:if(block_ready)load_sector(0,CHECK0);
    READ_REQ:if(block_ready)begin block_request<=1;state<=READ_WAIT;end
    READ_WAIT:if(block_done)begin state<=after_read;end
    GW1:state<=GW2;
    GW2:begin
     word_value<={mem_data,word_value[31:8]};
     if(word_byte==3)state<=after_word;
     else begin word_byte<=word_byte+1'b1;mem_addr<=mem_addr+1'b1;state<=GW1;end
    end
    CHECK0:get_word(11,BOOT_BPS);
    BOOT_BPS:if(word_value[15:0]==512)get_word(13,BOOT_GEOM);
     else if(volume_lba==0)get_word(450,MBR_TYPE);else fail(2);
    MBR_TYPE:if(word_value[7:0]!=8'h0b && word_value[7:0]!=8'h0c)fail(3);else get_word(454,MBR_LBA);
    MBR_LBA:if(word_value==0)fail(3);else begin volume_lba<=word_value;load_sector(word_value,CHECK0);end
    BOOT_GEOM:begin
     spc<=word_value[7:0];reserved<=word_value[23:8];fats<=word_value[31:24];
     case(word_value[7:0])1:spc_shift<=0;2:spc_shift<=1;4:spc_shift<=2;8:spc_shift<=3;
      16:spc_shift<=4;32:spc_shift<=5;64:spc_shift<=6;128:spc_shift<=7;default:spc_shift<=15;endcase
     get_word(36,BOOT_FAT);
    end
    BOOT_FAT:begin fat_sectors<=word_value;get_word(44,BOOT_ROOT);end
    BOOT_ROOT:begin root_cluster<=word_value;get_word(32,BOOT_TOTAL);end
    BOOT_TOTAL:begin total_sectors<=word_value;get_word(40,BOOT_FLAGS);end
    BOOT_FLAGS:if(word_value[31:16]!=0)fail(4);else begin ext_flags<=word_value[15:0];get_word(508,BOOT_SIG);end
    BOOT_SIG:if(word_value[31:16]!=16'haa55)fail(2);else get_word(17,LAYOUT_ROOT);
    LAYOUT_ROOT:if(word_value[15:0]!=0)fail(4);else get_word(22,LAYOUT_FAT16);
    LAYOUT_FAT16:if(word_value[15:0]!=0)fail(4);else state<=GEOMETRY;
    // Mount-only arithmetic is serialized to remove the former 30-level path.
    GEOMETRY:begin partition_data_q<=partition_data;volume_end_q<=volume_end;state<=GEOM_SUB;end
    GEOM_SUB:begin data_sectors_q<=total_sectors-partition_data_q;state<=GEOM_SHIFT;end
    GEOM_SHIFT:begin cluster_count_q<=data_sectors_q>>spc_shift;state<=GEOM_FLAGS;end
    GEOM_FLAGS:begin
     geometry_bad_q<=spc_shift==15 || reserved==0 || (fats!=1 && fats!=2) || fat_sectors==0 || fat_sectors[31:25]!=0 ||
       cluster_count_q>=(fat_sectors<<7) || total_sectors<=partition_data_q || volume_end_q[32] || root_cluster<2 || root_cluster[31:28]!=0 ||
       (ext_flags[7] && ext_flags[3:0]>=fats);
     state<=GEOM_CHECK;
    end
    GEOM_CHECK:if(geometry_bad_q)fail(4);else begin fat_lba<=volume_lba+{16'd0,reserved};state<=GEOM_ADDR;end
    GEOM_ADDR:begin
     if(ext_flags[7] && ext_flags[3:0]!=0)fat_lba<=fat_lba+fat_sectors;
     data_lba<=volume_lba+partition_data_q;max_cluster<=cluster_count_q+1;state<=GEOM_DATA;
    end
    GEOM_DATA:begin cluster<=root_cluster;cluster_sector<=0;directory_chain<=1;directory_sectors<=0;state<=DIR_START;end
    DIR_START:if(cluster<2 || cluster>max_cluster || directory_sectors==4095)fail(5);
     else begin directory_sectors<=directory_sectors+1'b1;dir_offset<=0;dir_word<=0;load_sector(cluster_lba(cluster)+{25'd0,cluster_sector},DIR_NEXT);end
    DIR_NEXT:begin dir_word<=0;entry<=0;get_word(dir_offset,DIR_WORD);end
    DIR_WORD:begin
     entry<={word_value,entry[255:32]};
     if(dir_word==7)state<=DIR_PARSE;
     else begin dir_word<=dir_word+1'b1;get_word(dir_offset+{4'd0,dir_word,2'b00}+9'd4,DIR_WORD);end
    end
    DIR_PARSE:begin
     if(entry[7:0]==0 || song_count==256)begin mounted<=1;state<=LIST;end
     else begin
      if(entry[7:0]!=8'he5 && (entry[95:88]&8'h18)==0 && entry[95:88]!=8'h0f &&
         entry[87:64]==24'h475048)begin
       names[song_count[7:0]]<={entry[7:0],entry[15:8],entry[23:16],entry[31:24],entry[39:32],entry[47:40],entry[55:48],entry[63:56]};
       clusters[song_count[7:0]]<={entry[175:160],entry[223:208]};sizes[song_count[7:0]]<=entry[255:224];song_count<=song_count+1'b1;
      end
      if(dir_offset==480)begin
       if(cluster_sector+1<spc)begin cluster_sector<=cluster_sector+1'b1;state<=DIR_START;end
       else chain();
      end else begin dir_offset<=dir_offset+9'd32;state<=DIR_NEXT;end
     end
    end
    CHAIN_WORD:get_word({cluster[6:0],2'b00},CHAIN_CHECK);
    CHAIN_CHECK:begin
     if(directory_chain && next_cluster>=28'hffffff8)begin mounted<=1;state<=LIST;end
     else if(next_cluster<2 || {4'd0,next_cluster}>max_cluster || next_cluster>=28'hffffff0)fail(6);
     else begin cluster<={4'd0,next_cluster};cluster_sector<=0;state<=directory_chain ? DIR_START:FILE_START;end
    end
    LIST:begin
     data_valid<=0;
     if(open_file && selection<song_count)begin
      if(selected_size<88 || selected_size>67108864 || selected_cluster<2 || selected_cluster>max_cluster)begin error_code<=7;file_done<=1;end
      else begin cluster<=selected_cluster;file_size<=selected_size;remaining<=selected_size;cluster_sector<=0;directory_chain<=0;state<=FILE_START;error_code<=0;end
     end
    end
    FILE_START:begin offset<=0;load_sector(cluster_lba(cluster)+{25'd0,cluster_sector},FILE_ADDR);end
    FILE_ADDR:begin mem_addr<=offset;state<=FILE_WAIT;end
    FILE_WAIT:state<=FILE_CAPTURE;
    FILE_CAPTURE:begin data_byte<=mem_data;data_valid<=1;state<=FILE_OUT;end
    FILE_OUT:if(data_ready || cancel)begin
     data_valid<=0;
     if(cancel || remaining==1)begin remaining<=0;file_done<=1;state<=LIST;end
     else begin remaining<=remaining-1'b1;
      if(offset==511)begin
       if(cluster_sector+1<spc)begin cluster_sector<=cluster_sector+1'b1;state<=FILE_START;end
       else chain();
      end else begin offset<=offset+1'b1;state<=FILE_ADDR;end
     end
    end
    DEAD:data_valid<=0;
    default:fail(255);
   endcase
  end
 end
endmodule
