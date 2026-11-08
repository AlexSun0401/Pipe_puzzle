module timer(CLOCK_50, victory, resetn, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0, level, restart);

parameter ticks = 26'd50_000_000;

input CLOCK_50;
input victory;
input resetn, restart;
input [1:0] level;

output [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;

reg [3:0] ones_L1 = 4'd0, tens_L1 = 4'd0, ones_L2 = 4'd0, tens_L2 = 4'd0, ones_L3 = 4'd0, tens_L3 = 4'd0;

reg [25:0] counter_L1 = 26'd0, counter_L2 = 26'd0, counter_L3 = 26'd0;

always@(posedge CLOCK_50) begin
	if(restart) begin
		counter_L1 <= 26'd0;
		ones_L1 <= 4'd0;
		tens_L1 <= 4'd0;
		counter_L2 <= 26'd0;
		ones_L2 <= 4'd0;
		tens_L2 <= 4'd0;
		counter_L3 <= 26'd0;
		ones_L3 <= 4'd0;
		tens_L3 <= 4'd0;
	end
	else if(!resetn) begin
		case(level)
			2'd1: begin
				counter_L1 <= 26'd0;
				ones_L1 <= 4'd0;
				tens_L1 <= 4'd0;
			end
			2'd2: begin
				counter_L2 <= 26'd0;
				ones_L2 <= 4'd0;
				tens_L2 <= 4'd0;
			end
			2'd3: begin
				counter_L3 <= 26'd0;
				ones_L3 <= 4'd0;
				tens_L3 <= 4'd0;
			end
			default: begin
			end
		endcase
	end
	else if(!victory) begin
		case(level)
			2'd1: begin
				if(counter_L1 == ticks - 1) begin
					counter_L1 <= 26'd0;
					if(ones_L1 >= 4'd9 && tens_L1 >= 4'd9) begin
					ones_L1 <= 4'd10;
					tens_L1 <= 4'd10;
					end
					else if(ones_L1 == 4'd9)begin
					ones_L1 <= 4'd0;
					tens_L1 <= tens_L1 + 4'd1;
					end
					else ones_L1 <= ones_L1 + 4'd1;	
				end
				else counter_L1 <= counter_L1 + 26'd1;
			end
			2'd2: begin
				if(counter_L2 == ticks - 1) begin
					counter_L2 <= 26'd0;
					if(ones_L2 >= 4'd9 && tens_L2 >= 4'd9) begin
					ones_L2 <= 4'd10;
					tens_L2 <= 4'd10;
					end
					else if(ones_L2 == 4'd9)begin
					ones_L2 <= 4'd0;
					tens_L2 <= tens_L2 + 4'd1;
					end
					else ones_L2 <= ones_L2 + 4'd1;	
				end
				else counter_L2 <= counter_L2 + 26'd1;
			end
			2'd3: begin
				if(counter_L3 == ticks - 1) begin
					counter_L3 <= 26'd0;
					if(ones_L3 >= 4'd9 && tens_L3 >= 4'd9) begin
					ones_L3 <= 4'd10;
					tens_L3 <= 4'd10;
					end
					else if(ones_L3 == 4'd9)begin
					ones_L3 <= 4'd0;
					tens_L3 <= tens_L3 + 4'd1;
					end
					else ones_L3 <= ones_L3 + 4'd1;	
				end
				else counter_L3 <= counter_L3 + 26'd1;
			end
			default: begin
			end
		endcase
    end
end

display tens_display_L1 (tens_L1, HEX5, (level >= 2'd1));
display ones_display_L1 (ones_L1, HEX4, (level >= 2'd1));
display tens_display_L2 (tens_L2, HEX3, (level >= 2'd2));
display ones_display_L2 (ones_L2, HEX2, (level >= 2'd2));
display tens_display_L3 (tens_L3, HEX1, (level >= 2'd3));
display ones_display_L3 (ones_L3, HEX0, (level >= 2'd3));

endmodule



module display(n, display, enable);
	input [3:0] n;
	input enable;
	output reg [6:0] display;
	
	always @*begin
		if(enable) begin
			if(n == 4'b0000) display =7'b100_0000;
			else if(n == 4'b0001) display =7'b111_1001;
			else if(n == 4'b0010) display =7'b010_0100;
			else if(n == 4'b0011) display =7'b011_0000;
			else if(n == 4'b0100) display =7'b001_1001;
			else if(n == 4'b0101) display =7'b001_0010;
			else if(n == 4'b0110) display =7'b000_0010;
			else if(n == 4'b0111) display =7'b111_1000;
			else if(n == 4'b1000) display =7'b000_0000;
			else if(n == 4'b1001) display =7'b001_0000;
			else display = 7'b011_1111;
		end
		else display = 7'b111_1111;
	end
endmodule

