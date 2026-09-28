source [file join [file dirname [info script]] create_project.tcl]
set_param general.maxThreads 1
synth_design -top phase2_capture_top -part xc7z020clg400-2 -mode out_of_context
set reports [file join $root build reports]
file mkdir $reports
report_utilization -file [file join $reports utilization_synth.rpt]
report_timing_summary -file [file join $reports timing_synth.rpt]
report_cdc -details -file [file join $reports cdc_synth.rpt]
report_bus_skew -file [file join $reports bus_skew_synth.rpt]
report_drc -file [file join $reports drc_synth.rpt]
if {[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]<4} {error "Expected block RAM for frame banks"}
write_checkpoint -force [file join $reports capture_synth.dcp]
puts "PHASE2_SYNTH_PASS: digital OOC only; board and CDC signoff pending"
