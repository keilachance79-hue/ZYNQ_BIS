`timescale 1ns/1ps
module scan_check #(parameter integer N=32,SAMPLES=16)(output reg done);
  initial done=0;
  localparam TOTAL=N*(N-3), WAIT_CYCLES=12, AW=$clog2(SAMPLES);
  reg clk=0;always #5 clk=~clk;
  reg reset_n=0,start=0,stop=0,abort_scan=0,system_ready=1;
  reg [31:0] scan_id=77,calibration_id=99,latest_tag=0;
  wire [31:0] capture_completed;
  wire [7:0] capture_fault;
  wire request_ready,request_valid,descriptor_valid;
  reg descriptor_ready=0;
  wire [31:0] request_start,request_id,request_calibration,descriptor_scan_id,measurements_completed;
  wire [9:0] measurement_index;
  wire [23:0] electrodes;
  wire [19:0] mux_address;
  wire busy,scan_done,acquisition_abort;
  wire [3:0] fault;
  phase5_scan_top #(.ELECTRODE_NUM(N),.FRAME_SAMPLES(SAMPLES),.MUX_SWITCH_WAIT_CYCLES(WAIT_CYCLES),
    .START_LEAD_SAMPLES(2*SAMPLES),.TIMEOUT_CYCLES(50000)) dut(.*);
  reg [31:0] tag=0;
  wire [47:0] a_data={tag,tag[15:0]},b_data={tag,~tag[15:0]};
  reg sample_valid=0,read_ready=0;
  wire a_pop,b_pop,active,m_valid,m_last;
  wire [1:0] banks_ready;
  wire [31:0] m_data,m_frame_id,m_start,m_calibration,aborted_frames;
  wire [AW-1:0] m_index;
  adc_frame_buffer #(.N(SAMPLES)) buffer_i(.clk(clk),.reset_n(reset_n),.clock_ok(1'b1),.alignment_verified(1'b1),
    .overflow_a(1'b0),.overflow_b(1'b0),.a_data(a_data),.b_data(b_data),.a_valid(sample_valid),.b_valid(sample_valid),
    .a_pop(a_pop),.b_pop(b_pop),.request_valid(request_valid),.request_ready(request_ready),
    .request_start(request_start),.request_id(request_id),.request_calibration(request_calibration),
    .fault(capture_fault),.active(active),.banks_ready(banks_ready),.m_data(m_data),.m_valid(m_valid),.m_ready(read_ready),
    .m_last(m_last),.m_index(m_index),.m_frame_id(m_frame_id),.m_start(m_start),.m_calibration(m_calibration),
    .completed_frames(capture_completed),.aborted_frames(aborted_frames));
  reg [43:0] golden[0:TOTAL-1];
  reg [31:0] epochs[0:TOTAL-1];
  reg [19:0] previous_address=0;
  integer cycles=0,requests=0,frames_read=0,word_index=0,last_switch=-1000,overlaps=0,stalls=0;
  integer fd;
  reg [15:0] expected_sample;
  reg [128+AW:0] held;
  reg stalled=0;
  always @(negedge clk) begin
    sample_valid<=reset_n && cycles%4==0;
    descriptor_ready<=reset_n && cycles%7!=0;
    // Deliberately exhaust both banks, then drain more slowly than sampling.
    read_ready<=reset_n && cycles>650 && cycles%8==0;
  end
  always @(posedge clk) begin
    cycles=cycles+1;
    if(cycles>500000) $fatal(1,"N=%0d global timeout",N);
    if(reset_n) begin
      if(sample_valid && a_pop && b_pop) begin latest_tag<=tag;tag<=tag+1;end
      if(fault || capture_fault || acquisition_abort || aborted_frames) $fatal(1,"N=%0d faults %h %h",N,fault,capture_fault);
      if(mux_address!=previous_address) begin
        if(active) $fatal(1,"Changed MUX during capture");
        if(m_valid || banks_ready!=0) overlaps=overlaps+1;
        last_switch=cycles;previous_address=mux_address;
      end
      if(busy && !request_ready && !active) stalls=stalls+1;
      if(request_valid && request_ready) begin
        if(!descriptor_valid || !descriptor_ready) $fatal(1,"Descriptor lost");
        if(requests>=TOTAL || {mux_address,electrodes}!==golden[requests]) $fatal(1,"N=%0d map/order index=%0d",N,requests);
        if(cycles-last_switch<WAIT_CYCLES) $fatal(1,"Settling too short");
        if(measurement_index!=requests || request_id!=requests || descriptor_scan_id!=77 || request_calibration!=99)
          $fatal(1,"Metadata mismatch");
        if(request_start%SAMPLES || $signed(request_start-latest_tag)<=0) $fatal(1,"Bad epoch");
        epochs[requests]=request_start;
        $fdisplay(fd,"%0d,%0d,%0d,%0d,%h,%h",requests,cycles,request_start,capture_completed,electrodes,mux_address);
        requests=requests+1;
      end
      if(descriptor_valid && descriptor_ready && !(request_valid && request_ready)) $fatal(1,"Orphan descriptor");
      if(stalled && (!m_valid || {m_data,m_frame_id,m_start,m_calibration,m_index,m_last}!==held)) $fatal(1,"Buffered output unstable");
      held={m_data,m_frame_id,m_start,m_calibration,m_index,m_last};stalled=m_valid && !read_ready;
      if(m_valid && read_ready) begin
        if(frames_read>=requests || m_frame_id!=frames_read || m_start!=epochs[frames_read] || m_calibration!=99 || m_index!=word_index || m_last!=(word_index==SAMPLES-1))
          $fatal(1,"Buffered data metadata mismatch");
        expected_sample=epochs[frames_read]+word_index;
        if(m_data!=={~expected_sample,expected_sample}) $fatal(1,"Sample mismatch");
        if(m_last) begin frames_read=frames_read+1;word_index=0;end else word_index=word_index+1;
      end
    end
  end
  initial begin
    $readmemh($sformatf("scan_%0d.hex",N),golden);
    fd=$fopen($sformatf("scan_%0d_%0d_trace.csv",N,SAMPLES),"w");
    $fdisplay(fd,"index,cycle,start_tag,completed_at_request,electrodes_hex,addresses_hex");
    repeat(10) @(negedge clk);reset_n=1;repeat(10) @(negedge clk);start=1;
    @(negedge clk);start=0;
    wait(scan_done);@(negedge clk);
    if(requests!=TOTAL || measurements_completed!=TOTAL) $fatal(1,"Scan count mismatch");
    wait(frames_read==TOTAL);repeat(5) @(negedge clk);
    if(overlaps<1 || (SAMPLES==16 && stalls<1)) $fatal(1,"Missing pipeline/backpressure coverage");
    $fclose(fd);done=1;
    $display("SCAN_PASS N=%0d frame_samples=%0d requests=%0d samples=%0d overlaps=%0d stalls=%0d",N,SAMPLES,requests,frames_read*SAMPLES,overlaps,stalls);
  end
endmodule

module fault_check(output reg done);
  initial done=0;
  reg clk=0;always #5 clk=~clk;
  reg reset_n=0,start=0,stop=0,abort_scan=0,system_ready=1;
  reg [31:0] scan_id=1,calibration_id=2,latest_tag=0,capture_completed=0;
  reg [7:0] capture_fault=0;
  reg request_ready=1,descriptor_ready=1;
  wire request_valid,descriptor_valid,busy,scan_done,acquisition_abort;
  wire [31:0] request_start,request_id,request_calibration,descriptor_scan_id,measurements_completed;
  wire [9:0] measurement_index;wire [23:0] electrodes;wire [19:0] mux_address;wire [3:0] fault;
  phase5_scan_top #(.ELECTRODE_NUM(4),.FRAME_SAMPLES(16),.MUX_SWITCH_WAIT_CYCLES(10),
    .START_LEAD_SAMPLES(32),.TIMEOUT_CYCLES(100)) dut(.*);
  task reset_all;
    begin
      @(negedge clk);reset_n=0;start=0;stop=0;abort_scan=0;system_ready=1;request_ready=1;descriptor_ready=1;
      latest_tag=0;capture_completed=0;capture_fault=0;
      repeat(5) @(negedge clk);reset_n=1;repeat(3) @(negedge clk);
    end
  endtask
  task launch;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
  task check_fault(input [3:0] expected);
    begin
      repeat(3) @(negedge clk);
      if(fault!==expected || busy || request_valid || !acquisition_abort) $fatal(1,"Fault mismatch %h expected %h",fault,expected);
      repeat(5) @(negedge clk);if(fault!==expected) $fatal(1,"Not sticky");
    end
  endtask
  initial begin
    reset_all;system_ready=0;launch;check_fault(1);
    reset_all;launch;wait(dut.state==6);@(negedge clk);system_ready=0;check_fault(2);
    reset_all;launch;wait(dut.state==3);@(negedge clk);abort_scan=1;check_fault(2);
    reset_all;launch;wait(dut.state==6);@(negedge clk);capture_fault=8'h04;check_fault(2);
    reset_all;request_ready=0;launch;wait(fault!=0);check_fault(4);
    reset_all;launch;wait(dut.state==6);wait(fault!=0);check_fault(4);
    reset_all;launch;wait(dut.state==5);@(negedge clk);request_ready=0;descriptor_ready=0;latest_tag=request_start;check_fault(8);
    reset_all;launch;wait(dut.state==6);@(negedge clk);capture_completed=2;check_fault(8);
    // Tag wrap, latched scan config, and graceful stop after the in-flight capture.
    reset_all;latest_tag=32'hfffffff8;launch;wait(dut.state==6);
    if(request_start!==32'd32) $fatal(1,"Epoch wrap failed");
    @(negedge clk);stop=1;scan_id=8;calibration_id=9;
    repeat(5) @(negedge clk);
    if(!busy || request_calibration!=2 || descriptor_scan_id!=1) $fatal(1,"Stop/config changed in flight");
    capture_completed=1;wait(!busy);if(fault || scan_done || measurements_completed!=1) $fatal(1,"Stop failed");
    @(negedge clk);stop=0;launch;wait(dut.state==6);
    if(request_id!=1 || descriptor_scan_id!=8 || request_calibration!=9) $fatal(1,"Restart ID/config failed");
    // Reset during unsettled address update and request; no phantom completion.
    reset_all;launch;wait(dut.state==3);reset_all;
    launch;wait(dut.state==5);reset_all;
    if(request_valid || descriptor_valid || busy || fault) $fatal(1,"Reset failed");
    done=1;$display("FAULT_PASS cases=12");
  end
endmodule

module tb_phase5_scan;
  wire d4,d16,d32,df,d2048;
  scan_check #(.N(4)) c4(d4);
  scan_check #(.N(16)) c16(d16);
  scan_check #(.N(32)) c32(d32);
  scan_check #(.N(4),.SAMPLES(2048)) c2048(d2048);
  fault_check f(df);
  initial begin wait(d4 && d16 && d32 && df && d2048);$display("PHASE5_SCAN_PASS");$finish;end
  initial begin #6000000;$fatal(1,"Suite timeout");end
endmodule
