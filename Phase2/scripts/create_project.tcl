set root [file normalize [file join [file dirname [info script]] ..]]
set build [file join $root build vivado]
create_project phase2_capture $build -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
add_files [glob [file join $root rtl *.sv]]
add_files -fileset sim_1 [glob [file join $root sim *.sv]]
foreach f [glob [file join $root generated *.hex]] {
  add_files -fileset sim_1 $f
  set_property file_type {Memory Initialization Files} [get_files $f]
}
set_property top phase2_capture_top [get_filesets sources_1]
set_property top tb_phase2_capture [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
add_files -fileset constrs_1 [file join $root constraints digital_ooc.xdc]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
