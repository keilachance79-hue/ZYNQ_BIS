source [file join [file dirname [info script]] create_project.tcl]
set_param general.maxThreads 1
set report_dir [file join $root build reports]
file mkdir $report_dir
synth_design -top bia_core -part $part -mode out_of_context
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing_synth.rpt]
report_cdc -file [file join $report_dir cdc_synth.rpt]
write_checkpoint -force [file join $report_dir bia_core_synth.dcp]
puts "OOC synthesis completed. This is not board implementation/timing signoff."
