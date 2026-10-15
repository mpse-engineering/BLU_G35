BLU G35 (SC9863A) bootloader unlock kit
========================================

Read 00_GUIDE.md first. Really. Then DISCLAIMER.md.

Support lives at one address: the pinned issue of the repo this kit
    comes from — https://github.com/mpse-engineering/BLU_G35/issues/1
    (what this repository is, how to verify your copy, how to report
    problems — its wiki page is the report fill-in). That issue is
    pinned repo-top; the repo description points at it too.
Licensing: LICENSE.md in this folder — kit code under GPL-3.0-or-later;
    third-party lineage and runtime-fetched dependencies have their own
    sections there (some upstream material carries NO license; read it
    before any reuse).

What this is
    A self-contained kit that unlocks the bootloader of the BLU G35
    (Unisoc SC9863A) using the publicly documented CVE-2022-38694 BootROM
    method, leaves the boot chain stock, and verifies every write. It also
    insures the phone first (three backup passes over the insured partition
    set — your device-specific restore source and USB health test), roots it
    via a gated Magisk init_boot writer, and can return it to stock state.

Personal data warning
    Unlocking performs a factory reset. Back up important data independently
    and verify that your copy is usable before starting. The insurance phase
    asks whether to include userdata.img: NO means it is omitted and cannot
    be restored by this kit; YES enables an optional capture/restore path that
    was not field-tested in the maintainer's physical test cycles. Recommended:
    back up personal data separately and select NO; choose YES only if you
    deliberately accept the untested path and have another verified backup.
    Do not rely on that optional path as your only backup. The guide explains
    practical file/SMS backups and the root requirement for Neo Backup. Contact
    import/export in SMS Import / Export is marked experimental upstream; verify
    that exported contacts can actually be restored.

How to use it (the short version — the guide has every keystroke)

    1. get the kit into a fresh workspace folder (budget ~120 GB for the full
       insurance path; actual need may be lower if userdata.img is omitted):
       git clone https://github.com/mpse-engineering/BLU_G35.git blug35_unlock_kit
       (ZIP release: unzip it, then: mv BLU_G35-* blug35_unlock_kit)
    2. cd blug35_unlock_kit && ./prepare.sh      # compile-proof + fetch/build spd_dump
    3. cd .. && ./blug35_unlock_kit/setup.sh    # verifies spd_dump (SPD_DUMP_HOME)
    4. cd blug35_unlock_kit && ./verify.sh       # integrity + offline self-test
    5. ./insure.sh                               # the insurance (read-only, hours)
    6. ./run.sh                                  # the guided unlock procedure
    7. ./root_with_magisk.sh                    # fetch Magisk + patch + write root (guide ch. 8)
       (offline/pinned: MAGISK_APK=/path/to.apk, or the manual chapter 8 way)
    8. ./make_report.sh  -> post your success report (be nice, help others)

    Later, if you want box state back:
        ./rollback_to_stock.sh                   # stock + relock + reset; optional userdata restore (or unroot-only)

Safety model
    - every flash-writing step prints the exact partitions it will touch
      BEFORE asking for a typed YES
    - every write is followed by a hash-verified read-back
    - the insurance gates everything: run.sh refuses to start without the
      verified restore path; rollback_to_stock.sh refuses without it too
    - step02 fingerprints YOUR firmware and hard-fails with no override
    - userdata.img is optional; if not captured, rollback cannot restore the
      prior user-data partition; if captured, its restore path is untested
    - Linux only (Windows intercepts the USB device — guide chapter 3 has
      the one-hour live-USB path)

Requirements
    Linux (or the live USB from chapter 3), python3, git + gcc/make +
    libusb-1.0 headers (prepare.sh fetches and builds spd_dump —
    pinned to the field-certified source revision d24c21a — from
    TomKing062/spreadtrum_flash when SPD_DUMP_HOME is unset; setup.sh
    checks that registration;
    export SPD_DUMP_HOME to use your own build). Budget ~120 GB for the
    full insurance partition set; storage and time may be lower if the
    optional userdata.img capture is omitted. Insurance is a one-time,
    multi-hour operation. Safety is above anything.
