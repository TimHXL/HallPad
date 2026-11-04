#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
v="${VERILATOR_BIN:-verilator}"
python3 verification/test_converter.py
python3 verification/test_hpg2.py
python3 verification/make_sd_fixture.py
"$v" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
"$v" --binary --timing -Wno-fatal -Iverification -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_v6_offline --Mdir obj_v6_offline src/*.v verification/tb_v6_offline.sv
./obj_v6_offline/Vtb_v6_offline
"$v" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_v6_render --Mdir obj_v6_render src/keyboard_menu_renderer.v src/menu_font5x7.v verification/tb_v6_render.sv
./obj_v6_render/Vtb_v6_render
