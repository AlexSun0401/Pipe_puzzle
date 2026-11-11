`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_ps2_driver.v -- unit testbench for rtl/input/ps2_driver.v
//
// A PS/2 keyboard model (models/ps2_keyboard_bfm.v) sends real 11-bit frames on
// open-drain lines. The bench predicts the cursor position and the number of
// rotate / reset / frame-received pulses, and monitors pulse widths.
//
//   1. reset state           outputs after KEY[0]
//   2. cursor                W A S D, all 16 tiles, saturation at the four edges
//   3. rotate and reset      Space and R give exactly one single-cycle pulse
//   4. key release           F0 <code> is ignored for every key
//   5. typematic             a held key repeats its make code
//   6. every scan code       all 256 make codes: only six of them act
//   7. extended keys         E0-prefixed arrows do nothing
//   8. reset_position        returns the cursor to tile (0,0)
//   9. KEY[0]                clears the cursor and re-aligns a half-received frame
//  10. timing                10 kHz .. 16.7 kHz PS/2 clock, every clock phase
//  11. line errors           bad parity, bad stop bit, spurious clock edge
//                            (documented limitations, see tb/README.md)
// -----------------------------------------------------------------------------
module tb_ps2_driver;

    localparam TB_NAME       = "tb_ps2_driver";
    localparam TB_TIMEOUT_NS = 400_000_000;
    localparam CLK_PERIOD    = 20;

    localparam FAST_HALF_PERIOD_NS = 203;       // accelerated PS/2 clock, not a multiple of 20 ns
    localparam LATENCY_CYCLES      = 6;         // decode must be visible this soon after the stop bit

    reg        clk            = 1'b0;
    reg        key0           = 1'b1;           // active-low reset push button
    reg        reset_position = 1'b0;
    wire       PS2_CLK, PS2_DAT;
    wire [1:0] out_x, out_y;
    wire       out_reset, out_rotate, ps2_rec;

    always #(CLK_PERIOD/2) clk = ~clk;

    pullup (PS2_CLK);
    pullup (PS2_DAT);

    ps2_keyboard_bfm kbd (PS2_CLK, PS2_DAT);

    ps2_driver dut (clk, key0, PS2_CLK, PS2_DAT, out_x, out_y, out_reset, out_rotate,
                    ps2_rec, reset_position);

    `include "tb_util.vh"

    reg [8*120-1:0] msg;
    integer cov_pos, cov_edge, cov_make, cov_break, cov_unmapped, cov_rate, cov_phase;

    // ------------------------------------------------------------- monitors
    integer rot_count = 0, rst_count = 0, rec_count = 0;
    reg     prev_rot = 1'b0, prev_rst = 1'b0, prev_rec = 1'b0;

    always @(negedge clk) begin
        // pulses are counted on their first cycle and must not last a second one
        if (out_rotate === 1'b1) begin
            if (prev_rot) tb_fail("OUT_Rotate stayed high for more than one clock");
            else rot_count = rot_count + 1;
        end
        if (out_reset === 1'b0) begin
            if (prev_rst) tb_fail("OUT_Reset stayed low for more than one clock");
            else rst_count = rst_count + 1;
        end
        if (ps2_rec === 1'b1) begin
            if (prev_rec) tb_fail("ps2_rec stayed high for more than one clock");
            else rec_count = rec_count + 1;
        end
        prev_rot = (out_rotate === 1'b1);
        prev_rst = (out_reset  === 1'b0);
        prev_rec = (ps2_rec    === 1'b1);
    end

    // The host side never drives the bus: a released line must read high.
    // Sampled half a nanosecond off the grid on which the keyboard model moves.
    always @(negedge clk) begin
        #0.5;
        if (!kbd.clk_low && PS2_CLK !== 1'b1) tb_fail("PS2_CLK is driven while the keyboard released it");
        if (!kbd.dat_low && PS2_DAT !== 1'b1) tb_fail("PS2_DAT is driven while the keyboard released it");
    end

    // ------------------------------------------------------- expected state
    integer exp_x = 0, exp_y = 0, exp_rot = 0, exp_rst = 0, exp_rec = 0;

    // Effect of one make code on the expected state.
    task predict_make(input [7:0] code);
        begin
            case (code)
                kbd.KEY_W:     if (exp_y > 0) exp_y = exp_y - 1; else tb_cov_hit(cov_edge + 0);
                kbd.KEY_S:     if (exp_y < 3) exp_y = exp_y + 1; else tb_cov_hit(cov_edge + 1);
                kbd.KEY_A:     if (exp_x > 0) exp_x = exp_x - 1; else tb_cov_hit(cov_edge + 2);
                kbd.KEY_D:     if (exp_x < 3) exp_x = exp_x + 1; else tb_cov_hit(cov_edge + 3);
                kbd.KEY_SPACE: exp_rot = exp_rot + 1;
                kbd.KEY_R:     exp_rst = exp_rst + 1;
                default:       tb_cov_hit(cov_unmapped);
            endcase
        end
    endtask

    function integer key_index(input [7:0] code);
        begin
            case (code)
                kbd.KEY_W:     key_index = 0;
                kbd.KEY_A:     key_index = 1;
                kbd.KEY_S:     key_index = 2;
                kbd.KEY_D:     key_index = 3;
                kbd.KEY_SPACE: key_index = 4;
                kbd.KEY_R:     key_index = 5;
                default:       key_index = -1;
            endcase
        end
    endfunction

    task check_now(input [8*60-1:0] what);
        begin
            if (out_x === exp_x[1:0] && out_y === exp_y[1:0] && out_reset === 1'b1 &&
                out_rotate === 1'b0 && rot_count == exp_rot && rst_count == exp_rst &&
                rec_count == exp_rec) begin
                tb_checks = tb_checks + 7;
            end else begin
                $sformat(msg, "%0s: OUT_X", what);               tb_check_eq(out_x, exp_x, msg);
                $sformat(msg, "%0s: OUT_Y", what);               tb_check_eq(out_y, exp_y, msg);
                $sformat(msg, "%0s: OUT_Reset idles high", what); tb_check_eq(out_reset, 1'b1, msg);
                $sformat(msg, "%0s: OUT_Rotate idles low", what); tb_check_eq(out_rotate, 1'b0, msg);
                $sformat(msg, "%0s: rotate pulses", what);       tb_check_eq(rot_count, exp_rot, msg);
                $sformat(msg, "%0s: reset pulses", what);        tb_check_eq(rst_count, exp_rst, msg);
                $sformat(msg, "%0s: frames received", what);     tb_check_eq(rec_count, exp_rec, msg);
            end
            tb_cov_hit(cov_pos + 4*exp_y + exp_x);
        end
    endtask

    // The decode of a frame must be visible within LATENCY_CYCLES of its end.
    // The model has already idled for one PS/2 bit time when a send returns.
    task settle;
        begin
            repeat (LATENCY_CYCLES) @(posedge clk);
            #1;
        end
    endtask

    task press(input [7:0] code);               // key goes down
        begin
            kbd.key_make(code);
            predict_make(code);
            exp_rec = exp_rec + 1;
            if (key_index(code) >= 0) tb_cov_hit(cov_make + key_index(code));
            settle;
            $sformat(msg, "make %h", code);
            check_now(msg);
        end
    endtask

    task release_key(input [7:0] code);         // key goes up: F0 <code>, no effect
        begin
            kbd.key_break(code);
            exp_rec = exp_rec + 2;
            if (key_index(code) >= 0) tb_cov_hit(cov_break + key_index(code));
            settle;
            $sformat(msg, "break %h", code);
            check_now(msg);
        end
    endtask

    task tap(input [7:0] code);
        begin
            press(code);
            release_key(code);
        end
    endtask

    task apply_key0_reset;
        begin
            @(negedge clk);
            key0 = 1'b0;
            repeat (4) @(negedge clk);
            // synchronous reset: outputs are in their reset state while KEY[0] is low
            tb_check_eq({out_x, out_y, out_reset, out_rotate}, 6'b00_00_1_0, "outputs while KEY[0] is held");
            key0 = 1'b1;
            exp_x = 0; exp_y = 0;
            repeat (4) @(negedge clk);
        end
    endtask

    // ================================================================ tests
    task test_reset_state;
        begin
            tb_case_begin("reset state");
            apply_key0_reset;
            check_now("after reset");
            tb_check((^{dut.Packet_Count, dut.ps2_shift_reg, dut.break_received, dut.prev_ps2_clk}) !== 1'bx,
                     "no receiver register is X after reset");
            tb_check_eq(ps2_rec, 1'b0, "ps2_rec idle after reset");
        end
    endtask

    task test_cursor;
        integer n, row;
        begin
            tb_case_begin("cursor: saturation at the edges");
            for (n = 0; n < 5; n = n + 1) tap(kbd.KEY_D);        // 3 moves, then blocked
            tb_check_eq(out_x, 2'd3, "D stops at the right edge");
            for (n = 0; n < 5; n = n + 1) tap(kbd.KEY_S);
            tb_check_eq(out_y, 2'd3, "S stops at the bottom edge");
            for (n = 0; n < 5; n = n + 1) tap(kbd.KEY_A);
            tb_check_eq(out_x, 2'd0, "A stops at the left edge");
            for (n = 0; n < 5; n = n + 1) tap(kbd.KEY_W);
            tb_check_eq(out_y, 2'd0, "W stops at the top edge");

            tb_case_begin("cursor: visit all 16 tiles");
            for (row = 0; row < 4; row = row + 1) begin
                for (n = 0; n < 3; n = n + 1) tap(row[0] ? kbd.KEY_A : kbd.KEY_D);
                if (row < 3) tap(kbd.KEY_S);
            end
            tb_check_eq({out_x, out_y}, 4'b00_11, "snake walk ends at the bottom-left tile");
            for (n = 0; n < 3; n = n + 1) tap(kbd.KEY_W);
        end
    endtask

    task test_rotate_and_reset;
        integer n;
        begin
            tb_case_begin("Space rotates, R resets");
            tap(kbd.KEY_D); tap(kbd.KEY_S);                      // pulses must not move the cursor
            for (n = 0; n < 4; n = n + 1) tap(kbd.KEY_SPACE);
            for (n = 0; n < 3; n = n + 1) tap(kbd.KEY_R);
            tb_check_eq({out_x, out_y}, 4'b01_01, "cursor unchanged by Space and R");
            tb_check_eq(rot_count, 4, "four Space taps give four rotate pulses");
            tb_check_eq(rst_count, 3, "three R taps give three reset pulses");
        end
    endtask

    task test_typematic;
        integer n;
        begin
            tb_case_begin("held key repeats (typematic)");
            for (n = 0; n < 6; n = n + 1) press(kbd.KEY_SPACE);  // make, make, make ...
            release_key(kbd.KEY_SPACE);
            for (n = 0; n < 3; n = n + 1) press(kbd.KEY_D);
            release_key(kbd.KEY_D);
            // two keys held at once: releases arrive in any order
            press(kbd.KEY_A); press(kbd.KEY_W);
            release_key(kbd.KEY_A); release_key(kbd.KEY_W);
        end
    endtask

    task test_all_scan_codes;
        integer code, x0, y0;
        begin
            tb_case_begin("all 256 scan codes");
            tap(kbd.KEY_D); tap(kbd.KEY_S);                      // away from the edges, if possible
            for (code = 0; code < 256; code = code + 1)
                if (code != kbd.CODE_BREAK) begin
                    x0 = exp_x; y0 = exp_y;
                    press(code);
                    // step back after a move, so that no key is hidden by an edge
                    if (exp_x > x0) press(kbd.KEY_A);
                    if (exp_x < x0) press(kbd.KEY_D);
                    if (exp_y > y0) press(kbd.KEY_W);
                    if (exp_y < y0) press(kbd.KEY_S);
                end
            // a release prefix swallows exactly one byte, whatever that byte is
            for (code = 0; code < 256; code = code + 1)
                if (code != kbd.CODE_BREAK) begin
                    kbd.key_break(code);
                    exp_rec = exp_rec + 2;
                end
            settle;
            check_now("release of every code");
            press(kbd.KEY_SPACE);                                // decoder still in step
        end
    endtask

    task test_extended_keys;
        begin
            tb_case_begin("extended keys are ignored");
            kbd.key_tap_extended(8'h75);                         // arrow up
            kbd.key_tap_extended(8'h72);                         // arrow down
            kbd.key_tap_extended(8'h6B);                         // arrow left
            kbd.key_tap_extended(8'h74);                         // arrow right
            exp_rec = exp_rec + 20;
            settle;
            check_now("after the four arrow keys");
        end
    endtask

    task test_reset_position;
        begin
            tb_case_begin("reset_position");
            tap(kbd.KEY_D); tap(kbd.KEY_S); tap(kbd.KEY_S);
            tb_check(out_x != 2'd0 && out_y != 2'd0, "cursor away from tile (0,0) before reset_position");
            @(negedge clk); reset_position = 1'b1;
            @(negedge clk); reset_position = 1'b0;
            exp_x = 0; exp_y = 0;
            #1;
            check_now("after reset_position");
            tap(kbd.KEY_D); tap(kbd.KEY_SPACE);                  // keys work again right away
        end
    endtask

    task test_key0;
        begin
            tb_case_begin("KEY[0] reset");
            tap(kbd.KEY_S); tap(kbd.KEY_D);
            apply_key0_reset;
            check_now("after KEY[0]");

            tb_case_begin("KEY[0] re-aligns a half-received frame");
            kbd.send_raw({1'b1, 1'b1, kbd.KEY_D, 1'b0}, 6);      // transmission cut after 6 bits
            apply_key0_reset;
            tap(kbd.KEY_D);                                      // must decode as a whole frame
            tap(kbd.KEY_SPACE);
        end
    endtask

    task test_timing;
        integer   phase, latency;
        reg [1:0] x_start;
        begin
            tb_case_begin("PS/2 clock 10 kHz");
            kbd.set_half_period(50_000);
            tap(kbd.KEY_D); tap(kbd.KEY_SPACE);
            tb_cov_hit(cov_rate + 0);
            tb_case_begin("PS/2 clock 12.5 kHz");
            kbd.set_half_period(40_000);
            tap(kbd.KEY_S); tap(kbd.KEY_R);
            tb_cov_hit(cov_rate + 1);
            tb_case_begin("PS/2 clock 16.7 kHz");
            kbd.set_half_period(30_000);
            tap(kbd.KEY_A); tap(kbd.KEY_SPACE);
            tb_cov_hit(cov_rate + 2);

            tb_case_begin("decode latency");
            kbd.set_half_period(FAST_HALF_PERIOD_NS);
            tap(kbd.KEY_A); tap(kbd.KEY_A); tap(kbd.KEY_A);      // room to move right
            for (phase = 0; phase < 4; phase = phase + 1) begin
                if (phase == 3) begin tap(kbd.KEY_A); tap(kbd.KEY_A); tap(kbd.KEY_A); end
                x_start = out_x;
                fork
                    kbd.key_make(kbd.KEY_D);
                    begin
                        repeat (11) @(negedge PS2_CLK);          // the stop bit is clocked in here
                        latency = 0;
                        while (out_x === x_start && latency < 100) begin
                            @(posedge clk); #1;
                            latency = latency + 1;
                        end
                    end
                join
                predict_make(kbd.KEY_D);
                exp_rec = exp_rec + 1;
                $sformat(msg, "cursor moved %0d clocks after the stop bit (limit %0d)", latency, LATENCY_CYCLES);
                tb_check(latency <= LATENCY_CYCLES, msg);
                settle;
                check_now("after latency measurement");
            end
            $display("    decode latency: %0d CLOCK_50 cycles after the last PS/2 clock edge", latency);

            tb_case_begin("every phase between PS/2 clock and CLOCK_50");
            kbd.set_half_period(200);                            // an exact multiple of the clock
            for (phase = 0; phase < CLK_PERIOD; phase = phase + 1) begin
                @(posedge clk); #(phase);
                press(kbd.KEY_SPACE);
                tb_cov_hit(cov_phase + phase);
            end
            kbd.set_half_period(FAST_HALF_PERIOD_NS);
        end
    endtask

    task test_line_errors;
        integer x_before;
        begin
            tb_case_begin("line errors (documented limitations)");
            tap(kbd.KEY_A); tap(kbd.KEY_A); tap(kbd.KEY_A);      // left edge, so a move right shows
            // A frame with wrong parity should be dropped; the design has no parity check.
            x_before = out_x;
            kbd.send_byte_with(kbd.KEY_D, ^kbd.KEY_D, 1'b1);     // even parity = wrong
            exp_rec = exp_rec + 1;
            settle;
            tb_known_issue(out_x === x_before[1:0], "KI-3",
                           "a frame with a parity error is accepted and acted on");
            exp_x = out_x;
            // The same for a missing stop bit.
            x_before = out_x;
            kbd.send_byte_with(kbd.KEY_A, ~^kbd.KEY_A, 1'b0);
            exp_rec = exp_rec + 1;
            settle;
            tb_known_issue(out_x === x_before[1:0], "KI-3",
                           "a frame with a framing error (stop bit low) is accepted and acted on");
            exp_x = out_x;
            check_now("after the error frames");

            // One spurious falling edge on the clock line. A receiver with an idle
            // time-out would drop the stray bit; this one stays one bit out of step.
            kbd.clock_glitch;
            repeat (100_000) @(posedge clk);                     // 2 ms of idle line
            x_before = out_x;
            kbd.key_make(kbd.KEY_D);
            settle;
            tb_known_issue(out_x === x_before[1:0] + 2'd1, "KI-4",
                           "after one spurious clock edge the receiver stays out of step");
            // KEY[0] is the documented way out, and it must work.
            apply_key0_reset;
            rot_count = 0; rst_count = 0; rec_count = 0;
            exp_rot   = 0; exp_rst   = 0; exp_rec   = 0;
            tap(kbd.KEY_D); tap(kbd.KEY_S); tap(kbd.KEY_SPACE);
        end
    endtask

    // ================================================================== main
    initial begin
        tb_start;
        tb_cov_group(cov_pos,      "cursor on tile",                16);
        tb_cov_group(cov_edge,     "blocked at top/bottom/left/right", 4);
        tb_cov_group(cov_make,     "make of W A S D Space R",        6);
        tb_cov_group(cov_break,    "break of W A S D Space R",       6);
        tb_cov_group(cov_unmapped, "unmapped scan code",             1);
        tb_cov_group(cov_rate,     "PS/2 clock 10/12.5/16.7 kHz",    3);
        tb_cov_group(cov_phase,    "PS/2 edge at clock phase (ns)", CLK_PERIOD);

        kbd.set_half_period(FAST_HALF_PERIOD_NS);
        test_reset_state;
        test_cursor;
        test_rotate_and_reset;
        test_typematic;
        test_all_scan_codes;
        test_extended_keys;
        test_reset_position;
        test_key0;
        test_timing;
        test_line_errors;
        tb_finish;
    end

endmodule
