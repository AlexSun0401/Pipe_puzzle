// -----------------------------------------------------------------------------
// pipe_ref_model.vh -- golden model of the pipe rules, written independently of
// rtl/game/pipe_manager.v. `include inside a testbench module.
//
// Conventions (same as the design):
//   tile index      j = 4*y + x          x = column 0..3, y = row 0..3
//   opening nibble  {N, E, S, W} = bits [3:0]
//   board state     64 bits, tile j in bits [4*j+3 : 4*j]
//   orientations    32 bits, tile j in bits [2*j+1 : 2*j]; +1 = 90 deg clockwise
//   tile types      48 bits, tile j in bits [3*j+2 : 3*j]
//
// Rules being modelled:
//   - Water enters tile 0 through its west side and must leave tile 15 through
//     its east side.
//   - Water passes between two neighbours only if both open towards each other.
//   - A wet tile leaks if one of its openings faces a closed neighbour or the
//     edge of the board (the inlet and the outlet do not count).
//   - Victory: tile 15 is wet, its east side is open, and nothing leaks.
// -----------------------------------------------------------------------------

localparam [2:0] REF_EMPTY    = 3'd0;
localparam [2:0] REF_STRAIGHT = 3'd1;
localparam [2:0] REF_L        = 3'd2;
localparam [2:0] REF_T        = 3'd3;
localparam [2:0] REF_CROSS    = 3'd4;

localparam REF_W = 0, REF_S = 1, REF_E = 2, REF_N = 3;   // bit index of each side
localparam REF_NONE = 16;                                 // "no neighbour"

// One quarter turn clockwise: N->E, E->S, S->W, W->N.
function [3:0] ref_rot_cw(input [3:0] o);
    begin
        ref_rot_cw = {o[0], o[3:1]};
    end
endfunction

// Openings of a tile: the shape at orientation 0, turned `orient` quarter turns.
function [3:0] ref_opening(input [2:0] tile_type, input [1:0] orient);
    reg [3:0] shape;
    integer   k;
    begin
        case (tile_type)
            REF_STRAIGHT: shape = 4'b0101;   // E + W
            REF_L:        shape = 4'b0110;   // E + S
            REF_T:        shape = 4'b0111;   // E + S + W
            REF_CROSS:    shape = 4'b1111;
            default:      shape = 4'b0000;   // empty and undefined codes
        endcase
        for (k = 0; k < orient; k = k + 1) shape = ref_rot_cw(shape);
        ref_opening = shape;
    end
endfunction

// Neighbour of tile j on the given side, or REF_NONE at the edge of the board.
function integer ref_nbr(input integer j, input integer side);
    integer x, y;
    begin
        x = j % 4;
        y = j / 4;
        ref_nbr = REF_NONE;
        case (side)
            REF_N: if (y > 0) ref_nbr = j - 4;
            REF_E: if (x < 3) ref_nbr = j + 1;
            REF_S: if (y < 3) ref_nbr = j + 4;
            REF_W: if (x > 0) ref_nbr = j - 1;
        endcase
    end
endfunction

function integer ref_opposite(input integer side);
    begin
        ref_opposite = (side + 2) % 4;
    end
endfunction

// True for the two openings that face the edge of the board on purpose.
function ref_is_port(input integer j, input integer side);
    begin
        ref_is_port = (j == 0 && side == REF_W) || (j == 15 && side == REF_E);
    end
endfunction

// Board state from tile types and orientations.
function [63:0] ref_board(input [47:0] types, input [31:0] orient);
    integer j;
    begin
        for (j = 0; j < 16; j = j + 1)
            ref_board[4*j +: 4] = ref_opening(types[3*j +: 3], orient[2*j +: 2]);
    end
endfunction

