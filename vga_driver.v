module vga_driver (CLOCK_50, Resetn, SW, pipe_opening_state, pipe_connected_to_source, pipe_leak, 
enable, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK, victory, level);

	input wire CLOCK_50;
	input wire Resetn;
	input wire [3:0] SW;
	input wire victory;
	input wire [1:0] level;

    
	input wire [63:0] pipe_opening_state;
	input wire [15:0] pipe_connected_to_source;
	input wire [15:0] pipe_leak;
	input wire enable;
	
	output wire [7:0] VGA_R; 
	output wire [7:0] VGA_G; 
   output wire [7:0] VGA_B; 
   output wire VGA_HS;
   output wire VGA_VS;
   output wire VGA_BLANK_N;
   output wire VGA_SYNC_N;
   output wire VGA_CLK;

	// resolution is fixed at 640x480
	localparam nX = 10;
	localparam nY = 9;
	localparam COLOR_DEPTH = 9;

	// resolution
	localparam RES_X = 640;
	localparam RES_Y = 480;

	// The dimension of the tiles
	localparam TILE_WIDTH = 120;
	localparam TILE_HEIGHT = 120;
	
	// The horizontal and vertical offset
	localparam H_OFFSET = 80;
	localparam V_OFFSET = 0;

	// Thickness of border and pipes
	localparam BORDER_THICKNESS = 2;
	localparam PIPE_THICKNESS = 16;
	
	reg [nX-1:0] draw_x;
	reg [nY-1:0] draw_y;

	// traverse through every pixel
   	always @(posedge CLOCK_50 or negedge Resetn)
		begin
			if (!Resetn)
				begin
					draw_x <= 0;
					draw_y <= 0;
				end
			else 
					if (draw_x == RES_X - 1)
						begin
							draw_x <= 0;
							if (draw_y == RES_Y - 1) draw_y <= 0;
							else draw_y <= draw_y + 1'b1;
						end
					else draw_x <= draw_x + 1'b1;
		end
   
	// Check if pixel (x,y) is in the domain of drawing
	wire is_drawing_domain = (draw_x >= H_OFFSET) && (draw_x < H_OFFSET+4*TILE_WIDTH) && (draw_y >= V_OFFSET) && (draw_y < V_OFFSET+4*TILE_HEIGHT);
	
	wire [1:0] tile_x = (draw_x - H_OFFSET)/ TILE_WIDTH;
	wire [1:0] tile_y = (draw_y - V_OFFSET) / TILE_HEIGHT;
	wire [3:0] tile_index = tile_y * 4 + tile_x;
	reg [3:0] current_opening;

	always @* begin
		case (tile_index)
			4'd0: current_opening = pipe_opening_state[3:0];
			4'd1: current_opening = pipe_opening_state[7:4];
			4'd2: current_opening = pipe_opening_state[11:8];
			4'd3: current_opening = pipe_opening_state[15:12];
			4'd4: current_opening = pipe_opening_state[19:16];
			4'd5: current_opening = pipe_opening_state[23:20];
			4'd6: current_opening = pipe_opening_state[27:24];
			4'd7: current_opening = pipe_opening_state[31:28];
			4'd8: current_opening = pipe_opening_state[35:32];
			4'd9: current_opening = pipe_opening_state[39:36];
			4'd10: current_opening = pipe_opening_state[43:40];
			4'd11: current_opening = pipe_opening_state[47:44];
			4'd12: current_opening = pipe_opening_state[51:48];
			4'd13: current_opening = pipe_opening_state[55:52];
			4'd14: current_opening = pipe_opening_state[59:56];
			4'd15: current_opening = pipe_opening_state[63:60];
			default: current_opening = 4'bxxxx;
		endcase
	end

	// determine the position of the pixel inside the tile where it locates
	wire [nX-1:0] local_x = (draw_x - H_OFFSET) % TILE_WIDTH;
	wire [nY-1:0] local_y = (draw_y - V_OFFSET) % TILE_HEIGHT;

	wire is_connected = pipe_connected_to_source[tile_index];
	wire is_leaking = pipe_leak[tile_index];
    
	// Check if the tile is selected by the switches
	wire is_selected = (tile_x == SW[3:2]) && (tile_y == SW[1:0]);

	localparam [COLOR_DEPTH-1:0] COLOR_GREEN  = 9'b000_111_000;
	localparam [COLOR_DEPTH-1:0] COLOR_BLUE   = 9'b000_000_110;
	localparam [COLOR_DEPTH-1:0] COLOR_RED    = 9'b111_000_000;
	localparam [COLOR_DEPTH-1:0] COLOR_PURPLE = 9'b111_000_111;
	localparam [COLOR_DEPTH-1:0] COLOR_YELLOW = 9'b111_111_000;
	localparam [COLOR_DEPTH-1:0] COLOR_GRAY   = 9'b011_011_011;
	localparam [COLOR_DEPTH-1:0] COLOR_BLACK  = 9'b000_000_000;
	localparam [COLOR_DEPTH-1:0] COLOR_WHITE  = 9'b111_111_111;
    
	
	// calculate the color of each pixel
	reg [COLOR_DEPTH-1:0] calculated_color;

	wire center_y = (local_y > TILE_HEIGHT/2 - PIPE_THICKNESS/2) && (local_y < TILE_HEIGHT/2 + PIPE_THICKNESS/2);
	wire center_x = (local_x > TILE_WIDTH/2 - PIPE_THICKNESS/2) && (local_x < TILE_WIDTH/2 + PIPE_THICKNESS/2);
	
	wire pipe_N = current_opening[3] && center_x && (local_y < TILE_HEIGHT/2);
	wire pipe_E = current_opening[2] && center_y && (local_x > TILE_WIDTH/2);
	wire pipe_S = current_opening[1] && center_x && (local_y > TILE_HEIGHT/2);
	wire pipe_W = current_opening[0] && center_y && (local_x < TILE_WIDTH/2);
	wire pipe_center = (current_opening != 4'b0000) && center_y && center_x;

	wire is_pipe = (pipe_N || pipe_E || pipe_S || pipe_W || pipe_center);
	wire is_border = (local_x < BORDER_THICKNESS || local_x >= TILE_WIDTH - BORDER_THICKNESS || local_y < BORDER_THICKNESS || local_y >= TILE_HEIGHT - BORDER_THICKNESS);
	
	always @* begin
		if(enable) begin
			if(victory)
				if(level == 2'd1 || level == 2'd2) calculated_color <= COLOR_GREEN;
				else if(level == 2'd3) calculated_color <= COLOR_PURPLE;
				else calculated_color <= COLOR_BLACK;
			else calculated_color <= COLOR_BLACK;
			if(is_drawing_domain) begin
				calculated_color <= COLOR_BLACK;
				if(is_border)
					if (is_selected) calculated_color <= COLOR_YELLOW;
					else if (is_leaking) calculated_color <= COLOR_RED;
					else calculated_color <= COLOR_WHITE;
        
				else if(is_pipe)
					if (is_connected) calculated_color <= COLOR_BLUE;
					else calculated_color <= COLOR_GRAY;
			end
		end
	end
	
	vga_adapter VGA (Resetn, CLOCK_50, calculated_color, draw_x, draw_y, enable,
	VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);
	defparam VGA.RESOLUTION = "640x480";
	defparam VGA.COLOR_DEPTH = 9;
	defparam VGA.BACKGROUND_IMAGE = "Pipe_cover_9bit.mif"; 
endmodule
