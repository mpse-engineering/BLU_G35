#!/usr/bin/env bash
# prepare.sh — GATE 1 of 3. Compiles/derives every patch artifact from the
# kit's own official/ dumps and byte-compares against the shipped artifacts.
# If ANYTHING in this kit was altered or corrupted, this is where it dies.
#
#     ./prepare.sh            (from the kit root; no device)
#
# What it rebuilds and proves:
#   artifacts/spl-unlock.bin   : the maintainer tool's canonical 20-NOP patch
#                                (5 verify sites x 4 words incl. the fail-handler
#                                call; payload cut at 0xE804 keeps the sig block)
#   artifacts/uboot-patched.bin: patch A — cbz->b at 0x10e28 (fastboot oem unlock
#                                SN-verify bypass). The boot-time trampoline was
#                                field-falsified and stays retired.
#   fdl/fdl2-cboot.bin         : fdl2-dl + EXACTLY 8 words (mov w0,#1; bl
#                                <set_lock_status path>) — the unlock writer
# It also self-checks the exec stub (custom_exec_no_verify_4ee8.bin).
#
# Dependency: SPD_DUMP_HOME — a directory containing the spd_dump binary
# ($SPD_DUMP_HOME/spd_dump). If it is not set, this script fetches and builds
# the source ONCE — PINNED to the field-certified upstream commit
# d24c21a0c93a545c0130668caa1826d59ceebe48 (git clone + checkout + make into
# the workspace next to this kit; the tree the certified binary's sha1 line
# self-reports. Newer upstream main needs libxml2-dev to build and its
# changes are unproven here — the kit does not deviate) — and exports
# SPD_DUMP_HOME for its own run. If it IS set, your own checkout/build is
# used, untouched.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
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

echo "prepare — rebuild-proofs all patch artifacts (no device)"
echo

# ---- 0a) sanity: required inputs present -----------------------------------
for f in official/splloader.bin official/uboot.bin fdl/fdl2-dl.bin \
         artifacts/spl-unlock.bin artifacts/uboot-patched.bin fdl/fdl2-cboot.bin \
         fdl/custom_exec_no_verify_4ee8.bin; do
  [ -f "$f" ] || fail "required file missing: $f (incomplete extraction? re-extract the tarball)"
done
ok "all required inputs present"

# ---- 0b) SPD_DUMP_HOME — locate or build the one runtime dependency --------
# The device tools talk to the phone through spd_dump (built from the
# TomKing062/spreadtrum_flash sources). Contract: $SPD_DUMP_HOME/spd_dump.
#   export SPD_DUMP_HOME=/path/to/spreadtrum_flash  -> your own build is used
#   unset                                           -> cloned + built ONCE
#      into the workspace (../spreadtrum_flash) and exported for this run
SPD_DUMP_HOME="${SPD_DUMP_HOME:-}"
if [ -n "$SPD_DUMP_HOME" ]; then
  [ -x "$SPD_DUMP_HOME/spd_dump" ] \
    || fail "SPD_DUMP_HOME=$SPD_DUMP_HOME has no executable spd_dump in it — point it\nat the spreadtrum_flash directory whose build produced the binary\n(or unset it and let this script fetch and build the canonical source)"
  ok "SPD_DUMP_HOME: $SPD_DUMP_HOME (operator-provided)"
