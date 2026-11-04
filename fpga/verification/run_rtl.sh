#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
sim_tool="${VERILATOR:-verilator}"
build_root="$(mktemp -d)"
trap 'rm -rf "$build_root"' EXIT
"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_drum_control --Mdir "$build_root/control" verification/tb_drum_control.sv src/drum_cal_control.v src/logger_calibration.v src/drum_hit_lights.v
"$build_root/control/Vtb_drum_control"
"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_drum_protocol --Mdir "$build_root/protocol" verification/tb_drum_protocol.sv src/hallpad_protocol_ctrl.v
"$build_root/protocol/Vtb_drum_protocol"

python3 verification/make_sd_fixture.py
"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' -Iverification --top-module tb_offline --Mdir "$build_root/offline" verification/tb_offline.sv src/hallpad_sd_catalog.v src/hallpad_offline_ctrl.v src/hallpad_protocol_ctrl.v src/hallpad_practice.v src/hallpad_practice_runner.v
"$build_root/offline/Vtb_offline"
python3 verification/test_converter.py

"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_drum80 --Mdir "$build_root/drum80" verification/tb_drum80.sv src/drum_strip_lights.v src/drum_ripple_envelope.v src/drum_hit_lights.v src/drum_strip_rgb_ram.v
"$build_root/drum80/Vtb_drum80"

"$sim_tool" --binary --timing -Wno-fatal --top-module tb_joystick_swap --Mdir "$build_root/joystick" verification/tb_joystick_swap.sv src/joystick_pitch_bend.v
"$build_root/joystick/Vtb_joystick_swap"

"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_strip_ram --Mdir "$build_root/strip_ram" verification/tb_strip_ram.sv src/drum_strip_rgb_ram.v
"$build_root/strip_ram/Vtb_strip_ram"

"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_menu_pipeline --Mdir "$build_root/menu" verification/tb_menu_pipeline.sv verification/keyboard_menu_renderer_before.v src/keyboard_menu_renderer.v src/menu_font5x7.v
"$build_root/menu/Vtb_menu_pipeline"

"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_i2c_link --Mdir "$build_root/tb_i2c_link" verification/tb_i2c_link.sv src/drum_i2c_master.v
"$build_root/tb_i2c_link/Vtb_i2c_link"

"$sim_tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_key_finish --Mdir "$build_root/tb_key_finish" verification/tb_key_finish.sv src/key_calibrate.v
"$build_root/tb_key_finish/Vtb_key_finish"
