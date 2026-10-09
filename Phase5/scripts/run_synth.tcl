set root [file normalize [file join [file dirname [info script]] ..]]
set reports [file join $root build reports]
file mkdir $reports
create_project phase5_scan [file join $root build vivado] -part xc7z020clg400-2 -force
add_files [file join $root generated electrode_map.sv]
add_files [file join $root rtl phase5_scan_top.sv]
add_files -fileset constrs_1 [file join $root constraints digital_ooc.xdc]
set_property top phase5_scan_top [get_filesets sources_1]
set_param general.maxThreads 2
synth_design -top phase5_scan_top -part xc7z020clg400-2 -mode out_of_context
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "Unexpected black boxes"}
report_utilization -file [file join $reports utilization_synth.rpt]
report_timing_summary -file [file join $reports timing_synth.rpt]
report_drc -file [file join $reports drc_synth.rpt]
puts PHASE5_SYNTH_PASS
