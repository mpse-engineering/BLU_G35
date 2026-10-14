#!/usr/bin/env bash
# step08_wipe_data.sh — the unlock requires a userdata wipe. This stages the
# stock-recovery wipe by writing a boot-recovery BCB image ("recovery
# --wipe_data") into misc; on reboot, stock recovery performs the wipe and
# boots fresh. official/misc.bin (captured at extraction) restores the
# original misc content via rollback/restore_misc.sh if ever needed.
# Run:  ./scripts/step08_wipe_data.sh
. "$(dirname "$0")/common.sh"

echo "step08 — data wipe via BCB (WRITES FLASH: misc)"
echo

# ---- [public-kit addition] GUI-reset supersession ask (field 2026-09-30) ----
# After step07's boot the phone ITSELF offered the factory reset (the
# encryption state changed); the operator accepted it. That GUI reset IS the
# wipe — staging the BCB afterwards would only schedule a SECOND wipe.
ask_choice "Did the on-screen factory reset already happen after step07's boot? (y/n)" y n
case "$CHOICE" in
  y)
    ok "on-screen reset already performed — the wipe is done; NOT staging the BCB"
    echo "  (staging it now would only schedule a SECOND wipe of an already-fresh phone)"
    echo
    echo "Next: complete Android setup (skip what you like), then root:"
    echo "    ./root_with_magisk.sh        # fetch Magisk + patch + write (guide ch. 8)"
    exit 0 ;;
esac

confirm "write the boot-recovery BCB into misc; the phone reboots into recovery
and wipes userdata by itself. This erases apps/accounts/settings (the unlock
requires it). Type YES to proceed."
echo "running: $SPD_DUMP ... exec w misc artifacts/misc-wipe.bin reset"
connect w misc artifacts/misc-wipe.bin reset || fail "misc write failed (full output above)"

echo
ok "BCB staged — the phone wipes and boots unlocked, fresh"
echo "After first boot: complete setup, enable Developer options + USB debugging,"
echo "then root: ./root_with_magisk.sh — it installs Magisk, patches the STOCK"
echo "init_boot in the Magisk app and writes it through the gated download-agent"
echo "writer (never fastboot: its write path is broken on this phone; the patched"
echo "image needs no signing — the unlocked chain skips AVB)."
echo
echo "Undo (before reboot only): rollback/restore_misc.sh"
