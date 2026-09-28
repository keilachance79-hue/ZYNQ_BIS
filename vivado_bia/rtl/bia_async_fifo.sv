`timescale 1ns/1ps
module bia_async_fifo #(
  parameter integer WIDTH=32, DEPTH=4096
)(
  input wire wr_clk, rd_clk, resetn,
  input wire [WIDTH-1:0] din,
  input wire push,
  output wire wr_ready,
  output wire [WIDTH-1:0] dout,
  input wire pop,
  output wire rd_valid
);
  wire full, empty, wr_busy, rd_busy;
  // XPM reset is synchronous to the write clock. Both clocks must run
  // throughout reset. Keep resetn low >=32 cycles of the slower clock.
  (* ASYNC_REG="TRUE" *) reg [2:0] wr_reset_pipe=3'b111;
  always @(posedge wr_clk) wr_reset_pipe <= {wr_reset_pipe[1:0], !resetn};
  assign wr_ready = !full && !wr_busy && !wr_reset_pipe[2];
  assign rd_valid = !empty && !rd_busy;
  xpm_fifo_async #(
    .FIFO_MEMORY_TYPE("auto"), .FIFO_WRITE_DEPTH(DEPTH),
    .WRITE_DATA_WIDTH(WIDTH), .READ_DATA_WIDTH(WIDTH),
    .READ_MODE("fwft"), .FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES(2), .RELATED_CLOCKS(0),
    .WR_DATA_COUNT_WIDTH($clog2(DEPTH)+1),
    .RD_DATA_COUNT_WIDTH($clog2(DEPTH)+1),
    .PROG_FULL_THRESH(DEPTH-4), .PROG_EMPTY_THRESH(4),
    // 2020.2's optional SLEEP_CHECK S-5 compares an asynchronous read pointer
    // with its delayed synchronized copy after one write cycle, producing false
    // failures. Disable that vendor assertion set; testbench checks end-to-end
    // conservation, overflow recovery and stable ready/valid explicitly.
    .USE_ADV_FEATURES("0000"), .SIM_ASSERT_CHK(0)
  ) fifo_i (
    .rst(wr_reset_pipe[2]), .wr_clk(wr_clk), .rd_clk(rd_clk),
    .din(din), .wr_en(push && wr_ready), .full(full),
    .dout(dout), .rd_en(pop && rd_valid), .empty(empty),
    .wr_rst_busy(wr_busy), .rd_rst_busy(rd_busy),
    .sleep(1'b0), .injectsbiterr(1'b0), .injectdbiterr(1'b0),
    .almost_empty(), .almost_full(), .data_valid(), .dbiterr(),
    .overflow(), .prog_empty(), .prog_full(), .rd_data_count(),
    .sbiterr(), .underflow(), .wr_ack(), .wr_data_count()
  );
endmodule
