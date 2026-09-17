# FPGA-Based Edge-AI Vision Accelerator

CNN convolution accelerator implemented in synthesizable Verilog for the IEEE
SSCS Egypt Student Design Competition 2026. The design accepts a streamed
32x32, single-channel image and applies a signed 3x3 kernel with stride 1 and
no padding, producing 900 valid 30x30 convolution results.

## Repository contents

- `rtl/` - Hardware implementation:
  - `Top_accelerator.v` - top-level integration and streaming interface
  - `Control_FSM.v` - frame control, handshaking, counters, and output timing
  - `Data_Router.v`, `Line_Buffer.v`, `Window_Generator.v` - 3x3 window creation
  - `MAC_array.v`, `parallel_multipliers.v`, `adder_tree.v` - nine-way MAC datapath
  - `data_formatter_and_ReLU.v` - ReLU and unsigned 16-bit saturation
- `tb/Top_accelerator_tb.v` - regression testbench
- `cnn_golden_model_package_v2/` - Python reference model and nine golden-vector cases
- `scripts/run.do` - Questa/ModelSim compilation, waveform, and regression script
- `sim/` - simulation artifacts, including the regression transcript and SAIF activity file
- `FPGA/CNN_Project/CNN_Project.xpr` - Vivado project
- `FPGA/Timing.xdc` - clock and timing constraints
- `FPGA/Reports/` - competition implementation reports
- `Report.pdf` - project and competition report

## Hardware interface

`Top_accelerator` uses an active-low reset, a one-cycle `start` request, and a
valid/ready input pixel stream. A pixel is accepted when `pixel_valid` and
`pixel_ready` are both high. The fixed configuration is parameterized by
`IMAGE_WIDTH` and `IMAGE_HEIGHT`, both defaulting to 32.

The kernel is nine signed 8-bit two's-complement coefficients packed into
`kernel[71:0]`. The raw accumulated result is signed 20-bit data. The optional
`pixel_out` path applies ReLU and saturates positive values to 16'hFFFF.

## Golden model and verification

The reference model assumes unsigned 8-bit pixels, signed 8-bit coefficients,
row-major raster order, cross-correlation without kernel flipping, and valid
3x3 convolution. Each vector contains 1,024 input pixels, 9 kernel values, and
900 expected raw and formatted outputs.

From the repository root:

```text
python cnn_golden_model_package_v2/golden_model.py --self-test
```

For Questa/ModelSim, run `scripts/run.do` from a directory where the RTL and
testbench paths resolve, or adapt the source paths for the simulator project.
The checked-in regression transcript records all nine built-in tests completing
with zero errors.

## Implementation snapshot

The checked-in Vivado reports were generated for a routed design targeting the
Xilinx Zynq-7000 `xc7z020clg400-1`. The reported top-level utilization is 235
LUTs, 279 flip-flops, and 9 DSP48 blocks, with no BRAM usage. The timing report
uses a 4 ns clock period (250 MHz), reports 0.388 ns worst setup slack and
0.067 ns worst hold slack, and shows zero failing endpoints for both checks.

## Notes

Vivado caches, run directories, simulator work products, and other generated
files remain excluded by `.gitignore`. The competition reports under
`FPGA/Reports/` are explicitly tracked deliverables.
