// ============================================================================
// Top_accelerator.v
// This is the TOP module that glues everything together for our CNN
// convolution accelerator project. Basically this file doesn't really "do"
// any math itself -- it just wires up the 4 building blocks we designed
// (FSM, Data Router, MAC array, Formatter) so they talk to each other
// correctly. Think of it like the "main.c" of our hardware design :)
// ============================================================================
module Top_accelerator #(
    parameter IMAGE_WIDTH  = 32,   // default image is 32x32 like the competition asked
    parameter IMAGE_HEIGHT = 32
)(
    input  wire clk,     // main clock, everything in the design is synchronous to this
    input  wire rst_n,   // active LOW reset (so rst_n = 0 means "reset now")

    // Control & Status Interface
    // These are basically how the outside world (testbench / PS side) tells
    // us to start, and how we tell them we're busy or finished.
    input  wire start,   // pulse this high for 1 cycle to kick off a new frame
    output wire busy,    // high while we are still processing the current frame
    output wire done,    // one-cycle pulse when the LAST output pixel is ready

    // Input Pixel Stream Interface
    // Pixels come in one at a time (streaming), not all at once. Classic
    // valid/ready handshake -> a pixel is only accepted when BOTH
    // pixel_valid (sender says "here's data") AND pixel_ready (we say
    // "yes give it to me") are high on the same clock edge.
    input  wire [7:0]  pixel_in,     // 8-bit grayscale pixel value (0-255)
    input  wire        pixel_valid,  // asserted by whoever is feeding pixels
    output wire        pixel_ready,  // asserted by us when we can accept a pixel

    // Programmable Weights
    // Expected as a flattened 72-bit vector (9 weights x 8 bits)
    // Note to self: this is NOT one 72-bit number, it's 9 separate signed
    // 8-bit kernel coefficients just packed next to each other so we only
    // need one port instead of 9 separate ports.
    input  wire signed [71:0] kernel,

    // Output Data Stream Interface
    // Same idea as input, but for results coming OUT of the accelerator.
    output wire [15:0] pixel_out,        // final (post ReLU/saturation) pixel
    output wire        pixel_out_valid   // high for exactly 1 cycle per valid output
);

    // =========================================================================
    // Internal Interconnect Wires
    // These are just the "cables" connecting the sub-modules below. None of
    // them are real ports of Top_accelerator, they only exist inside here.
    // =========================================================================
    
    // FSM to Router control
    // router_en basically means "a new pixel was just accepted, go ahead and
    // shift it into the line buffers / window".
    wire router_en;
    
    // Router to Math Engine data bus
    // This carries the current 3x3 window, all 9 pixels packed into one bus.
    wire [71:0] window_flat;
    
    // MAC to Formatter data
    // Raw (before ReLU/saturation) accumulated result, still signed because
    // convolution with a signed kernel can definitely go negative.
    wire signed [19:0] raw_mac_out;

    // =========================================================================
    // 1. Control FSM
    // =========================================================================
    // Handles all counters, handshakes, and pipeline synchronization.
    // This is basically the "brain" of the design -- it knows which row/col
    // we're on, when we have a full legal window, and when the whole frame
    // is finished draining through the pipeline.
    Control_FSM #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) u_FSM (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .router_en(router_en),             // Acts as valid_in for the Data Router
        .window_valid(),                   // Internal to FSM valid pipeline calculation
        // ^ we don't actually need this outside the FSM so we just leave the
        // port unconnected here (dangling), the FSM uses it internally anyway.
        .mac_out_valid(pixel_out_valid),   // Aligned perfectly with the final MAC output
        .busy(busy),
        .done(done)
    );

    // =========================================================================
    // 2. Memory & Data Routing Subsystem
    // =========================================================================
    // Transforms the 1D pixel stream into a 2D packed 72-bit spatial window.
    // (this is where the line buffers + window generator live, see
    // Data_Router.v for the actual details)
    Data_Router #(
        .Image_Width(IMAGE_WIDTH)
    ) u_Data_Router (
        .clk(clk),
        .valid_in(router_en),
        .pixel_in(pixel_in),
        .window_flat(window_flat)
    );

    // =========================================================================
    // 3. Math Engine (MAC Array)
    // =========================================================================
    // Executes 9 parallel multiplications and accumulates the result.
    // This is the actual "convolution math" part -- 9 pixels x 9 kernel
    // weights, multiplied and summed up with a pipelined adder tree.
    MAC_array u_MAC_array (
        .clk(clk),
        .kernel(kernel),
        .image_pixels(window_flat),
        .MAC_out(raw_mac_out)
    );

    // =========================================================================
    // 4. Output Formatting & ReLU
    // =========================================================================
    // Clips negative values to 0 and clamps overflows to 16'hFFFF.
    // Basically turns the "raw math result" into a nice clean pixel value
    // that we can actually display/store.
    data_formatter_and_ReLU u_Formatter (
        .MAC_out(raw_mac_out),
        .pixel_out(pixel_out)
    );

endmodule
