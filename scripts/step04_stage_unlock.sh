#!/usr/bin/env bash
# step04_stage_unlock.sh — FIRST flash-writing step.
# 1. re-reads splloader + uboot_a/uboot_b (fresh backups, hash-checked BEFORE
#    the write results are trusted)
# 2. erases splloader (the trigger that forces ROM fallback mode)
# 3. writes the patched LK into BOTH slots (uboot_a and uboot_b)
# 4. reads both slots back and hash-verifies them against the artifact
# The device is left unable to boot normally until step05/step07 complete.
# Recovery exists at every moment: rollback/rollback_spl_uboot.sh
# Run:  ./scripts/step04_stage_unlock.sh
. "$(dirname "$0")/common.sh"

echo "step04 — stage the unlock window (WRITES FLASH: splloader, uboot_a, uboot_b)"
echo

mkdir -p work
rm -f splloader.bin uboot_a.bin uboot_b.bin
confirm "read fresh backups, ERASE splloader, WRITE patched LK into uboot_a and uboot_b.
After this, the phone cannot boot normally until the patched SPL (step05)
or a restore has run. Type YES only if you are ready for that state."
echo "running: $SPD_DUMP ... exec r splloader r uboot_a r uboot_b e splloader w uboot_a artifacts/uboot-patched.bin w uboot_b artifacts/uboot-patched.bin reset"
connect r splloader r uboot_a r uboot_b e splloader \
  w uboot_a artifacts/uboot-patched.bin \
  w uboot_b artifacts/uboot-patched.bin reset || fail "spd_dump session failed (full output above)"

[ -f splloader.bin ] || fail "backup splloader was not read back"
[ -f uboot_a.bin ]   || fail "backup uboot_a was not read back"
[ -f uboot_b.bin ]   || fail "backup uboot_b was not read back"
mv splloader.bin work/splloader-prestep04.bin
mv uboot_a.bin   work/uboot_a-prestep04.bin
mv uboot_b.bin   work/uboot_b-prestep04.bin

info "verifying the fresh backups BEFORE trusting the writes that followed"
expect "backup splloader == official" "$(sha_file work/splloader-prestep04.bin)" "$(sha_file official/splloader.bin)"
expect "backup uboot_a == official"   "$(sha_file work/uboot_a-prestep04.bin)"   "$(sha_file official/uboot.bin)"
expect "backup uboot_b == official"   "$(sha_file work/uboot_b-prestep04.bin)"   "$(sha_file official/uboot.bin)"

info "verifying the patch landed in both slots"
rm -f uboot_a.bin uboot_b.bin
echo "running: $SPD_DUMP ... exec r uboot_a r uboot_b reset"
connect r uboot_a r uboot_b reset || fail "read-back session failed (full output above)"
[ -f uboot_a.bin ] || fail "uboot_a read-back missing"
[ -f uboot_b.bin ] || fail "uboot_b read-back missing"
mv uboot_a.bin work/uboot_a-readback.bin
mv uboot_b.bin work/uboot_b-readback.bin
expect "uboot_a readback == patched LK" "$(sha_file work/uboot_a-readback.bin)" "$(sha_file artifacts/uboot-patched.bin)"
expect "uboot_b readback == patched LK" "$(sha_file work/uboot_b-readback.bin)" "$(sha_file artifacts/uboot-patched.bin)"

echo
ok "staged: splloader erased, patched LK verified in uboot_a and uboot_b"
echo "The device currently boots ONLY via ROM fallback. Proceed to step05 —"
echo "or return to stock now: rollback/rollback_spl_uboot.sh"
