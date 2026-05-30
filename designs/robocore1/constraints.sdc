set ::env(CLOCK_PORT) clk
set ::env(CLOCK_PERIOD) 10.0
create_clock [get_ports clk] -name clk -period 10.0
set_input_delay 2.0 -clock clk [all_inputs]
set_output_delay 2.0 -clock clk [all_outputs]
set_clock_uncertainty 0.5 clk
