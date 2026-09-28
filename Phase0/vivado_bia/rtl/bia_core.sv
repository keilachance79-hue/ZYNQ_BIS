`timescale 1ns/1ps
// AXI-Lite peripheral + AXI-Stream source. DMA and PS7 belong to the block design.
// meas_clk is the correctly phased ADC reception clock; both ADC buses must be
// valid on its rising edge. It must have a fixed relationship to external DACCLK.
module bia_core #(
  parameter integer FRAME_LOG2=14,
  parameter integer SAMPLE_FIFO_DEPTH=4096,
  parameter integer OUTPUT_FIFO_DEPTH=512,
  parameter integer ADC_CAPTURE_DELAY=9,
  parameter integer TIMESTAMP_CALIBRATED=0,
  parameter ROM_FILE="sin1024.mem"
)(
  (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 axi_clk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI:M_AXIS, ASSOCIATED_RESET axi_resetn" *)
  input wire axi_clk,
  (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 axi_resetn RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *)
  input wire axi_resetn,
  input wire meas_clk,
  input wire fault_in,
  input wire [15:0] adc_v,adc_i,
  input wire adc_valid,adc_or_v,adc_or_i,
  output wire [15:0] dac_data,
  output wire excitation_en,mux_en,
  output wire [19:0] electrodes,
  input wire [17:0] s_axi_awaddr,
  input wire [2:0] s_axi_awprot,
  input wire s_axi_awvalid,output wire s_axi_awready,
  input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,
  input wire s_axi_wvalid,output wire s_axi_wready,
  output wire [1:0] s_axi_bresp,output wire s_axi_bvalid,input wire s_axi_bready,
  input wire [17:0] s_axi_araddr,input wire [2:0] s_axi_arprot,
  input wire s_axi_arvalid,output wire s_axi_arready,
  output wire [31:0] s_axi_rdata,output wire [1:0] s_axi_rresp,
  output wire s_axi_rvalid,input wire s_axi_rready,
  output wire [31:0] m_axis_tdata,
  output wire [3:0] m_axis_tkeep,
  output wire m_axis_tlast,m_axis_tvalid,input wire m_axis_tready,
  output wire irq
);
  import bia_pkg::*;
  command_t command, command_rx;
  metadata_t meta_tx,meta_rx;
  wire cmd_push,cmd_ready,cmd_valid,cmd_pop;
  wire meta_push,meta_ready,meta_valid,meta_pop;
  wire [35:0] sample_tx,sample_rx;
  wire sample_push,sample_ready,sample_valid,sample_pop;
  wire ack_ready,ack_valid,ack_pop;
  wire packet_complete=m_axis_tvalid && m_axis_tready && m_axis_tlast;
  wire [31:0] final_status,final_count;
  wire busy,wave_we,wr_bank,rd_bank;
  wire [FRAME_LOG2-1:0] wr_addr,rd_addr;
  wire [15:0] wr_data,rd_data;
  wire [31:0] p_data;
  wire p_valid,p_ready,p_last;
  (* ASYNC_REG="TRUE" *) reg [2:0] meas_reset_pipe;
  always @(posedge meas_clk or negedge axi_resetn)
    if(!axi_resetn) meas_reset_pipe<=0;
    else meas_reset_pipe<={meas_reset_pipe[1:0],1'b1};
  wire meas_resetn=meas_reset_pipe[2];
  assign m_axis_tkeep=4'hf;
  assign irq=packet_complete; // DMA completion IRQ is preferred by PS software.
  bia_axil_regs #(.FRAME_LOG2(FRAME_LOG2)) regs_i(
    .clk(axi_clk),.resetn(axi_resetn),
    .s_axi_awaddr(s_axi_awaddr),.s_axi_awprot(s_axi_awprot),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),.s_axi_arprot(s_axi_arprot),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),
    .command(command),.cmd_push(cmd_push),.cmd_ready(cmd_ready),.packet_complete(packet_complete),
    .final_status(final_status),.final_count(final_count),.busy(busy),
    .wave_we(wave_we),.wave_bank(wr_bank),.wave_addr(wr_addr),.wave_data(wr_data));
  bia_async_fifo #(.WIDTH(COMMAND_W),.DEPTH(16)) cmd_fifo_i(
    .wr_clk(axi_clk),.rd_clk(meas_clk),.resetn(axi_resetn),.din(command),.push(cmd_push),.wr_ready(cmd_ready),
    .dout(command_rx),.pop(cmd_pop),.rd_valid(cmd_valid));
  bia_async_fifo #(.WIDTH(1),.DEPTH(16)) ack_fifo_i(
    .wr_clk(axi_clk),.rd_clk(meas_clk),.resetn(axi_resetn),.din(1'b1),.push(packet_complete),.wr_ready(ack_ready),
    .dout(),.pop(ack_pop),.rd_valid(ack_valid));
  bia_wave_ram #(.FRAME_LOG2(FRAME_LOG2)) wave_i(
    .wr_clk(axi_clk),.wr_en(wave_we),.wr_bank(wr_bank),.wr_addr(wr_addr),.wr_data(wr_data),
    .rd_clk(meas_clk),.rd_bank(rd_bank),.rd_addr(rd_addr),.rd_data(rd_data));
  bia_acquire #(.FRAME_LOG2(FRAME_LOG2),.ADC_CAPTURE_DELAY(ADC_CAPTURE_DELAY),.TIMESTAMP_CALIBRATED(TIMESTAMP_CALIBRATED)) acq_i(
    .clk(meas_clk),.resetn(meas_resetn),.fault_in(fault_in),.cmd(command_rx),.cmd_valid(cmd_valid),.cmd_pop(cmd_pop),
    .ack_valid(ack_valid),.ack_pop(ack_pop),.adc_v(adc_v),.adc_i(adc_i),.adc_valid(adc_valid),
    .adc_or_v(adc_or_v),.adc_or_i(adc_or_i),.sample_data(sample_tx),.sample_push(sample_push),.sample_ready(sample_ready),
    .metadata(meta_tx),.meta_push(meta_push),.meta_ready(meta_ready),
    .wave_bank(rd_bank),.wave_addr(rd_addr),.wave_data(rd_data),.dac_data(dac_data),
    .excitation_en(excitation_en),.mux_en(mux_en),.electrodes(electrodes));
  bia_async_fifo #(.WIDTH(36),.DEPTH(SAMPLE_FIFO_DEPTH)) sample_fifo_i(
    .wr_clk(meas_clk),.rd_clk(axi_clk),.resetn(axi_resetn),.din(sample_tx),.push(sample_push),.wr_ready(sample_ready),
    .dout(sample_rx),.pop(sample_pop),.rd_valid(sample_valid));
  bia_async_fifo #(.WIDTH(META_W),.DEPTH(16)) metadata_fifo_i(
    .wr_clk(meas_clk),.rd_clk(axi_clk),.resetn(axi_resetn),.din(meta_tx),.push(meta_push),.wr_ready(meta_ready),
    .dout(meta_rx),.pop(meta_pop),.rd_valid(meta_valid));
  bia_processor #(.FRAME_LOG2(FRAME_LOG2),.ROM_FILE(ROM_FILE)) processor_i(
    .clk(axi_clk),.resetn(axi_resetn),.command(command),.metadata(meta_rx),.meta_valid(meta_valid),.meta_pop(meta_pop),
    .sample_data(sample_rx),.sample_valid(sample_valid),.sample_pop(sample_pop),
    .p_data(p_data),.p_last(p_last),.p_valid(p_valid),.p_ready(p_ready),
    .packet_complete(packet_complete),.final_status(final_status),.final_count(final_count));
  bia_axis_fifo #(.DEPTH(OUTPUT_FIFO_DEPTH)) output_fifo_i(
    .clk(axi_clk),.resetn(axi_resetn),.s_data(p_data),.s_last(p_last),.s_valid(p_valid),.s_ready(p_ready),
    .m_data(m_axis_tdata),.m_last(m_axis_tlast),.m_valid(m_axis_tvalid),.m_ready(m_axis_tready));
endmodule
