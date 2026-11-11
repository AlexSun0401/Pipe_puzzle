`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_pipe_manager.v -- unit testbench for rtl/game/pipe_manager.v
//
// Covers pipe_config_opening, rng_lfsr_32 and pipe_manager:
//   1. opening table      every type code x orientation, by shape and rotation
//   2. LFSR               seed, shift structure, feedback taps, basic statistics
//   3. level maps         level mux against the level parameters, level 0 empty
//   4. reset              asynchronous reset loads the LFSR value
//   5. rotation           every tile, wrap-around, disabled -> re-randomise
//   6. flow, directed     hand-computed boards (anchors for the golden model)
//   7. flow, random       forced opening patterns against the golden model
//   8. levels, random     random orientations on every level
//   9. play to victory    solver + rotations through the real interface,
//                         rotation lock after victory, single-turn perturbation
//
// Every output is compared with the golden model in include/pipe_ref_model.vh.
// -----------------------------------------------------------------------------
module tb_pipe_manager;

    localparam TB_NAME       = "tb_pipe_manager";
    localparam TB_TIMEOUT_NS = 500_000_000;
    localparam CLK_PERIOD    = 20;              // 50 MHz

    // Stimulus volume; override with -P (Icarus) or -g (ModelSim) for a longer soak.
    parameter N_LFSR_CYCLES    = 20000;
    parameter N_RANDOM_BOARDS  = 6000;          // forced opening patterns
    parameter N_RANDOM_ORIENTS = 2000;          // per level

    // ------------------------------------------------------------------ DUTs
    reg         clk    = 1'b0;
    reg         rotate = 1'b0;
    reg         resetn = 1'b1;
    reg         enable = 1'b0;
    reg  [3:0]  sw     = 4'b0;                  // {x, y} of the selected tile
    reg  [1:0]  level  = 2'd0;
    wire [63:0] board;
    wire [15:0] wet;
    wire [15:0] leak;
    wire        victory;

    always #(CLK_PERIOD/2) clk = ~clk;

    pipe_manager dut (clk, rotate, resetn, sw, board, wet, leak, victory, level, enable);

    // Stand-alone instances for the exhaustive leaf checks. u_lfsr starts from
    // the same seed as the generator inside the DUT, so it also predicts the
    // value that a reset loads.
    reg  [2:0]  cfg_type   = 3'd0;
    reg  [1:0]  cfg_orient = 2'd0;
    wire [3:0]  cfg_open;
    pipe_config_opening u_cfg (cfg_type, cfg_orient, cfg_open);

    wire [31:0] lfsr_out;
    rng_lfsr_32 u_lfsr (clk, lfsr_out);

    `include "tb_util.vh"
    `include "pipe_ref_model.vh"

    // --------------------------------------------------------- expected state
    reg [31:0] exp_orient = 32'b0;              // shadow of the orientation register
    reg [47:0] level_types [0:3];
    reg [63:0] forced_board;
    reg [8*120-1:0] msg;

    integer cov_rotate, cov_wrap, cov_locked, cov_reset, cov_rerandom;
    integer cov_side, cov_wet, cov_wet_count, cov_leak_count, cov_outcome, cov_win_level;
    integer cov_lost;

    // ---------------------------------------------------------------- helpers
    function integer popcount16(input [15:0] v);
        integer k;
        begin
            popcount16 = 0;
            for (k = 0; k < 16; k = k + 1) popcount16 = popcount16 + v[k];
        end
    endfunction

    // Coverage of what a board exercises, classified by the golden model.
    task sample_board(input [63:0] b, input [15:0] w, input [15:0] l, input v);
        reg [63:0] sides;
        integer    j, side, n;
        begin
            sides = ref_last_leak_sides;            // left by ref_eval for this board
            for (j = 0; j < 16; j = j + 1) begin
                if (w[j]) tb_cov_hit(cov_wet + j);
                for (side = 0; side < 4; side = side + 1)
                    // the two port bins count "wet and open towards the port"
                    if (sides[4*j + side] || (ref_is_port(j, side) && w[j] && b[4*j + side]))
                        tb_cov_hit(cov_side + 4*j + side);
            end
            n = popcount16(w);
            tb_cov_hit(cov_wet_count + (n == 0 ? 0 : n == 1 ? 1 : n <= 8 ? 2 : n <= 15 ? 3 : 4));
            n = popcount16(l);
            tb_cov_hit(cov_leak_count + (n == 0 ? 0 : n == 1 ? 1 : 2));
            if (v)                    tb_cov_hit(cov_outcome + 0);   // solved
            else if (!w[15])          tb_cov_hit(cov_outcome + 1);   // outlet dry
            else if (l != 16'b0)      tb_cov_hit(cov_outcome + 2);   // outlet wet, but a leak
            else                      tb_cov_hit(cov_outcome + 3);   // closed network, outlet shut
        end
    endtask

    // Compare the three outputs with the golden model for the given board.
    // Messages are only formatted on a mismatch: this runs tens of thousands
    // of times.
    task check_outputs(input [63:0] b, input [8*40-1:0] what);
        reg [15:0] exp_wet, exp_leak;
        reg        exp_victory;
        begin
            ref_eval(b, exp_wet, exp_leak, exp_victory);
            if (wet === exp_wet && leak === exp_leak && victory === exp_victory) begin
                tb_checks = tb_checks + 3;
            end else begin
                $sformat(msg, "%0s: wet tiles (board %h)", what, b);
                tb_check_eq(wet, exp_wet, msg);
                $sformat(msg, "%0s: leaking tiles (board %h)", what, b);
                tb_check_eq(leak, exp_leak, msg);
                $sformat(msg, "%0s: victory (board %h)", what, b);
                tb_check_eq(victory, exp_victory, msg);
            end
            sample_board(b, exp_wet, exp_leak, exp_victory);
        end
    endtask

    // Compare register, board and outputs with the shadow state.
    task check_state(input [8*40-1:0] what);
        reg [63:0] exp_board;
        begin
            #1;
            exp_board = ref_board(level_types[level], exp_orient);
            if (dut.pipe_orientation === exp_orient && board === exp_board) begin
                tb_checks = tb_checks + 2;
            end else begin
                $sformat(msg, "%0s: orientation register", what);
                tb_check_eq(dut.pipe_orientation, exp_orient, msg);
                $sformat(msg, "%0s: opening state", what);
                tb_check_eq(board, exp_board, msg);
            end
            check_outputs(exp_board, what);
        end
    endtask

    // One-cycle reset pulse, timed like the one from the keyboard decoder. The
    // register takes the LFSR value present when the reset falls.
    task do_reset;
        begin
            @(posedge clk); #1;
            exp_orient = lfsr_out;
            resetn = 1'b0;
            @(posedge clk); #1;
            resetn = 1'b1;
            tb_cov_hit(cov_reset);
        end
    endtask

    // Select tile j, pulse rotate for one clock and update the shadow state.
    task rotate_tile(input integer j);
        begin
            @(posedge clk); #1;
            sw = {j[1:0], j[3:2]};
            if (!enable) begin
                exp_orient = lfsr_out;                       // re-randomise
                tb_cov_hit(cov_rerandom);
            end else if (victory) begin
                tb_cov_hit(cov_locked);                      // solved boards are frozen
            end else begin
                if (exp_orient[2*j +: 2] == 2'd3) tb_cov_hit(cov_wrap);
                exp_orient[2*j +: 2] = exp_orient[2*j +: 2] + 2'd1;
                tb_cov_hit(cov_rotate + j);
            end
            rotate = 1'b1;
            @(posedge clk); #1;
            rotate = 1'b0;
        end
    endtask

    // Deposit an orientation word directly (back door) to reach a state fast.
    task deposit_orient(input [31:0] value);
        begin
            dut.pipe_orientation = value;
            exp_orient           = value;
        end
    endtask

    function [63:0] random64(input integer unused);     // a Verilog-2001 function needs an input
        begin
            random64 = {$random(tb_seed), $random(tb_seed)};
        end
    endfunction

    // =========================================================== 1. openings
    task test_opening_table;
        integer   t, o, ones, k;
        reg [3:0] at_zero, previous;
        begin
            tb_case_begin("opening table");
            for (t = 0; t < 8; t = t + 1) begin
                for (o = 0; o < 4; o = o + 1) begin
                    cfg_type = t; cfg_orient = o; #1;
                    $sformat(msg, "type %0d orientation %0d openings", t, o);
                    tb_check_eq(cfg_open, ref_opening(t, o), msg);
                    // +1 orientation is exactly one quarter turn clockwise
                    if (o == 0) at_zero = cfg_open;
                    else begin
                        $sformat(msg, "type %0d: orientation %0d is orientation %0d turned clockwise", t, o, o - 1);
                        tb_check_eq(cfg_open, ref_rot_cw(previous), msg);
                    end
                    previous = cfg_open;
                    // the number of openings identifies the piece
                    ones = 0;
                    for (k = 0; k < 4; k = k + 1) ones = ones + cfg_open[k];
                    $sformat(msg, "type %0d orientation %0d number of openings", t, o);
                    case (t)
                        REF_STRAIGHT: tb_check_eq(ones, 2, msg);
                        REF_L:        tb_check_eq(ones, 2, msg);
                        REF_T:        tb_check_eq(ones, 3, msg);
                        REF_CROSS:    tb_check_eq(ones, 4, msg);
                        default:      tb_check_eq(ones, 0, msg);
                    endcase
                    // a straight piece opens on opposite sides, an L on adjacent sides
                    if (t == REF_STRAIGHT) tb_check(cfg_open == 4'b0101 || cfg_open == 4'b1010, "straight piece is straight");
                    if (t == REF_L)        tb_check(cfg_open != 4'b0101 && cfg_open != 4'b1010, "L piece is bent");
                end
                // four quarter turns bring the piece back
                tb_check_eq(ref_rot_cw(previous), at_zero, "four turns are a full turn");
            end
        end
    endtask

    // =============================================================== 2. LFSR
    // Model of the generator, run for the whole simulation.
    reg [31:0] lfsr_model = 32'hBEEF_BEEF;
    always @(posedge clk)
        lfsr_model <= {lfsr_model[30:0], lfsr_model[31] ^ lfsr_model[21] ^ lfsr_model[1] ^ lfsr_model[0]};
    always @(negedge clk) begin
        tb_checks = tb_checks + 1;
        if (lfsr_out !== lfsr_model) tb_fail("LFSR sequence differs from seed 0xBEEFBEEF, taps 32,22,2,1");
        if (dut.random_orientation !== lfsr_out) tb_fail("generator inside pipe_manager differs from a stand-alone one");
    end

    task test_lfsr;
        integer    n, k;
        reg [31:0] prev, seen_one, seen_zero;
        integer    ones;
        begin
            tb_case_begin("LFSR");
            @(posedge clk); #1;
            seen_one = 32'b0; seen_zero = 32'b0; ones = 0;
            for (n = 0; n < N_LFSR_CYCLES; n = n + 1) begin
                prev = lfsr_out;
                @(posedge clk); #1;
                tb_checks = tb_checks + 2;
                if (lfsr_out[31:1] !== prev[30:0])
                    tb_fail("LFSR is not a left shift of its previous value");
                if (lfsr_out === 32'b0 || (^lfsr_out) === 1'bx)
                    tb_fail("LFSR reached the all-zero lock-up state or X");
                seen_one  = seen_one  |  lfsr_out;
                seen_zero = seen_zero | ~lfsr_out;
                for (k = 0; k < 32; k = k + 1) ones = ones + lfsr_out[k];
            end
            tb_check_eq(seen_one,  32'hFFFF_FFFF, "every LFSR bit was 1 at some point");
            tb_check_eq(seen_zero, 32'hFFFF_FFFF, "every LFSR bit was 0 at some point");
            // loose balance bound: 48 % .. 52 % ones over 640 000 bits
            tb_check(ones * 100 > N_LFSR_CYCLES * 32 * 48 && ones * 100 < N_LFSR_CYCLES * 32 * 52,
                     "LFSR output is roughly balanced");
        end
    endtask

    // ========================================================= 3. level maps
    task test_level_maps;
        integer lv, n;
        begin
            tb_case_begin("level maps");
            enable = 1'b1;
            for (lv = 0; lv < 4; lv = lv + 1) begin
                level = lv; #1;
                $sformat(msg, "level %0d: types selected by the level mux", lv);
                tb_check_eq(`PIPE_ACTIVE_TYPES(dut), level_types[lv], msg);
            end
            // level 0 is the title screen: an empty board whatever the register holds
            level = 2'd0;
            for (n = 0; n < 50; n = n + 1) begin
                deposit_orient($random(tb_seed));
                check_state("level 0");
                tb_check_eq(board,   64'b0, "level 0: board is empty");
                tb_check_eq(victory, 1'b0,  "level 0: no victory");
            end
            // every level must be solvable, otherwise the game cannot be finished
            for (lv = 1; lv < 4; lv = lv + 1) begin
                ref_solve(level_types[lv]);
                $display("    level %0d: %0d winning network(s)", lv, ref_sol_count);
                $sformat(msg, "level %0d has a solution", lv);
                tb_check(ref_sol_count > 0, msg);
            end
        end
    endtask

    // ============================================================== 4. reset
    task test_reset;
        integer n;
        begin
            tb_case_begin("reset loads the LFSR value");
            level = 2'd1; enable = 1'b1;
            for (n = 0; n < 20; n = n + 1) begin
                repeat ({$random(tb_seed)} % 7) @(posedge clk);
                do_reset;
                check_state("after reset");
            end
            // asynchronous: a reset that falls between two clock edges acts at once
            @(negedge clk); #3;
            exp_orient = lfsr_out;
            resetn = 1'b0;
            check_state("reset between clock edges");
            // while reset is held, a rotate pulse loads again instead of turning a tile
            @(posedge clk); #1;
            exp_orient = lfsr_out;
            rotate = 1'b1;
            check_state("rotate during reset");
            @(posedge clk); #1;
            rotate = 1'b0; resetn = 1'b1;
            check_state("reset released");
            // enable does not gate the reset
            enable = 1'b0;
            do_reset;
            check_state("reset while disabled");
            enable = 1'b1;
        end
    endtask

    // =========================================================== 5. rotation
    task test_rotation;
        integer j, k;
        begin
            tb_case_begin("rotation of every tile");
            // level 3 uses every piece type; start from a board that is not solved
            level = 2'd3; enable = 1'b1;
            deposit_orient(32'h0000_0000);
            check_state("start");
            tb_check_eq(victory, 1'b0, "start board is not solved");
            for (j = 0; j < 16; j = j + 1)
                for (k = 0; k < 4; k = k + 1) begin
                    rotate_tile(j);
                    $sformat(msg, "tile %0d turn %0d", j, k + 1);
                    check_state(msg);
                end
            tb_check_eq(dut.pipe_orientation, exp_orient, "four turns of every tile restore the board");

            tb_case_begin("rotate while disabled re-randomises");
            enable = 1'b0;
            for (k = 0; k < 5; k = k + 1) begin
                rotate_tile({$random(tb_seed)} % 16);
                check_state("disabled rotate");
            end
            enable = 1'b1;

            tb_case_begin("rotate needs an edge");
            // holding rotate high for many clocks is still a single turn
            deposit_orient(32'h0000_0000);
            @(posedge clk); #1;
            sw = 4'b00_00; rotate = 1'b1;
            exp_orient[1:0] = 2'd1;
            repeat (10) @(posedge clk);
            #1; rotate = 1'b0;
            check_state("long rotate pulse");
            // changing the selection alone never turns anything
            for (j = 0; j < 16; j = j + 1) begin
                sw = j; #1;
                check_state("selection change");
            end
        end
    endtask

    // ===================================================== 6. flow, directed
    // Hand-computed boards. These do not depend on the golden model, so they
    // also guard the model itself.
    task directed(input [63:0] b, input [15:0] exp_wet, input [15:0] exp_leak,
                  input exp_victory, input [8*40-1:0] what);
        begin
            forced_board = b; #1;
            $sformat(msg, "%0s: wet tiles", what);
            tb_check_eq(wet, exp_wet, msg);
            $sformat(msg, "%0s: leaking tiles", what);
            tb_check_eq(leak, exp_leak, msg);
            $sformat(msg, "%0s: victory", what);
            tb_check_eq(victory, exp_victory, msg);
            check_outputs(b, what);                 // and the model agrees
        end
    endtask

    // opening nibbles {N, E, S, W}
    localparam [3:0] EW = 4'b0101, NS = 4'b1010, SW_ = 4'b0011, NW = 4'b1001,
                     NE = 4'b1100, ES = 4'b0110, ESW = 4'b0111, ALL = 4'b1111;

    function [63:0] with_tile(input [63:0] b, input integer j, input [3:0] openings);
        begin
            with_tile = b;
            with_tile[4*j +: 4] = openings;
        end
    endfunction

    task test_flow_directed;
        reg [63:0] b, path;
        begin
            tb_case_begin("flow, directed boards");
            force dut.pipe_opening_state = forced_board;

            directed(64'b0, 16'h0000, 16'h0000, 1'b0, "empty board");

            b = with_tile(64'b0, 0, 4'b0001);
            directed(b, 16'h0001, 16'h0000, 1'b0, "inlet only");

            b = with_tile(64'b0, 0, 4'b0100);
            b = with_tile(b, 1, 4'b0001);
            directed(b, 16'h0000, 16'h0000, 1'b0, "inlet closed");

            b = with_tile(64'b0, 0, NW);
            directed(b, 16'h0001, 16'h0001, 1'b0, "leak at the top edge");

            b = with_tile(64'b0, 0, SW_);
            directed(b, 16'h0001, 16'h0001, 1'b0, "leak into a closed neighbour");
            b = with_tile(b, 4, 4'b1000);
            directed(b, 16'h0011, 16'h0000, 1'b0, "neighbour opened");
            b = with_tile(b, 4, 4'b1001);
            directed(b, 16'h0011, 16'h0010, 1'b0, "leak at the left edge");
            b = with_tile(b, 4, 4'b1010);
            b = with_tile(b, 8, 4'b1010);
            b = with_tile(b, 12, 4'b1010);
            directed(b, 16'h1111, 16'h1000, 1'b0, "leak at the bottom edge");

            // inlet -> along the top row -> down the right column -> outlet
            path = 64'b0;
            path = with_tile(path, 0, EW);
            path = with_tile(path, 1, EW);
            path = with_tile(path, 2, EW);
            path = with_tile(path, 3, SW_);
            path = with_tile(path, 7, NS);
            path = with_tile(path, 11, NS);
            path = with_tile(path, 15, NE);
            directed(path, 16'h888F, 16'h0000, 1'b1, "simple solved path");

            b = with_tile(path, 15, 4'b1000);
            directed(b, 16'h888F, 16'h0000, 1'b0, "outlet shut");

            b = with_tile(path, 15, 4'b1110);
            directed(b, 16'h888F, 16'h8000, 1'b0, "leak below the outlet");

            b = with_tile(path, 1, ESW);
            directed(b, 16'h888F, 16'h0002, 1'b0, "solved path with a side leak");
            b = with_tile(b, 5, 4'b1000);
            directed(b, 16'h88AF, 16'h0000, 1'b1, "side branch capped");

            b = with_tile(path, 7, 4'b1110);
            directed(b, 16'h888F, 16'h0080, 1'b0, "leak at the right edge");

            b = with_tile(path, 2, 4'b0000);
            directed(b, 16'h0003, 16'h0002, 1'b0, "path broken");

            // every tile on one path: the longest possible flow (15 hops)
            b = 64'b0;
            b = with_tile(b, 0, EW);   b = with_tile(b, 1, EW);
            b = with_tile(b, 2, EW);   b = with_tile(b, 3, SW_);
            b = with_tile(b, 7, NW);   b = with_tile(b, 6, EW);
            b = with_tile(b, 5, EW);   b = with_tile(b, 4, ES);
            b = with_tile(b, 8, NE);   b = with_tile(b, 9, EW);
            b = with_tile(b, 10, EW);  b = with_tile(b, 11, SW_);
            b = with_tile(b, 15, NW);  b = with_tile(b, 14, EW);
            b = with_tile(b, 13, EW);  b = with_tile(b, 12, 4'b0100);
            directed(b, 16'hFFFF, 16'h0000, 1'b0, "serpentine through all 16 tiles");

            // the same path cut one tile before its end
            b = with_tile(b, 13, 4'b0100);
            directed(b, 16'hEFFF, 16'h0000, 1'b0, "serpentine, last tile cut off");

            // all crosses: everything wet, every edge tile leaks
            directed({16{ALL}}, 16'hFFFF, 16'hF99F, 1'b0, "all crosses");

            // a closed loop next to the inlet, nothing leaks, outlet never reached
            b = 64'b0;
            b = with_tile(b, 0, ESW);  b = with_tile(b, 1, SW_);
            b = with_tile(b, 4, NE);   b = with_tile(b, 5, NW);
            directed(b, 16'h0033, 16'h0000, 1'b0, "closed loop");

            release dut.pipe_opening_state;
        end
    endtask

    // ======================================================= 7. flow, random
    task test_flow_random;
        integer    n;
        reg [63:0] b;
        begin
            tb_case_begin("flow, random forced boards");
            force dut.pipe_opening_state = forced_board;
            for (n = 0; n < N_RANDOM_BOARDS; n = n + 1) begin
                // three densities of openings (25 %, 50 %, 75 %): sparse boards
                // stress leaks near the inlet, dense boards reach the far corner
                case (n % 3)
                    0: b = random64(0) & random64(0);
                    1: b = random64(0);
                    2: b = random64(0) | random64(0);
                endcase
                if (n % 8 != 0) b[0] = 1'b1;            // usually open the inlet
                forced_board = b; #1;
                check_outputs(b, "random board");
            end
            release dut.pipe_opening_state;
        end
    endtask

    // ===================================================== 8. levels, random
    task test_levels_random;
        integer lv, n;
        begin
            tb_case_begin("random orientations on every level");
            enable = 1'b1;
            for (lv = 1; lv < 4; lv = lv + 1) begin
                level = lv;
                for (n = 0; n < N_RANDOM_ORIENTS; n = n + 1) begin
                    deposit_orient($random(tb_seed));
                    check_state("random orientation");
                end
            end
        end
    endtask

    // ==================================================== 9. play to victory
    // Orientation word that realises the first solver network, with the tiles
    // outside the network taken from `filler`.
    function [31:0] solved_orient(input [47:0] types, input [31:0] filler);
        integer j;
        begin
            solved_orient = filler;
            for (j = 0; j < 16; j = j + 1)
                if (ref_sol_net[j])
                    solved_orient[2*j +: 2] = filler[2*j +: 2] +
                        ref_turns_needed(types[3*j +: 3], filler[2*j +: 2], ref_sol_board[4*j +: 4]);
        end
    endfunction

    task test_play_level(input integer lv);
        integer    j, k, turns, tries;
        reg [31:0] solved, perturbed;
        reg [2:0]  t;
        begin
            $sformat(msg, "play level %0d to victory", lv);
            tb_case_begin(msg);
            level = lv; enable = 1'b1;
            ref_solve(level_types[lv]);

            // a fresh random board, as after pressing R (skip the rare solved one)
            do_reset; check_state("fresh board");
            tries = 0;
            while (victory && tries < 10) begin
                do_reset; check_state("fresh board");
                tries = tries + 1;
            end
            tb_check_eq(victory, 1'b0, "board is not solved before playing");

            // turn the tiles of the solution network into place, one click at a time
            for (j = 0; j < 16; j = j + 1)
                if (ref_sol_net[j] && !victory) begin
                    t     = level_types[lv][3*j +: 3];
                    turns = ref_turns_needed(t, exp_orient[2*j +: 2], ref_sol_board[4*j +: 4]);
                    tb_check(turns < 4, "solution uses a shape the tile can take");
                    for (k = 0; k < turns; k = k + 1) begin
                        rotate_tile(j);
                        check_state("solving");
                    end
                end
            tb_check_eq(victory, 1'b1, "victory once the network is complete");
            tb_check_eq(leak, 16'b0, "no leak on the solved board");
            tb_cov_hit(cov_win_level + lv - 1);

            // a solved board is frozen: no tile can be turned any more
            solved = exp_orient;
            for (j = 0; j < 16; j = j + 1) begin
                rotate_tile(j);
                check_state("rotation after victory");
            end
            tb_check_eq(dut.pipe_orientation, solved, "solved board did not change");

            // one tile of the network turned away breaks the solution
            for (j = 0; j < 16; j = j + 1)
                if (ref_sol_net[j])
                    for (k = 1; k < 4; k = k + 1) begin
                        perturbed = solved;
                        perturbed[2*j +: 2] = solved[2*j +: 2] + k;
                        deposit_orient(perturbed);
                        check_state("one tile turned away");
                        if (!victory) tb_cov_hit(cov_lost);
                        t = level_types[lv][3*j +: 3];
                        if (ref_opening(t, exp_orient[2*j +: 2]) != ref_sol_board[4*j +: 4] && ref_sol_count == 1)
                            tb_check_eq(victory, 1'b0, "a wrong tile on the only solution loses the victory");
                    end

            // the solution holds whatever the tiles outside the network do
            for (k = 0; k < 200; k = k + 1) begin
                deposit_orient(solved_orient(level_types[lv], $random(tb_seed)));
                check_state("solution with random filler");
                tb_check_eq(victory, 1'b1, "tiles outside the network do not matter");
            end

            // R (reset) on a solved board gives a new random board
            do_reset;
            check_state("reset after victory");
        end
    endtask

    // ================================================================== main
    initial begin
        tb_start;
        tb_cov_group(cov_rotate,     "tile turned",                    16);
        tb_cov_group(cov_wrap,       "orientation wrapped 3 -> 0",      1);
        tb_cov_group(cov_locked,     "turn refused on a solved board",  1);
        tb_cov_group(cov_reset,      "board randomised by reset",       1);
        tb_cov_group(cov_rerandom,   "board randomised while disabled", 1);
        tb_cov_group(cov_side,       "leak (or port) on tile*4+side",  64);
        tb_cov_group(cov_wet,        "tile wet",                       16);
        tb_cov_group(cov_wet_count,  "wet tiles 0/1/2-8/9-15/16",       5);
        tb_cov_group(cov_leak_count, "leaking tiles 0/1/many",          3);
        tb_cov_group(cov_outcome,    "win/dry/leak/outlet shut",        4);
        tb_cov_group(cov_win_level,  "victory on level",                3);
        tb_cov_group(cov_lost,       "victory lost by one turn",        1);

        level_types[0] = 48'b0;
        level_types[1] = `PIPE_LEVEL1_TYPES(dut);
        level_types[2] = `PIPE_LEVEL2_TYPES(dut);
        level_types[3] = `PIPE_LEVEL3_TYPES(dut);

        test_lfsr;
        test_opening_table;
        test_level_maps;
        test_reset;
        test_rotation;
        test_flow_directed;
        test_flow_random;
        test_levels_random;
        test_play_level(1);
        test_play_level(2);
        test_play_level(3);
        tb_finish;
    end

endmodule
