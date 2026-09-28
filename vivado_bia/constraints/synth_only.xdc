# Timing context for standalone OOC RTL checking, NOT board-level signoff.
create_clock -name axi_clk -period 10.000 [get_ports axi_clk]
create_clock -name meas_clk -period 97.65625 [get_ports meas_clk]
# XPM FIFO instances supply their own gray-pointer CDC constraints.
# Do not mask all crossings with a broad false_path/clock_groups constraint.
