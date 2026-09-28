`timescale 1ns/1ps
module tb_dac_player;
  reg clk=0, reset_n=0;
  always #50 clk=~clk;
  wire [15:0] data, pins;
  wire [4:0] index, pin_index;
  wire valid, pin_valid, boundary, dac_clk;
  reg [15:0] expected[0:16];
  integer count=0, epoch=0;
  dac_player #(.ROM_LENGTH(17),.FS_HZ(10000000),.ROM_FILE("test_pattern17.hex")) player(
    .sample_clk(clk),.reset_n(reset_n),.rom_data(data),.rom_index(index),.rom_valid(valid));
  ltc1668_if #(.ADDR_WIDTH(5)) pins_i(.sample_clk(clk),.reset_n(reset_n),
    .rom_data(data),.rom_index(index),.rom_valid(valid),.dac_data(pins),.dac_clk(dac_clk),
    .sample_valid(pin_valid),.period_start(boundary),.sample_index(pin_index));
  always @(posedge dac_clk) begin
    #0.2;
    if(reset_n && pin_valid) begin
      if(pins!==expected[count%17] || pin_index!==count%17 || boundary!==(count%17==0))
        $fatal(1,"Parameterized 17-word ROM mismatch epoch=%0d count=%0d",epoch,count);
      count=count+1;
    end
  end
  initial begin
    $readmemh("test_pattern17.hex",expected);
    #137 reset_n=1;
    wait(count==73);
    #13 reset_n=0;
    #1 if(pins!==16'h8000 || pin_valid!==0) $fatal(1,"Idle/reset mismatch");
    #133 count=0; epoch=1; reset_n=1;
    wait(count==68);
    $display("PHASE1_PLAYER_PASS: non-power-of-two ROM, wrap, startup and midstream reset");
    $finish;
  end
  initial begin #100000; $fatal(1,"Player watchdog"); end
endmodule
