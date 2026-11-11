# Pipe Puzzle testbench runner for Icarus Verilog.
#
#   make                 run every testbench, print one verdict per bench
#   make tb_timer        run one testbench
#   make SEED=7          another seed for the random stimulus
#   make WAVES=1 tb_ps2_driver      also write build/tb_ps2_driver.vcd
#   make STRICT=1        treat the documented known issues as failures
#   make PLUSARGS=+long tb_timer    extra plusargs (see tb/README.md)
#   make clean
#
# A testbench passes when its log contains "TB_RESULT: PASS".

IVERILOG ?= iverilog
VVP      ?= vvp
SEED     ?= 1
RTL      := ../rtl
BUILD    := build

TESTS := tb_pipe_manager tb_timer tb_ps2_driver tb_vga_driver tb_pipe_puzzle_game

IVFLAGS := -g2005 -Wall -Wno-timescale -Wno-sensitivity-entire-array -I include

RTL_GAME  := $(RTL)/game/pipe_manager.v $(RTL)/game/timer.v
RTL_INPUT := $(RTL)/input/ps2_driver.v
RTL_VIDEO := $(RTL)/video/vga_driver.v $(sort $(wildcard $(RTL)/video/vga_adapter/*.v))
RTL_TOP   := $(RTL)/pipe_puzzle_game.v
VIDEO_SIM := models/vga_monitor.v models/altera_sim_models.v
INCLUDES  := $(wildcard include/*.vh)

# Design and model files of each testbench.
SRC_tb_pipe_manager     := $(RTL)/game/pipe_manager.v
SRC_tb_timer            := $(RTL)/game/timer.v
SRC_tb_ps2_driver       := $(RTL_INPUT) models/ps2_keyboard_bfm.v
SRC_tb_vga_driver       := $(RTL_VIDEO) $(VIDEO_SIM)
SRC_tb_pipe_puzzle_game := $(RTL_TOP) $(RTL_GAME) $(RTL_INPUT) $(RTL_VIDEO) $(VIDEO_SIM) models/ps2_keyboard_bfm.v

# Plusargs of each testbench: only the system bench needs the title image.
ARGS_tb_vga_driver       := +no_mif
ARGS_tb_pipe_puzzle_game := +mif_dir=$(abspath ../quartus)

RUNARGS := +seed=$(SEED) $(if $(WAVES),+waves) $(if $(STRICT),+strict) $(PLUSARGS)

.PHONY: all clean $(TESTS)
.SECONDEXPANSION:

all:
	@status=0; \
	for t in $(TESTS); do \
		rm -f $(BUILD)/$$t.log; \
		$(MAKE) --no-print-directory -s $$t > /dev/null 2>&1; \
		if grep -q "TB_RESULT: PASS" $(BUILD)/$$t.log 2>/dev/null; then \
			printf "PASS  %-22s %s\n" $$t "$$(grep '^==== .*checks' $(BUILD)/$$t.log | sed 's/^==== [a-z_0-9]*: //; s/ ====$$//')"; \
		else \
			printf "FAIL  %-22s see $(BUILD)/%s.log\n" $$t $$t; status=1; \
		fi; \
	done; \
	exit $$status

$(TESTS): %: $(BUILD)/%.vvp
	@cd $(BUILD) && $(VVP) -n $*.vvp $(ARGS_$*) $(RUNARGS) | tee $*.log
	@grep -q "TB_RESULT: PASS" $(BUILD)/$*.log

$(BUILD)/%.vvp: tests/%.v $$(SRC_$$*) $(INCLUDES) | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -s $* -o $@ tests/$*.v $(SRC_$*)

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
