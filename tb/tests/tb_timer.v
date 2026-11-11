`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_timer.v -- unit testbench for rtl/game/timer.v (timer and display)
//
// The DUT is built with a short "second" (TICKS clock cycles) so that minutes
// of game time take microseconds of simulation. A scoreboard keeps the three
// level times as plain integers and compares all six seven-segment outputs on
// every clock cycle.
//
//   1. seven-segment decoder   all 16 codes, enabled and blanked
//   2. title screen            nothing counts, everything blank
//   3. counting                exact second length, digit carry, per level
//   4. victory                 freezes the running timer
//   5. R (resetn)              clears only the current level
//   6. KEY[0] (restart)        clears all levels, highest priority
//   7. overflow                99 s -> "--" and stays there
//   8. random soak             random level / victory / reset / restart
//   9. default build           one second is 50 000 000 cycles of CLOCK_50
//      (+long additionally simulates a real second of the default build)
// -----------------------------------------------------------------------------
module tb_timer;

    localparam TB_NAME       = "tb_timer";
    localparam TB_TIMEOUT_NS = 2_000_000_000;
    localparam CLK_PERIOD    = 20;
    localparam TICKS         = 7;               // clock cycles per second in this bench

    parameter N_SOAK_CYCLES  = 60000;

    reg        clk     = 1'b0;
    reg        victory = 1'b0;
    reg        resetn  = 1'b1;                  // low while R is pressed
    reg        restart = 1'b0;                  // high while KEY[0] restarts the game
    reg  [1:0] level   = 2'd0;
    wire [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;

    always #(CLK_PERIOD/2) clk = ~clk;

    timer #(.ticks(TICKS)) dut (clk, victory, resetn, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0, level, restart);

    // Default build, used for the parameter check and the optional long test.
    reg        long_run = 1'b0;
    wire [6:0] D5, D4, D3, D2, D1, D0;
    timer dut_default (clk & long_run, 1'b0, 1'b1, D5, D4, D3, D2, D1, D0, 2'd1, 1'b0);

    // Stand-alone decoder for the exhaustive check.
    reg  [3:0] dec_n      = 4'd0;
    reg        dec_enable = 1'b0;
    wire [6:0] dec_out;
    display u_dec (dec_n, dec_out, dec_enable);

    `include "tb_util.vh"
    `include "seg7_ref_model.vh"

    reg [8*120-1:0] msg;
    integer cov_count, cov_carry, cov_overflow, cov_r, cov_restart, cov_freeze, cov_prio, cov_digit;

    // ---------------------------------------------------------- golden model
    // Level times in whole seconds; OVERFLOW means "more than 99", shown as "--".
    localparam OVERFLOW = 100;
    integer m_sec [1:3];
    integer m_sub [1:3];                        // clock cycles into the current second
    integer m_lv;

    initial begin
        for (m_lv = 1; m_lv <= 3; m_lv = m_lv + 1) begin
            m_sec[m_lv] = 0;
            m_sub[m_lv] = 0;
        end
    end

    always @(posedge clk) begin : model
        integer lv;
        if (restart) begin
            for (lv = 1; lv <= 3; lv = lv + 1) begin
                m_sec[lv] = 0;
                m_sub[lv] = 0;
            end
        end else if (level != 2'd0) begin
            lv = level;
            if (!resetn) begin
                m_sec[lv] = 0;
                m_sub[lv] = 0;
            end else if (!victory) begin
                if (m_sub[lv] == TICKS - 1) begin
                    m_sub[lv] = 0;
                    if (m_sec[lv] < OVERFLOW) m_sec[lv] = m_sec[lv] + 1;
                    if (m_sec[lv] % 10 == 0 && m_sec[lv] < OVERFLOW) tb_cov_hit(cov_carry);
                    if (m_sec[lv] == OVERFLOW) tb_cov_hit(cov_overflow + lv - 1);
                    tb_cov_hit(cov_count + lv - 1);
                end else begin
                    m_sub[lv] = m_sub[lv] + 1;
                end
            end
        end
        // stimulus coverage
        if (restart)                      tb_cov_hit(cov_restart + level);
        else if (!resetn)                 tb_cov_hit(cov_r + level);
        else if (victory && level != 0)   tb_cov_hit(cov_freeze);
        if (restart && !resetn)           tb_cov_hit(cov_prio + 0);
        if (!restart && !resetn && victory) tb_cov_hit(cov_prio + 1);
    end

    function [6:0] expect_tens(input integer lv);
        begin
            if (level < lv)                  expect_tens = SEG_BLANK;
            else if (m_sec[lv] == OVERFLOW)  expect_tens = seg_of(10);
            else                             expect_tens = seg_of(m_sec[lv] / 10);
        end
    endfunction

    function [6:0] expect_ones(input integer lv);
        begin
            if (level < lv)                  expect_ones = SEG_BLANK;
            else if (m_sec[lv] == OVERFLOW)  expect_ones = seg_of(10);
            else                             expect_ones = seg_of(m_sec[lv] % 10);
        end
    endfunction

    // Scoreboard: all six displays, every cycle, from the first clock on. It
    // samples a quarter period after the falling edge: the stimulus (which
    // changes on the falling edge) has settled and the next rising edge has
    // not happened yet.
    wire [41:0] hex_all = {HEX5, HEX4, HEX3, HEX2, HEX1, HEX0};
    always @(negedge clk) begin : scoreboard
        reg [41:0] exp_all;
        #(CLK_PERIOD/4);
        exp_all = {expect_tens(1), expect_ones(1), expect_tens(2), expect_ones(2),
                   expect_tens(3), expect_ones(3)};
        tb_checks = tb_checks + 1;
        if (hex_all !== exp_all) begin
            $sformat(msg, "HEX5..0 = %h, expected %h (level %0d, times %0d/%0d/%0d s)",
                     hex_all, exp_all, level, m_sec[1], m_sec[2], m_sec[3]);
            tb_fail(msg);
        end
    end

    // ---------------------------------------------------------------- helpers
    // Inputs change on the falling edge, so they are stable at the rising edge.
    task run(input integer cycles);
        begin
            repeat (cycles) @(negedge clk);
        end
    endtask

    task run_seconds(input integer seconds);
        begin
            run(seconds * TICKS);
        end
    endtask

    task press_r;                               // one-cycle pulse, as from ps2_driver
        begin
            resetn = 1'b0; run(1); resetn = 1'b1;
        end
    endtask

    task press_key0;                            // one-cycle pulse on restart
        begin
            restart = 1'b1; run(1); restart = 1'b0;
        end
    endtask

    // Wait for the next change of the level-1 ones digit and return how many
    // clock cycles it took. Independent of the scoreboard model.
    task cycles_to_next_change(output integer cycles);
        reg [6:0] start;
        begin
            start  = HEX4;
            cycles = 0;
            while (HEX4 === start && cycles < 100 * TICKS) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    // ============================================================ 1. decoder
    task test_decoder;
        integer n;
        begin
            tb_case_begin("seven-segment decoder");
            for (n = 0; n < 16; n = n + 1) begin
                dec_n = n; dec_enable = 1'b1; #1;
                $sformat(msg, "digit %0d", n);
                tb_check_eq(dec_out, seg_of(n), msg);
                tb_cov_hit(cov_digit + (n < 10 ? n : 10));
                dec_enable = 1'b0; #1;
                $sformat(msg, "digit %0d blanked", n);
                tb_check_eq(dec_out, SEG_BLANK, msg);
                tb_cov_hit(cov_digit + 11);
            end
            // anchors that do not go through seg_of
            dec_enable = 1'b1;
            dec_n = 4'd0; #1; tb_check_eq(dec_out, 7'h40, "0 lights every segment but g");
            dec_n = 4'd8; #1; tb_check_eq(dec_out, 7'h00, "8 lights every segment");
            dec_n = 4'd1; #1; tb_check_eq(dec_out, 7'h79, "1 lights b and c");
        end
    endtask

    // ======================================================= 2. title screen
    task test_title_screen;
        begin
            tb_case_begin("title screen: nothing counts");
            level = 2'd0;
            run_seconds(5);
            tb_check_eq(hex_all, {6{SEG_BLANK}}, "all displays blank on level 0");
            tb_check_eq(dut.counter_L1 | dut.counter_L2 | dut.counter_L3, 0, "no prescaler runs on level 0");
            press_r;
            run_seconds(2);
            tb_check_eq(hex_all, {6{SEG_BLANK}}, "R on the title screen changes nothing");
        end
    endtask

    // =========================================================== 3. counting
    task test_counting;
        integer cycles, n;
        begin
            tb_case_begin("level 1 counts seconds");
            level = 2'd1;
            run(1);
            tb_check_eq({HEX5, HEX4}, {seg_of(0), seg_of(0)}, "level 1 starts at 00");
            tb_check_eq({HEX3, HEX2, HEX1, HEX0}, {4{SEG_BLANK}}, "levels 2 and 3 blank during level 1");
            cycles_to_next_change(cycles);          // align to a second boundary
            for (n = 0; n < 12; n = n + 1) begin
                cycles_to_next_change(cycles);
                tb_check_eq(cycles, TICKS, "one displayed second is exactly TICKS clock cycles");
            end
            tb_check_eq({HEX5, HEX4}, {seg_of(1), seg_of(3)}, "13 seconds elapsed, tens digit carried");

            tb_case_begin("victory freezes the timer");
            victory = 1'b1;
            run_seconds(4);
            tb_check_eq({HEX5, HEX4}, {seg_of(1), seg_of(3)}, "time held while victory is high");

            tb_case_begin("level 2 keeps the level 1 time");
            level = 2'd2; victory = 1'b0;
            run(1);
            tb_check_eq({HEX5, HEX4}, {seg_of(1), seg_of(3)}, "level 1 time kept");
            tb_check_eq({HEX3, HEX2}, {seg_of(0), seg_of(0)}, "level 2 starts at 00");
            tb_check_eq({HEX1, HEX0}, {2{SEG_BLANK}}, "level 3 blank during level 2");
            run_seconds(27);
            tb_check_eq({HEX5, HEX4}, {seg_of(1), seg_of(3)}, "level 1 time still kept");

            tb_case_begin("level 3 keeps both earlier times");
            victory = 1'b1; run_seconds(1);
            level = 2'd3; victory = 1'b0;
            run_seconds(8);
            tb_check_eq({HEX5, HEX4}, {seg_of(1), seg_of(3)}, "level 1 time kept on level 3");
            tb_check(HEX3 === seg_of(2) && (HEX2 === seg_of(6) || HEX2 === seg_of(7)), "level 2 time kept on level 3");
            tb_check(HEX1 === seg_of(0) && HEX0 !== seg_of(0) && HEX0 !== SEG_BLANK, "level 3 is counting");
        end
    endtask

    // ============================================================== 4. R key
    // Stored digits of the three levels, visible or not: {L1, L2, L3}, 8 bits each.
    wire [23:0] digits = {dut.tens_L1, dut.ones_L1, dut.tens_L2, dut.ones_L2, dut.tens_L3, dut.ones_L3};

    task test_r_key;
        integer    lv, cycles;
        reg [23:0] saved;
        begin
            tb_case_begin("R clears only the current level");
            for (lv = 3; lv >= 1; lv = lv - 1) begin
                level = lv; victory = 1'b0;
                run_seconds(3); run(TICKS / 2);          // somewhere inside a second
                saved = digits;
                tb_check(saved[8*(3-lv) +: 8] != 8'h00, "the level has a non-zero time before R");
                press_r;
                $sformat(msg, "level %0d time is 00 after R", lv);
                case (lv)
                    1: tb_check_eq({HEX5, HEX4}, {2{seg_of(0)}}, msg);
                    2: tb_check_eq({HEX3, HEX2}, {2{seg_of(0)}}, msg);
                    3: tb_check_eq({HEX1, HEX0}, {2{seg_of(0)}}, msg);
                endcase
                $sformat(msg, "R on level %0d leaves the other two times alone", lv);
                case (lv)
                    1: tb_check_eq(digits[15:0], saved[15:0], msg);
                    2: tb_check_eq({digits[23:16], digits[7:0]}, {saved[23:16], saved[7:0]}, msg);
                    3: tb_check_eq(digits[23:8], saved[23:8], msg);
                endcase
            end
            // level is 1 here: the second after R is a full one (prescaler cleared too)
            cycles_to_next_change(cycles);
            tb_check_eq(cycles, TICKS, "first second after R is a full second");

            tb_case_begin("R held, and R on a solved level");
            resetn = 1'b0; run_seconds(3); resetn = 1'b1;
            run(1);
            tb_check_eq({HEX5, HEX4}, {2{seg_of(0)}}, "timer stays at 00 while R is held");
            run_seconds(4);
            victory = 1'b1; run_seconds(2);
            resetn = 1'b0; run(1); resetn = 1'b1;       // R wins over victory
            tb_check_eq({HEX5, HEX4}, {2{seg_of(0)}}, "R clears the time of a solved level");
            victory = 1'b0;
        end
    endtask

    // ============================================================ 5. restart
    task test_restart;
        integer lv;
        begin
            tb_case_begin("KEY[0] restart clears every level");
            for (lv = 3; lv >= 0; lv = lv - 1) begin
                level = 2'd1; run_seconds(2);
                level = 2'd2; run_seconds(3);
                level = 2'd3; run_seconds(4);
                level = lv;
                press_key0;
                level = 2'd3;                           // look at all three times
                #1;
                $sformat(msg, "all times 00 after a restart on level %0d", lv);
                tb_check_eq(hex_all, {6{seg_of(0)}}, msg);
            end
            // restart outranks R and victory when they arrive together
            level = 2'd2; run_seconds(5);
            restart = 1'b1; resetn = 1'b0; victory = 1'b1; run(1);
            restart = 1'b0; resetn = 1'b1; victory = 1'b0;
            level = 2'd3; #1;
            tb_check_eq(hex_all, {6{seg_of(0)}}, "restart together with R and victory clears everything");
            // R together with victory still clears (R outranks victory)
            level = 2'd3; run_seconds(3);
            resetn = 1'b0; victory = 1'b1; run(1); resetn = 1'b1;
            tb_check_eq({HEX1, HEX0}, {2{seg_of(0)}}, "R together with victory clears the level");
            victory = 1'b0;
            press_key0;
        end
    endtask

    // =========================================================== 6. overflow
    task test_overflow;
        integer lv;
        begin
            tb_case_begin("99 s, then dashes");
            for (lv = 1; lv <= 3; lv = lv + 1) begin
                level = lv;
                press_r;
                run_seconds(99);
                $sformat(msg, "level %0d shows 99 after 99 s", lv);
                case (lv)
                    1: tb_check_eq({HEX5, HEX4}, {2{seg_of(9)}}, msg);
                    2: tb_check_eq({HEX3, HEX2}, {2{seg_of(9)}}, msg);
                    3: tb_check_eq({HEX1, HEX0}, {2{seg_of(9)}}, msg);
                endcase
                run_seconds(1);
                $sformat(msg, "level %0d shows -- after 100 s", lv);
                case (lv)
                    1: tb_check_eq({HEX5, HEX4}, {2{SEG_DASH}}, msg);
                    2: tb_check_eq({HEX3, HEX2}, {2{SEG_DASH}}, msg);
                    3: tb_check_eq({HEX1, HEX0}, {2{SEG_DASH}}, msg);
                endcase
                run_seconds(30);                        // and it stays there
            end
            tb_check_eq(hex_all, {6{SEG_DASH}}, "all three levels stay at -- once overflowed");
            level = 2'd2;
            press_r;
            run(1);
            tb_check_eq({HEX3, HEX2}, {2{seg_of(0)}}, "R recovers an overflowed level");
            press_key0;
        end
    endtask

    // =============================================================== 7. soak
    task test_soak;
        integer n, r;
        begin
            tb_case_begin("random soak");
            for (n = 0; n < N_SOAK_CYCLES; n = n + 1) begin
                r = {$random(tb_seed)} % 1000;
                if (r < 4)        level = {$random(tb_seed)} % 4;     // level changes are rare
                else if (r < 8)   level = (level == 2'd3) ? 2'd3 : level + 2'd1;
                victory = (r % 16 == 5)  ? ~victory : victory;
                resetn  = (r % 64 == 7)  ? 1'b0 : 1'b1;
                restart = (r % 512 == 9) ? 1'b1 : 1'b0;
                if (r % 512 == 73) begin restart = 1'b1; resetn = 1'b0; end
                run(1);
            end
            victory = 1'b0; resetn = 1'b1; restart = 1'b0;
        end
    endtask

    // ====================================================== 8. default build
    task test_default_build;
        integer n;
        begin
            tb_case_begin("default build: 50 000 000 cycles per second");
            tb_check_eq(dut_default.ticks, 50_000_000, "default ticks parameter is one second of CLOCK_50");
            if ($test$plusargs("long")) begin
                tb_case_begin("default build: one real second (+long)");
                long_run = 1'b1;
                for (n = 0; n < 49_999_990; n = n + 1) @(negedge clk);
                tb_check_eq({D5, D4}, {2{seg_of(0)}}, "still 00 just before one second");
                repeat (20) @(negedge clk);
                tb_check_eq({D5, D4}, {seg_of(0), seg_of(1)}, "01 just after one second");
                long_run = 1'b0;
            end else begin
                tb_note("real-time run of the default build skipped (add +long to enable)");
            end
        end
    endtask

    // ================================================================== main
    initial begin
        tb_start;
        tb_cov_group(cov_count,    "second counted on level 1..3",   3);
        tb_cov_group(cov_carry,    "ones digit carried into tens",   1);
        tb_cov_group(cov_overflow, "overflow to -- on level 1..3",   3);
        tb_cov_group(cov_r,        "R pressed on level 0..3",        4);
        tb_cov_group(cov_restart,  "restart on level 0..3",          4);
        tb_cov_group(cov_freeze,   "timer frozen by victory",        1);
        tb_cov_group(cov_prio,     "restart+R / R+victory together", 2);
        tb_cov_group(cov_digit,    "digit 0..9, dash, blank",       12);

        test_decoder;
        test_title_screen;
        test_counting;
        test_r_key;
        test_restart;
        test_overflow;
        test_soak;
        test_default_build;
        tb_finish;
    end

endmodule
