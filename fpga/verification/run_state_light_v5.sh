#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
v="${VERILATOR_BIN:-verilator}"
"$v" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
for t in cal pose protocol wave;do
 case "$t" in
 cal) sources="src/drum_cal_control.v src/logger_calibration.v";;
 pose) sources="src/pose_tracker.v src/drum_math.v";;
 protocol) sources="src/*.v";;
 wave) sources="src/drum_strip_lights.v src/drum_strip_rgb_ram.v src/drum_hit_lights.v src/drum_ripple_envelope.v";;
 esac
 "$v" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module "tb_v5_$t" --Mdir "obj_v5_$t" $sources "verification/tb_v5_$t.sv"
 "./obj_v5_$t/Vtb_v5_$t"
done
"$v" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_v3_slots --Mdir obj_v5_slots src/drum_slot5ms.v src/drum_i2c_master.v src/drum_strip_lights.v src/drum_strip_rgb_ram.v src/drum_hit_lights.v src/drum_ripple_envelope.v verification/tb_v3_slots.sv
./obj_v5_slots/Vtb_v3_slots
