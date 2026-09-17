// ============================================================================
// Window_Generator.v
// This module builds the actual 3x3 "window" of pixels that gets fed into
// the MAC array. It takes 3 pixel streams (one from each of the 3 rows
// currently "in view": 2-rows-ago, 1-row-ago, and the live row) and keeps
// a small 3x3 grid of registers that shifts left every cycle, kind of like
// a tiny sliding puzzle. Once the grid is full, window_flat always holds
// the current legal (or not yet legal, FSM handles that part) 3x3 window.
// ============================================================================
module Window_Generator (input clk,valid_in,input [7:0] row_1_in, row_2_in, row_3_in,
                        output [71:0] window_flat );

// naming convention: wXY = row X, col Y of the 3x3 window (0-indexed)
// w02/w12/w22 are the "newest" column (just shifted in), w00/w10/w20 are
// the "oldest" column (about to fall out of the window on the next shift)
reg [7:0] w00, w01, w02;
reg [7:0] w10, w11, w12;
reg [7:0] w20, w21, w22;

always @(posedge clk) begin
    if(valid_in) begin
        // Shift left
        // everything slides one column to the left, making room for the
        // new incoming column on the right (w02/w12/w22)
        w01 <= w02; w00 <= w01; // first row
        w11 <= w12; w10 <= w11; // second row
        w21 <= w22; w20 <= w21; // third row

        // taking the input pixels
        // now fill in the new rightmost column with the freshest pixels
        // from each of our 3 delayed row streams
        w02 <= row_1_in; // first row taking pixel from FIFO delayed by 2 rows
        w12 <= row_2_in; // second raw taking pixel from FIFO delayed by 1 row
        w22 <= row_3_in; // third row taking live pixel ( the pixel that is on input line now)
    end
end

// pack the whole 3x3 window into one flat bus so it's easy to pass around
// (order here has to match what the golden model / testbench expect!)
assign window_flat = {w00, w01, w02, w10, w11, w12, w20, w21, w22};
endmodule         
