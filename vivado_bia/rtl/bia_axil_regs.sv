`timescale 1ns/1ps
module bia_axil_regs #(parameter integer FRAME_LOG2=14)(
  input wire clk, resetn,
  input wire [17:0] s_axi_awaddr, input wire [2:0] s_axi_awprot,
  input wire s_axi_awvalid, output wire s_axi_awready,
  input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
  input wire s_axi_wvalid, output wire s_axi_wready,
  output reg [1:0] s_axi_bresp, output reg s_axi_bvalid, input wire s_axi_bready,
  input wire [17:0] s_axi_araddr, input wire [2:0] s_axi_arprot,
  input wire s_axi_arvalid, output wire s_axi_arready,
  output reg [31:0] s_axi_rdata, output reg [1:0] s_axi_rresp,
  output reg s_axi_rvalid, input wire s_axi_rready,
  output bia_pkg::command_t command,
  output reg cmd_push, input wire cmd_ready,
  input wire packet_complete,
  input wire [31:0] final_status, final_count,
  output reg busy,
  output reg wave_we, wave_bank,
  output reg [FRAME_LOG2-1:0] wave_addr,
  output reg [15:0] wave_data
);
  import bia_pkg::*;
  localparam integer N=1<<FRAME_LOG2;
  command_t shadow;
  reg aw_pending,w_pending;
  reg [17:0] aw;
  reg [31:0] wd;
  reg [3:0] ws;
  reg done_sticky;
  reg [31:0] last_status,last_count;
  integer k,j;
  reg bins_ok;
  wire [31:0] options_old={29'b0,shadow.adc_offset_binary,shadow.raw_mode,shadow.bank};
  wire [31:0] options_new=merge32(options_old,wd,ws);
  function automatic [31:0] merge32(input [31:0] oldv,newv,input [3:0] strobe);
    integer b;
    begin
      merge32=oldv;
      for(b=0;b<4;b=b+1) if(strobe[b]) merge32[b*8+:8]=newv[b*8+:8];
    end
  endfunction
  always @* begin
    bins_ok=1;
    for(integer a=0;a<8;a=a+1) begin
      if(shadow.freq_bins[a]==0 || shadow.freq_bins[a]>=N/2) bins_ok=0;
      for(integer b=0;b<a;b=b+1)
        if(shadow.freq_bins[a]==shadow.freq_bins[b]) bins_ok=0;
    end
  end
  assign s_axi_awready=!aw_pending && !s_axi_bvalid;
  assign s_axi_wready=!w_pending && !s_axi_bvalid;
  assign s_axi_arready=!s_axi_rvalid;
  always @(posedge clk) begin
    if(!resetn) begin
      aw_pending<=0; w_pending<=0; aw<=0; wd<=0; ws<=0;
      s_axi_bvalid<=0; s_axi_bresp<=0;
      s_axi_rvalid<=0; s_axi_rresp<=0; s_axi_rdata<=0;
      shadow<='0; shadow.fs_hz<=10240000;
      shadow.settle_cycles<=256; shadow.break_cycles<=16;
      shadow.raw_mode<=1; shadow.adc_offset_binary<=1;
      for(k=0;k<8;k=k+1) shadow.freq_bins[k]<=k+1;
      command<='0; cmd_push<=0; busy<=0; done_sticky<=0;
      last_status<=0; last_count<=0;
      wave_we<=0; wave_bank<=0; wave_addr<=0; wave_data<=0;
    end else begin
      cmd_push<=0; wave_we<=0;
      if(packet_complete) begin
        busy<=0; done_sticky<=1;
        last_status<=final_status; last_count<=final_count;
      end
      if(s_axi_awvalid && s_axi_awready) begin aw<=s_axi_awaddr; aw_pending<=1; end
      if(s_axi_wvalid && s_axi_wready) begin wd<=s_axi_wdata; ws<=s_axi_wstrb; w_pending<=1; end
      if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
      // AW and W are independently buffered; no simultaneous-arrival assumption.
      if(aw_pending && w_pending && !s_axi_bvalid) begin
        aw_pending<=0; w_pending<=0; s_axi_bvalid<=1; s_axi_bresp<=0;
        if(aw[1:0]!=0) s_axi_bresp<=2;
        else if(aw>=18'h10000 && aw<18'h30000) begin
          if(aw[15:2]>=N || (busy && (aw[17]==command.bank)) ||
             (ws[1:0]!=0 && ws[1:0]!=2'b11)) s_axi_bresp<=2;
          else if(ws[1:0]==2'b11) begin
            wave_we<=1; wave_bank<=aw[17]; wave_addr<=aw[FRAME_LOG2+1:2]; wave_data<=wd[15:0];
          end
        end else case(aw)
          18'h00004: begin
            if(ws[0] && wd[1]) done_sticky<=0;
            if(ws[0] && wd[0]) begin
              if(busy || !cmd_ready || (!shadow.raw_mode && !bins_ok) || shadow.fs_hz==0)
                s_axi_bresp<=2;
              else begin command<=shadow; cmd_push<=1; busy<=1; done_sticky<=0; end
            end
          end
          18'h0000c: shadow.session_id<=merge32(shadow.session_id,wd,ws);
          18'h00010: shadow.frame_id<=merge32(shadow.frame_id,wd,ws);
          18'h00014: shadow.config_id<=merge32(shadow.config_id,wd,ws);
          18'h00018: shadow.fs_hz<=merge32(shadow.fs_hz,wd,ws);
          18'h0001c: shadow.settle_cycles<=merge32(shadow.settle_cycles,wd,ws);
          18'h00020: shadow.break_cycles<=merge32({16'b0,shadow.break_cycles},wd,ws);
          18'h00024: shadow.electrodes<=merge32({12'b0,shadow.electrodes},wd,ws);
          18'h00028: begin
            shadow.bank<=options_new[0]; shadow.raw_mode<=options_new[1];
            shadow.adc_offset_binary<=options_new[2];
          end
          default: begin
            if(aw>=18'h40 && aw<18'h60)
              shadow.freq_bins[(aw-18'h40)>>2]<=merge32({18'b0,shadow.freq_bins[(aw-18'h40)>>2]},wd,ws);
            else s_axi_bresp<=2;
          end
        endcase
      end
      if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
      if(s_axi_arvalid && s_axi_arready) begin
        s_axi_rvalid<=1; s_axi_rresp<=0; s_axi_rdata<=0;
        if(s_axi_araddr[1:0]!=0) s_axi_rresp<=2;
        else case(s_axi_araddr)
          18'h00000: s_axi_rdata<=MAGIC;
          18'h00008: s_axi_rdata<={30'b0,done_sticky,busy};
          18'h0000c: s_axi_rdata<=shadow.session_id;
          18'h00010: s_axi_rdata<=shadow.frame_id;
          18'h00014: s_axi_rdata<=shadow.config_id;
          18'h00018: s_axi_rdata<=shadow.fs_hz;
          18'h0001c: s_axi_rdata<=shadow.settle_cycles;
          18'h00020: s_axi_rdata<={16'b0,shadow.break_cycles};
          18'h00024: s_axi_rdata<={12'b0,shadow.electrodes};
          18'h00028: s_axi_rdata<=options_old;
          18'h0002c: s_axi_rdata<=N;
          18'h00030: s_axi_rdata<=last_status;
          18'h00034: s_axi_rdata<=last_count;
          18'h00038: s_axi_rdata<=32'h00010008; // protocol 1, 8 tones
          default: begin
            if(s_axi_araddr>=18'h40 && s_axi_araddr<18'h60)
              s_axi_rdata<={18'b0,shadow.freq_bins[(s_axi_araddr-18'h40)>>2]};
            else s_axi_rresp<=2;
          end
        endcase
      end
    end
  end
endmodule