// Which side of which tile causes a leak: bit [4*j + side]. ref_eval also leaves
// its result in ref_last_leak_sides for coverage sampling.
function [63:0] ref_leak_sides(input [63:0] board, input [15:0] wet);
    integer j, side, n;
    begin
        ref_leak_sides = 64'b0;
        for (j = 0; j < 16; j = j + 1)
            if (wet[j])
                for (side = 0; side < 4; side = side + 1)
                    if (board[4*j + side]) begin
                        n = ref_nbr(j, side);
                        if (n == REF_NONE) begin
                            if (!ref_is_port(j, side)) ref_leak_sides[4*j + side] = 1'b1;
                        end else if (!board[4*n + ref_opposite(side)]) begin
                            ref_leak_sides[4*j + side] = 1'b1;
                        end
                    end
    end
endfunction

// Flood fill to a fixed point (the design uses a fixed number of passes).
function [15:0] ref_wet(input [63:0] board);
    integer j, side, n;
    reg     changed;
    begin
        ref_wet = 16'b0;
        if (board[REF_W]) ref_wet[0] = 1'b1;
        changed = 1'b1;
        while (changed) begin
            changed = 1'b0;
            for (j = 0; j < 16; j = j + 1)
                if (ref_wet[j])
                    for (side = 0; side < 4; side = side + 1)
                        if (board[4*j + side]) begin
                            n = ref_nbr(j, side);
                            if (n != REF_NONE && !ref_wet[n] && board[4*n + ref_opposite(side)]) begin
                                ref_wet[n] = 1'b1;
                                changed    = 1'b1;
                            end
                        end
        end
    end
endfunction

reg [63:0] ref_last_leak_sides;

