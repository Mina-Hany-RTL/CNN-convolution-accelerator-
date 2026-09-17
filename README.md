# FPGA-Based Edge-AI Vision Accelerator

This repository contains a streaming CNN convolution accelerator implemented
in synthesizable Verilog for the IEEE SSCS Egypt Student Design Competition
2026. The design targets a Xilinx Zynq-7000 device and processes one
single-channel image frame at a time using a fixed 3x3 convolution datapath.

The checked-in repository includes the RTL, testbench, Python golden model,
golden vectors, Questa/ModelSim scripts, SAIF activity data, Vivado project
metadata, timing constraints, implementation reports, and the project report.

## Design summary

| Item | Current configuration |
| --- | --- |
| Input image | 32x32, one channel |
| Pixel format | Unsigned 8-bit, 0 to 255 |
| Kernel | 3x3, nine signed 8-bit coefficients |
| Convolution | Cross-correlation, no kernel flip |
| Stride and padding | Stride 1, valid/no padding |
| Output geometry | 30x30, 900 valid positions |
| Raw result | Signed 20-bit MAC result |
| Formatted result | Unsigned 16-bit ReLU and positive saturation |
| Target device | `xc7z020clg400-1` |

For a 32x32 input, the valid output size is:

```text
(32 - 3) / 1 + 1 = 30
30 x 30 = 900 output values
```

## Repository layout

```text
rtl/
  Top_accelerator.v              Top-level integration module
  Control_FSM.v                  Frame control and valid timing
  Data_Router.v                  Pixel-to-window routing
  Line_Buffer.v                  Two image line buffers
  Window_Generator.v             3x3 spatial window registers
  MAC_array.v                    Nine-way multiply-accumulate datapath
  parallel_multipliers.v         Nine parallel signed multipliers
  adder_tree.v                   Pipelined partial-sum reduction
  data_formatter_and_ReLU.v      ReLU and 16-bit positive saturation

tb/
  Top_accelerator_tb.v            RTL regression testbench

cnn_golden_model_package_v2/
  golden_model.py                 Numerical Python reference model
  golden_vectors/                 Nine input/kernel/expected-output cases
  GOLDEN_MODEL_README.txt         Model and vector usage
  TOP_ALIGNMENT_AND_ASSUMPTIONS.txt
                                  Required top-level packing assumptions
  RTL_CHANGES_NEEDED.txt          Follow-up engineering notes

scripts/
  run.do                          Questa/ModelSim compile and regression script

sim/
  regression_transcript.log       Captured nine-case simulator transcript
  active_processing.saif          Switching activity from regression case 05
  README.md                       Simulation artifact description

FPGA/
  CNN_Project/CNN_Project.xpr     Vivado project metadata
  Timing.xdc                     Clock and timing constraints
  Reports/                       Required competition implementation reports

Report.pdf                        Project and competition report
```

Vivado generated caches, run directories, simulator work products, and other
temporary outputs are excluded by `.gitignore`. The reports in
`FPGA/Reports/` are explicitly included because they are competition
deliverables.

## RTL architecture and dataflow

The top-level module is `rtl/Top_accelerator.v`. It connects four functional
subsystems:

1. **Control FSM** - accepts a frame start, tracks the image position, controls
   the input handshake, and aligns output-valid timing with the pipelined MAC.
2. **Data router** - accepts pixels in raster order and shifts them through two
   line buffers and a window generator to form each 3x3 neighborhood.
3. **MAC array** - multiplies nine window pixels by nine kernel coefficients in
   parallel and reduces the products through an adder tree.
4. **Output formatter** - maps negative MAC results to zero and saturates
   positive results above 65535 to `16'hFFFF`.

The raw signed MAC result is the safest signal for checking the convolution
itself. The formatted `pixel_out` signal is a post-processing representation
that applies ReLU and unsigned 16-bit saturation.

## Top-level interface

`Top_accelerator` has a synchronous clock and active-low reset:

```verilog
module Top_accelerator #(
    parameter IMAGE_WIDTH  = 32,
    parameter IMAGE_HEIGHT = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output wire        busy,
    output wire        done,
    input  wire [7:0]  pixel_in,
    input  wire        pixel_valid,
    output wire        pixel_ready,
    input  wire signed [71:0] kernel,
    output wire [15:0] pixel_out,
    output wire        pixel_out_valid
);
```

### Control signals

- Assert `rst_n = 0` to reset the design.
- Pulse `start` for one clock cycle to begin a frame.
- A pixel is accepted only when `pixel_valid && pixel_ready` is high at the
  active clock edge.
- `busy` remains high while the frame is being processed.
- `done` pulses when the final output has completed.
- `pixel_out_valid` identifies each valid formatted output value.

The source must keep `pixel_in` and `pixel_valid` stable until a transfer is
accepted. Kernel coefficients should remain stable for the complete frame.

### Kernel packing

The 72-bit `kernel` input contains nine signed 8-bit coefficients in row-major
spatial order:

```text
kernel[7:0]    = k00    kernel[15:8]  = k01    kernel[23:16] = k02
kernel[31:24]  = k10    kernel[39:32] = k11    kernel[47:40] = k12
kernel[55:48]  = k20    kernel[63:56] = k21    kernel[71:64] = k22
```

