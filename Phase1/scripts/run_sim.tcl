source [file join [file dirname [info script]] create_project.tcl]
set report_dir [file join $root build reports]
file mkdir $report_dir
foreach {tb marker} {tb_dac_player PHASE1_PLAYER_PASS tb_phase1_dac PHASE1_TOP_PASS} {
  set_property top $tb [get_filesets sim_1]
  launch_simulation -simset sim_1 -mode behavioral
  close_sim
  set simdir [file join $build phase1_dac.sim sim_1 behav xsim]
  set log [file join $simdir simulate.log]
  set f [open $log r]; set text [read $f]; close $f
  file copy -force $log [file join $report_dir ${tb}.log]
  if {[string first $marker $text]<0 || [regexp {Fatal:|Error:} $text]} {
    error "Simulation failed: $tb; see $log"
  }
  if {$tb eq "tb_phase1_dac"} {
    file copy -force [file join $simdir dac_capture.csv] [file join $report_dir dac_capture.csv]
  }
}
puts "PHASE1_ALL_SIM_PASS"
