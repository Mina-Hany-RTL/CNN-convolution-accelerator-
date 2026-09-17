// ============================================================================
// parallel_multipliers.v
// Does all 9 pixel x kernel multiplications for one 3x3 window AT THE SAME
// TIME (in parallel), instead of looping one multiplier 9 times. Costs us
// 9 DSP blocks instead of 1, but means we can accept a brand new window
// every single clock cycle -- that's the whole point of our throughput=1
// design goal. Each of the 9 copies below is basically an identical
// 4-stage pipelined multiplier, just wired to a different pixel/weight pair.
// ============================================================================
module parallel_multipliers (
    input  wire clk,
    input  wire signed [71:0] kernel,          // 9 packed signed 8-bit weights
    input  wire [71:0] image_pixels,           // 9 packed unsigned 8-bit pixels
    output reg  signed [143:0] multiplier_out  // 9 packed signed 16-bit products
);
    
    genvar i;
    // generate loop = "stamp out" 9 identical copies of this multiplier
    // hardware block, one per pixel/weight pair (i = 0..8)
    generate
        for(i = 0; i < 9; i = i + 1) begin : dsp_gen
            // Pipeline registers to allow Vivado to infer AREG, BREG, MREG, PREG
            // (these specific register names/stages match what a Xilinx
            // DSP48E1 slice expects internally, so Vivado can map this
            // straight onto real DSP hardware instead of burning LUTs)
            reg signed [17:0] a_reg;   // registered kernel weight (sign-extended)
            reg signed [24:0] b_reg;   // registered pixel value (zero-extended)
            
            // Force Vivado to use a DSP block for this register's logic
            (* use_dsp = "yes" *) reg signed [42:0] mult_reg;
            
            reg signed [42:0] p_reg;   // extra pipeline register after the multiply
            
            always @(posedge clk) begin
                // Cycle 1: Input registers (infers AREG, BREG)
                // sign-extend the 8-bit signed kernel weight up to 18 bits
                a_reg <= $signed({{10{kernel[i*8 + 7]}}, kernel[i*8 +: 8]});
                // zero-extend the 8-bit UNSIGNED pixel up to 25 bits (pixels
                // are 0-255, never negative, so zero-extend not sign-extend)
                b_reg <= $signed({17'b0, image_pixels[i*8 +: 8]});
                
                // Cycle 2: Multiplication (infers MREG)
                // this is the actual multiply -- weight * pixel
                mult_reg <= a_reg * b_reg;
                
                // Cycle 3: Pipeline register (infers PREG)
                // just passing the product along another pipeline stage
                p_reg <= mult_reg;
                
                // Cycle 4: Output register
                // we only ever actually need the low 16 bits since we
                // already proved the product always fits in signed 16-bit
                // (see the bit-width analysis in the report)
                multiplier_out[i*16 +: 16] <= p_reg[15:0];
            end
        end
    endgenerate
    
endmodule
