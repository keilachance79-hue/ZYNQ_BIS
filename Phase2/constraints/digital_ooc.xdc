# Test contract ONLY; these are not board clocks or signoff I/O delays.
create_clock -name conversion -period 97.656 [get_ports conversion_clk]
create_clock -name dsp -period 10.000 [get_ports dsp_clk]
create_clock -name dco_a -period 97.656 -waveform {20.000 60.000} [get_ports dco_a]
create_clock -name dco_b -period 97.656 -waveform {51.000 86.000} [get_ports dco_b]
# ADC output ports update at model +4/+11 ns, captured at model +20/+51 ns.
# Real board setup/hold, DCO routing and clock relationship must replace these.
set_input_delay -clock conversion -max 4.000 [get_ports {adc_a[*]}]
set_input_delay -clock conversion -min 4.000 [get_ports {adc_a[*]}]
set_input_delay -clock conversion -max 11.000 [get_ports {adc_b[*]}]
set_input_delay -clock conversion -min 11.000 [get_ports {adc_b[*]}]
# Gray bus first-stage synchronizers: bound routing to less than one source
# period; do not use a whole-domain false path to hide other crossings.
set_max_delay -datapath_only 90.000 -from [get_cells -hier -filter {NAME =~ *conversion_gray_reg* && IS_SEQUENTIAL}] -to [get_cells -hier -filter {NAME =~ *gray_meta_reg* && IS_SEQUENTIAL}]
set_bus_skew 90.000 -from [get_cells -hier -filter {NAME =~ *conversion_gray_reg* && IS_SEQUENTIAL}] -to [get_cells -hier -filter {NAME =~ *gray_meta_reg* && IS_SEQUENTIAL}]
set_false_path -to [get_pins -hier -filter {NAME =~ *overflow_meta_reg*/D}]
