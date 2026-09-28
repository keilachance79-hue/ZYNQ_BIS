`timescale 1ns/1ps
module system_clock_gen #(
  parameter integer REF_CLK_HZ=50000000,
  parameter integer FS_HZ=10240000,
  parameter integer MMCM_DIVCLK=1,
  parameter real MMCM_MULT=16.0,
  parameter real MMCM_OUT_DIV=78.125
)(
  input wire ref_clk, reset_n,
  output wire sample_clk, locked,
  output wire sample_reset_n
);
  wire feedback_raw, feedback, sample_raw;
  // Nominal 50 MHz * 16 / 1 = 800 MHz VCO; /78.125 = 10.24 MHz.
  // User confirmed 50 MHz; reference pin and jitter still need board evidence.
  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),.CLKIN1_PERIOD(1.0e9/REF_CLK_HZ),
    .DIVCLK_DIVIDE(MMCM_DIVCLK),.CLKFBOUT_MULT_F(MMCM_MULT),
    .CLKOUT0_DIVIDE_F(MMCM_OUT_DIV),.CLKOUT0_DUTY_CYCLE(0.5),
    .STARTUP_WAIT("FALSE")
  ) mmcm_i (
    .CLKIN1(ref_clk),.RST(!reset_n),.PWRDWN(1'b0),.CLKFBIN(feedback),
    .CLKFBOUT(feedback_raw),.CLKOUT0(sample_raw),.LOCKED(locked),
    .CLKFBOUTB(),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
    .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6());
  BUFG feedback_i(.I(feedback_raw),.O(feedback));
  BUFG sample_buffer_i(.I(sample_raw),.O(sample_clk));
  (* ASYNC_REG="TRUE" *) reg [3:0] reset_release=0;
  wire reset_async_n=reset_n && locked;
  always @(posedge sample_clk or negedge reset_async_n)
    if(!reset_async_n) reset_release<=0;
    else reset_release<={reset_release[2:0],1'b1};
  assign sample_reset_n=reset_release[3];
  // synthesis translate_off
  real configured_fs;
  initial begin
    configured_fs=REF_CLK_HZ*MMCM_MULT/MMCM_DIVCLK/MMCM_OUT_DIV;
    if(configured_fs<FS_HZ-0.001 || configured_fs>FS_HZ+0.001)
      $fatal(1,"FS_HZ must match the real MMCM configuration");
  end
  // synthesis translate_on
endmodule
