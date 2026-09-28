`timescale 1ns/1ps
module bia_acquire #(
  parameter integer FRAME_LOG2=14,
  parameter integer ADC_CAPTURE_DELAY=9,
  parameter integer TIMESTAMP_CALIBRATED=0
)(
  input wire clk, resetn, fault_in,
  input bia_pkg::command_t cmd,
  input wire cmd_valid, output wire cmd_pop,
  input wire ack_valid, output wire ack_pop,
  input wire [15:0] adc_v,adc_i,
  input wire adc_valid, adc_or_v, adc_or_i,
  output wire [35:0] sample_data,
  output wire sample_push, input wire sample_ready,
  output bia_pkg::metadata_t metadata,
  output wire meta_push, input wire meta_ready,
  output wire wave_bank,
  output reg [FRAME_LOG2-1:0] wave_addr,
  input wire [15:0] wave_data,
  output reg [15:0] dac_data,
  output wire excitation_en, mux_en,
  output wire [19:0] electrodes
);
  import bia_pkg::*;
  localparam integer N=1<<FRAME_LOG2;
  typedef enum logic[3:0] {IDLE,BREAK,SETTLE,ALIGN,SEND_START,CAPTURE,SEND_END,WAIT_ACK} state_t;
  state_t state;
  command_t active;
  reg [63:0] tick, wave_epoch, frame_start;
  reg [31:0] wait_count, sample_count, accepted,status;
  reg dropping;
  (* ASYNC_REG="TRUE" *) reg fault1,fault2;
  reg [FRAME_LOG2-1:0] wave_index_q,dac_index;
  wire playing=(state==SETTLE || state==ALIGN || state==SEND_START || state==CAPTURE);
  assign excitation_en=playing && !fault2 && !fault_in;
  assign mux_en=(state!=IDLE && state!=BREAK && state!=WAIT_ACK) && !fault2 && !fault_in;
  assign electrodes=active.electrodes;
  assign wave_bank=active.bank;
  assign cmd_pop=(state==IDLE && cmd_valid);
  assign ack_pop=(state==WAIT_ACK && ack_valid);
  wire [15:0] v_signed=adc_v ^ (active.adc_offset_binary ? 16'h8000:16'h0000);
  wire [15:0] i_signed=adc_i ^ (active.adc_offset_binary ? 16'h8000:16'h0000);
  assign sample_data={adc_or_i,adc_or_v,(sample_count==N-1),(sample_count==0),i_signed,v_signed};
  assign sample_push=(state==CAPTURE && adc_valid && !dropping && !fault2 && sample_ready);
  assign meta_push=((state==SEND_START || state==SEND_END) && meta_ready);
  always @* begin
    metadata='0;
    metadata.is_end=(state==SEND_END);
    metadata.tick=(state==SEND_START) ? tick+64'd1-ADC_CAPTURE_DELAY : frame_start;
    metadata.wave_epoch=wave_epoch;
    metadata.accepted=accepted;
    metadata.status=status;
  end
  // Launch DAC data on the falling edge; board timing must verify setup/hold
  // relative to the external DAC clock. This is not a generated DAC clock.
  always @(negedge clk) begin
    if(!resetn) begin dac_data<=16'h8000; dac_index<=0; end
    else if(excitation_en) begin dac_data<=wave_data; dac_index<=wave_index_q; end
    else begin dac_data<=16'h8000; dac_index<=0; end
  end
  always @(posedge clk) begin
    if(!resetn) begin
      state<=IDLE; active<='0; tick<=0; wave_epoch<=0; frame_start<=0;
      wait_count<=0; sample_count<=0; accepted<=0; status<=0; dropping<=0;
      wave_addr<=0; wave_index_q<=0; fault1<=0; fault2<=0;
    end else begin
      tick<=tick+1'b1; fault1<=fault_in; fault2<=fault1;
      wave_index_q<=wave_addr;
      if(playing) wave_addr<=wave_addr+1'b1;
      else wave_addr<=0;
      case(state)
        IDLE: if(cmd_valid) begin
          active<=cmd; wait_count<=0; accepted<=0; sample_count<=0; dropping<=0;
          status<=TIMESTAMP_CALIBRATED ? 0:32'h10;
          state<=BREAK;
        end
        BREAK: begin
          // At least two cycles to prefetch bank data and break old MUX path.
          if(wait_count>=active.break_cycles && wait_count>=2) begin
            state<=SETTLE; wait_count<=0; wave_addr<=1;
            wave_epoch<=tick+1'b1;
          end else wait_count<=wait_count+1'b1;
        end
        SETTLE: if(wait_count>=active.settle_cycles) state<=ALIGN;
                else wait_count<=wait_count+1'b1;
        ALIGN: if(dac_index==0) state<=SEND_START;
        SEND_START: if(meta_ready) begin
          frame_start<=tick+64'd1-ADC_CAPTURE_DELAY;
          sample_count<=0; state<=CAPTURE;
        end
        CAPTURE: begin
          if(adc_or_v) status[1]<=1;
          if(adc_or_i) status[2]<=1;
          if(fault2) begin status[3]<=1; dropping<=1; end
          if(!adc_valid) begin status[6]<=1; dropping<=1; end
          if(!dropping && !fault2 && adc_valid) begin
            if(sample_ready) accepted<=accepted+1'b1;
            else begin status[0]<=1; dropping<=1; end
          end
          if(sample_count==N-1) state<=SEND_END;
          else sample_count<=sample_count+1'b1;
        end
        SEND_END: if(meta_ready) state<=WAIT_ACK;
        WAIT_ACK: if(ack_valid) state<=IDLE;
        default: state<=IDLE;
      endcase
    end
  end
endmodule
