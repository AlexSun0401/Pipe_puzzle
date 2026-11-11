# -----------------------------------------------------------------------------
# modelsim.do -- run the Pipe Puzzle testbenches in ModelSim or Questa.
#
# From the tb/ directory:
#     vsim -c -do modelsim.do              batch mode, all testbenches
# or in the transcript window of the GUI:
#     do modelsim.do
#
# Before `do`, these Tcl variables can be set to change the run:
#     set SEED 7                           seed of the random stimulus
#     set TESTS {tb_timer tb_ps2_driver}   run only these testbenches
#     set EXTRA "+strict"                  extra plusargs (see README.md)
#
# Each testbench prints "TB_RESULT: PASS" or "TB_RESULT: FAIL"; a summary of
# all of them is printed at the end.
#
# The video design is simulated with the models in models/altera_sim_models.v,
# so the Intel simulation libraries are not needed.
# -----------------------------------------------------------------------------

if {![info exists SEED]}  { set SEED 1 }
if {![info exists EXTRA]} { set EXTRA "" }
if {![info exists TESTS]} {
    set TESTS {tb_pipe_manager tb_timer tb_ps2_driver tb_vga_driver tb_pipe_puzzle_game}
}

set RTL ../rtl

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -quiet +incdir+include \
    $RTL/pipe_puzzle_game.v \
    $RTL/game/pipe_manager.v \
    $RTL/game/timer.v \
    $RTL/input/ps2_driver.v \
    $RTL/video/vga_driver.v \
    $RTL/video/vga_adapter/vga_adapter.v \
    $RTL/video/vga_adapter/vga_address_translator.v \
    $RTL/video/vga_adapter/vga_controller.v \
    $RTL/video/vga_adapter/vga_pll.v \
    models/altera_sim_models.v \
    models/ps2_keyboard_bfm.v \
    models/vga_monitor.v \
    tests/tb_pipe_manager.v \
    tests/tb_timer.v \
    tests/tb_ps2_driver.v \
    tests/tb_vga_driver.v \
    tests/tb_pipe_puzzle_game.v

set summary {}
foreach tb $TESTS {
    set args "+seed=$SEED $EXTRA"
    if {$tb eq "tb_vga_driver"}       { append args " +no_mif" }
    if {$tb eq "tb_pipe_puzzle_game"} { append args " +mif_dir=../quartus" }

    eval vsim -quiet -t 1ps work.$tb $args
    onfinish stop
    run -all

    # every testbench keeps its error count in tb_errors and sets tb_done
    set errors [examine -radix decimal sim:/$tb/tb_errors]
    set done   [examine -radix binary  sim:/$tb/tb_done]
    if {$done eq "1" && $errors == 0} {
        lappend summary "PASS  $tb"
    } else {
        lappend summary "FAIL  $tb  ($errors error(s))"
    }
    quit -sim
}

echo ""
echo "==== summary ===="
foreach line $summary { echo $line }

if {[batch_mode]} { quit -f }
