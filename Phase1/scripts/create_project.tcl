# Recreates a Phase 1 project. No board PACKAGE_PIN assignments or bitstream.
set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7z020clg400-2
if {[llength $argv]>0} {set part [lindex $argv 0]}
set build [file join $root build vivado]
create_project phase1_dac $build -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
foreach d {clock dac top} {
  foreach f [glob [file join $root rtl $d *.sv]] {add_files $f}
}
set_property include_dirs [list [file join $root generated]] [get_filesets sources_1]
add_files [file join $root generated phase1_config.svh]
set_property file_type {Verilog Header} [get_files phase1_config.svh]
# .hex is read by $readmemh; the MEM type lets Vivado copy it into xsim's cwd.
add_files [file join $root generated waveform.hex]
set_property file_type {Memory Initialization Files} [get_files waveform.hex]
add_files -fileset sim_1 [glob [file join $root sim *.sv]]
add_files -fileset sim_1 [file join $root sim test_pattern17.hex]
set_property file_type {Memory Initialization Files} [get_files test_pattern17.hex]
set_property include_dirs [list [file join $root generated]] [get_filesets sim_1]
set_property top phase1_dac_top [get_filesets sources_1]
set_property top tb_phase1_dac [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
add_files -fileset constrs_1 [file join $root generated phase1_clock.xdc]
add_files -fileset constrs_1 [file join $root constraints phase1_ooc.xdc]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
