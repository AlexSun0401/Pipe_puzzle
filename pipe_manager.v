module pipe_manager(CLOCK_50, rotate, resetn, SW, pipe_opening_state, pipe_connected_to_source, pipe_leak, victory, level, enable);

input rotate, resetn, enable, CLOCK_50;
input [3:0] SW;
input [1:0] level;

output wire [63:0] pipe_opening_state;
output reg [15:0] pipe_connected_to_source;
output reg [15:0] pipe_leak;
output reg victory;

//5 types of pipes
parameter type_empty = 3'd0;
parameter type_straight = 3'd1;
parameter type_L = 3'd2;
parameter type_T = 3'd3;
parameter type_cross = 3'd4;

parameter L1_pipe_type_00 = type_straight,   L1_pipe_type_10 = type_straight,   L1_pipe_type_20 = type_L,           L1_pipe_type_30 = type_empty;
parameter L1_pipe_type_01 = type_L,          L1_pipe_type_11 = type_straight,   L1_pipe_type_21 = type_L,           L1_pipe_type_31 = type_empty;
parameter L1_pipe_type_02 = type_L,          L1_pipe_type_12 = type_straight,   L1_pipe_type_22 = type_straight,    L1_pipe_type_32 = type_L;
parameter L1_pipe_type_03 = type_empty,      L1_pipe_type_13 = type_empty,      L1_pipe_type_23 = type_empty,       L1_pipe_type_33 = type_L;

parameter L2_pipe_type_00 = type_L,          L2_pipe_type_10 = type_L,          L2_pipe_type_20 = type_straight,    L2_pipe_type_30 = type_L;
parameter L2_pipe_type_01 = type_L,          L2_pipe_type_11 = type_L,          L2_pipe_type_21 = type_empty,       L2_pipe_type_31 = type_straight;
parameter L2_pipe_type_02 = type_L,          L2_pipe_type_12 = type_L,          L2_pipe_type_22 = type_L,           L2_pipe_type_32 = type_L;
parameter L2_pipe_type_03 = type_L,          L2_pipe_type_13 = type_empty,      L2_pipe_type_23 = type_L,           L2_pipe_type_33 = type_straight;

parameter L3_pipe_type_00 = type_T,          L3_pipe_type_10 = type_straight,   L3_pipe_type_20 = type_straight,    L3_pipe_type_30 = type_L;
parameter L3_pipe_type_01 = type_straight,   L3_pipe_type_11 = type_L,          L3_pipe_type_21 = type_straight,    L3_pipe_type_31 = type_L;
parameter L3_pipe_type_02 = type_L,          L3_pipe_type_12 = type_cross,      L3_pipe_type_22 = type_straight,    L3_pipe_type_32 = type_L;
parameter L3_pipe_type_03 = type_L,          L3_pipe_type_13 = type_L,          L3_pipe_type_23 = type_straight,    L3_pipe_type_33 = type_T;

reg [31:0] pipe_orientation = 32'b0;

wire [31:0] random_orientation;

rng_lfsr_32 rng(CLOCK_50, random_orientation);

