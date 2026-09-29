## RESET SWITCH
set_property PACKAGE_PIN A8 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

## DONE LED
set_property PACKAGE_PIN H5 [get_ports done_led]
set_property IOSTANDARD LVCMOS33 [get_ports done_led]

## USB UART
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports usb_uart_rxd]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports usb_uart_txd]

## Clock signal
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports sys_clock]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports sys_clock]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets sys_clock_IBUF]

## Debug hub
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]

## Fan-out constraints to fix conv2 weight BRAM critical path
## Problem: conv2_w_mem BRAM output fans out to 288 wt[] registers
##          causing 6.96ns routing delay (73% of 9.414ns path)
## Fix: force Vivado to duplicate registers near their destinations
set_property MAX_FANOUT 4 [get_nets {design_1_i/cnn_core_0/inst/u_conv2/w_dout_reg[*]}]
