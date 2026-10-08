`timescale 1ns/1ps
module tb_phase3_fft;
  `include "fixture_config.vh"
  reg clk=0; always #5 clk=~clk;
  reg reset_n=0,s_valid=0,s_last=0,m_ready=0;
  reg [31:0] s_data=0,s_frame_id=0,s_start=0,s_calibration=0;
  reg [10:0] s_index=0;
  wire s_ready,m_valid,m_last;
  wire [127:0] m_data;
  wire [31:0] m_frame_id,m_start,m_calibration,completed_frames;
  wire [10:0] m_bin;
  wire [3:0] m_slot,fault;
  phase3_fft_top #(.TIMEOUT_CYCLES(30000)) dut(.*);
  reg [31:0] inputs[0:FRAMES*2048-1];
  reg [63:0] golden[0:FRAMES*4096-1];
  reg [31:0] rng=32'h20261008;
  reg fft_allow=0, checking=0,hold_output=0;
  integer reference_frame=0,fft_count=0,result_count=0,total_fft=0,total_bins=0;
  integer cycle=0,start_cycle=0,max_latency=0,logfile;
  reg stalled=0,fft_stalled=0;
  reg [239:0] held;
  reg [80:0] fft_held;
  integer target_bins[0:8];
  wire [63:0] fft_signed={{4{dut.fft_out_data[59]}},dut.fft_out_data[59:32],
                          {4{dut.fft_out_data[27]}},dut.fft_out_data[27:0]};
  always @(negedge clk) begin
    rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    m_ready<=reset_n && !hold_output && (rng[3:0]!=0);
    // Inject legal backpressure at the FFT output, before the bin capture logic.
    fft_allow<=reset_n && (dut.state==2 || dut.state==3 || dut.state==4) && rng[5:4]!=0;
  end
  always @(posedge clk) begin
    cycle=cycle+1;
    if(cycle>3000000) $fatal(1,"Global simulation timeout");
    if(!reset_n) begin stalled=0; fft_stalled=0; end
    else begin
      if(stalled && (!m_valid || {m_data,m_bin,m_slot,m_frame_id,m_start,m_calibration,m_last}!==held))
        $fatal(1,"Result changed under backpressure");
      held={m_data,m_bin,m_slot,m_frame_id,m_start,m_calibration,m_last};
      stalled=m_valid && !m_ready;
      if(fft_stalled && (!dut.fft_out_valid || {dut.fft_out_data,dut.fft_out_user,dut.fft_out_last}!==fft_held))
        $fatal(1,"FFT AXIS output changed under backpressure");
      fft_held={dut.fft_out_data,dut.fft_out_user,dut.fft_out_last};
      fft_stalled=dut.fft_out_valid && !dut.fft_out_ready;
      if(checking) begin
        if(fault!=0) $fatal(1,"Unexpected fault %h frame %0d",fault,reference_frame);
        if(dut.output_fire) begin
          if(fft_count>=4096 || fft_signed!==golden[reference_frame*4096+fft_count])
            $fatal(1,"Bit-accurate FFT mismatch frame=%0d count=%0d got=%h expected=%h",
              reference_frame,fft_count,fft_signed,golden[reference_frame*4096+fft_count]);
          if(dut.fft_out_user[10:0]!=(fft_count%2048)) $fatal(1,"FFT index mismatch");
          fft_count=fft_count+1; total_fft=total_fft+1;
        end
        if(m_valid && m_ready) begin
          if(result_count>=9 || m_slot!=result_count || m_bin!=target_bins[result_count] || m_last!=(result_count==8))
            $fatal(1,"Selected bin framing mismatch");
          if(m_frame_id!=100+reference_frame || m_start!=2048*(reference_frame+1) || m_calibration!=700+reference_frame)
            $fatal(1,"Descriptor mismatch");
          if(m_data!=={golden[reference_frame*4096+2048+target_bins[result_count]],
                        golden[reference_frame*4096+target_bins[result_count]]}) $fatal(1,"V/I bin data mismatch");
          $fdisplay(logfile,"%0d,%0d,%0d,%0d,%0d,%0d",m_frame_id,m_bin,
            $signed(m_data[31:0]),$signed(m_data[63:32]),$signed(m_data[95:64]),$signed(m_data[127:96]));
          result_count=result_count+1; total_bins=total_bins+1;
        end
      end else if(m_valid) $fatal(1,"Output from invalid or interrupted frame");
    end
  end
  task reset_all;
    begin
      @(negedge clk); reset_n=0; s_valid=0; checking=0; hold_output=0;
      repeat(20) @(negedge clk);
      reset_n=1;
      repeat(20) @(negedge clk);
    end
  endtask
  task send_samples(input integer f,input integer count,input integer bad);
    integer n;
    begin
      for(n=0;n<count;n=n+1) begin
        @(negedge clk); s_valid=0;
        if(rng[2:0]==0) repeat(3) @(negedge clk);
        s_data=inputs[f*2048+n]; s_index=n;
        s_frame_id=100+f; s_start=2048*(f+1); s_calibration=700+f;
        s_last=(n==2047);
        if(bad==1 && n==17) s_last=1;
        if(bad==2 && n==2047) s_last=0;
        if(bad==3 && n==17) s_index=18;
        if(bad==4 && n==17) s_calibration=9999;
        s_valid=1;
        @(posedge clk); while(!s_ready) @(posedge clk);
      end
      @(negedge clk); s_valid=0;
    end
  endtask
  task expect_fault(input [3:0] code);
    begin
      repeat(5) @(negedge clk);
      if(fault!==code || s_ready || m_valid) $fatal(1,"Fault handling mismatch got=%h expected=%h",fault,code);
      repeat(30) @(negedge clk);
      if(fault!==code) $fatal(1,"Fault was not sticky");
    end
  endtask
  integer f,k;
  initial begin
    target_bins[0]=2;target_bins[1]=3;target_bins[2]=7;target_bins[3]=11;target_bins[4]=19;
    target_bins[5]=37;target_bins[6]=61;target_bins[7]=113;target_bins[8]=199;
    $readmemh("input.hex",inputs); $readmemh("golden.hex",golden);
    logfile=$fopen("nine_bins.csv","w");
    $fdisplay(logfile,"frame_id,bin,v_real,v_imag,i_real,i_imag");
    force dut.fft_out_ready=fft_allow;
    reset_all;
    for(k=1;k<=4;k=k+1) begin
      send_samples(0,(k==2)?2048:18,k); expect_fault(1); reset_all;
    end
    send_samples(0,7,0); repeat(30010) @(negedge clk); expect_fault(8); reset_all;
    // Reset while loading and while the FFT is processing: neither may publish.
    send_samples(0,31,0); reset_all;
    send_samples(0,2048,0); repeat(200) @(negedge clk); reset_all;
    for(f=0;f<FRAMES;f=f+1) begin
      reference_frame=f; fft_count=0; result_count=0; checking=1; start_cycle=cycle;
      if(f==0) hold_output=1;
      send_samples(f,2048,0);
      if(f==0) begin
        wait(m_valid); repeat(100) @(negedge clk);
        if(s_ready) $fatal(1,"Accepted new frame before draining results");
        hold_output=0;
      end
      wait(result_count==9);
      @(negedge clk);
      if(fft_count!=4096 || completed_frames!=f+1) $fatal(1,"Frame completion counts mismatch");
      if(cycle-start_cycle>max_latency) max_latency=cycle-start_cycle;
      checking=0;
      $display("FRAME_PASS frame=%0d cycles=%0d",f,cycle-start_cycle);
    end
    release dut.fft_out_ready;
    $fclose(logfile);
    $display("PHASE3_FFT_PASS frames=%0d complex_outputs=%0d selected_pairs=%0d max_cycles=%0d",FRAMES,total_fft,total_bins,max_latency);
    $finish;
  end
endmodule
