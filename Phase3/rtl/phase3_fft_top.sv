`timescale 1ns/1ps
// Fixed 2048-point digital subsystem. No physical ADC/clock/pin assumptions.
module phase3_fft_top #(
  parameter integer TIMEOUT_CYCLES=1000000
)(
  input wire clk, reset_n,
  input wire [31:0] s_data,
  input wire s_valid,s_last,
  output wire s_ready,
  input wire [10:0] s_index,
  input wire [31:0] s_frame_id,s_start,s_calibration,
  output wire [127:0] m_data,
  output wire m_valid,m_last,
  input wire m_ready,
  output wire [10:0] m_bin,
  output wire [3:0] m_slot,
  output reg [31:0] m_frame_id,m_start,m_calibration,
  output reg [3:0] fault,
  output reg [31:0] completed_frames
);
  localparam LOAD=0,CONFIG=1,READ=2,SEND=3,DRAIN=4,EMIT=5,FAILED=6;
  reg [2:0] state=LOAD;
  (* ram_style="block" *) reg [31:0] samples [0:2047];
  reg [63:0] v_bins[0:8],i_bins[0:8];
  reg [10:0] load_index=0,feed_index=0,out_index=0;
  reg [3:0] emit_index=0,selected_count=0;
  reg channel=0;
  reg [31:0] sample_word=0;
  reg [31:0] idle_cycles=0;
  wire cfg_ready,fft_in_ready,fft_out_valid,fft_out_last;
  wire [63:0] fft_out_data;
  wire [15:0] fft_out_user;
  wire event_started,event_unexpected,event_missing,event_in_halt,event_out_halt,event_status_halt;
  wire fft_out_ready=reset_n && (state==READ || state==SEND || state==DRAIN);
  wire output_fire=fft_out_valid && fft_out_ready;
  wire input_fire=s_valid && s_ready;
  wire fft_input_fire=(state==SEND) && fft_in_ready;
  wire config_fire=(state==CONFIG) && cfg_ready;
  wire [15:0] real_input=channel ? sample_word[31:16] : sample_word[15:0];
  // Vendor fields are 28-bit two's-complement, byte-padded to 32 per component.
  wire [63:0] signed_output={{4{fft_out_data[59]}},fft_out_data[59:32],
                             {4{fft_out_data[27]}},fft_out_data[27:0]};
  function automatic [10:0] bin_at(input [3:0] slot);
    case(slot)
      0:bin_at=2; 1:bin_at=3; 2:bin_at=7; 3:bin_at=11; 4:bin_at=19;
      5:bin_at=37; 6:bin_at=61; 7:bin_at=113; 8:bin_at=199;
      default:bin_at=2047;
    endcase
  endfunction
  function automatic [3:0] slot_at(input [10:0] bin_number);
    case(bin_number)
      2:slot_at=0; 3:slot_at=1; 7:slot_at=2; 11:slot_at=3; 19:slot_at=4;
      37:slot_at=5; 61:slot_at=6; 113:slot_at=7; 199:slot_at=8;
      default:slot_at=15;
    endcase
  endfunction
  wire [3:0] output_slot=slot_at(fft_out_user[10:0]);
  assign s_ready=reset_n && state==LOAD;
  assign m_valid=reset_n && state==EMIT;
  assign m_last=(emit_index==8);
  assign m_slot=emit_index;
  assign m_bin=bin_at(emit_index);
  assign m_data={i_bins[emit_index],v_bins[emit_index]};

  fft2048 fft_i(
    .aclk(clk),.aresetn(reset_n),
    .s_axis_config_tdata(8'h01),.s_axis_config_tvalid(state==CONFIG && reset_n),.s_axis_config_tready(cfg_ready),
    .s_axis_data_tdata({16'b0,real_input}),.s_axis_data_tvalid(state==SEND && reset_n),
    .s_axis_data_tready(fft_in_ready),.s_axis_data_tlast(feed_index==2047),
    .m_axis_data_tdata(fft_out_data),.m_axis_data_tuser(fft_out_user),
    .m_axis_data_tvalid(fft_out_valid),.m_axis_data_tready(fft_out_ready),.m_axis_data_tlast(fft_out_last),
    .event_frame_started(event_started),.event_tlast_unexpected(event_unexpected),.event_tlast_missing(event_missing),
    .event_status_channel_halt(event_status_halt),.event_data_in_channel_halt(event_in_halt),
    .event_data_out_channel_halt(event_out_halt)
  );

  // Synchronous frame RAM read. Output register holds while the FFT is stalled.
  always @(posedge clk) begin
    if(state==READ) sample_word<=samples[feed_index];
    if(input_fire) samples[load_index]<=s_data;
  end
  always @(posedge clk) begin
    if(!reset_n) begin
      state<=LOAD; load_index<=0; feed_index<=0; out_index<=0; emit_index<=0;
      selected_count<=0; channel<=0; fault<=0; idle_cycles<=0;
      m_frame_id<=0; m_start<=0; m_calibration<=0; completed_frames<=0;
    end else begin
      if(input_fire || fft_input_fire || output_fire || config_fire || state==EMIT || (state==LOAD && load_index==0))
        idle_cycles<=0;
      else if(state!=FAILED) idle_cycles<=idle_cycles+1;
      case(state)
        LOAD: if(input_fire) begin
          if(load_index==0) begin
            m_frame_id<=s_frame_id; m_start<=s_start; m_calibration<=s_calibration;
          end
          if(load_index==2047) begin
            load_index<=0; channel<=0; feed_index<=0; out_index<=0; selected_count<=0; state<=CONFIG;
          end else load_index<=load_index+1;
          if(s_index!=load_index || s_last!=(load_index==2047) ||
             (load_index!=0 && {s_frame_id,s_start,s_calibration}!={m_frame_id,m_start,m_calibration})) begin
            fault[0]<=1; state<=FAILED;
          end
        end
        CONFIG: if(config_fire) state<=READ;
        READ: state<=SEND;
        SEND: if(fft_input_fire) begin
          if(feed_index==2047) state<=DRAIN;
          else begin feed_index<=feed_index+1; state<=READ; end
        end
        EMIT: if(m_valid && m_ready) begin
          if(emit_index==8) begin state<=LOAD; emit_index<=0; completed_frames<=completed_frames+1; end
          else emit_index<=emit_index+1;
        end
        default: ;
      endcase
      if(output_fire) begin
        if(output_slot!=15) begin
          if(channel) i_bins[output_slot]<=signed_output;
          else v_bins[output_slot]<=signed_output;
          selected_count<=selected_count+1;
        end
        if(out_index==2047) begin
          if(channel) begin state<=EMIT; emit_index<=0; end
          else begin channel<=1; state<=CONFIG; feed_index<=0; end
          out_index<=0; selected_count<=0;
        end else out_index<=out_index+1;
        if(fft_out_user[10:0]!=out_index || fft_out_last!=(out_index==2047) ||
           (out_index==2047 && selected_count!=9)) begin fault[2]<=1; state<=FAILED; end
      end
      // Halt events are expected with valid/ready gaps and are not data faults.
      if(event_unexpected || event_missing) begin fault[1]<=1; state<=FAILED; end
      if(state!=FAILED && idle_cycles>=TIMEOUT_CYCLES-1 &&
         !(input_fire || fft_input_fire || output_fire || config_fire) &&
         state!=EMIT && !(state==LOAD && load_index==0)) begin fault[3]<=1; state<=FAILED; end
    end
  end
endmodule
