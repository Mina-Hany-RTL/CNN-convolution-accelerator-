# FPGA-Based Edge-AI Vision Accelerator

A streaming 3x3 convolution accelerator for grayscale image processing, designed in Verilog for the IEEE SSCS Egypt Student Design Competition 2026. The design targets a Xilinx Zynq-7000 FPGA and implements a programmable CNN-style convolution engine for single-channel 32x32 images.

This repository includes the RTL, simulation testbench, golden-model verification package, Vivado project metadata, implementation reports, and the project report PDF.

## Team and project context

- Team: Abtal Eldigital
- Members:
  - Mina Hany Eid
  - Ziad Mostafa Abdelwahed
  - Jomana Abdelmohsen Abdelatty
  - Omar Sherif Hussien
- Institution: Ain Shams University, Faculty of Engineering
- Department: Computer and Systems Engineering
- Competition: IEEE SSCS Egypt Student Design Competition 2026

## Why this project matters

Convolution is the core computational primitive of CNNs, but it is expensive in software and inefficient when implemented naively in hardware. This accelerator is designed to keep the datapath compact, streaming, and highly parallel while remaining synthesizable and easy to verify.

The architecture processes pixels in raster order, builds a 3x3 sliding window, multiplies it by a programmable 3x3 kernel, and emits a valid output stream with ReLU-style post-processing.

## Design summary

| Parameter | Value |
| --- | --- |
| Input image | 32x32 grayscale |
| Pixel format | Unsigned 8-bit (0..255) |
| Kernel format | 9 signed 8-bit coefficients |
| Kernel shape | 3x3 |
| Convolution mode | Cross-correlation (no kernel flip) |
| Stride | 1 |
| Padding | None / valid-only |
| Output size | 30x30 = 900 valid outputs |
| Raw MAC output | Signed 20-bit |
| Final pixel output | Unsigned 16-bit after ReLU + saturation |
| Target FPGA | xc7z020clg400-1 |

The valid output size is calculated as:

```text
(32 - 3) / 1 + 1 = 30
30 x 30 = 900 output values
```

## System architecture

```text
        +------------------+
        |  Input stream    |
        |  pixel_valid/    |
        |  pixel_ready     |
        +---------+--------+
                  |
                  v
      +------------------------------+
      | Control_FSM                 |
      | - start/idle/stream/drain  |
      | - valid timing alignment   |
      +--------------+---------------+
                     |
                     v
      +------------------------------+
      | Data_Router                 |
      | - line buffers             |
      | - 3x3 window generator     |
      +--------------+---------------+
                     |
                     v
      +------------------------------+
      | MAC_array                   |
      | - 9 parallel multipliers    |
      | - adder tree               |
      | - signed 20-bit MAC_out     |
      +--------------+---------------+
                     |
                     v
      +------------------------------+
      | data_formatter_and_ReLU     |
      | - ReLU                     |
      | - positive saturation       |
      | - 16-bit pixel_out          |
      +------------------------------+
```

### 1) Control FSM
The RTL controller (`rtl/Control_FSM.v`) handles the frame lifecycle:

- waits in IDLE for a start pulse
- accepts pixels in STREAM mode
- tracks row/column position for valid window generation
- asserts a delayed valid signal aligned with the MAC pipeline latency
- moves to DRAIN when the final pixel is accepted
- asserts `done` when the last output has propagated

### 2) Data routing and window formation
The input image enters one pixel at a time through a valid/ready handshake. The router stores previous rows and forms a 3x3 spatial neighborhood that is forwarded into the MAC core. This is implemented with line buffering and shift-register based window extraction.

### 3) MAC datapath
The multiply-accumulate unit (`rtl/MAC_array.v`) multiplies the nine window pixels by nine kernel coefficients in parallel and reduces the products through an adder tree. This gives a raw signed 20-bit convolution result for each valid window.

### 4) Output formatting
The formatter (`rtl/data_formatter_and_ReLU.v`) applies:

- ReLU: negative results are clamped to zero
- saturation: positive results above 16-bit range are clamped to `16'hFFFF`

The final result is a 16-bit unsigned output pixel.

## Top-level interface

The main module is `rtl/Top_accelerator.v`.

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

### Kernel packing
The 72-bit kernel input is packed as nine signed 8-bit values in row-major order:

