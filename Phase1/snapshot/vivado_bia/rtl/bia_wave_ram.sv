`timescale 1ns/1ps
module bia_wave_ram #(parameter integer FRAME_LOG2=14)(
  input wire wr_clk, wr_en, wr_bank,
  input wire [FRAME_LOG2-1:0] wr_addr,
  input wire [15:0] wr_data,
  input wire rd_clk, rd_bank,
  input wire [FRAME_LOG2-1:0] rd_addr,
  output reg [15:0] rd_data
);
  // Independent-clock simple dual-port BRAM. No reset on the memory array.
  (* ram_style="block" *) reg [15:0] mem[0:(2<<FRAME_LOG2)-1];
  always @(posedge wr_clk)
    if(wr_en) mem[{wr_bank,wr_addr}]<=wr_data;
  always @(posedge rd_clk)
    rd_data<=mem[{rd_bank,rd_addr}];
endmodule
