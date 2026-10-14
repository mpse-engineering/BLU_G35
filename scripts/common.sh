# shared helpers — sourced by every step
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
cd "$KIT_ROOT"
RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; NC=$'\033[0m'
fail() { echo "${RED}FAIL:${NC} $*"; exit 1; }
info() { echo "${YLW}==>${NC} $*"; }
ok()   { echo "${GRN}PASS:${NC} $*"; }
sha_file() { python3 - "$1" <<'PY'
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
PY
}
expect() { # expect <label> <got> <want>
  if [ "$2" = "$3" ]; then ok "$1 matches"; else fail "$1 mismatch: got=$2 want=$3"; fi
}
confirm() { # confirm <what>
  echo "${YLW}ABOUT TO:${NC} $1"
  read -r -p "type YES to continue: " a
  [ "$a" = "YES" ] || fail "aborted by operator"
  echo "[operator confirmed YES]"
}
stage_exec_payload() { # spd_dump needs this file in its CWD (see connect)
  local want="a06838f71a2e938f4abb66cd80b1ef7992640db8d939d81c093fb60b83849cd9"
  if [ -f fdl/custom_exec_no_verify_4ee8.bin ]; then
    cp fdl/custom_exec_no_verify_4ee8.bin custom_exec_no_verify_4ee8.bin
    local got; got="$(sha_file custom_exec_no_verify_4ee8.bin)"
    [ "$got" = "$want" ] || fail "staged exec payload hash mismatch: got=$got want=$want"
  else
    fail "fdl/custom_exec_no_verify_4ee8.bin missing from the kit"
  fi
}
connect() { # connect <ops...>  — canonical sc9863a download-mode session
  # spd_dump resolves the exec_addr payload as a CWD-RELATIVE filename
  # ("custom_exec_no_verify_4ee8.bin", hardcoded in its arg parser — no path
  # option exists), so stage it next to the process CWD before every session.
  # Hash-checked: a corrupted stage aborts the session before USB is touched.
  stage_exec_payload
  "$SPD_DUMP" --wait 300 exec_addr 0x4ee8 \
    fdl fdl/fdl1-dl.bin 0x5000 \
    fdl fdl/fdl2-dl.bin 0x9efffe00 \
    exec "$@"
}

# ---- session logging -------------------------------------------------------
# Every script that sources this file is tee'd to
#   logs/<script-name>_<timestamp>.log
# so the full transcript (PASS/FAIL lines, YES-gate questions, spd_dump output)
# survives for post-run review. Typed y/n answers do NOT land in the log (they
# never echo); the questions and the final rc do.
LOG_DIR="$KIT_ROOT/logs"
LOG_NAME="$(basename "${BASH_SOURCE[1]}" .sh)"
LOG_FILE="$LOG_DIR/${LOG_NAME}_$(date +%Y%m%d_%H%M%S).log"
LOG_START=$SECONDS
mkdir -p "$LOG_DIR" || { echo "FAIL: cannot create $LOG_DIR" >&2; exit 1; }
: > "$LOG_FILE" || { echo "FAIL: cannot write $LOG_FILE" >&2; exit 1; }
exec > >(tee "$LOG_FILE") 2>&1
trap 'rc=$?; echo "=== ended rc=$rc after $((SECONDS-LOG_START))s — $LOG_FILE ==="' EXIT
echo "=== BLU G35 unlock kit — session log ==="
echo "script : ${LOG_NAME}.sh"
echo "started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "host   : $(uname -srm)"
echo "kit    : $KIT_ROOT"
echo "========================================="

# SPD_DUMP is MANDATORY — operator policy: no PATH/tools/ guessing, the tool
# location must be explicit. EVERY step in this kit serves the device run, so
# all of them refuse to run without it. Enforced after the session log opens,
# so the refusal is recorded in the log.
# ---- [public-kit addition] SPD_DUMP_HOME -> SPD_DUMP ------------------------
# Release contract: SPD_DUMP_HOME is a spreadtrum_flash directory whose build
# produced spd_dump. prepare.sh/setup.sh fetch and build the canonical source
# (TomKing062/spreadtrum_flash) into the workspace when it is unset, and
# record the path in ../.spd_dump_home so later gates pick it up in any
# terminal. An explicit export always wins over the recorded path.
if [ -z "${SPD_DUMP_HOME:-}" ]; then
  SPD_DUMP_HOME="$(cat "$KIT_ROOT/../.spd_dump_home" 2>/dev/null || true)"
fi
[ -n "${SPD_DUMP_HOME:-}" ]   || fail "SPD_DUMP_HOME is not defined — run ./prepare.sh first (it fetches and
builds the canonical spd_dump into the workspace and records the path), or:
    export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
