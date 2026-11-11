# Pipe Puzzle testbenches

Self-checking testbenches for every module of the game and for the complete design. Each bench compares the design with an independent golden model, measures functional coverage, and ends with a single verdict line, `TB_RESULT: PASS` or `TB_RESULT: FAIL`.

## Run

Icarus Verilog (tested with 12.0), from this directory:

```bash
make                 # all five testbenches, about one minute
make tb_timer        # one testbench
make SEED=7          # another seed for the random stimulus
make WAVES=1 tb_ps2_driver      # also writes build/tb_ps2_driver.vcd
make STRICT=1        # known issues (below) count as failures
```

```text
PASS  tb_pipe_manager        114907 checks, 0 error(s), 0 known issue(s)
PASS  tb_timer               63708 checks, 0 error(s), 0 known issue(s)
PASS  tb_ps2_driver          3214 checks, 0 error(s), 3 known issue(s)
PASS  tb_vga_driver          2393905 checks, 0 error(s), 0 known issue(s)
PASS  tb_pipe_puzzle_game    797788 checks, 0 error(s), 2 known issue(s)
```

ModelSim or Questa: `vsim -c -do modelsim.do`, or `do modelsim.do` in the GUI. The sources are plain Verilog-2001 (compiled with `iverilog -g2005`), but the script itself has not been run in ModelSim.

The Intel simulation libraries are not needed: `models/altera_sim_models.v` stands in for `altsyncram` and `altpll`.

## Layout

| Path | Contents |
| --- | --- |
| `tests/tb_pipe_manager.v` | Pipe openings, LFSR, level maps, rotation, water flow, leaks, victory |
| `tests/tb_timer.v` | Level timers and the seven-segment decoder |
| `tests/tb_ps2_driver.v` | PS/2 receiver and key decoding |
| `tests/tb_vga_driver.v` | Renderer, video-memory writes, VGA timing and the displayed frame |
| `tests/tb_pipe_puzzle_game.v` | The whole game, played through the keyboard from title screen to the end |
| `include/tb_util.vh` | Checks, known-issue channel, coverage bins, watchdog, verdict |
| `include/pipe_ref_model.vh` | Golden model of the pipe rules, and a solver for the levels |
| `include/vga_ref_model.vh` | Golden renderer: the colour of every pixel for a game state |
| `include/seg7_ref_model.vh` | Golden seven-segment patterns |
| `models/ps2_keyboard_bfm.v` | PS/2 keyboard: open-drain lines, 11-bit frames, make and break codes |
| `models/vga_monitor.v` | VGA monitor: measures sync timing and captures frames |
| `models/altera_sim_models.v` | Behavioural `altsyncram` (with MIF loading) and `altpll` |

## What is verified

| Testbench | Checked against | Main points |
| --- | --- | --- |
| `tb_pipe_manager` | Pipe model: flood fill to a fixed point, leak rules, victory rule | All 8 type codes × 4 orientations; LFSR seed, taps and balance; level mux; every tile turned through a full circle; 6 000 random boards forced onto the flow logic; 6 000 random orientations over the three levels; each level solved by turning tiles through the real interface |
| `tb_timer` | Three integer timers, compared with all six displays on every clock | Exact length of a second, digit carry, per-level timing, victory freeze, R, restart, priorities, overflow to `--`, 60 000 clocks of random inputs |
| `tb_ps2_driver` | Predicted cursor and pulse counts | All 256 scan codes, releases, typematic repeat, extended keys, saturation at the edges, pulse widths, 10 to 16.7 kHz keyboard clock, all 20 phases against `CLOCK_50`, decode latency |
| `tb_vga_driver` | Golden renderer, at the video-memory write port on every clock | Two complementary full frames, random state changes in mid-frame, victory backgrounds, cursor on every tile; then one frame captured from the VGA pins and compared pixel by pixel; 640×480@60 sync timing |
| `tb_pipe_puzzle_game` | All of the models above at once | Title image on the VGA pins, start, cursor, rotate, R, three levels solved with key strokes, victory hold, level change, final level, `KEY[0]` restart from every level |

Level solutions are never hard-coded. The solver in `pipe_ref_model.vh` reads the level tables from the design and finds every leak-free network from inlet to outlet (1, 2 and 1 networks for levels 1, 2 and 3), so the benches keep working when a level is redesigned and fail if a level becomes unsolvable.

