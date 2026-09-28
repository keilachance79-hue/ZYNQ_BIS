`timescale 1ns/1ps
// Two complete-frame banks. No sample is exposed before its frame commits.
// All configuration and handshake signals on this module are dsp_clk domain.
module adc_frame_buffer #(
  parameter integer N=2048, TIMEOUT_CYCLES=2048, AW=$clog2(N)
)(
  input wire clk, reset_n, clock_ok, alignment_verified,
  input wire overflow_a, overflow_b,
  input wire [47:0] a_data,b_data,
  input wire a_valid,b_valid,
  output wire a_pop,b_pop,
  input wire request_valid,
  output wire request_ready,
  input wire [31:0] request_start,request_id,request_calibration,
  output reg [7:0] fault,
  output reg active,
  output wire [1:0] banks_ready,
  output reg [31:0] m_data,
  output reg m_valid,
  input wire m_ready,
  output reg m_last,
  output reg [AW-1:0] m_index,
  output reg [31:0] m_frame_id,m_start,m_calibration,
  output reg [31:0] completed_frames,aborted_frames
);
  localparam [7:0] F_OVERFLOW_A=1,F_OVERFLOW_B=2,F_TAG=4,F_GAP=8,
    F_TIMEOUT=16,F_CLOCK=32,F_ALIGNMENT=64,F_START=128;
  (* ram_style="block" *) reg [31:0] memory[0:2*N-1];
  reg [1:0] ready_bank;
  reg wr_bank,rd_bank;
  reg [AW-1:0] wr_index,rd_index;
  reg [31:0] expected,start_tag,frame_id,calibration;
  reg [31:0] bank_id[0:1],bank_start[0:1],bank_cal[0:1];
  reg [31:0] last_tag;
  reg have_pair;
  reg [$clog2(TIMEOUT_CYCLES+1)-1:0] silence;
  wire pair=a_valid && b_valid;
  wire equal_tag=a_data[47:16]==b_data[47:16];
  wire [31:0] tag=a_data[47:16];
  wire consecutive=!have_pair || tag==last_tag+1;
  // Ordered bank allocation means a stalled reader can never be overwritten.
  assign request_ready=reset_n && !active && !ready_bank[wr_bank] &&
    fault==0 && clock_ok && alignment_verified && have_pair;
  assign banks_ready=ready_bank;
  // Reset release can differ by one DCO cycle. Before the first common tag,
  // discard only the older head; after alignment any mismatch is a fault.
  assign a_pop=reset_n && fault==0 && pair &&
    (have_pair || equal_tag || $signed(a_data[47:16]-b_data[47:16])<0);
  assign b_pop=reset_n && fault==0 && pair &&
    (have_pair || equal_tag || $signed(b_data[47:16]-a_data[47:16])<0);
  reg [7:0] next_fault;
  always @* begin
    next_fault=0;
    if(overflow_a) next_fault=next_fault|F_OVERFLOW_A;
    if(overflow_b) next_fault=next_fault|F_OVERFLOW_B;
    if(pair && have_pair && !equal_tag) next_fault=next_fault|F_TAG;
    if(pair && equal_tag && !consecutive) next_fault=next_fault|F_GAP;
    if(silence==TIMEOUT_CYCLES-1) next_fault=next_fault|F_TIMEOUT;
    if((active || have_pair) && !clock_ok) next_fault=next_fault|F_CLOCK;
    if(active && !alignment_verified) next_fault=next_fault|F_ALIGNMENT;
    if(active && pair && wr_index==0 && $signed(tag-start_tag)>0)
      next_fault=next_fault|F_START;
    if(active && pair && wr_index!=0 && tag!=expected)
      next_fault=next_fault|F_GAP;
  end
  always @(posedge clk) begin
    if(!reset_n) begin
      ready_bank<=0; wr_bank<=0; rd_bank<=0; wr_index<=0; rd_index<=0;
      active<=0; fault<=0; expected<=0; start_tag<=0; frame_id<=0; calibration<=0;
      have_pair<=0; last_tag<=0; silence<=0;
      m_valid<=0; m_last<=0; m_index<=0; m_frame_id<=0; m_start<=0; m_calibration<=0;
      completed_frames<=0; aborted_frames<=0;
    end else begin
      if(pair && equal_tag) begin silence<=0; have_pair<=1; last_tag<=tag; end
      else if(silence<TIMEOUT_CYCLES) silence<=silence+1'b1;
      if(fault==0 && next_fault!=0) begin
        fault<=next_fault;
        if(active) begin active<=0; aborted_frames<=aborted_frames+1; end
      end else if(fault==0) begin
        if(request_valid && request_ready) begin
          active<=1; start_tag<=request_start; expected<=request_start;
          frame_id<=request_id; calibration<=request_calibration; wr_index<=0;
        end
        if(active && pair && (wr_index!=0 || tag==start_tag)) begin
          memory[wr_bank*N+wr_index]<={b_data[15:0],a_data[15:0]};
          expected<=tag+1;
          if(wr_index==N-1) begin
            ready_bank[wr_bank]<=1; bank_id[wr_bank]<=frame_id;
            bank_start[wr_bank]<=start_tag; bank_cal[wr_bank]<=calibration;
            wr_bank<=!wr_bank; active<=0; completed_frames<=completed_frames+1;
          end else wr_index<=wr_index+1'b1;
        end
      end
      // Single synchronous memory read; one elastic output word. Once valid,
      // data AND descriptor remain stable until ready, including on faults.
      if(!m_valid || m_ready) begin
        m_valid<=0;
        if(m_valid && m_last) begin
          ready_bank[rd_bank]<=0; rd_bank<=!rd_bank; rd_index<=0;
        end else if(ready_bank[rd_bank]) begin
          m_data<=memory[rd_bank*N+rd_index]; m_valid<=1;
          m_index<=rd_index; m_last<=(rd_index==N-1);
          m_frame_id<=bank_id[rd_bank]; m_start<=bank_start[rd_bank];
          m_calibration<=bank_cal[rd_bank]; rd_index<=rd_index+1'b1;
        end
      end
    end
  end
endmodule
