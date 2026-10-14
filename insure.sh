#!/usr/bin/env bash
# insure.sh — GATE 4 of 4. THE INSURANCE. Three complete firmware backups +
# 3-way verification + a certified master copy. 100% READ-ONLY: no
# write-shaped command exists in this script.
#
#     ./insure.sh                 (runs/resumes automatically)
#     ./insure.sh session1|session2|session3|verify   (re-do one stage,
#                              e.g. after fixing a bad cable)
#     ./insure.sh status
#
# Why (guide chapter 4): (1) it is the per-device restore source — the kit
# can never ship another phone's NV/RF data, so backup3 is the ONLY correct
# rollback source; (2) it is the USB health test — three full read sessions
# plus two power cycles move far more data than the entire unlock ever will,
# so a bad cable or flaky port dies HERE, before any write exists.
#
# THE COST OF SAFETY, STATED PLAINLY (policy, not apology): this is a
# multi-hour, one-time operation and ~120 GB of disk. Safety is above
# anything — if you cannot afford the time or the disk, you are not ready
# to perform surgery on this phone.
#
# Everything is backed up, THREE times. userdata is INCLUDED by default, but
# the operator decides ONCE (first run of ./insure.sh): the answer is stored
# in ../.insure_userdata (workspace, not kit tree) and honored by all three
# sessions — see SKIP_USERDATA below and the guide. Only the VERIFICATION
# treats partitions differently (KEY/CAL/VOLATILE/UNKNOWN,
# tools/part_classes.py); everything captured is verified 3-way.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
# decision gate (case-sensitive, re-asks — never throws work away)
. "$KIT_ROOT/tools/ask_continue.sh"
cd "$KIT_ROOT"

FRESH=0; MODE="all"; SUB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fresh) FRESH=1 ;;
    session1|session2|session3|verify|all|status) MODE="$1" ;;
    userdata) MODE="userdata" ;;
    y|yes|n|no|Y|YES|N|NO) SUB="$1" ;;   # the answer TO 'userdata'
    *) fail "unknown argument: $1 (valid: all|session1|session2|session3|verify|status, ./insure.sh userdata y|n, plus --fresh)" ;;
  esac
  shift
done

# ---- userdata: ASKED ONCE, BEFORE ANYTHING, answer REMEMBERED (field log 3,
# operator's design: "ask before you do anything, remember the user answer,
# then do the backup accordingly, either with userdata or without"). A "n"/
# "no" excludes userdata from ALL three sessions — the tool's own prompt is
# then never reached (it cannot be answered from a keyboard anyway: the kit
# runs spd_dump with stdin as a pipe; the typed 'NO' in the field leaked to
# the shell). Only ./insure.sh userdata y|n changes it later. NEVER ASKED
# AGAIN once stored.
UD_FILE="$(cd "$KIT_ROOT/.." && pwd)/.insure_userdata"
if [ "$MODE" = "userdata" ]; then
  case "$SUB" in
    y|yes|Y|YES) echo yes > "$UD_FILE"; echo "userdata capture: YES — all sessions include it (~25 GB x3)" ;;
    n|no|N|NO)   echo no  > "$UD_FILE"; echo "userdata capture: NO — excluded from all sessions" ;;
    *) if [ -f "$UD_FILE" ]; then echo "userdata capture: $(cat "$UD_FILE") (stored)"; else echo "userdata capture: not decided yet (asked on first session run)"; fi
       echo "change with: ./insure.sh userdata y|n"
       [ -f "$UD_FILE" ] && echo "note: a change applies to FUTURE sessions; captured partitions stay as they are" ;;
  esac
  exit 0