```text
kernel[7:0]    = k00
kernel[15:8]  = k01
kernel[23:16] = k02
kernel[31:24] = k10
kernel[39:32] = k11
kernel[47:40] = k12
kernel[55:48] = k20
kernel[63:56] = k21
kernel[71:64] = k22
```

The design assumes consistent row-major slot ordering and no kernel flip. This is a critical alignment requirement enforced by the testbench and golden model.

## Repository layout

```text
.
├── README.md
├── Report.pdf
├── .gitignore
├── rtl/
│   ├── Top_accelerator.v
│   ├── Control_FSM.v
│   ├── Data_Router.v
│   ├── Line_Buffer.v
│   ├── Window_Generator.v
│   ├── MAC_array.v
│   ├── parallel_multipliers.v
│   ├── adder_tree.v
│   └── data_formatter_and_ReLU.v
├── tb/
│   └── Top_accelerator_tb.v
├── cnn_golden_model_package_v2/
│   ├── golden_model.py
│   ├── GOLDEN_MODEL_README.txt
│   ├── TOP_ALIGNMENT_AND_ASSUMPTIONS.txt
│   ├── RTL_CHANGES_NEEDED.txt
│   └── golden_vectors/
├── scripts/
│   └── run.do
├── sim/
│   ├── README.md
│   ├── regression_transcript.log
│   └── active_processing.saif
├── FPGA/
│   ├── Timing.xdc
│   ├── CNN_Project/CNN_Project.xpr
│   └── Reports/
└──
```

## Golden model and verification

The project includes a Python reference model in `cnn_golden_model_package_v2/golden_model.py` that numerically verifies the expected behavior for the current hardware configuration.

It models:

- 32x32 grayscale input image
- 3x3 signed 8-bit kernel
- stride = 1, valid-only output generation
- raw 20-bit MAC result
- ReLU + positive saturation to 16-bit unsigned output

The verification package includes nine built-in test vectors covering:

1. zero input / identity kernel
2. all-ones image / all-ones kernel
3. increasing image / identity kernel
4. Sobel-like pattern
5. random image and kernel
6. max-value saturation
7. positive overflow case
8. negative ReLU case
9. top packing/order validation

### Run the Python golden model

```bash
cd /workspaces/CNN-convolution-accelerator-
python -m pip install numpy
python cnn_golden_model_package_v2/golden_model.py --self-test
```

To generate the built-in vectors:

```bash
python cnn_golden_model_package_v2/golden_model.py --generate-tests
```

To evaluate a custom image/kernel pair:

```bash
python cnn_golden_model_package_v2/golden_model.py \
  --image input_image.txt \
  --kernel kernel.txt
```

## Simulation flow

The repository provides a QuestaSim/ModelSim flow via `scripts/run.do`.

```bash
cd /workspaces/CNN-convolution-accelerator-
vsim -do scripts/run.do
```

The testbench `tb/Top_accelerator_tb.v` streams each golden-vector case into the DUT and checks the output values cycle-by-cycle. The transcript confirms the intended behavior:

```text
ALL 9 TESTS PASSED SUCCESSFULLY!
```

## FPGA implementation results

The provided Vivado project and implementation reports target the `xc7z020clg400-1` device.

| Metric | Result |
| --- | ---: |
| LUTs | 235 |
| Flip-flops | 279 |
| BRAM36 | 0 |
| BRAM18 | 0 |
| DSP48 blocks | 9 |
| Operating clock frequency | 250 MHz |
| Maximum frequency (Fmax) | 289.9 MHz |
| Clock period at operating point | 4.000 ns |
| Worst setup slack | 0.388 ns |
| Worst hold slack | 0.067 ns |
| Total on-chip power | 0.156 W |

## Key implementation notes

- The datapath is fully pipelined to maintain throughput while keeping the resource count low.
- Nine parallel multipliers reduce arithmetic latency and allow a compact streaming design.
- The design preserves programmable kernel coefficients and can be reused for different filter values without re-synthesizing the entire datapath.
- The design is intentionally valid-only for no-padding convolution, matching the competition constraints and the golden-model assumption.

## Project report

The full technical report is available as `Report.pdf` and documents system overview, RTL design decisions, verification strategy, FPGA results, and trade-offs.

## License and usage

This project is intended for academic and educational use as part of the IEEE SSCS Egypt Student Design Competition workflow. The RTL, testbench, and golden-model files are provided as reference material for hardware design verification and FPGA implementation exploration.
