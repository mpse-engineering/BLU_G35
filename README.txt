BLU G35 (SC9863A) bootloader unlock kit
========================================

Read 00_GUIDE.md first. Really. Then DISCLAIMER.md.

What this is
    A self-contained kit that unlocks the bootloader of the BLU G35
    (Unisoc SC9863A) using the publicly documented CVE-2022-38694 BootROM
    method, leaves the boot chain stock, and verifies every write. It also
    insures the phone first (three complete verified backups — your
    personal restore source and the USB health test), roots it via a gated
    Magisk init_boot writer, and can return it to full box state.

How to use it (the short version — the guide has every keystroke)

    1. get the kit into a fresh workspace folder (~120 GB free):
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
        ./rollback_to_stock.sh                   # stock + relock + wipe (or unroot-only)

Safety model
    - every flash-writing step prints the exact partitions it will touch
      BEFORE asking for a typed YES
    - every write is followed by a hash-verified read-back
    - the insurance gates everything: run.sh refuses to start without the
      verified restore path; rollback_to_stock.sh refuses without it too
    - step02 fingerprints YOUR firmware and hard-fails with no override
    - Linux only (Windows intercepts the USB device — guide chapter 3 has
      the one-hour live-USB path)

Requirements
    Linux (or the live USB from chapter 3), python3, git + gcc/make +
    libusb-1.0 headers (prepare.sh/setup.sh fetch and build spd_dump —
    pinned to the field-certified source revision d24c21a — from
    TomKing062/spreadtrum_flash when SPD_DUMP_HOME is unset;
    export SPD_DUMP_HOME to use your own build), ~120 GB disk for the
    insurance. The cost of safety, stated plainly: the insurance is a
    one-time multi-hour operation. Safety is above anything.
