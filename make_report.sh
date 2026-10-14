#!/usr/bin/env bash
# make_report.sh — assemble your success report automatically (enhancement #4:
# report-back). Run AFTER root works, with the phone connected and USB
# debugging enabled. Fills the transcript section of SUCCESS_REPORT.md and
# prints the block to paste into your post.
#
#     ./make_report.sh
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$KIT_ROOT"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; NC=$'\033[0m'
fail() { echo "${RED}FAIL:${NC} $*"; exit 1; }
ok()   { echo "${GRN}PASS:${NC} $*"; }

command -v adb >/dev/null 2>&1 || fail "adb not found — install adb (guide chapter 6) and enable USB debugging on the phone"
adb get-state >/dev/null 2>&1 || fail "no device via adb — enable USB debugging, plug the phone, accept the prompt"

[ -f MANIFEST.sha256 ] || fail "not in a kit directory"
KIT_SHA="$(sha256sum blug35_unlock_kit.tar.gz 2>/dev/null | cut -d' ' -f1 || true)"
[ -n "$KIT_SHA" ] || KIT_SHA="(see the release post for the kit tarball sha256)"

OUT="SUCCESS_REPORT_filled.md"
{
  echo "# Success report — BLU G35 unlock kit"
  echo
  echo "- Kit sha256: \`$KIT_SHA\`"
  echo "- Firmware revision (step02 fingerprint): \`(grep -h 'sha256' logs/step02_*.log 2>/dev/null | head -1 || echo 'see step02 log')\`"
  echo "- Date: $(date +%Y-%m-%d)"
  echo
  echo "## Terminal transcript"
  echo
  echo '```'
  echo "\$ adb shell getprop ro.product.model"
  echo "$(adb shell getprop ro.product.model | tr -d '\r')"
  echo
  echo "\$ adb shell getprop ro.build.display.id"
  echo "$(adb shell getprop ro.build.display.id | tr -d '\r')"
  echo
  echo "\$ adb shell uname -a"
  echo "$(adb shell uname -a | tr -d '\r')"
  echo
  echo "\$ adb shell su -c id"
  echo "$(adb shell su -c id | tr -d '\r')"
  echo
  echo "\$ adb shell su -c 'ls /data'"
  adb shell su -c 'ls /data' | tr -d '\r'
  echo '```'
  echo
  echo "## Boot screen proof"
  echo
  echo "*(attach the photo of the power-on unlocked-bootloader warning)*"
  echo
  echo "## Anything that surprised you?"
  echo
  echo "*(one or two lines)*"
} > "$OUT"

ok "report assembled: $OUT"
echo
echo "Next: attach your boot-screen photo, fill the last section, and post it"
echo "where you found the kit. Privacy: none of this exposes personal data or"
echo "IMEI — and never post get_identifier_token output (serial-derived)."
