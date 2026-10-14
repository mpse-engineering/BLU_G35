#!/usr/bin/env bash
# rollback_to_stock.sh — bring the phone back to its box state. For users who
# want to return the device, or just want root gone.
#
#     ./rollback_to_stock.sh          (asks: full box state, or unroot-only)
#
# Requires the insurance stamp (.insured): the certified master in
# $BLU35_WORKSPACE/firmware/ is the ONLY correct restore source — it is this
# exact phone's own firmware, including the per-device NV partitions no kit
# can ever ship.
#
# WHY THERE IS NO RACE (proven on this silicon): the BootROM download session
# ignores the lock flag — it worked on this phone while LOCKED (the 4x
# firmware extraction) and while UNLOCKED (every unlock write). So the order
# here is chosen purely for SAFETY: push full stock FIRST, and only switch
# locked enforcement on when the chain is already proven stock.
#
# Full box state:
#   preflight -> data warning -> push full stock (unroots by overwriting the
#   Magisk init_boot) -> boot verdict -> relock (snapshot miscdata, zero the
#   64-byte flag in the captured image, rewrite, verify) -> boot verdict
#   (bootloop = auto-restore the snapshot) -> factory reset (staged or menu)
#   -> final read-only confirmation (64 zeros = locked, chain hashes match).
# Unroot-only: stock init_boot_a/b from the master, unlock kept, nothing else.
#
# Fully reversible: no fuse exists in this method; the lock is 64 bytes of
# data, and every step here keeps its own undo artifact.
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
[ -f .insured ]  || fail "insurance stamp missing — run ./insure.sh first. No master copy, no rollback."
# dependency: SPD_DUMP_HOME — explicit export wins; else the path recorded by
# prepare.sh/setup.sh in ../.spd_dump_home; else refuse with instructions
[ -n "${SPD_DUMP_HOME:-}" ] || SPD_DUMP_HOME="$(cat "$(cd "$KIT_ROOT/.." && pwd)/.spd_dump_home" 2>/dev/null || true)"
[ -n "${SPD_DUMP_HOME:-}" ] || fail "SPD_DUMP_HOME is not defined — run ./prepare.sh first (it fetches and
builds the canonical spd_dump into the workspace and records the path), or:
    export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
SPD_DUMP="$SPD_DUMP_HOME/spd_dump"
[ -x "$SPD_DUMP" ] || fail "SPD_DUMP_HOME=$SPD_DUMP_HOME has no executable spd_dump in it"

WS="$(cd "$KIT_ROOT/.." && pwd)"
FW="$WS/firmware"
if [ ! -f "$FW/CHECKSUMS" ] || [ ! -f "$FW/partitions.txt" ]; then
  fail "$FW is not a certified master copy — re-run ./insure.sh"
fi

# session log — same discipline as every step (paste-the-log on failure)
mkdir -p logs
LOG_FILE="logs/rollback_to_stock_$(date +%Y%m%d_%H%M%S).log"
LOG_START=$SECONDS
exec > >(tee "$LOG_FILE") 2>&1
trap 'rc=$?; echo "=== ended rc=$rc after $((SECONDS-LOG_START))s — $LOG_FILE ==="' EXIT
echo "=== BLU G35 kit — rollback_to_stock ==="
echo "started: $(date '+%Y-%m-%d %H:%M:%S')  host: $(uname -srm)"
SESSION_LOG="logs/rollback_session.log"   # every spd_dump line lands here, VISIBLE
echo "=== rollback_to_stock $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$SESSION_LOG"

session() { # session <ops...>  — download-mode session with staged exec payload.
  # Output is NEVER hidden: it streams here AND is tee'd into the session log
  # (an unconnected phone shows a sitting 'Waiting for dl_diag connection').
  cp fdl/custom_exec_no_verify_4ee8.bin custom_exec_no_verify_4ee8.bin
  local want="a06838f71a2e938f4abb66cd80b1ef7992640db8d939d81c093fb60b83849cd9"
  [ "$(sha custom_exec_no_verify_4ee8.bin)" = "$want" ] || fail "staged exec payload hash mismatch"
  local rc=0
  # stdin = "y": the only interactive gate in one-shot mode is the hardcoded
  # 'read userdata' confirm (field log 3); these sessions never read
  # userdata, but the consent contract is uniform: the kit gates first,
  # the tool is answered deterministically.
  "$SPD_DUMP" --wait 300 exec_addr 0x4ee8 \
    fdl fdl/fdl1-dl.bin 0x5000 \
    fdl fdl/fdl2-dl.bin 0x9efffe00 \
    exec "$@" <<< "y" 2>&1 | tee -a "$SESSION_LOG" || rc=$?
  return "$rc"
}

