`timescale 1ns/1ps
// Digital subsystem, not a board top: no unapproved ADC CLK+/- driver or pins.
// conversion_clk is the physical conversion timebase. Its epoch must be tied
// to a known DAC period by the eventual board wrapper/calibration procedure.
module phase2_capture_top #(
  parameter integer N=2048,FIFO_DEPTH=256,TAG_SUB_A=8,TAG_SUB_B=8,TIMEOUT_CYCLES=2048
)(
  input wire conversion_clk,dsp_clk,dco_a,dco_b,reset_n,
  input wire [15:0] adc_a,adc_b,
  input wire clock_ok,alignment_verified,
  input wire request_valid,
  output wire request_ready,
  input wire [31:0] request_start,request_id,request_calibration,
  output wire [7:0] fault,
  output wire active,
  output wire [1:0] banks_ready,
  output wire [31:0] m_data,
  output wire m_valid,m_last,
  input wire m_ready,
  output wire [$clog2(N)-1:0] m_index,
  output wire [31:0] m_frame_id,m_start,m_calibration,completed_frames,aborted_frames
);
  reg [31:0] conversion_tick=0,conversion_gray=0;
  wire [31:0] next_tick=conversion_tick+1;
  always @(posedge conversion_clk) begin
    if(!reset_n) begin conversion_tick<=0; conversion_gray<=0; end
    else begin conversion_tick<=next_tick; conversion_gray<=(next_tick>>1)^next_tick; end
  end
  wire [47:0] data_a,data_b;
  wire valid_a,valid_b,pop_a,pop_b,overflow_a,overflow_b;
  (* ASYNC_REG="TRUE" *) reg [1:0] overflow_meta,overflow_sync;
  always @(posedge dsp_clk) begin
    if(!reset_n) begin overflow_meta<=0; overflow_sync<=0; end
    else begin overflow_meta<={overflow_b,overflow_a}; overflow_sync<=overflow_meta; end
  end
  adc_channel_rx #(.FIFO_DEPTH(FIFO_DEPTH),.TAG_SUB(TAG_SUB_A)) rx_a(
    .dco(dco_a),.dsp_clk(dsp_clk),.reset_n(reset_n),.adc_data(adc_a),
    .conversion_gray(conversion_gray),.data(data_a),.valid(valid_a),.pop(pop_a),.overflow_sticky(overflow_a));
  adc_channel_rx #(.FIFO_DEPTH(FIFO_DEPTH),.TAG_SUB(TAG_SUB_B)) rx_b(
    .dco(dco_b),.dsp_clk(dsp_clk),.reset_n(reset_n),.adc_data(adc_b),
    .conversion_gray(conversion_gray),.data(data_b),.valid(valid_b),.pop(pop_b),.overflow_sticky(overflow_b));
  adc_frame_buffer #(.N(N),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) buffer_i(
    .clk(dsp_clk),.reset_n(reset_n),.clock_ok(clock_ok),.alignment_verified(alignment_verified),
    .overflow_a(overflow_sync[0]),.overflow_b(overflow_sync[1]),
    .a_data(data_a),.b_data(data_b),.a_valid(valid_a),.b_valid(valid_b),.a_pop(pop_a),.b_pop(pop_b),
    .request_valid(request_valid),.request_ready(request_ready),.request_start(request_start),
    .request_id(request_id),.request_calibration(request_calibration),.fault(fault),.active(active),
    .banks_ready(banks_ready),.m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_last(m_last),
    .m_index(m_index),.m_frame_id(m_frame_id),.m_start(m_start),.m_calibration(m_calibration),
    .completed_frames(completed_frames),.aborted_frames(aborted_frames));
endmodule
