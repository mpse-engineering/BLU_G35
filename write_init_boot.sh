#!/usr/bin/env bash
# write_init_boot.sh — the gated way to write an init_boot image (the root
# step, and the OTA-recovery tool). This is the MOST IMPORTANT write of the
# whole journey, so it gets the same discipline as every other write:
# preflight, kill-switch prompt, write + hash-verified read-back, verdict.
#
#     IMG=magisk_patched-XXXXX.img ./write_init_boot.sh
#
# Do NOT use fastboot flash on this device — its write path is broken
# (proven twice: 'Write img fail!' and a USB drop mid-write). Every
# partition write on this phone goes through the download agent, with a
# hash-verified read-back. This script is that discipline, applied to the
# one write the kit's steps don't cover.
#
# Uses:
#   - initial root: IMG=<magisk-patched init_boot> (made in the Magisk app,
#     guide chapter 6)
#   - OTA recovery: read the NEW stock image out, patch it in the Magisk
#     app, write it back with this script — root restored after any OTA.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
# decision gate (case-sensitive, re-asks — never throws work away)
. "$KIT_ROOT/tools/ask_continue.sh"
cd "$KIT_ROOT"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; NC=$'\033[0m'
fail() { echo "${RED}FAIL:${NC} $*"; exit 1; }
ok()   { echo "${GRN}PASS:${NC} $*"; }
info() { echo "${YLW}==>${NC} $*"; }
sha()  { python3 - "$1" <<'PY'
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
PY
}

[ -f .verified ] || fail "workspace contract incomplete — run ./verify.sh first"
# dependency: SPD_DUMP_HOME — explicit export wins; else the path recorded by
# prepare.sh/setup.sh in ../.spd_dump_home; else refuse with instructions
[ -n "${SPD_DUMP_HOME:-}" ] || SPD_DUMP_HOME="$(cat "$(cd "$KIT_ROOT/.." && pwd)/.spd_dump_home" 2>/dev/null || true)"
[ -n "${SPD_DUMP_HOME:-}" ] || fail "SPD_DUMP_HOME is not defined — run ./prepare.sh first (it fetches and
builds the canonical spd_dump into the workspace and records the path), or:
    export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
SPD_DUMP="$SPD_DUMP_HOME/spd_dump"
[ -x "$SPD_DUMP" ] || fail "SPD_DUMP_HOME=$SPD_DUMP_HOME has no executable spd_dump in it"

IMG="${IMG:-}"
[ -n "$IMG" ] || fail "usage: IMG=/path/to/init_boot-image.img ./write_init_boot.sh
  (the image you want in init_boot_a: your Magisk-patched one for root,
   or a stock one to return to unpatched boot)"
[ -f "$IMG" ] || fail "IMG=$IMG does not exist"

# ---- preflight ---------------------------------------------------------------
info "preflight"
SZ="$(stat -c%s "$IMG")"
[ "$SZ" = "8388608" ] || fail "image size is $SZ, expected 8388608 — is this really an init_boot image for this device?"
ok "image size correct (8388608 bytes)"

ask_choice "Confirm this image is what you intend to boot (its name: $(basename "$IMG")) — y or n" y n
case "$CHOICE" in
  n) echo "[operator aborted: n — nothing further was done]"; exit 1 ;;
esac

# ---- kill-switch prompt -------------------------------------------------------
echo
ask_continue YES "ABOUT TO: write into init_boot_a (the ACTIVE boot slot), then read it back and compare hashes. Nothing else is touched. Phone must be in download mode (power off ~10 s, hold VOL_UP, plug USB)."

# ---- write + read-back --------------------------------------------------------
cp fdl/custom_exec_no_verify_4ee8.bin custom_exec_no_verify_4ee8.bin
want="a06838f71a2e938f4abb66cd80b1ef7992640db8d939d81c093fb60b83849cd9"
[ "$(sha custom_exec_no_verify_4ee8.bin)" = "$want" ] || fail "staged exec payload hash mismatch"
rm -f init_boot_a.bin

"$SPD_DUMP" --wait 300 exec_addr 0x4ee8 \
  fdl fdl/fdl1-dl.bin 0x5000 \
  fdl fdl/fdl2-dl.bin 0x9efffe00 \
  exec w init_boot_a "$IMG" r init_boot_a reset \
  || fail "download session failed — see output above; the phone is fine, retry"

# ---- verdict ------------------------------------------------------------------
[ -f init_boot_a.bin ] || fail "read-back missing — write not proven; do not boot until re-run"
H_IMG="$(sha "$IMG")"; H_FB="$(sha init_boot_a.bin)"
if [ "$H_IMG" = "$H_FB" ]; then
  ok "read-back hash matches the image — the write is PROVEN in flash"
  echo "$H_IMG  $(basename "$IMG")" > logs/init_boot_write_last.txt
  rm -f init_boot_a.bin
  echo
  echo "${GRN}write_init_boot: DONE${NC}"
  echo "  Boot the phone normally (just power on)."
  echo "  - Magisk-patched image -> open the Magisk app: expect 'Installed'."
  echo "    Hard proof: adb shell su -c id  (uid=0 root)."
  echo "  - Stock image -> the phone boots unpatched (unroot path)."
else
  fail "hash mismatch: image=$H_IMG read-back=$H_FB — DO NOT boot; re-run this script"
fi
