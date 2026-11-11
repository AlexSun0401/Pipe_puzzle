// -----------------------------------------------------------------------------
// tb_util.vh -- shared self-checking utilities for the Pipe Puzzle testbenches
//
// `include this file inside a testbench module after declaring
//
//     localparam TB_NAME       = "tb_example";
//     localparam TB_TIMEOUT_NS = 10_000_000;    // watchdog, simulation ns
//
// It provides checks, a known-issue channel, functional-coverage bins, a
// watchdog and the final verdict line that the Makefile and the ModelSim
// script look for:
//
//     TB_RESULT: PASS      or      TB_RESULT: FAIL
//
// Plusargs understood by every testbench:
//     +seed=<n>   seed for the random stimulus (default 1)
//     +waves      dump a VCD next to the simulation
//     +strict     treat known issues as errors
//
// Plain Verilog-2001, so it runs in ModelSim Starter and in Icarus Verilog.
// -----------------------------------------------------------------------------

localparam TB_MAX_ERRORS = 30;    // stop after this many failed checks
localparam TB_COV_MAX    = 400;   // coverage bins per testbench
localparam TB_GRP_MAX    = 48;    // coverage groups per testbench

integer tb_checks = 0;            // checks evaluated
integer tb_errors = 0;            // checks failed
integer tb_known  = 0;            // known issues observed
integer tb_seed   = 1;
reg     tb_strict = 1'b0;
reg     tb_done   = 1'b0;
reg [8*64-1:0] tb_case = "startup";

integer        tb_cov_n = 0;
integer        tb_cov_hits [0:TB_COV_MAX-1];
integer        tb_grp_n = 0;
integer        tb_grp_first [0:TB_GRP_MAX-1];
integer        tb_grp_count [0:TB_GRP_MAX-1];
reg [8*36-1:0] tb_grp_name  [0:TB_GRP_MAX-1];

// --- start-up ----------------------------------------------------------------
task tb_start;
    begin
        if (!$value$plusargs("seed=%d", tb_seed)) tb_seed = 1;
        tb_strict = $test$plusargs("strict");
        $timeformat(-9, 0, " ns", 0);
        if ($test$plusargs("waves")) begin
            $dumpfile({TB_NAME, ".vcd"});
            $dumpvars;
        end
        $display("");
        $display("==== %0s  (seed %0d%0s) ====", TB_NAME, tb_seed, tb_strict ? ", strict" : "");
    end
endtask

task tb_case_begin(input [8*64-1:0] name);
    begin
        tb_case = name;
        $display("[%0t] -- %0s", $time, name);
    end
endtask

// --- checks ------------------------------------------------------------------
task tb_fail(input [8*120-1:0] msg);
    begin
        tb_errors = tb_errors + 1;
        $display("[%0t] ERROR (%0s): %0s", $time, tb_case, msg);
        if (tb_errors >= TB_MAX_ERRORS) begin
            $display("Too many errors, stopping.");
            tb_finish;
        end
    end
endtask

task tb_check(input ok, input [8*120-1:0] msg);
    begin
        tb_checks = tb_checks + 1;
        if (ok !== 1'b1) tb_fail(msg);
    end
endtask

// Case-equality compare, so an X or Z on either side is a mismatch.
task tb_check_eq(input [63:0] actual, input [63:0] expected, input [8*96-1:0] what);
    begin
        tb_checks = tb_checks + 1;
        if (actual !== expected) begin
            tb_errors = tb_errors + 1;
            $display("[%0t] ERROR (%0s): %0s: got 0x%0h, expected 0x%0h",
                     $time, tb_case, what, actual, expected);
            if (tb_errors >= TB_MAX_ERRORS) begin
                $display("Too many errors, stopping.");
                tb_finish;
            end
        end
    end
endtask

task tb_note(input [8*160-1:0] msg);
    begin
        $display("[%0t] note  (%0s): %0s", $time, tb_case, msg);
    end
endtask

// A behaviour that deviates from the intended design but is documented in
// tb/README.md. It is reported and counted, and fails only with +strict, so the
// suite stays usable as a regression gate while the issue is open.
task tb_known_issue(input ok, input [8*8-1:0] id, input [8*160-1:0] msg);
    begin
        tb_checks = tb_checks + 1;
        if (ok === 1'b1) begin
            $display("[%0t] note  (%0s): known issue %0s was not observed", $time, tb_case, id);
        end else begin
            tb_known = tb_known + 1;
            $display("[%0t] KNOWN ISSUE %0s (%0s): %0s", $time, id, tb_case, msg);
            if (tb_strict) tb_errors = tb_errors + 1;
        end
    end
endtask

// --- functional coverage -----------------------------------------------------
// A group is `count` consecutive bins. Every bin must be hit at least once by
// the end of the run, otherwise the testbench fails.
task tb_cov_group(output integer first_id, input [8*36-1:0] name, input integer count);
    integer k;
    begin
        first_id = tb_cov_n;
        if (tb_cov_n + count > TB_COV_MAX || tb_grp_n >= TB_GRP_MAX) begin
            $display("ERROR: coverage tables are too small for group %0s", name);
            tb_errors = tb_errors + 1;
        end else begin
            tb_grp_name[tb_grp_n]  = name;
            tb_grp_first[tb_grp_n] = tb_cov_n;
            tb_grp_count[tb_grp_n] = count;
            tb_grp_n = tb_grp_n + 1;
            for (k = 0; k < count; k = k + 1) tb_cov_hits[tb_cov_n + k] = 0;
            tb_cov_n = tb_cov_n + count;
        end
    end
endtask

task tb_cov_hit(input integer id);
    begin
        if (id >= 0 && id < tb_cov_n) tb_cov_hits[id] = tb_cov_hits[id] + 1;
    end
endtask

task tb_cov_report;
    integer g, k, hit, total_hit;
    begin
        total_hit = 0;
        if (tb_grp_n > 0) $display("---- functional coverage ----");
        for (g = 0; g < tb_grp_n; g = g + 1) begin
            hit = 0;
            for (k = 0; k < tb_grp_count[g]; k = k + 1)
                if (tb_cov_hits[tb_grp_first[g] + k] > 0) hit = hit + 1;
            total_hit = total_hit + hit;
            $display("  %-36s %0d/%0d", tb_grp_name[g], hit, tb_grp_count[g]);
            for (k = 0; k < tb_grp_count[g]; k = k + 1)
                if (tb_cov_hits[tb_grp_first[g] + k] == 0) begin
                    tb_errors = tb_errors + 1;
                    $display("    ERROR: bin %0s[%0d] was never hit", tb_grp_name[g], k);
                end
        end
        if (tb_grp_n > 0) $display("  total bins hit: %0d/%0d", total_hit, tb_cov_n);
    end
endtask

// --- verdict -----------------------------------------------------------------
task tb_finish;
    begin
        if (!tb_done) begin
            tb_done = 1'b1;
            tb_cov_report;
            $display("==== %0s: %0d checks, %0d error(s), %0d known issue(s) ====",
                     TB_NAME, tb_checks, tb_errors, tb_known);
            if (tb_errors == 0) $display("TB_RESULT: PASS");
            else                $display("TB_RESULT: FAIL");
        end
        $finish;
    end
endtask

initial begin : tb_watchdog
    #(TB_TIMEOUT_NS);
    tb_fail("watchdog timeout: the test did not finish");
    tb_finish;
end
