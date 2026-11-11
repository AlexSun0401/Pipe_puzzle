`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_pipe_puzzle_game.v -- system testbench for rtl/pipe_puzzle_game.v
//
// The whole design is driven only through its pins: CLOCK_50, KEY[0] and a
// PS/2 keyboard model. An automatic player solves the three levels with real
// key strokes; the solution of each level is computed by the golden model.
//
// Scenario
//   1. power-up, title screen     title image on the VGA pins, nothing running
//   2. KEY[0] on the title screen does not start the game
//   3. any key                    starts level 1
//   4. keyboard                   cursor on all 16 tiles, rotate, R
//   5. levels 1, 2, 3             solved with W A S D + Space; victory freezes
//                                 the board and the timer; two-second hold,
//                                 then the next level
//   6. game complete              level 3 stays; R still gives a new board
//   7. KEY[0]                     restart from every level, also during the hold
//
// Checked continuously while the scenario runs
//   - board, wet tiles, leaks and victory against the golden pipe model
//   - HEX5..0 against a model of the three level timers, every clock
//   - the video-memory write port against the golden renderer (sampled)
//   - VGA sync timing, by the monitor model
//   - every re-randomisation of the board takes the LFSR value
//
// Speed-ups that do not change the design
//   - the timer "second" is shortened with a defparam on its `ticks` parameter
//   - the two-second victory hold is fast-forwarded by depositing a value in
//     delay_counter shortly before its end; the end itself is simulated
// -----------------------------------------------------------------------------
module tb_pipe_puzzle_game;

    localparam TB_NAME       = "tb_pipe_puzzle_game";
    localparam TB_TIMEOUT_NS = 1_000_000_000;
    localparam CLK_PERIOD    = 20;
    localparam SECOND        = 3000;            // CLOCK_50 cycles per game second in this bench
    localparam HOLD_CYCLES   = 100_000_000;     // victory hold in the design: 2 s at 50 MHz
    localparam PS2_HALF_NS   = 203;             // accelerated keyboard clock
    localparam TITLE_LINES   = 64;              // displayed lines compared on the title screen
    localparam PORT_SAMPLE   = 7;               // check the video write port every 7th clock

    // ---------------------------------------------------------------- DUT
    reg         clk = 1'b0;
    reg  [3:0]  KEY = 4'b1111;                  // push buttons, active low
    wire        PS2_CLK, PS2_DAT;
    wire [9:0]  LEDR;
    wire [6:0]  HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;
    wire [7:0]  VGA_R, VGA_G, VGA_B;
    wire        VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    always #(CLK_PERIOD/2) clk = ~clk;

    pullup (PS2_CLK);
    pullup (PS2_DAT);

    pipe_puzzle_game dut (clk, KEY, PS2_CLK, PS2_DAT, LEDR, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0,
                          VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);
    defparam dut.t1.ticks = SECOND;

    ps2_keyboard_bfm kbd (PS2_CLK, PS2_DAT);
    vga_monitor      mon (VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_R, VGA_G, VGA_B);

    `include "tb_util.vh"
    `include "pipe_ref_model.vh"
    `include "vga_ref_model.vh"
    `include "seg7_ref_model.vh"

    // Internal points the bench looks at.
    `define PM   dut.u1
    `define VRAM dut.v1.VGA.VideoMemory

    reg [8*120-1:0] msg;
    integer cov_level, cov_victory, cov_board_reset, cov_key0, cov_cursor, cov_key, cov_second;

    wire [1:0] level  = dut.level;
    wire [3:0] cursor = dut.Coordinate_Selected;        // {x, y}

    // =====================================================================
    // Continuous checkers
    // =====================================================================

    // ---- 1. pipe logic: whenever the board changes, compare with the model
    always @(dut.pipe_opening_state or dut.level) begin : game_checker
        reg [63:0] exp_board;
        reg [15:0] exp_wet, exp_leak;
        reg        exp_victory;
        #2;
        exp_board = ref_board(`PIPE_ACTIVE_TYPES(`PM), `PM.pipe_orientation);
        ref_eval(exp_board, exp_wet, exp_leak, exp_victory);
        tb_checks = tb_checks + 4;
        if (dut.pipe_opening_state !== exp_board)
            tb_fail("opening state differs from tile types and orientations");
        if (dut.pipe_connected_to_source !== exp_wet)  tb_fail("wet tiles differ from the golden model");
        if (dut.pipe_leak !== exp_leak)                tb_fail("leaking tiles differ from the golden model");
        if (dut.victory !== exp_victory)               tb_fail("victory differs from the golden model");
    end

    // ---- 2. every reset of the pipe manager loads the LFSR value
    integer board_resets = 0;
    always @(negedge `PM.resetn) begin
        #1;
        board_resets = board_resets + 1;
        tb_checks = tb_checks + 1;
        if (`PM.pipe_orientation !== `PM.random_orientation)
            tb_fail("board was reset but did not take the LFSR value");
        if (dut.resetn === 1'b0)     tb_cov_hit(cov_board_reset + 0);   // R key
        if (dut.next_level === 1'b1) tb_cov_hit(cov_board_reset + 1);   // next level
        if (dut.restart === 1'b1)    tb_cov_hit(cov_board_reset + 2);   // KEY[0]
    end

    // ---- 3. level timers on HEX5..0, every clock
    localparam OVERFLOW = 100;
    integer m_sec [1:3];
    integer m_sub [1:3];
    integer m_i;
    initial for (m_i = 1; m_i <= 3; m_i = m_i + 1) begin m_sec[m_i] = 0; m_sub[m_i] = 0; end

    always @(posedge clk) begin : timer_model
        integer lv;
        if (dut.restart === 1'b1) begin
            for (lv = 1; lv <= 3; lv = lv + 1) begin m_sec[lv] = 0; m_sub[lv] = 0; end
        end else if (level != 2'd0) begin
            lv = level;
            if (dut.resetn === 1'b0) begin                  // R pressed
                m_sec[lv] = 0; m_sub[lv] = 0;
            end else if (dut.victory !== 1'b1) begin
                if (m_sub[lv] == SECOND - 1) begin
                    m_sub[lv] = 0;
                    if (m_sec[lv] < OVERFLOW) m_sec[lv] = m_sec[lv] + 1;
                    tb_cov_hit(cov_second + lv - 1);
                end else m_sub[lv] = m_sub[lv] + 1;
            end
        end
    end

    function [13:0] expect_pair(input integer lv);
        begin
            if (level < lv)                  expect_pair = {2{SEG_BLANK}};
            else if (m_sec[lv] == OVERFLOW)  expect_pair = {2{SEG_DASH}};
            else                             expect_pair = {seg_of(m_sec[lv] / 10), seg_of(m_sec[lv] % 10)};
        end
    endfunction

    wire [41:0] hex_all = {HEX5, HEX4, HEX3, HEX2, HEX1, HEX0};
    reg         hex_check = 1'b0;
    always @(negedge clk) begin : hex_scoreboard
        reg [41:0] exp_all;
        #(CLK_PERIOD/4);
        if (hex_check) begin
            exp_all = {expect_pair(1), expect_pair(2), expect_pair(3)};
            tb_checks = tb_checks + 1;
            if (hex_all !== exp_all) begin
                $sformat(msg, "HEX5..0 = %h, expected %h (level %0d, times %0d/%0d/%0d s)",
                         hex_all, exp_all, level, m_sec[1], m_sec[2], m_sec[3]);
                tb_fail(msg);
            end
        end
    end

    // ---- 4. video-memory write port against the golden renderer (sampled)
    integer exp_x = 0, exp_y = 0, port_phase = 0;
    reg     port_check = 1'b0;

    always @(posedge clk or negedge KEY[0]) begin
        if (!KEY[0]) begin
            exp_x = 0; exp_y = 0;
        end else if (exp_x == REF_RES_X - 1) begin
            exp_x = 0;
            exp_y = (exp_y == REF_RES_Y - 1) ? 0 : exp_y + 1;
        end else exp_x = exp_x + 1;
    end

    always @(negedge clk) begin : port_checker
        reg [8:0] exp_color;
        #(CLK_PERIOD/4);
        port_phase = (port_phase + 1) % PORT_SAMPLE;
        if (port_check && port_phase == 0) begin
            tb_checks = tb_checks + 1;
            if (`VRAM.wren_a !== dut.enable) tb_fail("video memory is written while the title screen is shown, or not written in the game");
            if (dut.enable === 1'b1) begin
                exp_color = ref_pixel(exp_x, exp_y, dut.pipe_opening_state, dut.pipe_connected_to_source,
                                      dut.pipe_leak, cursor, dut.victory, level);
                tb_checks = tb_checks + 2;
                if (`VRAM.address_a !== exp_y * REF_RES_X + exp_x) begin
                    $sformat(msg, "video write address %0d, expected pixel (%0d,%0d)", `VRAM.address_a, exp_x, exp_y);
                    tb_fail(msg);
                end
                if (`VRAM.data_a !== exp_color) begin
                    $sformat(msg, "pixel (%0d,%0d) is %o, expected %o", exp_x, exp_y, `VRAM.data_a, exp_color);
                    tb_fail(msg);
                end
            end
        end
    end

    // ---- 5. pins that never change, and the PS/2 lines
    reg pin_check = 1'b0;
    always @(negedge clk) begin
        if (pin_check) begin
            tb_checks = tb_checks + 1;
            if (LEDR !== 10'b0)       tb_fail("LEDR is not all off");
            if (VGA_SYNC_N !== 1'b1)  tb_fail("VGA_SYNC_N is not high");
            if ((^hex_all) === 1'bx)  tb_fail("X on a HEX display");
        end
        #0.5;
        if (!kbd.clk_low && PS2_CLK !== 1'b1) tb_fail("PS2_CLK is driven by the design");
        if (!kbd.dat_low && PS2_DAT !== 1'b1) tb_fail("PS2_DAT is driven by the design");
    end

    // ---- 6. level changes, for coverage and for the next-level pulse
    integer next_level_pulses = 0;
    always @(posedge clk) if (dut.next_level === 1'b1) next_level_pulses = next_level_pulses + 1;
    always @(level) if (level != 2'd0) tb_cov_hit(cov_level + level - 1);

    // =====================================================================
    // Stimulus helpers
    // =====================================================================
    integer exp_cx = 0, exp_cy = 0;             // expected cursor

    task clocks(input integer n);
        begin
            repeat (n) @(negedge clk);
        end
    endtask

    task expect_level(input integer lv, input [8*60-1:0] what);
        begin
            $sformat(msg, "%0s: level", what);
            tb_check_eq(level, lv, msg);
        end
    endtask

    task check_cursor(input [8*60-1:0] what);
        begin
            $sformat(msg, "%0s: cursor {x,y}", what);
            tb_check_eq(cursor, {exp_cx[1:0], exp_cy[1:0]}, msg);
            tb_cov_hit(cov_cursor + 4*exp_cy + exp_cx);
        end
    endtask

    // Press and release a key, as a keyboard does, and track the cursor.
    task tap(input [7:0] code);
        begin
            kbd.key_tap(code);
            case (code)
                kbd.KEY_W:     begin if (exp_cy > 0) exp_cy = exp_cy - 1; tb_cov_hit(cov_key + 0); end
                kbd.KEY_A:     begin if (exp_cx > 0) exp_cx = exp_cx - 1; tb_cov_hit(cov_key + 1); end
                kbd.KEY_S:     begin if (exp_cy < 3) exp_cy = exp_cy + 1; tb_cov_hit(cov_key + 2); end
                kbd.KEY_D:     begin if (exp_cx < 3) exp_cx = exp_cx + 1; tb_cov_hit(cov_key + 3); end
                kbd.KEY_SPACE: tb_cov_hit(cov_key + 4);
                kbd.KEY_R:     tb_cov_hit(cov_key + 5);
            endcase
            clocks(8);
            $sformat(msg, "after key %h", code);
            check_cursor(msg);
        end
    endtask

    task move_to(input integer x, input integer y);
        begin
            while (exp_cx < x) tap(kbd.KEY_D);
            while (exp_cx > x) tap(kbd.KEY_A);
            while (exp_cy < y) tap(kbd.KEY_S);
            while (exp_cy > y) tap(kbd.KEY_W);
        end
    endtask

    // Hold KEY[0] for a few clocks. It also resets the keyboard decoder and the
    // video timing, so the cursor and the VGA monitor start again.
    task press_key0;
        begin
            tb_cov_hit(cov_key0 + level);
            @(negedge clk);
            mon.resync;                         // the sync pattern is about to restart
            KEY[0] = 1'b0;
            clocks(6);
            KEY[0] = 1'b1;
            mon.resync;
            exp_cx = 0; exp_cy = 0;
            clocks(6);
        end
    endtask

    // Wait until the raster is in the left margin of the screen and return the
    // colour being written there.
    task margin_colour(output [8:0] colour);
        begin
            while (!(exp_x > 2 && exp_x < REF_H_OFF - 2)) @(negedge clk);
            #(CLK_PERIOD/4);
            colour = `VRAM.data_a;
        end
    endtask

    function integer level_seconds(input integer lv);
        begin
            case (lv)
                1: level_seconds = seg_to_seconds(HEX5, HEX4);
                2: level_seconds = seg_to_seconds(HEX3, HEX2);
                default: level_seconds = seg_to_seconds(HEX1, HEX0);
            endcase
        end
    endfunction

    // ---------------------------------------------------------------------
    // The automatic player: solve the current level with key strokes.
    // ---------------------------------------------------------------------
    task play_level(input integer lv);
        integer    j, k, turns, taps_before;
        reg [47:0] types;
        reg [31:0] expected;
        reg [8:0]  colour;
        integer    seconds;
        begin
            $sformat(msg, "level %0d: play to victory", lv);
            tb_case_begin(msg);
            expect_level(lv, "start of play");
            types = `PIPE_ACTIVE_TYPES(`PM);
            ref_solve(types);
            tb_check(ref_sol_count > 0, "the level has a solution");
            if (dut.victory === 1'b1) tb_note("the fresh board is already solved, nothing to play");
            taps_before = kbd.frames_sent;

            for (j = 0; j < 16; j = j + 1)
                if (ref_sol_net[j] && dut.victory !== 1'b1) begin
                    turns = ref_turns_needed(types[3*j +: 3], `PM.pipe_orientation[2*j +: 2], ref_sol_board[4*j +: 4]);
                    if (turns > 0) move_to(j % 4, j / 4);
                    for (k = 0; k < turns && dut.victory !== 1'b1; k = k + 1) begin
                        expected = `PM.pipe_orientation;
                        tap(kbd.KEY_SPACE);
                        // exactly the tile under the cursor made one quarter turn
                        expected[2*j +: 2] = expected[2*j +: 2] + 2'd1;
                        $sformat(msg, "Space on tile %0d turns that tile only", j);
                        tb_check_eq(`PM.pipe_orientation, expected, msg);
                    end
                end

            tb_check_eq(dut.victory, 1'b1, "victory once the network is complete");
            tb_check_eq(dut.pipe_leak, 16'b0, "no leak on the solved board");
            tb_check_eq(dut.pipe_connected_to_source[15], 1'b1, "the outlet tile is wet");
            expect_level(lv, "right after the victory");
            tb_cov_hit(cov_victory + lv - 1);
            seconds = level_seconds(lv);
            $display("    level %0d solved with %0d PS/2 frames, time on the display %0d s",
                     lv, kbd.frames_sent - taps_before, seconds);

            // the solved board is frozen and its timer stops
            expected = `PM.pipe_orientation;
            tap(kbd.KEY_SPACE);
            tap(kbd.KEY_D); tap(kbd.KEY_SPACE); tap(kbd.KEY_A);
            tb_check_eq(`PM.pipe_orientation, expected, "Space does nothing on a solved board");
            clocks(3 * SECOND);
            tb_check_eq(level_seconds(lv), seconds, "the timer of a solved level stands still");

            // the margins of the screen change colour
            margin_colour(colour);
            $sformat(msg, "margin colour after the victory on level %0d", lv);
            tb_check_eq(colour, lv == 3 ? REF_PURPLE : REF_GREEN, msg);
        end
    endtask

    // ---------------------------------------------------------------------
    // The victory screen is held for HOLD_CYCLES + 1 clocks, then the next
    // level starts. Everything but the last 200 clocks is skipped.
    // ---------------------------------------------------------------------
    task victory_hold(input integer lv);
        integer count, pulses, resets;
        integer seconds;
        begin
            $sformat(msg, "level %0d: victory hold, then level %0d", lv, lv + 1);
            tb_case_begin(msg);
            count = dut.delay_counter;
            clocks(100);
            tb_check_eq(dut.delay_counter, count + 100, "the hold counter advances every clock");
            seconds = level_seconds(lv);
            pulses  = next_level_pulses;
            resets  = board_resets;

            @(negedge clk);
            dut.delay_counter = HOLD_CYCLES - 200;      // fast-forward (back door)
            clocks(200);
            tb_check_eq(dut.delay_counter, HOLD_CYCLES, "hold counter at its terminal count");
            expect_level(lv, "one clock before the end of the hold");
            tb_check_eq(next_level_pulses, pulses, "no next-level pulse before the end of the hold");
            clocks(1);
            expect_level(lv + 1, "at the end of the hold");
            tb_check_eq(dut.delay_counter, 0, "hold counter cleared for the next level");
            clocks(3);
            tb_check_eq(next_level_pulses, pulses + 1, "exactly one next-level pulse");
            tb_check_eq(board_resets, resets + 1, "the next level starts with a freshly randomised board");
            exp_cx = 0; exp_cy = 0;
            check_cursor("new level: cursor back on tile (0,0)");
            tb_check_eq(level_seconds(lv), seconds, "the time of the finished level stays on its displays");
            tb_check(level_seconds(lv + 1) == 0, "the timer of the new level starts at 00");
        end
    endtask

    // =====================================================================
    // Scenario
    // =====================================================================
    integer    i, distinct, mismatches, resets_before;
    reg [511:0] seen;
    reg [31:0]  expected;
    reg [8:0]   colour;

    initial begin
        tb_start;
        tb_cov_group(cov_level,       "level 1..3 entered",              3);
        tb_cov_group(cov_victory,     "victory on level 1..3",           3);
        tb_cov_group(cov_board_reset, "board reset by R/next level/KEY0", 3);
        tb_cov_group(cov_key0,        "KEY[0] pressed on level 0..3",    4);
        tb_cov_group(cov_cursor,      "cursor on tile",                 16);
        tb_cov_group(cov_key,         "key used: W A S D Space R",       6);
        tb_cov_group(cov_second,      "second counted on level 1..3",    3);
        kbd.set_half_period(PS2_HALF_NS);

        // ------------------------------------------------------------ 1
        tb_case_begin("power-up and title screen");
        clocks(5);
        press_key0;                             // initialises the registers that have no reset value
        hex_check = 1'b1; port_check = 1'b1; pin_check = 1'b1;
        expect_level(0, "after power-up");
        tb_check_eq(dut.enable, 1'b0, "game disabled on the title screen");
        tb_check_eq(hex_all, {6{SEG_BLANK}}, "all HEX displays blank on the title screen");
        if ($test$plusargs("no_mif")) tb_note("title image not loaded (+no_mif)");
        else tb_check(`VRAM.init_loaded === 1'b1, "title image loaded from the MIF (pass +mif_dir=<quartus dir>)");

        // the first lines that reach the VGA pins are the title image
        while (mon.y < TITLE_LINES) clocks(200);
        seen = 512'b0; mismatches = 0;
        for (i = 0; i < TITLE_LINES * REF_RES_X; i = i + 1) begin
            seen[`VRAM.mem[i]] = 1'b1;
            if (mon.frame[i] !== `VRAM.mem[i]) mismatches = mismatches + 1;
        end
        distinct = 0;
        for (i = 0; i < 512; i = i + 1) distinct = distinct + seen[i];
        tb_check_eq(mismatches, 0, "displayed title pixels that differ from the frame buffer");
        if (!$test$plusargs("no_mif")) tb_check(distinct >= 8, "the title image has many colours in its first lines");
        tb_check_eq(`VRAM.writes, 0, "nothing is drawn over the title image before the game starts");
        tb_check_eq(dut.delay_counter, 0, "hold counter idle on the title screen");

        // ------------------------------------------------------------ 2
        tb_case_begin("buttons on the title screen");
        press_key0;
        expect_level(0, "KEY[0] on the title screen");
        tb_check_eq(dut.enable, 1'b0, "KEY[0] does not start the game");
        KEY[3:1] = 3'b000; clocks(50); KEY[3:1] = 3'b111; clocks(50);
        expect_level(0, "KEY[3:1] are not used");

        // ------------------------------------------------------------ 3
        tb_case_begin("any key starts the game");
        resets_before = board_resets;
        tap(kbd.KEY_ENTER);
        expect_level(1, "after the first key");
        tb_check_eq(dut.enable, 1'b1, "game enabled");
        tb_check_eq(level_seconds(1), 0, "level 1 timer starts at 00");
        tb_known_issue(`PM.pipe_orientation !== 32'b0 || board_resets != resets_before, "KI-1",
                       "the first level-1 board after power-up is not randomised (every tile at orientation 0)");
        clocks(2000);
        tb_check(`VRAM.writes > 1000, "the board is being drawn");

        // ------------------------------------------------------------ 4
        tb_case_begin("keyboard: cursor on every tile");
        for (i = 0; i < 4; i = i + 1) begin
            repeat (4) tap(i[0] ? kbd.KEY_A : kbd.KEY_D);       // the fourth press hits the edge
            tap(kbd.KEY_S);
        end
        tap(kbd.KEY_S);                                         // bottom edge
        move_to(0, 0);
        tap(kbd.KEY_W); tap(kbd.KEY_A);                         // top and left edges

        tb_case_begin("keyboard: Space rotates the selected tile");
        move_to(2, 1);                                          // tile 6
        expected = `PM.pipe_orientation;
        for (i = 1; i <= 4; i = i + 1) begin
            tap(kbd.KEY_SPACE);
            expected[13:12] = expected[13:12] + 2'd1;
            tb_check_eq(`PM.pipe_orientation, expected, "one quarter turn of tile 6 per Space");
        end

        tb_case_begin("keyboard: R gives a new board and clears the level timer");
        clocks(2 * SECOND);
        tb_check(level_seconds(1) >= 2, "level 1 timer has been running");
        resets_before = board_resets;
        tap(kbd.KEY_R);
        tb_check_eq(board_resets, resets_before + 1, "R re-randomises the board once");
        tb_check(level_seconds(1) == 0, "R clears the level timer");
        check_cursor("R leaves the cursor where it is");

        // ------------------------------------------------------------ 5
        play_level(1);
        victory_hold(1);
        tb_case_begin("level 2: R in the middle of the level");
        tap(kbd.KEY_D); tap(kbd.KEY_SPACE);
        clocks(2 * SECOND);
        resets_before = board_resets;
        tap(kbd.KEY_R);
        tb_check_eq(board_resets, resets_before + 1, "R re-randomises the level-2 board");
        tb_check(level_seconds(2) == 0, "R clears the level-2 timer");
        tb_check(level_seconds(1) >= 0 && level_seconds(1) < 100, "R on level 2 keeps the level-1 time");
        play_level(2);
        victory_hold(2);
        play_level(3);

        // ------------------------------------------------------------ 6
        tb_case_begin("game complete: level 3 stays");
        i = level_seconds(3);
        clocks(5 * SECOND);
        expect_level(3, "after the final victory");
        tb_check_eq(dut.delay_counter, 0, "no hold counter after the last level");
        tb_check_eq(level_seconds(3), i, "all three times stay on the displays");
        $display("    final times on HEX5..0: %0d s / %0d s / %0d s",
                 level_seconds(1), level_seconds(2), level_seconds(3));
        // R still works on the solved last level: new board, level 3 goes on
        resets_before = board_resets;
        tap(kbd.KEY_R);
        tb_check_eq(board_resets, resets_before + 1, "R on the solved level 3 gives a new board");
        expect_level(3, "after R on level 3");
        tb_check(level_seconds(3) == 0, "R clears the level-3 timer");
        margin_colour(colour);
        if (dut.victory !== 1'b1) tb_check_eq(colour, REF_BLACK, "margins black again once the board is unsolved");

        // ------------------------------------------------------------ 7
        tb_case_begin("KEY[0] restarts from level 3");
        resets_before = board_resets;
        press_key0;
        expect_level(1, "after KEY[0]");
        tb_check_eq(dut.enable, 1'b1, "the game stays enabled after a restart");
        tb_check(board_resets > resets_before, "restart re-randomises the board");
        tb_check_eq({HEX3, HEX2, HEX1, HEX0}, {4{SEG_BLANK}}, "level 2 and 3 displays blank after a restart");
        tb_check(level_seconds(1) == 0, "level 1 timer cleared by the restart");
        check_cursor("restart: cursor on tile (0,0)");

        play_level(1);
        victory_hold(1);
        tb_case_begin("KEY[0] restarts from level 2");
        tap(kbd.KEY_S); tap(kbd.KEY_D);
        press_key0;
        expect_level(1, "after KEY[0] on level 2");
        tb_check_eq({HEX3, HEX2}, {2{SEG_BLANK}}, "level 2 display blank again");
        check_cursor("restart: cursor on tile (0,0)");

        tb_case_begin("KEY[0] restarts in the middle of level 1");
        tap(kbd.KEY_D); tap(kbd.KEY_SPACE); tap(kbd.KEY_S);
        clocks(2 * SECOND);
        press_key0;
        expect_level(1, "after KEY[0] on level 1");
        tb_check(level_seconds(1) == 0, "level 1 timer cleared");

        tb_case_begin("KEY[0] during the victory hold");
        play_level(1);
        tb_case_begin("KEY[0] during the victory hold");
        clocks(500);
        tb_check(dut.delay_counter > 400, "the hold is running");
        press_key0;
        expect_level(1, "restart during the hold");
        if (dut.victory !== 1'b1)
            tb_known_issue(dut.delay_counter === 27'd0, "KI-2",
                           "KEY[0] during the victory hold leaves the hold counter running from its old value");
        // the game is still playable afterwards
        play_level(1);
        victory_hold(1);
        expect_level(2, "end of the scenario");

        tb_check_eq(mon.errors, 0, "errors reported by the VGA monitor");
        tb_finish;
    end

endmodule
