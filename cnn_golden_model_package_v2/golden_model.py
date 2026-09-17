#!/usr/bin/env python3
"""Golden reference model for the team's current FPGA CNN datapath.

CURRENT TEAM CONFIGURATION MODELED
----------------------------------
- Image: 32x32, single-channel, unsigned 8-bit pixels.
- Kernel: fixed 3x3 architecture, programmable signed 8-bit coefficients.
- Stride: 1.
- Padding: none / valid convolution.
- Numerical operation: CNN-style cross-correlation (NO kernel flip), under the
  explicit Top-level byte-packing assumption documented below.
- Raw convolution result: signed 20-bit MAC_out.
- Optional post-processing block: combinational ReLU + unsigned 16-bit upper
  saturation, matching data_formatter_and_ReLU.v.

IMPORTANT TOP-LEVEL PACKING ASSUMPTION
--------------------------------------
The supplied RTL proves that multiplier slot i multiplies:

    image_pixels[i*8 +: 8] * kernel[i*8 +: 8]

but the Top_Accelerator packing that creates image_pixels[71:0] and packs the
external 3x3 kernel into kernel[71:0] has not been supplied. This model assumes:

    slot 0 = w00 / k00
    slot 1 = w01 / k01
    slot 2 = w02 / k02
    slot 3 = w10 / k10
    slot 4 = w11 / k11
    slot 5 = w12 / k12
    slot 6 = w20 / k20
    slot 7 = w21 / k21
    slot 8 = w22 / k22

That is row-major matching with no 180-degree kernel flip. Top_Accelerator must
use the same mapping, or this model must be changed to match Top.

OUTPUT FILES
------------
- expected_mac20.txt:
    Raw signed 20-bit convolution result. Use this to verify the core mandatory
    signed convolution datapath.
- expected_output.txt:
    Post-ReLU/post-saturation unsigned 16-bit pixel_out. Use this to verify the
    optional data_formatter_and_ReLU block.

The model is mathematical: it reproduces RTL numeric behavior and output order,
not FSM states, line-buffer cycle timing, or pipeline latency.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable, Tuple

import numpy as np

# Fixed team configuration used by this golden model.
IMAGE_H = 32
IMAGE_W = 32
KERNEL_H = 3
KERNEL_W = 3
STRIDE = 1
OUT_H = 30
OUT_W = 30
OUTPUT_COUNT = 900

# Matrix coordinates associated with multiplier slots 0..8 under the explicit
# Top-level row-major/no-flip assumption above.
SLOT_COORDS: Tuple[Tuple[int, int], ...] = (
    (0, 0), (0, 1), (0, 2),
    (1, 0), (1, 1), (1, 2),
    (2, 0), (2, 1), (2, 2),
)


def wrap_signed(value: int, bits: int) -> int:
    """Interpret value as an exactly 'bits'-wide two's-complement integer."""
    mask = (1 << bits) - 1
    value &= mask
    sign = 1 << (bits - 1)
    return value - (1 << bits) if (value & sign) else value


def validate_inputs(image: np.ndarray, kernel: np.ndarray) -> None:
    if image.shape != (IMAGE_H, IMAGE_W):
        raise ValueError(f"image must be exactly {IMAGE_H}x{IMAGE_W}, got {image.shape}")
    if kernel.shape != (KERNEL_H, KERNEL_W):
        raise ValueError(f"kernel must be exactly {KERNEL_H}x{KERNEL_W}, got {kernel.shape}")
    if not np.all((image >= 0) & (image <= 255)):
        raise ValueError("pixel values must be unsigned 8-bit values in 0..255")
    if not np.all((kernel >= -128) & (kernel <= 127)):
        raise ValueError("kernel coefficients must be signed 8-bit values in -128..127")


def rtl_mac_3x3(window: np.ndarray, kernel: np.ndarray) -> int:
    """Reproduce parallel_multipliers + adder_tree numerical behavior."""
    if window.shape != (3, 3):
        raise ValueError(f"window must be 3x3, got {window.shape}")
    if kernel.shape != (3, 3):
        raise ValueError(f"kernel must be 3x3, got {kernel.shape}")

    products = []
    for r, c in SLOT_COORDS:
        # RTL kernel byte: $signed(kernel[i*8 +: 8]) => -128..127.
        k = wrap_signed(int(kernel[r, c]), 8)

        # RTL pixel byte: $signed({1'b0, image_pixels[...]}) => +0..255.
        p = int(window[r, c])

        # Product is carried/stored as signed 16 bits in the current datapath.
        products.append(wrap_signed(k * p, 16))

    # Match the exact current adder-tree grouping and declared bit widths.
    s1 = [
        wrap_signed(products[0] + products[1], 17),
        wrap_signed(products[2] + products[3], 17),
        wrap_signed(products[4] + products[5], 17),
        wrap_signed(products[6] + products[7], 17),
        wrap_signed(products[8], 17),
    ]
    s2 = [
        wrap_signed(s1[0] + s1[1], 18),
        wrap_signed(s1[2] + s1[3], 18),
        wrap_signed(s1[4], 18),
    ]
    s3 = [
        wrap_signed(s2[0] + s2[1], 19),
        wrap_signed(s2[2], 19),
    ]
    return wrap_signed(s3[0] + s3[1], 20)


