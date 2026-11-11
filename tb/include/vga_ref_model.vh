// -----------------------------------------------------------------------------
// vga_ref_model.vh -- golden renderer for rtl/video/vga_driver.v.
// `include inside a testbench module.
//
// ref_pixel returns the 9-bit colour {R[2:0], G[2:0], B[2:0]} that the game
// must write to pixel (x, y) of the 640x480 frame for a given game state.
//
// Screen layout:
//   - The board is 4x4 tiles of 120x120 pixels at x = 80..559, y = 0..479.
//   - Each tile has a 2-pixel border: yellow on the selected tile, otherwise
//     red if the tile leaks, otherwise white. The border is drawn over pipes.
//   - Pipes are grey, or blue when wet: a centre square plus one arm per
//     opening. The arms and the square span local coordinates 53..67, i.e.
//     15 pixels (PIPE_THICKNESS is 16 with both bounds exclusive in the RTL).
//   - Outside the board the screen is black, green after a win on level 1 or
//     2, and purple after a win on level 3.
// -----------------------------------------------------------------------------

localparam REF_RES_X  = 640;
localparam REF_RES_Y  = 480;
localparam REF_TILE   = 120;
localparam REF_H_OFF  = 80;
localparam REF_BORDER = 2;
localparam REF_MID    = 60;     // centre line of a tile
localparam REF_HALF   = 8;      // pipes cover MID-HALF < coordinate < MID+HALF

localparam [8:0] REF_GREEN  = 9'b000_111_000;
localparam [8:0] REF_BLUE   = 9'b000_000_110;
localparam [8:0] REF_RED    = 9'b111_000_000;
localparam [8:0] REF_PURPLE = 9'b111_000_111;
localparam [8:0] REF_YELLOW = 9'b111_111_000;
localparam [8:0] REF_GRAY   = 9'b011_011_011;
localparam [8:0] REF_BLACK  = 9'b000_000_000;
localparam [8:0] REF_WHITE  = 9'b111_111_111;

// Pixel classes, for coverage.
localparam REF_PX_OUTSIDE = 0, REF_PX_WIN12 = 1, REF_PX_WIN3 = 2, REF_PX_BORDER = 3,
           REF_PX_SELECTED = 4, REF_PX_LEAK = 5, REF_PX_WET = 6, REF_PX_DRY = 7,
           REF_PX_TILE = 8, REF_PX_CLASSES = 9;

integer ref_px_class;           // class of the last pixel computed by ref_pixel
integer ref_px_tile;            // its tile index, or -1 outside the board

function [8:0] ref_pixel(input integer x, input integer y,
                         input [63:0] board, input [15:0] wet, input [15:0] leak,
                         input [3:0] selected,        // {x, y} of the cursor tile
                         input victory, input [1:0] level);
    integer   tx, ty, lx, ly, j;
    reg [3:0] o;
    reg       mid_x, mid_y, on_pipe, on_border;
    begin
        if (x >= REF_H_OFF && x < REF_H_OFF + 4*REF_TILE && y >= 0 && y < 4*REF_TILE) begin
            tx = (x - REF_H_OFF) / REF_TILE;
            ty = y / REF_TILE;
            lx = (x - REF_H_OFF) % REF_TILE;
            ly = y % REF_TILE;
            j  = 4*ty + tx;
            o  = board[4*j +: 4];
            ref_px_tile = j;
            on_border = lx < REF_BORDER || lx >= REF_TILE - REF_BORDER ||
                        ly < REF_BORDER || ly >= REF_TILE - REF_BORDER;
            mid_x   = lx > REF_MID - REF_HALF && lx < REF_MID + REF_HALF;
            mid_y   = ly > REF_MID - REF_HALF && ly < REF_MID + REF_HALF;
            on_pipe = (o != 4'b0 && mid_x && mid_y) ||
                      (o[3] && mid_x && ly < REF_MID) ||       // north arm
                      (o[2] && mid_y && lx > REF_MID) ||       // east arm
                      (o[1] && mid_x && ly > REF_MID) ||       // south arm
                      (o[0] && mid_y && lx < REF_MID);         // west arm
            if (on_border) begin
                if (tx == selected[3:2] && ty == selected[1:0]) begin
                    ref_pixel = REF_YELLOW; ref_px_class = REF_PX_SELECTED;
                end else if (leak[j]) begin
                    ref_pixel = REF_RED;    ref_px_class = REF_PX_LEAK;
                end else begin
                    ref_pixel = REF_WHITE;  ref_px_class = REF_PX_BORDER;
                end
            end else if (on_pipe) begin
                if (wet[j]) begin
                    ref_pixel = REF_BLUE;   ref_px_class = REF_PX_WET;
                end else begin
                    ref_pixel = REF_GRAY;   ref_px_class = REF_PX_DRY;
                end
            end else begin
                ref_pixel = REF_BLACK;      ref_px_class = REF_PX_TILE;
            end
        end else begin
            ref_px_tile = -1;
            if (victory && (level == 2'd1 || level == 2'd2)) begin
                ref_pixel = REF_GREEN;      ref_px_class = REF_PX_WIN12;
            end else if (victory && level == 2'd3) begin
                ref_pixel = REF_PURPLE;     ref_px_class = REF_PX_WIN3;
            end else begin
                ref_pixel = REF_BLACK;      ref_px_class = REF_PX_OUTSIDE;
            end
        end
    end
endfunction
