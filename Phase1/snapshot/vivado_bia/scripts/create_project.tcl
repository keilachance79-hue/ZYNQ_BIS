# vivado -mode batch -source scripts/create_project.tcl -tclargs xc7z020clg400-1
# The default part is for RTL/OOC checking only; verify your actual core-board part.
set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7z020clg400-1
if {[llength $argv] > 0} { set part [lindex $argv 0] }
set build [file join $root build vivado]
create_project bia $build -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property xpm_libraries {XPM_CDC XPM_MEMORY XPM_FIFO} [current_project]
add_files [file join $root rtl bia_pkg.sv]
foreach f [lsort [glob [file join $root rtl *.sv]]] {
  if {[file tail $f] ne "bia_pkg.sv"} { add_files $f }
}
add_files [file join $root mem sin1024.mem]
set_property file_type {Memory Initialization Files} [get_files sin1024.mem]
add_files -fileset sim_1 [file join $root sim tb_bia_core.sv]
set_property top bia_core [get_filesets sources_1]
set_property top tb_bia_core [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
add_files -fileset constrs_1 [file join $root constraints synth_only.xdc]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created RTL project at $build. No board pin assignments or bitstream are supplied."
