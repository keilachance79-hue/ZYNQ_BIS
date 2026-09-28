`timescale 1ns/1ps
`include "phase1_config.svh"
module tb_phase1_dac;
  localparam integer N=`PH1_ROM_LENGTH;
  localparam real EXPECT_PERIOD=1.0e9/`PH1_FS_HZ;
  reg ref_clk=0, reset_n=0;
  always #(0.5e9/`PH1_REF_CLK_HZ) ref_clk=~ref_clk;
  wire [15:0] dac_data;
  wire dac_clk,locked,valid,boundary;
  wire [$clog2(N)-1:0] sample_index;
  phase1_dac_top dut(.ref_clk(ref_clk),.reset_n(reset_n),.dac_data(dac_data),
    .dac_clk(dac_clk),.locked(locked),.sample_valid(valid),.period_start(boundary),
    .sample_index(sample_index));
  reg [15:0] expected[0:N-1];
  integer count=0, epoch=0, total=0, fd, boundaries=0;
  realtime last_change=-1000, last_latch=-1000, last_fall=-1000, last_rise=-1000;
  realtime first_time, elapsed, min_setup=1e9, min_hold=1e9;
  reg checking=0;
  always @(dac_data) begin
    if(reset_n && locked && checking && $realtime-last_latch<min_hold)
      min_hold=$realtime-last_latch;
    if(reset_n && locked && checking && $realtime-last_latch<4.0)
      $fatal(1,"LTC1668 hold time below 4 ns");
    last_change=$realtime;
  end
  always @(negedge dac_clk) begin
    if(checking && $realtime-last_rise<6.0) $fatal(1,"Clock high below 6 ns");
    last_fall=$realtime;
  end
  always @(posedge dac_clk) begin
    last_rise=$realtime;
    #0.2;
    if(reset_n && valid) begin
      if(!locked) $fatal(1,"Valid data before MMCM lock");
      if(dac_data !== expected[count%N]) $fatal(1,"LUT mismatch epoch=%0d n=%0d",epoch,count);
      if(sample_index !== count%N) $fatal(1,"Sample index mismatch");
      if(boundary !== (count%N==0)) $fatal(1,"Period tag does not label DAC sample 0");
      if(boundary) boundaries=boundaries+1;
      if(last_rise-last_change<8.0) $fatal(1,"LTC1668 setup time below 8 ns");
      if(last_rise-last_change<min_setup) min_setup=last_rise-last_change;
      if(checking && last_rise-last_fall<8.0) $fatal(1,"Clock low below 8 ns");
      if(count==0) first_time=last_rise;
      if(count>0 && count%N==0) begin
        elapsed=(last_rise-first_time)/count;
        if(elapsed<EXPECT_PERIOD*0.9999 || elapsed>EXPECT_PERIOD*1.0001)
          $fatal(1,"Sample clock mean period mismatch: %f ns",elapsed);
      end
      $fwrite(fd,"%0d,%0d,%0d,%0d,%0.3f\n",epoch,count,sample_index,dac_data,last_rise);
      last_latch=last_rise; checking=1;
      count=count+1; total=total+1;
    end
  end
  initial begin
    $readmemh("waveform.hex",expected);
    fd=$fopen("dac_capture.csv","w");
    if(!fd) $fatal(1,"Cannot open capture file");
    $fwrite(fd,"epoch,ordinal,index,dac_code,time_ns\n");
    #177 reset_n=1;
    wait(count>=3*N+23);
    // Reset mid-period, away from clock edges. An abort invalidates timing.
    #17 checking=0; reset_n=0;
    #1;
    if(valid!==0 || dac_data!==16'h8000) $fatal(1,"Reset did not force idle code");
    #211 count=0; epoch=1; reset_n=1;
    wait(count>=2*N+7);
    #5;
    $fclose(fd);
    $display("PHASE1_TOP_PASS: samples=%0d boundaries=%0d min_setup_ns=%f min_hold_ns=%f mean_period_ns=%f",
      total,boundaries,min_setup,min_hold,elapsed);
    $finish;
  end
  initial begin #3000000; $fatal(1,"Simulation watchdog timeout"); end
endmodule
