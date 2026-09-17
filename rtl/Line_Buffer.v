// Line Buffer is implemented as FIFO 
// oldest pixel gets popped first
//
// My notes: this is basically a shift register that's exactly one row
// (Image_Width pixels) long. Every time a new pixel comes in, everything
// shifts down by one slot, and whatever falls off the end (the pixel that
// entered Image_Width cycles ago) is what comes out as delayed_pixel.
// That's how we get a "delay by one whole row" effect without needing a
// real addressed memory / read-write pointer FIFO.

module Line_Buffer #(parameter Image_Width=32) 
(input clk,valid_in,input [7:0] pixel_in,output [7:0] delayed_pixel );

// one register per pixel position in a row -- Image_Width deep
reg [7:0] buffer [0:Image_Width-1];
integer i;   // loop counter for the shifting for-loop below
always@(posedge clk) begin
    if (valid_in) begin
        buffer[0] <= pixel_in;   // new pixel walks in at the front

        // Shifitng Logic
        // everybody else just moves down one slot (buffer[i] -> buffer[i+1])
        for(i=0;i< Image_Width-1;i=i+1) begin
            buffer[i+1] <= buffer[i];
        end
    end        
end

// the oldest pixel pops out
// this is just always reading the very last slot in the shift register,
// i.e. the pixel that has been sitting in here the longest
assign delayed_pixel = buffer[Image_Width-1];

endmodule
