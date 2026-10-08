set root [file normalize [file join [file dirname [info script]] ..]]
set build [file join $root build vivado]
set reports [file join $root build reports]
file mkdir $reports
create_project phase4_polar $build -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
create_ip -name cordic -vendor xilinx.com -library ip -version 6.0 -module_name polar32
set_property -dict [list CONFIG.Functional_Selection {Translate} CONFIG.Architectural_Configuration {Word_Serial} \
 CONFIG.Data_Format {SignedFraction} CONFIG.Phase_Format {Radians} CONFIG.Input_Width {32} CONFIG.Output_Width {32} \
 CONFIG.Coarse_Rotation {true} CONFIG.Compensation_Scaling {LUT_based} CONFIG.Round_Mode {Nearest_Even} \
 CONFIG.Iterations {0} CONFIG.Precision {0} CONFIG.ARESETN {true} \
 CONFIG.flow_control {Blocking} CONFIG.out_tready {true}] [get_ips polar32]
set_property generate_synth_checkpoint false [get_files polar32.xci]
generate_target all [get_ips polar32]
set f [open [file join $reports cordic_config.txt] w]
foreach p [list_property [get_ips polar32]] {
 if {[string match CONFIG.* $p]} {puts $f "$p = [get_property $p [get_ips polar32]]"}
}
close $f
if {[llength [glob -nocomplain [file join $root rtl *.sv]]]} {
 add_files [glob [file join $root rtl *.sv]]
 set_property top phase4_polar_top [get_filesets sources_1]
 add_files -fileset constrs_1 [file join $root constraints digital_ooc.xdc]
 update_compile_order -fileset sources_1
}
puts PHASE4_IP_READY