def rtl_formatter(mac_out: int) -> int:
    """Exact numerical behavior of data_formatter_and_ReLU.v."""
    mac_out = wrap_signed(mac_out, 20)
    if mac_out < 0:
        return 0
    if mac_out <= 0xFFFF:
        return mac_out
    return 0xFFFF


def golden_model(image: np.ndarray, kernel: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Return (formatted_relu16, raw_mac20), each in 30x30 raster order."""
    image = np.asarray(image, dtype=np.int64)
    kernel = np.asarray(kernel, dtype=np.int64)
    validate_inputs(image, kernel)

    raw = np.zeros((OUT_H, OUT_W), dtype=np.int64)
    formatted = np.zeros((OUT_H, OUT_W), dtype=np.int64)

    # Valid 3x3 cross-correlation, stride 1, no padding.
    for out_r in range(OUT_H):
        for out_c in range(OUT_W):
            window = image[out_r:out_r + 3, out_c:out_c + 3]
            mac = rtl_mac_3x3(window, kernel)
            raw[out_r, out_c] = mac
            formatted[out_r, out_c] = rtl_formatter(mac)

    if raw.shape != (30, 30) or formatted.shape != (30, 30):
        raise AssertionError("internal error: output shape is not 30x30")
    if raw.size != OUTPUT_COUNT or formatted.size != OUTPUT_COUNT:
        raise AssertionError("internal error: output count is not 900")

    # Legal pixel/kernel ranges cannot overflow signed 20-bit raw MAC.
    if not np.all((raw >= -(1 << 19)) & (raw <= (1 << 19) - 1)):
        raise AssertionError("internal error: raw MAC escaped signed 20-bit range")

    return formatted, raw


def write_values(path: Path, values: Iterable[int]) -> None:
    """Write decimal integers, one value per line."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as f:
        for value in values:
            f.write(f"{int(value)}\n")


def read_values(path: Path, expected_count: int) -> np.ndarray:
    vals = []
    with path.open("r", encoding="ascii") as f:
        for line_no, line in enumerate(f, 1):
            text = line.strip()
            if not text:
                continue
            try:
                vals.append(int(text, 10))
            except ValueError as exc:
                raise ValueError(
                    f"{path}:{line_no}: expected a decimal integer, got {text!r}"
                ) from exc

    if len(vals) != expected_count:
        raise ValueError(f"{path}: expected {expected_count} values, got {len(vals)}")
    return np.asarray(vals, dtype=np.int64)


def save_case(case_dir: Path, image: np.ndarray, kernel: np.ndarray) -> None:
    formatted, raw = golden_model(image, kernel)
    write_values(case_dir / "input_image.txt", image.reshape(-1))
    write_values(case_dir / "kernel.txt", kernel.reshape(-1))
    write_values(case_dir / "expected_output.txt", formatted.reshape(-1))
    write_values(case_dir / "expected_mac20.txt", raw.reshape(-1))


def build_order_probe() -> Tuple[np.ndarray, np.ndarray]:
    """Create an easy-to-debug vector that exposes slot order / kernel flipping."""
    image = np.zeros((32, 32), dtype=np.int64)
    image[:3, :3] = np.array([
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ], dtype=np.int64)

    kernel = np.array([
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ], dtype=np.int64)
    return image, kernel


def make_test_cases(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)

    identity = np.array([
        [0, 0, 0],
        [0, 1, 0],
        [0, 0, 0],
    ], dtype=np.int64)

    all_ones_kernel = np.ones((3, 3), dtype=np.int64)

    sobel_x = np.array([
        [-1, 0, 1],
        [-2, 0, 2],
        [-1, 0, 1],
    ], dtype=np.int64)

    save_case(
        root / "01_zero_image_identity",
        np.zeros((32, 32), dtype=np.int64),
        identity,
    )

    save_case(
        root / "02_one_image_all_ones_kernel",
        np.ones((32, 32), dtype=np.int64),
        all_ones_kernel,
    )

    increasing = np.arange(32 * 32, dtype=np.int64).reshape(32, 32) % 256
    save_case(root / "03_increasing_image_identity", increasing, identity)

    rr, cc = np.indices((32, 32))
    pattern = ((17 * rr + 29 * cc + 7 * (rr ^ cc)) % 256).astype(np.int64)
    save_case(root / "04_pattern_image_sobel_x", pattern, sobel_x)

    rng = np.random.default_rng(20260907)
    random_image = rng.integers(0, 256, size=(32, 32), dtype=np.int64)
    random_kernel = rng.integers(-128, 128, size=(3, 3), dtype=np.int64)
    save_case(root / "05_random_image_random_kernel", random_image, random_kernel)

    max_image = np.full((32, 32), 255, dtype=np.int64)
    save_case(root / "06_max255_image_identity", max_image, identity)

    max_pos_kernel = np.full((3, 3), 127, dtype=np.int64)
    save_case(root / "07_max255_positive_saturation", max_image, max_pos_kernel)

    max_neg_kernel = np.full((3, 3), -128, dtype=np.int64)
    save_case(root / "08_max255_negative_relu", max_image, max_neg_kernel)

    order_image, order_kernel = build_order_probe()
    save_case(root / "09_top_packing_order_probe", order_image, order_kernel)


def self_test() -> None:
    """Sanity-check the golden model itself before it is used against RTL."""
    identity = np.array([[0, 0, 0], [0, 1, 0], [0, 0, 0]], dtype=np.int64)

    # Zero case.
    formatted, raw = golden_model(np.zeros((32, 32), dtype=np.int64), identity)
    assert np.all(raw == 0) and np.all(formatted == 0)

    # Ones + all-ones kernel -> every valid raw output = 9.
    formatted, raw = golden_model(
        np.ones((32, 32), dtype=np.int64),
        np.ones((3, 3), dtype=np.int64),
    )
    assert np.all(raw == 9) and np.all(formatted == 9)

    # Positive upper saturation.
    max_image = np.full((32, 32), 255, dtype=np.int64)
    formatted, raw = golden_model(max_image, np.full((3, 3), 127, dtype=np.int64))
    assert np.all(raw == 291465)
    assert np.all(formatted == 65535)

    # Negative ReLU.
    formatted, raw = golden_model(max_image, np.full((3, 3), -128, dtype=np.int64))
    assert np.all(raw == -293760)
    assert np.all(formatted == 0)

    # Top-packing/no-flip probe: first window is 1..9 and kernel is 1..9.
    # Row-major/no-flip dot product = 1^2 + ... + 9^2 = 285.
    order_image, order_kernel = build_order_probe()
    formatted, raw = golden_model(order_image, order_kernel)
    assert int(raw[0, 0]) == 285
    assert int(formatted[0, 0]) == 285

    print("SELF-TEST PASS")
    print("  output shape/count: 30x30 / 900")
    print("  max positive raw:   291465 -> ReLU16 65535")
    print("  max negative raw:  -293760 -> ReLU16 0")
    print("  packing probe[0]:   285 (row-major, no kernel flip)")


def run_from_files(
    image_file: Path,
    kernel_file: Path,
    formatted_output_file: Path,
    raw_output_file: Path,
) -> None:
    image = read_values(image_file, 32 * 32).reshape(32, 32)
    kernel = read_values(kernel_file, 3 * 3).reshape(3, 3)
    formatted, raw = golden_model(image, kernel)
    write_values(formatted_output_file, formatted.reshape(-1))
    write_values(raw_output_file, raw.reshape(-1))


def main() -> None:
    parser = argparse.ArgumentParser(description="RTL-matching 3x3 CNN golden model")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run built-in mathematical sanity checks",
    )
    parser.add_argument(
        "--generate-tests",
        action="store_true",
        help="generate all built-in test-vector directories",
    )
    parser.add_argument(
        "--tests-dir",
        type=Path,
        default=Path("golden_vectors"),
        help="directory for generated vectors (default: golden_vectors)",
    )
    parser.add_argument("--image", type=Path, help="1024-line unsigned decimal image file")
    parser.add_argument("--kernel", type=Path, help="9-line signed decimal kernel file")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("expected_output.txt"),
        help="900-line post-ReLU/saturation unsigned output file",
    )
    parser.add_argument(
        "--raw-output",
        type=Path,
        default=Path("expected_mac20.txt"),
        help="900-line raw signed 20-bit MAC output file",
    )
    args = parser.parse_args()

    if args.self_test:
        self_test()

    if args.generate_tests:
        make_test_cases(args.tests_dir)
        print(f"Generated test vectors in: {args.tests_dir.resolve()}")

    if (args.image is None) ^ (args.kernel is None):
        parser.error("--image and --kernel must be supplied together")

    if args.image is not None and args.kernel is not None:
        run_from_files(args.image, args.kernel, args.output, args.raw_output)
        print(f"Wrote formatted ReLU output: {args.output.resolve()}")
        print(f"Wrote raw signed MAC output: {args.raw_output.resolve()}")

    if not args.self_test and not args.generate_tests and args.image is None:
        parser.print_help()


if __name__ == "__main__":
    main()
