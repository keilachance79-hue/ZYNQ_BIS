# Source after opening the RTL project. Imports RTL/memory into build/ip_repo.
if {![info exists root]} { set root [file normalize [file join [file dirname [info script]] ..]] }
set ipdir [file join $root build ip_repo bia_core]
ipx::package_project -root_dir $ipdir -vendor local -library user -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property name bia_core $core
set_property display_name {Bioimpedance acquisition and multitone demodulator} $core
set_property version 1.0 $core
foreach b [ipx::get_bus_interfaces -of_objects $core] { ipx::remove_bus_interface [get_property NAME $b] $core }
foreach m [ipx::get_memory_maps -of_objects $core] { ipx::remove_memory_map [get_property NAME $m] $core }
set ax [ipx::add_bus_interface S_AXI $core]
set_property bus_type_vlnv xilinx.com:interface:aximm:1.0 $ax
set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 $ax
set_property interface_mode slave $ax
foreach name {AWADDR AWPROT AWVALID AWREADY WDATA WSTRB WVALID WREADY BRESP BVALID BREADY ARADDR ARPROT ARVALID ARREADY RDATA RRESP RVALID RREADY} {
  set pm [ipx::add_port_map $name $ax]
  set_property physical_name s_axi_[string tolower $name] $pm
}
foreach {p v} {PROTOCOL AXI4LITE DATA_WIDTH 32 ADDR_WIDTH 18} {
  set_property value $v [ipx::add_bus_parameter $p $ax]
}
set mm [ipx::add_memory_map S_AXI $core]
set ab [ipx::add_address_block registers $mm]
set_property range 262144 $ab
set_property width 32 $ab
set_property usage register $ab
set_property slave_memory_map_ref S_AXI $ax
set st [ipx::add_bus_interface M_AXIS $core]
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 $st
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 $st
set_property interface_mode master $st
foreach name {TDATA TKEEP TLAST TVALID TREADY} {
  set pm [ipx::add_port_map $name $st]
  set_property physical_name m_axis_[string tolower $name] $pm
}
foreach {p v} {TDATA_NUM_BYTES 4 HAS_TKEEP 1 HAS_TLAST 1} {
  set_property value $v [ipx::add_bus_parameter $p $st]
}
foreach {bus port} {axi_clk axi_clk meas_clk meas_clk} {
  set b [ipx::add_bus_interface $bus $core]
  set_property bus_type_vlnv xilinx.com:signal:clock:1.0 $b
  set_property abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0 $b
  set_property interface_mode slave $b
  set_property physical_name $port [ipx::add_port_map CLK $b]
  if {$port eq "axi_clk"} {
    set_property value S_AXI:M_AXIS [ipx::add_bus_parameter ASSOCIATED_BUSIF $b]
    set_property value axi_resetn [ipx::add_bus_parameter ASSOCIATED_RESET $b]
  }
}
set b [ipx::add_bus_interface axi_resetn $core]
set_property bus_type_vlnv xilinx.com:signal:reset:1.0 $b
set_property abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0 $b
set_property interface_mode slave $b
set_property physical_name axi_resetn [ipx::add_port_map RST $b]
set_property value ACTIVE_LOW [ipx::add_bus_parameter POLARITY $b]
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
puts "Packaged custom IP: $ipdir"
