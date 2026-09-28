`timescale 1ns/1ps
module tb_bia_core #(parameter integer L=8);
  localparam integer N=1<<L;
  reg clk=0, meas_clk=0, resetn=0;
  always #5 clk=~clk;
  always #48.828125 meas_clk=~meas_clk;
  reg fault=0, adc_valid=1, adc_or_v=0, adc_or_i=0;
  reg [15:0] adc_v=16'h8000,adc_i=16'h8000;
  wire [15:0] dac_data;
  wire exc,mux_en;
  wire [19:0] electrodes;
  reg [17:0] awaddr=0,araddr=0;
  reg awvalid=0,wvalid=0,bready=1,arvalid=0,rready=1;
  reg [31:0] wdata=0;
  reg [3:0] wstrb=15;
  wire awready,wready,bvalid,arready,rvalid;
  wire [1:0] bresp,rresp;
  wire [31:0] rdata,td;
  wire [3:0] tk;
  wire tv,tl,irq;
  reg [1:0] ready_mode=1;
  reg [31:0] lfsr=32'hd00df00d;
  wire tr=(ready_mode==0) ? 1'b1 : ((ready_mode==2) ? 1'b0:lfsr[0]);
  bia_core #(.FRAME_LOG2(L),.SAMPLE_FIFO_DEPTH(32),.OUTPUT_FIFO_DEPTH(16),
    .ADC_CAPTURE_DELAY(9),.TIMESTAMP_CALIBRATED(0)) dut(
    .axi_clk(clk),.axi_resetn(resetn),.meas_clk(meas_clk),.fault_in(fault),
    .adc_v(adc_v),.adc_i(adc_i),.adc_valid(adc_valid),.adc_or_v(adc_or_v),.adc_or_i(adc_or_i),
    .dac_data(dac_data),.excitation_en(exc),.mux_en(mux_en),.electrodes(electrodes),
    .s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
    .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
    .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
    .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
    .m_axis_tdata(td),.m_axis_tkeep(tk),.m_axis_tlast(tl),.m_axis_tvalid(tv),.m_axis_tready(tr),.irq(irq));

  task automatic write_reg(input [17:0] addr,input [31:0] value,input [3:0] strobe,input integer order,input [1:0] expected_resp);
    begin
      fork
        begin
          if(order==1) repeat(4) @(negedge clk);
          @(negedge clk); awaddr=addr; awvalid=1;
          @(posedge clk); while(!awready) @(posedge clk);
          @(negedge clk); awvalid=0;
        end
        begin
          if(order==2) repeat(4) @(negedge clk);
          @(negedge clk); wdata=value; wstrb=strobe; wvalid=1;
          @(posedge clk); while(!wready) @(posedge clk);
          @(negedge clk); wvalid=0;
        end
      join
      @(posedge clk); while(!bvalid) @(posedge clk);
      if(bresp!==expected_resp) $fatal(1,"AXIL write %h response %h != %h",addr,bresp,expected_resp);
      @(negedge clk);
    end
  endtask
  task automatic read_reg(input [17:0] addr, output [31:0] value);
    begin
      @(negedge clk); araddr=addr; arvalid=1;
      @(posedge clk); while(!arready) @(posedge clk);
      @(negedge clk); arvalid=0;
      @(posedge clk); while(!rvalid) @(posedge clk);
      if(rresp!==0) $fatal(1,"AXIL read response error");
      value=rdata;
      @(negedge clk);
    end
  endtask

  integer adc_phase=0,base;
  real angle;
  always @(negedge meas_clk) begin
    angle=6.283185307179586*adc_phase/N;
    base=$rtoi(900.0*$cos(angle)+500.0*$sin(3.0*angle)+200.0*$cos(7.0*angle));
    adc_i=base+32768; adc_v=2*base+32768;
    adc_phase=(adc_phase+1)%N;
  end
  integer packet_count=0,word_count=0;
  reg [31:0] packets[0:7][0:N+31];
  integer lengths[0:7];
  reg stalled=0;
  reg [32:0] held;
  always @(posedge clk) begin
    if(!resetn) begin stalled<=0; packet_count<=0; word_count<=0; end
    else begin
      lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
      if(stalled && (!tv || {tl,td}!==held)) $fatal(1,"AXIS changed under backpressure");
      stalled<=tv && !tr; held<={tl,td};
      if(tv && tr) begin
        if(tk!==15) $fatal(1,"TKEEP incorrect");
        packets[packet_count][word_count]<=td;
        if(tl) begin
          lengths[packet_count]<=word_count+1;
          packet_count<=packet_count+1; word_count<=0;
        end else word_count<=word_count+1;
      end
    end
  end
  reg signed [15:0] sinrom[0:1023];
  reg [31:0] expected_raw[0:7][0:N-1];
  longint signed expected_dft[0:7][0:31];
  integer expected_count[0:7];
  integer active_test=0;
  integer si,ci,a,k;
  longint signed vv,ii,sn,cs;
  reg [63:0] expected_start[0:7];
  always @(posedge meas_clk) begin
    if(resetn) begin
      if(dut.meta_push && !dut.meta_tx.is_end) expected_start[active_test]=dut.meta_tx.tick;
      if(dut.sample_push) begin
        a=expected_count[active_test];
        if(a==0 && dut.acq_i.tick-9!==expected_start[active_test]) $fatal(1,"Timestamp not aligned to first sample");
        expected_raw[active_test][a]=dut.sample_tx[31:0];
        vv=$signed(dut.sample_tx[15:0]); ii=$signed(dut.sample_tx[31:16]);
        for(k=0;k<8;k=k+1) begin
          si=((a*(k+1))%N)*1024/N; ci=(si+256)%1024;
          sn=$signed(sinrom[si]); cs=$signed(sinrom[ci]);
          expected_dft[active_test][4*k+0]+=vv*cs;
          expected_dft[active_test][4*k+1]-=vv*sn;
          expected_dft[active_test][4*k+2]+=ii*cs;
          expected_dft[active_test][4*k+3]-=ii*sn;
        end
        expected_count[active_test]=a+1;
      end
    end
  end
  // Check waveform BRAM bank choice and synchronous-read/negative-edge launch.
  always @(negedge meas_clk) if(resetn && exc) begin
    #1;
    if(dac_data !== (dut.rd_bank ? (16'h9000+dut.acq_i.dac_index) : (16'h8000+dut.acq_i.dac_index)))
      $fatal(1,"DAC bank/address mismatch");
  end
  task automatic check_packet(input integer p,input bit raw,input [31:0] status,input [31:0] frame);
    integer w,tail,fd;
    longint signed got;
    reg [63:0] ts,te;
    begin
      wait(packet_count>p); @(negedge clk);
      tail=raw ? 16+N:16+64;
      if(lengths[p]!==tail+4) $fatal(1,"Packet length %0d",lengths[p]);
      if(packets[p][0]!==32'h31414942 || packets[p][3]!==frame) $fatal(1,"Frame header/id corrupted");
      if(packets[p][10]!==N || packets[p][13]!== (raw ? N*4:256)) $fatal(1,"Header size incorrect");
      ts={packets[p][7],packets[p][6]}; te={packets[p][tail+3],packets[p][tail+2]};
      if(ts!==expected_start[p] || te-ts!==N-1) $fatal(1,"Frame timestamp mismatch");
      if(p>0 && ts<=expected_start[p-1]) $fatal(1,"Non-monotonic timestamp");
      if(packets[p][tail]!==status || packets[p][tail+1]!==expected_count[p])
        $fatal(1,"Frame status/count mismatch p=%0d status=%h count=%0d expected=%0d",p,packets[p][tail],packets[p][tail+1],expected_count[p]);
      if(raw) begin
        for(w=0;w<N;w=w+1) begin
          if(w<expected_count[p]) begin
            if(packets[p][16+w]!==expected_raw[p][w]) $fatal(1,"Raw mismatch %0d",w);
          end else if(packets[p][16+w]!==0) $fatal(1,"Lost samples not zero-padded");
        end
      end else begin
        for(w=0;w<32;w=w+1) begin
          got={packets[p][17+2*w],packets[p][16+2*w]};
          if(got!==expected_dft[p][w]) $fatal(1,"DFT mismatch component %0d got=%0d expected=%0d",w,got,expected_dft[p][w]);
        end
      end
      $display("PASS packet %0d: mode=%s status=%h accepted=%0d timestamp=%0d",p,raw?"raw":"DFT",status,expected_count[p],ts);
      fd=$fopen($sformatf("packet_%0d.hex",p),"w");
      for(w=0;w<lengths[p];w=w+1) $fdisplay(fd,"%08x",packets[p][w]);
      $fclose(fd);
    end
  endtask
  integer n,t;
  reg [31:0] rd;
  initial begin
    $readmemh("sin1024.mem",sinrom);
    for(n=0;n<8;n=n+1) begin
      expected_count[n]=0; expected_start[n]=0;
      for(t=0;t<32;t=t+1) expected_dft[n][t]=0;
    end
    repeat(40) @(posedge meas_clk);
    @(negedge clk); resetn=1;
    repeat(40) @(posedge meas_clk);
    read_reg(0,rd); if(rd!==32'h31414942) $fatal(1,"ID mismatch");
    write_reg('h10,32'h12345678,15,1,0);
    write_reg('h10,32'h0000ab00,2,2,0);
    read_reg('h10,rd); if(rd!==32'h1234ab78) $fatal(1,"WSTRB merge failed");
    write_reg('h11,0,15,0,2);
    for(n=0;n<N;n=n+1) begin
      write_reg('h10000+4*n,'h8000+n,15,n%3,0);
      write_reg('h20000+4*n,'h9000+n,15,n%3,0);
    end
    write_reg('h0c,42,15,0,0);
    write_reg('h14,123,15,0,0);
    write_reg('h1c,10,15,0,0);
    write_reg('h20,3,15,0,0);
    write_reg('h24,20'h18820,15,0,0);
    // Raw, bank A, random backpressure. Change shadow during frame.
    write_reg('h10,100,15,0,0);
    write_reg('h28,6,15,0,0);
    write_reg(4,1,15,0,0);
    write_reg(4,1,15,1,2); // a second START must not corrupt the in-flight job
    write_reg('h10000,'h1234,15,0,2); // active bank protected
    write_reg('h10,999,15,2,0);
    check_packet(0,1,32'h10,100);
    // Eight-frequency DFT, bank B, exact integer reference comparison.
    active_test=1;
    write_reg('h10,101,15,0,0);
    write_reg('h28,5,15,0,0);
    write_reg(4,1,15,2,0);
    check_packet(1,0,32'h10,101);
    // Hold downstream until input FIFO overflows. Packet must still terminate.
    active_test=2; ready_mode=2;
    write_reg('h10,102,15,0,0);
    write_reg('h28,6,15,0,0);
    write_reg(4,1,15,1,0);
    wait(dut.acq_i.state==5); // ensure this job has entered CAPTURE
    wait(dut.acq_i.state==7); repeat(20) @(posedge clk);
    ready_mode=1;
    check_packet(2,1,32'h11,102);
    if(expected_count[2]>=N) $fatal(1,"Overflow was not exercised");
    // Recovery must contain no leftover samples/metadata from the failed frame.
    active_test=3;
    write_reg('h10,103,15,0,0);
    write_reg(4,1,15,0,0);
    check_packet(3,1,32'h10,103);
    // External fault disables excitation and produces an explicitly invalid frame.
    active_test=4;
    write_reg('h10,104,15,0,0);
    write_reg(4,1,15,0,0);
    wait(expected_count[4]>=20); @(negedge meas_clk); fault=1;
    #1; if(exc!==0) $fatal(1,"Fault did not disable excitation");
    check_packet(4,1,32'h18,104);
    fault=0;
    // Reject incoherent/invalid DFT bin settings.
    write_reg('h28,4,15,0,0);
    write_reg('h40,0,15,0,0);
    write_reg(4,1,15,0,2);
    $display("ALL TESTS PASSED: AXI ordering/WSTRB, bank protection, raw, DFT, backpressure, timestamps, overflow recovery, fault, bin validation");
    $finish;
  end
  initial begin #100000000; $fatal(1,"Simulation watchdog timeout"); end
endmodule
