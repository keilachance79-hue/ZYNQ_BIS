# Internal digital timing target only; no physical board I/O or pin signoff.
create_clock -name dsp_clk -period 10.000 [get_ports clk]
