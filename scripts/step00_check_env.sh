#!/usr/bin/env bash
# step00_check_env.sh — environment preflight.
# No device needed, nothing written except a write-probe file that is removed.
# Read this file, then run:  ./scripts/step00_check_env.sh
. "$(dirname "$0")/common.sh"

echo "step00 — environment preflight (device NOT required)"
echo

# --- 1) we are really inside the kit (guards against partial extraction) ---
[ -f "$KIT_ROOT/MANIFEST.sha256" ] || fail "MANIFEST.sha256 not found at kit root — incomplete extraction or wrong cwd"
[ -d "$KIT_ROOT/scripts" ]         || fail "scripts/ missing at kit root"
[ -f "$KIT_ROOT/artifacts/spl-unlock.bin" ]     || fail "artifacts/spl-unlock.bin missing"
[ -f "$KIT_ROOT/artifacts/uboot-patched.bin" ]  || fail "artifacts/uboot-patched.bin missing"
[ -f "$KIT_ROOT/artifacts/misc-wipe.bin" ]      || fail "artifacts/misc-wipe.bin missing"
[ -f "$KIT_ROOT/official/splloader.bin" ]       || fail "official/splloader.bin missing"
[ -f "$KIT_ROOT/official/uboot.bin" ]           || fail "official/uboot.bin missing"
[ -f "$KIT_ROOT/fdl/fdl1-dl.bin" ]              || fail "fdl/fdl1-dl.bin missing"
[ -f "$KIT_ROOT/fdl/fdl2-dl.bin" ]              || fail "fdl/fdl2-dl.bin missing"
[ -f "$KIT_ROOT/fdl/fdl2-cboot.bin" ]           || fail "fdl/fdl2-cboot.bin missing (the unlock writer)"
[ -f "$KIT_ROOT/fdl/custom_exec_no_verify_4ee8.bin" ] \
  || fail "fdl/custom_exec_no_verify_4ee8.bin missing (spd_dump exec_addr payload)"
# its content hash is pinned inside verify_artifacts.py (checked below)
ok "kit tree complete (all required files present)"
echo "  kit root: $KIT_ROOT"

# --- 2) tools ---
command -v python3 >/dev/null 2>&1 || fail "python3 not found in PATH — required"
ok "python3: $(python3 -V 2>&1)"
# SPD_DUMP is mandatory — common.sh already refused to run without it
ok "spd_dump: $SPD_DUMP"
"$SPD_DUMP" --help >/dev/null 2>&1 && ok "spd_dump runs" \
  || fail "spd_dump found at '$SPD_DUMP' but does not execute (wrong arch? missing loader?)"

# --- 2b) artifacts: re-prove every patched byte (fatal) ---
# verify_artifacts.py re-derives both artifacts from the official dumps with
# embedded math only and pins all security-relevant hashes. If this fails,
# the package is tampered/wrong — no device step may run.
python3 "$KIT_ROOT/verify_artifacts.py" || fail "artifact verification FAILED — see the FAIL lines above. Do not run any later step."

# --- 3) shell sanity: bash + pipefail supported ---
[ -n "${BASH_VERSION:-}" ] || fail "must run under bash (run: bash $0)"
(set -o pipefail) 2>/dev/null || fail "shell does not support 'pipefail'"
ok "bash ${BASH_VERSION%%.*} with pipefail"

# --- 4) working tree is writable (rollback logs and dumps land here) ---
PROBE=".kit_write_probe.$$"
if ( : > "$PROBE" ) 2>/dev/null; then rm -f "$PROBE"; ok "kit directory writable"; else fail "kit directory not writable: $KIT_ROOT"; fi

# --- 5) disk headroom (device dumps + logs, generous bound) ---
AVAIL_KB=$(df -Pk "$KIT_ROOT" | awk 'NR==2 {print $4}')
[ "${AVAIL_KB:-0}" -ge 1048576 ] || fail "less than 1 GiB free at $KIT_ROOT (have ${AVAIL_KB:-0} KiB)"
ok "disk headroom: $(( AVAIL_KB / 1024 )) MiB free"

# --- 6) no conflicting USB grabber (Windows-side adb is the usual culprit) ---
if command -v adb >/dev/null 2>&1; then
  adb kill-server >/dev/null 2>&1 || true
  echo "${YLW}NOTE${NC}: adb detected on this host — its server grabs devices in download mode."
  echo "       Killed it for this session; if it respawns (service/IDE), stop it properly."
else
  ok "no adb on host"
fi

echo
ok "environment preflight complete — next: scripts/step01_verify_package.sh"