// Update pipe orientations
always @(posedge rotate or negedge resetn)
	begin
		if(!resetn) pipe_orientation <= random_orientation;
		else if(enable)
			begin
				if(!victory) // If the player wins, the system will prohibit them from rotating the pipe
				case(SW)
				4'b00_00: pipe_orientation[1:0] <= pipe_orientation[1:0] + 2'b01;
				4'b01_00: pipe_orientation[3:2] <= pipe_orientation[3:2] + 2'b01;
				4'b10_00: pipe_orientation[5:4] <= pipe_orientation[5:4] + 2'b01;
				4'b11_00: pipe_orientation[7:6] <= pipe_orientation[7:6] + 2'b01;
				4'b00_01: pipe_orientation[9:8] <= pipe_orientation[9:8] + 2'b01;
				4'b01_01: pipe_orientation[11:10] <= pipe_orientation[11:10] + 2'b01;
				4'b10_01: pipe_orientation[13:12] <= pipe_orientation[13:12] + 2'b01;
				4'b11_01: pipe_orientation[15:14] <= pipe_orientation[15:14] + 2'b01;
				4'b00_10: pipe_orientation[17:16] <= pipe_orientation[17:16] + 2'b01;
				4'b01_10: pipe_orientation[19:18] <= pipe_orientation[19:18] + 2'b01;
				4'b10_10: pipe_orientation[21:20] <= pipe_orientation[21:20] + 2'b01;
				4'b11_10: pipe_orientation[23:22] <= pipe_orientation[23:22] + 2'b01;
				4'b00_11: pipe_orientation[25:24] <= pipe_orientation[25:24] + 2'b01;
				4'b01_11: pipe_orientation[27:26] <= pipe_orientation[27:26] + 2'b01;
				4'b10_11: pipe_orientation[29:28] <= pipe_orientation[29:28] + 2'b01;
				4'b11_11: pipe_orientation[31:30] <= pipe_orientation[31:30] + 2'b01;
				endcase
			end
		else pipe_orientation <= random_orientation;
	end
	
reg [2:0] 	pipe_type_00, pipe_type_01, pipe_type_02, pipe_type_03,
				pipe_type_10, pipe_type_11, pipe_type_12, pipe_type_13,
				pipe_type_20, pipe_type_21, pipe_type_22, pipe_type_23,
				pipe_type_30, pipe_type_31, pipe_type_32, pipe_type_33;

// Configure pipe types with current level
always @* begin
	case(level)
	default: begin
	pipe_type_00 <= type_empty;
	pipe_type_01 <= type_empty;
	pipe_type_02 <= type_empty;
	pipe_type_03 <= type_empty;
	pipe_type_10 <= type_empty;
	pipe_type_11 <= type_empty;
	pipe_type_12 <= type_empty;
	pipe_type_13 <= type_empty;
	pipe_type_20 <= type_empty;
	pipe_type_21 <= type_empty;
	pipe_type_22 <= type_empty;
	pipe_type_23 <= type_empty;
	pipe_type_30 <= type_empty;
	pipe_type_31 <= type_empty;
	pipe_type_32 <= type_empty;
	pipe_type_33 <= type_empty;
	end
	2'd1: begin
	pipe_type_00 <= L1_pipe_type_00;
	pipe_type_01 <= L1_pipe_type_01;
	pipe_type_02 <= L1_pipe_type_02;
	pipe_type_03 <= L1_pipe_type_03;
	pipe_type_10 <= L1_pipe_type_10;
	pipe_type_11 <= L1_pipe_type_11;
	pipe_type_12 <= L1_pipe_type_12;
	pipe_type_13 <= L1_pipe_type_13;
	pipe_type_20 <= L1_pipe_type_20;
	pipe_type_21 <= L1_pipe_type_21;
	pipe_type_22 <= L1_pipe_type_22;
	pipe_type_23 <= L1_pipe_type_23;
	pipe_type_30 <= L1_pipe_type_30;
	pipe_type_31 <= L1_pipe_type_31;
	pipe_type_32 <= L1_pipe_type_32;
	pipe_type_33 <= L1_pipe_type_33;
	end
	2'd2: begin
	pipe_type_00 <= L2_pipe_type_00;
	pipe_type_01 <= L2_pipe_type_01;
	pipe_type_02 <= L2_pipe_type_02;
	pipe_type_03 <= L2_pipe_type_03;
	pipe_type_10 <= L2_pipe_type_10;
	pipe_type_11 <= L2_pipe_type_11;
	pipe_type_12 <= L2_pipe_type_12;
	pipe_type_13 <= L2_pipe_type_13;
	pipe_type_20 <= L2_pipe_type_20;
	pipe_type_21 <= L2_pipe_type_21;
	pipe_type_22 <= L2_pipe_type_22;
	pipe_type_23 <= L2_pipe_type_23;
	pipe_type_30 <= L2_pipe_type_30;
	pipe_type_31 <= L2_pipe_type_31;
	pipe_type_32 <= L2_pipe_type_32;
	pipe_type_33 <= L2_pipe_type_33;
	end
	2'd3: begin
	pipe_type_00 <= L3_pipe_type_00;
	pipe_type_01 <= L3_pipe_type_01;
	pipe_type_02 <= L3_pipe_type_02;
	pipe_type_03 <= L3_pipe_type_03;
	pipe_type_10 <= L3_pipe_type_10;
	pipe_type_11 <= L3_pipe_type_11;
	pipe_type_12 <= L3_pipe_type_12;
	pipe_type_13 <= L3_pipe_type_13;
	pipe_type_20 <= L3_pipe_type_20;
	pipe_type_21 <= L3_pipe_type_21;
	pipe_type_22 <= L3_pipe_type_22;
	pipe_type_23 <= L3_pipe_type_23;
	pipe_type_30 <= L3_pipe_type_30;
	pipe_type_31 <= L3_pipe_type_31;
	pipe_type_32 <= L3_pipe_type_32;
	pipe_type_33 <= L3_pipe_type_33;
	end
	endcase
