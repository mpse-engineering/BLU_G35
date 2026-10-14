# BLU G35 (SC9863A) bootloader unlock — the guide

Audience: anyone. Every keystroke is written out. Nothing is assumed.
Total time: one focused hour for the unlock itself — plus a one-time
multi-hour insurance run (chapter 6), which is not optional.

> **Read this first — the four disclaimers.** Full text in `DISCLAIMERS.md`;
> the short form: (1) like any firmware tool, you can brick your phone —
> though everything demonstrated on this hardware was recoverable, and the
> risk concentrates in *deviating* from the procedure; (2) make sure your
> phone is the exact model; (3) this kit is the cleaned release of code that
> was proven end-to-end on a real BLU G35; (4) when it works for you, report
> back — that report is what gives the next person confidence.

---

## 0. Glossary — read this once

| word | meaning |
|---|---|
| **BootROM / BROM** | code burned into the chip at the factory. Cannot be changed by anything — any firmware, any OTA. Our entry point. It ignores the lock flag entirely; it is why this method always works. |
| **download mode** | a phone state where the BootROM listens over USB. Reached by: power off (~10 s hold), hold **VOL_UP**, plug the cable. Works no matter what software state the phone is in. |
| **fastboot** | the phone's own boot-menu flashing tool. On THIS phone its write command is broken (proven twice). This kit does not use it for writes — ever. |
| **partition** | a named slice of the phone's storage (splloader, uboot_a, miscdata, …). Think "files that live below the filesystem". |
| **slot a / slot b** | two copies of boot-critical partitions; the phone boots from the active one (yours: `a`). We patch both so it does not matter. |
| **hash / sha256** | a fingerprint of a file. If one byte changes, the fingerprint changes. We hash before and after every write. |
| **read-back** | after writing to the phone, we read the same region back and hash it. If it does not match what we sent, we stop. |
| **spd_dump** | the one tool this kit needs (prepare.sh fetches and builds it from TomKing062/spreadtrum_flash at a pinned, field-certified source revision when `SPD_DUMP_HOME` is unset; export `SPD_DUMP_HOME` to use your own build). It talks to the BootROM in download mode. |
| **insurance** | the kit's name for three complete firmware backups, verified against each other, plus one certified master copy. Your personal restore source and the USB health test. Chapter 6. |

---

## 1. What you need

- the phone: BLU G35 (Unisoc SC9863A), battery well above 40%, stock
- a USB **data** cable plugged directly into the computer (no hub) — and a
  spare if you have one; a bad cable is the single most common failure
- a computer running **Linux** (see chapter 3 if you only have Windows)
- ~120 GB free disk for the insurance backups (chapter 6 explains why)
- the kit, acquired from the release repository — git clone (next chapter)
  or the release's ZIP
- internet access ONCE, for the one-time spd_dump fetch+build — or a build
  you already trust, exported as `SPD_DUMP_HOME` (chapter 2, step 2)
- `git`, `gcc`, `make` and the libusb-1.0 headers (for that one build)

---

## 2. Workspace setup — keystroke by keystroke

Open a terminal and type exactly this, in order:

```bash
# 1) make the workspace and get the kit into it — ONE command. The clone
#    lands in a folder named blug35_unlock_kit, which every later step in
#    this guide counts on verbatim:
mkdir -p ~/BLU35_WORKSPACE
cd ~/BLU35_WORKSPACE
git clone https://github.com/mpse-engineering/BLU_G35.git blug35_unlock_kit
#    ZIP edition instead? unzip it, then rename the folder:
#    mv BLU_G35-* blug35_unlock_kit
#    (a tarball handed over directly by the maintainer? extract it the same
#    way — the folder name is what matters: tar xzf <kit>.tar.gz)

# 2) COMPILE + DEPENDENCY — prove every patch artifact derives from the real
#    firmware, and fetch/build spd_dump (one-time; needs git, gcc, make,
#    libusb-1.0 headers — the script prints the exact apt line if missing)
cd blug35_unlock_kit
./prepare.sh

# 3) SETUP — verify the dependency is registered for the whole workspace
cd ..
./blug35_unlock_kit/setup.sh

# 4) VERIFY — integrity + full offline self-test (no phone needed)
#    (we are back inside the kit directory from here on)
cd blug35_unlock_kit
./verify.sh

# 5) INSURE — three complete backups + verification (chapter 6)
./insure.sh

# 6) RUN — the guided unlock procedure
./run.sh
```

