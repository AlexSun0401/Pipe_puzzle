// -----------------------------------------------------------------------------
// seg7_ref_model.vh -- golden seven-segment patterns for the DE1-SoC displays.
// `include inside a testbench module.
//
// A display is 7 bits, bit 0 = segment a ... bit 6 = segment g, active low.
// The patterns are built from the list of segments that are lit, not copied
// from the design.
// -----------------------------------------------------------------------------

localparam [6:0] SEG_BLANK = 7'b111_1111;
localparam [6:0] SEG_DASH  = 7'b011_1111;      // only segment g

// Pattern of a decimal digit; anything above 9 is shown as a dash.
function [6:0] seg_of(input integer digit);
    reg [6:0] lit;
    begin
        case (digit)
            0: lit = 7'b0111111;                // a b c d e f
            1: lit = 7'b0000110;                //   b c
            2: lit = 7'b1011011;                // a b   d e   g
            3: lit = 7'b1001111;                // a b c d     g
            4: lit = 7'b1100110;                //   b c     f g
            5: lit = 7'b1101101;                // a   c d   f g
            6: lit = 7'b1111101;                // a   c d e f g
            7: lit = 7'b0000111;                // a b c
            8: lit = 7'b1111111;
            9: lit = 7'b1101111;                // a b c d   f g
            default: lit = 7'b1000000;          // g
        endcase
        seg_of = ~lit;
    end
endfunction

// Reads a display back: 0..9, 10 for a dash, 11 for blank, -1 for anything else.
function integer seg_to_digit(input [6:0] seg);
    integer d;
    begin
        seg_to_digit = -1;
        for (d = 0; d <= 9; d = d + 1)
            if (seg === seg_of(d)) seg_to_digit = d;
        if (seg === SEG_DASH)  seg_to_digit = 10;
        if (seg === SEG_BLANK) seg_to_digit = 11;
    end
endfunction

// Reads a pair of displays as seconds: 0..99, 100 for "--", -1 if blank or invalid.
function integer seg_to_seconds(input [6:0] tens, input [6:0] ones);
    integer t, o;
    begin
        t = seg_to_digit(tens);
        o = seg_to_digit(ones);
        if (t == 10 && o == 10)                         seg_to_seconds = 100;
        else if (t >= 0 && t <= 9 && o >= 0 && o <= 9)  seg_to_seconds = 10 * t + o;
        else                                            seg_to_seconds = -1;
    end
endfunction
