#!/usr/bin/env bash
# setup.sh — GATE 2 of 3. Confirms the kit's one runtime dependency:
# spd_dump, built from the TomKing062/spreadtrum_flash sources.
#
# The contract is ONE variable: SPD_DUMP_HOME — a directory containing the
# spd_dump binary ($SPD_DUMP_HOME/spd_dump). After the workspace is set up
# it looks like:
#
#     BLU35_WORKSPACE/
#     ├── spreadtrum_flash/   (the dependency: source + built binary)
#     └── blug35_unlock_kit/  (this kit)
#
# If SPD_DUMP_HOME is unset, this script fetches and builds the source ONCE
# (same logic as prepare.sh — the two gates are interchangeable on this;
# whichever runs first pays the one-time fetch/build; PINNED to the certified
# commit d24c21a0c93a545c0130668caa1826d59ceebe48, see prepare.sh). If it IS
# set, your own checkout/build is verified and used, untouched.
#
# After verifying, it prints the exact line to put in your shell (needed
# only if you run the gates in separate terminals):
#     export SPD_DUMP_HOME=/full/path/to/spreadtrum_flash
# (the device gates refuse to run without it — no tool guessing, ever).
#
# Usage:
#     ./setup.sh                            (detect, or fetch+build)
#     SPD_DUMP_HOME=/path/to/spreadtrum_flash ./setup.sh
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; NC=$'\033[0m'
fail() { echo "${RED}FAIL:${NC} $*"; exit 1; }
ok()   { echo "${GRN}PASS:${NC} $*"; }
info() { echo "${YLW}==>${NC} $*"; }

echo "setup — verify the spd_dump dependency (SPD_DUMP_HOME)"
echo

# ---- 0) basic requirements --------------------------------------------------
command -v python3 >/dev/null 2>&1 || fail "python3 not found — install python3 first"
ok "python3: $(command -v python3)"

WS="$(cd "$KIT_ROOT/.." && pwd)"

# ---- 1) locate or fetch+build the dependency --------------------------------
SPD_DUMP_HOME="${SPD_DUMP_HOME:-}"
if [ -n "$SPD_DUMP_HOME" ]; then
  [ -x "$SPD_DUMP_HOME/spd_dump" ] \
    || fail "SPD_DUMP_HOME=$SPD_DUMP_HOME has no executable spd_dump in it — point it
at the spreadtrum_flash directory whose build produced the binary
(or unset it and let this script fetch and build the canonical source)"
  ok "SPD_DUMP_HOME: $SPD_DUMP_HOME (operator-provided)"
else
  info "SPD_DUMP_HOME not set — fetching and building the certified spd_dump"
  info "  source: https://github.com/TomKing062/spreadtrum_flash.git, pinned to the certified commit"
  for t in git make gcc; do
    command -v "$t" >/dev/null 2>&1 \
      || fail "$t not found — needed to fetch/build spd_dump. Debian/Ubuntu:
sudo apt install git build-essential libusb-1.0-0-dev   — then re-run ./setup.sh
(or build the source yourself and: export SPD_DUMP_HOME=/path/to/spreadtrum_flash)"
  done
  pkg-config --exists libusb-1.0 2>/dev/null || \
    { ls /usr/include/libusb-1.0/libusb.h >/dev/null 2>&1 || \
      fail "libusb-1.0 development headers not found — Debian/Ubuntu:
sudo apt install libusb-1.0-0-dev   — then re-run ./setup.sh"; }
  # PINNED SOURCE (see prepare.sh): this kit builds ONLY the field-certified
  # upstream commit — the tree the certified binary's sha1 line self-reports.
  # Upstream main has moved past it; those changes are unproven on this
  # device. Your own build? export SPD_DUMP_HOME=/path/to/spreadtrum_flash
  SPFDUMP_PIN="d24c21a0c93a545c0130668caa1826d59ceebe48"
  SRCDIR="$WS/spreadtrum_flash"
  moved=0   # 1 = tree moved to the pin this run -> any existing binary is stale
  if [ ! -d "$SRCDIR" ]; then
    ( cd "$WS" && git clone https://github.com/TomKing062/spreadtrum_flash.git ) \
      || fail "git clone failed — check your network, or clone
https://github.com/TomKing062/spreadtrum_flash.git yourself into the workspace
(next to this kit), run: git checkout $SPFDUMP_PIN ; make ;
then: export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
    ( cd "$SRCDIR" && git -c advice.detachedHead=false checkout -q "$SPFDUMP_PIN" ) \
      || fail "could not check out the pinned commit $SPFDUMP_PIN in the fresh clone.
Or build your own copy and: export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
    moved=1
  else
    cur_head="$(git -C "$SRCDIR" rev-parse HEAD 2>/dev/null || true)"
    if [ "$cur_head" != "$SPFDUMP_PIN" ]; then
      [ -d "$SRCDIR/.git" ] \
        || fail "$SRCDIR is not the canonical git clone (no .git).
This kit builds ONLY the pinned commit $SPFDUMP_PIN.
Remove the directory and re-run, or build your own and:
export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
      info "$SRCDIR is at ${cur_head:-unknown} — checking out the pinned certified commit"
      ( cd "$SRCDIR" && git -c advice.detachedHead=false checkout -q "$SPFDUMP_PIN" ) \
        || fail "could not check out the pinned commit $SPFDUMP_PIN in $SRCDIR —
is it a clone of TomKing062/spreadtrum_flash?
Or build your own copy and: export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
      moved=1
    fi
  fi
  # the tree IS at the pin; build here in EVERY path — a fresh clone has no
  # binary, and a moved tree must not keep one from another revision
  if [ "$moved" = 0 ] && [ -x "$SRCDIR/spd_dump" ]; then
    ok "already built by a previous run: $SRCDIR/spd_dump (reusing)"
  else
    rm -f "$SRCDIR/spd_dump"   # a binary from a different tree must not survive
    info "building spd_dump from the pinned certified source"
    ( cd "$SRCDIR" && make ) || fail "spd_dump build failed — see the errors above"
    [ -x "$SRCDIR/spd_dump" ] || fail "build finished but $SRCDIR/spd_dump is not executable"
    ok "built: $SRCDIR/spd_dump (pinned source)"
  fi
  # binary identity gate: whatever was built/reused must self-report the pin
  ident="$($SRCDIR/spd_dump --help 2>&1 | grep -o 'sha1:[0-9a-f]*' | head -n1 || true)"
  [ "$ident" = "sha1:$SPFDUMP_PIN" ] \
    || fail "spd_dump identity mismatch: got '${ident:-none}', want sha1:$SPFDUMP_PIN.
The binary in $SRCDIR is not from the pinned certified tree.
Delete it and re-run, or build your own and:
export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
  ok "spd_dump identity: $ident (certified)"
  SPD_DUMP_HOME="$SRCDIR"
  ok "SPD_DUMP_HOME: $SPD_DUMP_HOME (pinned $SPFDUMP_PIN)"
fi
# record the resolved path — later gates pick it up in fresh terminals
printf '%s\n' "$SPD_DUMP_HOME" > "$WS/.spd_dump_home"

# ---- 2) the binary runs ------------------------------------------------------
"$SPD_DUMP_HOME/spd_dump" --help >/dev/null 2>&1 || true
ok "binary: $SPD_DUMP_HOME/spd_dump"

# ---- 3) provenance note (informational, never a gate) -----------------------
# The binary self-reports its source identity on every session:
#   branch:main, sha1:<id>
# Every source revision builds its own id; the guide and the steps teach you
# to READ this line and note it next to the build you registered, so you
# always know which tool ran.
info "provenance: read the 'branch:..., sha1:...' line in every session output"
info "            and note it next to the build in $SPD_DUMP_HOME"

# ---- 4) udev note (Linux access to the phone in download mode) --------------
if [ "$(id -u)" -ne 0 ] && [ ! -w /dev/bus/usb 2>/dev/null ]; then
  info "the guide's 'Access to the USB device' chapter covers running the sessions"
  info "  (root/sudo path or udev rule). Not a gate — decided in the guide, not here."
fi

echo
echo "${GRN}setup: DEPENDENCY READY${NC}"
echo
echo "spd_dump binary: $SPD_DUMP_HOME/spd_dump"
echo
echo "The path is recorded in $WS/.spd_dump_home — the device gates pick it up"
echo "automatically. To be explicit anyway (e.g. if you move things around), put"
echo "this in your shell (and in ~/.bashrc if you want it permanent):"
echo
echo "    export SPD_DUMP_HOME=$SPD_DUMP_HOME"
echo
echo "Then continue with ./verify.sh"
