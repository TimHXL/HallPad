# OfflineGuide verification — 2026-10-31

## Actual RTL simulation: PASS

Verilator built and ran these testbenches against the delivered RTL, not replacement behavioral models:

- tb_drum_control: existing first-entry/manual calibration, reconnect/fault/timeout; light envelope/hold/brightness/off; live RGB changes without envelope restart, custom black, fixed-mode hits preserve palette counter, switching back restores per-pixel palette index.
- tb_drum_protocol: real HELLO session, calibration control/cache dedup/busy/invalid payload, old 6-byte light configuration; new 0x7D set, invalid mode/length rejection without partial update, 0x7E/7F byte-order readback, CAPS bit24.
- tb_offline: actual FAT32 catalog, offline controller, protocol ownership mux and existing hallpad_practice/runner. Reads an MBR FAT32 volume through a block-level SD fixture; root chain 2→4 and score chain 5→9→7→11 are fragmented. Loads 64 records into the shared score RAM and reaches READY. Starts without a BLE session; establishes a HELLO session during local practice and lets it expire, verifying local phase and guidance persist. Checks physical short-note hit, long-note yellow and early-release advance, pause/resume/stop/exit, damaged score CRC rejection, wrong key-binding rejection.

Final offline result:

```
PASS: FAT32 MBR, fragmented root/file, shared RAM load/CRC/binding, standalone LED follow/early release/pause/resume/stop, no BLE session
```

The test accelerates ms_tick. The sector fixture replaces the physical SD/SPI card, not the FAT/file/loader/validator logic. It does NOT prove board electrical behavior, real SD card timing, BLE radio transport, or Gowin timing closure. SPI reader is reused from the known HP logger source, with write request tied low.

## Converter: PASS

Four standard-library unit tests: tempo map + file CRC/binding, running-status chord parsing, unmappable pitch rejection, invalid/empty input rejection. SCALE.HPG is generated from the bundled example mapping and group list; header and body CRC verified during packaging.

## Project checks

All production RTL passed syntax checking with pyslang. Whole-source elaboration retains exactly the baseline 18 MissingTimeScale and 1 audio_engine_top held_revisions UsedBeforeDeclared errors; no new errors. All 81 GPRJ source/constraint references exist. Testbenches are not included in synthesis.

No Gowin synthesis/place-and-route or board test was performed for this revision. No precompiled bitstream is included.

Run on a machine with Verilator, C++ build tools and Python3:

```
bash verification/run_rtl.sh
```

VERILATOR may specify the installed executable path. Pyslang is only used for the additional static check and is not required to run the Verilator tests.

## Drum80 current-version regression — PASS

Current 80-pixel revision built and ran these actual RTL tests:

- tb_drum80: 80 pixels per stick, bottom-to-top arrival, 500 and 30000 speed endpoints, fixed chord color window, same-stick retrigger clears old wave without affecting the other, linear fade to zero, solid RGB on all 80 without hits, brightness zero/off, no old-wave resurrection, complete 80-pixel GRB serial frame decoding. Passed after the final strip worker edits.
- tb_drum_protocol: 0x83/84/85 set/readback, mode/brightness/speed/length validation and atomic rejection, CAPS bit25, old SET selects legacy; prior RGB/calibration/light protocol tests also passed.
- tb_offline: fragmented FAT32/score loading, shared RAM validation, standalone guide, BLE session expiry isolation, early release, pause/resume/stop/exit, bad CRC/binding rejection. Passed with this revision's protocol controller.

Static check: exactly baseline 18 MissingTimeScale + 1 held_revisions UsedBeforeDeclared; no new syntax/elaboration errors. All 82 project references exist. No new Verilator latch/multidriver/combinational-loop diagnostics in these three test builds. Existing calibration/legacy pixel code is retained unchanged except its output is gated while the new engine owns the strips.

Tests use accelerated ms ticks and digital signal models; no physical 80-pixel strip, board power, Gowin synthesis or place-and-route was validated.

## Drum80_Diag update

PASS: tb_joystick_swap — horizontal endpoint depths reversed (127/32), vertical pitch endpoints unchanged (+8191/-8191). Whole-source syntax/elaboration retains only baseline errors. MPU/I2C failure policy is unchanged; new diagnostic display needs board verification.

## RAM revision — current tests

PASS tb_strip_ram: two synchronous RAM banks per strip, all 80 unique pixels on both channels, exact 320/880ns pulses and 1280ns bit periods including pixel boundaries, inactive-bank writes concurrent with active-bank reads, atomic bank swap.
PASS tb_drum80: full effects regression against the RAM-backed implementation (wave speed endpoints, 80 pixels, chord/retrigger/isolation/fade/solid/off/GRB).
PASS tb_drum_protocol: reset RELEASE_MS=400 assertion plus existing calibration, old light, RGB and three-mode protocol regression.
No new syntax/elaboration errors. Previous offline/joystick/calibration logic is retained; this RAM revision did not rerun every unchanged standalone test. No Gowin synthesis or PNR was run.
