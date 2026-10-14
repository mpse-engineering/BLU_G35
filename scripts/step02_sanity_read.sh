#!/usr/bin/env bash
# step02_sanity_read.sh — first device contact. READ-ONLY: pulls splloader and
# uboot_a/uboot_b from the device and compares them byte-for-byte against the
# dumps this kit was built from. Proves addressing, FDL chain, cable and
# tooling in one shot — before any write-shaped command exists in the flow.
# Run:  ./scripts/step02_sanity_read.sh
. "$(dirname "$0")/common.sh"

echo "step02 — device sanity (READ-ONLY)"
echo

mkdir -p work
rm -f splloader.bin uboot_a.bin uboot_b.bin
confirm "connect in download mode and READ splloader + uboot_a + uboot_b.
NO writes of any kind. The phone must be in download mode before you press YES."
echo "running: $SPD_DUMP --wait 300 exec_addr 0x4ee8 fdl fdl/fdl1-dl.bin 0x5000 fdl fdl/fdl2-dl.bin 0x9efffe00 exec r splloader r uboot_a r uboot_b reset"
connect r splloader r uboot_a r uboot_b reset || fail "spd_dump session failed (full output above)"

[ -f splloader.bin ] || fail "splloader.bin was not read back — is the device in download mode?"
[ -f uboot_a.bin ]   || fail "uboot_a.bin was not read back"
[ -f uboot_b.bin ]   || fail "uboot_b.bin was not read back"
mv splloader.bin work/splloader.bin
mv uboot_a.bin   work/uboot_a.bin
mv uboot_b.bin   work/uboot_b.bin

info "comparing read-back against the verified dumps"
expect "splloader sha256" "$(sha_file work/splloader.bin)" "$(sha_file official/splloader.bin)"
if [ "$(sha_file work/uboot_a.bin)" = "$(sha_file official/uboot.bin)" ]; then
  ok "uboot_a   sha256 matches"
else
  fail "uboot_a does NOT match the kit's official dump — this kit targets ONE\nfirmware revision and yours differs. NO OVERRIDE EXISTS. Do not improvise:\nget the kit variant for your revision (see guide chapter 7)."
fi
expect "uboot_b   sha256" "$(sha_file work/uboot_b.bin)"   "$(sha_file official/uboot.bin)"

echo
ok "device addressing, FDL chain and dumps all consistent"
ok "safe to continue — next: scripts/step03_ram_boot_test.sh"
