# Internal digital subsystem target; no board-level I/O timing assumptions.
create_clock -name dsp_clk -period 10.000 [get_ports clk]
