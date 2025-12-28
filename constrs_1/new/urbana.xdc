# clk input is from the 100 MHz oscillator on Urbana board
#create_clock -period 10.000 -name gclk [get_ports clk_100MHz]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {clk}]