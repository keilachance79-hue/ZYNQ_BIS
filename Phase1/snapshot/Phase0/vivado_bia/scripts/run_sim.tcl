set argv_saved $argv
source [file join [file dirname [info script]] create_project.tcl]
launch_simulation -simset sim_1 -mode behavioral
close_sim
set simlog [file join $build bia.sim sim_1 behav xsim simulate.log]
set fp [open $simlog r]
set contents [read $fp]
close $fp
if {[string first "ALL TESTS PASSED" $contents] < 0 || [regexp {Fatal:|Error:} $contents]} {
  error "Simulation did not pass; inspect $simlog"
}
puts "VERIFIED: all behavioral self-checks passed."
