CNN GOLDEN MODEL PACKAGE — UPDATED VERSION
==========================================

Purpose
-------
This package is the software reference used to verify the current FPGA CNN
accelerator configuration numerically.

Current modeled configuration
-----------------------------
- 32x32 single-channel image
- unsigned 8-bit pixels (0..255)
- fixed 3x3 hardware kernel shape
- programmable signed 8-bit coefficients (-128..127)
- stride = 1
- padding = none / valid
- 30x30 output = 900 output positions
- CNN-style cross-correlation (no kernel flip), SUBJECT TO TOP PACKING ASSUMPTION
- raw signed 20-bit MAC result
- optional combinational ReLU + positive saturation to unsigned 16-bit

Files
-----
- golden_model.py
- GOLDEN_MODEL_README.txt
- TOP_ALIGNMENT_AND_ASSUMPTIONS.txt
- RTL_CHANGES_NEEDED.txt
- golden_vectors/<case>/input_image.txt
- golden_vectors/<case>/kernel.txt
- golden_vectors/<case>/expected_mac20.txt
- golden_vectors/<case>/expected_output.txt

Which expected file should the testbench use?
---------------------------------------------
1) expected_mac20.txt
   Compare against signed [19:0] MAC_out when mac_out_valid is asserted.
   This is the raw signed convolution result and is the safest signal to use as
   the mandatory convolution output for competition compliance.

2) expected_output.txt
   Compare against the 16-bit pixel_out after data_formatter_and_ReLU.v.
   This output is ReLU + upper saturation and is unsigned.

The formatter is combinational, so if Top does not add another register,
pixel_out corresponds to the same mac_out_valid cycle as MAC_out.

Vector format
-------------
All files are plain ASCII decimal, one value per line.

- input_image.txt:     1024 values, unsigned decimal, row-major
- kernel.txt:             9 values, signed decimal, row-major
- expected_mac20.txt:   900 values, signed decimal, raster/row-major
- expected_output.txt:  900 values, unsigned decimal, raster/row-major

Run from VS Code
----------------
Install NumPy once:

    python -m pip install numpy

Check the model itself:

    python golden_model.py --self-test

Generate all built-in vectors:

    python golden_model.py --generate-tests

Generate outputs for your own image/kernel:

    python golden_model.py --image input_image.txt --kernel kernel.txt

That writes both:

    expected_mac20.txt
    expected_output.txt

Important unresolved point
--------------------------
Top_Accelerator.v is still needed to prove the relative byte packing of
w00..w22 and k00..k22. This model assumes matching row-major slots and NO
kernel flip. See TOP_ALIGNMENT_AND_ASSUMPTIONS.txt before writing Top.

Extra packing/order test
------------------------
Test 09_top_packing_order_probe is specifically included to detect a Top-level
byte-order or kernel-flip mistake. Under the intended row-major/no-flip mapping,
its FIRST raw output must be exactly:

    285

If the first raw RTL result is not 285, check Top packing before changing the
golden model.
