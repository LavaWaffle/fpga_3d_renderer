# clk input is from the 100 MHz oscillator on Urbana board
#create_clock -period 10.000 -name gclk [get_ports clk_100MHz]
create_clock -period 10.000 -name clk_100 -waveform {0.000 5.000} [get_ports clk]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {clk}]

# Btn 0
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports {rst_n}]

# LED 0
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {dummy_led}]