fi
if [ ! -f "$UD_FILE" ] && [ "$MODE" != "status" ]; then
  echo "userdata backup? The insurance can also capture userdata (~25 GB per"
  echo "  session, so ~75 GB extra disk and +hours). Decided ONCE, stored, and"
  echo "  followed by all three sessions — you will not be asked again."
  # flush STALE typed input first — interactive TTY only (field log 3: a
  # typed-ahead answer left in the buffer leaked to the shell after the
  # run; the operator may also double-tap Enter). NEVER drain a pipe: the
  # offline suites and scripted runs feed their answers through stdin.
  if [ -t 0 ]; then
    while read -r -t 0; do read -r -t 0.1 -n 4096 junk 2>/dev/null || true; done
  fi
  UD_ANS=""
  while [ -z "$UD_ANS" ]; do
    printf 'backup userdata? y/yes or n/no: '
    if ! read -r a; then UD_ANS=yes; echo "  (no input — defaulting to YES: data is the point of the insurance)"; break; fi
    case "$a" in
      y|yes|Y|YES|Yes) UD_ANS=yes ;;
      n|no|N|NO|No)    UD_ANS=no ;;
      *) echo "  please answer y/yes or n/no" ;;
    esac
  done
  echo "$UD_ANS" > "$UD_FILE"
  echo "  stored in $UD_FILE — change later with: ./insure.sh userdata y|n"
fi
UD_WANT="$(cat "$UD_FILE")"
SKIP_USERDATA=$([ "$UD_WANT" = "no" ] && echo 1 || echo 0)

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

WS="$(cd "$KIT_ROOT/.." && pwd)"
B1="$WS/backup1"; B2="$WS/backup2"; B3="$WS/backup3"; FW="$WS/firmware"
STAMP="$KIT_ROOT/.insured"
STAGE_DIR="$KIT_ROOT/logs"
STAGE_LOG="$STAGE_DIR/insure_session.log"   # every spd_dump line lands here, VISIBLE
mkdir -p "$STAGE_DIR"
echo "=== insure $(date '+%Y-%m-%d %H:%M:%S') — $MODE${FRESH:+ --fresh} ===" >> "$STAGE_LOG"

show_status() {
  echo "insurance status:"
  for s in session1 session2 session3 verify; do
    if [ -f "$STAGE_DIR/.insure_$s.done" ]; then echo "  [done]     $s"
    else echo "  [not done] $s"; fi
  done
  [ -f "$STAMP" ] && echo "  ${GRN}INSURED — run.sh may proceed${NC}" || echo "  ${RED}NOT insured — run.sh is locked${NC}"
  echo "  userdata capture: ${UD_WANT} ($(cat "$UD_FILE" 2>/dev/null || echo unset) stored in ../.insure_userdata)"
  echo "  sessions are RESUMABLE: re-running a session re-reads only partitions"
  echo "  missing or short of their GPT size; --fresh forces a clean redo."
}

session_active() { # download-mode session. Output is NEVER hidden: it streams
  # to the operator AND is tee'd into logs/insure_session.log (a silent session
  # is how "not connected at all" used to look like success).
  cp fdl/custom_exec_no_verify_4ee8.bin custom_exec_no_verify_4ee8.bin
  local want="a06838f71a2e938f4abb66cd80b1ef7992640db8d939d81c093fb60b83849cd9"
  [ "$(sha custom_exec_no_verify_4ee8.bin)" = "$want" ] || fail "staged exec payload hash mismatch"
  rm -f "$STAGE_DIR/.insure_session_marker"
  local rc=0
  # stdin = "y": the ONLY interactive gate in one-shot mode is the hardcoded
  # 'read userdata' confirm inside dump_partition (field log 3: it does NOT
  # auto-pass — an unattended session died on it after 68/69 reads). The
  # operator already consented to the full read via this script's own gate.
  "$SPD_DUMP" --wait 300 exec_addr 0x4ee8 \
    fdl fdl/fdl1-dl.bin 0x5000 \
    fdl fdl/fdl2-dl.bin 0x9efffe00 \
    exec "$@" <<< "y" 2>&1 | tee -a "$STAGE_LOG" || rc=$?
  [ "$rc" = "0" ] && touch "$STAGE_DIR/.insure_session_marker"
  return "$rc"
}

