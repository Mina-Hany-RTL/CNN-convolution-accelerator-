// ============================================================================
// Data_Router.v
// Small "glue" module -- just wires together 2 Line_Buffers (to delay
// whole rows) and 1 Window_Generator (to actually build the 3x3 window).
// Short file but it's actually the key idea of how we turn a 1D pixel
// stream into a 2D sliding window without needing a full frame buffer.
// ============================================================================
module Data_Router #(parameter Image_Width=32) (input clk,valid_in, input [7:0] pixel_in,
                                                output [71:0] window_flat);
// these carry the "delayed by 1 row" and "delayed by 2 rows" pixel streams
wire [7:0] LB1_out, LB2_out;

// LB1 takes the LIVE pixel stream and delays it by exactly one full row
Line_Buffer #(Image_Width) LB1 (clk,valid_in,pixel_in,LB1_out); // FIFO delays pixel by one row
// LB2 takes LB1's output and delays it ANOTHER row, so overall it's 2 rows behind
Line_Buffer #(Image_Width) LB2 (clk,valid_in,LB1_out,LB2_out); // FIFO delays pixel by two rows
// now we feed all 3 "row streams" (2-rows-ago, 1-row-ago, live) into the
// window generator, which stacks them into the 3x3 window we need
Window_Generator win (clk,valid_in,LB2_out,LB1_out,pixel_in,window_flat);

endmodule
