#!/usr/bin/env python3
"""part_classes.py — classification of SPRD/SC9863A partitions for the
3-way insurance verification (insure.sh).

KEY      — factory/identity/boot-chain content. MUST be identical across all
           three backups. Any difference HALTS the kit (no override).
CAL      — radio calibration / factory NV (l_fixnv*, calinv): per-device,
           boot-stable, and precious — but EXCLUDED from the 3-way comparison
           by field decision (2026-09-26): the capture tool cannot even read
           the nv1 copies back faithfully (it returns the nv2 mirror from
           offset 0x200), so a hash mismatch would be a tool artifact, not
           evidence. The kit never writes these either.
VOLATILE — runtime state: logs, counters, boot-time recomputed data. Backed
           up in full (everything is backed up), EXCLUDED from the 3-way
           comparison. Also covers userdata/cache (change constantly by
           design; the kit never diffs them).
UNKNOWN  — anything not matched below. Backed up; if its hash differs across
           the 3 backups the user gets a yellow warning and must type YES.

Matching is case-insensitive on the partition NAME from the device's own GPT
(pgpt.bin). Name prefixes are matched so size/family variants (nv1/nv2,
_lg, _gd, etc.) classify without hardcoding one device's exact layout.
Every GPT entry MUST end up in exactly one class — the classifier fails
closed: an unmatched name is UNKNOWN and an UNKNOWN diff is always
surfaced to the user, never silent.
"""
import re

# name-lowercase prefixes/regexes -> class
_CLASS_RULES = [
    # ---- KEY: boot chain ----
    (r"^(splloader|uboot_a|uboot_b|uboot|l_g0mp|l_ldsp|f_boot|tboot)$", "KEY"),
    (r"^(boot_a|boot_b|boot|init_boot_a|init_boot_b|init_boot|vendor_boot_a|vendor_boot_b|dtbo_a|dtbo_b|vbmeta_a|vbmeta_b|vbmeta_system|vbmeta_vendor|vbmeta)$", "KEY"),
    (r"^(trustos|tos|sml|teed|l_tee|f_tee|teecfg)", "KEY"),    # TrustOS/TEE family
    (r"^(hypervsior|hypervisor)", "KEY"),                      # hypervisor firmware (device's own spelling)
    (r"^(dtb_a|dtb_b|dtb)$", "KEY"),                           # device tree — firmware, like dtbo
    (r"^(vbmeta_odm|vbmeta_product|vbmeta_system|vbmeta_system_ext|vbmeta_vendor)", "KEY"),  # AVB descriptor partitions
    (r"^(logo|fbootlogo)$", "KEY"),                            # boot logos: static images (proven boot-stable by the verified rollback push)
    (r"^(super)$", "KEY"),                                     # dynamic-partitions OS image: static until an OTA
    (r"^(nvid|nvdata_l)$", "KEY"),                             # product NV (raw-writable, boot-stable)
    # ---- CAL: radio calibration / factory NV — compare excluded (see docstring)
    (r"^(l_fixnv1|l_fixnv2|l_fixnv|calinv)", "CAL"),
    # modem/DSP firmware — prefix-style so slot suffixes (_a/_b) match too
    # (field log 4: the anchored rule left l_modem_a/l_gdsp_a/l_ldsp_a in
    # UNKNOWN; they are firmware and must be KEY)
    (r"^(modem|l_modem|gdsp|dsp|l_gdsp|l_dsp|l_ldsp|pm_data|pm_sys|psyconf2|psyconf)", "KEY"),
    (r"^(persist|persist_a|persist_b)$", "KEY"),
    # ---- VOLATILE: runtime/boot-recomputed ----
    (r"^(l_runtimenv1|l_runtimenv2|l_runtimenv|l_runtnv1|l_runtnv2|l_runtnv|nvrng)$", "VOLATILE"),  # runtime NV pair
    (r"^(misc|miscdata|proinfo|wlog|flashinfo)$", "VOLATILE"),  # flags/state incl. the unlock flag
    (r"^(fsc|fsg|modemst1|modemst2)$", "VOLATILE"),             # modem runtime NV
    (r"^(l_deltanv|deltanv)", "VOLATILE"),                      # modem delta-NV (runtime-updated; slot-suffixed)
    # blackbox / common_rs*: field log 5 — encrypted per-device state and
    # runtime-updated reserve areas; differ across boots by design
    (r"^(blackbox)$", "VOLATILE"),
    (r"^(common_rs|avbmeta_rs)", "VOLATILE"),
    # prodnv: field log 4 (2026-09-30) — post-factory-reset captures across
    # normal boots DIFFER while all 18 other KEY partitions match exactly:
    # on this device prodnv is the RUNTIME NV store the modem writes at
    # boot. 3-way equality is unachievable and meaningless for it.
    (r"^(prodnv)$", "VOLATILE"),
    (r"^(metadata|frp|encrypt|sysdumpdb|sysdump|dump|full_dump|fulldump|minidump)$", "VOLATILE"),
    (r"^(log|logs|log_a|log_b|splog|spllog|ubootlog|uboot_log|bootchart|phonelog)$", "VOLATILE"),   # logs (anchored: must not swallow 'logo')
    (r"^(cache|userdata|data|sdcard|miscd)$", "VOLATILE"),      # user-side by definition
    (r"^(para|param|protection|fastboot|bootenv|env|ufs_fw|ffu|sim_lock|recover)", "VOLATILE"),
    (r"^(oem|oem_a|oem_b|expdb|seccfg|secu|reserve)", "VOLATILE"),
]


def classify(name):
    n = name.strip().lower()
    for pat, cls in _CLASS_RULES:
        if re.match(pat, n):
            return cls
    return "UNKNOWN"


def classify_all(names):
    """-> {class: [names sorted]}, and guarantees full coverage."""
    out = {"KEY": [], "CAL": [], "VOLATILE": [], "UNKNOWN": []}
    for n in names:
        out[classify(n)].append(n)
    for k in out:
        out[k].sort()
    return out


if __name__ == "__main__":
    import sys
    for n in sys.argv[1:]:
        print(f"{classify(n):9s} {n}")
