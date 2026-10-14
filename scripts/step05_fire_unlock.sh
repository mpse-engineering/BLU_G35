#!/usr/bin/env bash
# step05_fire_unlock.sh — CANONICAL unlock write (maintainer's method).
#
# Method (from refpkg/unlock_autopatch_9863a.bat — the proven flow):
#   Phase A: from the full download agent (fdl2-dl), write fdl2-cboot.bin
#            into BOTH LK slots (uboot_a + uboot_b). cboot is fdl2-dl plus
#            exactly 8 words: an inserted "mov w0,#1; bl set_lock_status"
#            unlock-write sequence (proven: cboot_provenance.py, 32 bytes).
#   Phase B: RAM-boot spl-unlock.bin (the proven patched SPL). It loads the
#            LK slot — which now contains cboot — so CBOOT runs instead of
#            the LK and executes the unlock write itself. THE SCREEN STAYS
#            BLACK. This is expected: cboot is a download agent, not a
#            bootloader. No fastboot, no volume keys, no Android.
#   The maintainer notes the write "may need twice" — the script offers a
#   second phase-B run automatically.
# Run:  ./scripts/step05_fire_unlock.sh
. "$(dirname "$0")/common.sh"

echo "step05 — canonical unlock write (flash: cboot into uboot_a/uboot_b; then RAM boot)"
echo

stage_exec_payload   # spd_dump expects the exec_addr payload in its CWD

# ---------- Phase A: stage cboot into both LK slots ----------
echo "Phase A — write fdl2-cboot.bin into uboot_a AND uboot_b (from the download agent)"
confirm "WRITE fdl2-cboot.bin into uboot_a and uboot_b via the download agent.
This replaces the patched LK in both slots with the unlock-writer image.
Rollback stays available: rollback/rollback_spl_uboot.sh"
echo "running: $SPD_DUMP ... exec w uboot_a fdl/fdl2-cboot.bin w uboot_b fdl/fdl2-cboot.bin reset"
connect w uboot_a fdl/fdl2-cboot.bin \
        w uboot_b fdl/fdl2-cboot.bin reset || fail "cboot write session failed (full output above)"

echo "verifying cboot landed in both slots (head compare, first 717044 bytes)"
rm -f uboot_a.bin uboot_b.bin
connect r uboot_a r uboot_b reset || fail "read-back session failed (full output above)"
[ -f uboot_a.bin ] || fail "uboot_a read-back missing"
[ -f uboot_b.bin ] || fail "uboot_b read-back missing"
mv uboot_a.bin work/uboot_a-cboot.bin
mv uboot_b.bin work/uboot_b-cboot.bin

python3 - <<'PY' || fail "cboot staging verification failed (details above)"
import hashlib, sys
want = hashlib.sha256(open("fdl/fdl2-cboot.bin", "rb").read()).hexdigest()
n = len(open("fdl/fdl2-cboot.bin", "rb").read())
bad = []
for name in ("work/uboot_a-cboot.bin", "work/uboot_b-cboot.bin"):
    d = open(name, "rb").read()
    if len(d) < n or hashlib.sha256(d[:n]).hexdigest() != want:
        bad.append(name)
    else:
        print(f"PASS: {name} head == fdl2-cboot.bin (first {n} bytes)")
if bad:
    print("FAIL: cboot read-back mismatch in:", ", ".join(bad))
    sys.exit(1)
PY

# ---------- Phase B: RAM-boot the SPL so cboot runs ----------
try_unlock() {
  echo
  echo "Phase B — RAM-boot the unlock window (attempt of this session)."
  confirm "RAM-boot spl-unlock.bin. The SPL loads the LK slot, which now holds
cboot, so CBOOT runs and performs the unlock write itself.
THE SCREEN STAYS BLACK — that is SUCCESS for this phase (cboot is a
download agent, not a bootloader; nothing will appear on the display).
Do NOT hold any volume key. Do NOT expect Android."
  echo "running: $SPD_DUMP --wait 300 exec_addr 0x4ee8 fdl artifacts/spl-unlock.bin 0x5000"
  echo "NOTE: usb_recv timeout / CHECK_BAUD FAIL / device removed = the RAM"
  echo "      image took over (expected teardown — the canonical bat ignores it)."
  rc=0
  "$SPD_DUMP" --wait 300 exec_addr 0x4ee8 \
    fdl artifacts/spl-unlock.bin 0x5000 || rc=$?   # || guard: set -e must NOT kill us here
  if [ "$rc" -ne 0 ]; then
    echo "NOTE: spd_dump exited rc=$rc — expected teardown for this RAM-boot form."
  fi
  echo
  echo "Phase B fired. (Black screen is expected — cboot wrote the flag and is gone.)"
}

try_unlock
echo
echo "The maintainer notes the write 'may need twice'. Run a second Phase B? (y/n)"
read -r again || again=""   # EOF-safe: no answer = skip second attempt
if [ "$again" = "y" ]; then
  try_unlock
fi

echo
ok "canonical unlock flow executed — next: scripts/step06_verify_unlock.sh proves the flag"
info "if step06 still shows all zeros, run this script again (maintainer: may need twice)"
info "to restore the patched LK for normal booting before step07: re-run scripts/step04_stage_unlock.sh"
