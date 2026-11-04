#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
v="${VERILATOR_BIN:-verilator}"
"$v" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
run_test() {
 t="$1"; shift
 "$v" --binary --timing -Wno-fatal -Iverification -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module "$t" --Mdir "obj_$t" "$@" "verification/$t.sv"
 "./obj_$t/V$t"
}
run_test tb_v7_cal src/drum_cal_control.v src/logger_calibration.v
run_test tb_v7_delay src/keyboard_response_monitor.v
run_test tb_v7_xy src/audio_lissajous.v src/audio_monitor_rom.v
run_test tb_v7_font src/menu_font5x7.v
run_test tb_v3_slots src/drum_slot5ms.v src/drum_i2c_master.v src/drum_strip_lights.v src/drum_strip_rgb_ram.v src/drum_hit_lights.v src/drum_ripple_envelope.v
run_test tb_route_protocol src/*.v verification/hallpad_protocol_ctrl_reference.v
python3 verification/test_v7_converter.py
run_test tb_hpg3 src/hallpad_hpg3.v
run_test tb_v7_runner src/hallpad_practice_runner.v
run_test tb_v7_overlap src/hallpad_practice_runner.v
run_test tb_v7_bundle_flow src/hallpad_hpg3.v src/hallpad_offline_ctrl.v src/hallpad_practice.v src/hallpad_practice_runner.v
run_test tb_v7_legacy src/*.v
run_test tb_v7_render src/keyboard_menu_renderer.v src/menu_font5x7.v

python3 verification/make_bundle_sd_fixture.py
run_test tb_v7_sd_bundle src/hallpad_hpg3.v src/hallpad_sd_catalog.v src/hallpad_offline_ctrl.v src/hallpad_practice.v src/hallpad_practice_runner.v
