`timescale 1ns/1ps
`include "phase1_config.svh"
module phase1_dac_top #(
  parameter integer ROM_LENGTH=`PH1_ROM_LENGTH,
  parameter integer FS_HZ=`PH1_FS_HZ,
  parameter integer REF_CLK_HZ=`PH1_REF_CLK_HZ,
  parameter integer MMCM_DIVCLK=`PH1_MMCM_DIVCLK,
  parameter real MMCM_MULT=`PH1_MMCM_MULT,
  parameter real MMCM_OUT_DIV=`PH1_MMCM_OUT_DIV,
  parameter ROM_FILE="waveform.hex"
)(
  input wire ref_clk, reset_n,
  output wire [15:0] dac_data,
  output wire dac_clk,
  output wire locked, sample_valid, period_start,
  output wire [$clog2(ROM_LENGTH)-1:0] sample_index
);
  localparam integer AW=$clog2(ROM_LENGTH);
  wire sample_clk, sample_reset_n, rom_valid;
  wire [15:0] rom_data;
  wire [AW-1:0] rom_index;
  system_clock_gen #(.REF_CLK_HZ(REF_CLK_HZ),.FS_HZ(FS_HZ),.MMCM_DIVCLK(MMCM_DIVCLK),
    .MMCM_MULT(MMCM_MULT),.MMCM_OUT_DIV(MMCM_OUT_DIV)) clock_i(
    .ref_clk(ref_clk),.reset_n(reset_n),.sample_clk(sample_clk),.locked(locked),
    .sample_reset_n(sample_reset_n));
  dac_player #(.ROM_LENGTH(ROM_LENGTH),.FS_HZ(FS_HZ),.ROM_FILE(ROM_FILE)) player_i(
    .sample_clk(sample_clk),.reset_n(sample_reset_n),.rom_data(rom_data),
    .rom_index(rom_index),.rom_valid(rom_valid));
  ltc1668_if #(.ADDR_WIDTH(AW)) dac_i(
    .sample_clk(sample_clk),.reset_n(sample_reset_n),.rom_data(rom_data),
    .rom_index(rom_index),.rom_valid(rom_valid),.dac_data(dac_data),.dac_clk(dac_clk),
    .sample_valid(sample_valid),.period_start(period_start),.sample_index(sample_index));
endmodule
