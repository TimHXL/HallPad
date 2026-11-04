#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
v="${VERILATOR_BIN:-verilator}"
"$v" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
run_test() {
 t="$1";shift
 "$v" --binary --timing -Wno-fatal -Iverification -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module "$t" --Mdir "obj_$t" "$@" "verification/$t.sv"
 "./obj_$t/V$t"
}
python3 verification/test_v7_converter.py
python3 verification/make_bundle_sd_fixture.py
run_test tb_v7_font src/menu_font5x7.v
run_test tb_hpg3 src/hallpad_hpg3.v
run_test tb_v8_preview src/hallpad_hpg3.v src/hallpad_title_preview.v src/hallpad_sd_catalog.v src/hallpad_offline_ctrl.v src/hallpad_practice.v src/hallpad_practice_runner.v
run_test tb_v7_legacy src/*.v
run_test tb_v8_render src/keyboard_menu_renderer.v src/menu_font5x7.v src/hallpad_offline_layout.v src/hallpad_title_scroll.v
