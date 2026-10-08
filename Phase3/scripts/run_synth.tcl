source [file join [file dirname [info script]] create_project.tcl]
set_param general.maxThreads 2
# Synthesize the real FFT sources together with the wrapper, not a black box.
synth_design -top phase3_fft_top -part xc7z020clg400-2 -mode out_of_context
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]]} {error "Unexpected black boxes"}
report_utilization -file [file join $reports utilization_synth.rpt]
report_timing_summary -file [file join $reports timing_synth.rpt]
report_drc -file [file join $reports drc_synth.rpt]
write_checkpoint -force [file join $reports fft_synth.dcp]
puts PHASE3_SYNTH_PASS
