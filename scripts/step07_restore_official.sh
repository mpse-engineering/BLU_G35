#!/usr/bin/env bash
# step07_restore_official.sh — return the boot chain to byte-exact stock.
# Writes official/splloader.bin, official/uboot.bin into BOTH slots, then
# reads all three back and hash-verifies. The unlock flag persists in
# miscdata — it is a partition write, not part of these images.
# Run:  ./scripts/step07_restore_official.sh
. "$(dirname "$0")/common.sh"

echo "step07 — restore the official boot chain (WRITES FLASH: splloader, uboot_a, uboot_b)"
echo

mkdir -p work && rm -f splloader.bin uboot_a.bin uboot_b.bin
confirm "write OFFICIAL splloader + uboot_a + uboot_b, then read back and verify.
After this the device boots stock again — with the unlock flag set."
echo "running: $SPD_DUMP ... exec w splloader official/splloader.bin w uboot_a official/uboot.bin w uboot_b official/uboot.bin r splloader r uboot_a r uboot_b reset"
connect w splloader official/splloader.bin \
  w uboot_a official/uboot.bin \
  w uboot_b official/uboot.bin \
  r splloader r uboot_a r uboot_b reset || fail "restore session failed (full output above)"

[ -f splloader.bin ] || fail "splloader read-back missing"
[ -f uboot_a.bin ]   || fail "uboot_a read-back missing"
[ -f uboot_b.bin ]   || fail "uboot_b read-back missing"
mv splloader.bin work/splloader-restored.bin
mv uboot_a.bin   work/uboot_a-restored.bin
mv uboot_b.bin   work/uboot_b-restored.bin

info "verifying the restored images against the official dumps"
expect "restored splloader == official" "$(sha_file work/splloader-restored.bin)" "$(sha_file official/splloader.bin)"
expect "restored uboot_a == official"   "$(sha_file work/uboot_a-restored.bin)"   "$(sha_file official/uboot.bin)"
expect "restored uboot_b == official"   "$(sha_file work/uboot_b-restored.bin)"   "$(sha_file official/uboot.bin)"

echo
ok "official boot chain restored, hash-verified in all three partitions"
ok "flash state is stock again; the unlock flag persists"
ok "next: scripts/step08_wipe_data.sh"
