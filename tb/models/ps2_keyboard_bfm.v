`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// ps2_keyboard_bfm.v -- bus-functional model of a PS/2 keyboard (device side)
//
// Drives PS2_CLK and PS2_DAT open-drain, as a real keyboard does: it only ever
// pulls a line low or releases it. The testbench must put a pull-up on both
// lines.
//
// Device-to-host frame, 11 bits, LSB first:
//     start (0), 8 data bits, odd parity, stop (1)
// Data changes while the clock is high and is valid at the falling edge.
// The PS/2 clock is 10 kHz to 16.7 kHz, i.e. a half period of 30 us to 50 us.
// The default below is 40 us (12.5 kHz); simulations that do not care about
// real time can speed it up with set_half_period.
//
// Scan codes are set 2, the power-on default of a PS/2 keyboard:
//     make  = <code>           break = F0 <code>
// -----------------------------------------------------------------------------
module ps2_keyboard_bfm (
    inout wire PS2_CLK,
    inout wire PS2_DAT
);
    parameter HALF_PERIOD_NS = 40_000;

    // scan codes used by the game, plus a few it must ignore
    localparam [7:0] KEY_W = 8'h1D, KEY_A = 8'h1C, KEY_S = 8'h1B, KEY_D = 8'h23,
                     KEY_SPACE = 8'h29, KEY_R = 8'h2D, KEY_ENTER = 8'h5A,
                     CODE_BREAK = 8'hF0, CODE_EXTENDED = 8'hE0;

    reg     clk_low = 1'b0;          // 1 = pull the line low, 0 = release
    reg     dat_low = 1'b0;
    integer half_period_ns;
    integer gap_ns;                  // idle time after each frame
    integer frames_sent = 0;
    reg     busy = 1'b0;

    assign PS2_CLK = clk_low ? 1'b0 : 1'bz;
    assign PS2_DAT = dat_low ? 1'b0 : 1'bz;

    initial begin
        half_period_ns = HALF_PERIOD_NS;
        gap_ns         = 2 * HALF_PERIOD_NS;
    end

    task set_half_period(input integer ns);
        begin
            half_period_ns = ns;
            gap_ns         = 2 * ns;
        end
    endtask

    // Send the first `bits` bits of a raw 11-bit frame {stop, parity, data, start}.
    // Fewer than 11 bits models a transmission that is cut short.
    task send_raw(input [10:0] frame, input integer bits);
        integer i;
        begin
            busy = 1'b1;
            for (i = 0; i < bits; i = i + 1) begin
                dat_low = ~frame[i];             // data changes while the clock is high
                #(half_period_ns);
                clk_low = 1'b1;                  // falling edge: the host samples here
                #(half_period_ns);
                clk_low = 1'b0;
            end
            dat_low = 1'b0;
            #(gap_ns);
            frames_sent = frames_sent + 1;
            busy = 1'b0;
        end
    endtask

    // One correct frame.
    task send_byte(input [7:0] data);
        begin
            send_raw({1'b1, ~^data, data, 1'b0}, 11);
        end
    endtask

    // One frame with selectable parity and stop bits, for error injection.
    task send_byte_with(input [7:0] data, input parity_bit, input stop_bit);
        begin
            send_raw({stop_bit, parity_bit, data, 1'b0}, 11);
        end
    endtask

    task key_make(input [7:0] code);
        begin
            send_byte(code);
        end
    endtask

    task key_break(input [7:0] code);
        begin
            send_byte(CODE_BREAK);
            send_byte(code);
        end
    endtask

    // Press and release a key.
    task key_tap(input [7:0] code);
        begin
            key_make(code);
            key_break(code);
        end
    endtask

    // Press and release an extended key (arrow keys, right Ctrl, ...).
    task key_tap_extended(input [7:0] code);
        begin
            send_byte(CODE_EXTENDED);
            send_byte(code);
            send_byte(CODE_EXTENDED);
            send_byte(CODE_BREAK);
            send_byte(code);
        end
    endtask

    // A spurious falling edge on the clock line (noise or a hot-plug glitch).
    task clock_glitch;
        begin
            clk_low = 1'b1;
            #(half_period_ns);
            clk_low = 1'b0;
            #(half_period_ns);
        end
    endtask

endmodule
