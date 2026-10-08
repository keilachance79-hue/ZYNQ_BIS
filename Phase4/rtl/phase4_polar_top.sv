`timescale 1ns/1ps
// Nine-bin frame adapter. Phase3 signed28 FFT integers, N fixed at 2048.
module phase4_polar_top #(parameter integer TIMEOUT_CYCLES=100000)(
  input wire clk,reset_n,
  input wire [127:0] s_data,
  input wire s_valid,s_last,
  output wire s_ready,
  input wire [3:0] s_slot,
  input wire [10:0] s_bin,
  input wire [31:0] s_frame_id,s_start,s_calibration,
  output wire [255:0] m_data,
  output wire [7:0] m_flags,
  output wire m_valid,m_last,
  input wire m_ready,
  output wire [3:0] m_slot,
  output wire [10:0] m_bin,
  output reg [31:0] m_frame_id,m_start,m_calibration,
  output reg [1:0] fault,
  output reg [31:0] completed_frames
);
  localparam LOAD=0,PREP=1,SEND=2,WAIT_RESULT=3,STORE=4,EMIT=5,FAILED=6,SCALE=7,NORMALIZE=8;
  localparam signed [31:0] PI_Q29=32'sd1686629713, HALF_PI_Q29=32'sd843314857;
  reg [3:0] state=LOAD;
  reg [31:0] abs_peak=0;
  reg [127:0] raw[0:8],polar[0:8];
  reg [7:0] flags[0:8];
  reg [3:0] load_slot=0,work_slot=0,emit_slot=0;
  reg channel=0;
  reg [5:0] shift_amount=0;
  reg [63:0] normalized=0;
  reg [31:0] result_amp=0,result_phase=0;
  reg [3:0] result_flags=0;
  reg [31:0] idle_cycles=0;
  wire signed [31:0] x=channel ? raw[work_slot][95:64] : raw[work_slot][31:0];
  wire signed [31:0] y=channel ? raw[work_slot][127:96] : raw[work_slot][63:32];
  wire range_bad=(x[31:27]!={5{x[27]}}) || (y[31:27]!={5{y[27]}});
  wire zero_vector=(x==0 && y==0);
  wire [31:0] abs_x=x[31] ? (~x+32'd1) : x;
  wire [31:0] abs_y=y[31] ? (~y+32'd1) : y;
  wire [31:0] max_abs=abs_x>abs_y ? abs_x : abs_y;
  function automatic [5:0] norm_shift(input [31:0] a);
    integer j;
    begin
      norm_shift=28;
      for(j=0;j<28;j=j+1) if(a[j]) norm_shift=28-j;
    end
  endfunction
  wire [5:0] next_shift=norm_shift(abs_peak);
  function automatic [10:0] bin_at(input [3:0] k);
    case(k)
      0:bin_at=2;1:bin_at=3;2:bin_at=7;3:bin_at=11;4:bin_at=19;
      5:bin_at=37;6:bin_at=61;7:bin_at=113;8:bin_at=199;default:bin_at=0;
    endcase
  endfunction
  wire core_in_ready,core_out_valid;
  wire [63:0] core_out_data;
  wire core_out_ready=reset_n && state==WAIT_RESULT;
  wire core_fire=core_out_valid && core_out_ready;
  // magnitude field Q2.30; phase field radians Q3.29.
  wire [31:0] magnitude=core_out_data[31:0];
  wire signed [31:0] raw_phase=core_out_data[63:32];
  wire [63:0] wide_magnitude={32'b0,magnitude};
  // Amp(Q18.14) = |FFT| * 16 = magnitude * 2^(4-normalization_shift).
  // Rounding at this final positive right shift is nearest, ties upward.
  wire [63:0] amplitude_scaled=(shift_amount>4) ?
     ((wide_magnitude+(64'd1<<(shift_amount-5)))>>(shift_amount-4)) :
     (wide_magnitude<<(4-shift_amount));
  wire overflow=(amplitude_scaled[63:32]!=0);
  wire input_fire=s_valid && s_ready;
  wire progress=input_fire || core_fire || (state==SEND && core_in_ready) || state==PREP || state==STORE || state==SCALE || state==NORMALIZE;
  assign s_ready=reset_n && state==LOAD;
  assign m_valid=reset_n && state==EMIT;
  assign m_slot=emit_slot;
  assign m_bin=bin_at(emit_slot);
  assign m_last=emit_slot==8;
  assign m_data={polar[emit_slot],raw[emit_slot]};
  assign m_flags=flags[emit_slot];
  polar32 cordic_i(.aclk(clk),.aresetn(reset_n),
    .s_axis_cartesian_tvalid(reset_n && state==SEND),.s_axis_cartesian_tready(core_in_ready),
    .s_axis_cartesian_tdata(normalized),.m_axis_dout_tvalid(core_out_valid),
    .m_axis_dout_tready(core_out_ready),.m_axis_dout_tdata(core_out_data));

  always @(posedge clk) begin
    if(!reset_n) begin
      state<=LOAD;load_slot<=0;work_slot<=0;emit_slot<=0;channel<=0;
      shift_amount<=0;abs_peak<=0;normalized<=0;result_amp<=0;result_phase<=0;result_flags<=0;
      idle_cycles<=0;fault<=0;completed_frames<=0;m_frame_id<=0;m_start<=0;m_calibration<=0;
    end else begin
      if(progress || state==EMIT || (state==LOAD && load_slot==0)) idle_cycles<=0;
      else if(state!=FAILED) idle_cycles<=idle_cycles+1;
      case(state)
        LOAD: if(input_fire) begin
          raw[load_slot]<=s_data;
          if(load_slot==0) begin m_frame_id<=s_frame_id;m_start<=s_start;m_calibration<=s_calibration;end
          if(load_slot==8) begin load_slot<=0;work_slot<=0;channel<=0;state<=PREP;end
          else load_slot<=load_slot+1;
          if(s_slot!=load_slot || s_bin!=bin_at(load_slot) || s_last!=(load_slot==8) ||
             (load_slot!=0 && {s_frame_id,s_start,s_calibration}!={m_frame_id,m_start,m_calibration})) begin
            fault[0]<=1;state<=FAILED;
          end
        end
        PREP: begin
          result_amp<=0;result_phase<=0;result_flags<=0;
          if(range_bad) begin result_flags<=4'b0010;state<=STORE;end
          else if(zero_vector) begin result_flags<=4'b1000;state<=STORE;end
          else begin
            abs_peak<=max_abs;
            state<=SCALE;
          end
        end
        SCALE: begin shift_amount<=next_shift;state<=NORMALIZE;end
        NORMALIZE: begin normalized<={(y<<<shift_amount),(x<<<shift_amount)};state<=SEND;end
        SEND: if(core_in_ready) state<=WAIT_RESULT;
        WAIT_RESULT: if(core_fire) begin
          result_amp<=overflow ? 32'hffffffff : amplitude_scaled[31:0];
          result_flags<={1'b0,overflow,1'b0,1'b1};
          // Canonical axes and branch cut: phase interval [-pi,pi).
          if(y==0) result_phase<=x[31] ? -PI_Q29 : 0;
          else if(x==0) result_phase<=y[31] ? -HALF_PI_Q29 : HALF_PI_Q29;
          else if(raw_phase>=PI_Q29) result_phase<=raw_phase-64'sd3373259426;
          else if(raw_phase < -PI_Q29) result_phase<=raw_phase+64'sd3373259426;
          else result_phase<=raw_phase;
          state<=STORE;
        end
        STORE: begin
          if(!channel) begin
            polar[work_slot][63:0]<={result_phase,result_amp};flags[work_slot][3:0]<=result_flags;
            channel<=1;state<=PREP;
          end else begin
            polar[work_slot][127:64]<={result_phase,result_amp};flags[work_slot][7:4]<=result_flags;
            channel<=0;
            if(work_slot==8) begin emit_slot<=0;state<=EMIT;end
            else begin work_slot<=work_slot+1;state<=PREP;end
          end
        end
        EMIT: if(m_ready) begin
          if(emit_slot==8) begin completed_frames<=completed_frames+1;emit_slot<=0;state<=LOAD;end
          else emit_slot<=emit_slot+1;
        end
        default: ;
      endcase
      if(state!=FAILED && state!=EMIT && !(state==LOAD && load_slot==0) && !progress && idle_cycles>=TIMEOUT_CYCLES-1) begin
        fault[1]<=1;state<=FAILED;
      end
    end
  end
endmodule