# ./rollback_to_stock.sh final-check — READ-ONLY re-proof of the end state
# (the step-4/4 confirmation) for a phone that already reached box state but
# whose run ended before that step — no re-push, one short session.
if [ "${1:-}" = "final-check" ]; then
  info "final-check — read-only confirmation of the box state (no writes)"
  session r splloader r uboot_a r uboot_b r init_boot_a r init_boot_b \
    read_part miscdata 8192 64 lockblock.bin reset \
    || fail "confirmation session failed (output above; also in $SESSION_LOG)"
  for p in splloader uboot_a uboot_b init_boot_a init_boot_b; do
    [ -f "$p.bin" ] || fail "$p read-back missing"
    H1="$(sha "$FW/$p.bin")"; H2="$(sha "$p.bin")"; rm -f "$p.bin"
    [ "$H1" = "$H2" ] || fail "$p does not match the certified master — investigate"
    ok "$p == master"
  done
  python3 -c "
d = open('lockblock.bin','rb').read()
assert d == b'\x00'*64, 'lock block is not 64 zeros'
print('PASS: lock block = 64 zeros = LOCKED')"
  rm -f lockblock.bin
  echo
  ok "BOX STATE confirmed (read-only): stock chain, bootloader locked."
  exit 0
fi

echo "rollback_to_stock — return this phone to its box state"
echo
echo "  1) FULL BOX STATE   : stock everything, bootloader RELOCKED, wiped."
echo "     For returning the device. Data is destroyed (that is the point)."
echo "  2) UNROOT ONLY      : stock init_boot (root gone), bootloader stays"
echo "     unlocked, data untouched."
echo
ask_choice "choose 1 (full box state) or 2 (unroot only)" 1 2
MODE="$CHOICE"

# ---- preflight (read-only) ----------------------------------------------------
# master-vs-official sanity: the certified master must BE stock for the boot
# chain (guards against an insurance run done on a staged device)
check_master() { # check_master <master-name> <official-name>
  [ -f "$FW/$1.bin" ] || return 0
  [ "$(sha "$FW/$1.bin")" = "$(sha "official/$2")" ] \
    || fail "master $1 is not the official stock image — your insurance ran on a\nnon-stock device. Re-run the insurance on a stock phone, then retry."
}
check_master splloader splloader.bin
check_master uboot_a uboot.bin
check_master uboot_b uboot.bin
check_master init_boot_a init_boot_a.bin
check_master init_boot_b init_boot_b.bin
ok "certified master boot chain matches the official stock images"

info "preflight — reading the current state (read-only)"
echo "  'Waiting for dl_diag connection' sits here until the phone connects —"
echo "  that is normal. Every failure mode is printed, not buried."
session read_part miscdata 8192 64 lockblock.bin reset \
  || fail "download session failed — the phone was NOT connected. Full spd_dump
output is above (also in $SESSION_LOG). Re-enter download mode (power off ~10 s,
hold VOL_UP, plug USB); permission trouble: sudo -E ./rollback_to_stock.sh"
LOCKED="$(python3 -c "
d = open('lockblock.bin','rb').read()
print('yes' if d == b'\x00'*64 else 'no')")"
if [ "$LOCKED" = "yes" ]; then
  echo "  note: the unlock flag reads LOCKED already."
  if [ "$MODE" = "1" ]; then
    echo "  (the relock step later will simply confirm this state)"
  fi
else
  ok "device is unlocked (as expected for rollback)"
fi
rm -f lockblock.bin

