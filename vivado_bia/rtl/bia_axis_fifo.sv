`timescale 1ns/1ps
module bia_axis_fifo #(parameter integer DEPTH=512)(
  input wire clk, resetn,
  input wire [31:0] s_data, input wire s_last, s_valid,
  output wire s_ready,
  output wire [31:0] m_data, output wire m_last, m_valid,
  input wire m_ready
);
  localparam integer AW=$clog2(DEPTH);
  (* ram_style="distributed" *) reg [32:0] mem[0:DEPTH-1];
  reg [AW-1:0] wp, rp;
  reg [AW:0] count;
  wire push=s_valid && s_ready, pop=m_valid && m_ready;
  assign s_ready=(count<DEPTH);
  assign m_valid=(count!=0);
  assign {m_last,m_data}=mem[rp];
  always @(posedge clk) begin
    if(!resetn) begin wp<=0; rp<=0; count<=0; end
    else begin
      if(push) begin mem[wp]<={s_last,s_data}; wp<=wp+1'b1; end
      if(pop) rp<=rp+1'b1;
      case({push,pop})
        2'b10: count<=count+1'b1;
        2'b01: count<=count-1'b1;
        default: count<=count;
      endcase
    end
  end
endmodule
