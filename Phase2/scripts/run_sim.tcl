source [file join [file dirname [info script]] create_project.tcl]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set simdir [file join $build phase2_capture.sim sim_1 behav xsim]
set f [open [file join $simdir simulate.log] r]; set result [read $f]; close $f
set reports [file join $root build reports]
file mkdir $reports
file copy -force [file join $simdir simulate.log] [file join $reports capture.log]
if {[string first PHASE2_CAPTURE_PASS $result]<0 || [regexp {Fatal:|Error:} $result]} {
  error "Phase2 capture regression failed"
}
file copy -force [file join $simdir raw_capture.csv] [file join $reports raw_capture.csv]
puts PHASE2_ALL_SIM_PASS
