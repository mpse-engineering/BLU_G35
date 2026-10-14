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
