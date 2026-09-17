vlib work
vmap work work

vlog data_formatter_and_ReLU.v
vlog Control_FSM.v
vlog Window_Generator.v
vlog Line_Buffer.v
vlog Data_Router.v
vlog parallel_multipliers.v
vlog adder_tree.v
vlog MAC_array.v
vlog Top_accelerator.v
vlog Top_accelerator_tb.v

# Start the simulation with optimization arguments that preserve signal visibility (+acc)
vsim -voptargs=+acc work.Top_accelerator_tb

# Open relevant UI windows
view wave
view structure
view signals

# ---------------------------------------------------
# Waveform Configuration
# ---------------------------------------------------
add wave -divider "Global Controls"
add wave -noupdate -radix binary /Top_accelerator_tb/clk
add wave -noupdate -radix binary /Top_accelerator_tb/rst_n
add wave -noupdate -radix binary /Top_accelerator_tb/start
add wave -noupdate -radix binary /Top_accelerator_tb/busy
add wave -noupdate -radix binary /Top_accelerator_tb/done

add wave -divider "Input Interface"
add wave -noupdate -radix hex /Top_accelerator_tb/kernel
add wave -noupdate -radix binary /Top_accelerator_tb/pixel_valid
add wave -noupdate -radix binary /Top_accelerator_tb/pixel_ready
add wave -noupdate -radix unsigned /Top_accelerator_tb/pixel_in

add wave -divider "Output Interface"
add wave -noupdate -radix binary /Top_accelerator_tb/pixel_out_valid
add wave -noupdate -radix unsigned /Top_accelerator_tb/pixel_out

add wave -divider "Internal FSM Tracking"
add wave -noupdate -radix unsigned /Top_accelerator_tb/uut/u_FSM/state
add wave -noupdate -radix unsigned /Top_accelerator_tb/uut/u_FSM/row_count
add wave -noupdate -radix unsigned /Top_accelerator_tb/uut/u_FSM/col_count

# Automatically format the waveform viewer to fit all signals
WaveRestoreZoom {0 ns} {1000 ns}

# ---------------------------------------------------
# SAIF capture — arm ONLY on the 5th start/done pair
# (test 05_random_image_random_kernel, given tests run in
#  01..09 order in the testbench's initial block)
# ---------------------------------------------------
set start_count 0
set power_added 0
set power_reported 0
when {/Top_accelerator_tb/start == 1} {
    incr start_count
    if {$start_count == 5 && !$power_added} {
        power add -r -in -inout -out -internal /Top_accelerator_tb/uut/*
        set power_added 1
        echo "Power tracking started at [now] (test 5, start #$start_count)"
    }
}
when {/Top_accelerator_tb/done == 1} {
    if {$power_added && !$power_reported} {
        power report -all -bsaif active_processing.saif
        set power_reported 1
        echo "SAIF written at [now]"
    }
}
run -all