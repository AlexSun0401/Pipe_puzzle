`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// vga_monitor.v -- a VGA "monitor" for simulation.
//
// Watches the DAC-side signals of the DE1-SoC VGA port, measures the sync
// timing, checks it against the 640x480@60 numbers below and captures every
// frame into `frame` as 9-bit colour {R[7:5], G[7:5], B[7:5]}.
//
// Timing reference (pixel clocks / lines):
//   horizontal  640 active, 800 total, sync pulse 96, active low
//   vertical    480 active, 525 total, sync pulse 2,  active low
// The porches are measured and reported, not checked: the adapter supplied
// with the course uses 19/45 instead of the textbook 16/48.
//
// Use: call resync after a reset of the design, then wait for `frame_done`.
// `frame_start` is the simulation time at which the first pixel of the frame
// that just completed was displayed.
// -----------------------------------------------------------------------------
module vga_monitor (
    input wire       VGA_CLK,
    input wire       VGA_HS,
    input wire       VGA_VS,
    input wire       VGA_BLANK_N,
    input wire [7:0] VGA_R,
    input wire [7:0] VGA_G,
    input wire [7:0] VGA_B
);
    parameter H_ACTIVE = 640, H_TOTAL = 800, H_SYNC = 96;
    parameter V_ACTIVE = 480, V_TOTAL = 525, V_SYNC = 2;

    reg [8:0] frame [0:H_ACTIVE*V_ACTIVE-1];
    integer   frames = 0;               // complete frames captured
    integer   errors = 0;
    time      frame_start = 0;
    event     frame_done;

    // last measurements
    integer meas_h_total = 0, meas_h_sync = 0, meas_h_active = 0, meas_h_front = 0;
    integer meas_v_total = 0, meas_v_sync = 0, meas_v_active = 0, meas_v_front = 0;

    reg     h_locked = 1'b0, v_locked = 1'b0;
    reg     prev_hs = 1'b1, prev_vs = 1'b1, prev_blank_n = 1'b0;
    integer h_count = 0;                // pixel clocks since the last HS falling edge
    integer hs_low  = 0;                // pixel clocks with HS low
    integer since_active = 0;           // pixel clocks since the end of the active line
    integer x = 0, y = 0;               // position of the next active pixel
    integer lines = 0;                  // HS pulses since the last VS falling edge
    integer vs_lines = 0;               // HS pulses with VS low
    integer lines_since_active = 0;
    time    next_frame_start = 0;

    task resync;
        begin
            h_locked = 1'b0; v_locked = 1'b0;
            // start from the present levels, so that a sync pulse that is already
            // in progress is not mistaken for the start of one
            prev_hs = VGA_HS; prev_vs = VGA_VS; prev_blank_n = 1'b0;
            h_count = 0; hs_low = 0; x = 0; y = 0; lines = 0; vs_lines = 0;
        end
    endtask

    task report(input [8*80-1:0] what, input integer got, input integer expected);
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("[%0t] ERROR (vga_monitor): %0s: got %0d, expected %0d", $time, what, got, expected);
        end
    endtask

    always @(posedge VGA_CLK) begin
        h_count = h_count + 1;
        if (!VGA_HS) hs_low = hs_low + 1;
        since_active = since_active + 1;

        // ---- active video
        if (VGA_BLANK_N === 1'b1) begin
            if (x == 0 && y == 0) next_frame_start = $time;
            if (x < H_ACTIVE && y < V_ACTIVE) begin
                frame[y*H_ACTIVE + x] = {VGA_R[7:5], VGA_G[7:5], VGA_B[7:5]};
                // each 3-bit colour is repeated to fill the 8-bit DAC input
                if (VGA_R !== {VGA_R[7:5], VGA_R[7:5], 2'b00} ||
                    VGA_G !== {VGA_G[7:5], VGA_G[7:5], 2'b00} ||
                    VGA_B !== {VGA_B[7:5], VGA_B[7:5], 2'b00})
                    report("DAC bits are not the 3-bit colour repeated", {VGA_R, VGA_G, VGA_B}, 0);
            end
            x = x + 1;
        end else if (prev_blank_n === 1'b1) begin
            // end of an active line
            meas_h_active = x;
            if (v_locked && x != H_ACTIVE) report("active pixels in a line", x, H_ACTIVE);
            x = 0;
            y = y + 1;
            since_active = 0;
            lines_since_active = 0;
        end

        // ---- horizontal sync
        if (prev_hs === 1'b1 && VGA_HS === 1'b0) begin
            if (h_locked) begin
                meas_h_total = h_count;
                if (h_count != H_TOTAL) report("pixel clocks per line", h_count, H_TOTAL);
            end
            if (since_active < H_TOTAL) meas_h_front = since_active;
            h_locked = 1'b1;
            h_count  = 0;
            hs_low   = 1;
            lines    = lines + 1;
            lines_since_active = lines_since_active + 1;
            if (!VGA_VS) vs_lines = vs_lines + 1;
        end
        if (prev_hs === 1'b0 && VGA_HS === 1'b1 && h_locked) begin
            meas_h_sync = hs_low;
            if (hs_low != H_SYNC) report("HSYNC pulse width", hs_low, H_SYNC);
        end

        // ---- vertical sync
        if (prev_vs === 1'b1 && VGA_VS === 1'b0) begin
            if (v_locked) begin
                meas_v_total  = lines;
                meas_v_active = y;
                meas_v_front  = lines_since_active - 1;   // do not count the last active line itself
                if (lines != V_TOTAL) report("lines per frame", lines, V_TOTAL);
                if (y != V_ACTIVE)    report("active lines per frame", y, V_ACTIVE);
                frames      = frames + 1;
                frame_start = next_frame_start;
                -> frame_done;
            end
            v_locked = 1'b1;
            lines    = 0;
            vs_lines = 0;
            y        = 0;
            x        = 0;
        end
        if (prev_vs === 1'b0 && VGA_VS === 1'b1 && v_locked) begin
            meas_v_sync = vs_lines;
            if (vs_lines != V_SYNC) report("VSYNC pulse width in lines", vs_lines, V_SYNC);
        end

        prev_hs      = VGA_HS;
        prev_vs      = VGA_VS;
        prev_blank_n = VGA_BLANK_N;
    end
endmodule