# ---- data warning gate ---------------------------------------------------------
echo
if [ "$MODE" = "1" ]; then
  echo "${YLW}DATA WARNING:${NC} full box state ENDS WITH A FACTORY RESET — everything"
  echo "  on the phone (accounts, photos, apps) is destroyed. Back up what you"
  echo "  want to keep BEFORE continuing."
  ask_continue "I UNDERSTAND" "DATA WARNING: full box state ENDS WITH A FACTORY RESET — everything on the phone (accounts, photos, apps) is destroyed. Back up what you want to keep BEFORE continuing."
fi

# ---- step: stock push -----------------------------------------------------------
if [ "$MODE" = "1" ]; then
  info "step 1/4 — pushing FULL stock from the certified master ($FW)"
  echo "  every write is followed by a hash-verified read-back. Deliberately NOT"
  echo "  touched at all — neither written nor verified (decisions 9+10, see"
  echo "  PUBLIC_KIT_NOTES.md in the DevKit):"
  echo "   - GPT/userdata/cache  — table matches, data handled by the factory reset"
  echo "   - misc, miscdata      — wipe flag + surgical relock, their own steps"
  echo "   - super               — spd_dump refuses >4 GiB writes one-shot; it is"
  echo "                           stock (root patched init_boot only)"
  echo "   - calinv, l_fixnv1/2_a/b — RADIO CALIBRATION / factory NV: per-device and"
  echo "                           boot-stable; rooting never touches it; the tool"
  echo "                           cannot even read the nv1 copies back faithfully"
  echo "   - persist, metadata,  — device state / logs / snapshots: legitimately"
  echo "     uboot_log, sysdumpdb,  different from any earlier capture; comparing"
  echo "     blackbox               them only produces false alarms"
  echo "   - l_runtimenv1/2      — runtime NV: changes by design; a write would"
  echo "                           ERASE it (tool semantics), so: hands off"
  ask_continue YES "Start the full-stock push now (phone in download mode)."
  # push list: all partitions except the ones with special handling:
  #   pgpt/pgtx      not GPT partitions on this SoC (GPT region + packet)
  #   userdata/cache handled by the factory reset that ends the rollback
  #   misc           gets the wipe flag; miscdata gets the surgical relock
  #   blackbox       per-device encrypted state — kept as-is, same device
  python3 - "$FW/partitions.txt" > pushlist.tmp <<'PY'
import sys
# Partitions the rollback NEVER touches — neither written nor verified
# (spd_dump source semantics + field guidance, PUBLIC_KIT_NOTES.md 9+10):
#   pgpt/pgtx                 not GPT partitions on this SoC (GPT region + packet)
#   userdata/cache            handled by the factory reset that ends the rollback
#   misc/miscdata             wipe flag + surgical relock, their own steps
#   blackbox/persist/metadata — per-device state, snapshots: comparing them
#   uboot_log/sysdumpdb         against an older capture only false-alarms
#   super                     'part too large' — silently refused one-shot (>4 GiB)
#   calinv, l_fixnv1/2_a/b    radio calibration / factory NV — per-device,
#                             untouched by rooting, and the tool cannot read
#                             the nv1 copies back (it returns the nv2 mirror)
#   l_runtimenv1/2            runtime NV — changes by design; the tool ERASES
#                             it on write
SKIP = {"pgpt", "pgtx", "userdata", "cache", "misc", "miscdata", "blackbox",
        "super", "calinv", "persist", "metadata", "uboot_log", "sysdumpdb",
        "l_fixnv1_a", "l_fixnv1_b", "l_fixnv2_a", "l_fixnv2_b",
        "l_runtimenv1", "l_runtimenv2"}
for l in open(sys.argv[1]):
    p = l.strip()
    if p and p.lower() not in SKIP:
        print(p)
