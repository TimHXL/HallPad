#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tool="${VERILATOR:-verilator}"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
"$tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_i2c_link --Mdir "$root/bus" verification/tb_i2c_link.sv src/drum_i2c_master.v
"$root/bus/Vtb_i2c_link"
"$tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_hp_driver --Mdir "$root/driver" verification/tb_hp_driver.sv src/drum_mpu6050.v
"$root/driver/Vtb_hp_driver"
"$tool" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
