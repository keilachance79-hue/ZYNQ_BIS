# Reference period is generated from config.json in generated/phase1_clock.xdc.
# User confirmed 50 MHz; board pin and jitter/skew remain NEED_CONFIRMATION.
# MMCM clocks are automatically derived. ODDR produces a forwarded sample clock.
create_generated_clock -name dac_forward -source [get_pins dac_i/forward_clock_i/C] -divide_by 1 [get_ports dac_clk]
# Datasheet limits only. PCB relative skew, jitter and I/O delay remain unknown.
set_output_delay -clock dac_forward -max 8.000 [get_ports {dac_data[*]}]
set_output_delay -clock dac_forward -min -4.000 [get_ports {dac_data[*]}]
# No fabricated PACKAGE_PIN, IOSTANDARD, or global false paths.
