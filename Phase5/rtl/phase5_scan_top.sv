`timescale 1ns/1ps
// Address-only ADG732 board. No fictitious enable/write/select FPGA outputs.
// All inputs synchronous to clk. Coupled request+descriptor handshake reserves both.
module phase5_scan_top #(
  parameter integer ELECTRODE_NUM=32, FRAME_SAMPLES=2048,
  parameter integer MUX_SWITCH_WAIT_CYCLES=5000, START_LEAD_SAMPLES=4096,
  parameter integer TIMEOUT_CYCLES=1000000
)(
  input wire clk,reset_n,start,stop,abort_scan,system_ready,
  input wire [31:0] scan_id,calibration_id,latest_tag,capture_completed,
  input wire [7:0] capture_fault,
  input wire request_ready,descriptor_ready,
  output wire request_valid,descriptor_valid,
  output reg [31:0] request_start,request_id,request_calibration,
  output reg [31:0] descriptor_scan_id,
  output reg [9:0] measurement_index,
  output reg [23:0] electrodes,
  output reg [19:0] mux_address,
  output reg busy,scan_done,
  output reg [3:0] fault,
  output wire acquisition_abort,
  output reg [31:0] measurements_completed
);
  import electrode_map_pkg::*;
  localparam IDLE=0,SELECT_PAIR=1,APPLY=2,SETTLE=3,ARM=4,REQUEST=5,CAPTURE=6,FAILED=7;
  localparam integer PARAM_OK=ELECTRODE_NUM>=4 && ELECTRODE_NUM<=32 &&
    FRAME_SAMPLES>=2 && (FRAME_SAMPLES&(FRAME_SAMPLES-1))==0 &&
    START_LEAD_SAMPLES>=FRAME_SAMPLES && START_LEAD_SAMPLES<32'h40000000 &&
    MUX_SWITCH_WAIT_CYCLES>=10 && TIMEOUT_CYCLES>=16;
  reg [2:0] state=IDLE;
  reg [5:0] ip=1,vp=1;
  wire [5:0] im=ip==ELECTRODE_NUM ? 6'd1 : ip+6'd1;
  wire [5:0] vm=vp==ELECTRODE_NUM ? 6'd1 : vp+6'd1;
  wire pair_allowed=ip!=vp && ip!=vm && im!=vp && im!=vm;
  reg [31:0] timer=0,capture_base=0,next_id=0;
  reg start_old=0,stop_pending=0;
  wire healthy=system_ready && capture_fault==0 && !abort_scan;
  wire request_future=$signed(request_start-latest_tag)>0;
  // This is an atomic ready-qualified event, not two independent AXI streams.
  assign request_valid=reset_n && state==REQUEST && healthy && request_future && descriptor_ready;
  assign descriptor_valid=reset_n && state==REQUEST && healthy && request_future && request_ready;
  wire fire=request_valid && request_ready;
  assign acquisition_abort=(fault!=0) || abort_scan || (busy && !healthy);
  always @(posedge clk) begin
    if(!reset_n) begin
      state<=IDLE;ip<=1;vp<=1;timer<=0;capture_base<=0;next_id<=0;
      start_old<=0;stop_pending<=0;busy<=0;scan_done<=0;fault<=0;
      request_start<=0;request_id<=0;request_calibration<=0;descriptor_scan_id<=0;
      measurement_index<=0;electrodes<=0;mux_address<=0;measurements_completed<=0;
    end else begin
      start_old<=start;scan_done<=0;
      if(busy && stop) stop_pending<=1;
      if(state==ARM || state==REQUEST || state==CAPTURE) timer<=timer+1;
      case(state)
        IDLE: if(start && !start_old) begin
          if(!PARAM_OK || !healthy) begin fault[0]<=1;state<=FAILED;end
          else begin
            busy<=1;ip<=1;vp<=1;measurement_index<=0;measurements_completed<=0;
            request_calibration<=calibration_id;descriptor_scan_id<=scan_id;
            stop_pending<=0;state<=SELECT_PAIR;
          end
        end
        SELECT_PAIR: begin
          if(stop_pending || stop) begin busy<=0;state<=IDLE;end
          else if(ip>ELECTRODE_NUM) begin busy<=0;scan_done<=1;state<=IDLE;end
          else if(pair_allowed) begin electrodes<={vm,vp,im,ip};state<=APPLY;end
          else if(vp==ELECTRODE_NUM) begin vp<=1;ip<=ip+1;end
          else vp<=vp+1;
        end
        APPLY: begin
          mux_address<={electrode_address(3,vm),electrode_address(2,vp),
                        electrode_address(1,im),electrode_address(0,ip)};
          timer<=0;state<=SETTLE;
        end
        SETTLE: begin
          if(timer==MUX_SWITCH_WAIT_CYCLES-1) begin timer<=0;state<=ARM;end
          else timer<=timer+1;
        end
        ARM: begin
          if(stop_pending || stop) begin busy<=0;state<=IDLE;end
          else if(request_ready && descriptor_ready) begin
            // Future integer-period epoch; wrap-safe within a signed half-range.
            request_start<=(latest_tag+START_LEAD_SAMPLES+FRAME_SAMPLES-1)&~(FRAME_SAMPLES-1);
            request_id<=next_id;timer<=0;state<=REQUEST;
          end
        end
        REQUEST: if(fire) begin
          capture_base<=capture_completed;next_id<=next_id+1;timer<=0;state<=CAPTURE;
        end else if(!request_future) begin fault[3]<=1;busy<=0;state<=FAILED;end
        CAPTURE: if(capture_completed!=capture_base) begin
          if(capture_completed!=capture_base+32'd1) begin fault[3]<=1;busy<=0;state<=FAILED;end
          else begin
            measurements_completed<=measurements_completed+1;
            measurement_index<=measurement_index+1;
            if(vp==ELECTRODE_NUM) begin vp<=1;ip<=ip+1;end else vp<=vp+1;
            state<=SELECT_PAIR;timer<=0;
          end
        end
        default: ;
      endcase
      if(busy && !healthy) begin fault[1]<=1;busy<=0;state<=FAILED;end
      if((state==ARM || state==REQUEST || state==CAPTURE) && timer>=TIMEOUT_CYCLES-1) begin
        fault[2]<=1;busy<=0;state<=FAILED;
      end
    end
  end
endmodule