end

// Determine opening states of each node with pipe type and orientation
pipe_config_opening o00(pipe_type_00, pipe_orientation[1:0], pipe_opening_state[3:0]);
pipe_config_opening o10(pipe_type_10, pipe_orientation[3:2], pipe_opening_state[7:4]);
pipe_config_opening o20(pipe_type_20, pipe_orientation[5:4], pipe_opening_state[11:8]);
pipe_config_opening o30(pipe_type_30, pipe_orientation[7:6], pipe_opening_state[15:12]);

pipe_config_opening o01(pipe_type_01, pipe_orientation[9:8], pipe_opening_state[19:16]);
pipe_config_opening o11(pipe_type_11, pipe_orientation[11:10], pipe_opening_state[23:20]);
pipe_config_opening o21(pipe_type_21, pipe_orientation[13:12], pipe_opening_state[27:24]);
pipe_config_opening o31(pipe_type_31, pipe_orientation[15:14], pipe_opening_state[31:28]);

pipe_config_opening o02(pipe_type_02, pipe_orientation[17:16], pipe_opening_state[35:32]);
pipe_config_opening o12(pipe_type_12, pipe_orientation[19:18], pipe_opening_state[39:36]);
pipe_config_opening o22(pipe_type_22, pipe_orientation[21:20], pipe_opening_state[43:40]);
pipe_config_opening o32(pipe_type_32, pipe_orientation[23:22], pipe_opening_state[47:44]);

pipe_config_opening o03(pipe_type_03, pipe_orientation[25:24], pipe_opening_state[51:48]);
pipe_config_opening o13(pipe_type_13, pipe_orientation[27:26], pipe_opening_state[55:52]);
pipe_config_opening o23(pipe_type_23, pipe_orientation[29:28], pipe_opening_state[59:56]);
pipe_config_opening o33(pipe_type_33, pipe_orientation[31:30], pipe_opening_state[63:60]);

reg [15:0] water_flow [0:16];
reg [4:0] i, j;

