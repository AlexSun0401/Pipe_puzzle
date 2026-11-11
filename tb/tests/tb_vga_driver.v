`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_vga_driver.v -- unit testbench for rtl/video/vga_driver.v and the VGA
// adapter below it (with the simulation models in models/altera_sim_models.v).
//
// Drawing side, checked on every clock cycle at the video-memory write port:
//   address  = the next pixel in raster order
//   data     = the golden renderer (include/vga_ref_model.vh)
//   write    = enable (the title image is never overwritten while disabled)
//
// Display side, checked by a VGA monitor model (models/vga_monitor.v):
//   640x480@60 sync timing, and a complete displayed frame compared pixel by
//   pixel with the golden renderer.
//
//   1. reset and title screen   raster at (0,0), no writes while disabled,
//                               reset in the middle of a frame
//   2. frame B / frame A        two complementary full frames: every opening
//                               pattern, every tile wet / dry / leaking
//   3. random soak              game state changes in the middle of frames
//   4. victory backgrounds      green on levels 1 and 2, purple on level 3
//   5. cursor                   yellow border on each of the 16 tiles
//   6. disable                  mid-frame, writes stop at once
//   7. display                  sync timing and frame A on the VGA pins
// -----------------------------------------------------------------------------
module tb_vga_driver;

    localparam TB_NAME       = "tb_vga_driver";
    localparam TB_TIMEOUT_NS = 400_000_000;
    localparam CLK_PERIOD    = 20;
    localparam PIXELS        = 640 * 480;

    parameter N_SOAK_CYCLES  = 150000;

    reg         clk     = 1'b0;
    reg         resetn  = 1'b1;
    reg  [3:0]  sel     = 4'b0;                 // {x, y} of the cursor tile
    reg  [63:0] board   = 64'b0;
    reg  [15:0] wet     = 16'b0;
    reg  [15:0] leak    = 16'b0;
    reg         enable  = 1'b0;
    reg         victory = 1'b0;
    reg  [1:0]  level   = 2'd0;
    wire [7:0]  VGA_R, VGA_G, VGA_B;
    wire        VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK;

    always #(CLK_PERIOD/2) clk = ~clk;

    vga_driver dut (clk, resetn, sel, board, wet, leak, enable,
                    VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK,
                    victory, level);

    vga_monitor mon (VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_R, VGA_G, VGA_B);

    `include "tb_util.vh"
    `include "vga_ref_model.vh"

    // Write port of the video memory inside the adapter.
    `define VRAM dut.VGA.VideoMemory

    reg [8*120-1:0] msg;
    integer cov_class, cov_open, cov_sel, cov_wet, cov_leak, cov_wrap;

    // ------------------------------------------------- raster model + checker
    integer exp_x = 0, exp_y = 0;               // pixel the design must write next
    reg     port_check = 1'b0;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            exp_x = 0; exp_y = 0;
        end else if (exp_x == REF_RES_X - 1) begin
            exp_x = 0;
            if (exp_y == REF_RES_Y - 1) begin
                exp_y = 0;
                tb_cov_hit(cov_wrap);
            end else exp_y = exp_y + 1;
        end else exp_x = exp_x + 1;
    end

    // Sampled a quarter period after the falling edge: the stimulus (which moves
    // on the falling edge) has settled, and this is what the next rising edge
    // will write.
    always @(negedge clk) begin : port_checker
        reg [8:0] exp_color;
        #(CLK_PERIOD/4);
        if (port_check) begin
            tb_checks = tb_checks + 1;
            if (`VRAM.wren_a !== enable) begin
                $sformat(msg, "write enable is %b with enable = %b at pixel (%0d,%0d)", `VRAM.wren_a, enable, exp_x, exp_y);
                tb_fail(msg);
            end
            if (enable) begin
                exp_color = ref_pixel(exp_x, exp_y, board, wet, leak, sel, victory, level);
                tb_checks = tb_checks + 2;
                if (`VRAM.address_a !== exp_y * REF_RES_X + exp_x) begin
                    $sformat(msg, "write address %0d, expected pixel (%0d,%0d) = %0d", `VRAM.address_a, exp_x, exp_y, exp_y * REF_RES_X + exp_x);
                    tb_fail(msg);
                end
                if (`VRAM.data_a !== exp_color) begin
                    $sformat(msg, "pixel (%0d,%0d) is %o, expected %o (tile %0d, openings %b)", exp_x, exp_y, `VRAM.data_a, exp_color,
                             ref_px_tile, ref_px_tile < 0 ? 4'b0 : board[4*ref_px_tile +: 4]);
                    tb_fail(msg);
                end
                tb_cov_hit(cov_class + ref_px_class);
                if (ref_px_tile >= 0) begin
                    if (ref_px_class == REF_PX_SELECTED) tb_cov_hit(cov_sel  + ref_px_tile);
                    if (ref_px_class == REF_PX_WET)      tb_cov_hit(cov_wet  + ref_px_tile);
                    if (ref_px_class == REF_PX_LEAK)     tb_cov_hit(cov_leak + ref_px_tile);
                    if ((exp_x - REF_H_OFF) % REF_TILE == REF_MID && exp_y % REF_TILE == REF_MID)
                        tb_cov_hit(cov_open + board[4*ref_px_tile +: 4]);
                end
            end
        end
    end

    // ---------------------------------------------------------------- helpers
    task run(input integer cycles);
        begin
            repeat (cycles) @(negedge clk);
        end
    endtask

    // Move the raster to a pixel without waiting for it (back door).
    task jump(input integer x, input integer y);
        begin
            @(negedge clk);
            dut.draw_x = x; dut.draw_y = y;
            exp_x = x;      exp_y = y;
        end
    endtask

    task set_state(input [63:0] b, input [15:0] w, input [15:0] l, input [3:0] s,
                   input v, input [1:0] lv);
        begin
            board = b; wet = w; leak = l; sel = s; victory = v; level = lv;
        end
    endtask

    // Frame A: tile j shows opening pattern j. Frame B is its complement, so
    // every tile is seen wet and dry, leaking and tight, with pipes on it.
    localparam [63:0] BOARD_A = 64'hFEDC_BA98_7654_3210;
    localparam [15:0] WET_A   = 16'hA5C2;
    localparam [15:0] LEAK_A  = 16'h3C5A;
    localparam [3:0]  SEL_A   = 4'b01_10;       // tile 9
    localparam [3:0]  SEL_B   = 4'b10_01;       // tile 6

    // ================================================================ tests
    task test_reset_and_title;
        integer writes_before;
        begin
            tb_case_begin("reset and title screen");
            @(negedge clk); resetn = 1'b0;
            run(4);
            tb_check_eq({dut.draw_x, dut.draw_y}, 19'b0, "raster at (0,0) during reset");
            resetn = 1'b1;
            port_check = 1'b1;
            writes_before = `VRAM.writes;
            set_state(BOARD_A, WET_A, LEAK_A, SEL_A, 1'b0, 2'd0);
            enable = 1'b0;
            run(3000);
            tb_check_eq(`VRAM.writes, writes_before, "no pixel is written while the game is disabled");

            tb_case_begin("reset in the middle of a frame");
            enable = 1'b1;
            run(1777);
            resetn = 1'b0;
            #3;
            tb_check_eq({dut.draw_x, dut.draw_y}, 19'b0, "asynchronous reset returns the raster to (0,0)");
            run(3);
            resetn = 1'b1;
            mon.resync;                                 // the sync pattern restarts with the reset
        end
    endtask

    task test_frame_b;
        begin
            tb_case_begin("frame B: complement of frame A");
            enable = 1'b1;
            set_state(~BOARD_A, ~WET_A, ~LEAK_A, SEL_B, 1'b0, 2'd2);
            run(PIXELS);
        end
    endtask

    task test_soak;
        integer n;
        begin
            tb_case_begin("random soak: state changes mid-frame");
            for (n = 0; n < N_SOAK_CYCLES; n = n + 1) begin
                if (n % 1009 == 0)
                    set_state({$random(tb_seed), $random(tb_seed)}, $random(tb_seed), $random(tb_seed),
                              $random(tb_seed), $random(tb_seed), $random(tb_seed));
                run(1);
            end
        end
    endtask

    task test_victory_backgrounds;
        integer lv;
        begin
            tb_case_begin("victory backgrounds");
            for (lv = 0; lv < 4; lv = lv + 1) begin
                set_state(BOARD_A, WET_A, 16'b0, SEL_A, 1'b1, lv);
                jump(0, 100);  run(2 * REF_RES_X);      // two full lines: margins and board
                jump(600, 479); run(100);               // bottom-right corner and the wrap
                #1;
                $sformat(msg, "left margin colour after a win on level %0d", lv);
                tb_check_eq(`VRAM.data_a, lv == 0 ? REF_BLACK : lv == 3 ? REF_PURPLE : REF_GREEN, msg);
            end
            // without a win the margins are black on every level
            for (lv = 0; lv < 4; lv = lv + 1) begin
                set_state(BOARD_A, WET_A, 16'b0, SEL_A, 1'b0, lv);
                jump(0, 300); run(REF_RES_X);
            end
        end
    endtask

    task test_cursor;
        integer j;
        begin
            tb_case_begin("cursor on every tile");
            for (j = 0; j < 16; j = j + 1) begin
                // leak everywhere: yellow must win over red on the selected tile only
                set_state(BOARD_A, WET_A, 16'hFFFF, {j[1:0], j[3:2]}, 1'b0, 2'd1);
                jump(0, 120 * (j / 4));       run(REF_RES_X);   // top border row of that tile row
                jump(0, 120 * (j / 4) + 60);  run(REF_RES_X);   // a row through the pipes
            end
        end
    endtask

    task test_disable;
        integer writes_before;
        begin
            tb_case_begin("disable in the middle of a frame");
            set_state(BOARD_A, WET_A, LEAK_A, SEL_A, 1'b0, 2'd1);
            jump(300, 200); run(500);
            enable = 1'b0;
            run(1);
            writes_before = `VRAM.writes;
            run(5000);
            tb_check_eq(`VRAM.writes, writes_before, "writes stop as soon as enable falls");
            tb_check(dut.draw_y > 200, "the raster keeps scanning while disabled");
            enable = 1'b1;
        end
    endtask

    task test_display;
        integer   x, y, mismatches;
        reg [8:0] exp_color;
        time      painted;
        realtime  t0, t1;
        begin
            tb_case_begin("frame A: every opening pattern");
            set_state(BOARD_A, WET_A, LEAK_A, SEL_A, 1'b0, 2'd1);
            enable = 1'b1;
            run(PIXELS + 10);                           // every pixel repainted with frame A
            port_check = 1'b0;                          // the write port is proven; save time
            painted = $time;

            tb_case_begin("display: sync timing and frame A on the pins");
            @(mon.frame_done);                          // a frame that began after the repaint
            while (mon.frame_start < painted) @(mon.frame_done);

            mismatches = 0;
            for (y = 0; y < REF_RES_Y; y = y + 1)
                for (x = 0; x < REF_RES_X; x = x + 1) begin
                    exp_color = ref_pixel(x, y, board, wet, leak, sel, victory, level);
                    if (mon.frame[y * REF_RES_X + x] !== exp_color) begin
                        mismatches = mismatches + 1;
                        if (mismatches <= 5)
                            $display("    displayed pixel (%0d,%0d) is %o, expected %o", x, y, mon.frame[y * REF_RES_X + x], exp_color);
                    end
                end
            tb_check_eq(mismatches, 0, "pixels of the displayed frame that differ from the golden frame");

            tb_check_eq(mon.meas_h_active, 640, "active pixels per line");
            tb_check_eq(mon.meas_h_total,  800, "pixel clocks per line");
            tb_check_eq(mon.meas_h_sync,    96, "HSYNC width");
            tb_check_eq(mon.meas_v_active, 480, "active lines per frame");
            tb_check_eq(mon.meas_v_total,  525, "lines per frame");
            tb_check_eq(mon.meas_v_sync,     2, "VSYNC width in lines");
            tb_check_eq(mon.errors,          0, "errors reported by the VGA monitor");
            tb_check_eq(VGA_SYNC_N, 1'b1, "VGA_SYNC_N is tied high");
            $display("    measured: H %0d active + %0d front + %0d sync, %0d total; V %0d active + %0d front + %0d sync, %0d total",
                     mon.meas_h_active, mon.meas_h_front, mon.meas_h_sync, mon.meas_h_total,
                     mon.meas_v_active, mon.meas_v_front, mon.meas_v_sync, mon.meas_v_total);

            // 25 MHz pixel clock: 60 frames per second with the totals above
            @(posedge VGA_CLK); t0 = $realtime;
            @(posedge VGA_CLK); t1 = $realtime;
            tb_check(t1 - t0 == 2.0 * CLK_PERIOD, "VGA_CLK is CLOCK_50 divided by two");
        end
    endtask

    // ================================================================== main
    initial begin
        tb_start;
        tb_cov_group(cov_class, "pixel class drawn",              REF_PX_CLASSES);
        tb_cov_group(cov_open,  "opening pattern drawn",          16);
        tb_cov_group(cov_sel,   "yellow border on tile",          16);
        tb_cov_group(cov_wet,   "blue pipe on tile",              16);
        tb_cov_group(cov_leak,  "red border on tile",             16);
        tb_cov_group(cov_wrap,  "raster wrapped to a new frame",   1);

        test_reset_and_title;
        test_frame_b;
        test_soak;
        test_victory_backgrounds;
        test_cursor;
        test_disable;
        test_display;
        tb_finish;
    end

endmodule
