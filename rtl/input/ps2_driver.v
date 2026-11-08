// Adapted from Professor Brown's ps2_demo.v
module ps2_driver (CLOCK_50, KEY, PS2_CLK, PS2_DAT, OUT_X, OUT_Y, OUT_Reset, OUT_Rotate, ps2_rec, reset_position);

	parameter scan_code_W = 8'h1D, scan_code_A = 8'h1C, scan_code_S = 8'h1B, scan_code_D = 8'h23, scan_code_Space = 8'h29, scan_code_R = 8'h2D;
	parameter scan_code_BREAK = 8'hF0; 

	input wire CLOCK_50;
	input wire [0:0] KEY;
	inout wire PS2_CLK, PS2_DAT;
	input wire reset_position;
	output reg [1:0] OUT_X = 2'b0, OUT_Y = 2'b0;
	output reg OUT_Reset = 1'b1, OUT_Rotate = 1'b0;

	wire Resetn, negedge_ps2_clk;
	reg [10:0] ps2_shift_reg; // changed the Serial signal to a shift register
	reg [3:0] Packet_Count;
	wire [7:0] scancode;
	output wire ps2_rec;

	reg prev_ps2_clk;
	wire PS2_CLK_S, PS2_DAT_S;
	reg break_received;

	assign Resetn = KEY[0];

	sync S3 (PS2_CLK, Resetn, CLOCK_50, PS2_CLK_S);
	sync S4 (PS2_DAT, Resetn, CLOCK_50, PS2_DAT_S);
    
	always @(posedge CLOCK_50) prev_ps2_clk <= PS2_CLK_S;

	assign negedge_ps2_clk = (prev_ps2_clk & !PS2_CLK_S);

	always @(posedge CLOCK_50) begin
		if (!Resetn) begin
			Packet_Count <= 4'b0;
			ps2_shift_reg <= 11'b0;
		end
		else if (negedge_ps2_clk) begin
			ps2_shift_reg <= {PS2_DAT_S, ps2_shift_reg[10:1]};
			if (Packet_Count == 4'd10) Packet_Count <= 4'b0;
			else Packet_Count <= Packet_Count + 1'b1;
		end
	end

	assign ps2_rec = (Packet_Count == 4'd10) && (negedge_ps2_clk);
	assign scancode = ps2_shift_reg[8:1];

	reg ps2_rec_pulse;
	always @(posedge CLOCK_50) ps2_rec_pulse <= ps2_rec;
	
	always @(posedge CLOCK_50) begin
		if (!Resetn) begin
			OUT_X <= 2'b00;
			OUT_Y <= 2'b00;
			OUT_Reset <= 1'b1;
			OUT_Rotate <= 1'b0;
			break_received <= 1'b0;
		end
		else if(reset_position) begin
			OUT_X <= 2'b00;
			OUT_Y <= 2'b00;
		end
		else begin
			OUT_Reset <= 1'b1;
			OUT_Rotate <= 1'b0;
			if (ps2_rec_pulse) begin 
				if (scancode == scan_code_BREAK) break_received <= 1'b1;
				else if (break_received) break_received <= 1'b0;
				else begin 
					case (scancode)
						scan_code_W:
							if(OUT_Y > 2'd0) OUT_Y <= OUT_Y - 1'b1; // up
						scan_code_S:
							if(OUT_Y < 2'd3) OUT_Y <= OUT_Y + 1'b1; // down
						scan_code_A:
							if(OUT_X > 2'd0) OUT_X <= OUT_X - 1'b1; // left
						scan_code_D:
							if(OUT_X < 2'd3) OUT_X <= OUT_X + 1'b1; // right
						scan_code_R: OUT_Reset <= 1'b0; 
						scan_code_Space: OUT_Rotate <= 1'b1; 
					endcase
				end
			end
		end
	end
endmodule


// syncronizer, implemented as two FFs in series
module sync(D, Resetn, Clock, Q);
    input wire D;
    input wire Resetn, Clock;
    output reg Q;

    reg Qi; // internal node

    always @(posedge Clock)
        if (Resetn == 0) begin
            Qi <= 1'b0;
            Q <= 1'b0;
        end
        else begin
            Qi <= D;
            Q <= Qi;
        end
endmodule

// n-bit register with enable
module regn(R, Resetn, E, Clock, Q);
    parameter n = 8;
    input wire [n-1:0] R;
    input wire Resetn, E, Clock;
    output reg [n-1:0] Q;

    always @(posedge Clock)
        if (!Resetn)
            Q <= 0;
        else if (E)
            Q <= R;
endmodule
