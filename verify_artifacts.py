#!/usr/bin/env python3
"""verify_artifacts.py — re-prove every patched byte on the operator's machine.

Independence: this script trusts NOTHING except itself and the kit's files.
It does not read MANIFEST.sha256, needs no network, no capstone, no build
environment. It re-derives both patch artifacts from the official/ dumps and
compares byte-for-byte, and pins the known-good sha256 of every security-
relevant file. If any check fails, NO device step may run.

Trust anchor: this file (it is short, commented, and worth reading).
The official/ dumps are the four-times-verified BROM extraction; pinning their
hashes here also guarantees the ROLLBACK images are the exact bases the
artifacts were built from.
Exit 0 = safe to proceed. Exit 1 = do not continue.
"""
import hashlib
import os
import struct
import sys

BASE = os.path.dirname(os.path.abspath(__file__))

# ---- pinned content (from the verified offline build, see patch_report.txt) ----
EXPECTED_SHA = {
    "official/uboot.bin":          "68c1b59986204ffada680d304c560839b6a188000b63f90c73a205d7381fb2a3",
    "official/splloader.bin":      "493b54241f201a03ba175752bea9345e987737340ec5f763645550280d3aa124",
    "official/misc.bin":           "7db67f82f318dc58a285dff1a025db0b638cf8bd8d7fe9eb198afb11e7dcc5e6",
    # patch A ONLY — the boot-time trampoline (patch B) was FIELD-FALSIFIED
    # (blank screen: TA mailbox call hangs pre-TOS on a stock-locked unit);
    # unlock goes through the maintainer's fdl2-cboot unlock-writer (below)
    "artifacts/uboot-patched.bin": "b13fbc77e6f6604a9ac6e6f8d98f0342fbf8546d6bdae99ce790a9404d28e4dc",
    # CANONICAL: byte-identical to refpkg gen_spl-unlock.exe run on this exact
    # dump (4 NOPs x 5 sites incl. bl fail_handler; cut 0xE804 keeps sig block)
    "artifacts/spl-unlock.bin":    "7b2489423b71f65bab203e1ea2eefe099f62c8026a52b77f50787db2f4e93d3a",
    # BROM-session kit (downloaded before anything else; the exec_addr payload
    # is the 128-byte no-verify exploit stub — tampering here = arbitrary
    # code at bootrom level)
    "fdl/fdl1-dl.bin":                    "9ff362f4bff3bd3bb91725291d4ded000414b60789dc22496176296df33d5384",
    "fdl/fdl2-dl.bin":                    "ec087b5dfea37874cd81d5edbc689739f60299841f6fb5622065555dcbebf294",
    # maintainer's unlock-writer: fdl2-dl plus EXACTLY 8 words — an inserted
    # "mov w0,#1; bl <set_lock_status path>" unlock write. Provenance is
    # re-proved in check (3) below, not just pinned by hash.
    "fdl/fdl2-cboot.bin":                 "c619fdc146bf778c1a3d92475f88c87f95f1b2ecee4efaa2577fe06bfe3c5dcd",
    "fdl/custom_exec_no_verify_4ee8.bin": "a06838f71a2e938f4abb66cd80b1ef7992640db8d939d81c093fb60b83849cd9",
    "fdl/pgpt.bin":                       "e71f8ba717b133976cf16d7b1ec33446cb2014d23407257246a96b07641c417d",
}
SPL_SITES = [0x9E00, 0x9F10, 0xA050, 0xA084, 0xA0B4]  # bl-verify positions (4 words each)
NOP = 0xD503201F

failures = []


def check(label, ok, detail=""):
    print(("PASS: " if ok else "FAIL: ") + label + ((" — " + detail) if detail else ""))
    if not ok:
        failures.append(label)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def word(buf, off):
    return struct.unpack_from("<I", buf, off)[0]


def setword(buf, off, w):
    struct.pack_into("<I", buf, off, w)