Notes on the dependency, once:

- the gates look for **`SPD_DUMP_HOME`** — a directory containing the built
  `spd_dump` binary.
- **Unset** (the normal case): `prepare.sh` clones the source into the
  workspace, checks out the **pinned certified commit**, builds it, records
  the path in `../.spd_dump_home`, and exports it for the rest of the run.
  What happens is exactly this, and you watch it happen:

  ```bash
  git clone https://github.com/TomKing062/spreadtrum_flash.git
  cd spreadtrum_flash
  git checkout d24c21a0c93a545c0130668caa1826d59ceebe48  # pinned: certified tree
  make
  ```

  The pin is deliberate: upstream `main` has moved past the revision this
  kit was field-proven with (newer main even needs `libxml2-dev` to build).
  The pinned source produces the binary whose session banner self-reports
  `sha1:d24c21a0c93a545c0130668caa1826d59ceebe48` — the gates verify that
  line before accepting the build.

- **Set** (you already have a build you trust):

  ```bash
  export SPD_DUMP_HOME=/path/to/spreadtrum_flash
  ```

  Your build is used untouched. An explicit export always wins over the
  recorded path.
- after step 2, every gate finds the path automatically — running gates in
  separate terminals needs no exporting at all.

**What you will see** at each gate:

- `prepare`: ends with `prepare: ALL PROOFS PASS` and the resolved
  `SPD_DUMP_HOME`. Anything else in the PROOFS = the kit was altered or
  corrupted → stop, re-extract.
- `setup`: ends with `setup: DEPENDENCY READY` and prints the binary path.
- `verify`: ends with `verify: ALL CHECKS PASS` after
  `offline self-test: 13/13 scenarios pass`.
- `insure`: ends with `insure: DEVICE INSURED` (takes hours; chapter 6).
  Its device-session output is shown live and logged to
  `logs/insure_session.log`.
- `run`: prints the disclaimers once, then the step plan, and asks
  `type RUN to execute it, S to stop` before **each** step.

**What you will NOT see** hidden from you: every device session streams its
output to the terminal. An unconnected phone looks like a sitting
`Waiting for dl_diag connection` line; a failure is printed, never buried.

**Network**: the ONLY touch is the one-time spd_dump fetch in step 2 — and
only when you did not export `SPD_DUMP_HOME` with your own build. Nothing
else downloads; nothing phones home.

---

## 3. Windows users: the one-hour Linux (live USB)

The kit runs on **Linux only** — not because of ideology, but because of
physics: Windows intercepts the phone's USB device before any tool can talk
to it (drivers, adb servers, timing), and every workaround built on Windows
inherits the problem. We tried. It is not certifiable, so it is not
supported. You do not need to install Linux to get it:

1. Download **Ubuntu Desktop** (ubuntu.com) and write it to an 8 GB+ USB
   stick — Windows users: use balenaEtcher, select the .iso, flash.
2. Reboot the PC and boot from the stick (tap F12/F2/Esc during power-on —
   the exact key shows on your screen; look for "boot menu").
3. Choose **Try Ubuntu** (not Install). You get a full Linux desktop,
   running from RAM, with native USB access and nothing installed that can
   intercept the phone. Your Windows disk is untouched.
4. You need internet ONCE in this session: with the kit in place (clone or
   ZIP above), `./prepare.sh` fetches and builds spd_dump from
   github.com/TomKing062/spreadtrum_flash (pinned to the certified source
   revision). (Or bring your own built copy on
   the second stick and `export SPD_DUMP_HOME=/path/to/spreadtrum_flash` —
   then no internet is needed at all.)
