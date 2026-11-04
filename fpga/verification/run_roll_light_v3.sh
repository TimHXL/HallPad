#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
v="${VERILATOR_BIN:-verilator}"
"$v" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
for t in dirty roll protocol slots; do
 case "$t" in
 dirty) sources="src/drum_strip_rgb_ram.v";;
 roll) sources="src/pose_tracker.v src/drum_math.v";;
 protocol) sources="src/*.v";;
 slots) sources="src/drum_slot5ms.v src/drum_i2c_master.v src/drum_strip_lights.v src/drum_strip_rgb_ram.v src/drum_hit_lights.v src/drum_ripple_envelope.v";;
 esac
 "$v" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module "tb_v3_$t" --Mdir "obj_v3_$t" $sources "verification/tb_v3_$t.sv"
 "./obj_v3_$t/Vtb_v3_$t"
done
