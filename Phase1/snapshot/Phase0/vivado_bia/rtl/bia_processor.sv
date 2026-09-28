`timescale 1ns/1ps
module bia_processor #(
  parameter integer FRAME_LOG2=14,
  parameter ROM_FILE="sin1024.mem"
)(
  input wire clk,resetn,
  input bia_pkg::command_t command,
  input bia_pkg::metadata_t metadata,
  input wire meta_valid, output wire meta_pop,
  input wire [35:0] sample_data,
  input wire sample_valid, output wire sample_pop,
  output reg [31:0] p_data,
  output reg p_last,p_valid, input wire p_ready,
  input wire packet_complete,
  output wire [31:0] final_status,final_count
);
  import bia_pkg::*;
  localparam integer N=1<<FRAME_LOG2;
  typedef enum logic [3:0] {WAIT_START,HEADER,DATA,WAIT_DFT,RESULTS,WAIT_END,TRAILER,WAIT_RELEASE} state_t;
  state_t state;
  command_t active;
  reg [63:0] t_start,wave_epoch;
  reg [31:0] end_count,end_status,sample_index;
  reg end_seen;
  reg [6:0] word_index;
  reg [8*4*48-1:0] snapshot;
  wire dft_done;
  wire [8*4*48-1:0] dft_results;
  wire start_meta=(state==WAIT_START && meta_valid && !metadata.is_end);
  assign meta_pop=start_meta || (state!=WAIT_START && !end_seen && meta_valid && metadata.is_end);
  wire pad=end_seen && sample_index>=end_count;
  wire have_sample=sample_valid || pad;
  wire take_sample=(state==DATA && have_sample && (!active.raw_mode || p_ready));
  wire [31:0] data_pair=pad ? 32'b0:sample_data[31:0];
  assign sample_pop=take_sample && !pad;
  wire dft_valid=take_sample && !active.raw_mode;
  wire [47:0] result_component=snapshot[(word_index>>1)*48+:48];
  wire [63:0] t_end=t_start+N-1;
  assign final_status=end_status;
  assign final_count=end_count;
  bia_demod #(.FRAME_LOG2(FRAME_LOG2),.ROM_FILE(ROM_FILE)) demod_i(
    .clk(clk),.resetn(resetn),.start(start_meta),.freq_bins(command.freq_bins),
    .sample_valid(dft_valid),.sample_last(sample_index==N-1),
    .sample_v(data_pair[15:0]),.sample_i(data_pair[31:16]),
    .done(dft_done),.results(dft_results));
  always @* begin
    p_data=0; p_valid=0; p_last=0;
    case(state)
      HEADER: begin
        p_valid=1;
        case(word_index)
          0:p_data=MAGIC;
          1:p_data=32'h00010000|{31'b0,active.raw_mode};
          2:p_data=active.session_id;
          3:p_data=active.frame_id;
          4:p_data=active.config_id;
          5:p_data={12'b0,active.electrodes};
          6:p_data=t_start[31:0];
          7:p_data=t_start[63:32];
          8:p_data=wave_epoch[31:0];
          9:p_data=wave_epoch[63:32];
          10:p_data=N;
          11:p_data=active.fs_hz;
          12:p_data=8;
          13:p_data=active.raw_mode ? N*4:8*32;
          14:p_data=15; // Q1.15 reference fractional bits
          default:p_data=0;
        endcase
      end
      DATA: if(active.raw_mode) begin p_valid=have_sample; p_data=data_pair; end
      RESULTS: begin
        p_valid=1;
        p_data=word_index[0] ? {{16{result_component[47]}},result_component[47:32]} : result_component[31:0];
      end
      TRAILER: begin
        p_valid=1; p_last=(word_index==3);
        case(word_index)
          0:p_data=end_status;
          1:p_data=end_count;
          2:p_data=t_end[31:0];
          default:p_data=t_end[63:32];
        endcase
      end
      default: begin end
    endcase
  end
  always @(posedge clk) begin
    if(!resetn) begin
      state<=WAIT_START; active<='0; t_start<=0; wave_epoch<=0;
      end_count<=0; end_status<=0; end_seen<=0; sample_index<=0; word_index<=0; snapshot<=0;
    end else begin
      if(meta_pop && metadata.is_end) begin
        end_seen<=1; end_count<=metadata.accepted; end_status<=metadata.status;
      end
      case(state)
        WAIT_START: if(start_meta) begin
          active<=command; t_start<=metadata.tick; wave_epoch<=metadata.wave_epoch;
          end_seen<=0; end_count<=0; end_status<=0; sample_index<=0; word_index<=0;
          state<=HEADER;
        end
        HEADER: if(p_ready) begin
          if(word_index==15) begin word_index<=0; state<=DATA; end
          else word_index<=word_index+1'b1;
        end
        DATA: if(take_sample) begin
          if(sample_index==N-1) begin
            sample_index<=N;
            state<=active.raw_mode ? WAIT_END:WAIT_DFT;
          end else sample_index<=sample_index+1'b1;
        end
        WAIT_DFT: if(dft_done) begin snapshot<=dft_results; word_index<=0; state<=RESULTS; end
        RESULTS: if(p_ready) begin
          if(word_index==63) begin word_index<=0; state<=WAIT_END; end
          else word_index<=word_index+1'b1;
        end
        WAIT_END: if(end_seen) begin word_index<=0; state<=TRAILER; end
        TRAILER: if(p_ready) begin
          if(word_index==3) state<=WAIT_RELEASE;
          else word_index<=word_index+1'b1;
        end
        WAIT_RELEASE: if(packet_complete) state<=WAIT_START;
        default: state<=WAIT_START;
      endcase
    end
  end
endmodule