# ---- ARM64 encoders (same math as the offline build) ----
def enc_b(src, dst):
    d = dst - src
    assert d % 4 == 0
    o = d // 4
    assert -(1 << 25) <= o < (1 << 25)
    return 0x14000000 | (o & 0x3FFFFFF)


def enc_bl(src, dst):
    d = dst - src
    assert d % 4 == 0
    o = d // 4
    assert -(1 << 25) <= o < (1 << 25)
    return 0x94000000 | (o & 0x3FFFFFF)


def enc_adrp(rd):
    return 0x90000000 | rd          # target page == PC page (0x290000)


def enc_str_x30(rn, off):
    assert off % 8 == 0 and 0 <= off < 0x8000
    return 0xF9000000 | ((off >> 3) << 10) | (rn << 5) | 30


def enc_ldr_x30(rn, off):
    assert off % 8 == 0 and 0 <= off < 0x8000
    return 0xF9400000 | ((off >> 3) << 10) | (rn << 5) | 30


def enc_mov(rd, imm):
    assert 0 <= imm < 0x10000
    return 0xD2800000 | (imm << 5) | rd


def expected_uboot(official):
    """Re-derive uboot-patched.bin from the official dump (patch A ONLY)."""
    b = bytearray(official)
    # base-state assertions (the patch assumptions themselves)
    check("uboot base @0x10e28 == cbz w0,#0x1100c", word(b, 0x10E28) == 0x34000F20,
          "%08x" % word(b, 0x10E28))
    check("uboot base @0x5fba8 == mov x0,#0x1dc (stock, untouched)",
          word(b, 0x5FBA8) == 0xD2803B80, "%08x" % word(b, 0x5FBA8))
    check("cave 0x290000..0x290900 all zero in official",
          all(x == 0 for x in official[0x290000:0x290900]))
    if failures:
        return None
    # patch A: SN-verify bypass (fastboot oem unlock route, TOS ready)
    setword(b, 0x10E28, enc_b(0x10E28, 0x1100C))
    # patch B RETIRED: no other word may change
    check("exactly ONE word differs (patch A only)",
          sum(1 for i in range(0, len(b), 4)
              if word(b, i) != word(official, i)) == 1)
    return bytes(b)


def expected_spl(official):
    """Re-derive spl-unlock.bin from the official dump (canonical algorithm:
    4 NOPs per verify site incl. the fail_handler call; cut 0xE804)."""
    b = bytearray(official)
    check("spl DHTB magic", b[:4] == b"DHTB")
    h30 = struct.unpack_from("<I", b, 0x30)[0]
    check("spl header[0x30] == 0xe350", h30 == 0xE350, "%#x" % h30)
    if failures:
        return None
    # canonical gen_spl-unlock scan (LE):
    #   bl verify ; cbz w0,#+2 ; mov w0,#imm ; bl fail_handler
    sites = []
    off = 0x200
    while off < h30 + 0x200:
        if off + 16 <= len(b):
            w0 = word(b, off)                     # cbz w0, +2 words
            wm = word(b, off - 4) >> 8            # bl
            w2 = struct.unpack_from("<H", b, off + 6)[0]
            w3 = word(b, off + 8)                 # bl fail_handler
            if w0 == 0x34000060 and wm == 0x940000 and w2 == 0x5280 \
                    and (w3 >> 26) == 0x25:
                sites.append(off - 4)             # site starts at bl verify
        off += 4
    check("exactly the 5 known verify sites (bl positions)", sites == SPL_SITES,
          str([hex(s) for s in sites]))
    if failures:
        return None
    for s in sites:
        # the 4th word (bl fail_handler) MUST be NOPed too — leaving it live
        # made every boot call the fail handler unconditionally (the step03 crash)
        check("site %s 4th word is bl (fail_handler)" % hex(s),
              (word(b, s + 0xC) >> 26) == 0x25, "%08x" % word(b, s + 0xC))
        for o in range(4):
            setword(b, s + 4 * o, NOP)
    cut = bytes(b[:0xE804])
    check("spl cut length == 0xe804 (sig block kept)", len(cut) == 0xE804,
          "%#x" % len(cut))
    return cut


