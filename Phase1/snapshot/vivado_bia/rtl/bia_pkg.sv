`timescale 1ns/1ps
package bia_pkg;
  parameter int TONES = 8;
  typedef struct packed {
    logic [31:0] session_id;
    logic [31:0] frame_id;
    logic [31:0] config_id;
    logic [31:0] fs_hz;
    logic [31:0] settle_cycles;
    logic [15:0] break_cycles;
    logic [19:0] electrodes; // {VN,VP,IN,IP}, each zero-based 5 bits
    logic bank;
    logic raw_mode;
    logic adc_offset_binary;
    logic [TONES-1:0][13:0] freq_bins;
  } command_t;
  typedef struct packed {
    logic is_end;
    logic [63:0] tick;
    logic [63:0] wave_epoch;
    logic [31:0] accepted;
    logic [31:0] status;
  } metadata_t;
  localparam int COMMAND_W = $bits(command_t);
  localparam int META_W = $bits(metadata_t);
  localparam logic [31:0] MAGIC = 32'h31414942; // little-endian "BIA1"
  // Status bits: 0 FIFO loss, 1 V overrange, 2 I overrange, 3 fault input.
  // 4 acquisition timestamp not calibrated; 5 reserved; 6 input gap.
  localparam logic [31:0] INVALID_MASK = 32'h0000004f;
endpackage