[ -x "$SPD_DUMP_HOME/spd_dump" ]   || fail "SPD_DUMP_HOME=$SPD_DUMP_HOME has no executable spd_dump in it —
point it at the directory whose build produced the binary"
SPD_DUMP="$SPD_DUMP_HOME/spd_dump"
ok "spd_dump: $SPD_DUMP"
# [public-kit addition] workspace gate — see README section 3.
# Appended verbatim by the release builder; not part of the field-proven
# DEV script body.

# ---- workspace gate (Release editions only; DEV has no such block) ---------
# The workspace contract is: ./prepare.sh -> ./setup.sh -> ./verify.sh ->
# ./insure.sh. verify.sh creates .verified; insure.sh creates .insured after
# the three backups are 3-way-verified and the certified master exists.
# Exemptions (offline testing only, set by the shipped tools — never by hand):
#   KIT_VERIFY_SELFTEST=1   verify.sh's own stub-driven self-test
#   KIT_ROLLBACK_SELFTEST=1 the offline suite's rollback_to_stock scenarios
if [ ! -f "$KIT_ROOT/.verified" ] && [ "${KIT_VERIFY_SELFTEST:-0}" != "1" ] \
   && [ "${KIT_ROLLBACK_SELFTEST:-0}" != "1" ]; then
  fail "workspace contract incomplete — this kit refuses to run until you have executed, from the kit root, in this exact order:
    ./prepare.sh   (rebuild-proofs every patch artifact; fetches/builds spd_dump when SPD_DUMP_HOME is unset)
    ./setup.sh     (verifies the spd_dump dependency — SPD_DUMP_HOME)
    ./verify.sh    (manifest + verifier + full offline self-test)
    ./insure.sh    (three complete backups, 3-way verified — the restore path)
Then re-run this step. Nothing has been written to any device."
fi
if [ ! -f "$KIT_ROOT/.insured" ] && [ "${KIT_VERIFY_SELFTEST:-0}" != "1" ] \
   && [ "${KIT_ROLLBACK_SELFTEST:-0}" != "1" ]; then
  fail "insurance stamp missing (.insured) — run ./insure.sh first. This kit does
not write to a phone that has no verified restore path. See guide chapter 6:
the insurance is the cost of safety, and safety is above anything."
fi

# ---- confirm v2: re-point DEV's confirm() at the release decision gate -----
# DEV signature: confirm <instruction...> (implicit word: YES). Same call
# signature here, so every step script gets the new UX with zero call-site
# changes. Case-sensitive on purpose.
confirm() { local m="$1"; ask_continue YES "$m"; }
#!/usr/bin/env bash
# ask_continue.sh — the kit's ONE decision gate (v2 UX), sourced by the root
# gates (insure.sh, rollback_to_stock.sh, write_init_boot.sh) and injected
# into scripts/common.sh by the builder (which re-points DEV's confirm() at
# ask_continue — so every step script gets it with zero call-site changes).
#
#   ask_continue <WORD> [instruction lines...]
#     exact WORD (case-sensitive)   -> proceed
#     NO                            -> clean abort (nothing further was done)
#     anything else / empty / EOF   -> hint + re-ask. Work is NEVER thrown
#                                      away over a typo.
#   ask_choice <question> <valid words...>   -> sets $CHOICE, re-asking on
#     anything invalid (used for y/n verdicts, RUN/S, 1/2 menus).
#
# Field lessons baked in: 'yes' with capslock off, and a stray \n from a
# double Enter, used to abort whole sessions and throw away completed work.
# Now they re-ask. The WORD itself stays case-sensitive ON PURPOSE — an
# important decision gate proves the operator read the instruction.
ask_choice() { # ask_choice <question> <valid words...>  -> sets CHOICE
  local q="$1"; shift
  local a w
  while :; do
    if ! read -r -p "$q: " a; then
      echo "[stdin closed — aborting, nothing further was done]"
      exit 1
    fi
    for w in "$@"; do
      if [ "$a" = "$w" ]; then CHOICE="$a"; return 0; fi
    done
    if [ -z "$a" ]; then
      echo "  (nothing entered — case-sensitive, exactly one of: $*. Nothing happened; try again.)"
    else
      echo "  (invalid answer \"$a\" — case-sensitive, exactly one of: $*. Nothing happened; try again.)"
    fi
  done
}

ask_continue() { # ask_continue <WORD> [instruction lines...]
  local want="$1"; shift
  if [ $# -gt 0 ]; then printf '%s\n' "$*"; fi
  ask_choice "Type $want to continue or NO to abort/exit" "$want" NO
  case "$CHOICE" in
    "$want") echo "[operator confirmed $want]" ;;
    NO)      echo "[operator aborted: NO — nothing further was done]"; exit 1 ;;
  esac
}
