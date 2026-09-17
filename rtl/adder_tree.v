// ============================================================================
// adder_tree.v
// Takes the 9 products from parallel_multipliers and sums them all up into
// one final MAC_out value. Instead of just chaining 9 additions in a row
// (which would make ONE really long combinational path and hurt our clock
// speed), we add them in a balanced "tree" shape over 4 pipeline stages.
// Basically: pair up numbers, add pairs, pair up THOSE results, add again,
// repeat until only one number is left. Classic tree-adder trick for timing.
// ============================================================================
module adder_tree (
    input clk,
    input signed [143:0] multiplier_out,   // 9 packed signed 16-bit products
    output reg signed [19:0] MAC_out       // final signed 20-bit sum
);

    // Pipeline stage registers with proper bit-growth
    // every time we add two numbers, the result needs one extra bit to
    // avoid overflow, so the widths grow: 16 -> 17 -> 18 -> 19 -> 20
    reg signed [16:0] add_stg1 [0:4];   // stage 1: 5 partial results (4 sums + 1 forwarded)
    reg signed [17:0] add_stg2 [0:2];   // stage 2: 3 partial results
    reg signed [18:0] add_stg3 [0:1];   // stage 3: 2 partial results

    always @(posedge clk) begin
        // Stage 1: Sign-extend 16-bit multiplier outputs to 17 bits BEFORE adding
        // we have 9 products total, so we pair up 8 of them (4 pairs) and
        // just "forward" the 9th one alone to the next stage (add_stg1[4])
        add_stg1[0] <= $signed({multiplier_out[15],  multiplier_out[15:0]})   + $signed({multiplier_out[31],  multiplier_out[31:16]});
        add_stg1[1] <= $signed({multiplier_out[47],  multiplier_out[47:32]})  + $signed({multiplier_out[63],  multiplier_out[63:48]});
        add_stg1[2] <= $signed({multiplier_out[79],  multiplier_out[79:64]})  + $signed({multiplier_out[95],  multiplier_out[95:80]});
        add_stg1[3] <= $signed({multiplier_out[111], multiplier_out[111:96]}) + $signed({multiplier_out[127], multiplier_out[127:112]});
        add_stg1[4] <= $signed({multiplier_out[143], multiplier_out[143:128]}); // Forwarded

        // Stage 2: Sign-extend 17-bit stage 1 sums to 18 bits BEFORE adding
        // now we have 5 partial sums left, pair up 4 of them (2 pairs) and
        // forward the leftover one (add_stg1[4]) again
        add_stg2[0] <= $signed({add_stg1[0][16], add_stg1[0]}) + $signed({add_stg1[1][16], add_stg1[1]});
        add_stg2[1] <= $signed({add_stg1[2][16], add_stg1[2]}) + $signed({add_stg1[3][16], add_stg1[3]});
        add_stg2[2] <= $signed({add_stg1[4][16], add_stg1[4]}); // Forwarded

        // Stage 3: Sign-extend 18-bit stage 2 sums to 19 bits BEFORE adding
        // 3 values left -> add 2 of them together, forward the last one
        add_stg3[0] <= $signed({add_stg2[0][17], add_stg2[0]}) + $signed({add_stg2[1][17], add_stg2[1]});
        add_stg3[1] <= $signed({add_stg2[2][17], add_stg2[2]}); // Forwarded

        // Stage 4: Final MAC output accumulation (20 bits)
        // last 2 values left, add them together and that's our final
        // convolution result for this window!
        MAC_out     <= $signed({add_stg3[0][18], add_stg3[0]}) + $signed({add_stg3[1][18], add_stg3[1]});
    end

endmodule      