5. Follow chapter 2 from a terminal inside the live session. Note: the live
   desktop's disk is RAM — keep the workspace on the second stick or an
   internal drive you mounted, or everything is lost on reboot (the
   insurance backups must NOT live in RAM).

**On WSL specifically**: tried; Windows interception plus USB-over-IP
latency break the download-mode sessions mid-chain, which looks exactly like
"the tool doesn't work". Not supported — use the live USB, it is genuinely
easier.

---

## 4. Access to the USB device (Linux)

Try the simple thing first — the steps will tell you if it fails:

**Option A — run the steps with sudo** (simplest, used in the field):

```bash
sudo -E ./run.sh        # -E keeps your environment (SPD_DUMP_HOME)
```

**Option B — udev rule** (no sudo afterwards). Create the rule, reload,
re-plug the phone:

```bash
sudo tee /etc/udev/rules.d/51-sprd-dl.rules <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="1782", ATTRS{idProduct}=="4d00", MODE="0666"
EOF
sudo udevadm control --reload-rules
```

If a step waits forever: the phone is not in download mode (power off 10 s,
hold VOL_UP, plug), or an adb server is running (`adb kill-server` — it
steals the device).

---

## 5. The procedure, end to end

```
prepare → setup → verify → insure → run (steps 00..08) → root (chapter 8)
```

| gate | touches phone? | what it does |
|---|---|---|
| prepare | no | rebuild-proofs every patch artifact from the shipped firmware |
| setup | no | verifies the spd_dump dependency (SPD_DUMP_HOME) |
| verify | no | manifest + 28 artifact proofs + 13-scenario offline self-test |
| **insure** | **READ-ONLY** | **3 complete backups, 3-way verified, certified master (chapter 6)** |
| run step00–01 | no | environment preflight, package integrity |
| step02 | **NO — read-only** | fingerprints YOUR firmware against the kit; mismatch = hard fail, no override |
| step03 | no | RAM-boot proof of the patched SPL (nothing written); if it does not boot, up to TWO guided retries are offered |
| step04 | YES (splloader, uboot_a/b) | stage: erase splloader, patched LK into both slots (read-back-verified) |
| step05 | YES (uboot_a/b, miscdata) | **THE UNLOCK** — stage the cboot writer, then RAM-boot it; the phone goes **black** during the write; that black screen IS success-in-progress |
| step06 | **NO — read-only** | shows the lock block. Populated = **unlocked** |
| step07 | YES (splloader, uboot_a/b) | restores the official boot chain, hash-verified; the unlock flag survives |
| step08 | YES (misc) | stages the factory wipe — but first asks whether the on-screen reset already happened (if it did: no second wipe) |

**Kill-switch rule**: every writing step prints the exact partitions it
will touch BEFORE the typed YES. Read it. Anything unexpected → answer NO.

**Stop-and-paste rule**: any red `FAIL:` means stop. Do not improvise, do
not "just run the next one". The transcript is in `logs/<step>_<timestamp>.log`.

### What the phone shows along the way (expected, not bugs)

- USB sessions: the phone screen stays black; it sits in download mode.
- step03 and step05's fire: the phone **reboots**. step03 → normal boot.
  step05 fire → **black screen, stays dark** — the writer is running.
- step03 honesty: some devices boot **silently** (no logo, no vibration).
  The host-side proof of execution is the session's teardown signature in
  your terminal (`device removed` / `CHECK_BAUD FAIL`); the verdict is the
  screen — Android appearing within ~60 s. If it does NOT boot: one retry
  is routine ("may need twice", same as step05) and the phone is untouched
  either way. The step walks you through the power-cycle and download-mode
  re-entry, and offers up to two retries before it stops.
