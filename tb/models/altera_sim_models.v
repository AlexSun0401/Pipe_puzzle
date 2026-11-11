`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// altera_sim_models.v -- behavioural stand-ins for the two Intel megafunctions
// that rtl/video/vga_adapter instantiates, so that the design simulates in any
// Verilog simulator without the Quartus simulation libraries.
//
// They model exactly the configurations used by this project:
//   altpll      one output, input clock divided by 2 (50 MHz -> 25 MHz)
//   altsyncram  simple dual-port RAM, write on clock0, read on clock1 with
//               registered address and registered output (two-edge latency)
//
// To simulate against Intel's own models instead, leave this file out and
// compile <quartus>/eda/sim_lib/altera_mf.v.
// -----------------------------------------------------------------------------

module altpll (inclk, clk);
    parameter operation_mode         = "NORMAL";
    parameter intended_device_family = "Cyclone V";
    parameter lpm_type               = "altpll";
    parameter pll_type               = "AUTO";
    parameter inclk0_input_frequency = 20000;
    parameter primary_clock          = "INCLK0";
    parameter compensate_clock       = "CLK0";
    parameter clk0_phase_shift       = "0";
    parameter clk0_divide_by         = 1;
    parameter clk0_multiply_by       = 1;
    parameter clk0_duty_cycle        = 50;

    input  wire [1:0] inclk;
    output wire [5:0] clk;

    reg half = 1'b0;
    always @(posedge inclk[0]) half <= ~half;
    assign clk = {5'b0, half};

    initial begin
        if (clk0_divide_by != 2 || clk0_multiply_by != 1) begin
            $display("ERROR: altpll simulation model only supports divide-by-2 (got %0d/%0d)",
                     clk0_multiply_by, clk0_divide_by);
            $finish;
        end
    end
endmodule


module altsyncram (wren_a, wren_b, clock0, clock1, clocken0, clocken1,
                   address_a, address_b, data_a, q_b);
    parameter width_a                = 1;
    parameter widthad_a              = 1;
    parameter numwords_a             = 2;
    parameter width_b                = 1;
    parameter widthad_b              = 1;
    parameter numwords_b             = 2;
    parameter operation_mode         = "DUAL_PORT";
    parameter outdata_reg_b          = "UNREGISTERED";
    parameter address_reg_b          = "CLOCK1";
    parameter clock_enable_input_a   = "NORMAL";
    parameter clock_enable_input_b   = "NORMAL";
    parameter clock_enable_output_b  = "NORMAL";
    parameter power_up_uninitialized = "FALSE";
    parameter init_file              = "UNUSED";
    parameter intended_device_family = "Cyclone V";

    input  wire                 wren_a, wren_b;
    input  wire                 clock0, clock1;
    input  wire                 clocken0, clocken1;
    input  wire [widthad_a-1:0] address_a;
    input  wire [widthad_b-1:0] address_b;
    input  wire [width_a-1:0]   data_a;
    output wire [width_b-1:0]   q_b;

    reg [width_a-1:0]   mem [0:numwords_a-1];
    reg [widthad_b-1:0] address_b_r = 0;
    reg [width_b-1:0]   q_b_r       = 0;

    // Bookkeeping for testbenches.
    integer writes      = 0;      // words written through port A
    integer init_words  = 0;      // words loaded from init_file
    reg     init_loaded = 1'b0;

    always @(posedge clock0)
        if (wren_a && address_a < numwords_a) begin
            mem[address_a] <= data_a;
            writes = writes + 1;
        end

    always @(posedge clock1) begin
        address_b_r <= address_b;
        q_b_r       <= mem[address_b_r];
    end

    assign q_b = (outdata_reg_b == "CLOCK1") ? q_b_r : mem[address_b_r];

    // ------------------------------------------------------------------------
    // Power-up contents: zero, then the memory initialisation file if it can be
    // found. The file is looked up in the directory given by +mif_dir=<dir>,
    // and +no_mif skips the load (the title image is 300 000 lines).
    // Supported MIF subset: ADDRESS_RADIX UNS/DEC/HEX, DATA_RADIX HEX, one
    // "address : value;" or "[first..last] : value;" entry per line.
    // ------------------------------------------------------------------------
    integer           fd, i, got, first, last, value;
    reg               hex_address, in_content;
    reg [8*256-1:0]   dir, path;
    reg [8*200-1:0]   line;
    reg [8*32-1:0]    word;

    initial begin
        for (i = 0; i < numwords_a; i = i + 1) mem[i] = 0;
        if (init_file != "UNUSED" && !$test$plusargs("no_mif")) begin
            if ($value$plusargs("mif_dir=%s", dir)) $sformat(path, "%0s/%0s", dir, init_file);
            else                                    $sformat(path, "%0s", init_file);
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $display("note: altsyncram model: cannot open %0s, memory starts at zero (use +mif_dir=<dir>)", path);
            end else begin
                hex_address = 1'b0;
                in_content  = 1'b0;
                while (!$feof(fd)) begin
                    line = 0;
                    got  = $fgets(line, fd);
                    if (got > 0 && !in_content) begin
                        // %s leaves "HEX;" or, with a space before the semicolon, "HEX"
                        if ($sscanf(line, " ADDRESS_RADIX = %s", word) == 1)
                            hex_address = (word[31:8] == "HEX" || word[23:0] == "HEX");
                        if ($sscanf(line, " DATA_RADIX = %s", word) == 1 &&
                            word[31:8] != "HEX" && word[23:0] != "HEX") begin
                            $display("ERROR: altsyncram model: only DATA_RADIX=HEX is supported (%0s)", path);
                            $finish;
                        end
                        if ($sscanf(line, " CONTENT %s", word) == 1) in_content = 1'b1;
                    end else if (got > 0) begin
                        // the common single-word entry first, then the range form
                        first = -1;
                        if (hex_address) begin
                            if ($sscanf(line, " %h : %h", first, value) == 2) last = first;
                            else if ($sscanf(line, " [%h..%h] : %h", first, last, value) != 3) first = -1;
                        end else begin
                            if ($sscanf(line, " %d : %h", first, value) == 2) last = first;
                            else if ($sscanf(line, " [%d..%d] : %h", first, last, value) != 3) first = -1;
                        end
                        if (first >= 0)
                            for (i = first; i <= last && i < numwords_a; i = i + 1) begin
                                mem[i]     = value;
                                init_words = init_words + 1;
                            end
                    end
                end
                $fclose(fd);
                init_loaded = 1'b1;
                $display("note: altsyncram model: loaded %0d words from %0s", init_words, path);
            end
        end
    end
endmodule
