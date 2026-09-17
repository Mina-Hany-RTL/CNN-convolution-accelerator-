// ============================================================================
// Control_FSM.v
// This is the "traffic controller" of the whole design. It's a simple
// 3-state state machine (IDLE -> STREAM -> DRAIN -> back to IDLE) that
// keeps track of where we are in the image (row_count/col_count), decides
// when a full 3x3 window is ready, and shifts a "valid" bit down a delay
// line so it lines up with the MAC pipeline latency. This was honestly the
// trickiest module to get right because of all the timing alignment stuff.
// ============================================================================
module Control_FSM #(
    parameter IMAGE_WIDTH  = 32,
    parameter IMAGE_HEIGHT = 32
)(
    input  wire clk,
    input  wire rst_n,

    // Frame control
    input  wire start,   // pulse to begin a new frame

    // Input-stream handshake
    input  wire pixel_valid,
    output wire pixel_ready,
    output wire router_en,   // tells Data_Router "go ahead, shift this pixel in"

    // Window/MAC synchronization
    output reg  window_valid,   // says "the window that's ready THIS cycle is legal"
    output wire mac_out_valid,  // delayed version of window_valid, lined up w/ MAC latency

    // Status
    output wire busy,
    output wire done
);

    // Encoding our 3 states. Only need 2 bits since we only have 3 states.
    localparam ST_IDLE   = 2'b00;
    localparam ST_STREAM = 2'b01;
    localparam ST_DRAIN  = 2'b10;

    reg [1:0] state;

    // 16 bits are more than enough for the required 32x32 image and
    // still allow larger parameterized image dimensions.
    // (32x32 would technically only need 6 bits, but 16 gives us headroom
    // if we ever try bigger images later without touching this file)
    reg [15:0] row_count;
    reg [15:0] col_count;

    // Marks the final valid convolution window.
    // i.e. this is set for the very last legal 3x3 window in the frame, so
    // we know when to eventually assert "done".
    reg last_window;

    // The current Window_Generator is registered.  window_valid is
    // therefore asserted in the cycle AFTER the pixel that completes
    // the corresponding KxK window is accepted.
    // (these 4 wires are just "this cycle" combinational versions, before
    // we register them below -- naming them *_now makes it clear they're
    // NOT registered yet)
    wire accepted_pixel;
    wire window_completed_now;
    wire last_pixel_now;
    wire last_window_now;

    // We only accept new pixels while we're in the STREAM state.
    assign pixel_ready    = (state == ST_STREAM);
    // A pixel is actually "accepted" only when both valid AND ready are high
    // at the same time -- classic handshake rule.
    assign accepted_pixel = pixel_valid && pixel_ready;

    // Drive this directly to Data_Router.valid_in.
    assign router_en = accepted_pixel;

    // A window is complete once we've accepted a pixel AND we're at least
    // 2 rows and 2 cols into the image (since a 3x3 window needs 3 rows/cols
    // of history before the first legal window exists -- rows/cols start
    // at 0, so >= 2 means we've seen 3 rows/cols total: 0,1,2).
    assign window_completed_now =
        accepted_pixel &&
        (row_count >= 2) &&
        (col_count >= 2);

    // This just checks: "was the pixel we JUST accepted literally the very
    // last pixel of the whole image" (bottom-right corner pixel).
    assign last_pixel_now =
        accepted_pixel &&
        (row_count == (IMAGE_HEIGHT - 1)) &&
        (col_count == (IMAGE_WIDTH  - 1));

    // Same idea but combined with window_completed_now, so this fires only
    // if the LAST pixel accepted is ALSO the one that completes the final
    // legal window (should always be true together for our no-padding case).
    assign last_window_now =
        window_completed_now &&
        (row_count == (IMAGE_HEIGHT - 1)) &&
        (col_count == (IMAGE_WIDTH  - 1));

    // We're "busy" any time we're not sitting idle waiting for start.
    assign busy = (state != ST_IDLE);

    // ----------------------------------------------------------------
    // FSM
    // IDLE   : wait for start
    // STREAM : accept image pixels; counters advance only on handshake
    // DRAIN  : stop input and wait for the final MAC result to exit
    // ----------------------------------------------------------------
    // Pretty standard 3-state machine. Note: this only updates the STATE,
    // the counters and valid pipeline are handled in their own always
    // blocks further down (keeps things a bit more readable/separated).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    // just sit here until someone pulses start
                    if (start)
                        state <= ST_STREAM;
                end

                ST_STREAM: begin
                    // keep streaming pixels in until we've accepted the
                    // very last pixel of the frame, then go drain the pipe
                    if (last_pixel_now)
                        state <= ST_DRAIN;
                end

                ST_DRAIN: begin
                    // no more new pixels accepted here, we're just waiting
                    // for the pipelined MAC result of the last window to
                    // finally pop out the other end
                    if (done)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;   // just in case, shouldn't happen
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Input coordinates
    // They advance only when the Data_Router also accepts/shifts a pixel.
    // ----------------------------------------------------------------
    // This is our (row, col) tracker for the CURRENT incoming pixel.
    // Basic row-major counting: col increments every accepted pixel, and
    // wraps around to 0 (bumping row) once we hit the end of a row.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_count <= 16'd0;
            col_count <= 16'd0;
        end
        else if (state == ST_IDLE) begin
            // reset counters every time we go back to idle, so a fresh
            // "start" always begins counting from (0,0) again
            row_count <= 16'd0;
            col_count <= 16'd0;
        end
        else if (accepted_pixel) begin
            if (col_count == (IMAGE_WIDTH - 1)) begin
                // we just accepted the last pixel in this row -> wrap col
                col_count <= 16'd0;

                // don't let row_count overflow past the last valid row
                // (shouldn't really happen since last_pixel_now would have
                // already kicked us into DRAIN, but doesn't hurt to guard)
                if (row_count != (IMAGE_HEIGHT - 1))
                    row_count <= row_count + 16'd1;
            end
            else begin
                // normal case: just move to the next column in this row
                col_count <= col_count + 16'd1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Window-valid generation
    //
    // For a 3x3 kernel with no padding, only pixels with row >= 2 and
    // col >= 2 complete a legal output window.
    //
    // This also suppresses the two horizontally invalid windows created
    // at each row boundary by the shift-register Window_Generator.
    // ----------------------------------------------------------------
    // Just registering the combinational "now" signals from above so they
    // become clean, glitch-free registered outputs.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_valid <= 1'b0;
            last_window  <= 1'b0;
        end
        else begin
            window_valid <= window_completed_now;
            last_window  <= last_window_now;
        end
    end