def main():
    print("=== verify_artifacts: re-proving every patched byte ===")
    # 1) pinned hashes (official dumps + artifacts)
    for rel, want in EXPECTED_SHA.items():
        p = os.path.join(BASE, rel)
        if not os.path.exists(p):
            check("file present: " + rel, False)
            continue
        got = sha(open(p, "rb").read())
        check("sha256 pinned: " + rel, got == want,
              "" if got == want else "got %s want %s" % (got[:16], want[:16]))
    if failures:
        print("\nverdict: PACKAGE TAMPERED OR WRONG DUMPS — do not run any device step")
        return 1

    # 2) re-derivation from the official dumps
    ub_off = open(os.path.join(BASE, "official/uboot.bin"), "rb").read()
    sp_off = open(os.path.join(BASE, "official/splloader.bin"), "rb").read()
    ub_art = open(os.path.join(BASE, "artifacts/uboot-patched.bin"), "rb").read()
    sp_art = open(os.path.join(BASE, "artifacts/spl-unlock.bin"), "rb").read()

    ub_exp = expected_uboot(ub_off)
    if ub_exp is not None:
        check("uboot-patched.bin == official + patch A only (byte-exact)",
              ub_exp == ub_art)
    sp_exp = expected_spl(sp_off)
    if sp_exp is not None:
        check("spl-unlock.bin == official + 20 NOPs (5x4) + cut 0xE804 (byte-exact)",
              sp_exp == sp_art)

    # 3) fdl2-cboot provenance: byte-identical to our proven fdl2-dl except
    #    EXACTLY the maintainer's 8-word unlock-write insertion. Any other
    #    delta anywhere in 717,044 bytes = tampered file, device steps stop.
    dl  = open(os.path.join(BASE, "fdl/fdl2-dl.bin"), "rb").read()
    cb  = open(os.path.join(BASE, "fdl/fdl2-cboot.bin"), "rb").read()
    CB_WORDS = {   # offset: (fdl2-dl word, fdl2-cboot word)
        0x0051AC: (0xD503201F, 0x97FFFECC),
        0x005714: (0x71000A7F, 0x52800020),   # mov w0,#1   (arg: 1 = unlock)
        0x005718: (0x54000B2C, 0x94018A06),   # bl <lockflag write path>
        0x00571C: (0x97FFFFC2, 0x14000055),   # b over the stock fail branch
        0x066CC4: (0xD503201F, 0x97FFE992),
        0x066CC8: (0xD503201F, 0x34000080),
        0x066CCC: (0xD503201F, 0xF8408E60),
        0x066CD0: (0xD503201F, 0xB5FFFF60),
    }
    if len(cb) == len(dl):
        check("fdl2-cboot same size as fdl2-dl", True, "%d bytes" % len(cb))
        diffs = {o: (word(dl, o), word(cb, o))
                 for o in range(0, min(len(dl), len(cb)), 4)
                 if word(dl, o) != word(cb, o)}
        check("cboot delta == exactly the 8 maintainer unlock-write words",
              diffs == CB_WORDS, "%d words differ" % len(diffs))
    else:
        check("fdl2-cboot same size as fdl2-dl", False)

    # 4) BCB wipe image sanity
    misc = open(os.path.join(BASE, "artifacts/misc-wipe.bin"), "rb").read()
    check("misc-wipe.bin is a boot-recovery BCB (2048 bytes)",
          len(misc) == 2048 and b"boot-recovery" in misc[:64]
          and b"--wipe_data" in misc[:1024])

    print()
    if failures:
        print("verdict: %d FAILURE(S) — do NOT run any device step" % len(failures))
        for f in failures:
            print("  - " + f)
        return 1
    print("verdict: ALL CHECKS PASS — artifacts are exactly official dumps + proven patches")
    return 0


if __name__ == "__main__":
    sys.exit(main())