- after step07 + step08: first boot shows the **unlocked-bootloader
  warning**, then recovery asks for a **factory data reset** — accept it.
  Your data was encrypted under the locked state and is unreadable now;
  the wipe is expected, and the unlock flag survives it. step08 itself
  first asks whether that on-screen reset already happened after step07's
  boot — if you already accepted it, the wipe is done and step08 stages
  nothing (a staged wipe would only run a SECOND time).

---

## 6. Insurance — why you do not skip this

`./insure.sh` reads **every partition of your phone, three times** — into
`backup1/`, `backup2/`, `backup3/` in the workspace — with a normal boot
between sessions. Each backup is **one single download-mode session** (all
~69 partitions in a row; one-shot sessions have no command limit), so you
enter download mode three times total, not once per handful of partitions.
Then it verifies:

- **KEY partitions** (boot chain, modem/DSP firmware, factory NV, TrustOS):
  must be byte-identical across all three. Any difference = your USB path
  is unreliable → HALT, no override. Fix the hardware and re-run the failed
  session — the kit resumes, it does not restart.
- **VOLATILE partitions** (logs, counters, userdata, cache, runtime NV):
  legitimately change on boot. They are fully backed up, and excluded from
  the comparison — that is why everything is still backed up three times
  even though verification ignores some of it.
- **anything else**: you get a named warning and decide (typed YES).

On pass it assembles `$BLU35_WORKSPACE/firmware/` — the **certified master**:
your phone's own complete firmware, checksummed. This is the restore source
for every partition, including the per-device NV data no kit could ever
ship for you.

**The cost of safety, stated plainly:** this is the multi-hour, ~120 GB
part. That is not an accident or waste — it is the price of "you cannot
lose this phone". Safety is above anything. If you cannot afford the time
or the disk, you are not ready to perform surgery on the phone.