PY
  total="$(grep -c . pushlist.tmp)"
  # SESSION SHAPE — spd_dump source + field-proven (2026-09-26): 'reset' is
  # an EXIT command — the tool reboots the phone and stops processing
  # arguments. NEVER lead a session with it: a leading reset silently skips
  # every op after it (caught in the field: rc=0, no writes, no read-backs,
  # phone rebooted). One-line sessions have NO token cap (ARGC_MAX=8 limits
  # interactive mode only), so batches of 4 write+read pairs are fine —
  # DEV's field-proven step07 runs even longer sessions.
  info "writing $total partitions, 4 per session (each: write + read-back verify)"
  batch=(); n=0; pushed=0
  flush_push() {
    args=()
    for q in "${batch[@]}"; do args+=("w" "$q" "$FW/$q.bin" "r" "$q"); done
    session "${args[@]}" reset \
      || fail "session failed during push — full spd_dump output above (also in $SESSION_LOG).
The phone remains recoverable; re-run this script to continue from the masters."
    local q2
    for q2 in "${batch[@]}"; do
      [ -f "$q2.bin" ] || fail "$q2.bin read-back missing — write not proven; re-run"
      H1="$(sha "$FW/$q2.bin")"; H2="$(sha "$q2.bin")"
      [ "$H1" = "$H2" ] || fail "$q2 read-back hash mismatch — write not proven; re-run"
      rm -f "$q2.bin"
    done
    pushed=$((pushed + ${#batch[@]}))
    batch=(); n=0
    echo "    ... progress: $pushed / $total verified"
  }
  while read -r p; do
    batch+=("$p"); n=$((n+1))
    if [ "$n" = "4" ]; then flush_push; fi
  done < pushlist.tmp
  if [ "$n" -gt 0 ]; then flush_push; fi
  rm -f pushlist.tmp
  ok "full stock pushed and hash-verified ($total partitions)"
  echo "  calibration + device-state set (calinv, l_fixnv*, l_runtimenv*, persist,"
  echo "  metadata, uboot_log, sysdumpdb, blackbox): deliberately untouched and"
  echo "  UNVERIFIED — per-device or volatile content cannot be compared against"
  echo "  an earlier capture without false alarms (field decision 10)."
  echo
  echo "  ${YLW}BOOT VERDICT${NC}: power the phone on normally (nothing held)."
  echo "  EXPECTED: normal boot into Android, no Magisk installed anymore."
  ask_choice "did it boot normally? y or n" y n
  [ "$CHOICE" = "y" ] || fail "stock push did not boot. STOP — download mode still works; do not improvise. Paste the log."
else
  info "unroot-only — writing stock init_boot_a and init_boot_b from the master"
  ask_continue YES "Write stock init_boot_a and init_boot_b now (phone in download mode). Nothing else is touched."
  for p in init_boot_a init_boot_b; do
    session w "$p" "$FW/$p.bin" r "$p" reset || fail "session failed on $p (output above; also in $SESSION_LOG)"
    H1="$(sha "$FW/$p.bin")"; H2="$(sha "$p.bin")"
    [ "$H1" = "$H2" ] || fail "$p read-back mismatch — write not proven"
    rm -f "$p.bin"
    ok "$p = stock (hash-verified)"
  done
  echo
  echo "${GRN}unroot complete — root is gone, bootloader stays unlocked, data untouched.${NC}"
  exit 0
fi

# ---- step: relock ----------------------------------------------------------------
info "step 2/4 — relock (surgical: snapshot -> zero the 64-byte flag -> rewrite)"
ask_continue YES "Relock now (phone in download mode): snapshot miscdata, zero the 64-byte flag, rewrite, verify."
session r miscdata reset || fail "miscdata read failed (output above; also in $SESSION_LOG)"
[ -f miscdata.bin ] || fail "miscdata read-back missing"
cp miscdata.bin miscdata_pre_relock_snapshot.bin   # the undo artifact
python3 - <<'PY'
import struct
d = bytearray(open("miscdata.bin", "rb").read())
assert len(d) >= 0x2040, f"miscdata shorter than expected: {len(d)}"
d[0x2000:0x2040] = b"\x00" * 64                   # maintainer model: 64 zeros = locked
open("miscdata_relock.bin", "wb").write(bytes(d))
PY
session w miscdata miscdata_relock.bin r miscdata reset \
  || fail "relock write session failed (output above; also in $SESSION_LOG)"
H1="$(sha miscdata_relock.bin)"; H2="$(sha miscdata.bin)"
[ "$H1" = "$H2" ] || fail "miscdata read-back mismatch after relock — re-run"
rm -f miscdata.bin
session read_part miscdata 8192 64 lockblock.bin reset
python3 -c "
d = open('lockblock.bin','rb').read()
assert d == b'\x00'*64, 'lock block is NOT 64 zeros — relock not proven: '+d.hex()
print('PASS: lock block reads 64 zeros = LOCKED')"
rm -f lockblock.bin
ok "relock written and verified"
echo
echo "  ${YLW}BOOT VERDICT${NC}: power on. EXPECTED: normal boot (possibly a"
echo "  recovery reset prompt — data was encrypted under the unlocked state;"
echo "  accept the reset). The unlocked banner should be GONE."
ask_choice "did it behave as described? y or n" y n
if [ "$CHOICE" != "y" ]; then
  info "restoring the pre-relock state (the snapshot) — phone returns to UNLOCKED"
  session w miscdata miscdata_pre_relock_snapshot.bin r miscdata reset \
    || fail "snapshot restore failed — the phone still boots via download mode; paste $SESSION_LOG"
  H1="$(sha miscdata_pre_relock_snapshot.bin)"; H2="$(sha miscdata.bin)"
  [ "$H1" = "$H2" ] && ok "pre-relock state restored (unlock flag back)" && rm -f miscdata.bin
  fail "relock misbehaved and was rolled back. Paste the log — do NOT retry blindly."
fi

# ---- step: factory reset (destructive, LAST) --------------------------------------
info "step 3/4 — factory reset (this is the destructive step, so it is last)"
echo "  Two ways, same result:"
echo "   a) on the phone: recovery menu -> factory data reset (if a reset"
echo "      prompt appeared, it is already on screen)"
echo "   b) let this script stage it: writes the wipe flag to misc; the"
echo "      phone's own recovery performs the wipe on next boot"
ask_choice "stage the wipe from here? y or n" y n
if [ "$CHOICE" = "y" ]; then
  # Verify the flag over the span ACTUALLY written: misc-wipe.bin is 0x800
  # bytes and 'w misc' writes raw, so read_part over exactly that many bytes
  # must equal the file. (Field lesson 2026-09-26: the previous check read
  # the FULL 1 MiB partition and compared it to the 0x800-byte file — an
  # unwinnable compare that failed AFTER the wipe had already been staged.)
  WZ="$(stat -c%s artifacts/misc-wipe.bin)"
  session w misc artifacts/misc-wipe.bin read_part misc 0 "$WZ" misc_check.bin reset \
    || fail "misc write session failed (output above; also in $SESSION_LOG)"
  [ -f misc_check.bin ] || fail "misc read-back missing — paste $SESSION_LOG"
  H1="$(sha artifacts/misc-wipe.bin)"; H2="$(sha misc_check.bin)"; rm -f misc_check.bin
  [ "$H1" = "$H2" ] || fail "wipe-flag read-back mismatch over $WZ bytes — the flag did not land;
nothing else was touched. Re-run ./rollback_to_stock.sh (it is idempotent)."
  ok "wipe staged and flag verified ($WZ bytes) — boot the phone and confirm the reset in recovery"
else
  echo "  do the reset in the recovery menu, then boot normally."
fi

# ---- step: final confirmation ------------------------------------------------------
info "step 4/4 — final confirmation (read-only)"
echo "  phone in download mode one last time:"
ask_continue YES "Final confirmation session (read-only), phone in download mode."
session r splloader r uboot_a r uboot_b r init_boot_a r init_boot_b \
  read_part miscdata 8192 64 lockblock.bin reset \
  || fail "confirmation session failed (output above; also in $SESSION_LOG)"
for p in splloader uboot_a uboot_b init_boot_a init_boot_b; do
  [ -f "$p.bin" ] || fail "$p read-back missing"
  H1="$(sha "$FW/$p.bin")"; H2="$(sha "$p.bin")"; rm -f "$p.bin"
  [ "$H1" = "$H2" ] || fail "$p does not match the certified master — investigate"
  ok "$p == master"
done
python3 -c "
d = open('lockblock.bin','rb').read()
assert d == b'\x00'*64, 'lock block is not 64 zeros'
print('PASS: lock block = 64 zeros = LOCKED')"
rm -f lockblock.bin miscdata_relock.bin miscdata_pre_relock_snapshot.bin

echo
echo "${GRN}rollback_to_stock: BOX STATE REACHED${NC}"
echo "  stock chain hash-verified, bootloader locked, data wiped, no Magisk."
echo "  Nothing about this method burned any fuse — the kit can unlock this"
echo "  phone again exactly the same way, any time."
