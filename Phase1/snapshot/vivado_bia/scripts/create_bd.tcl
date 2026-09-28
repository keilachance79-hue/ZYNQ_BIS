# Run in an open RTL project after create_project.tcl.
# Optional: set BIA_PS_CONFIG to a board-specific Tcl file before sourcing.
# That file receives variable 'ps' and must configure DDR/MIO for YOUR core board.
# Without it, this creates a wiring template only, NOT a board-ready design.
if {![info exists root]} { set root [file normalize [file join [file dirname [info script]] ..]] }
source [file join $root scripts package_ip.tcl]
set_property ip_repo_paths [file join $root build ip_repo] [current_project]
update_ip_catalog
create_bd_design bia_system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
if {[info exists BIA_PS_CONFIG]} {
  source $BIA_PS_CONFIG
} else {
  puts "WARNING: No core-board PS configuration: DDR/MIO remain unverified defaults. Do not generate a bitstream."
}
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
  CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1}] $ps
set acq [create_bd_cell -type ip -vlnv local:user:bia_core:1.0 acquisition]
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma]
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_mm2s {0} CONFIG.c_include_s2mm {1} \
  CONFIG.c_s_axis_s2mm_tdata_width {32} CONFIG.c_m_axi_s2mm_data_width {64} \
  CONFIG.c_sg_length_width {23}] $dma
set ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 control_bus]
set_property CONFIG.NUM_MI 2 $ic
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_controller]
set_property CONFIG.C_EXT_RESET_HIGH 0 $rst
set one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one]
set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero]
set_property CONFIG.CONST_VAL 0 $zero
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins control_bus/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins control_bus/M00_AXI] [get_bd_intf_pins acquisition/S_AXI]
connect_bd_intf_net [get_bd_intf_pins control_bus/M01_AXI] [get_bd_intf_pins dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins acquisition/M_AXIS] [get_bd_intf_pins dma/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins ps7/S_AXI_HP0]
foreach p {ps7/M_AXI_GP0_ACLK ps7/S_AXI_HP0_ACLK acquisition/axi_clk dma/s_axi_lite_aclk dma/m_axi_s2mm_aclk control_bus/ACLK control_bus/S00_ACLK control_bus/M00_ACLK control_bus/M01_ACLK reset_controller/slowest_sync_clk} {
  connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins $p]
}
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset_controller/ext_reset_in]
connect_bd_net [get_bd_pins const_one/dout] [get_bd_pins reset_controller/dcm_locked] [get_bd_pins acquisition/adc_valid]
connect_bd_net [get_bd_pins const_zero/dout] [get_bd_pins reset_controller/aux_reset_in] [get_bd_pins reset_controller/mb_debug_sys_rst]
foreach p {acquisition/axi_resetn dma/axi_resetn control_bus/ARESETN control_bus/S00_ARESETN control_bus/M00_ARESETN control_bus/M01_ARESETN} {
  connect_bd_net [get_bd_pins reset_controller/peripheral_aresetn] [get_bd_pins $p]
}
connect_bd_net [get_bd_pins dma/s2mm_introut] [get_bd_pins ps7/IRQ_F2P]
make_bd_intf_pins_external [get_bd_intf_pins ps7/DDR]
make_bd_intf_pins_external [get_bd_intf_pins ps7/FIXED_IO]
foreach p {meas_clk fault_in adc_v adc_i adc_or_v adc_or_i dac_data excitation_en mux_en electrodes} {
  make_bd_pins_external [get_bd_pins acquisition/$p]
}
set_property CONFIG.FREQ_HZ 10240000 [get_bd_ports meas_clk_0]
assign_bd_address
validate_bd_design
save_bd_design
puts "Block design wiring created. Apply verified PS DDR/MIO, physical I/O adapter, and board XDC before implementation."
