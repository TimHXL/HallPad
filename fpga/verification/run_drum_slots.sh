#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
VERILATOR_BIN="${VERILATOR_BIN:-verilator}"
"$VERILATOR_BIN" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
"$VERILATOR_BIN" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_kp_drum_slots --Mdir obj_drum_slots src/drum_slot5ms.v src/drum_i2c_master.v src/drum_strip_lights.v src/drum_strip_rgb_ram.v src/drum_hit_lights.v src/drum_ripple_envelope.v verification/tb_kp_drum_slots.sv
./obj_drum_slots/Vtb_kp_drum_slots
"$VERILATOR_BIN" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_slot_driver --Mdir obj_drum_driver src/drum_slot5ms.v src/drum_mpu6050.v verification/tb_slot_driver.sv
./obj_drum_driver/Vtb_slot_driver