read_session() { # read_session <target-dir> <stage-name>
  local T="$1" SN="$2"
  mkdir -p "$T"
  info "$SN — READ-ONLY full firmware backup into $(basename "$T")/"
  echo "    every partition is read, including userdata, in ONE session (no"
  echo "    token cap in one-shot mode — field + source proven). If the cable"
  echo "    drops, RE-RUN the same command: it resumes, re-reading only the"
  echo "    partitions missing or short of their GPT size. ./insure.sh --fresh"
  echo "    <session> forces a clean redo."
  echo "    THE COST OF SAFETY: this session reads ~30 GB and takes a while."
  echo "    You do NOT have to babysit it: the phone stays in download mode for"
  echo "    the whole session; check in occasionally."
  ask_continue YES "Start the READ-ONLY session now (phone in download mode)."

  # GPT capture — output VISIBLE. Upstream mechanism (spd_dump source): the
  # tool saves the standard GPT table AUTOMATICALLY on the first
  # named-partition read ('standard gpt table saved to pgpt.bin') — there is
  # no 'pgpt' partition to request. So this first session reads splloader,
  # which ALSO fetches the one partition that is NOT a GPT entry on this SoC.
  # No blind redirects anywhere: until the phone connects you see the tool's
  # Waiting line, and every failure mode ('find port failed', permission
  # denied, adb grab) is printed, not buried.
  info "connecting to the BootROM — waiting for the download-mode port"
  echo "    phone in download mode? (power off ~10 s, hold VOL_UP, plug USB)"
  echo "    'Waiting for dl_diag connection' will sit here until the phone is
    connected — that is normal. Everything the tool prints is shown below
    and recorded in $STAGE_LOG"
  rm -f pgpt.bin splloader.bin
  echo "    capture caveat (spd_dump source): reads of any *nv1* partition come
    back from the *nv2* mirror at offset 0x200, so the captures of
    l_fixnv1_a/b and l_runtimenv1 hold mirror content (identical bytes on a
    healthy device). l_fixnv* is RADIO CALIBRATION: per-device, boot-stable,
    and EXCLUDED from the 3-way comparison by design — a mismatch there would
    be a capture artifact, not evidence. Nothing ever writes these."
  session_active r splloader reset \
    || fail "download session failed — the phone was NOT connected. Full spd_dump
output is above (also in $STAGE_LOG). Fixes, in order of likelihood:
  - re-enter download mode: power off ~10 s, hold VOL_UP, plug USB
  - 'find port failed' right away: wrong/hub cable, no USB permission
    (run: sudo -E ./insure.sh  — or install the guide's udev rule),
    or an adb server grabbed the device (run: adb kill-server)
  - bad cable/port: try another port, no hubs, another cable"
  [ -f pgpt.bin ] || fail "the session ran but pgpt.bin was not produced —
the tool saves the standard GPT table on the first partition read. If it could
not (no standard GPT), it prints 'unable to get standard gpt table' and saves
sprdpart.bin instead. Paste $STAGE_LOG."
  # splloader lives OUTSIDE the GPT (RAW special): the tool always resolves
  # it to 256 KiB (source: get_partition_info).
  local SPLSIZE=262144
  complete_check() { # every REQUIRED partition present at its exact expected size
    [ -f "$T/splloader.bin" ] && [ "$(stat -c%s "$T/splloader.bin")" = "$SPLSIZE" ] || return 1
    [ -f "$T/partitions.sizes" ] || return 1
    local p3 e3
    while read -r p3 e3; do
      [ -n "$p3" ] || continue
      [ "$p3" = "userdata" ] && [ "$SKIP_USERDATA" = "1" ] && continue
      [ -f "$T/$p3.bin" ] && [ "$(stat -c%s "$T/$p3.bin")" = "$e3" ] || return 1
    done < "$T/partitions.sizes"
    return 0
  }
  if [ "$FRESH" = "1" ]; then
    info "--fresh: discarding ALL captures in $(basename "$T")/"
    ( cd "$T" && rm -f -- ./*.bin CHECKSUMS partitions.sizes partitions.txt pgpt.bin )
  fi
  if complete_check; then
    [ -f "$T/CHECKSUMS" ] || ( cd "$T" && sha256sum *.bin > CHECKSUMS )
    touch "$STAGE_DIR/.insure_$SN.done"
    ok "$SN already complete ($(grep -c . "$T/CHECKSUMS") files, all size-verified) — no phone needed"
    return 0
  fi
  # GPT + expected sizes: reused from a prior partial run when present (a
  # resume needs NO extra BROM entry for the table); captured from the device
  # otherwise — the first named read auto-saves the standard GPT table.
  if [ ! -f "$T/pgpt.bin" ]; then
    info "connecting to the BootROM — waiting for the download-mode port"
    echo "    phone in download mode? (power off ~10 s, hold VOL_UP, plug USB)"
    echo "    'Waiting for dl_diag connection' will sit here until the phone is
    connected — that is normal. Everything the tool prints is shown below
    and recorded in $STAGE_LOG"
    rm -f pgpt.bin splloader.bin misc.bin
    echo "    capture caveat (spd_dump source): reads of any *nv1* partition come
    back from the *nv2* mirror at offset 0x200, so the captures of
    l_fixnv1_a/b and l_runtimenv1 hold mirror content (identical bytes on a
    healthy device). l_fixnv* is RADIO CALIBRATION: per-device, boot-stable,
    and EXCLUDED from the 3-way comparison by design — a mismatch there would
    be a capture artifact, not evidence. Nothing ever writes these."
    session_active r splloader reset \
      || fail "download session failed — the phone was NOT connected. Full spd_dump
output is above (also in $STAGE_LOG). Fixes, in order of likelihood:
  - re-enter download mode: power off ~10 s, hold VOL_UP, plug USB
  - 'find port failed' right away: wrong/hub cable, no USB permission
    (run: sudo -E ./insure.sh  — or install the guide's udev rule),
    or an adb server grabbed the device (run: adb kill-server)
  - bad cable/port: try another port, no hubs, another cable"
    [ -f pgpt.bin ] || fail "the session ran but pgpt.bin was not produced —
the tool saves the standard GPT table on the first partition read. If it could
not (no standard GPT), it prints 'unable to get standard gpt table' and saves
sprdpart.bin instead. Paste $STAGE_LOG."
    rm -f splloader.bin misc.bin   # splloader is re-read in the main session; misc.bin is a slot-info side dump
    mv -f pgpt.bin "$T/pgpt.bin"
  fi
  [ -f "$T/partitions.txt" ] || python3 - "$T/pgpt.bin" > "$T/partitions.txt" <<'PY'
import struct, sys
# Union of (a) the device's own GPT and (b) the SPRD raw-area specials the
# tool addresses by name. splloader lives BEFORE the GPT on this SoC — it is
# not a GPT entry (verified against the device's own table: 68 entries, no
# splloader) — so a GPT-only loop would silently skip the most important
# partition of all.
RAW = ["splloader"]
g = open(sys.argv[1], "rb").read()
assert g[512:520] == b"EFI PART", "pgpt.bin is not a GPT"
ent_lba = struct.unpack_from("<Q", g, 512 + 0x48)[0]
n_ent   = struct.unpack_from("<I", g, 512 + 0x50)[0]
ent_sz  = struct.unpack_from("<I", g, 512 + 0x54)[0]
names = []
for i in range(n_ent):
    e = g[ent_lba * 512 + i * ent_sz:][:ent_sz]
    if e[:16] == b"\x00" * 16:
        continue
    names.append(e[56:56 + 72].decode("utf-16-le").split("\x00")[0])
for r in RAW:
    if r not in names:
        names.insert(0, r)
print("\n".join(n for n in names if n))
PY
  # expected byte sizes, straight from the device's own GPT. *nv1* reads come
  # back from the nv2 mirror minus the 0x200 header, so their expected FILE
  # size is GPT-size − 512 (decision 9).
  [ -f "$T/partitions.sizes" ] || python3 - "$T/pgpt.bin" > "$T/partitions.sizes" <<'PY'
import struct, sys
g = open(sys.argv[1], "rb").read()
assert g[512:520] == b"EFI PART", "pgpt.bin is not a GPT"
ent_lba = struct.unpack_from("<Q", g, 512 + 0x48)[0]
n_ent   = struct.unpack_from("<I", g, 512 + 0x50)[0]
ent_sz  = struct.unpack_from("<I", g, 512 + 0x54)[0]
for i in range(n_ent):
    e = g[ent_lba * 512 + i * ent_sz:][:ent_sz]
    if e[:16] == b"\x00" * 16:
        continue
    first, last = struct.unpack_from("<Q", e, 32)[0], struct.unpack_from("<Q", e, 40)[0]
    name = e[56:56 + 72].decode("utf-16-le").split("\x00")[0]
    if not name:
        continue
    sz = (last - first + 1) * 512
    if "nv1" in name and sz > 512:
        sz -= 512
    print(f"{name} {sz}")
PY
  local total; total="$(grep -c . "$T/partitions.txt")"
  [ "$total" -gt 0 ] || fail "parsed 0 partitions from pgpt.bin — unexpected GPT"
  # size-verified resume list: a file counts ONLY if it matches its GPT size
  # exactly — a dropped session leaves a truncated file, and the tool
  # rewrites the dump target from byte 0 on every read, so a redo is clean.
  # (User requirement: NEVER trust a file just because it exists on disk.)
  local args=() p exp pend=0 have=0
  if [ -f "$T/splloader.bin" ] && [ "$(stat -c%s "$T/splloader.bin")" = "$SPLSIZE" ]; then
    have=$((have+1))
  else
    rm -f "$T/splloader.bin" splloader.bin; args+=(r splloader); pend=$((pend+1))
  fi
  while read -r p exp; do
    [ -n "$p" ] || continue
    [ "$p" = "userdata" ] && [ "$SKIP_USERDATA" = "1" ] && continue
    if [ -f "$T/$p.bin" ] && [ "$(stat -c%s "$T/$p.bin")" = "$exp" ]; then
      have=$((have+1))
    else
      rm -f "$T/$p.bin" "$p.bin"; args+=(r "$p"); pend=$((pend+1))
    fi
  done < "$T/partitions.sizes"
  info "$total partitions (+splloader): $have already size-verified, $pend to read this session$([ "$SKIP_USERDATA" = "1" ] && echo ' [userdata excluded by operator choice]' || true)"
  if [ "$pend" = "0" ]; then
    fail "$SN is complete per the sizes map but the fast path missed — re-run ./insure.sh $SN"
  fi
  echo "    ONE session, no batches: one-shot sessions have no token cap (field
    + source proven). 'reset' is spd_dump's EXIT command — this session ENDS
    with it; the phone reboots afterward (expected, not a bug)."
  session_active "${args[@]}" reset \
    || fail "read session failed — full spd_dump output above (also in $STAGE_LOG).
Resume is cheap: fix cable/port, re-enter download mode, RE-RUN the same
command — it re-reads only what is missing or short:
    ./insure.sh $SN
(completed sessions keep their stamps; every completed partition survives.)"
  # collect the fresh dumps from the kit CWD into the backup dir. CWD was
  # pre-cleaned for every pending name, so anything present here is fresh.
  mv -f splloader.bin "$T/splloader.bin" 2>/dev/null || true
  [ -f pgpt.bin ] && mv -f pgpt.bin "$T/pgpt.bin"
  # NOTE: misc.bin is a REAL capture here (misc is a GPT partition); the
  # slot-info side dump only happens with 'preset_modem'/'r all', never with
  # named one-shot reads, so there is nothing to clean. CWD hygiene for every
  # pending name already happened in the resume-list build.
  while read -r p exp; do
    [ -n "$p" ] || continue
    [ -f "$p.bin" ] && mv -f "$p.bin" "$T/$p.bin"
  done < "$T/partitions.sizes"
  # completion gate: EVERY partition present at its exact GPT size. A session
  # that exited 0 but under-delivered is caught HERE, never assumed.
  local miss=0 p2 exp2
  if [ ! -f "$T/splloader.bin" ] || [ "$(stat -c%s "$T/splloader.bin")" != "$SPLSIZE" ]; then
    echo "  INCOMPLETE: splloader.bin (want $SPLSIZE bytes)"; miss=1
  fi
  while read -r p2 exp2; do
    [ -n "$p2" ] || continue
    [ "$p2" = "userdata" ] && [ "$SKIP_USERDATA" = "1" ] && continue
    if [ ! -f "$T/$p2.bin" ] || [ "$(stat -c%s "$T/$p2.bin")" != "$exp2" ]; then
      echo "  INCOMPLETE: $p2.bin (want $exp2 bytes)"; miss=1
    fi
  done < "$T/partitions.sizes"
  [ "$miss" = "0" ] || fail "$SN incomplete (session rc=0 marker: $([ -f "$STAGE_DIR/.insure_session_marker" ] && echo present || echo ABSENT)) —
RE-RUN ./insure.sh $SN to resume (only the incomplete partitions will be
re-read). Session output: $STAGE_LOG"
  ( cd "$T" && sha256sum *.bin > CHECKSUMS )
  touch "$STAGE_DIR/.insure_$SN.done"
  ok "$SN complete and checksummed ($(grep -c . "$T/CHECKSUMS") files, all size-verified)"
  echo "  next: power off (hold POWER ~10 s), boot the phone normally once, then"
  echo "  power off again and re-enter download mode (hold VOL_UP, plug USB)."
}

verify_backups() {
  [ -f "$STAGE_DIR/.insure_session1.done" ] && [ -f "$STAGE_DIR/.insure_session2.done" ] \
    && [ -f "$STAGE_DIR/.insure_session3.done" ] || fail "run all three sessions first (./insure.sh status)"
  info "3-way verification across backup1 / backup2 / backup3"
  local rc=0
  python3 - "$B1" "$B2" "$B3" "$SKIP_USERDATA" <<'PY' || rc=$?
import hashlib, os, sys
import importlib.util
spec = importlib.util.spec_from_file_location("pc", os.path.join("tools", "part_classes.py"))
pc = importlib.util.module_from_spec(spec); spec.loader.exec_module(pc)

b1, b2, b3, skip_ud = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
def load_names(b):
    ns = [l.strip() for l in open(os.path.join(b, "partitions.txt")) if l.strip()]
    if skip_ud:
        ns = [n for n in ns if n != "userdata"]
    return ns
names = load_names(b1)
if skip_ud:
    print("  userdata: EXCLUDED by operator choice (../.insure_userdata = no) — not captured, not compared")
for b in (b2, b3):
    if set(load_names(b)) != set(names):
        print(f"FAIL: partition sets differ between {b1} and {b}")
        sys.exit(1)

cls = pc.classify_all(names)
print(f"  partitions: {len(names)}  (KEY: {len(cls['KEY'])}, CAL: {len(cls['CAL'])}, VOLATILE: {len(cls['VOLATILE'])}, UNKNOWN: {len(cls['UNKNOWN'])})")
for c in ("KEY", "CAL", "VOLATILE", "UNKNOWN"):
    print(f"    {c}: {', '.join(cls[c]) if cls[c] else '(none)'}")

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

halt, unknown_diffs = [], []
for part in names:
    h1 = sha(os.path.join(b1, part + ".bin"))
    h2 = sha(os.path.join(b2, part + ".bin"))
    h3 = sha(os.path.join(b3, part + ".bin"))
    if h1 == h2 == h3:
        continue
    c = pc.classify(part)
    if c == "KEY":
        halt.append(part)
    elif c == "UNKNOWN":
        unknown_diffs.append(part)
    # CAL: radio calibration — capture is mirror-proxied (tool artifact), and
    # per field decision 10 the class is compare-excluded entirely
    # VOLATILE: expected to differ across boots; excluded by design

if halt:
    print("\nHALT — KEY partitions differ across backups (no override exists):")
    for p in halt:
        print("  " + p)
    print("The cable/port or the device is unreliable. Fix the hardware, then")
    print("re-run the affected session(s). The kit will NOT proceed.")
    sys.exit(2)
if unknown_diffs:
    print("\nWARNING — unclassified partitions differ across backups:")
    for p in unknown_diffs:
        print("  " + p)
    print("This is usually harmless runtime state we did not classify, but")
    print("YOU decide — nothing proceeds silently.")
    sys.exit(3)
print("PASS: every KEY partition is identical across all three backups")
PY
  if [ "$rc" -eq 2 ]; then
    echo "${RED}FAIL:${NC} KEY partition mismatch — see the list above. The kit will NOT proceed."
    exit 2
  elif [ "$rc" -eq 3 ]; then
    ask_continue YES "Accept the unclassified differences listed above and continue."
  elif [ "$rc" -ne 0 ]; then
    fail "verification failed (rc=$rc)"
  fi

  # ---- certified master copy (complete, incl. userdata) -------------------
  info "assembling the certified master copy: $FW"
  rm -rf "$FW"; mkdir -p "$FW"
  cp -r "$B3"/. "$FW"/
  ( cd "$FW" && sha256sum *.bin > CHECKSUMS )
  printf 'certified master — source: backup3 (3-way verified %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$FW/README.txt"
  ok "certified master ready: firmware/ (restore source for EVERY partition)"
  touch "$STAMP"
  echo
  echo "${GRN}insure: DEVICE INSURED${NC}"
  echo "  rollback source for this phone: $FW"
  echo "  run.sh is now unlocked."
  echo
  echo "  This is the cost of safety — paid once, in full: three complete"
  echo "  backups, 3-way verified, master certified. Safety above anything."
}

case "$MODE" in
  userdata)
    a="${2:-}"
    case "$a" in
      y|yes) echo yes > "$UD_FILE"; echo "userdata capture: YES (all future sessions include it)" ;;
      n|no)  echo no  > "$UD_FILE"; echo "userdata capture: NO (excluded from all sessions; change with ./insure.sh userdata y)" ;;
      *) show_status; echo; echo "change with: ./insure.sh userdata y|n" ;;
    esac
    exit 0 ;;
  status)   show_status ;;
  session1) read_session "$B1" "session1" ;;
  session2) read_session "$B2" "session2" ;;
  session3) read_session "$B3" "session3" ;;
  verify)   verify_backups ;;
  all)
    echo "insure — THE INSURANCE (3 complete backups + 3-way verify + master copy)"
    echo
    echo "  THE COST OF SAFETY, stated plainly: 3 full read sessions (multi-hour,"
    echo "  userdata included) and ~120 GB of disk. Safety is above anything — if"
    echo "  you cannot afford the time or the disk, you are not ready to perform"
    echo "  surgery on this phone. It is one-time."
    echo
    show_status
    echo
    [ -f "$STAGE_DIR/.insure_session1.done" ] || read_session "$B1" "session1"
    [ -f "$STAGE_DIR/.insure_session2.done" ] || read_session "$B2" "session2"
    [ -f "$STAGE_DIR/.insure_session3.done" ] || read_session "$B3" "session3"
    verify_backups
    ;;
  *) fail "usage: ./insure.sh [all|session1|session2|session3|verify|status] [--fresh]" ;;
esac
