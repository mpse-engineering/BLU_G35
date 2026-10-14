#!/usr/bin/env bash
# step01_verify_package.sh — sha256-verify every file in the kit against
# MANIFEST.sha256. Catches corrupted or partially transferred packages BEFORE
# anything touches the device. No device needed.
# Read this file, then run:  ./scripts/step01_verify_package.sh
. "$(dirname "$0")/common.sh"

echo "step01 — package integrity (device NOT required)"
echo

python3 - <<'PY'
import hashlib, os, sys
n_ok = n_bad = 0
for line in open("MANIFEST.sha256"):
    line = line.strip()
    if not line:
        continue
    h, name = line.split(maxsplit=1)
    name = name.strip()
    if not os.path.exists(name):
        print(f"FAIL: missing       {name}"); n_bad += 1; continue
    d = hashlib.sha256(open(name, "rb").read()).hexdigest()
    if d != h:
        print(f"FAIL: hash mismatch {name}"); n_bad += 1
    else:
        n_ok += 1
print(f"PASS: {n_ok} files verified against MANIFEST.sha256")
if n_bad:
    print(f"FAIL: {n_bad} problems — do NOT run any later step")
    print("      re-extract the tarball and run this step again")
sys.exit(1 if n_bad else 0)
PY

echo
ok "package integrity confirmed — next: scripts/step02_sanity_read.sh"
