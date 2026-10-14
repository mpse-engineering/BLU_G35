#!/usr/bin/env bash
# root_with_magisk.sh — one-command root (release helper, guide chapter 8).
# Fetches the latest Magisk APK (or uses MAGISK_APK=), installs it on the
# phone with adb, pushes the STOCK init_boot so the Magisk app patches THAT
# (double-patching is impossible by construction), pulls the patched image
# back, and hands it to the gated, hash-verified writer (./write_init_boot.sh).
# No write logic of its own — the writer is the only thing here that ever
# touches flash.
#
#   ./root_with_magisk.sh                                      # latest Magisk
#   MAGISK_APK=/path/Magisk-vXX.X.apk ./root_with_magisk.sh    # pinned/offline
#   ./root_with_magisk.sh --ota                                # after an OTA
#     (see "OTA recovery mode" below)
#
# Network: ONLY the Magisk APK fetch, and only when MAGISK_APK is unset. A
# fetch failure prints the browser URL and exits cleanly — download the APK
# by hand and re-run with MAGISK_APK=.
#
# ADB_BIN= overrides the adb binary (default "adb"); used by the offline
# suite's fake-phone and by anyone with adb outside PATH.
#
# OTA recovery mode (--ota)
# -------------------------
# An OTA boots a NEW stock init_boot; patching the kit's insurance-snapshot
# copy would put old software on a new system. --ota first does a READ-ONLY
# download-mode session that reads BOTH init_boot slots straight off the
# phone, guards what it read, and only then continues into the normal
# patch-and-write flow using the CURRENT stock:
#   - a read image that still carries the Magisk signature means root was
#     NOT actually removed (the OTA did not replace init_boot) -> hard
#     refuse, nothing stored;
#   - a slot identical to the master's copy is kept as-is (no OTA on it);
#   - a changed, un-signed slot is stored beside the certified master as
#     firmware/init_boot_<X>.ota-stock.bin with a written record
#     (firmware/OTA-STOCK.txt) and the master's CHECKSUMS regenerated.
#     The canonical master files stay the pre-OTA insurance snapshot, so
#     ./rollback_to_stock.sh keeps its exact proven semantics (full box
#     state = the insured firmware). A later ./insure.sh re-run re-baselines
#     the whole master to the post-OTA phone.
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

# ---- gates (same workspace contract as every other root gate) ---------------
[ -f .verified ] || fail "workspace contract incomplete — run ./verify.sh first"
[ -f .insured ]  || fail "insurance stamp missing (.insured) — run ./insure.sh first; the certified master it builds is the stock init_boot this flow patches"
[ -n "${SPD_DUMP_HOME:-}" ] || SPD_DUMP_HOME="$(cat "$(cd "$KIT_ROOT/.." && pwd)/.spd_dump_home" 2>/dev/null || true)"
[ -n "${SPD_DUMP_HOME:-}" ] || fail "SPD_DUMP_HOME is not defined — run ./prepare.sh first (it fetches and
builds the canonical spd_dump into the workspace and records the path), or:
    export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
[ -x "$SPD_DUMP_HOME/spd_dump" ] || fail "SPD_DUMP_HOME=$SPD_DUMP_HOME has no executable spd_dump in it"
SPD_DUMP="$SPD_DUMP_HOME/spd_dump"

