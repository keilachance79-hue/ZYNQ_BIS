source [file join [file dirname [info script]] create_project.tcl]
set_param general.maxThreads 1
set report_dir [file join $root build reports]
file mkdir $report_dir
synth_design -top phase1_dac_top -part $part -mode out_of_context
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_clocks -file [file join $report_dir clocks_synth.rpt]
report_timing_summary -file [file join $report_dir timing_synth.rpt]
report_cdc -file [file join $report_dir cdc_synth.rpt]
report_drc -file [file join $report_dir drc_synth.rpt]
if {[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]==0} {error "ROM did not infer block RAM"}
if {[llength [get_cells -hier -filter {REF_NAME =~ MMCME2*}]]!=1} {error "Expected one MMCM"}
if {[llength [get_cells -hier -filter {REF_NAME == ODDR}]]!=1} {error "Expected forwarded-clock ODDR"}
write_checkpoint -force [file join $report_dir phase1_dac_synth.dcp]
puts "PHASE1_SYNTH_PASS: OOC only, not board timing signoff"
