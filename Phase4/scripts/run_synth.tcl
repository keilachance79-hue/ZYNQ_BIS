source [file join [file dirname [info script]] create_project.tcl]
set_param general.maxThreads 2
synth_design -top phase4_polar_top -part xc7z020clg400-2 -mode out_of_context
if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "Unexpected black boxes"}
report_utilization -file [file join $reports utilization_synth.rpt]
report_timing_summary -file [file join $reports timing_synth.rpt]
report_drc -file [file join $reports drc_synth.rpt]
write_checkpoint -force [file join $reports polar_synth.dcp]
puts PHASE4_SYNTH_PASS
