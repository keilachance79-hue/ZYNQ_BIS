set root [file normalize [file join [file dirname [info script]] ..]]
set build [file join $root build vivado]
create_project phase3_fft $build -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name fft2048
set_property -dict [list CONFIG.transform_length {2048} CONFIG.implementation_options {pipelined_streaming_io} \
 CONFIG.data_format {fixed_point} CONFIG.input_width {16} CONFIG.phase_factor_width {24} \
 CONFIG.scaling_options {unscaled} CONFIG.rounding_modes {convergent_rounding} \
 CONFIG.output_ordering {natural_order} CONFIG.xk_index {true} CONFIG.aresetn {true} \
 CONFIG.throttle_scheme {nonrealtime} CONFIG.target_clock_frequency {100} \
 CONFIG.run_time_configurable_transform_length {false}] [get_ips fft2048]
set_property generate_synth_checkpoint false [get_files fft2048.xci]
generate_target all [get_ips fft2048]
set reports [file join $root build reports]
file mkdir $reports
set f [open [file join $reports fft_config.txt] w]
foreach p [list_property [get_ips fft2048]] {
 if {[string match CONFIG.* $p]} {puts $f "$p = [get_property $p [get_ips fft2048]]"}
}
close $f
add_files [glob [file join $root rtl *.sv]]
set_property top phase3_fft_top [get_filesets sources_1]
add_files -fileset constrs_1 [file join $root constraints digital_ooc.xdc]
update_compile_order -fileset sources_1
puts PHASE3_IP_READY
