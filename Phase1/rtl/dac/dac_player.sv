`timescale 1ns/1ps
module dac_player #(
  parameter integer ROM_LENGTH=2048,
  parameter integer FS_HZ=10240000,
  parameter integer ADDR_WIDTH=$clog2(ROM_LENGTH),
  parameter ROM_FILE="waveform.hex"
)(
  input wire sample_clk, reset_n,
  output wire [15:0] rom_data,
  output reg [ADDR_WIDTH-1:0] rom_index,
  output reg rom_valid
);
  reg [ADDR_WIDTH-1:0] address;
  multisine_rom #(.ROM_LENGTH(ROM_LENGTH),.ADDR_WIDTH(ADDR_WIDTH),.ROM_FILE(ROM_FILE)) rom_i(
    .clk(sample_clk),.address(address),.data(rom_data));
  // BRAM address controls must reset synchronously (Vivado REQP-1839).
  // The output interface still aborts asynchronously. Clock-gen reset release
  // waits four running sample clocks so this address is reset before playback.
  always @(posedge sample_clk) begin
    if(!reset_n) begin address<=0; rom_index<=0; rom_valid<=0; end
    else begin
      rom_index<=address;
      rom_valid<=1;
      if(address==ROM_LENGTH-1) address<=0;
      else address<=address+1'b1;
    end
  end
  // synthesis translate_off
  initial begin
    if(ROM_LENGTH<2 || (1<<ADDR_WIDTH)<ROM_LENGTH || FS_HZ<=0)
      $fatal(1,"Invalid DAC player parameters");
  end
  // synthesis translate_on
endmodule
