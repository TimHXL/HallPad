#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tool="${VERILATOR:-verilator}"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
"$tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_score_beat --Mdir "$root/beat" verification/tb_score_beat.sv src/*.v
"$root/beat/Vtb_score_beat"
"$tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' --top-module tb_score_protocol --Mdir "$root/protocol" verification/tb_score_protocol.sv src/hallpad_protocol_ctrl.v
"$root/protocol/Vtb_score_protocol"
"$tool" --binary --timing -Wno-fatal -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include' -Iverification --top-module tb_offline --Mdir "$root/offline" verification/tb_offline.sv src/hallpad_sd_catalog.v src/hallpad_offline_ctrl.v src/hallpad_protocol_ctrl.v src/hallpad_practice.v src/hallpad_practice_runner.v
"$root/offline/Vtb_offline"
"$tool" --lint-only --timing -Wno-fatal --bbox-unsup --bbox-sys --top-module keyboard_top src/*.v
