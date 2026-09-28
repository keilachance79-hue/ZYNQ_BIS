`timescale 1ns/1ps
module ltc1668_if #(
  parameter integer ADDR_WIDTH=11,
  parameter [15:0] IDLE_CODE=16'h8000
)(
  input wire sample_clk, reset_n,
  input wire [15:0] rom_data,
  input wire [ADDR_WIDTH-1:0] rom_index,
  input wire rom_valid,
  output reg [15:0] dac_data,
  output wire dac_clk,
  output reg sample_valid,
  output reg period_start,
  output reg [ADDR_WIDTH-1:0] sample_index
);
  reg launch_valid;
  reg [ADDR_WIDTH-1:0] launch_index;
  // Falling-edge launch provides half a sample period before DAC rising latch.
  // Asynchronous reset is an abort; setup/hold guarantees apply while valid.
  always @(negedge sample_clk or negedge reset_n) begin
    if(!reset_n) begin dac_data<=IDLE_CODE; launch_valid<=0; launch_index<=0; end
    else begin
      dac_data<=rom_valid ? rom_data:IDLE_CODE;
      launch_valid<=rom_valid;
      launch_index<=rom_index;
    end
  end
  // Clock always runs while the MMCM runs, including idle-code intervals.
  // Do not gate this clock through LUTs or combinational reset logic.
  ODDR #(.DDR_CLK_EDGE("SAME_EDGE"),.INIT(1'b0),.SRTYPE("SYNC")) forward_clock_i(
    .C(sample_clk),.CE(1'b1),.D1(1'b1),.D2(1'b0),.R(1'b0),.S(1'b0),.Q(dac_clk));
  always @(posedge sample_clk or negedge reset_n) begin
    if(!reset_n) begin sample_valid<=0; period_start<=0; sample_index<=0; end
    else begin
      sample_valid<=launch_valid;
      period_start<=launch_valid && (launch_index==0);
      sample_index<=launch_index;
    end
  end
endmodule
