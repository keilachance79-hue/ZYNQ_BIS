`timescale 1ns/1ps
module tb_phase4_polar;
  `include "fixture_config.vh"
  reg clk=0;always #5 clk=~clk;
  reg reset_n=0,s_valid=0,s_last=0,m_ready=0;
  reg [127:0] s_data=0;
  reg [3:0] s_slot=0;
  reg [10:0] s_bin=0;
  reg [31:0] s_frame_id=0,s_start=0,s_calibration=0;
  wire s_ready,m_valid,m_last;
  wire [255:0] m_data;
  wire [7:0] m_flags;
  wire [3:0] m_slot;
  wire [10:0] m_bin;
  wire [31:0] m_frame_id,m_start,m_calibration,completed_frames;
  wire [1:0] fault;
  phase4_polar_top #(.TIMEOUT_CYCLES(1000)) dut(.*);
  reg [127:0] inputs[0:RECORDS-1];
  reg [263:0] expected[0:RECORDS-1];
  reg [64:0] core_expected[0:RECORDS*2-1];
  reg [31:0] rng=32'h74120261;
  reg core_allow=0,hold_output=0,checking=0;
  reg stalled=0,core_stalled=0;
  reg [375:0] held;
  reg [63:0] core_held;
  integer target_bins[0:8];
  integer reference_frame=0,result_count=0,total_results=0,total_cores=0,cycle=0,start_cycle=0,max_cycles=0,fd;
  integer core_offset;
  always @(negedge clk) begin
    rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    m_ready<=reset_n && !hold_output && rng[3:0]!=0;
    core_allow<=reset_n && dut.state==3 && rng[5:4]!=0;
  end
  always @(posedge clk) begin
    cycle=cycle+1;
    if(cycle>200000) $fatal(1,"Global timeout");
    if(!reset_n) begin stalled=0;core_stalled=0;end
    else begin
      if(stalled && (!m_valid || {m_data,m_flags,m_slot,m_bin,m_frame_id,m_start,m_calibration,m_last}!==held))
        $fatal(1,"Output changed under backpressure");
      held={m_data,m_flags,m_slot,m_bin,m_frame_id,m_start,m_calibration,m_last};
      stalled=m_valid && !m_ready;
      if(core_stalled && (!dut.core_out_valid || dut.core_out_data!==core_held)) $fatal(1,"CORDIC AXIS changed while stalled");
      core_held=dut.core_out_data;core_stalled=dut.core_out_valid && !dut.core_out_ready;
      if(checking) begin
        if(fault) $fatal(1,"Unexpected protocol fault %h",fault);
        if(dut.core_fire) begin
          core_offset=(reference_frame*9+dut.work_slot)*2+dut.channel;
          if(!core_expected[core_offset][64] || dut.core_out_data!==core_expected[core_offset][63:0])
            $fatal(1,"Core mismatch index=%0d got=%h expected=%h",core_offset,dut.core_out_data,core_expected[core_offset]);
          total_cores=total_cores+1;
        end
        if(m_valid && m_ready) begin
          if(result_count>=9 || m_slot!=result_count || m_bin!=target_bins[result_count] || m_last!=(result_count==8))
            $fatal(1,"Result ordering mismatch");
          if(m_frame_id!=1000+reference_frame || m_start!=2048*(reference_frame+1) || m_calibration!=900+reference_frame)
            $fatal(1,"Descriptor mismatch");
          if({m_flags,m_data}!==expected[reference_frame*9+result_count])
            $fatal(1,"Polar mismatch record=%0d got=%h expected=%h",reference_frame*9+result_count,{m_flags,m_data},expected[reference_frame*9+result_count]);
          $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d",m_frame_id,m_bin,m_flags,
            m_data[159:128],$signed(m_data[191:160]),m_data[223:192],$signed(m_data[255:224]));
          result_count=result_count+1;total_results=total_results+1;
        end
      end else if(m_valid) $fatal(1,"Output from invalid/interrupted frame");
    end
  end
  task reset_all;
    begin
      @(negedge clk);reset_n=0;s_valid=0;checking=0;hold_output=0;
      repeat(20) @(negedge clk);reset_n=1;repeat(20) @(negedge clk);
    end
  endtask
  task send_records(input integer f,input integer count,input integer bad);
    integer j;
    begin
      for(j=0;j<count;j=j+1) begin
        @(negedge clk);s_valid=0;
        if(rng[2:0]==0) repeat(3) @(negedge clk);
        s_data=inputs[f*9+j];s_slot=j;s_bin=target_bins[j];s_last=(j==8);
        s_frame_id=1000+f;s_start=2048*(f+1);s_calibration=900+f;
        if(bad==1 && j==2) s_last=1;
        if(bad==2 && j==8) s_last=0;
        if(bad==3 && j==2) s_slot=3;
        if(bad==4 && j==2) s_bin=113;
        if(bad==5 && j==2) s_start=7;
        s_valid=1;@(posedge clk);while(!s_ready) @(posedge clk);
      end
      @(negedge clk);s_valid=0;
    end
  endtask
  task expect_fault(input [1:0] value);
    begin
      repeat(5) @(negedge clk);
      if(fault!==value || s_ready || m_valid) $fatal(1,"Fault handling failed got=%h expected=%h",fault,value);
      repeat(20) @(negedge clk);
      if(fault!==value) $fatal(1,"Fault not sticky");
    end
  endtask
  integer f,k;
  initial begin
    target_bins[0]=2;target_bins[1]=3;target_bins[2]=7;target_bins[3]=11;target_bins[4]=19;
    target_bins[5]=37;target_bins[6]=61;target_bins[7]=113;target_bins[8]=199;
    $readmemh("input.hex",inputs);$readmemh("expected.hex",expected);$readmemh("core.hex",core_expected);
    fd=$fopen("polar_results.csv","w");
    $fdisplay(fd,"frame_id,bin,flags,v_amp_q14,v_phase_q29,i_amp_q14,i_phase_q29");
    force dut.core_out_ready=core_allow;
    reset_all;
    for(k=1;k<=5;k=k+1) begin send_records(0,k==2?9:3,k);expect_fault(1);reset_all;end
    send_records(0,2,0);repeat(1010) @(negedge clk);expect_fault(2);reset_all;
    send_records(0,3,0);reset_all;
    // Use a nonzero Phase3 frame to interrupt a real CORDIC operation.
    send_records(2,9,0);wait(dut.state==3);reset_all;
    for(f=0;f<FRAMES;f=f+1) begin
      reference_frame=f;result_count=0;checking=1;start_cycle=cycle;
      if(f==2) hold_output=1;
      send_records(f,9,0);
      if(f==2) begin wait(m_valid);repeat(100) @(negedge clk);if(s_ready) $fatal(1,"Frame overwritten");hold_output=0;end
      wait(result_count==9);@(negedge clk);
      if(completed_frames!=f+1) $fatal(1,"Completion count mismatch");
      if(cycle-start_cycle>max_cycles) max_cycles=cycle-start_cycle;
      checking=0;
    end
    release dut.core_out_ready;
    $fclose(fd);
    $display("PHASE4_POLAR_PASS frames=%0d records=%0d core_results=%0d max_cycles=%0d",FRAMES,total_results,total_cores,max_cycles);
    $finish;
  end
endmodule