always @*
begin
		// check if pipe(0,0) is connected to the source
		if (pipe_opening_state[0]) water_flow[0] = 16'h0001;
		else water_flow[0] = 16'h0000;

	// iterate for 16 times to simulate the water flow
	for (i = 0; i < 16; i = i + 1)
	begin
		water_flow[i+1] = water_flow[i];
		// traverse through all the pipes
		for (j = 0; j < 16; j = j + 1)
			begin
				if (water_flow[i][j] == 1'b1)
					begin
						// check the north neighbor pipe (j-4) if the current pipe is not in the fist row
						if(j >= 4)
							if (pipe_opening_state[4*j + 3] && pipe_opening_state[4*(j-4) + 1]) water_flow[i+1][j-4] = 1'b1;
                
						// check the east neighbor (j+1) if the current pipe is not in the rightmost line
						if(j % 4 != 3)
							if (pipe_opening_state[4*j + 2] && pipe_opening_state[4*(j+1) + 0]) water_flow[i+1][j+1] = 1'b1;
                
						// check the south neighbor pipe (j+4) if the current pipe is not in the last row
						if(j < 12)
							if(pipe_opening_state[4*j + 1] && pipe_opening_state[4*(j+4) + 3]) water_flow[i+1][j+4] = 1'b1;
                
						// check the west neighbor pipe (j-1) if the current pipe is not in the leftmost line
						if (j % 4 != 0)
							if(pipe_opening_state[4*j + 0] && pipe_opening_state[4*(j-1) + 2]) water_flow[i+1][j-1] = 1'b1;
					end
			end
    
		pipe_connected_to_source = water_flow[16];
    
		pipe_leak = 16'b0; // assume there is not leak at the start
		
		for (j = 0; j < 16; j = j + 1)
		begin
			if (pipe_connected_to_source[j])
				begin
					// check the north opening
					if (pipe_opening_state[4*j + 3] == 1'b1)
						begin
							if (j < 4) pipe_leak[j] = 1'b1;
							else if (!pipe_opening_state[4*(j-4) + 1]) pipe_leak[j] = 1'b1;
						end
            
					// check the east opening
					if (pipe_opening_state[4*j + 2] == 1'b1 && j != 15)
						begin
							if (j % 4 == 3) pipe_leak[j] = 1'b1;
							else if (!pipe_opening_state[4*(j+1) + 0]) pipe_leak[j] = 1'b1;
						end
            
					// check the south opening
					if (pipe_opening_state[4*j + 1] == 1'b1)
						begin
							if (j >= 12) pipe_leak[j] = 1'b1;
							else if (!pipe_opening_state[4*(j+4) + 3]) pipe_leak[j] = 1'b1;
						end
            
					// check the west opening
					if (pipe_opening_state[4*j + 0] == 1'b1 && j != 0)
						begin
							if (j % 4 == 0) pipe_leak[j] = 1'b1;
							else if (!pipe_opening_state[4*(j-1) + 2]) pipe_leak[j] = 1'b1;
						end
				end
		end

    // Check victory
    if (pipe_connected_to_source[15] == 1'b1 && pipe_opening_state[4*15 + 2] == 1'b1 && pipe_leak == 16'b0)  victory = 1'b1;
    else victory = 1'b0;
	end
end
endmodule



module pipe_config_opening(pipe_type, current_orient, opening_state); // [N, E, S, W] -> [3, 2, 1, 0]
	input [2:0] pipe_type;
	input [1:0] current_orient;
	output reg [3:0] opening_state;
	
	//5 types of pipes
	parameter type_empty = 3'd0;
	parameter type_straight = 3'd1;
	parameter type_L = 3'd2;
	parameter type_T = 3'd3;
	parameter type_cross = 3'd4;
	
	always @* begin
		case(pipe_type)
			type_empty: opening_state <= 4'b0000;
			type_straight: 
				if(current_orient == 2'd0 || current_orient == 2'd2) opening_state <= 4'b0101;
				else opening_state <= 4'b1010;
			type_L:
				if(current_orient == 2'd0) opening_state <= 4'b0110;
				else if(current_orient == 2'd1) opening_state <= 4'b0011;
				else if(current_orient == 2'd2) opening_state <= 4'b1001;
				else opening_state <= 4'b1100;
			type_T:
				if(current_orient == 2'd0) opening_state <= 4'b0111;
				else if(current_orient == 2'd1) opening_state <= 4'b1011;
				else if(current_orient == 2'd2) opening_state <= 4'b1101;
				else opening_state <= 4'b1110;
			type_cross: opening_state <= 4'b1111;
			default: opening_state <= 4'b0000;
		endcase
	end
endmodule


// 32-bit LFSR RNG
module rng_lfsr_32(clk, random_out);
	input clk;
	output [31:0] random_out;
	reg [31:0] r_lfsr = 32'hBEEF_BEEF;
	wire feedback = r_lfsr[31] ^ r_lfsr[21] ^ r_lfsr[1] ^ r_lfsr[0];

	always @(posedge clk) r_lfsr <= {r_lfsr[30:0], feedback};

	assign random_out = r_lfsr;
endmodule