task ref_eval(input [63:0] board, output [15:0] wet, output [15:0] leak, output victory);
    integer j;
    begin
        wet = ref_wet(board);
        ref_last_leak_sides = ref_leak_sides(board, wet);
        for (j = 0; j < 16; j = j + 1) leak[j] = |ref_last_leak_sides[4*j +: 4];
        victory = wet[15] && board[4*15 + REF_E] && (leak == 16'b0);
    end
endtask

// -----------------------------------------------------------------------------
// Solver: enumerates every leak-free network that joins the inlet to the outlet
// for a given set of tile types. Tiles outside the network are don't-care.
// It grows the network from the inlet; each tile that a network tile opens
// towards must join, with an orientation that agrees with all of its network
// neighbours and does not face the edge of the board.
//
// Results: ref_sol_count networks found; the first one is kept in
//   ref_sol_net    tiles that belong to the network
//   ref_sol_board  their openings (other tiles 0)
// -----------------------------------------------------------------------------
integer    ref_sol_count;
reg [15:0] ref_sol_net;
reg [63:0] ref_sol_board;

task automatic ref_solve_step(input [47:0] types, input [15:0] net,
                              input [15:0] pending, input [63:0] board);
    integer    j, o, side, n, earlier;
    reg [3:0]  shape;
    reg [15:0] next_pending;
    reg [63:0] next_board;
    reg        ok;
    begin
        if (pending == 16'b0) begin
            if (net[15] && board[4*15 + REF_E]) begin
                if (ref_sol_count == 0) begin
                    ref_sol_net   = net;
                    ref_sol_board = board;
                end
                ref_sol_count = ref_sol_count + 1;
            end
        end else begin
            j = 0;
            while (!pending[j]) j = j + 1;
            for (o = 0; o < 4; o = o + 1) begin
                shape = ref_opening(types[3*j +: 3], o);
                ok    = 1'b1;
                // a shape that an earlier orientation already produced is a duplicate
                for (earlier = 0; earlier < o; earlier = earlier + 1)
                    if (ref_opening(types[3*j +: 3], earlier) == shape) ok = 1'b0;
                if (j == 0 && !shape[REF_W]) ok = 1'b0;      // the inlet must be open
                next_pending    = pending;
                next_pending[j] = 1'b0;
                for (side = 0; side < 4; side = side + 1) begin
                    n = ref_nbr(j, side);
                    if (n == REF_NONE) begin
                        if (shape[side] && !ref_is_port(j, side)) ok = 1'b0;
                    end else if (net[n]) begin
                        if (shape[side] != board[4*n + ref_opposite(side)]) ok = 1'b0;
                    end else if (shape[side]) begin
                        next_pending[n] = 1'b1;
                    end
                end
                if (ok) begin
                    next_board            = board;
                    next_board[4*j +: 4]  = shape;
                    ref_solve_step(types, net | (16'b1 << j), next_pending, next_board);
                end
            end
        end
    end
endtask

task ref_solve(input [47:0] types);
    begin
        ref_sol_count = 0;
        ref_sol_net   = 16'b0;
        ref_sol_board = 64'b0;
        ref_solve_step(types, 16'b0, 16'h0001, 64'b0);
    end
endtask

// Quarter turns needed to bring a tile from `orient` to the wanted openings,
// or 4 if the tile type cannot produce them.
function integer ref_turns_needed(input [2:0] tile_type, input [1:0] orient, input [3:0] wanted);
    integer k;
    begin
        ref_turns_needed = 4;
        for (k = 3; k >= 0; k = k - 1)
            if (ref_opening(tile_type, orient + k) == wanted) ref_turns_needed = k;
    end
endfunction

// -----------------------------------------------------------------------------
// Access to the level tables inside a pipe_manager instance P. The result is a
// 48-bit type vector with tile j = 4*y + x in bits [3*j+2 : 3*j]; tile (x, y)
// is called pipe_type_<x><y> in the design. The level parameters must stay
// sized (3 bits) for the concatenations to be legal.
// -----------------------------------------------------------------------------
`define PIPE_LEVEL1_TYPES(P) \
    { P.L1_pipe_type_33, P.L1_pipe_type_23, P.L1_pipe_type_13, P.L1_pipe_type_03, \
      P.L1_pipe_type_32, P.L1_pipe_type_22, P.L1_pipe_type_12, P.L1_pipe_type_02, \
      P.L1_pipe_type_31, P.L1_pipe_type_21, P.L1_pipe_type_11, P.L1_pipe_type_01, \
      P.L1_pipe_type_30, P.L1_pipe_type_20, P.L1_pipe_type_10, P.L1_pipe_type_00 }
`define PIPE_LEVEL2_TYPES(P) \
    { P.L2_pipe_type_33, P.L2_pipe_type_23, P.L2_pipe_type_13, P.L2_pipe_type_03, \
      P.L2_pipe_type_32, P.L2_pipe_type_22, P.L2_pipe_type_12, P.L2_pipe_type_02, \
      P.L2_pipe_type_31, P.L2_pipe_type_21, P.L2_pipe_type_11, P.L2_pipe_type_01, \
      P.L2_pipe_type_30, P.L2_pipe_type_20, P.L2_pipe_type_10, P.L2_pipe_type_00 }
`define PIPE_LEVEL3_TYPES(P) \
    { P.L3_pipe_type_33, P.L3_pipe_type_23, P.L3_pipe_type_13, P.L3_pipe_type_03, \
      P.L3_pipe_type_32, P.L3_pipe_type_22, P.L3_pipe_type_12, P.L3_pipe_type_02, \
      P.L3_pipe_type_31, P.L3_pipe_type_21, P.L3_pipe_type_11, P.L3_pipe_type_01, \
      P.L3_pipe_type_30, P.L3_pipe_type_20, P.L3_pipe_type_10, P.L3_pipe_type_00 }
// The types currently selected by the level input (output of the level mux).
`define PIPE_ACTIVE_TYPES(P) \
    { P.pipe_type_33, P.pipe_type_23, P.pipe_type_13, P.pipe_type_03, \
      P.pipe_type_32, P.pipe_type_22, P.pipe_type_12, P.pipe_type_02, \
      P.pipe_type_31, P.pipe_type_21, P.pipe_type_11, P.pipe_type_01, \
      P.pipe_type_30, P.pipe_type_20, P.pipe_type_10, P.pipe_type_00 }
