`timescale 1ns/1ps
// Candidate DCO receiver. Physical DCO routing and epoch calibration are NOT
// approved for this board. TAG_SUB is meaningful only after phase qualification.
module adc_channel_rx #(
  parameter integer FIFO_DEPTH=256, TAG_SUB=8
)(
  input wire dco, dsp_clk, reset_n,
  input wire [15:0] adc_data,
  input wire [31:0] conversion_gray,
  output wire [47:0] data,
  output wire valid,
  input wire pop,
  output reg overflow_sticky
);
  function automatic [31:0] ungray(input [31:0] g);
    integer k;
    begin ungray[31]=g[31]; for(k=30;k>=0;k=k-1) ungray[k]=ungray[k+1]^g[k]; end
  endfunction
  (* ASYNC_REG="TRUE" *) reg [31:0] gray_meta, gray_sync;
  (* ASYNC_REG="TRUE" *) reg [2:0] reset_pipe=3'b111;
  always @(posedge dco) reset_pipe<={reset_pipe[1:0],!reset_n};
  (* IOB="TRUE" *) reg [15:0] input_code;
  reg [31:0] input_tag;
  reg [3:0] warmup;
  wire full, empty, wr_busy, rd_busy;
  wire push=(warmup==15) && !reset_pipe[2] && !wr_busy;
  // Two DCO synchronizer stages reduce metastability probability but do not
  // establish sample identity. Stable relative phase + TAG_SUB calibration is
  // mandatory; a one-cycle common-mode error cannot be detected by pair matching.
  always @(posedge dco) begin
    if(reset_pipe[2]) begin
      gray_meta<=0; gray_sync<=0; input_code<=16'h8000; input_tag<=0;
      warmup<=0; overflow_sticky<=0;
    end else begin
      gray_meta<=conversion_gray; gray_sync<=gray_meta;
      input_code<=adc_data;
      input_tag<=ungray(gray_sync)-TAG_SUB;
      if(!wr_busy && warmup!=15) warmup<=warmup+1'b1;
      if(push && full) overflow_sticky<=1;
    end
  end
  assign valid=!empty && !rd_busy && reset_n;
  xpm_fifo_async #(
    .FIFO_MEMORY_TYPE("auto"),.FIFO_WRITE_DEPTH(FIFO_DEPTH),
    .WRITE_DATA_WIDTH(48),.READ_DATA_WIDTH(48),
    .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.CDC_SYNC_STAGES(2),
    .RELATED_CLOCKS(0),.WR_DATA_COUNT_WIDTH($clog2(FIFO_DEPTH)+1),
    .RD_DATA_COUNT_WIDTH($clog2(FIFO_DEPTH)+1),
    .PROG_FULL_THRESH(FIFO_DEPTH-4),.PROG_EMPTY_THRESH(4),
    .USE_ADV_FEATURES("0000"),.SIM_ASSERT_CHK(0)
  ) fifo_i (
    .rst(reset_pipe[2]),.wr_clk(dco),.rd_clk(dsp_clk),
    .din({input_tag,input_code ^ 16'h8000}),.wr_en(push && !full),
    .dout(data),.rd_en(pop && valid),.full(full),.empty(empty),
    .wr_rst_busy(wr_busy),.rd_rst_busy(rd_busy),.sleep(1'b0),
    .injectsbiterr(1'b0),.injectdbiterr(1'b0),
    .almost_empty(),.almost_full(),.data_valid(),.dbiterr(),.overflow(),
    .prog_empty(),.prog_full(),.rd_data_count(),.sbiterr(),.underflow(),
    .wr_ack(),.wr_data_count()
  );
endmodule