// ----------------------------------------------------------------
// Valid pipeline aligned with MAC_array.
//
// New MAC_array stages (8 total):
//   1-4) DSP48E1 multiplier pipeline + output register
//   5) adder stage 1
//   6) adder stage 2
//   7) adder stage 3
//   8) final MAC_out register
// ----------------------------------------------------------------
// This part gave me a headache at first -- the whole point is that
// window_valid tells us a window ENTERED the MAC pipeline this cycle, but
// the actual math result doesn't come out until 8 cycles later. So we
// build an 8-stage shift register ("valid_pipe") that just shifts the
// valid bit along every cycle, and by the time it reaches the last stage
// (valid_pipe[7]) it lines up exactly with when MAC_out is finally ready.
// last_pipe does the exact same trick but for the "is this the last
// window of the frame" flag.
    reg [7:0] valid_pipe;
    reg [7:0] last_pipe;
    integer i;   // just a loop variable, nothing fancy

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= {8{1'b0}};
            last_pipe  <= {8{1'b0}};
        end
        else begin
            // new value enters at the front of the pipe...
            valid_pipe[0] <= window_valid;
            last_pipe[0]  <= last_window;

            // ...and everything else just shifts down by one stage
            for (i = 1; i < 8; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                last_pipe[i]  <= last_pipe[i-1];
            end
        end
    end

    // After shifting through all 8 stages, this bit is finally aligned
    // with the real MAC_out coming out of the adder tree.
    assign mac_out_valid = valid_pipe[7];

    // One-cycle pulse, aligned with the last valid MAC output.
    // Only assert done if we're actually in DRAIN, the current output is
    // valid, AND it corresponds to the very last window of the frame.
    assign done = (state == ST_DRAIN) &&
                mac_out_valid &&
                last_pipe[7];

endmodule
