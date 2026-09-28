`timescale 1ns/1ps
module multisine_rom #(
  parameter integer ROM_LENGTH=2048,
  parameter integer ADDR_WIDTH=$clog2(ROM_LENGTH),
  parameter ROM_FILE="waveform.hex"
)(
  input wire clk,
  input wire [ADDR_WIDTH-1:0] address,
  output reg [15:0] data
);
  (* rom_style="block" *) reg [15:0] memory[0:ROM_LENGTH-1];
  initial $readmemh(ROM_FILE, memory);
  // One clock synchronous read; deliberately no reset on BRAM data register.
  always @(posedge clk) data <= memory[address];
endmodule
