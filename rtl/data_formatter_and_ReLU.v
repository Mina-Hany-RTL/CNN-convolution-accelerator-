// ============================================================================
// data_formatter_and_ReLU.v
// Last stop before the pixel leaves the accelerator. Takes the raw signed
// 20-bit MAC result and turns it into a clean unsigned 16-bit pixel value.
// Does 2 jobs at once: (1) ReLU -- clip any negative value to 0, and
// (2) saturation -- clamp anything bigger than 65535 down to 65535 so it
// still fits in 16 bits. Purely combinational (no clock), so it adds zero
// extra pipeline latency.
// ============================================================================
module data_formatter_and_ReLU (
    input  signed [19:0] MAC_out,    // raw signed convolution result
    output reg    [15:0] pixel_out   // final unsigned, ReLU'd + saturated pixel
);

    always @(*) begin
        if (MAC_out < 0) begin
            // ReLU part: negative results just become 0
            pixel_out = 16'd0;
        end
        else if (MAC_out <= 20'h0000FFFF) begin
            // normal case: value already fits fine in 16 bits, just truncate
            // the top (always-zero, since we already know it's <= 0xFFFF) bits
            pixel_out = MAC_out[15:0];
        end
        else begin
            // saturation part: too big for 16 bits, clamp to the max value
            pixel_out = 16'hFFFF;
        end
    end

endmodule
