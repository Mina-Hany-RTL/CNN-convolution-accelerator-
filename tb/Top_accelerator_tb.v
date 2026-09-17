// ============================================================================
// Top_accelerator_tb.v
// Testbench for the whole accelerator. Basically this just instantiates
// our design (uut = "unit under test"), generates a clock, then runs 9
// different test cases from our golden-model package one after another,
// comparing every output pixel against the expected value read from a
// file. If literally anything mismatches, we stop the sim right there so
// we can go look at the waveform and figure out what went wrong.
// ============================================================================
`timescale 1ns/1ps

module Top_accelerator_tb;
    // keep these matching the DUT parameters so everything lines up
    parameter IMAGE_WIDTH  = 32;
    parameter IMAGE_HEIGHT = 32;
    parameter TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;              // 1024 input pixels per test
    parameter TOTAL_OUT_PIXELS = (IMAGE_WIDTH - 2) * (IMAGE_HEIGHT - 2); // 900 valid outputs (no padding, 3x3 kernel)

    // testbench-driven signals (these are "reg" because we assign them
    // from inside initial/always blocks)
    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] pixel_in;
    reg pixel_valid;
    reg signed [71:0] kernel;

    // signals coming FROM the DUT, so these are just wires
    wire busy;
    wire done;
    wire pixel_ready;
    wire [15:0] pixel_out;
    wire pixel_out_valid;

    // instantiate our accelerator -- this "uut" is literally the chip
    // we're testing
    Top_accelerator #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .kernel(kernel),
        .pixel_out(pixel_out),
        .pixel_out_valid(pixel_out_valid)
    );

    // simple free-running clock generator: toggles every 5ns -> 10ns
    // period -> 100MHz simulation clock (doesn't need to match the real
    // implementation Fmax, this is just for functional simulation)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Global error counter
    // this adds up across ALL 9 tests, so at the very end we know if
    // literally everything passed or not
    integer total_errors = 0;

    // Task to run a single test vector directory
    // this task does the heavy lifting: opens the 3 files for one test
    // case (input image, kernel, expected output), streams the image in,
    // and checks every output pixel as it comes out.
    task run_test;
        input [1024:1] test_dir_name; // Large string buffer for the directory path
        
        integer file_in, file_kernel, file_expected, r;
        integer pixel_count, out_count, local_errors;
        reg [1024:1] filename;
        reg [15:0] expected_val;

        begin
            local_errors = 0;
            pixel_count = 0;
            out_count = 0;

            // Dynamically construct file paths based on the provided directory
            // (just string-building the 3 file paths we need for this test)
            $sformat(filename, "%0s/input_image.txt", test_dir_name);
            file_in = $fopen(filename, "r");
            
            $sformat(filename, "%0s/kernel.txt", test_dir_name);
            file_kernel = $fopen(filename, "r");
            
            $sformat(filename, "%0s/expected_output.txt", test_dir_name);
            file_expected = $fopen(filename, "r");

            if (!file_in || !file_kernel || !file_expected) begin
                // sanity check -- if we can't even open the files, don't
                // bother trying to run the test, just complain and bail
                $display("ERROR: Could not open files in %0s", test_dir_name);
            end else begin
                $display("Running test: %0s", test_dir_name);
                
              // Read 9 signed decimal kernel weights robustly
              // (do this once up front, before streaming pixels, since the
              // kernel input to the DUT stays constant for the whole frame)
                begin : kernel_read_block
                    integer k_idx;
                    reg signed [7:0] single_weight;
                    
                    kernel = 72'd0;
                    for (k_idx = 0; k_idx < 9; k_idx = k_idx + 1) begin
                        // Using %d without an explicit \n lets Verilog handle any whitespace/newlines automatically
                        r = $fscanf(file_kernel, "%d", single_weight);
                        
                        // pack each weight into its 8-bit slot of the 72-bit
                        // kernel bus, matching the order the RTL expects
                        case (k_idx)
                            0: kernel[71:64] = single_weight;
                            1: kernel[63:56] = single_weight;
                            2: kernel[55:48] = single_weight;
                            3: kernel[47:40] = single_weight;
                            4: kernel[39:32] = single_weight;
                            5: kernel[31:24] = single_weight;
                            6: kernel[23:16] = single_weight;
                            7: kernel[15:8]  = single_weight;
                            8: kernel[7:0]   = single_weight;
                        endcase
                    end
                end

                rst_n = 0; start = 0; pixel_in = 0; pixel_valid = 0; //Reset sequence
                #20 rst_n = 1; #10;
                
                // Trigger FSM
                // pulse start for exactly one cycle to kick things off
                start = 1; #10 start = 0;

                // Fork concurrent threads to handle input feeding and output checking simultaneously
                // (we need BOTH happening at once since outputs start
                // coming out while we're still feeding later input pixels,
                // thanks to the pipeline)
                fork
                    // Thread 1: Feed input stream
                    // keeps pushing pixels in as long as the DUT says
                    // pixel_ready, using the standard valid/ready handshake
                    begin
                        while (pixel_count < TOTAL_PIXELS) begin
                            if (pixel_ready) begin
                                pixel_valid = 1;
                                r = $fscanf(file_in, "%d\n", pixel_in);
                                pixel_count = pixel_count + 1;
                            end else begin
                                pixel_valid = 0;
                            end
                            @(posedge clk);
                        end
                        pixel_valid = 0; // Deassert when done
                    end

                   // Thread 2: Monitor and verify output stream
                   // every time pixel_out_valid goes high, grab the next
                   // expected value from file and compare -- this is the
                   // actual pass/fail check of the whole testbench
                    begin
                        while (out_count < TOTAL_OUT_PIXELS) begin 
                            @(posedge clk);
                            if (pixel_out_valid) begin
                                r = $fscanf(file_expected, "%d\n", expected_val);
                                if (pixel_out !== expected_val) begin
                                    // uh oh, mismatch -- print what we got vs
                                    // what we expected and stop immediately so
                                    // we can inspect the waveform right here
                                    $display("  MISMATCH at pixel %d: Expected %h, Got %h", out_count, expected_val, pixel_out);
                                    local_errors = local_errors + 1;
                                    $stop;
                                end
                                out_count = out_count + 1;
                            end
                        end
                    end
                join

                // Wait for FSM to assert done flag
                // (make sure the DUT itself agrees the frame is fully finished
                // before we move on to the next test case)
                wait(done);
                @(posedge clk); 
                
                $display("Completed %0s with %0d errors.\n", test_dir_name, local_errors);
                total_errors = total_errors + local_errors;

                $fclose(file_in);
                $fclose(file_kernel);
                $fclose(file_expected);
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        // Sequentially execute all 9 test vectors provided in the golden model package
        // each of these exercises a different scenario (zero image, all
        // ones, ramp pattern, sobel edge kernel, random data, saturation
        // corner cases, etc.) -- see the report for what each one checks
        run_test("cnn_golden_model_package_v2/golden_vectors/01_zero_image_identity");
        run_test("cnn_golden_model_package_v2/golden_vectors/02_one_image_all_ones_kernel");
        run_test("cnn_golden_model_package_v2/golden_vectors/03_increasing_image_identity");
        run_test("cnn_golden_model_package_v2/golden_vectors/04_pattern_image_sobel_x");
        run_test("cnn_golden_model_package_v2/golden_vectors/05_random_image_random_kernel");
        run_test("cnn_golden_model_package_v2/golden_vectors/06_max255_image_identity");
        run_test("cnn_golden_model_package_v2/golden_vectors/07_max255_positive_saturation");
        run_test("cnn_golden_model_package_v2/golden_vectors/08_max255_negative_relu");
        run_test("cnn_golden_model_package_v2/golden_vectors/09_top_packing_order_probe");

        // final summary -- nice and easy to spot in the transcript log
        $display("========================================");
        if (total_errors == 0)
            $display("ALL 9 TESTS PASSED SUCCESSFULLY!");
        else
            $display("SIMULATION FAILED WITH %0d TOTAL ERRORS.", total_errors);
        $display("========================================");
        
        $stop;
    end

endmodule
