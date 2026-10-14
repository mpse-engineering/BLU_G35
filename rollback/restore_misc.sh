#!/usr/bin/env bash
# restore_misc.sh — put the original misc partition content back, removing a
# pending recovery wipe (BCB) if one was staged but not consumed.
# Run:  ./rollback/restore_misc.sh
. "$(dirname "$0")/../scripts/common.sh"

echo "rollback — restore original misc (WRITES FLASH: misc)"
echo

confirm "write the ORIGINAL misc partition image (captured at extraction).
Removes a pending BCB wipe if one was staged. Type YES when the phone is
in download mode."
echo "running: $SPD_DUMP ... exec w misc official/misc.bin reset"
connect w misc official/misc.bin reset || fail "misc restore failed (full output above)"

echo
ok "original misc restored"
echo "Note: misc read-back verification is not performed here — the BCB"
echo "content is state-dependent. If you need proof, compare a fresh"
echo "read_part misc dump against official/misc.bin manually."
