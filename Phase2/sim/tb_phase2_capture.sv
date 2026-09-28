`timescale 1ns/1ps
module tb_phase2_capture;
  localparam N=2048;
  reg conversion_clk=0,dsp_clk=0,dsp_run=1,reset_n=0;
  always #48.828125 conversion_clk=~conversion_clk;
  always begin #5; if(dsp_run) dsp_clk=~dsp_clk; end
  reg dco_a=0,dco_b=0,run_b=1,skip_b=0;
  reg [15:0] adc_a=16'h8000,adc_b=16'h8000;
  reg clock_ok=1,qualified=0,request_valid=0,m_ready=0;
  reg [31:0] req_start=0,req_id=0,req_cal=0;
  wire request_ready,active,m_valid,m_last;
  wire [31:0] m_data,m_id,m_start,m_cal,completed,aborted;
  wire [10:0] m_index;
  wire [7:0] fault;
  wire [1:0] banks;
  integer model_tick=0,mode=0,phase_variant=0,session=0,fd;
  reg [15:0] fixture_a[0:N-1],fixture_b[0:N-1];
  function automatic [15:0] code_a(input integer t);
    begin
      if(t<0) code_a=16'h8000;
      else if(mode==1) code_a=fixture_a[t%N];
      else case(t%N)
        0:code_a=0; 1:code_a=16'h8000; 2:code_a=16'hffff;
        default:code_a=(t*17+123)&16'hffff;
      endcase
    end
  endfunction
  function automatic [15:0] code_b(input integer t);
    begin
      if(t<0) code_b=16'h8000;
      else if(mode==1) code_b=fixture_b[t%N];
      else case(t%N)
        0:code_b=16'hffff; 1:code_b=0; 2:code_b=16'h8000;
        default:code_b=(t*29+4567)&16'hffff;
      endcase
    end
  endfunction
  // Conversion N emerges after nine complete conversion cycles. Data and DCO
  // arrivals differ by channel, and DCO phase is swept within a qualified window.
  always @(posedge conversion_clk) begin
    if(!reset_n) model_tick=0;
    adc_a<=#4 code_a(model_tick-9);
    adc_b<=#11 code_b(model_tick-9);
    if(reset_n) model_tick=model_tick+1;
  end
  always @(posedge conversion_clk) begin
    #(20+phase_variant*7); dco_a=1; #40; dco_a=0;
  end
  always @(posedge conversion_clk) begin
    #(51+phase_variant*5);
    if(run_b && !skip_b) dco_b=1;
    #35; dco_b=0; skip_b=0;
  end
  phase2_capture_top dut(
    .conversion_clk(conversion_clk),.dsp_clk(dsp_clk),.dco_a(dco_a),.dco_b(dco_b),
    .reset_n(reset_n),.adc_a(adc_a),.adc_b(adc_b),.clock_ok(clock_ok),
    .alignment_verified(qualified),.request_valid(request_valid),.request_ready(request_ready),
    .request_start(req_start),.request_id(req_id),.request_calibration(req_cal),
    .fault(fault),.active(active),.banks_ready(banks),.m_data(m_data),.m_valid(m_valid),
    .m_ready(m_ready),.m_last(m_last),.m_index(m_index),.m_frame_id(m_id),
    .m_start(m_start),.m_calibration(m_cal),.completed_frames(completed),.aborted_frames(aborted));
  integer words=0,frames=0,index_expected=0,scenario_passes=0;
  reg stalled=0;
  reg [139:0] held;
  wire [139:0] payload={m_data,m_last,m_index,m_id,m_start,m_cal};
  reg random_ready=0;
  reg [31:0] rng=32'h92ace712;
  always @(negedge dsp_clk) begin
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    if(random_ready) m_ready=rng[0] | rng[3];
  end
  always @(posedge dsp_clk) begin
    if(!reset_n) begin stalled<=0; index_expected=0; end
    else begin
      if(stalled && (!m_valid || payload!==held)) $fatal(1,"AXIS data/descriptor changed under backpressure");
      stalled<=m_valid && !m_ready; held<=payload;
      if(m_valid && m_ready) begin
        if(m_index!==index_expected || m_last!==(index_expected==N-1)) $fatal(1,"Frame boundary/index failure");
        if(m_data!=={(code_b(m_start+m_index)^16'h8000),(code_a(m_start+m_index)^16'h8000)})
          $fatal(1,"V/I code or epoch mismatch start=%0d index=%0d got=%h",m_start,m_index,m_data);
        if(m_cal!==32'hcafe0001) $fatal(1,"Descriptor overwritten by next request");
        $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",session,mode,m_id,m_start,m_index,$signed(m_data[15:0]),$signed(m_data[31:16]));
        words=words+1;
        if(m_last) begin index_expected=0; frames=frames+1; end
        else index_expected=index_expected+1;
      end
    end
  end
  task automatic restart(input integer variant);
    begin
      @(negedge dsp_clk); reset_n=0; qualified=0; clock_ok=1;
      run_b=1; skip_b=0; request_valid=0; random_ready=0; m_ready=0;
      phase_variant=variant; session=session+1;
      repeat(80) @(negedge conversion_clk);
      #(13+variant*19); reset_n=1;
      repeat(100) @(negedge conversion_clk);
      if(fault) $fatal(1,"Startup fault %h",fault);
    end
  endtask
  task automatic request_frame(input integer id);
    begin
      qualified=1;
      wait(request_ready);
      @(negedge dsp_clk);
      req_start=((model_tick/N)+1)*N;
      req_id=id; req_cal=32'hcafe0001; request_valid=1;
      @(negedge dsp_clk); request_valid=0;
      req_id=32'hbad; req_cal=32'hbad;
      wait(active);
    end
  endtask
  task automatic require_fault(input [7:0] mask);
    begin
      wait(fault!=0);
      repeat(10) @(negedge dsp_clk);
      if((fault & mask)==0 || active || completed!=0 || aborted!=1 || m_valid)
        $fatal(1,"Fault did not discard whole frame: fault=%h completed=%0d aborted=%0d",fault,completed,aborted);
      scenario_passes=scenario_passes+1;
    end
  endtask
  integer base_frames;
  initial begin
    $readmemh("input_a.hex",fixture_a); $readmemh("input_b.hex",fixture_b);
    fd=$fopen("raw_capture.csv","w");
    $fwrite(fd,"session,mode,frame_id,start_tick,index,v_signed,i_signed\n");
    restart(0);
    // Calibration gate blocks requests; this is not automatic hardware alignment.
    request_valid=1; repeat(20) @(negedge dsp_clk);
    if(request_ready || active) $fatal(1,"Unqualified alignment accepted");
    request_valid=0; scenario_passes=scenario_passes+1;
    base_frames=frames;
    request_frame(10); wait(completed==1);
    request_frame(11); wait(completed==2);
    repeat(50) @(negedge conversion_clk);
    if(request_ready || banks!=2'b11 || fault) $fatal(1,"Full banks were overwritten or sampling stalled");
    random_ready=1; wait(frames==base_frames+2);
    scenario_passes=scenario_passes+1;
    mode=1; restart(1); base_frames=frames;
    request_frame(20); random_ready=1; wait(frames==base_frames+1);
    scenario_passes=scenario_passes+1;
    mode=0; restart(2); request_frame(30);
    wait(dut.buffer_i.wr_index==40); run_b=0; require_fault(8'h10);
    restart(0); request_frame(40); wait(dut.buffer_i.wr_index==60);
    skip_b=1; require_fault(8'h0c);
    restart(1); request_frame(50); wait(dut.buffer_i.wr_index==40);
    clock_ok=0; require_fault(8'h20);
    restart(2); request_frame(60); wait(dut.buffer_i.wr_index==40);
    qualified=0; require_fault(8'h40);
    restart(0); request_frame(70); wait(dut.buffer_i.wr_index==40);
    @(negedge dsp_clk); dsp_run=0;
    repeat(300) @(negedge conversion_clk); dsp_run=1;
    require_fault(8'h03);
    restart(1); qualified=1; wait(request_ready);
    @(negedge dsp_clk); req_start=0; request_valid=1;
    @(negedge dsp_clk); request_valid=0;
    require_fault(8'h80);
    // Mid-frame reset discards partial data and rebuilds timestamp state.
    restart(2); request_frame(80); wait(dut.buffer_i.wr_index==40);
    restart(1); base_frames=frames;
    request_frame(81); random_ready=1; wait(frames==base_frames+1);
    scenario_passes=scenario_passes+1;
    #100; $fclose(fd);
    $display("PHASE2_CAPTURE_PASS: scenarios=%0d frames=%0d paired_words=%0d",scenario_passes,frames,words);
    $finish;
  end
  initial begin #10000000; $fatal(1,"Phase2 watchdog timeout fault=%h",fault); end
endmodule