# ---- mode --------------------------------------------------------------------
OTA=0
if [ $# -gt 0 ]; then
  [ "$1" = "--ota" ] || fail "unknown argument: $1 (usage: ./root_with_magisk.sh [--ota])"
  OTA=1
fi

FW_DIR="$KIT_ROOT/../firmware"
CANON_A="$FW_DIR/init_boot_a.bin"
CANON_B="$FW_DIR/init_boot_b.bin"

# ---- OTA recovery phase: read the CURRENT stock off the phone -----------------
# The download-mode session shape is the kit's proven one (connect() in
# scripts/common.sh): staged exec payload (hash-checked), fdl1 + fdl2-dl,
# ops, exit command LAST (never first — decision 8). Reads only: nothing is
# written to the phone.
if [ "$OTA" = "1" ]; then
  [ -f "$CANON_A" ] || fail "certified master missing: ../firmware/init_boot_a.bin — ./insure.sh builds it"
  [ -f "$CANON_B" ] || fail "certified master missing: ../firmware/init_boot_b.bin — ./insure.sh builds it"
  mkdir -p logs work
  OTA_LOG="logs/root_with_magisk_ota_session.log"
  trap 'rm -f init_boot_a.bin init_boot_b.bin' EXIT   # read-backs never stay in the kit root

  ask_continue YES "OTA RECOVERY, step 1 of 2 — READ-ONLY session. Put the phone in DOWNLOAD MODE: power off (~10 s hold), hold VOL_UP, plug USB. This reads BOTH init_boot slots off the phone and writes NOTHING."

  info "reading the current stock init_boot (read-only; session also logged to $OTA_LOG)"
  cp fdl/custom_exec_no_verify_4ee8.bin custom_exec_no_verify_4ee8.bin
  want="a06838f71a2e938f4abb66cd80b1ef7992640db8d939d81c093fb60b83849cd9"
  [ "$(sha custom_exec_no_verify_4ee8.bin)" = "$want" ] || fail "staged exec payload hash mismatch"
  orc=0
  "$SPD_DUMP" --wait 300 exec_addr 0x4ee8 \
    fdl fdl/fdl1-dl.bin 0x5000 \
    fdl fdl/fdl2-dl.bin 0x9efffe00 \
    exec r init_boot_a r init_boot_b reset  <<< "y" 2>&1 | tee -a "$OTA_LOG" || orc=$?
  [ "$orc" -eq 0 ] || fail "read session failed (output above; also in $OTA_LOG). The phone was likely
not in download mode — power off ~10 s, hold VOL_UP, plug USB, re-run."
  [ -f init_boot_a.bin ] || fail "init_boot_a read-back missing — read not proven"
  [ -f init_boot_b.bin ] || fail "init_boot_b read-back missing — read not proven"
  [ "$(stat -c%s init_boot_a.bin)" = "8388608" ] || fail "init_boot_a read-back is $(stat -c%s init_boot_a.bin) bytes, expected 8388608"
  [ "$(stat -c%s init_boot_b.bin)" = "8388608" ] || fail "init_boot_b read-back is $(stat -c%s init_boot_b.bin) bytes, expected 8388608"
  ok "read both init_boot slots (read-only)"

  # classify each slot: unchanged / NEW stock / Magisk-signed (= still patched)
  STORE_A=0; STORE_B=0
  for S in a b; do
    W="init_boot_$S.bin"; C="$FW_DIR/init_boot_$S.bin"
    W_SHA="$(sha "$W")"; C_SHA="$(sha "$C")"
    if [ "$W_SHA" = "$C_SHA" ]; then
      ok "init_boot_$S: unchanged vs the certified master — no OTA touched this slot"
    elif LC_ALL=C grep -qa MAGISK "$W"; then
      fail "init_boot_$S read-back carries the Magisk signature — it is STILL PATCHED,
meaning the OTA did not replace init_boot and root is probably still active.
Nothing was stored; the certified master is untouched. Check the phone
(Magisk app / su -c id) and run WITHOUT --ota if root is simply gone-but-present."
    else
      info "init_boot_$S: NEW stock read from the phone (sha256 $W_SHA)"
      # NOTE: 'STORE_$S=1' would be a COMMAND, not an assignment (bash only
      # recognizes literal name=) — set each slot explicitly.
      if [ "$S" = "a" ]; then STORE_A=1; else STORE_B=1; fi
    fi
  done

  if [ "$STORE_A" = "1" ] || [ "$STORE_B" = "1" ]; then
    ask_continue YES "ABOUT TO (workspace only, no device): store the read CURRENT-stock image(s) beside the certified master as firmware/init_boot_<X>.ota-stock.bin with a written record (OTA-STOCK.txt), and regenerate the master's CHECKSUMS. The canonical master files stay the pre-OTA insurance snapshot — rollback semantics unchanged."
    REC="$FW_DIR/OTA-STOCK.txt"
    if [ ! -f "$REC" ]; then
      {
        echo "# OTA stock addendum — written by root_with_magisk.sh --ota"
        echo "# canonical init_boot_a/b.bin remain the pre-OTA insurance snapshot;"
        echo "# rollback_to_stock.sh semantics are unchanged by this file."
      } > "$REC"
    fi
    echo "== OTA stock read $(date -u +'%Y-%m-%dT%H:%M:%SZ') ==" >> "$REC"
    for S in a b; do
      if [ "$S" = "a" ]; then ST="$STORE_A"; else ST="$STORE_B"; fi
      [ "$ST" = "1" ] || continue
      W="init_boot_$S.bin"
      W_SHA="$(sha "$W")"
      cp "$W" "$FW_DIR/init_boot_$S.ota-stock.bin"
      [ "$(sha "$FW_DIR/init_boot_$S.ota-stock.bin")" = "$W_SHA" ] \
        || fail "addendum copy verification failed for init_boot_$S — aborting"
      echo "init_boot_$S: sha256 $W_SHA (stored as init_boot_$S.ota-stock.bin)" >> "$REC"
      ok "stored current stock: ../firmware/init_boot_$S.ota-stock.bin"
    done
    if [ -f "$FW_DIR/CHECKSUMS" ]; then
      ( cd "$FW_DIR" && sha256sum *.bin > CHECKSUMS )
      ok "master CHECKSUMS regenerated (includes the OTA addendum)"
    fi
  fi
  rm -f init_boot_a.bin init_boot_b.bin

  # what the patch phase must start from: the CURRENT stock (addendum if the
  # active slot was refreshed, else the canonical master — identical thing
  # when no OTA touched init_boot)
  if [ -f "$FW_DIR/init_boot_a.ota-stock.bin" ]; then
    SRC="$FW_DIR/init_boot_a.ota-stock.bin"
  else
    SRC="$CANON_A"
  fi

  ask_continue YES "OTA RECOVERY, step 2 of 2 — the patch phase needs the phone BOOTED: power it on normally, complete any unlock screen, enable Developer options + USB debugging if the OTA reset them, plug in, accept the adb authorization prompt."
else
  SRC="$CANON_A"
fi

# ---- 1) the Magisk APK -------------------------------------------------------
APK="${MAGISK_APK:-}"
if [ -z "$APK" ]; then
  info "fetching the latest Magisk release (GitHub API — the only network touch here)"
  mkdir -p work
  J=work/magisk_release.json
  API="https://api.github.com/repos/topjohnwu/Magisk/releases/latest"
  if ! wget -qO "$J" "$API" 2>/dev/null; then
    rm -f "$J"
    if ! curl -fsSL -o "$J" "$API" 2>/dev/null; then
      rm -f "$J"
      echo "${RED}FAIL:${NC} could not reach the GitHub API (offline? blocked?)."
      echo "  Download the APK yourself in a browser:"
      echo "    https://github.com/topjohnwu/Magisk/releases/latest"
      echo "  then re-run with its path:"
      echo "    MAGISK_APK=/path/to/Magisk-vXX.X.apk ./root_with_magisk.sh"
      exit 1
    fi
  fi
  python3 - "$J" > work/magisk_env.sh <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
def esc(s): return "'" + str(s).replace("'", "'\\''") + "'"
print("M_TAG=" + esc(j.get("tag_name", "?")))
apk = next((a for a in j.get("assets", [])
            if str(a.get("name", "")).lower().endswith(".apk")), None)
if apk is None:
    print("APK_URL="); print("APK_NAME="); print("APK_SIZE=0"); print("APK_DIGEST=")
else:
    d = str(apk.get("digest", "") or "")
    print("APK_URL=" + esc(apk.get("browser_download_url", "")))
    print("APK_NAME=" + esc(apk.get("name", "")))
    print("APK_SIZE=" + esc(apk.get("size", 0)))
    print("APK_DIGEST=" + esc(d.split("sha256:")[-1] if d else ""))
PY
  . work/magisk_env.sh
  [ -n "$APK_URL" ] || fail "no .apk asset in the latest Magisk release JSON — download by hand:
    https://github.com/topjohnwu/Magisk/releases/latest
  then re-run with:  MAGISK_APK=/path/to.apk ./root_with_magisk.sh"
  A=work/magisk_latest.apk
  if ! wget -qO "$A" "$APK_URL" 2>/dev/null; then
    rm -f "$A"
    if ! curl -fsSL -o "$A" "$APK_URL" 2>/dev/null; then
      rm -f "$A"
      echo "${RED}FAIL:${NC} could not download $APK_URL (offline? blocked?)."
      echo "  Download the APK yourself in a browser:"
      echo "    https://github.com/topjohnwu/Magisk/releases/latest"
      echo "  then re-run with its path:"
      echo "    MAGISK_APK=/path/to/Magisk-vXX.X.apk ./root_with_magisk.sh"
      exit 1
    fi
  fi
  APK="$A"
  [ "$APK_SIZE" = "0" ] || [ "$(stat -c%s "$APK")" = "$APK_SIZE" ] \
    || fail "downloaded APK size $(stat -c%s "$APK") != release asset size $APK_SIZE — re-run"
  info "Magisk $M_TAG: $APK_NAME"
fi
[ -f "$APK" ] || fail "MAGISK_APK=$APK does not exist"
ok "Magisk APK: $(basename "$APK") ($(stat -c%s "$APK") bytes)"
A_SHA="$(sha "$APK")"
ok "  sha256 $A_SHA"
if [ -n "${APK_DIGEST:-}" ] && [ -z "${MAGISK_APK:-}" ]; then
  [ "$A_SHA" = "$APK_DIGEST" ] \
    || fail "APK sha256 does not match the release's published digest — refusing (deleted? truncated? MITM?)"
fi

# ---- 2) adb preflight --------------------------------------------------------
ADB_BIN="${ADB_BIN:-adb}"   # documented default: adb from PATH (never unset under set -u)
command -v "$ADB_BIN" >/dev/null 2>&1 \
  || fail "adb not found — install it (e.g. sudo apt install adb) or point ADB_BIN= at your binary"
DEV_LIST="$("$ADB_BIN" devices 2>/dev/null || true)"
echo "$DEV_LIST" | grep -q $'\tdevice$' \
  || fail "no authorized phone on adb — on the phone: enable Developer options (tap build number 7x), enable USB debugging, plug in, accept the authorization prompt, then re-run. (adb sees: $(echo "$DEV_LIST" | tail -n +2 | tr '\n' ' '))"
ok "adb: authorized phone attached"

# ---- 3) the stock source (this is what makes double-patching impossible) -----
[ -f "$SRC" ] \
  || fail "stock source missing: $SRC — the certified master is built by ./insure.sh; in --ota mode the addendum is written by the read step above. Rooting rewrites init_boot_a; this kit refuses to do it without the stock restore source."
SRC_SHA="$(sha "$SRC")"
ok "stock source: $(basename "$SRC")"
ok "  sha256 $SRC_SHA"

# ---- 4) install + push -------------------------------------------------------
info "installing Magisk on the phone"
"$ADB_BIN" install -r "$APK" >/dev/null 2>&1 \
  || fail "Magisk install failed — re-run without redirecting output to see why"
"$ADB_BIN" shell mkdir -p /sdcard/Download 2>/dev/null || true
"$ADB_BIN" push "$SRC" /sdcard/Download/init_boot_stock.img >/dev/null 2>&1 \
  || fail "could not push the stock init_boot to the phone (storage full? authorization dropped?)"
ok "stock init_boot pushed -> /sdcard/Download/init_boot_stock.img"

# ---- 5) the four taps, then wait ----------------------------------------------
echo
echo "NOW, ON THE PHONE:"
echo "  1. open the Magisk app (allow any permission it asks)"
echo "  2. Install -> Select and Patch a File"
echo "  3. pick Download/init_boot_stock.img (the file just pushed)"
echo "  4. LET'S GO — wait for 'All done'"
echo
wait_patched() { # wait_patched <seconds> -> prints newest remote path, or nothing
  local i=0 list
  while [ "$i" -lt "$1" ]; do
    list="$("$ADB_BIN" shell "ls /sdcard/Download/magisk_patched-*.img 2>/dev/null" 2>/dev/null \
            | tr -d '\r' | grep . || true)"
    if [ -n "$list" ]; then
      printf '%s\n' "$list" | sort | tail -n 1
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  return 1
}
info "waiting for the patched image (up to 360 s)..."
REMOTE="$(wait_patched 360 || true)"
if [ -z "$REMOTE" ]; then
  printf "Magisk not detected yet — finish the taps on the phone, then press ENTER: "
  read -r _
  info "looking again (up to 30 s)..."
  REMOTE="$(wait_patched 30 || true)"
fi
[ -n "$REMOTE" ] \
  || fail "no /sdcard/Download/magisk_patched-*.img appeared — did the Magisk app finish? (guide chapter 8)"
ok "patched image on the phone: $REMOTE"

# ---- 6) pull back --------------------------------------------------------------
mkdir -p work
PATCHED=work/magisk_patched.img
"$ADB_BIN" pull "$REMOTE" "$PATCHED" >/dev/null 2>&1 \
  || fail "could not pull $REMOTE back to the computer"
[ "$(stat -c%s "$PATCHED")" = "8388608" ] \
  || fail "pulled image is $(stat -c%s "$PATCHED") bytes, expected 8388608 — that is not an init_boot image for this device"
P_SHA="$(sha "$PATCHED")"
ok "pulled: $PATCHED ($(stat -c%s "$PATCHED") bytes)"
ok "  sha256 $P_SHA"
if [ "$P_SHA" = "$SRC_SHA" ]; then
  echo "${YLW}==>${NC} note: hash equals the stock source — the patch looks like a no-op;"
  echo "    check the Magisk app really said 'All done' before writing"
fi

# ---- 7) the gated write --------------------------------------------------------
echo
echo "  (this flow ALWAYS patches the stock source — never an already-patched"
echo "   image; that is how double-patching is avoided by construction)"
ask_continue YES "ABOUT TO: write the Magisk-patched image into init_boot_a via ./write_init_boot.sh (download agent, hash-verified read-back). Put the phone in DOWNLOAD MODE first: power off (~10 s hold), hold VOL_UP, plug USB. The phone reboots when done."
IMG="$PATCHED" bash ./write_init_boot.sh \
  || fail "write_init_boot.sh failed — see its output above; nothing else to undo (its read-back gates every claim)"

# ---- 8) proof -------------------------------------------------------------------
echo
echo "${GRN}root_with_magisk: DONE${NC}"
echo "  Boot the phone normally, open Magisk -> expect 'Installed'."
echo "  Hard proof:  adb shell su -c id"
echo "    expect: uid=0(root) ... context=u:r:magisk:s0"
echo "  (the FIRST su use pops Magisk's grant dialog on the phone — allow it)"
