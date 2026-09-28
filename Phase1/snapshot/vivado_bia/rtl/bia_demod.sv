`timescale 1ns/1ps
module bia_demod #(
  parameter integer FRAME_LOG2=14,
  parameter ROM_FILE="sin1024.mem"
)(
  input wire clk, resetn, start,
  input wire [8*14-1:0] freq_bins,
  input wire sample_valid, sample_last,
  input wire signed [15:0] sample_v, sample_i,
  output reg done,
  output wire [8*4*48-1:0] results
);
  // Eight parallel lanes; four signed products per lane. Q1.15 references.
  // Imaginary component uses -sin: sum(x[n] * exp(-j*2*pi*k*n/N)).
  genvar k;
  reg v1,v2,last1,last2;
  reg signed [15:0] sv,si;
  always @(posedge clk) begin
    if(!resetn || start) begin
      v1<=0; v2<=0; last1<=0; last2<=0; done<=0; sv<=0; si<=0;
    end else begin
      v1<=sample_valid; v2<=v1;
      last1<=sample_last; last2<=last1;
      done<=v2 && last2;
      if(sample_valid) begin sv<=sample_v; si<=sample_i; end
    end
  end
  generate for(k=0;k<8;k=k+1) begin: lane
    reg [FRAME_LOG2-1:0] phase;
    wire signed [15:0] sn,cs;
    reg signed [31:0] pv_r,pv_s,pi_r,pi_s;
    reg signed [47:0] av_r,av_i,ai_r,ai_i;
    bia_sincos_rom #(.FRAME_LOG2(FRAME_LOG2),.ROM_FILE(ROM_FILE)) rom_i(
      .clk(clk),.en(sample_valid),.phase(phase),.sin_q(sn),.cos_q(cs));
    always @(posedge clk) begin
      if(!resetn || start) begin
        phase<=0; av_r<=0; av_i<=0; ai_r<=0; ai_i<=0;
        pv_r<=0; pv_s<=0; pi_r<=0; pi_s<=0;
      end else begin
        if(sample_valid) phase<=phase+freq_bins[k*14+:14];
        if(v1) begin
          pv_r<=sv*cs; pv_s<=sv*sn; pi_r<=si*cs; pi_s<=si*sn;
        end
        if(v2) begin
          av_r<=av_r+{{16{pv_r[31]}},pv_r};
          av_i<=av_i-{{16{pv_s[31]}},pv_s};
          ai_r<=ai_r+{{16{pi_r[31]}},pi_r};
          ai_i<=ai_i-{{16{pi_s[31]}},pi_s};
        end
      end
    end
    assign results[(k*4+0)*48+:48]=av_r;
    assign results[(k*4+1)*48+:48]=av_i;
    assign results[(k*4+2)*48+:48]=ai_r;
    assign results[(k*4+3)*48+:48]=ai_i;
  end endgenerate
endmodule
