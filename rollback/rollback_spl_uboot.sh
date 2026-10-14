#!/usr/bin/env bash
# rollback_spl_uboot.sh — EMERGENCY restore of the boot chain.
# Works from any flash state (stock, staged, erased-splloader): as long as the
# phone reaches download mode, the ROM accepts the fdl chain and rewrites
# splloader + uboot_a + uboot_b byte-exact. Read-back verified.
# Run:  ./rollback/rollback_spl_uboot.sh
. "$(dirname "$0")/../scripts/common.sh"

echo "rollback — emergency boot-chain restore (WRITES FLASH: splloader, uboot_a, uboot_b)"
echo

mkdir -p work && rm -f splloader.bin uboot_a.bin uboot_b.bin   # clear stale read-backs BEFORE the session
confirm "write OFFICIAL splloader + uboot_a + uboot_b and read them back.
Works from any state. Type YES when the phone is in download mode."
echo "running: $SPD_DUMP ... exec w splloader official/splloader.bin w uboot_a official/uboot.bin w uboot_b official/uboot.bin r splloader r uboot_a r uboot_b reset"
connect w splloader official/splloader.bin \
  w uboot_a official/uboot.bin \
  w uboot_b official/uboot.bin \
  r splloader r uboot_a r uboot_b reset || fail "restore session failed (full output above)"

[ -f splloader.bin ] || fail "splloader read-back missing"
[ -f uboot_a.bin ]   || fail "uboot_a read-back missing"
[ -f uboot_b.bin ]   || fail "uboot_b read-back missing"
mv splloader.bin work/splloader-rollback.bin
mv uboot_a.bin   work/uboot_a-rollback.bin
mv uboot_b.bin   work/uboot_b-rollback.bin

info "verifying the restored images against the official dumps"
expect "restored splloader == official" "$(sha_file work/splloader-rollback.bin)" "$(sha_file official/splloader.bin)"
expect "restored uboot_a == official"   "$(sha_file work/uboot_a-rollback.bin)"   "$(sha_file official/uboot.bin)"
expect "restored uboot_b == official"   "$(sha_file work/uboot_b-rollback.bin)"   "$(sha_file official/uboot.bin)"

echo
ok "boot chain restored byte-exact — the device is stock again"