Hand-computed boards in `tb_pipe_manager` (a solved path, a path through all 16 tiles, leaks at each edge, a closed loop) check the golden model itself.

### Functional coverage

Every bench ends with a coverage table and fails if a bin is empty. 314 bins in total, for example:

- a leak caused by each side of each tile, and the inlet and outlet exemptions (64 bins)
- each tile turned, wet, selected, drawn with a red border, drawn with a blue pipe
- victory on each level; the three ways a board is not solved
- timer overflow, R and restart on each level
- each key pressed and released; cursor on each tile, blocked at each edge
- `KEY[0]` on each level; board re-randomised by R, by a level change and by a restart

### Do the benches catch bugs?

59 single bugs were injected into copies of the RTL (wrong opening table entry, swapped ports in the top level, off-by-one in a timer, wrong scan code, shifted pixel, shorter sync pulse, and so on). All 59 made at least one bench fail.

## Known issues in the design

The benches found four behaviours that differ from what the game is meant to do. They are reported as `KNOWN ISSUE` and do not fail a run unless `STRICT=1` is set.

| Id | Where | Behaviour |
| --- | --- | --- |
| KI-1 | `pipe_puzzle_game.v` | The first level-1 board after power-up is not randomised. Nothing resets the pipe manager when the game starts, so every tile is at orientation 0. The "randomise while disabled" branch of `pipe_manager` cannot be reached, because `enable` is already 1 when the first rotate pulse arrives. |
| KI-2 | `pipe_puzzle_game.v` | `delay_counter` is not cleared when `KEY[0]` or R ends a victory during its two-second hold. The next victory screen is shorter by the time already counted. |
| KI-3 | `ps2_driver.v` | Parity and stop bit are not checked; a corrupted frame is acted on. |
| KI-4 | `ps2_driver.v` | The receiver has no idle time-out. One stray falling edge on `PS2_CLK` leaves it one bit out of step until `KEY[0]` is pressed. |

Other observations, not counted as issues:

- Several registers have no reset or initial value (`Packet_Count`, `ps2_shift_reg`, `break_received`, `draw_x`, `draw_y`, `restart`). They are X in simulation until `KEY[0]` is pressed once, so every bench starts with a `KEY[0]` pulse. The FPGA powers them up as 0.
- `pipe_orientation` is clocked by `rotate` and asynchronously loaded with a changing value. Simulation takes the LFSR value at the reset edge; a synthesised asynchronous load may keep following it while the reset is low. Any value is acceptable here.
- The key that starts the game is also executed: Space turns tile (0,0), D moves the cursor.
- A new board can already be solved (about 1 in 8 000 random boards on level 2), which shows the victory screen at once.
- Pipes are 15 pixels wide: `PIPE_THICKNESS` is 16 with exclusive bounds on both sides.
- The VGA adapter uses porches of 19/45 pixels and 13/30 lines instead of 16/48 and 10/33. Totals and sync widths are standard.

## Simulation speed-ups

None of these edit the RTL.

| What | How | Still simulated at full length |
| --- | --- | --- |
| Timer second (50 000 000 clocks) | `ticks` parameter overridden | `make PLUSARGS=+long tb_timer` runs a real second of the default build (several minutes) |
| Victory hold (100 000 000 clocks) | `delay_counter` deposited 200 clocks before its end | The terminal count itself: the level changes exactly at 100 000 000 |
| PS/2 clock | Keyboard model runs at about 2.5 MHz | `tb_ps2_driver` also sends keys at 10, 12.5 and 16.7 kHz |
| Title image | `+no_mif` skips loading the 307 200-word MIF | The system bench loads it and checks it on the VGA pins |

## Plusargs

| Plusarg | Effect |
| --- | --- |
| `+seed=<n>` | Seed of the random stimulus (default 1) |
| `+waves` | Write `<testbench>.vcd` |
| `+strict` | Known issues become errors |
| `+long` | `tb_timer`: simulate a real second of the default build |
| `+mif_dir=<dir>` | Directory of `Pipe_cover_9bit.mif` for the video-memory model |
| `+no_mif` | Start the video memory at zero |

## Limits

- RTL simulation only: no gate-level or timing simulation, and metastability on the PS/2 inputs is not modelled.
- `altsyncram` and `altpll` are behavioural models of the configurations this project uses, not Intel's own.
- The benches read internal signals of the design (level, board, orientation register, video-memory port). Renaming those signals means updating the benches.
