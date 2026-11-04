#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
v="${VERILATOR_BIN:-verilator}"
"$v" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
for t in dirty protocol;do
 case "$t" in
 dirty) sources="src/drum_strip_rgb_ram.v verification/drum_strip_rgb_ram_reference.v";;
 protocol) sources="src/*.v verification/hallpad_protocol_ctrl_reference.v";;
 esac
 "$v" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module "tb_route_$t" --Mdir "obj_route_$t" $sources "verification/tb_route_$t.sv"
 "./obj_route_$t/Vtb_route_$t"
done
"$v" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_v3_slots --Mdir obj_route_slots src/drum_slot5ms.v src/drum_i2c_master.v src/drum_strip_lights.v src/drum_strip_rgb_ram.v src/drum_hit_lights.v src/drum_ripple_envelope.v verification/tb_v3_slots.sv
./obj_route_slots/Vtb_v3_slots
"$v" --binary --timing -Wno-fatal -Iverification -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_v6_offline --Mdir obj_route_sd src/*.v verification/tb_v6_offline.sv
./obj_route_sd/Vtb_v6_offline
