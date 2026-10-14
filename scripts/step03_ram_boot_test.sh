#!/usr/bin/env bash
# step03_ram_boot_test.sh — prove the patched SPL runs on this silicon with
# ZERO flash writes. spl-unlock.bin is sent as FDL1 (loaded to RAM at 0x5000)
# and executed; it loads the stock chain from eMMC with verification disabled,
# and the phone should BOOT NORMALLY. This is the go/no-go gate for the run.
# Run:  ./scripts/step03_ram_boot_test.sh
. "$(dirname "$0")/common.sh"

echo "step03 — RAM-boot test (NO flash writes)"
echo

stage_exec_payload   # spd_dump expects the exec_addr payload in its CWD
confirm "send spl-unlock.bin as FDL1 to 0x5000 and EXEC it.
RAM only — nothing is written to flash. Expected on the phone:
normal boot (logo -> Android). If it does NOT boot, this is the stop point,
and the device is still completely stock."
# ---- [public-kit addition] honest verdict + up to TWO guided retries -------
# Field (2026-09-30): the first attempt answered n, the old text said STOP,
# an identical retry booted and the whole unlock succeeded. A first no-boot
# is routine ("may need twice", same as step05) and the phone is UNTOUCHED
# either way — step03 is RAM-only.
attempt=1
while :; do
  if [ "$attempt" -gt 1 ]; then echo; echo "attempt $attempt of 3:"; fi
  echo "running: $SPD_DUMP --wait 300 exec_addr 0x4ee8 fdl artifacts/spl-unlock.bin 0x5000"
  echo "NOTE: when the image RUNS, spd_dump ends with usb_recv timeout / CHECK_BAUD FAIL"
  echo "      / device removed — the phone leaves download mode because it is BOOTING."
  echo "      (The canonical bat ignores this session's exit code; the screen decides.)"
  echo "NOTE: some devices boot SILENTLY (no logo, no vibration). The host-side"
  echo "      proof of execution is that teardown signature; the verdict is the screen."
  rc=0
  "$SPD_DUMP" --wait 300 exec_addr 0x4ee8 \
    fdl artifacts/spl-unlock.bin 0x5000 || rc=$?   # || guard: set -e must NOT kill us here
  if [ "$rc" -ne 0 ]; then
    echo "NOTE: spd_dump exited rc=$rc — expected teardown for this RAM-boot form."
  fi
  echo
  echo "Watch the phone for up to ~60 s — Android may take a moment."
  echo "Did the phone boot (logo / Android / charging screen)? (y/n)"
  read -r ans || ans=""   # EOF-safe: no answer counts as "no"
  [ "$ans" = "y" ] && break
  if [ "$attempt" -ge 3 ]; then
    fail "no boot after 3 attempts — STOP HERE. Nothing was written (RAM only);
the device is completely stock. Paste this log:
  $LOG_FILE"
  fi
  echo
  echo "  One retry is ROUTINE — the same \"may need twice\" applies here as in"
  echo "  step05 (field-proven: attempt 1 no-boot, identical retry booted, the"
  echo "  whole unlock succeeded). The phone is UNTOUCHED either way: this step"
  echo "  writes nothing to flash."
  echo "  To retry:"
  echo "    1. power-cycle the phone (hold POWER ~10 s); confirm normal Android boot"
  echo "    2. power off (~10 s hold), hold VOL_UP, plug USB — download mode"
  echo "    3. answer y below (n stops; nothing was written)"
  echo
  if ! read -r -p "Retry the RAM-boot? (y/n) " ans || [ "$ans" != "y" ]; then
    fail "no boot, no retry — STOP HERE. Nothing was written (RAM only);
the device is completely stock. Paste this log:
  $LOG_FILE"
  fi
  attempt=$((attempt+1))
done

echo
ok "patched SPL proven on this silicon"
ok "next: scripts/step04_stage_unlock.sh (first flash-writing step)"
