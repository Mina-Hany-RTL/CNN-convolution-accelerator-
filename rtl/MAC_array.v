// ============================================================================
// MAC_array.v
// This is just a small wrapper that connects our two math sub-modules:
// parallel_multipliers (does all 9 pixel*kernel multiplications at once)
// and adder_tree (sums those 9 products together into one final result).
// Splitting it this way made it way easier to debug -- I could check the
// 9 individual products before trusting the adder tree logic.
// ============================================================================
module MAC_array
(
    input clk,
    input signed [71:0] kernel,        // 9 packed signed 8-bit kernel weights
    input [71:0] image_pixels,         // 9 packed unsigned 8-bit window pixels
    output signed [19:0] MAC_out       // final accumulated convolution result
);
    // holds all 9 individual (pixel * weight) products, packed together,
    // before they get summed up by the adder tree
    wire signed [143:0] temp_wire;

    // step 1: multiply each of the 9 pixels by its matching kernel weight
    parallel_multipliers u_multipliers(.clk(clk), .kernel(kernel),
    .image_pixels(image_pixels), .multiplier_out(temp_wire));

    // step 2: add up all 9 products (with proper bit growth) into MAC_out
    adder_tree u_adder_tree(.clk(clk), .multiplier_out(temp_wire),
        .MAC_out(MAC_out));

endmodule
