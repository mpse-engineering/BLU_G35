#!/usr/bin/env bash
# run.sh — the RUN entry point. After prepare/setup/verify/insure, this walks
# you through the device procedure in order, with a printed plan before each
# step and a mandatory confirmation between steps.
#
#     ./run.sh              (interactive, from the kit root)
#     ./run.sh step02       (run one named step: step02, step03, ... rollback)
#
# It only orchestrates: every actual gate (YES prompts, partition lists,
# read-back verification) lives inside the step scripts themselves.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$KIT_ROOT"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; NC=$'\033[0m'
fail() { echo "${RED}FAIL:${NC} $*"; exit 1; }
info() { echo "${YLW}==>${NC} $*"; }

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


[ -f .verified ] || fail "workspace contract incomplete — run ./verify.sh first (README, section 3)"
[ -f .insured ]  || fail "insurance stamp missing — run ./insure.sh first. The kit does not write to a phone that has no verified restore path."
# dependency: SPD_DUMP_HOME — explicit export wins; else the path recorded by
# prepare.sh/setup.sh in ../.spd_dump_home; else refuse with instructions
[ -n "${SPD_DUMP_HOME:-}" ] || SPD_DUMP_HOME="$(cat "$(cd "$KIT_ROOT/.." && pwd)/.spd_dump_home" 2>/dev/null || true)"
[ -n "${SPD_DUMP_HOME:-}" ] || fail "SPD_DUMP_HOME is not defined — run ./prepare.sh first (it fetches and
builds the canonical spd_dump into the workspace and records the path), or:
    export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
SPD_DUMP="$SPD_DUMP_HOME/spd_dump"
[ -x "$SPD_DUMP" ] || fail "SPD_DUMP_HOME=$SPD_DUMP_HOME has no executable spd_dump in it"

step_file() { # step_file step04 -> scripts/step04_stage_unlock.sh
  case "$1" in
    step00) echo scripts/step00_check_env.sh ;;
    step01) echo scripts/step01_verify_package.sh ;;
    step02) echo scripts/step02_sanity_read.sh ;;
    step03) echo scripts/step03_ram_boot_test.sh ;;
    step04) echo scripts/step04_stage_unlock.sh ;;
    step05) echo scripts/step05_fire_unlock.sh ;;
    step06) echo scripts/step06_verify_unlock.sh ;;
    step07) echo scripts/step07_restore_official.sh ;;
    step08) echo scripts/step08_wipe_data.sh ;;
  esac
}
ORDER=(step00 step01 step02 step03 step04 step05 step06 step07 step08)

if [ $# -ge 1 ]; then
  case "$1" in
    rollback) exec bash rollback/rollback_spl_uboot.sh ;;
    step0[0-8]) exec bash "$(step_file "$1")" ;;
    *) fail "unknown target: $1 (use: ${ORDER[*]} or rollback)" ;;
  esac
fi

echo "run — BLU G35 (SC9863A) bootloader unlock, full sequence"
echo
cat <<'DISC'
THE FOUR DISCLAIMERS (full text: DISCLAIMER.md — read it before this):
  1) Like any phone firmware tool, you can brick your phone. Everything
     demonstrated on this hardware was recoverable via download mode, and
     the real risk concentrates in DEVIATING from the procedure.
  2) Make sure your phone is the exact model. step02 hard-fails on any
     firmware mismatch, with no override, by design.
  3) This kit is the cleaned release of code proven end-to-end on a real
     BLU G35 (see DISCLAIMER.md for the precise lineage).
  4) When this works for you, report back (./make_report.sh). That report
     is what gives the next person confidence to start.
DISC
echo
cat <<'PLAN'
The procedure, in order. Each step explains itself and asks for an explicit
YES before doing anything:

  step00  environment preflight (offline)
  step01  package integrity (offline)
  step02  device sanity, READ-ONLY (proves this kit matches YOUR firmware)
  step03  RAM-boot proof of the patched SPL (no flash writes; if it does
          not boot, up to TWO guided retries are offered — one no-boot is
          routine, "may need twice", exactly like step05)
  step04  stage: erase splloader, write patched LK to both slots
  step05  THE UNLOCK: stage cboot writer, then fire it (black screen)
  step06  verify the unlock flag (populated = unlocked)
  step07  restore official boot chain (hash-verified stock everywhere)
  step08  wipe data (mandatory after unlock — asks first whether the
          on-screen factory reset already happened after step07's boot;
          if it did, the wipe is done and step08 skips the second one)

RULES: stock device, battery well above 40 minutes, cable plugged directly
into the computer, and STOP on any FAIL — paste the log from logs/.
PLAN
echo

for s in "${ORDER[@]}"; do
  f="$(step_file "$s")"
  [ -f "$f" ] || fail "missing $f"
  echo
  info "NEXT: $f"
  ask_choice "Type RUN to execute it, or S to stop here" RUN S
  case "$CHOICE" in
    RUN) bash "$f" || fail "$f returned non-zero — STOP (rule: no step after a FAIL). Log is in logs/." ;;
    S)   echo "stopped by operator — resume later with: ./run.sh $s"; exit 0 ;;
  esac
done

echo
echo "${GRN}run: FULL SEQUENCE COMPLETED${NC}"
cat <<'AFTER'
Next: after step08's wipe and first boot, complete setup, enable Developer
options + USB debugging, then root with ONE command:

    ./root_with_magisk.sh

(it fetches the latest Magisk, installs it, patches YOUR stock init_boot in
the Magisk app, and writes it through the gated writer — guide chapter 8.
Offline/pinned alternative: MAGISK_APK=/path/to.apk ./root_with_magisk.sh,
or the manual chapter 8 way ending in:
    IMG=magisk_patched-XXXXX.img ./write_init_boot.sh
NOT fastboot — its write path is broken on this phone.)
When it works: ./make_report.sh, attach the boot-screen photo, and post it.
AFTER
