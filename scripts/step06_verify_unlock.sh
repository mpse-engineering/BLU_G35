#!/usr/bin/env bash
# step06_verify_unlock.sh — read the lock-flag block back and classify it.
# Geometry from the firmware RE: miscdata partition, offset 0x2000, 64 bytes.
#   all-zero  => LOCKED (flag never written)
#   populated => UNLOCKED (encrypted/encoded block — content is device-specific)
#   all-FF    => erased region; treat as LOCKED
# Run:  ./scripts/step06_verify_unlock.sh
. "$(dirname "$0")/common.sh"

echo "step06 — verify the unlock flag (READ-ONLY)"
echo

rm -f m.bin
confirm "connect and read miscdata offset 8192, 64 bytes (the lock block). NO writes."
echo "running: $SPD_DUMP ... exec verbose 2 read_part miscdata 8192 64 m.bin reset"
connect verbose 2 read_part miscdata 8192 64 m.bin reset || fail "read failed (full output above)"
[ -f m.bin ] || fail "no data read back — is the device in download mode?"
mv m.bin work/lockblock.bin

python3 - <<'PY'
d = open("work/lockblock.bin", "rb").read()
if len(d) < 64:
    print(f"FAIL: only {len(d)} bytes read (expected 64)"); raise SystemExit(1)
blk = d[:64]
if blk == b"\x00" * 64:
    print("FAIL: block all-zero => still LOCKED"); raise SystemExit(1)
if blk == b"\xff" * 64:
    print("FAIL: block all-FF => erased region, treat as LOCKED"); raise SystemExit(1)
print(f"PASS: lock block populated: {blk[:16].hex()}...")
print("      (this firmware stores it encoded — nonzero content is the unlock proof)")
PY

echo
echo "Does the lock block show populated above? (y/n)"
read -r ans
if [ "$ans" != "y" ]; then
  fail "still locked. Re-run scripts/step05_fire_unlock.sh and answer y to the
second Phase B attempt (maintainer: the write may need twice), then re-run
this step. If it stays all-zero after three full step05 runs, STOP and
report the logs."
fi

echo
ok "UNLOCK CONFIRMED — next: scripts/step07_restore_official.sh"
