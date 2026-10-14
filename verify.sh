#!/usr/bin/env bash
# verify.sh — GATE 3 of 3. Proves this extracted copy is intact and sane, then
# stamps it (.verified) so the run steps will execute. Nothing here touches a
# device.
#
#     ./verify.sh              (from the kit root)
#
# 1) manifest integrity  — every file's sha256 vs MANIFEST.sha256
# 2) artifact proofs     — verify_artifacts.py (the 28-check re-derivation +
#                          pin verification; independent of the manifest)
# 3) offline self-test   — the FULL step choreography (step02..step08, rollback,
#                          negative cases) executed against a stateful spd_dump
#                          stub. No phone, no USB, nothing real is touched.
# On success it writes .verified — the run steps refuse to start without it.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$KIT_ROOT"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; NC=$'\033[0m'
fail() { echo "${RED}FAIL:${NC} $*"; exit 1; }
ok()   { echo "${GRN}PASS:${NC} $*"; }

echo "verify — package integrity, artifact proofs, offline self-test (no device)"
echo

# ---- 1) manifest integrity --------------------------------------------------
python3 - <<'PY' || fail "manifest integrity — see mismatches above; re-extract the tarball"
import hashlib, sys
want = {}
for line in open("MANIFEST.sha256"):
    h, name = line.split(maxsplit=1)
    want[name.strip()] = h
bad = 0
for name, h in sorted(want.items()):
    try:
        got = hashlib.sha256(open(name, "rb").read()).hexdigest()
    except FileNotFoundError:
        print(f"FAIL: missing: {name}"); bad += 1; continue
    if got != h:
        print(f"FAIL: altered: {name}"); bad += 1
extra = []
RUNTIME_ROOT_FILES = ("custom_exec_no_verify_4ee8.bin", "pgpt.bin")
for root, dirs, files in __import__("os").walk("."):
    dirs[:] = [d for d in dirs if d not in ("logs", "work", "stub_state", "official", ".git")]
    for f in files:
        rel = __import__("os").path.relpath(__import__("os").path.join(root, f), ".").replace("\\", "/")
        if rel in ("MANIFEST.sha256", ".verified") or rel.startswith(("work/", "logs/", "stub_state/")):
            continue
        if rel in RUNTIME_ROOT_FILES or rel.startswith("partition_") and rel.endswith(".xml"):
            continue  # runtime artifacts of device sessions — re-verify stays clean
        if rel not in want:
            extra.append(rel)
for e in sorted(extra):
    print(f"FAIL: file not in manifest: {e}"); bad += 1
sys.exit(1 if bad else 0)
PY
ok "manifest: $(grep -c . MANIFEST.sha256) entries verified, no alterations"

# ---- 2) artifact proofs ------------------------------------------------------
python3 verify_artifacts.py || fail "artifact proofs failed — DO NOT continue"
ok "verify_artifacts.py: all artifact proofs pass"

# ---- 3) offline self-test against the stub ----------------------------------
[ -f tools/stub_spd_dump ] || fail "tools/stub_spd_dump missing (incomplete extraction)"
T="$(mktemp -d)"
cp -r . "$T/kit"
rm -rf "$T/kit/logs" "$T/kit/work" "$T/kit/stub_state" "$T/kit/.verified"
cp tools/stub_spd_dump "$T/kit/stub_spd_dump"
chmod +x "$T/kit/stub_spd_dump"
mkdir -p "$T/kit/stubhome"
ln -sf ../stub_spd_dump "$T/kit/stubhome/spd_dump"   # stub masquerades as a built spd_dump
pass=0; failed=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else echo "FAIL: $1 (want rc=$2 got rc=$3)"; failed=$((failed+1)); fi; }
set +e   # several scenarios EXPECT failure; they manage their own rc
# (no subshell: the counters must be updated in THIS shell — a (…) block
# would silently discard every result and the verdict would mean nothing)
cd "$T/kit"
export SPD_DUMP_HOME="$PWD/stubhome" STUB_STATE="$PWD/stub_state"
export KIT_VERIFY_SELFTEST=1
STUB_NO_DEVICE=1 bash scripts/step02_sanity_read.sh </dev/null >/dev/null 2>&1; chk "no-device refusal" 1 $?
printf 'YES\n' | bash scripts/step02_sanity_read.sh   >/dev/null 2>&1; chk "step02" 0 $?
printf 'YES\n' | bash scripts/step04_stage_unlock.sh  >/dev/null 2>&1; chk "step04" 0 $?
printf 'YES\n' | bash rollback/rollback_spl_uboot.sh  >/dev/null 2>&1; chk "rollback from staged" 0 $?
printf 'YES\n' | bash scripts/step04_stage_unlock.sh  >/dev/null 2>&1; chk "re-stage" 0 $?
printf 'YES\ny\n' | bash scripts/step03_ram_boot_test.sh >/dev/null 2>&1; chk "step03" 0 $?
printf 'YES\nYES\nn\n' | bash scripts/step05_fire_unlock.sh >/dev/null 2>&1; chk "step05" 0 $?
printf 'YES\nYES\ny\nYES\n' | bash scripts/step05_fire_unlock.sh >/dev/null 2>&1; chk "step05 2nd attempt" 0 $?
printf 'YES\n' | bash scripts/step06_verify_unlock.sh >/dev/null 2>&1; chk "step06 on locked state refuses" 1 $?
touch stub_state/.unlocked
printf 'YES\ny\n' | bash scripts/step06_verify_unlock.sh >/dev/null 2>&1; chk "step06 unlocked" 0 $?
printf 'YES\n' | bash scripts/step07_restore_official.sh >/dev/null 2>&1; chk "step07" 0 $?
printf 'n\nYES\n' | bash scripts/step08_wipe_data.sh     >/dev/null 2>&1; chk "step08" 0 $?
bash scripts/step01_verify_package.sh                 >/dev/null 2>&1; chk "step01" 0 $?
cd "$KIT_ROOT"
set -euo pipefail
if [ "$failed" -ne 0 ]; then
  echo; echo "self-test transcript: $T/kit/logs/ (kept for inspection)"
  fail "offline self-test: $pass passed, $failed FAILED"
fi
ok "offline self-test: $pass/13 scenarios pass (full choreography, no device)"
rm -rf "$T"

# ---- 4) stamp ----------------------------------------------------------------
date -u +"verified %Y-%m-%dT%H:%M:%SZ by verify.sh" > .verified
echo
echo "${GRN}verify: ALL CHECKS PASS — this copy is stamped .verified${NC}"
echo "You may now run:  ./insure.sh    (the insurance — it unlocks ./run.sh)"