It is also the USB health test: three full reads move more data than the
entire unlock ever will. A bad cable dies here, read-only, where it costs
nothing. (The author's own cable failed this test. That is the point.)

**Sessions are resumable.** If a session dies mid-way (cable, port,
sleep), just re-run the same command: it reads only the partitions that
are missing or short of their exact GPT size — a truncated file never
counts as captured. A completed session re-run needs no phone at all.
`./insure.sh --fresh sessionN` throws away that backup's captures and
starts it over if you want zero doubt.

---

## 7. If anything fails — triage table

| what you saw | what it means | what to do |
|---|---|---|
| `find port failed` / waits forever | not in download mode, or adb grabbed the device, or no permission | re-enter download mode; `adb kill-server`; try `sudo -E` |
| `step02 ... does NOT match` | firmware revision differs from this kit | **stop.** No override exists. Do not improvise. |
| insurance HALT on KEY partitions | cable/port unreliable | fix the hardware, `./insure.sh session2` (etc.) — it resumes |
| a write step FAILs on a hash | the write did not land | stop; phone is fine — download mode and re-run that step |
| step03: "no boot" on the first attempt | a first no-boot is routine — the maintainer's "may need twice" applies to the RAM-boot too | answer y at the retry prompt (power-cycle, re-enter download mode); the step only hard-stops after 3 attempts, and its stop message names the exact log to paste |
| Magisk shows "N/A" after root | wrong image or wrong slot | re-do chapter 8 with the correct Magisk-patched image |
| a module bootloops the phone | bad module | hold **VOL-DOWN** through boot = Safe Mode (modules disabled), remove the module |
| anything else | — | stop, paste `logs/<step>_*.log` |

**Total-loss insurance:** everything the procedure modifies is restorable
from your certified master (`firmware/`), hash-verified, via download mode.
The BootROM itself cannot be damaged by software. There is no state this
procedure can put the phone in that download mode cannot reach.

---

## 8. Root with Magisk (gated, like everything else)

The unlock alone does not root the phone. The patched `init_boot` does —
and you build that image yourself, on the phone, so the kit never ships
boot images at all.

### The one-command way

With the phone booted normally, Developer options + USB debugging on, and
the adb authorization prompt accepted:

    ./root_with_magisk.sh

It does this whole chapter in order, printing every gate:

1. fetches the **latest Magisk APK** from the official GitHub releases and
   prints its sha256 (the only network touch; `MAGISK_APK=/path/to.apk
   ./root_with_magisk.sh` skips the fetch — pinned or fully offline)
2. installs it with adb
3. pushes the **stock** `init_boot` from your certified master to the
   phone — the Magisk app patches THAT, so double-patching cannot happen
4. walks you through the four taps (Magisk → Install → Select and Patch a
   File → `init_boot_stock.img` → LET'S GO) and waits for the result
5. pulls `magisk_patched-XXXXX.img` back and writes it with the gated
   writer — download mode, kill-switch prompt, hash-verified read-back

If the fetch cannot reach GitHub, the script prints the browser URL and
exits cleanly: download the APK by hand, then re-run with `MAGISK_APK=`.

### After an OTA removes root: one command

    ./root_with_magisk.sh --ota

An OTA boots a NEW stock init_boot — patching the kit's insurance-snapshot
copy would put old software on a new system. `--ota` does the whole
recovery in order, with every gate printed:

1. phone in download mode: a READ-ONLY session reads BOTH init_boot slots
   straight off the phone (logged to `logs/`)
2. guard: if a read image still carries the Magisk signature, root was not
   actually removed (the OTA did not replace init_boot) — it refuses and
   stores nothing
3. an unchanged slot is kept as-is; a changed, un-signed slot is stored
   beside the certified master (`firmware/init_boot_X.ota-stock.bin`) with
   a written record (`OTA-STOCK.txt`) and the master's CHECKSUMS refreshed.
   The canonical master files stay the pre-OTA insurance snapshot —
   `rollback_to_stock.sh` keeps its exact proven semantics (full box state
   = the insured firmware).
4. then it installs Magisk, patches THAT current-stock image in the Magisk
   app, and writes it through the gated writer — exactly like the normal
   mode, so the patched image matches the OTA'd system

Note: after an OTA, `step02` would refuse the phone by design (one kit =
one firmware revision, no override) — `--ota` is the sanctioned post-OTA
path, and a later `./insure.sh` re-run re-baselines the whole master to
the post-OTA phone.

### The manual way (same steps, by hand)

1. get the Magisk APK (github.com/topjohnwu/Magisk) and
   `adb install Magisk-vXX.X.apk` — phone booted, USB debugging on,
   authorization accepted
2. copy the stock `init_boot` from your certified master
   (`../firmware/init_boot_a.bin`) onto the phone
3. Open Magisk → *Install* → *Select and Patch a File* → pick it →
   it writes `magisk_patched-XXXXX.img` — copy that back to the computer
4. Write it with the gated writer — NOT fastboot (its write path is broken
   on this phone, proven twice):

```bash
IMG=magisk_patched-XXXXX.img ./write_init_boot.sh
```

   The script checks the image size, asks you to confirm, shows the
   kill-switch prompt, writes through the download agent, and reads the
   partition back — the hashes must match or it tells you not to boot.

5. Boot, open Magisk → expect **Installed**. Hard proof: `adb shell su -c id`.

**After a future OTA removes root** (see chapter 9): same chapter, same
tool — read the new stock image out, patch it in the Magisk app, write it
back with `write_init_boot.sh`. Root restored, data intact. (With the
helper: re-run `./root_with_magisk.sh` once the master holds the new stock
image.)

---

## 9. Living with an unlocked, rooted phone

- The boot warning at every power-on is the unlock flag doing its job.
- **OTAs.** Do not accept an OTA while `init_boot` is Magisk-patched
  without thinking. If one lands anyway and root disappears:
  `./root_with_magisk.sh --ota` (chapter 8) reads the NEW stock init_boot
  off the phone, guards it, and re-roots from the current stock — one
  command. The BootROM (and this kit) survive every OTA by design.
- **Safe Mode escape hatch:** VOL-DOWN held through boot disables all
  modules for that boot.
- **Magisk updates** are in-app (*Install → Direct Install → reboot*);
  no computer needed.
- Module users: **Zygisk** ON if you run LSPosed; keep **Enforce DenyList
  OFF** while LSPosed is active (it unmounts Magisk's modifications and
  breaks LSPosed hooks inside listed apps — hide from apps via LSPosed's
  own mechanism instead).

### Privacy: default-deny

The author's policy, offered as the recommended posture: **deny everything
by default; an app gets nothing unless you explicitly granted it.** Root +
Zygisk/LSPosed gives you the hooks to enforce it system-wide, including
controlling which apps can see which packages. The one honest limit: fully
de-Googling a device is achievable but fiddly — budget real time, and
remember that on THIS device a bad experiment costs one download-mode
recovery (~2 minutes), not the phone.

---

## 10. Unroot / return to box state

Changed your mind, or returning the device? `./rollback_to_stock.sh`
(requires the insurance stamp — the certified master is what makes this
safe and per-device):

- **Full box state**: pushes your complete stock firmware back
  (hash-verified per partition — this unroots by overwriting the Magisk
  init_boot), then **relocks** the bootloader (a surgical 64-byte flag
  write, with a snapshot kept as instant undo), then the factory reset
  happens last. Final read-only confirmation: stock chain, locked, wiped.
- **Unroot only**: stock init_boot back, root gone, bootloader stays
  unlocked, data untouched.

There is no race and no one-way door: the BootROM ignores the lock flag
(it always has — that is the method), so the cycle unlock ↔ relock works
indefinitely, in both directions. No fuse exists in this method.

A note on the NV/calibration partitions (source-proven, field decisions
9+10, see PUBLIC_KIT_NOTES.md in the DevKit): the rollback push
deliberately never WRITES and never VERIFIES `l_fixnv1/2_a/b` (radio
calibration), `l_runtimenv1/2` (runtime NV), `calinv`, `persist`,
`metadata`, `uboot_log`, `sysdumpdb` or `blackbox`. Calibration is
per-device and untouched by rooting; device state and logs legitimately
differ from any earlier capture — comparing them only produces false
alarms (proven in the field: the first rollback run halted on exactly
such a comparison). The tool itself also refuses or mangles writes to
these (it would ERASE the runtime NV instead of writing it, and it
cannot read the fixnv main copies back — it silently returns the
mirror instead).

---

## 11. Be nice, and report back

When it works: `./make_report.sh` assembles your proof transcript
(model, build, kernel, root, Magisk), you attach one photo of the boot
screen showing the unlocked warning, and post it with the kit hash and
your firmware revision (the filled `SUCCESS_REPORT.md` template tells you
exactly what goes where — and what NOT to post: never your
`get_identifier_token` output, it is serial-derived).

That report is the same thing you searched for before starting. For the
next person at 1 AM with a TracFone and no unlock path, it is the reason
they try at all. Answer newcomers when you can. You were one once.

---

## 12. What this kit will not do

- no SIM/carrier changes, no modem work, no IMEI anything
- no firmware revisions other than the one step02 fingerprints — hard fail, no override
- no writes over fastboot, ever
- nothing downloads except the one-time spd_dump fetch (chapter 2) — and
  only when you do not supply `SPD_DUMP_HOME` yourself — plus the Magisk
  APK fetch in `./root_with_magisk.sh` (skipped with `MAGISK_APK=`);
  nothing phones home
- no Windows support (chapter 3 explains why, and what to do instead)

## 13. Provenance

- Method: CVE-2022-38694 (SPRD BootROM download-mode session, publicly documented)
- Patch artifacts: derived and byte-verified against the phone's own dumps
  by `./prepare.sh` on every fresh copy — the "compile" step IS the proof
- SPL patch: byte-identical to the canonical maintainer tool's output on
  this dump (20 NOPs, 5 sites, signature block kept)
- Unlock writer: the canonical `fdl2-cboot` — the download agent plus
  exactly the unlock-write words (re-proved on every prepare/verify run)
- Full engineering history: see the DevKit edition