else
  info "SPD_DUMP_HOME not set — fetching and building the certified spd_dump"
  info "  source: https://github.com/TomKing062/spreadtrum_flash.git, pinned to the certified commit"
  for t in git make gcc; do
    command -v "$t" >/dev/null 2>&1 \
      || fail "$t not found — needed to fetch/build spd_dump. Debian/Ubuntu:\nsudo apt install git build-essential libusb-1.0-0-dev   — then re-run ./prepare.sh\n(or build the source yourself and: export SPD_DUMP_HOME=/path/to/spreadtrum_flash)"
  done
  pkg-config --exists libusb-1.0 2>/dev/null || \
    { ls /usr/include/libusb-1.0/libusb.h >/dev/null 2>&1 || \
      fail "libusb-1.0 development headers not found — Debian/Ubuntu:\nsudo apt install libusb-1.0-0-dev   — then re-run ./prepare.sh"; }
  # PINNED SOURCE (see header): this kit builds ONLY the field-certified
  # upstream commit — the tree the certified binary's sha1 line self-reports.
  # Upstream main has moved past it; those changes are unproven on this
  # device. Your own build? export SPD_DUMP_HOME=/path/to/spreadtrum_flash
  SPFDUMP_PIN="d24c21a0c93a545c0130668caa1826d59ceebe48"
  SRCDIR="$(cd .. && pwd)/spreadtrum_flash"
  moved=0   # 1 = tree moved to the pin this run -> any existing binary is stale
  if [ ! -d "$SRCDIR" ]; then
    ( cd .. && git clone https://github.com/TomKing062/spreadtrum_flash.git ) \
      || fail "git clone failed — check your network, or clone\nhttps://github.com/TomKing062/spreadtrum_flash.git yourself into the workspace\n(next to this kit), run: git checkout $SPFDUMP_PIN ; make ;\nthen: export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
    ( cd "$SRCDIR" && git -c advice.detachedHead=false checkout -q "$SPFDUMP_PIN" ) \
      || fail "could not check out the pinned commit $SPFDUMP_PIN in the fresh clone.\nOr build your own copy and: export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
    moved=1
  else
    cur_head="$(git -C "$SRCDIR" rev-parse HEAD 2>/dev/null || true)"
    if [ "$cur_head" != "$SPFDUMP_PIN" ]; then
      [ -d "$SRCDIR/.git" ] \
        || fail "$SRCDIR is not the canonical git clone (no .git).\nThis kit builds ONLY the pinned commit $SPFDUMP_PIN.\nRemove the directory and re-run, or build your own and:\nexport SPD_DUMP_HOME=/path/to/spreadtrum_flash"
      info "$SRCDIR is at ${cur_head:-unknown} — checking out the pinned certified commit"
      ( cd "$SRCDIR" && git -c advice.detachedHead=false checkout -q "$SPFDUMP_PIN" ) \
        || fail "could not check out the pinned commit $SPFDUMP_PIN in $SRCDIR —\nis it a clone of TomKing062/spreadtrum_flash?\nOr build your own copy and: export SPD_DUMP_HOME=/path/to/spreadtrum_flash"
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
    [ -x "$SRCDIR/spd_dump" ] \
      || fail "build finished but $SRCDIR/spd_dump is not executable"
    ok "built: $SRCDIR/spd_dump (pinned source)"
  fi
  # binary identity gate: whatever was built/reused must self-report the pin
  ident="$($SRCDIR/spd_dump --help 2>&1 | grep -o 'sha1:[0-9a-f]*' | head -n1 || true)"
  [ "$ident" = "sha1:$SPFDUMP_PIN" ] \
    || fail "spd_dump identity mismatch: got '${ident:-none}', want sha1:$SPFDUMP_PIN.\nThe binary in $SRCDIR is not from the pinned certified tree.\nDelete it and re-run, or build your own and:\nexport SPD_DUMP_HOME=/path/to/spreadtrum_flash"
  ok "spd_dump identity: $ident (certified)"
  SPD_DUMP_HOME="$SRCDIR"
  ok "SPD_DUMP_HOME: $SPD_DUMP_HOME (pinned $SPFDUMP_PIN)"
fi
# record the resolved path — later gates pick it up in fresh terminals
printf '%s\n' "$SPD_DUMP_HOME" > "$(cd .. && pwd)/.spd_dump_home"

# ---- 1) official/ dumps are the proven bases -------------------------------
SPL_SHA="$(sha official/splloader.bin)"
UB_SHA="$(sha official/uboot.bin)"
[ "$SPL_SHA" = "493b54241f201a03ba175752bea9345e987737340ec5f763645550280d3aa124" ] \
  || fail "official/splloader.bin is not the proven dump ($SPL_SHA)"
[ "$UB_SHA" = "68c1b59986204ffada680d304c560839b6a188000b63f90c73a205d7381fb2a3" ] \
  || fail "official/uboot.bin is not the proven dump ($UB_SHA)"
ok "official/ dumps match the proven hashes"

# ---- 2) rebuild spl-unlock.bin (canonical 4-NOP x 5 sites, cut 0xE804) -----
mkdir -p work
python3 - <<'PY'
import struct
stock = bytearray(open("official/splloader.bin","rb").read())
SITES = [0x9E00, 0x9F10, 0xA050, 0xA084, 0xA0B4]   # bl-verify positions
NOP   = 0xD503201F
w = lambda b,o: struct.unpack_from("<I", b, o)[0]
for s in SITES:
    for o in range(4):                                   # all four words, incl.
        struct.pack_into("<I", stock, s+4*o, NOP)        # the bl fail_handler
open("work/spl-unlock.rebuilt.bin","wb").write(bytes(stock[:0xE804]))
PY
ok "spl-unlock rebuilt (canonical algorithm)"
cmp -s work/spl-unlock.rebuilt.bin artifacts/spl-unlock.bin \
  || fail "artifacts/spl-unlock.bin does NOT match its recipe — the kit was altered or corrupted. STOP."
ok "artifacts/spl-unlock.bin == rebuilt from official/ (byte-exact)"

# ---- 3) rebuild uboot-patched.bin (patch A only) ----------------------------
python3 - <<'PY'
import struct
ub = bytearray(open("official/uboot.bin","rb").read())
SITE, TARGET = 0x10E28, 0x1100C
w = struct.unpack_from("<I", ub, SITE)[0]
assert w == 0x34000F20, f"stock word at {SITE:#x} is {w:#x}, want cbz w0,#0x1100c"
off = (TARGET - SITE)//4
struct.pack_into("<I", ub, SITE, 0x14000000 | (off & 0x3FFFFFF))
open("work/uboot-patched.rebuilt.bin","wb").write(bytes(ub))
PY
ok "uboot-patched rebuilt (patch A: cbz->b @0x10e28)"
cmp -s work/uboot-patched.rebuilt.bin artifacts/uboot-patched.bin \
  || fail "artifacts/uboot-patched.bin does NOT match its recipe. STOP."
ok "artifacts/uboot-patched.bin == rebuilt from official/ (byte-exact)"

# ---- 4) prove fdl2-cboot == fdl2-dl + exactly 8 words ----------------------
python3 - <<'PY'
import struct
a = open("fdl/fdl2-dl.bin","rb").read()
b = open("fdl/fdl2-cboot.bin","rb").read()
assert len(a) == len(b), "cboot/dl size differ — not the proven pair"
diffs = [(o, struct.unpack_from("<I",a,o)[0], struct.unpack_from("<I",b,o)[0])
         for o in range(0, min(len(a),len(b))-3, 4)
         if a[o:o+4] != b[o:o+4]]
assert len(diffs) == 8, f"cboot delta is {len(diffs)} words, proven value is 8"
OFFS = {o for o, _, _ in diffs}
PROVEN = {0x0051AC, 0x005714, 0x005718, 0x00571C,
          0x066CC4, 0x066CC8, 0x066CCC, 0x066CD0}
assert OFFS == PROVEN, f"cboot delta offsets {sorted(hex(o) for o in OFFS)} != proven set"
assert diffs[1][2] == 0x52800020, \
    "word at 0x5714 is not 'mov w0,#1' (unlock arg) — provenance broken"
assert (diffs[2][2] >> 26) == 0b100101, \
    "word at 0x5718 is not a bl (lockflag write path) — provenance broken"
words = " ".join(f"{w:08x}" for _,_,w in diffs)
print(f"  cboot delta: {len(diffs)} words at "
      + ", ".join(f"0x{o:x}" for o,_,_ in diffs))
PY
ok "fdl2-cboot provenance: fdl2-dl + exactly the unlock-write words"

# ---- 5) exec stub self-check ------------------------------------------------
GOT="$(sha fdl/custom_exec_no_verify_4ee8.bin)"
[ "$GOT" = "a06838f71a2e938f4abb66cd80b1ef7992640db8d939d81c093fb60b83849cd9" ] \
  || fail "exec stub hash mismatch: $GOT (tampered or corrupted — STOP)"
ok "exec stub (custom_exec_no_verify_4ee8.bin) intact"

# ---- 6) cleanup + summary ---------------------------------------------------
rm -rf work
echo
echo "${GRN}prepare: ALL PROOFS PASS${NC}"
echo "  every shipped artifact is byte-exactly derivable from the official/"
echo "  dumps this kit ships with. Dependency ready: SPD_DUMP_HOME=$SPD_DUMP_HOME"
echo "  Continue with ./setup.sh (it re-detects SPD_DUMP_HOME; export it in your"
echo "  shell only if you run the gates in separate terminals)"