When building the vector by concatenation, this corresponds to
`{k22,k21,k20,k12,k11,k10,k02,k01,k00}`. Negative coefficients are preserved
as 8-bit two's-complement values; for example, `-1` is `8'hFF`.

The window must use the same slot order for `w00` through `w22`. The packing
probe in test case 09 uses the 3x3 values 1 through 9 with the same kernel and
expects a first raw result of 285.

## Golden model and test vectors

`cnn_golden_model_package_v2/golden_model.py` is the numerical reference for
the current hardware configuration. It models:

- unsigned 8-bit input pixels;
- signed 8-bit integer kernel coefficients;
- one input channel;
- 3x3 cross-correlation without kernel flipping;
- stride 1 and valid/no-padding geometry;
- signed 20-bit raw MAC values; and
- ReLU plus upper saturation for the formatted output.

The model does not attempt to reproduce FSM states, line-buffer fill cycles,
or internal pipeline latency. It checks numerical values in raster order.

Each vector case contains:

```text
input_image.txt       1024 unsigned decimal values, row-major
kernel.txt               9 signed decimal values, row-major
expected_mac20.txt     900 signed raw convolution results
expected_output.txt    900 unsigned formatted results
```

The nine cases cover zero input, all-ones input, increasing data, a Sobel
pattern, random data, maximum-value saturation, negative ReLU behavior, and
top-level packing order.

From the repository root, run:

```text
python cnn_golden_model_package_v2/golden_model.py --self-test
```

To regenerate the built-in vectors:

```text
python cnn_golden_model_package_v2/golden_model.py --generate-tests
```

To generate outputs for a custom image and kernel:

```text
python cnn_golden_model_package_v2/golden_model.py \
  --image input_image.txt \
  --kernel kernel.txt
```

The Python model requires NumPy:

```text
python -m pip install numpy
```

## RTL simulation

The intended simulator flow uses QuestaSim/ModelSim and `scripts/run.do`. The
script compiles the RTL and testbench, launches `Top_accelerator_tb`, opens
useful waveform signals, arms SAIF capture for regression case 05, and runs
the complete test sequence.

The script references the Verilog source files by name. Run it from a
simulation working directory where the RTL and testbench source paths resolve,
or adapt the `vlog` paths to your simulator project layout.

The checked-in `sim/regression_transcript.log` records:

```text
ALL 9 TESTS PASSED SUCCESSFULLY!
```

Each vector completed with zero errors. The transcript also preserves a
redundant-literal compiler warning and end-of-run simulator messages, so those
messages should not be confused with failed vector comparisons.

The testbench captures switching activity during
`05_random_image_random_kernel`. The resulting
`sim/active_processing.saif` file can be supplied to a downstream power
analysis flow.

## Vivado implementation

Open `FPGA/CNN_Project/CNN_Project.xpr` in Vivado 2018.2 or a compatible
Vivado version. The project targets the Zynq-7000
`xc7z020clg400-1`. `FPGA/Timing.xdc` contains the clock constraint used for
implementation.

The checked-in reports describe a routed implementation with:

| Resource/check | Reported result |
| --- | ---: |
| LUTs | 235 |
| Flip-flops | 279 |
| BRAM36 / BRAM18 | 0 / 0 |
| DSP48 blocks | 9 |
| Clock period | 4.000 ns (250 MHz) |
| Worst setup slack | 0.388 ns |
| Worst hold slack | 0.067 ns |
| Setup failing endpoints | 0 |
| Hold failing endpoints | 0 |

The reports are preserved under `FPGA/Reports/` for competition review. They
are not intended to be regenerated or edited by the documentation workflow.

## Assumptions and limitations

- The current reference configuration is fixed to a 32x32 grayscale frame and
  3x3 kernel, although the top-level image dimensions are parameters.
- The model assumes row-major input and matching row-major window/kernel slots.
- The model assumes cross-correlation rather than a mathematically flipped
  convolution kernel.
- The current formatter output is unsigned 16-bit ReLU/saturation; the raw
  signed MAC result is the preferred official convolution signal.
- The golden model does not model cycle latency or startup fill behavior.
- Line-buffer and window-generator startup registers are valid only after the
  FSM asserts the corresponding output-valid timing.
- Coefficients should not change during an active frame.

Before changing packing, output interpretation, or valid timing, review
`TOP_ALIGNMENT_AND_ASSUMPTIONS.txt` and rerun the packing probe.

## Troubleshooting

**No output values are observed:** verify reset release, pulse `start`, and
hold each input pixel until `pixel_valid && pixel_ready` is accepted.

**The first packing-probe result is not 285:** inspect the byte ordering of the
window and kernel buses before changing the Python model.

**Expected files do not match:** compare the signed raw `MAC_out` against
`expected_mac20.txt`; compare the ReLU/saturation path against
`expected_output.txt`. Do not compare these two representations interchangeably.

**The simulator cannot find a source file:** run the `.do` script from a
directory with the expected source paths, or replace the bare `vlog` file names
with paths to `rtl/` and `tb/`.

## Reproducing and extending the project

1. Run the Python self-test and inspect the golden vectors.
2. Run the Questa/ModelSim regression and confirm all nine cases pass.
3. Review `sim/regression_transcript.log` and the SAIF artifact.
4. Open the Vivado project, confirm the target part and `Timing.xdc`, and
   regenerate reports only when implementation changes are intentional.
5. Keep new reusable source files under `rtl/`, testbench files under `tb/`,
   simulator artifacts under `sim/`, and scripts under `scripts/`.

When extending the design, update the golden model and vector documentation
alongside any interface or numerical behavior change.
