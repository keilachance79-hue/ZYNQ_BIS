`timescale 1ns/1ps
module bia_sincos_rom #(
  parameter integer FRAME_LOG2=14,
  parameter ROM_FILE="sin1024.mem"
)(
  input wire clk, en,
  input wire [FRAME_LOG2-1:0] phase,
  output reg signed [15:0] sin_q, cos_q
);
  (* ram_style="block" *) reg signed [15:0] mem[0:1023];
  wire [9:0] addr;
  generate if(FRAME_LOG2>=10) begin
    assign addr=phase >> (FRAME_LOG2-10);
  end else begin
    assign addr=phase << (10-FRAME_LOG2);
  end endgenerate
  wire [9:0] cos_addr=addr+10'd256;
  initial $readmemh(ROM_FILE,mem);
  always @(posedge clk) if(en) begin
    sin_q<=mem[addr]; cos_q<=mem[cos_addr];
  end
endmodule
