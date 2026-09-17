# Aggressive 400 MHz clock constraint to force timing failure and find WNS
create_clock -period 2.500 -name clk [get_ports clk]