module pipe_puzzle_game(CLOCK_50, KEY, PS2_CLK, PS2_DAT, LEDR, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0, 
VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);

input [3:0] KEY;
input CLOCK_50;
	
output wire [7:0] VGA_R;
output wire [7:0] VGA_G;
output wire [7:0] VGA_B;
output wire VGA_HS;
output wire VGA_VS;
output wire VGA_BLANK_N;
output wire VGA_SYNC_N;
output wire VGA_CLK;
inout wire PS2_CLK, PS2_DAT;

output [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;
output reg [9:0] LEDR = 10'b0;

wire [63:0] pipe_opening_state;
wire [15:0] pipe_connected_to_source;
wire [15:0] pipe_leak;
wire victory;

wire resetn, rotate, key_pressed;

reg enable = 1'b0;

// Enter the next level when current level is completed
reg next_level = 1'b0; // This signal will be passed to pipe manager to reset the pipes
reg [1:0] level = 2'd0;
reg [26:0] delay_counter = 27'd0; // This counter is used for keeping the victory screen for a while

reg restart;

always @ (posedge CLOCK_50) begin
	next_level <= 1'b0;
	restart <= 1'b0;
	// restart the game when KEY[0] is pressed
	if(level != 2'd0 && KEY[0] == 1'b0) begin 
		level <= 2'd1;
		restart <= 1'b1;
	end
	else if(key_pressed && level == 2'd0) begin // press any key to start
		enable <= 1'b1;
		level <= 2'd1;
	end
	else if(level == 2'd1 || level == 2'd2) begin
		if(victory == 1'b1) begin
			if(delay_counter == 27'd100_000_000) begin
				level <= level + 1'b1;
				next_level <= 1'b1; 
				delay_counter <= 27'd0;
			end
			else delay_counter <= delay_counter + 1'b1;
		end
	end
end

wire [3:0] Coordinate_Selected;

ps2_driver k1(CLOCK_50, KEY[0], PS2_CLK, PS2_DAT, Coordinate_Selected[3:2], Coordinate_Selected[1:0], resetn, rotate, key_pressed, next_level);

pipe_manager u1(CLOCK_50, rotate, resetn && (~next_level) && (~restart), Coordinate_Selected, pipe_opening_state, pipe_connected_to_source, pipe_leak, victory, level, enable);

timer t1(CLOCK_50, victory, resetn, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0, level, restart);

vga_driver v1(CLOCK_50, KEY[0], Coordinate_Selected, pipe_opening_state, pipe_connected_to_source, pipe_leak, 
enable, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK, victory, level);

endmodule
